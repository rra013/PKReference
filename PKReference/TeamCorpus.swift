//
//  TeamCorpus.swift
//  PKReference
//
//  The tournament teams Team Search searches: every published decklist
//  from recent Limitless events in one Champions regulation.
//
//  Limitless has no bulk endpoint, so building a corpus takes a crawl of
//  the tournament list plus one standings request per event.
//  `TeamCorpusStore` keeps each event's standings on disk, in the API's own
//  shape. The API has no "finished" flag, so a time rule stands in for one:
//  standings fetched at least `settleAfter` past an event's start are
//  final and never fetched again. After the first build, a refresh costs
//  the list pages plus any new or still-running events.
//

import Foundation

// MARK: - Corpus

/// One event and its standings, as cached.
nonisolated struct CorpusEvent: Codable, Sendable {
    let tournament: LimitlessTournament
    let standings: [LimitlessStanding]
    /// When the standings were fetched.
    let fetchedAt: Date
}

/// One published team: a player's decklist at one event.
nonisolated struct CorpusTeam: Sendable, Identifiable {
    let tournament: LimitlessTournament
    let standing: LimitlessStanding

    var id: String { "\(tournament.id)/\(standing.player)" }
    var members: [LimitlessStanding.TeamMember] { standing.decklist ?? [] }
}

nonisolated struct TeamCorpus: Sendable {
    /// Limitless format ID, e.g. "M-C".
    let format: String
    /// Newest first.
    let events: [CorpusEvent]
    /// Every team with a published decklist: newest event first, then by
    /// placing, with unranked (dropped) players last.
    let teams: [CorpusTeam]
    /// When the tournament list was last crawled.
    let listFetchedAt: Date
    /// Listed events whose standings couldn't be fetched and weren't cached.
    let missingEvents: [LimitlessTournament]
    /// Why re-crawling the tournament list failed, when this corpus fell back
    /// to the cached list. nil when the list is as fresh as it was asked to be.
    let listRefreshError: String?

    init(format: String, events: [CorpusEvent], listFetchedAt: Date,
         missingEvents: [LimitlessTournament], listRefreshError: String? = nil) {
        self.format = format
        self.events = events
        self.listFetchedAt = listFetchedAt
        self.missingEvents = missingEvents
        self.listRefreshError = listRefreshError
        self.teams = events.flatMap { event in
            LimitlessStanding.sortedByPlacing(event.standings)
                .filter { !($0.decklist ?? []).isEmpty }
                .map { CorpusTeam(tournament: event.tournament, standing: $0) }
        }
    }
}

extension ChampionsRegulation {
    /// Limitless's format ID for this regulation ("m-c" → "M-C").
    nonisolated var limitlessFormat: String { rawValue.uppercased() }
}

// MARK: - Fetching

/// The two Limitless calls a corpus needs. A protocol so tests can serve
/// canned responses.
nonisolated protocol TeamCorpusFetching: Sendable {
    /// One page of the format's tournament list, newest first.
    func tournaments(format: String, page: Int, limit: Int) async throws -> [LimitlessTournament]
    func standings(tournamentID: String) async throws -> [LimitlessStanding]
}

/// Live Limitless, through the app's shared API service. Team Search covers
/// Champions doubles, which Limitless files under the "VGC" game.
nonisolated struct LimitlessCorpusFetcher: TeamCorpusFetching {
    func tournaments(format: String, page: Int, limit: Int) async throws -> [LimitlessTournament] {
        try await LimitlessAPIService.shared.fetchTournaments(
            game: "VGC", format: format, limit: limit, page: page)
    }

    func standings(tournamentID: String) async throws -> [LimitlessStanding] {
        try await LimitlessAPIService.shared.fetchStandings(tournamentID: tournamentID)
    }
}

nonisolated struct TeamCorpusConfiguration: Sendable {
    /// Smaller events say little about what's popular.
    var minPlayers = 16
    /// How many of the newest qualifying events to include. Bounds the first
    /// build, which makes one standings request per event.
    var maxEvents = 100
    var pageSize = 50
    /// Stops the list crawl even if Limitless keeps returning full pages.
    var maxPages = 20
    /// How long a crawled tournament list is reused.
    var listTTL: TimeInterval = 6 * 60 * 60
    /// Standings fetched this long after an event's start are final.
    var settleAfter: TimeInterval = 48 * 60 * 60
    /// Standings requests in flight at once. Limitless is a free API; stay
    /// polite.
    var maxConcurrentFetches = 4
    /// Retries for a rate-limited (HTTP 429) or server-error request.
    var maxRetries = 3
    /// The first retry's wait when the server sends no Retry-After. It
    /// doubles for each further retry.
    var initialBackoff: TimeInterval = 2
    /// The longest single wait, including a server's Retry-After.
    var maxBackoff: TimeInterval = 60
}

// MARK: - Store

actor TeamCorpusStore {
    static let shared = TeamCorpusStore()

    struct FetchProgress: Sendable, Equatable {
        let completed: Int
        let total: Int
    }

    private let fetcher: any TeamCorpusFetching
    private let directory: URL
    private let configuration: TeamCorpusConfiguration
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var memory: [String: TeamCorpus] = [:]

    /// Bump when the cached file layout changes; older caches are ignored.
    nonisolated private static let cacheVersion = "v1"

    nonisolated static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "TeamSearch", directoryHint: .isDirectory)
    }

    init(fetcher: any TeamCorpusFetching = PreferredCorpusFetcher(),
         directory: URL = TeamCorpusStore.defaultDirectory,
         configuration: TeamCorpusConfiguration = TeamCorpusConfiguration(),
         now: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
             try await Task.sleep(for: .seconds($0))
         }) {
        self.fetcher = fetcher
        self.directory = directory.appending(path: Self.cacheVersion, directoryHint: .isDirectory)
        self.configuration = configuration
        self.now = now
        self.sleep = sleep
    }

    /// The corpus from memory or disk, without touching the network. nil
    /// when nothing is cached for the format.
    func cachedCorpus(format: String) -> TeamCorpus? {
        if let corpus = memory[format] { return corpus }
        guard let list = readList(format: format) else { return nil }
        var events: [CorpusEvent] = []
        var missing: [LimitlessTournament] = []
        for tournament in list.tournaments {
            if let event = readEvent(format: format, id: tournament.id) {
                events.append(event)
            } else {
                missing.append(tournament)
            }
        }
        let corpus = TeamCorpus(format: format, events: events,
                                listFetchedAt: list.fetchedAt, missingEvents: missing)
        memory[format] = corpus
        return corpus
    }

    /// Brings the corpus up to date. The tournament list is re-crawled when
    /// it's older than `listTTL`, or on `forceRefresh`. Standings are fetched
    /// for events that aren't cached, or whose cached standings aren't final
    /// and are older than `listTTL` (always, on `forceRefresh`).
    ///
    /// Failures degrade rather than throw: a failed list crawl falls back to
    /// the cached list (and says so in `listRefreshError`), and a failed
    /// standings fetch to that event's cached standings, or to
    /// `missingEvents`. Throws only when the list can't be fetched and none
    /// is cached.
    func corpus(format: String, forceRefresh: Bool = false,
                progress: (@Sendable (FetchProgress) -> Void)? = nil) async throws -> TeamCorpus {
        let start = now()

        let list: CachedList
        var listRefreshError: String?
        let cachedList = readList(format: format)
        if let cachedList, !forceRefresh,
           start.timeIntervalSince(cachedList.fetchedAt) <= configuration.listTTL {
            list = cachedList
        } else {
            do {
                list = CachedList(fetchedAt: start, tournaments: try await crawl(format: format))
                write(list, to: listURL(format: format))
            } catch {
                guard let cachedList else { throw error }
                list = cachedList
                listRefreshError = error.localizedDescription
            }
        }

        var cached: [String: CorpusEvent] = [:]
        var toFetch: [LimitlessTournament] = []
        for tournament in list.tournaments {
            let event = readEvent(format: format, id: tournament.id)
            if let event { cached[tournament.id] = event }
            if let event, isFinal(event)
                || (!forceRefresh && start.timeIntervalSince(event.fetchedAt) <= configuration.listTTL) {
                continue
            }
            toFetch.append(tournament)
        }

        let total = list.tournaments.count
        var completed = total - toFetch.count
        progress?(FetchProgress(completed: completed, total: total))

        let fetcher = self.fetcher, configuration = self.configuration, sleep = self.sleep
        @Sendable func fetchStandings(_ tournament: LimitlessTournament) async -> [LimitlessStanding]? {
            try? await Self.withRetries(configuration, sleep: sleep) {
                try await fetcher.standings(tournamentID: tournament.id)
            }
        }
        await withTaskGroup(of: (LimitlessTournament, [LimitlessStanding]?).self) { group in
            // At most `maxConcurrentFetches` in flight: start that many, then
            // one more as each finishes.
            var pending = toFetch[...]
            for _ in 0..<configuration.maxConcurrentFetches {
                guard let tournament = pending.popFirst() else { break }
                group.addTask { (tournament, await fetchStandings(tournament)) }
            }
            while let result = await group.next() {
                let (tournament, standings) = result
                if let standings {
                    let event = CorpusEvent(tournament: tournament, standings: standings,
                                            fetchedAt: now())
                    write(event, to: eventURL(format: format, id: tournament.id))
                    cached[tournament.id] = event
                }
                completed += 1
                progress?(FetchProgress(completed: completed, total: total))
                if let next = pending.popFirst() {
                    group.addTask { (next, await fetchStandings(next)) }
                }
            }
        }

        let corpus = TeamCorpus(
            format: format,
            events: list.tournaments.compactMap { cached[$0.id] },
            listFetchedAt: list.fetchedAt,
            missingEvents: list.tournaments.filter { cached[$0.id] == nil },
            listRefreshError: listRefreshError)
        memory[format] = corpus
        return corpus
    }

    func corpus(for regulation: ChampionsRegulation, forceRefresh: Bool = false,
                progress: (@Sendable (FetchProgress) -> Void)? = nil) async throws -> TeamCorpus {
        try await corpus(format: regulation.limitlessFormat, forceRefresh: forceRefresh,
                         progress: progress)
    }

    /// Deletes every cached list and event.
    func clearCache() throws {
        memory = [:]
        if FileManager.default.fileExists(atPath: directory.path()) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// Bytes on disk, for Settings.
    func cacheSize() -> Int {
        guard let files = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in files {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    // MARK: Crawl

    /// The newest `maxEvents` events with at least `minPlayers` players,
    /// newest first.
    private func crawl(format: String) async throws -> [LimitlessTournament] {
        var kept: [LimitlessTournament] = []
        for page in 1...configuration.maxPages {
            let fetcher = self.fetcher, pageSize = configuration.pageSize
            let batch = try await Self.withRetries(configuration, sleep: sleep) {
                try await fetcher.tournaments(format: format, page: page, limit: pageSize)
            }
            for tournament in batch where tournament.players >= configuration.minPlayers {
                kept.append(tournament)
                if kept.count == configuration.maxEvents { return kept }
            }
            if batch.count < configuration.pageSize { break }
        }
        return kept
    }

    /// Runs `request`, retrying rate limits and server errors up to
    /// `maxRetries` times. Each retry waits for the server's Retry-After when
    /// it sent one, otherwise `initialBackoff`, doubling each time. Either way
    /// the wait is capped at `maxBackoff`. Other errors are thrown at once.
    nonisolated static func withRetries<T: Sendable>(
        _ configuration: TeamCorpusConfiguration,
        sleep: @Sendable (TimeInterval) async throws -> Void,
        _ request: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await request()
            } catch let error as LimitlessAPIError where error.isTransient
                                                       && attempt < configuration.maxRetries {
                let backoff = configuration.initialBackoff * pow(2, Double(attempt))
                var wait = backoff
                if case .rateLimited(let retryAfter?) = error { wait = retryAfter }
                attempt += 1
                try await sleep(min(wait, configuration.maxBackoff))
            }
        }
    }

    private func isFinal(_ event: CorpusEvent) -> Bool {
        guard let started = event.tournament.parsedDate else { return false }
        return event.fetchedAt.timeIntervalSince(started) >= configuration.settleAfter
    }

    // MARK: Disk

    private struct CachedList: Codable {
        let fetchedAt: Date
        let tournaments: [LimitlessTournament]
    }

    private func listURL(format: String) -> URL {
        directory.appending(path: format).appending(path: "list.json")
    }

    private func eventURL(format: String, id: String) -> URL {
        directory.appending(path: format).appending(path: "events").appending(path: "\(id).json")
    }

    private func readList(format: String) -> CachedList? {
        read(CachedList.self, from: listURL(format: format))
    }

    private func readEvent(format: String, id: String) -> CorpusEvent? {
        read(CorpusEvent.self, from: eventURL(format: format, id: id))
    }

    /// nil for a missing or unreadable file: a bad cache entry is refetched,
    /// never fatal.
    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Best effort: a failed write only costs a refetch later.
    private func write(_ value: some Encodable, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
