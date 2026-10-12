//
//  SmogonUsage.swift
//  PKReference
//
//  Smogon's monthly ladder usage statistics, as Team Search uses them: how
//  often each Pokémon is used and which teammates it's paired with. Smogon
//  publishes whole-team data only as these pairwise statistics, so they
//  complement Limitless's tournament teams rather than replace them.
//
//  The numbers are a ladder record's (MetaAPI.LadderStats), which comes from
//  the PK Reference server or from Smogon's own files (LadderStore). This
//  file has Team Search's view of one, and how Smogon's files are fetched:
//  https://www.smogon.com/stats/<month>/chaos/<format>-<rating>.json and
//  .../leads/<format>-<rating>.txt.
//
//  A regulation has no stats until the month after it starts, so Team Search
//  falls back to the newest month of an earlier regulation.
//  `SmogonUsage.format` and `month` say which one it got, for labelling.
//

import Foundation

// MARK: - Usage

nonisolated struct SmogonUsage: Sendable, Equatable {

    struct Teammate: Sendable, Equatable {
        /// Smogon's species name: "Charizard-Mega-Y".
        let name: String
        /// Share of this species' teams that also run the teammate, 0–1.
        let share: Double
    }

    struct Species: Sendable, Equatable {
        let name: String
        /// Share of all teams that run it, 0–1.
        let usage: Double
        /// Most-paired first.
        let teammates: [Teammate]
    }

    /// Smogon's format ID: "gen9championsvgc2026regmb".
    let format: String
    /// "2026-08".
    let month: String
    /// The ladder rating cutoff the stats are weighted for.
    let rating: Int
    let battles: Int
    /// Most-used first.
    let species: [Species]

    /// The Champions regulation the format is for, from its "reg<id>" suffix.
    var regulation: ChampionsRegulation? { SmogonLadderFormat(id: format)?.regulation }
}

nonisolated extension SmogonUsage {
    /// A ladder record's usage and teammates.
    init(_ stats: MetaAPI.LadderStats) {
        self.init(format: stats.format, month: stats.month, rating: stats.rating, battles: stats.battles,
                  species: stats.pokemon.map { pokemon in
                      Species(name: pokemon.name, usage: pokemon.usage,
                              teammates: pokemon.teammates.map { Teammate(name: $0.value, share: $0.share) })
                  })
    }
}

nonisolated enum SmogonUsageError: LocalizedError, Equatable, Sendable {
    case unreadableStats
    case http(status: Int)

    var errorDescription: String? {
        switch self {
        case .unreadableStats: return "Smogon's usage stats couldn't be read."
        case .http(let status): return "Smogon returned an error (HTTP \(status))."
        }
    }
}

// MARK: - Fetching

/// A file in one of Smogon's listings, with its size when the listing says.
nonisolated struct SmogonFile: Sendable, Equatable, Codable {
    let name: String
    let bytes: Int?
}

/// Smogon's stats directory. A protocol so tests can serve canned listings.
nonisolated protocol SmogonFetching: Sendable {
    /// Month directories on the stats index, e.g. "2026-08".
    func months() async throws -> [String]
    /// The files in a month's chaos directory.
    func chaosFiles(month: String) async throws -> [SmogonFile]
    func chaos(month: String, file: String) async throws -> Data
    /// A month's leads table for a chaos file's format and rating
    /// ("<format>-<rating>.txt"); nil when Smogon has none.
    func leads(month: String, file: String) async throws -> String?
}

nonisolated struct SmogonLiveFetcher: SmogonFetching {
    private static let base = URL(string: "https://www.smogon.com/stats/")!

    func months() async throws -> [String] {
        try await Self.listing(at: Self.base).map(\.name)
            .filter { $0.range(of: #"^\d{4}-\d{2}/$"#, options: .regularExpression) != nil }
            .map { String($0.dropLast()) }
    }

    func chaosFiles(month: String) async throws -> [SmogonFile] {
        try await Self.listing(at: Self.base.appending(path: "\(month)/chaos/"))
            .filter { $0.name.hasSuffix(".json") }
    }

    func chaos(month: String, file: String) async throws -> Data {
        try await Self.get(Self.base.appending(path: "\(month)/chaos/\(file)"))
    }

    func leads(month: String, file: String) async throws -> String? {
        do {
            return String(decoding: try await Self.get(Self.base.appending(path: "\(month)/leads/\(file)")),
                          as: UTF8.self)
        } catch SmogonUsageError.http(status: 404) {
            return nil
        }
    }

    /// The links on a directory listing page, each with the size at the end
    /// of its line:
    /// `<a href="x-0.json">x-0.json</a>     01-Oct-2026 14:40    612931`.
    static func listing(_ html: String) -> [SmogonFile] {
        html.split(whereSeparator: \.isNewline).compactMap { line in
            guard let match = line.firstMatch(of: /href="([^"]+)"/) else { return nil }
            let size = line.split(separator: " ").last.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return SmogonFile(name: String(match.1), bytes: size)
        }
    }

    private static func listing(at url: URL) async throws -> [SmogonFile] {
        listing(String(decoding: try await get(url), as: UTF8.self))
    }

    private static func get(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SmogonUsageError.http(status: http.statusCode)
        }
        return data
    }
}
