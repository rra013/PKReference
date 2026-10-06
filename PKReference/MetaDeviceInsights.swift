//
//  MetaDeviceInsights.swift
//  PKReference
//
//  The Meta tab's insights worked out on the device, from Team Search's
//  corpus, for when the PK Reference server is off or can't be reached
//  (BackendIntegration-PHASE4.md §6). It answers in the server's shapes
//  (MetaAPI), so the screens don't care where the numbers came from.
//
//  It counts as the backend's MetaService does, line for line where it can:
//  usage, trends, sets and their parts, teammates, cores and archetypes come
//  out the same, which MetaDeviceInsightsTests checks against the backend's
//  golden/meta-fixture.json. Two numbers differ, because the corpus has
//  placings but not the events' phases or pairings:
//
//  - the top-cut fields hold the top-8 rate: teams placed 1st to 8th;
//  - `record` is the team record: the wins, losses and ties of teams with
//    the Pokémon, from their standings, mirror matches included.
//
//  Archetypes have no matchups, and events no top-cut size.
//
//  Items, abilities, natures and moves are standardized by MetaNames, a port
//  of the server's NameStandardizer.
//

import Foundation

nonisolated struct MetaDeviceInsights: Sendable {
    /// Trend: the last 14 days against the 14 before.
    static let trendPeriod: TimeInterval = 14 * 86_400
    /// Fewer teams than this in either period, and there's no trend.
    static let trendMinTeams = 50
    static let topValues = 12
    static let topSets = 10
    /// Fewer matches than this, and there's no win rate.
    static let minMatches = 30
    static let topCores = 20
    /// A core or archetype needs at least this many teams, and at least
    /// `archetypeShare` of them.
    static let minCoreTeams = 4
    static let archetypeShare = 0.02
    static let exampleTeams = 5
    /// Placed this high or better counts toward the top-8 rate.
    static let topPlacing = 8
    /// Standings fetched this long after an event's start are final, as in
    /// `TeamCorpusConfiguration`.
    static let settleAfter: TimeInterval = 48 * 60 * 60

    /// One published team.
    struct Team: Sendable {
        /// "event/player", as `CorpusTeam.id`.
        let id: String
        let date: Date
        let keys: Set<String>
        /// The members with their species keys, in the team's order.
        let members: [(key: String, member: LimitlessStanding.TeamMember)]
        let standing: LimitlessStanding
        let tournament: LimitlessTournament
    }

    let format: String
    let now: Date
    let teams: [Team]
    let events: [CorpusEvent]
    private let vocabulary: TeamSearchVocabulary
    private let names: MetaNames

    init(corpus: TeamCorpus, vocabulary: TeamSearchVocabulary, names: MetaNames, now: Date = Date()) {
        format = corpus.format
        self.now = now
        self.vocabulary = vocabulary
        events = corpus.events
        teams = corpus.teams.compactMap { team in
            guard let date = team.tournament.parsedDate else { return nil }
            let members = team.members.map {
                (key: vocabulary.identity(name: $0.name, slug: $0.limitlessID).key, member: $0)
            }
            return Team(id: team.id, date: date, keys: Set(members.map(\.key)), members: members,
                        standing: team.standing, tournament: team.tournament)
        }
        self.names = names
    }

    // MARK: Pokémon

    func pokemon(window: MetaAPI.Window) -> MetaAPI.PokemonList {
        let from = self.from(window)
        let inWindow = self.teams(from: from)
        let byKey = Self.teamsByKey(inWindow)
        let top = Set(inWindow.filter(Self.isTop).map(\.id))
        let trends = self.trends()
        let pokemon = byKey.map { key, withIt in
            usage(key: key, withIt: withIt, teams: inWindow.count, top: top, trend: trends[key])
        }
        .sorted { $0.teams != $1.teams ? $0.teams > $1.teams : $0.key < $1.key }
        return MetaAPI.PokemonList(format: format, window: window.rawValue, from: from, to: now, generatedAt: now,
                                   sample: sample(inWindow, top: top), pokemon: pokemon)
    }

    /// One Pokémon's page; nil when no team in the window has it.
    func pokemon(key: String, window: MetaAPI.Window) -> MetaAPI.PokemonDetail? {
        let inWindow = teams(from: from(window))
        let byKey = Self.teamsByKey(inWindow)
        guard let withIt = byKey[key] else { return nil }
        let top = Set(inWindow.filter(Self.isTop).map(\.id))
        let usage = usage(key: key, withIt: withIt, teams: inWindow.count, top: top, trend: trends()[key])

        let members = inWindow.flatMap { team in team.members.filter { $0.key == key }.map(\.member) }
        let n = members.count
        // Each member's moves, once each.
        let movesByMember = members.map { Set(($0.attacks ?? []).compactMap(names.move)) }

        var teammates: [String: Int] = [:]
        for team in withIt {
            for other in team.keys where other != key { teammates[other, default: 0] += 1 }
        }

        var sets: [SetKey: Int] = [:]
        for (member, moves) in zip(members, movesByMember) {
            let key = SetKey(item: names.item(member.item) ?? "", ability: names.ability(member.ability) ?? "",
                             nature: names.nature(member.nature) ?? "", moves: moves.sorted())
            sets[key, default: 0] += 1
        }
        let topSets = sets.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.javaString < $1.key.javaString }
            .prefix(Self.topSets)
            .map { MetaAPI.PokemonSet(item: Self.blankToNil($0.key.item), ability: Self.blankToNil($0.key.ability),
                                      nature: Self.blankToNil($0.key.nature), moves: $0.key.moves,
                                      count: $0.value, share: Self.ratio($0.value, n)) }

        var moveCounts: [String: Int] = [:]
        for moves in movesByMember { for move in moves { moveCounts[move, default: 0] += 1 } }

        let speciesID = vocabulary.species(forKey: key)?.speciesID
        return MetaAPI.PokemonDetail(
            format: format, key: key, window: window.rawValue, generatedAt: now, sample: sample(inWindow, top: top),
            usage: usage,
            items: Self.shares(members.map { names.item($0.item) }, total: n),
            abilities: Self.shares(members.map { names.ability($0.ability) }, total: n),
            natures: Self.shares(members.map { names.nature($0.nature) }, total: n),
            moves: Self.top(moveCounts, total: n),
            megaStones: Self.shares(members.map { member in
                speciesID.flatMap { vocabulary.mega(heldItem: member.item, speciesID: $0)?.stoneID }
            }, total: n),
            teammates: Self.top(teammates, total: withIt.count),
            sets: Array(topSets),
            weekly: weekly(inWindow, withIt: Set(withIt.map(\.id))))
    }

    // MARK: Cores and archetypes

    /// The pairs and trios most often on teams together, with how much more
    /// often than chance.
    func cores(window: MetaAPI.Window) -> MetaAPI.Cores {
        let inWindow = teams(from: from(window))
        let top = Set(inWindow.filter(Self.isTop).map(\.id))
        return MetaAPI.Cores(format: format, window: window.rawValue, generatedAt: now,
                             sample: sample(inWindow, top: top),
                             pairs: Self.topCores(inWindow, size: 2), trios: Self.topCores(inWindow, size: 3))
    }

    /// Teams built around a core of four, as the server finds them; without
    /// matchups, which need pairings.
    func archetypes(window: MetaAPI.Window) -> MetaAPI.Archetypes {
        let g = grouping(window)
        let n = g.teams.count
        let byKey = Self.teamsByKey(g.teams)
        let byID = Dictionary(uniqueKeysWithValues: g.teams.map { ($0.id, $0) })
        var archetypes: [MetaAPI.Archetype] = []
        for core in g.cores {
            let id = core.joined(separator: "+")
            guard let inIt = g.members[id], !inIt.isEmpty else { continue }
            let byUsage = core.sorted {
                let a = byKey[$0]?.count ?? 0, b = byKey[$1]?.count ?? 0
                return a != b ? a > b : $0 < $1
            }
            let inTop = inIt.filter(g.top.contains).count
            archetypes.append(MetaAPI.Archetype(
                id: id, name: "", core: byUsage, teams: inIt.count, usage: Self.ratio(inIt.count, n),
                topCutTeams: inTop, topCutUsage: g.top.isEmpty ? nil : Self.ratio(inTop, g.top.count),
                record: Self.teamRecord(inIt.compactMap { byID[$0] }), matchups: []))
        }
        archetypes.sort { $0.teams != $1.teams ? $0.teams > $1.teams : $0.id < $1.id }
        return MetaAPI.Archetypes(format: format, window: window.rawValue, generatedAt: now,
                                  sample: sample(g.teams, top: g.top), other: n - g.archetypeOf.count,
                                  archetypes: Self.named(archetypes))
    }

    /// One archetype, with its best-placed teams; nil for an id not in the
    /// window.
    func archetype(id: String, window: MetaAPI.Window) -> MetaAPI.ArchetypeDetail? {
        let all = archetypes(window: window)
        guard let archetype = all.archetypes.first(where: { $0.id == id }) else { return nil }
        let inIt = grouping(window).members[id] ?? []
        let best = teams(from: from(window))
            .filter { $0.standing.placing != nil && inIt.contains($0.id) }
            .sorted { a, b in
                if a.standing.placing! != b.standing.placing! { return a.standing.placing! < b.standing.placing! }
                if a.tournament.players != b.tournament.players { return a.tournament.players > b.tournament.players }
                if a.date != b.date { return a.date > b.date }
                return a.id < b.id
            }
            .prefix(Self.exampleTeams)
        let examples = best.map { team in
            let record = team.standing.record
            return MetaAPI.ExampleTeam(
                eventId: team.tournament.id, eventName: team.tournament.name, eventDate: team.date,
                players: team.tournament.players, player: team.standing.name, placing: team.standing.placing,
                wins: record?.wins ?? 0, losses: record?.losses ?? 0, ties: record?.ties ?? 0,
                members: team.members.map { key, member in
                    MetaAPI.ExampleMember(key: key, name: member.name, item: names.item(member.item),
                                          ability: names.ability(member.ability), nature: names.nature(member.nature),
                                          moves: (member.attacks ?? []).compactMap(names.move))
                })
        }
        return MetaAPI.ArchetypeDetail(format: format, window: window.rawValue, generatedAt: now, sample: all.sample,
                                       archetype: archetype, examples: Array(examples))
    }

    // MARK: Events

    /// The corpus's newest events, with their winners. The corpus doesn't
    /// know their top cuts.
    func events(limit: Int = 10) -> MetaAPI.Events {
        let newest = events.sorted {
            let a = $0.tournament.parsedDate ?? .distantPast, b = $1.tournament.parsedDate ?? .distantPast
            return a != b ? a > b : $0.tournament.id < $1.tournament.id
        }
        .prefix(limit)
        return MetaAPI.Events(format: format, generatedAt: now, events: newest.map { event in
            let date = event.tournament.parsedDate
            let winner = event.standings.first { $0.placing == 1 }.map { first in
                MetaAPI.EventWinner(player: first.name, wins: first.record?.wins ?? 0,
                                    losses: first.record?.losses ?? 0, ties: first.record?.ties ?? 0,
                                    team: (first.decklist ?? []).map {
                                        vocabulary.identity(name: $0.name, slug: $0.limitlessID).key
                                    })
            }
            return MetaAPI.EventSummary(
                id: event.tournament.id, name: event.tournament.name, date: date, players: event.tournament.players,
                standingsFinal: date.map { event.fetchedAt.timeIntervalSince($0) >= Self.settleAfter } ?? false,
                topCutPlayers: nil, winner: winner)
        })
    }

    // MARK: Workings

    private func from(_ window: MetaAPI.Window) -> Date? {
        switch window {
        case .days14: now.addingTimeInterval(-14 * 86_400)
        case .days30: now.addingTimeInterval(-30 * 86_400)
        case .regulation: nil
        }
    }

    /// Teams at events in [from, now).
    private func teams(from: Date?) -> [Team] {
        teams.filter { team in team.date < now && (from.map { team.date >= $0 } ?? true) }
    }

    private static func teamsByKey(_ teams: [Team]) -> [String: [Team]] {
        var out: [String: [Team]] = [:]
        for team in teams { for key in team.keys { out[key, default: []].append(team) } }
        return out
    }

    private static func isTop(_ team: Team) -> Bool {
        team.standing.placing.map { $0 <= topPlacing } ?? false
    }

    private func sample(_ teams: [Team], top: Set<String>) -> MetaAPI.Sample {
        MetaAPI.Sample(events: Set(teams.map(\.tournament.id)).count, teams: teams.count, topCutTeams: top.count)
    }

    private func usage(key: String, withIt: [Team], teams: Int, top: Set<String>, trend: Double?) -> MetaAPI.PokemonUsage {
        let inTop = withIt.filter { top.contains($0.id) }.count
        return MetaAPI.PokemonUsage(key: key, teams: withIt.count, usage: Self.ratio(withIt.count, teams),
                                    topCutTeams: inTop, topCutUsage: top.isEmpty ? nil : Self.ratio(inTop, top.count),
                                    trend: trend, record: Self.teamRecord(withIt))
    }

    /// Usage in the last 14 days less the 14 before, for each key; empty
    /// when either period has under 50 teams.
    func trends() -> [String: Double] {
        let split = now.addingTimeInterval(-Self.trendPeriod)
        let all = teams(from: split.addingTimeInterval(-Self.trendPeriod))
        let recent = all.filter { $0.date >= split }
        let before = all.filter { $0.date < split }
        guard recent.count >= Self.trendMinTeams, before.count >= Self.trendMinTeams else { return [:] }
        let recentByKey = Self.teamsByKey(recent), beforeByKey = Self.teamsByKey(before)
        var trends: [String: Double] = [:]
        for key in Set(recentByKey.keys).union(beforeByKey.keys) {
            let now = Self.ratio(recentByKey[key]?.count ?? 0, recent.count)
            let then = Self.ratio(beforeByKey[key]?.count ?? 0, before.count)
            trends[key] = Self.round(now - then)
        }
        return trends
    }

    /// The summed standings records of these teams, with a win rate (a tie
    /// is half a win) and its 95% Wilson range, both nil under 30 matches.
    static func teamRecord(_ teams: [Team]) -> MetaAPI.WinRecord {
        var w = 0, l = 0, t = 0
        for team in teams {
            guard let record = team.standing.record else { continue }
            w += record.wins
            l += record.losses
            t += record.ties
        }
        return winRecord(wins: w, losses: l, ties: t)
    }

    static func winRecord(wins: Int, losses: Int, ties: Int) -> MetaAPI.WinRecord {
        let n = wins + losses + ties
        guard n >= minMatches else {
            return MetaAPI.WinRecord(wins: wins, losses: losses, ties: ties, matches: n, winRate: nil,
                                     winRateLow: nil, winRateHigh: nil)
        }
        let nd = Double(n)
        let p = (Double(wins) + Double(ties) / 2) / nd
        let z = 1.96
        let denominator = 1 + z * z / nd
        let centre = (p + z * z / (2 * nd)) / denominator
        let half = z * (p * (1 - p) / nd + z * z / (4 * nd * nd)).squareRoot() / denominator
        return MetaAPI.WinRecord(wins: wins, losses: losses, ties: ties, matches: n, winRate: round(p),
                                 winRateLow: round(centre - half), winRateHigh: round(centre + half))
    }

    private func weekly(_ teams: [Team], withIt: Set<String>) -> [MetaAPI.WeekUsage] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var weeks: [Date: (teams: Int, with: Int)] = [:]
        for team in teams {
            let monday = calendar.dateInterval(of: .weekOfYear, for: team.date)!.start
            weeks[monday, default: (0, 0)].teams += 1
            if withIt.contains(team.id) { weeks[monday, default: (0, 0)].with += 1 }
        }
        let format = Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC")!).year().month().day()
        return weeks.sorted { $0.key < $1.key }.map {
            MetaAPI.WeekUsage(week: $0.key.formatted(format), teams: $0.value.teams, withPokemon: $0.value.with,
                              usage: Self.ratio($0.value.with, $0.value.teams))
        }
    }

    private static func topCores(_ teams: [Team], size: Int) -> [MetaAPI.Core] {
        var counts: [[String]: Int] = [:]
        for team in teams { for combo in combinations(team.keys, size) { counts[combo, default: 0] += 1 } }
        let byKey = teamsByKey(teams)
        let n = Double(teams.count)
        return counts.filter { $0.value >= minCoreTeams }
            .sorted { $0.value != $1.value ? $0.value > $1.value
                : $0.key.joined(separator: "+") < $1.key.joined(separator: "+") }
            .prefix(topCores)
            .map { members, count in
                let share = Double(count) / n
                let chance = members.reduce(1.0) { $0 * Double(byKey[$1]?.count ?? 0) / n }
                return MetaAPI.Core(members: members, teams: count, share: round(share), lift: round(share / chance))
            }
    }

    /// Teams grouped into archetypes, as the server's MetaService groups them.
    private struct Grouping {
        let teams: [Team]
        let top: Set<String>
        let cores: [[String]]
        let archetypeOf: [String: String]
        let members: [String: Set<String>]
    }

    private func grouping(_ window: MetaAPI.Window) -> Grouping {
        let inWindow = teams(from: from(window))
        let n = inWindow.count
        let minTeams = max(Self.minCoreTeams, Int((Self.archetypeShare * Double(n)).rounded(.up)))
        var quads: [[String]: Int] = [:]
        for team in inWindow { for combo in Self.combinations(team.keys, 4) { quads[combo, default: 0] += 1 } }
        var cores: [[String]] = []
        for (quad, _) in quads.filter({ $0.value >= minTeams }).sorted(by: {
            $0.value != $1.value ? $0.value > $1.value : $0.key.joined(separator: "+") < $1.key.joined(separator: "+")
        }) where cores.allSatisfy({ core in core.filter(quad.contains).count <= 2 }) {
            cores.append(quad)
        }
        var archetypeOf: [String: String] = [:]
        var members: [String: Set<String>] = [:]
        for team in inWindow {
            guard let core = cores.first(where: { Set($0).isSubset(of: team.keys) }) else { continue }
            let id = core.joined(separator: "+")
            archetypeOf[team.id] = id
            members[id, default: []].insert(team.id)
        }
        return Grouping(teams: inWindow, top: Set(inWindow.filter(Self.isTop).map(\.id)), cores: cores,
                        archetypeOf: archetypeOf, members: members)
    }

    /// Names in order (most teams first): the two most-used members, or as
    /// many more as it takes to differ from every name before it.
    static func named(_ archetypes: [MetaAPI.Archetype]) -> [MetaAPI.Archetype] {
        var used = Set<String>()
        return archetypes.map { a in
            var size = min(2, a.core.count)
            var name = a.core.prefix(size).joined(separator: "+")
            while used.contains(name) && size < a.core.count {
                size += 1
                name = a.core.prefix(size).joined(separator: "+")
            }
            used.insert(name)
            return MetaAPI.Archetype(id: a.id, name: name, core: a.core, teams: a.teams, usage: a.usage,
                                     topCutTeams: a.topCutTeams, topCutUsage: a.topCutUsage, record: a.record,
                                     matchups: a.matchups)
        }
    }

    /// Every sorted combination of `size` keys.
    static func combinations(_ keys: Set<String>, _ size: Int) -> [[String]] {
        let sorted = keys.sorted()
        var out: [[String]] = []
        var current: [String] = []
        func combine(_ start: Int) {
            if current.count == size { out.append(current); return }
            guard start < sorted.count else { return }
            for i in start..<sorted.count {
                current.append(sorted[i])
                combine(i + 1)
                current.removeLast()
            }
        }
        combine(0)
        return out
    }

    private static func shares(_ values: [String?], total: Int) -> [MetaAPI.Share] {
        var counts: [String: Int] = [:]
        for case let value? in values where !value.isEmpty { counts[value, default: 0] += 1 }
        return top(counts, total: total)
    }

    private static func top(_ counts: [String: Int], total: Int) -> [MetaAPI.Share] {
        counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(topValues)
            .map { MetaAPI.Share(value: $0.key, count: $0.value, share: ratio($0.value, total)) }
    }

    private static func blankToNil(_ text: String) -> String? { text.isEmpty ? nil : text }

    static func ratio(_ part: Int, _ whole: Int) -> Double {
        whole == 0 ? 0 : round(Double(part) / Double(whole))
    }

    /// To 4 places, halves up, as the server's Math.round does.
    static func round(_ x: Double) -> Double {
        (x * 10_000 + 0.5).rounded(.down) / 10_000
    }

    /// A whole set, counted as one.
    private struct SetKey: Hashable {
        let item: String
        let ability: String
        let nature: String
        let moves: [String]

        /// How the server breaks ties between sets: Java's List.toString.
        var javaString: String {
            "[\(item), \(ability), \(nature), [\(moves.joined(separator: ", "))]]"
        }
    }
}
