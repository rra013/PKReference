//
//  MetaDeviceInsightsTests.swift
//  PKReferenceTests
//
//  The Meta tab's insights worked out on the device must match the server's
//  for the same teams. The backend's MetaGoldenFileTest records what its
//  MetaService works out from its fixture event into
//  backend/src/test/resources/golden/meta-fixture.json; this suite works the
//  same numbers out from the same event's standings and checks them against
//  that file. The device-only numbers (the top-8 rate, team records) are
//  checked by hand.
//

import Testing
import Foundation
@testable import PKReference

private let backend = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "backend/src/test/resources")

/// The golden file's shapes.
private struct Golden: Decodable {
    let event: Scenario
    let trends: [String: Double?]

    struct Scenario: Decodable {
        let sample: Sample
        let pokemon: [Usage]
        let pages: [String: Page]
        let pairs: [Core]
        let trios: [Core]
        let other: Int
        let archetypes: [Archetype]
    }

    struct Sample: Decodable { let events: Int; let teams: Int }
    struct Usage: Decodable, Equatable { let key: String; let teams: Int; let usage: Double }
    struct Share: Decodable, Equatable { let value: String; let count: Int; let share: Double }
    struct PokemonSet: Decodable, Equatable {
        let item: String?; let ability: String?; let nature: String?; let moves: [String]; let count: Int; let share: Double
    }
    struct Page: Decodable {
        let items: [Share]; let abilities: [Share]; let natures: [Share]; let moves: [Share]
        let megaStones: [Share]; let teammates: [Share]; let sets: [PokemonSet]
    }
    struct Core: Decodable, Equatable { let members: [String]; let teams: Int; let share: Double; let lift: Double }
    struct Archetype: Decodable, Equatable {
        let id: String; let name: String; let core: [String]; let teams: Int; let usage: Double
    }
}

/// The backend's fixture event (M-C, 83 players), with its players' names
/// replaced, as Limitless's API sent it.
private func fixtureStandings() throws -> [LimitlessStanding] {
    try JSONDecoder().decode([LimitlessStanding].self,
                             from: Data(contentsOf: backend.appending(path: "limitless/event-83/standings.json")))
}

private let now = Date(timeIntervalSince1970: 1_791_288_000)   // 2026-10-06T12:00:00Z, as the backend's tests

private func event(_ id: String, date: String, standings: [LimitlessStanding]) -> CorpusEvent {
    CorpusEvent(tournament: LimitlessTournament(id: id, name: "Test Event", game: "VGC", format: "M-C", date: date,
                                                players: 83),
                standings: standings, fetchedAt: now)
}

private func insights(_ events: [CorpusEvent]) throws -> MetaDeviceInsights {
    MetaDeviceInsights(corpus: TeamCorpus(format: "M-C", events: events, listFetchedAt: now, missingEvents: []),
                       vocabulary: try TeamSearchVocabulary.bundled(for: .mC),
                       names: try MetaNames.bundled(for: .mC), now: now)
}

@MainActor
struct MetaDeviceInsightsTests {
    @Test func theClock() {
        #expect(now == ISO8601DateFormatter().date(from: "2026-10-06T12:00:00Z"))
    }

    /// Usage, Pokémon pages, cores and archetypes match the server's.
    @Test func matchesTheServer() throws {
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: backend
            .appending(path: "golden/meta-fixture.json"))).event
        let device = try insights([event("event-83", date: "2026-10-05T18:00:00.000Z", standings: fixtureStandings())])

        let list = device.pokemon(window: .days30)
        #expect(list.sample.events == golden.sample.events)
        #expect(list.sample.teams == golden.sample.teams)
        #expect(list.pokemon.map { Golden.Usage(key: $0.key, teams: $0.teams, usage: $0.usage) } == golden.pokemon)

        #expect(golden.pages.count == 12)
        for (key, page) in golden.pages {
            let detail = try #require(device.pokemon(key: key, window: .days30), "\(key)")
            func shares(_ shares: [MetaAPI.Share]) -> [Golden.Share] {
                shares.map { Golden.Share(value: $0.value, count: $0.count, share: $0.share) }
            }
            #expect(shares(detail.items) == page.items, "\(key) items")
            #expect(shares(detail.abilities) == page.abilities, "\(key) abilities")
            #expect(shares(detail.natures) == page.natures, "\(key) natures")
            #expect(shares(detail.moves) == page.moves, "\(key) moves")
            #expect(shares(detail.megaStones) == page.megaStones, "\(key) Mega Stones")
            #expect(shares(detail.teammates) == page.teammates, "\(key) teammates")
            #expect(detail.sets.map {
                Golden.PokemonSet(item: $0.item, ability: $0.ability, nature: $0.nature, moves: $0.moves,
                                  count: $0.count, share: $0.share)
            } == page.sets, "\(key) sets")
        }
        #expect(device.pokemon(key: "missingno", window: .days30) == nil)

        let deviceCores = device.cores(window: .days30)
        func cores(_ cores: [MetaAPI.Core]) -> [Golden.Core] {
            cores.map { Golden.Core(members: $0.members, teams: $0.teams, share: $0.share, lift: $0.lift) }
        }
        #expect(cores(deviceCores.pairs) == golden.pairs)
        #expect(cores(deviceCores.trios) == golden.trios)

        let archetypes = device.archetypes(window: .days30)
        #expect(archetypes.other == golden.other)
        #expect(archetypes.archetypes.map {
            Golden.Archetype(id: $0.id, name: $0.name, core: $0.core, teams: $0.teams, usage: $0.usage)
        } == golden.archetypes)
    }

    /// The last 14 days (the event) against the 14 before (a copy of its
    /// first 60 teams, three weeks earlier).
    @Test func trendsMatchTheServer() throws {
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: backend
            .appending(path: "golden/meta-fixture.json"))).trends
        let standings = try fixtureStandings()
        let device = try insights([
            event("event-83", date: "2026-10-05T18:00:00.000Z", standings: standings),
            // The first 60 entries as Limitless lists them, as the backend's test takes them.
            event("three-weeks-ago", date: "2026-09-15T18:00:00.000Z", standings: Array(standings.prefix(60))),
        ])
        let trends = device.trends()
        #expect(!golden.isEmpty)
        for (key, trend) in golden {
            #expect(trends[key] == trend, "\(key)")
        }
        #expect(device.pokemon(window: .days30).pokemon.first { $0.key == "rillaboom" }?.trend == -0.0199)

        // Under 50 teams in either fortnight, no trends.
        let thin = try insights([
            event("event-83", date: "2026-10-05T18:00:00.000Z", standings: standings),
            event("three-weeks-ago", date: "2026-09-15T18:00:00.000Z", standings: Array(standings.prefix(40))),
        ])
        #expect(thin.trends().isEmpty)
    }

    /// What only the device works out: the top-8 rate and team records, in
    /// place of the server's top cut and win records.
    @Test func topEightAndTeamRecords() throws {
        let standings = try fixtureStandings()
        let device = try insights([event("event-83", date: "2026-10-05T18:00:00.000Z", standings: standings)])
        let list = device.pokemon(window: .days30)

        let withTeams = standings.filter { !($0.decklist ?? []).isEmpty }
        let top8 = withTeams.filter { ($0.placing ?? .max) <= 8 }
        #expect(list.sample.topCutTeams == top8.count)

        let vocabulary = try TeamSearchVocabulary.bundled(for: .mC)
        func has(_ standing: LimitlessStanding, _ key: String) -> Bool {
            (standing.decklist ?? []).contains { vocabulary.identity(name: $0.name, slug: $0.limitlessID).key == key }
        }
        let rillaboom = try #require(list.pokemon.first { $0.key == "rillaboom" })
        let topWith = top8.filter { has($0, "rillaboom") }.count
        #expect(rillaboom.topCutTeams == topWith)
        #expect(rillaboom.topCutUsage == MetaDeviceInsights.ratio(topWith, top8.count))

        let records = withTeams.filter { has($0, "rillaboom") }.compactMap(\.record)
        let record = try #require(rillaboom.record)
        #expect(record.wins == records.map(\.wins).reduce(0, +))
        #expect(record.losses == records.map(\.losses).reduce(0, +))
        #expect(record.matches == record.wins + record.losses + record.ties)
        #expect(record.winRate != nil && record.winRateLow! < record.winRate! && record.winRate! < record.winRateHigh!)

        // The Wilson range, as the server works it out (MetaServiceTest's
        // Rillaboom: 46-51 gives 0.4742, 0.3777 to 0.5727).
        #expect(MetaDeviceInsights.winRecord(wins: 46, losses: 51, ties: 0)
                == MetaAPI.WinRecord(wins: 46, losses: 51, ties: 0, matches: 97, winRate: 0.4742,
                                     winRateLow: 0.3777, winRateHigh: 0.5727))
        #expect(MetaDeviceInsights.winRecord(wins: 10, losses: 19, ties: 0).winRate == nil)
    }

    /// An archetype's page and the newest events, as the server gives them
    /// (MetaServiceTest's numbers), without what needs pairings.
    @Test func archetypePageAndEvents() throws {
        let standings = try fixtureStandings()
        let device = try insights([
            event("event-83", date: "2026-10-05T18:00:00.000Z", standings: standings),
            event("older", date: "2026-08-01T18:00:00.000Z", standings: standings),
        ])
        let page = try #require(device.archetype(id: "garchomp+gholdengo+rillaboom+volcarona", window: .days30))
        #expect(page.archetype.name == "rillaboom+gholdengo")
        #expect(page.archetype.matchups.isEmpty)
        #expect(page.examples.map(\.placing) == [19, 23, 26, 33, 46])
        let best = try #require(page.examples.first)
        #expect(best.player == "Player 19" && best.wins == 3 && best.losses == 1)
        #expect(best.members.first == MetaAPI.ExampleMember(
            key: "gholdengo", name: "Gholdengo", item: "Life Orb", ability: "Good as Gold", nature: "Modest",
            moves: ["Protect", "Shadow Ball", "Nasty Plot", "Make It Rain"]))
        #expect(device.archetype(id: "a+b+c+d", window: .days30) == nil)

        let events = device.events(limit: 10).events
        #expect(events.map(\.id) == ["event-83", "older"])
        #expect(events[0].winner == MetaAPI.EventWinner(
            player: "Player 01", wins: 8, losses: 2, ties: 0,
            team: ["grimmsnarl", "golisopod", "pelipper", "charizard", "basculegion", "archaludon"]))
        #expect(events[0].topCutPlayers == nil, "the corpus doesn't know")
        #expect(events[0].standingsFinal == false, "fetched 18 hours after the start")
        #expect(events[1].standingsFinal == true)
        #expect(device.events(limit: 1).events.count == 1)

        // The regulation window has both events; 30 days only the newer.
        #expect(device.pokemon(window: .regulation).sample.teams == 2 * device.pokemon(window: .days30).sample.teams)
    }

    /// Names standardized as the server's NameStandardizer does them
    /// (its NameStandardizerTest's cases).
    @Test func names() throws {
        let names = try MetaNames.bundled(for: .mC)
        #expect(names.item("MIRACLE SEED") == "Miracle Seed")
        #expect(names.item("Focus Slash") == "Focus Sash", "one letter off")
        #expect(names.item("") == "No Item")
        #expect(names.item("none") == "No Item")
        #expect(names.item(nil) == nil)
        #expect(names.move("Fake-out") == "Fake Out")
        #expect(names.move("Darkest Larient") == "Darkest Lariat", "two letters off in a long name")
        #expect(names.ability("intimidate") == "Intimidate")
        #expect(names.nature("jolly") == "Jolly")
        #expect(names.nature("JOLY") == "Joly", "under 5 letters needs an exact match")
        #expect(names.item("totally new  item") == "Totally New Item", "unknown names are kept, title-cased")
        #expect(MetaNames.Dictionary.titleCase("never-melt ice") == "Never-Melt Ice")
        #expect(MetaNames.key("Flabébé") == "flabb", "as the server, which drops é")
    }

    /// Spellings that read the same are one value.
    @Test func spellings() throws {
        let standing = try fixtureStandings()[0]
        func member(_ item: String, nature: String) -> LimitlessStanding.TeamMember {
            try! JSONDecoder().decode(LimitlessStanding.TeamMember.self, from: Data("""
                {"name":"Rillaboom","id":"rillaboom","item":"\(item)","ability":"grassy surge",
                 "attacks":["Fake Out","fake-out"],"nature":"\(nature)"}
                """.utf8))
        }
        let teams = [("p1", "Miracle Seed", "Adamant"), ("p2", "MIRACLE SEED", "adamant"), ("p3", "Miracle Sed", "ADAMANT")]
            .map { player, item, nature in
                LimitlessStanding(player: player, name: player, country: nil, placing: nil, record: standing.record,
                                  deck: nil, decklist: [member(item, nature: nature)], drop: nil)
            }
        let device = try insights([event("e", date: "2026-10-05T18:00:00.000Z", standings: teams)])
        let page = try #require(device.pokemon(key: "rillaboom", window: .days30))
        #expect(page.items == [MetaAPI.Share(value: "Miracle Seed", count: 3, share: 1)])
        #expect(page.natures == [MetaAPI.Share(value: "Adamant", count: 3, share: 1)])
        #expect(page.abilities == [MetaAPI.Share(value: "Grassy Surge", count: 3, share: 1)])
        #expect(page.moves == [MetaAPI.Share(value: "Fake Out", count: 3, share: 1)], "once each per member")
    }

    @Test func readsTheNewAnswers() throws {
        func fixture(_ name: String) throws -> Data {
            try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appending(path: "MetaFixtures/\(name).json"))
        }
        let events = try MetaAPI.decode(MetaAPI.Events.self, from: fixture("events-M-C"))
        #expect(!events.events.isEmpty)
        #expect(events.events.contains { $0.winner?.team.count == 6 })
        #expect(events.events.contains { $0.topCutPlayers == nil } || events.events.allSatisfy { $0.topCutPlayers != nil })

        let page = try MetaAPI.decode(MetaAPI.ArchetypeDetail.self, from: fixture("archetype-M-C-30d"))
        #expect(page.archetype.core.count == 4)
        #expect(page.examples.count == 5)
        #expect(page.examples.allSatisfy { $0.members.count == 6 && $0.placing != nil })

        let archetypes = try MetaAPI.decode(MetaAPI.Archetypes.self, from: fixture("archetypes-M-C-30d"))
        #expect(Set(archetypes.archetypes.map(\.name)).count == archetypes.archetypes.count, "names are unique")

        let base = URL(string: "http://localhost:8080")!
        #expect(MetaAPI.events(format: "M-C").url(on: base).absoluteString
                == "http://localhost:8080/v1/formats/M-C/events?limit=10")
        #expect(MetaAPI.archetype(format: "M-C", id: "arcanine:hisui+gholdengo+raichu+staraptor", window: .days30)
            .url(on: base).path() == "/v1/formats/M-C/archetypes/arcanine:hisui+gholdengo+raichu+staraptor")
    }
}
