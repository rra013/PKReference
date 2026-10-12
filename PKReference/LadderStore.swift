//
//  LadderStore.swift
//  PKReference
//
//  Where a ladder's record comes from (BackendIntegration-PHASE5.md §5):
//
//  1. The PK Reference server, when Settings' switch is on and it answers,
//     or an answer of its is cached (MetaInsights and its cache). The server
//     fetched Smogon's files once for everyone, and adds what one file
//     can't say: the change since last month, and usage at the other
//     ratings.
//  2. Otherwise Smogon's own files, reduced on this device
//     (SmogonLadderStore).
//
//  `load` never downloads from Smogon: it's for screens that show what
//  there is and offer the download. `fetch` downloads, as Team Search always
//  has.
//

import Foundation

nonisolated struct LadderStore: Sendable {
    static let shared = LadderStore()

    enum Source: Equatable, Sendable {
        case server
        case device
    }

    /// A ladder's record, and where it's from.
    struct Answer: Sendable, Equatable {
        let stats: MetaAPI.LadderStats
        let source: Source
    }

    /// What `load` and `fetch` found.
    struct Loaded: Sendable {
        /// nil when neither source has the ladder.
        let answer: Answer?
        /// Why the server couldn't answer, when it's on.
        let serverProblem: MetaFailure?
    }

    var serverURL: @Sendable () -> URL? = { MetaServerSettings.baseURL() }
    var insights: @Sendable (URL) -> MetaInsights = { MetaInsights(baseURL: $0) }
    var device: SmogonLadderStore = .shared

    /// The record without asking anyone: the server's cached answer, or the
    /// device's own.
    func cached(_ request: LadderRequest, fallBack: Bool = false) async -> Answer? {
        if let url = serverURL() {
            let insights = insights(url)
            if let index = await insights.cached(MetaAPI.ladder)?.value,
               let entry = Self.choose(request, from: index.stats, fallBack: fallBack),
               let stats = await insights.cached(Self.endpoint(entry))?.value {
                return Answer(stats: stats, source: .server)
            }
        }
        return await device.cached(request, fallBack: fallBack).map { Answer(stats: $0, source: .device) }
    }

    /// The record from the server, by its cache's rule (asked again when
    /// `force`d), or else what the device already has. Never downloads from
    /// Smogon.
    func load(_ request: LadderRequest, fallBack: Bool = false, force: Bool = false) async -> Loaded {
        let server = await fromServer(request, fallBack: fallBack, force: force)
        if server.answer != nil { return server }
        let onDevice = await device.cached(request, fallBack: fallBack)
        return Loaded(answer: onDevice.map { Answer(stats: $0, source: .device) }, serverProblem: server.serverProblem)
    }

    /// As `load`, but when the server has nothing the record is made from
    /// Smogon's files, downloading them if needed. Throws when Smogon can't
    /// be reached and nothing is on the device.
    func fetch(_ request: LadderRequest, fallBack: Bool = false, force: Bool = false) async throws -> Loaded {
        let server = await fromServer(request, fallBack: fallBack, force: force)
        if server.answer != nil { return server }
        let made = try await device.stats(request, fallBack: fallBack, forceRefresh: force)
        return Loaded(answer: made.map { Answer(stats: $0, source: .device) }, serverProblem: server.serverProblem)
    }

    private func fromServer(_ request: LadderRequest, fallBack: Bool, force: Bool) async -> Loaded {
        guard let url = serverURL() else { return Loaded(answer: nil, serverProblem: nil) }
        let insights = insights(url)
        do {
            let index = try await insights.load(MetaAPI.ladder, force: force)
            guard let entry = Self.choose(request, from: index.value.stats, fallBack: fallBack) else {
                return Loaded(answer: nil, serverProblem: index.refreshError)
            }
            let stats = try await insights.load(Self.endpoint(entry), force: force)
            return Loaded(answer: Answer(stats: stats.value, source: .server),
                          serverProblem: index.refreshError ?? stats.refreshError)
        } catch {
            return Loaded(answer: nil, serverProblem: error)
        }
    }

    private static func endpoint(_ entry: MetaAPI.LadderEntry) -> MetaAPI.Endpoint<MetaAPI.LadderStats> {
        MetaAPI.ladder(format: entry.format, rating: entry.rating, month: entry.month)
    }

    /// The server's entry for `request`: the regulation's own newest month;
    /// with `fallBack`, otherwise the newest month of the latest earlier
    /// regulation, as SmogonLadderStore chooses from Smogon's listings.
    static func choose(_ request: LadderRequest, from entries: [MetaAPI.LadderEntry],
                       fallBack: Bool) -> MetaAPI.LadderEntry? {
        let candidates = entries.compactMap { entry -> (entry: MetaAPI.LadderEntry, regulation: ChampionsRegulation)? in
            guard entry.rating == request.rating, entry.mode == request.mode.rawValue,
                  entry.bestOf == request.bestOf,
                  let regulation = ChampionsRegulation(rawValue: entry.regulation.lowercased()) else { return nil }
            return (entry, regulation)
        }
        if let own = candidates.filter({ $0.regulation == request.regulation }).max(by: { $0.entry.month < $1.entry.month }) {
            return own.entry
        }
        guard fallBack else { return nil }
        let requestedStart = request.regulation.validFrom ?? .distantFuture
        return candidates
            .filter { ($0.regulation.validFrom ?? .distantPast) <= requestedStart }
            .max { a, b in
                a.entry.month != b.entry.month ? a.entry.month < b.entry.month
                    : (a.regulation.validFrom ?? .distantPast) < (b.regulation.validFrom ?? .distantPast)
            }?.entry
    }
}
