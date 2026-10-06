//
//  MetaModel.swift
//  PKReference
//
//  State behind the Meta tab: where its numbers come from, and what it says
//  when it has none (BackendIntegration-PHASE4.md §6).
//
//  The source:
//  1. The PK Reference server, when Settings' switch is on and the server
//     answers, or an answer of its is cached (MetaInsights).
//  2. Otherwise the device, from the tournament teams Team Search has
//     downloaded (MetaDeviceInsights). Opening Meta never downloads them
//     itself; Download Events does, as the Problem Solver's download does.
//
//  The regulation is always Settings' Champions regulation. When the source
//  has nothing for it, or nothing in the window, the tab says so.
//

import Foundation
import Observation

@MainActor
@Observable
final class MetaModel {
    nonisolated enum Source: Equatable, Sendable {
        case server
        case device
    }

    /// What the home shows: one source's numbers for one regulation and
    /// window.
    nonisolated struct Snapshot: Sendable {
        let source: Source
        let regulation: ChampionsRegulation
        let window: MetaAPI.Window
        let list: MetaAPI.PokemonList
        /// Newest first.
        let events: [MetaAPI.EventSummary]
        /// When the newest data was fetched: by the server, or by Team
        /// Search's last look at the event list.
        let updated: Date?
        /// Events of the regulation in all, for the empty-window warning.
        let allEvents: Int
        /// Where a Pokémon's page comes from: the server's answers, or the
        /// device's numbers.
        let pages: PageSource
    }

    /// Where pages come from, kept with the snapshot so a page matches it.
    nonisolated enum PageSource: Sendable {
        case server(MetaInsights)
        case device(MetaDeviceInsights)
    }

    /// One Pokémon's page: its numbers, and the cores it's in.
    nonisolated struct Page: Sendable {
        let source: Source
        let detail: MetaAPI.PokemonDetail
        let pairs: [MetaAPI.Core]
        let trios: [MetaAPI.Core]
    }

    enum Status: Equatable {
        case loading
        case ready
        /// No server answer, and Team Search hasn't downloaded any teams.
        case needsDownload
        case downloading(completed: Int, total: Int)
        case downloadFailed(String)
    }

    private(set) var status: Status = .loading
    private(set) var snapshot: Snapshot?
    /// Why the source has nothing to show for the regulation or window.
    private(set) var warning: String?
    /// Why the server couldn't answer, when it's on: shown over what's
    /// shown instead.
    private(set) var serverProblem: MetaFailure?
    /// Limitless's newest events for the regulation, when there's nothing
    /// else to list.
    private(set) var limitlessEvents: [LimitlessTournament] = []

    private let serverURL: @Sendable () -> URL?
    private let session: URLSession
    private let cache: MetaCache
    private let corpusStore: TeamCorpusStore
    private let recentFromLimitless: @Sendable (String) async throws -> [LimitlessTournament]
    private let now: @Sendable () -> Date
    /// The newest request; an older one that finishes later is dropped.
    private var generation = 0

    init(serverURL: @escaping @Sendable () -> URL? = { MetaServerSettings.baseURL() },
         session: URLSession = MetaServerClient.session,
         cache: MetaCache = .shared,
         corpusStore: TeamCorpusStore = .shared,
         recentFromLimitless: @escaping @Sendable (String) async throws -> [LimitlessTournament] = {
             try await LimitlessAPIService.shared.fetchTournaments(game: "VGC", format: $0, limit: 5, page: 1)
         },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.serverURL = serverURL
        self.session = session
        self.cache = cache
        self.corpusStore = corpusStore
        self.recentFromLimitless = recentFromLimitless
        self.now = now
    }

    /// Loads the regulation's numbers for the window: from the server's
    /// cache when it's current, and fresh when `force`d (pull to refresh).
    func load(_ regulation: ChampionsRegulation, window: MetaAPI.Window, force: Bool = false) async {
        generation += 1
        let mine = generation
        if snapshot?.regulation != regulation || snapshot?.window != window { status = .loading }

        var problem: MetaFailure?
        if let url = serverURL() {
            let insights = MetaInsights(baseURL: url, session: session, cache: cache, now: now)
            do {
                let shown = try await fromServer(insights, regulation, window, force: force)
                guard mine == generation else { return }
                apply(shown.snapshot, warning: shown.warning, problem: shown.problem)
                if snapshot == nil { await loadLimitlessEvents(regulation, mine) }
                return
            } catch {
                problem = error
            }
        }
        await fromDevice(regulation, window, problem: problem, mine)
    }

    /// Pull to refresh: the server's answers asked for again, or Team
    /// Search's events brought up to date, as its own refresh does.
    func refresh(_ regulation: ChampionsRegulation, window: MetaAPI.Window) async {
        if serverURL() != nil, serverProblem == nil {
            await load(regulation, window: window, force: true)
            return
        }
        if snapshot?.source == .device {
            _ = try? await corpusStore.corpus(for: regulation, forceRefresh: true)
        }
        await load(regulation, window: window, force: true)
    }

    /// Downloads the regulation's events, as Team Search does, then works the
    /// numbers out from them.
    func download(_ regulation: ChampionsRegulation, window: MetaAPI.Window) async {
        status = .downloading(completed: 0, total: 0)
        do {
            _ = try await corpusStore.corpus(for: regulation) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = self.status else { return }
                    self.status = .downloading(completed: progress.completed, total: progress.total)
                }
            }
        } catch {
            status = .downloadFailed(error.localizedDescription)
            return
        }
        await load(regulation, window: window)
    }

    /// A Pokémon's page from the snapshot's source, in its window: the
    /// server's (cached by the rule in MetaCache.swift) or the device's. nil
    /// when the server can't answer, or no team in the window has it.
    nonisolated static func page(_ key: String, in snapshot: Snapshot) async -> Page? {
        let format = snapshot.regulation.limitlessFormat
        switch snapshot.pages {
        case .server(let insights):
            guard let detail = try? await insights.load(MetaAPI.pokemon(format: format, key: key,
                                                                        window: snapshot.window)) else { return nil }
            let cores = try? await insights.load(MetaAPI.cores(format: format, window: snapshot.window))
            return Page(source: .server, detail: detail.value,
                        pairs: cores?.value.pairs.filter { $0.members.contains(key) } ?? [],
                        trios: cores?.value.trios.filter { $0.members.contains(key) } ?? [])
        case .device(let device):
            return await devicePage(key, device, snapshot.window)
        }
    }

    @concurrent
    nonisolated private static func devicePage(_ key: String, _ device: MetaDeviceInsights,
                                               _ window: MetaAPI.Window) async -> Page? {
        guard let detail = device.pokemon(key: key, window: window) else { return nil }
        let cores = device.cores(window: window)
        return Page(source: .device, detail: detail, pairs: cores.pairs.filter { $0.members.contains(key) },
                    trios: cores.trios.filter { $0.members.contains(key) })
    }

    // MARK: Sources

    private struct Shown {
        let snapshot: Snapshot?
        let warning: String?
        let problem: MetaFailure?
    }

    /// The server's answers. Throws when it can't answer and nothing is
    /// cached, or its answer doesn't read.
    private func fromServer(_ insights: MetaInsights, _ regulation: ChampionsRegulation,
                            _ window: MetaAPI.Window, force: Bool) async throws(MetaFailure) -> Shown {
        let formats = try await insights.load(MetaAPI.formats, force: force)
        let format = regulation.limitlessFormat
        guard let stored = formats.value.formats.first(where: { $0.format.uppercased() == format }),
              stored.teams > 0 else {
            return Shown(snapshot: nil, warning: MetaText.serverHasNoEvents(regulation, formats.value.formats),
                         problem: formats.refreshError)
        }
        let list = try await insights.load(MetaAPI.pokemon(format: format, window: window), force: force)
        let events = try? await insights.load(MetaAPI.events(format: format), force: force)
        let snapshot = Snapshot(source: .server, regulation: regulation, window: window, list: list.value,
                                events: events?.value.events ?? [], updated: stored.lastFetched,
                                allEvents: stored.events, pages: .server(insights))
        return Shown(snapshot: snapshot, warning: Self.emptyWindow(snapshot),
                     problem: formats.refreshError ?? list.refreshError)
    }

    /// The device's numbers, from Team Search's downloaded events.
    private func fromDevice(_ regulation: ChampionsRegulation, _ window: MetaAPI.Window,
                            problem: MetaFailure?, _ mine: Int) async {
        let corpus = await corpusStore.cachedCorpus(format: regulation.limitlessFormat)
        guard mine == generation else { return }
        guard let corpus, !corpus.teams.isEmpty else {
            apply(nil, warning: nil, problem: problem)
            status = .needsDownload
            await loadLimitlessEvents(regulation, mine)
            return
        }
        let snapshot = await Self.deviceSnapshot(corpus, regulation, window, now())
        guard mine == generation else { return }
        apply(snapshot, warning: snapshot.flatMap(Self.emptyWindow), problem: problem)
        if snapshot == nil { status = .downloadFailed("The Team Search data for \(regulation.displayName) didn't load.") }
    }

    @concurrent
    nonisolated private static func deviceSnapshot(_ corpus: TeamCorpus, _ regulation: ChampionsRegulation,
                                                   _ window: MetaAPI.Window, _ now: Date) async -> Snapshot? {
        guard let vocabulary = try? TeamSearchVocabulary.bundled(for: regulation),
              let names = try? MetaNames.bundled(for: regulation) else { return nil }
        let device = MetaDeviceInsights(corpus: corpus, vocabulary: vocabulary, names: names, now: now)
        return Snapshot(source: .device, regulation: regulation, window: window, list: device.pokemon(window: window),
                        events: device.events(limit: 10).events, updated: corpus.listFetchedAt,
                        allEvents: Set(device.teams.map(\.tournament.id)).count, pages: .device(device))
    }

    private func apply(_ snapshot: Snapshot?, warning: String?, problem: MetaFailure?) {
        self.snapshot = snapshot
        self.warning = warning
        serverProblem = problem
        status = .ready
        if snapshot != nil { limitlessEvents = [] }
    }

    private func loadLimitlessEvents(_ regulation: ChampionsRegulation, _ mine: Int) async {
        let events = (try? await recentFromLimitless(regulation.limitlessFormat)) ?? []
        guard mine == generation else { return }
        limitlessEvents = Array(events.prefix(5))
    }

    private static func emptyWindow(_ snapshot: Snapshot) -> String? {
        snapshot.list.sample.teams == 0
            ? MetaText.emptyWindow(snapshot.regulation, snapshot.window, allEvents: snapshot.allEvents) : nil
    }
}

// MARK: - A set to save or calc

/// One of a Pokémon's top sets, for Save Set and Calc Against This: as a
/// Limitless team member, so the importer Events uses resolves it.
nonisolated struct MetaSetRequest: Hashable, Sendable {
    /// The species key: "arcanine:hisui".
    let key: String
    /// "Arcanine (Hisui)".
    let name: String
    let item: String?
    let ability: String?
    let nature: String?
    let moves: [String]

    init(key: String, name: String, set: MetaAPI.PokemonSet?) {
        self.key = key
        self.name = name
        item = set?.item == MetaNames.noItem ? nil : set?.item
        ability = set?.ability
        nature = set?.nature
        moves = set?.moves ?? []
    }

    /// The set as Limitless would list it. The slug is the key with its form
    /// words ("arcanine-hisui"), as Limitless's slugs mostly are.
    var member: LimitlessStanding.TeamMember {
        LimitlessStanding.TeamMember(name: name, limitlessID: key.replacingOccurrences(of: ":", with: "-"),
                                     item: item, ability: ability, attacks: moves, nature: nature, tera: nil)
    }
}

// MARK: - Words

/// The Meta tab's sentences, as plain functions so tests can read them.
nonisolated enum MetaText {
    static func window(_ window: MetaAPI.Window) -> String {
        switch window {
        case .days14: "14 Days"
        case .days30: "30 Days"
        case .regulation: "Regulation"
        }
    }

    /// "the last 14 days", "the regulation so far".
    static func windowPhrase(_ window: MetaAPI.Window) -> String {
        switch window {
        case .days14: "the last 14 days"
        case .days30: "the last 30 days"
        case .regulation: "the regulation so far"
        }
    }

    /// "46 events · 2,633 teams · 484 in top cuts", or "368 in the top 8"
    /// for the device's numbers.
    static func sample(_ sample: MetaAPI.Sample, source: MetaModel.Source) -> String {
        let top = switch source {
        case .server: "\(sample.topCutTeams.formatted()) in top cuts"
        case .device: "\(sample.topCutTeams.formatted()) in the top 8"
        }
        return "\(count(sample.events, "event")) · \(count(sample.teams, "team")) · \(top)"
    }

    /// Where the numbers come from, and how old they are.
    static func source(_ source: MetaModel.Source, updated: Date?, now: Date,
                       locale: Locale = .current) -> String {
        let from = switch source {
        case .server: "Limitless, through your PK Reference server"
        case .device: "Limitless, from the events Team Search downloaded to this device"
        }
        guard let updated else { return from }
        return "\(from) · updated \(ago(updated, now: now, locale: locale))"
    }

    /// "12 minutes ago", "2 hours ago"; "just now" under a minute.
    static func ago(_ date: Date, now: Date, locale: Locale = .current) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// The server has nothing for Settings' regulation.
    static func serverHasNoEvents(_ regulation: ChampionsRegulation, _ formats: [MetaAPI.Format]) -> String {
        let format = regulation.limitlessFormat
        let others = formats
            .filter { ChampionsRegulation(rawValue: $0.format.lowercased()) != nil && $0.teams > 0 }
            .map { "\($0.format) (\(count($0.events, "event")))" }
        var text = "The server has no \(format) events."
        if !others.isEmpty { text += " It has \(others.joined(separator: ", "))." }
        return text + " Change the regulation in Settings, or add \(format) to the server's LIMITLESS_FORMATS."
    }

    /// The window has no teams.
    static func emptyWindow(_ regulation: ChampionsRegulation, _ window: MetaAPI.Window, allEvents: Int) -> String {
        var text = "No \(regulation.limitlessFormat) events in \(windowPhrase(window))."
        if window != .regulation && allEvents > 0 {
            text += " The regulation so far has \(count(allEvents, "event")): try a longer window."
        }
        return text
    }

    /// Team Search hasn't downloaded any teams for the regulation.
    static func needsDownload(_ regulation: ChampionsRegulation) -> String {
        "Usage comes from tournament teams Team Search downloads from Limitless. None for "
            + "\(regulation.limitlessFormat) on this device yet."
    }

    /// The server couldn't answer, and what's shown instead.
    static func serverProblem(_ failure: MetaFailure, showing source: MetaModel.Source?, updated: Date?,
                              now: Date, locale: Locale = .current) -> String {
        let shown: String = switch source {
        case .server?: updated.map { " Showing its answers from \(ago($0, now: now, locale: locale))." }
            ?? " Showing its last answers."
        case .device?: " Showing what this device worked out."
        case nil: ""
        }
        return failure.message + shown
    }

    /// "Won by Player 01, 7–1–0".
    static func winner(_ winner: MetaAPI.EventWinner) -> String {
        var text = "Won by \(winner.player ?? "an unnamed player"), \(winner.wins)–\(winner.losses)"
        if winner.ties > 0 { text += "–\(winner.ties)" }
        return text
    }

    /// "55%"; under 1%, "<1%".
    static func percent(_ share: Double) -> String {
        let value = share * 100
        if value > 0 && value < 1 { return "<1%" }
        return "\(Int(value.rounded()))%"
    }

    /// "▲ 6 points", "▼ 0.4 points", "no change"; nil when there's no trend.
    static func trend(_ trend: Double?) -> String? {
        guard let trend else { return nil }
        let points = trend * 100
        let size = abs(points)
        guard size >= 0.05 else { return "no change" }
        let number = size >= 10 ? String(Int(size.rounded())) : String(format: "%.1f", size)
        return "\(points > 0 ? "▲" : "▼") \(number) point\(number == "1.0" ? "" : "s")"
    }

    /// "Wins 48% (46–50%) of 2,965 matches"; "29 matches: too few for a rate".
    static func record(_ record: MetaAPI.WinRecord?, source: MetaModel.Source) -> String? {
        guard let record, record.matches > 0 else { return nil }
        let matches = count(record.matches, "match", plural: "matches")
        guard let rate = record.winRate else { return "\(matches): too few for a rate" }
        var text = source == .server ? "Wins \(percent(rate))" : "Team record \(percent(rate))"
        if let low = record.winRateLow, let high = record.winRateHigh {
            text += " (\(Int((low * 100).rounded()))–\(percent(high)))"
        }
        return text + " of \(matches)"
    }

    /// The top-cut rate's label for a source.
    static func topCutLabel(_ source: MetaModel.Source) -> String {
        source == .server ? "top cut" : "top 8"
    }

    /// What's winning, in a sentence: the most-used Pokémon, and the top
    /// five's biggest gap between its top-cut rate and its usage when it's
    /// 5 points or more.
    static func whatsWinning(_ pokemon: [MetaAPI.PokemonUsage], source: MetaModel.Source,
                             name: (String) -> String) -> String? {
        guard let first = pokemon.first else { return nil }
        let teams = source == .server ? "top-cut teams" : "top-8 teams"
        var text = "\(name(first.key)) is on \(percent(first.usage)) of teams"
        if let top = first.topCutUsage { text += " and \(percent(top)) of \(teams)" }
        text += "."
        let gaps = pokemon.prefix(5).compactMap { p in p.topCutUsage.map { (p, $0 - p.usage) } }
        if let (p, gap) = gaps.max(by: { abs($0.1) < abs($1.1) }), abs(gap) >= 0.05 {
            text += " \(name(p.key)) does \(gap > 0 ? "better" : "worse") than its usage says: "
                + "\(percent(p.usage)) of teams, \(percent(p.topCutUsage!)) of \(teams)."
        }
        return text
    }

    /// One Pokémon's numbers for VoiceOver, in a sentence.
    static func spoken(_ p: MetaAPI.PokemonUsage, name: String, source: MetaModel.Source) -> String {
        var parts = ["\(name). On \(percent(p.usage)) of teams"]
        if let top = p.topCutUsage {
            parts[0] += ", \(percent(top)) of \(source == .server ? "top-cut" : "top-8") teams"
        }
        parts[0] += "."
        if let record = record(p.record, source: source) { parts.append(record + ".") }
        if let trend = trend(p.trend) {
            parts.append("Trend \(trend.replacingOccurrences(of: "▲", with: "up").replacingOccurrences(of: "▼", with: "down")).")
        } else {
            parts.append("No trend yet.")
        }
        return parts.joined(separator: " ")
    }

    /// "1 event", "46 events".
    static func count(_ n: Int, _ noun: String, plural: String? = nil) -> String {
        "\(n.formatted()) \(n == 1 ? noun : plural ?? noun + "s")"
    }
}
