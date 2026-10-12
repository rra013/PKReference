//
//  SmogonLadderStore.swift
//  PKReference
//
//  Ladder records made on this device from Smogon's own files, for when
//  there's no PK Reference server: which month and file a ladder's stats are
//  in, the download, the reduction (SmogonLadder.reduce) and the cache.
//
//  A chaos file is up to 7 MB, so it's reduced to the record the app shows
//  and only that is kept. A published month never changes, so a reduced
//  month never expires; only the choice of month does.
//
//  Nothing here downloads a chaos file unless asked to: `cached` and
//  `offer` don't, and `stats` does. Team Search asks; the Meta tab's ladder
//  shows what's on the device and offers the download
//  (BackendIntegration-PHASE5.md §5).
//

import Foundation

nonisolated struct SmogonLadderConfiguration: Sendable {
    /// How many recent months to search for a ladder's stats.
    var lookbackMonths = 4
    /// How long the choice of month is reused before checking for a newer one.
    var resolutionTTL: TimeInterval = 12 * 60 * 60
}

actor SmogonLadderStore {
    static let shared = SmogonLadderStore()

    /// The month and file a ladder's stats are in.
    struct Offer: Sendable, Equatable, Codable {
        let month: String
        /// "gen9championsvgc2026regmc-1760.json".
        let file: String
        /// The download's size, when Smogon's listing says.
        let bytes: Int?
    }

    /// What reducing needs of a regulation; tests give their own.
    typealias Lookups = @Sendable (ChampionsRegulation) -> (vocabulary: TeamSearchVocabulary?, names: MetaNames?)

    private let fetcher: any SmogonFetching
    private let root: URL
    private let directory: URL
    private let configuration: SmogonLadderConfiguration
    private let lookups: Lookups
    private let now: @Sendable () -> Date

    /// v1 held Team Search's usage and teammates only (SmogonUsage); v2
    /// holds ladder records.
    nonisolated private static let cacheVersion = "v2"
    nonisolated private static let oldCacheVersions = ["v1"]

    nonisolated static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "SmogonUsage", directoryHint: .isDirectory)
    }

    nonisolated static let bundledLookups: Lookups = { regulation in
        (try? TeamSearchVocabulary.bundled(for: regulation), try? MetaNames.bundled(for: regulation))
    }

    init(fetcher: any SmogonFetching = SmogonLiveFetcher(),
         directory: URL = SmogonLadderStore.defaultDirectory,
         configuration: SmogonLadderConfiguration = SmogonLadderConfiguration(),
         lookups: @escaping Lookups = SmogonLadderStore.bundledLookups,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetcher = fetcher
        root = directory
        self.directory = directory.appending(path: Self.cacheVersion, directoryHint: .isDirectory)
        self.configuration = configuration
        self.lookups = lookups
        self.now = now
    }

    /// The record for `request`, without touching the network: the last
    /// month chosen for it, if its stats are on the device. With
    /// `fallBack`, an earlier regulation's when that was the choice.
    func cached(_ request: LadderRequest, fallBack: Bool = false) -> MetaAPI.LadderStats? {
        guard let offer = readChoice(request, fallBack)?.offer else { return nil }
        return readStats(offer)
    }

    /// The month and file `request`'s stats are in: the regulation's own
    /// newest month within `lookbackMonths`; with `fallBack`, otherwise the
    /// newest month of the latest earlier regulation. nil when Smogon has
    /// nothing usable. Reads Smogon's listings, never a chaos file.
    ///
    /// If Smogon can't be reached, the last choice is used even if stale.
    /// Throws only when there's no choice to fall back on.
    func offer(_ request: LadderRequest, fallBack: Bool = false, forceRefresh: Bool = false) async throws -> Offer? {
        let last = readChoice(request, fallBack)
        if !forceRefresh, let last, now().timeIntervalSince(last.chosenAt) < configuration.resolutionTTL {
            return last.offer
        }
        let choice: Choice
        do {
            choice = Choice(chosenAt: now(), offer: try await choose(request, fallBack: fallBack))
        } catch {
            guard let last else { throw error }
            return last.offer
        }
        write(choice, to: choiceURL(request, fallBack))
        return choice.offer
    }

    /// Whether an offer's stats are on the device already.
    func isDownloaded(_ offer: Offer) -> Bool {
        FileManager.default.fileExists(atPath: statsURL(offer).path())
    }

    /// The record for `request`, downloading and reducing Smogon's file when
    /// it isn't on the device. nil when Smogon has nothing usable.
    func stats(_ request: LadderRequest, fallBack: Bool = false,
               forceRefresh: Bool = false) async throws -> MetaAPI.LadderStats? {
        guard let offer = try await offer(request, fallBack: fallBack, forceRefresh: forceRefresh) else { return nil }
        return try await load(offer)
    }

    func clearCache() throws {
        if FileManager.default.fileExists(atPath: root.path()) {
            try FileManager.default.removeItem(at: root)
        }
    }

    /// Bytes on disk, for Settings. Looking also clears what an older
    /// version of the app left.
    func cacheSize() -> Int {
        removeOldCaches()
        guard let files = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in files {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    // MARK: Choosing a month

    /// What was chosen for a ladder, and when. `offer` is nil when Smogon
    /// had nothing usable.
    private struct Choice: Codable {
        let chosenAt: Date
        let offer: Offer?
    }

    private func choose(_ request: LadderRequest, fallBack: Bool) async throws -> Offer? {
        let months = try await fetcher.months().sorted(by: >).prefix(configuration.lookbackMonths)
        let requestedStart = request.regulation.validFrom ?? .distantFuture
        var fallback: (offer: Offer, start: Date)?
        for month in months {
            for file in try await fetcher.chaosFiles(month: month) {
                guard let hit = SmogonLadderFormat.file(file.name), hit.rating == request.rating,
                      hit.format.matches(request) else { continue }
                let offer = Offer(month: month, file: file.name, bytes: file.bytes)
                if hit.format.regulation == request.regulation { return offer }
                guard fallBack else { continue }
                // An earlier regulation, newest month first, then newest regulation.
                let start = hit.format.regulation.validFrom ?? .distantPast
                if start <= requestedStart, fallback == nil
                    || (fallback!.offer.month == month && start > fallback!.start) {
                    fallback = (offer, start)
                }
            }
            // Keep looking in older months for the regulation's own stats,
            // but never prefer an older month's fallback.
        }
        return fallback?.offer
    }

    // MARK: Loading a month

    private func load(_ offer: Offer) async throws -> MetaAPI.LadderStats? {
        if let cached = readStats(offer) { return cached }
        guard let hit = SmogonLadderFormat.file(offer.file) else { return nil }
        // Without the leads table the record just has no lead shares.
        let leads = try? await fetcher.leads(month: offer.month, file: "\(hit.format.id)-\(hit.rating).txt")
        let chaos = try await fetcher.chaos(month: offer.month, file: offer.file)
        let stats = try await Self.reduce(chaos, leads, hit.format, offer.month, hit.rating, lookups)
        write(stats, to: statsURL(offer))
        return stats
    }

    /// Off the actor: reducing a 7 MB file takes a moment.
    @concurrent
    nonisolated private static func reduce(_ chaos: Data, _ leads: String?, _ format: SmogonLadderFormat,
                                           _ month: String, _ rating: Int,
                                           _ lookups: Lookups) async throws -> MetaAPI.LadderStats {
        let (vocabulary, names) = lookups(format.regulation)
        return try SmogonLadder.reduce(chaos: chaos, leads: leads, format: format, month: month, rating: rating,
                                       vocabulary: vocabulary, names: names)
    }

    // MARK: Disk

    private func choiceURL(_ request: LadderRequest, _ fallBack: Bool) -> URL {
        let name = "choice-\(request.regulation.rawValue)-\(request.mode.rawValue)-bo\(request.bestOf)-\(request.rating)"
        return directory.appending(path: name + (fallBack ? "-or-earlier" : "") + ".json")
    }

    /// One file per month, format, rating and rule, so a new rule's records
    /// are made again.
    private func statsURL(_ offer: Offer) -> URL {
        directory.appending(path: "stats")
            .appending(path: "r\(SmogonLadder.reduction)-\(offer.month)-\(offer.file)")
    }

    private func readChoice(_ request: LadderRequest, _ fallBack: Bool) -> Choice? {
        read(Choice.self, from: choiceURL(request, fallBack))
    }

    private func readStats(_ offer: Offer) -> MetaAPI.LadderStats? {
        read(MetaAPI.LadderStats.self, from: statsURL(offer))
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Best effort: a failed write only costs a refetch later.
    private func write(_ value: some Encodable, to url: URL) {
        removeOldCaches()
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private var removedOldCaches = false

    private func removeOldCaches() {
        guard !removedOldCaches else { return }
        removedOldCaches = true
        for version in Self.oldCacheVersions {
            try? FileManager.default.removeItem(at: root.appending(path: version, directoryHint: .isDirectory))
        }
    }
}
