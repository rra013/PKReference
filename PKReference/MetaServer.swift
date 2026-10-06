//
//  MetaServer.swift
//  PKReference
//
//  The PK Reference server (backend/): tournament data the server has
//  already collected from Limitless. With Settings' switch on, Team Search
//  and the Problem Solver's tournament usage build their corpus from it, with
//  the same two calls they make to Limitless, which the server answers in
//  Limitless's own shapes. When the server can't answer, they ask Limitless,
//  as they always have. The switch is off by default
//  (BackendIntegration-PLAN.md §4.4).
//

import Foundation

/// The server's settings, as stored. Plain strings so the corpus code, off
/// the main actor, can read them; `AppSettings` has the same keys.
nonisolated enum MetaServerSettings {
    static let enabledKey = "metaServerEnabled"
    static let addressKey = "metaServerAddress"
    /// The owner's local Docker setup while the app isn't deployed: the
    /// simulator's and the Mac's own machine. A phone needs the Mac's
    /// network address.
    static let defaultAddress = "http://localhost:8080"

    /// The server to use, or nil when the switch is off or the address
    /// doesn't read as an http(s) URL.
    static func baseURL(_ defaults: UserDefaults = .standard) -> URL? {
        guard defaults.bool(forKey: enabledKey) else { return nil }
        return url(from: defaults.string(forKey: addressKey) ?? defaultAddress)
    }

    /// "localhost:8080" reads as "http://localhost:8080"; a trailing slash
    /// is dropped.
    static func url(from address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil else { return nil }
        return url
    }
}

/// What went wrong talking to the server.
nonisolated enum MetaServerError: LocalizedError, Equatable {
    case http(status: Int)
    case notHTTP

    var errorDescription: String? {
        switch self {
        case .http(let status): return "The server answered HTTP \(status)."
        case .notHTTP: return "The server's answer wasn't HTTP."
        }
    }
}

/// GETs JSON from the server. Short timeouts: a server that's down should
/// fall back to Limitless quickly, not hold Team Search up.
nonisolated struct MetaServerClient: Sendable {
    let baseURL: URL
    var session: URLSession = MetaServerClient.session

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    func get<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse else { throw MetaServerError.notHTTP }
        guard (200..<300).contains(http.statusCode) else { throw MetaServerError.http(status: http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// The corpus's two calls, answered by the server in Limitless's shapes.
nonisolated struct ServerCorpusFetcher: TeamCorpusFetching {
    let client: MetaServerClient

    func tournaments(format: String, page: Int, limit: Int) async throws -> [LimitlessTournament] {
        try await client.get([LimitlessTournament].self, path: "v1/formats/\(format)/tournaments",
                             query: [URLQueryItem(name: "page", value: String(page)),
                                     URLQueryItem(name: "limit", value: String(limit))])
    }

    func standings(tournamentID: String) async throws -> [LimitlessStanding] {
        try await client.get([LimitlessStanding].self, path: "v1/tournaments/\(tournamentID)/standings")
    }
}

/// The corpus's source: the server when Settings' switch is on, read at each
/// call, and Limitless otherwise, or whenever the server can't answer.
nonisolated struct PreferredCorpusFetcher: TeamCorpusFetching {
    var serverURL: @Sendable () -> URL? = { MetaServerSettings.baseURL() }
    var server: @Sendable (URL) -> any TeamCorpusFetching = { ServerCorpusFetcher(client: MetaServerClient(baseURL: $0)) }
    var limitless: any TeamCorpusFetching = LimitlessCorpusFetcher()

    func tournaments(format: String, page: Int, limit: Int) async throws -> [LimitlessTournament] {
        if let url = serverURL(),
           let list = try? await server(url).tournaments(format: format, page: page, limit: limit) {
            return list
        }
        return try await limitless.tournaments(format: format, page: page, limit: limit)
    }

    func standings(tournamentID: String) async throws -> [LimitlessStanding] {
        if let url = serverURL(), let standings = try? await server(url).standings(tournamentID: tournamentID) {
            return standings
        }
        return try await limitless.standings(tournamentID: tournamentID)
    }
}

// MARK: - Settings' connection test

/// The server's `/v1/formats`, for Settings to say what it has.
nonisolated struct MetaServerFormats: Decodable, Sendable {
    let formats: [Format]

    struct Format: Decodable, Sendable {
        let format: String
        let events: Int
        let teams: Int
        let lastFetched: String?
    }

    /// "M-C: 212 events, 9,410 teams" for each format, newest first.
    var summary: String {
        guard !formats.isEmpty else { return "Connected, but the server has no events yet." }
        return formats.map { "\($0.format): \($0.events.formatted()) events, \($0.teams.formatted()) teams" }
            .joined(separator: "\n")
    }

    static func fetch(from baseURL: URL) async throws -> MetaServerFormats {
        try await MetaServerClient(baseURL: baseURL).get(MetaServerFormats.self, path: "v1/formats")
    }
}
