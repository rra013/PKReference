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
//  (BackendIntegration-PLAN.md §4.4). The Meta tab's insights come from the
//  same server, through MetaAPI.swift and MetaCache.swift.
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

    /// The API key, from the Keychain, or nil when none is saved. Only a
    /// server with keys configured needs one.
    static func apiKey() -> String? {
        MetaServerKeychain.read()
    }

    /// Whether the key may go to `url`: over HTTPS, or to this machine. Over
    /// plain HTTP anywhere else, anyone on the way could read it.
    static func canSendKey(to url: URL) -> Bool {
        if url.scheme?.lowercased() == "https" { return true }
        let host = url.host()?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

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
    /// The answer came, but not in a shape this version of the app reads.
    case unreadable
    /// There's an API key, and the address isn't HTTPS: it wasn't sent.
    case insecureKey

    var errorDescription: String? {
        switch self {
        case .http(401): return "The server needs an API key: add yours in Settings, or check it's the right one."
        case .http(let status): return "The server answered HTTP \(status)."
        case .insecureKey:
            return "The API key is only sent over HTTPS, or to this device: use the server's https:// address."
        case .notHTTP: return "The server's answer wasn't HTTP."
        case .unreadable:
            return "The server's answer is in a format this version can't read. Update the app or the server."
        }
    }
}

/// GETs JSON from the server. Short timeouts: a server that's down should
/// fall back to Limitless quickly, not hold Team Search up.
nonisolated struct MetaServerClient: Sendable {
    let baseURL: URL
    var session: URLSession = MetaServerClient.session
    /// Sent as `Authorization: Bearer`, only where `canSendKey(to:)` allows.
    var apiKey: String? = MetaServerSettings.apiKey()

    /// No URL cache. The server says its answers may be reused for 15
    /// minutes, and URLSession's cache did, so Settings' connection test and
    /// Team Search's refresh missed new events for that long. MetaCache is
    /// the app's one cache of the server's answers, and decides when to ask.
    static let session = URLSession(configuration: configuration())

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    /// An answer, or word that the one the app has is still current.
    enum Fetched: Sendable, Equatable {
        case fresh(Data, etag: String?)
        case notModified
    }

    func get<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard case .fresh(let data, _) = try await fetch(components.url!, etag: nil) else {
            throw MetaServerError.http(status: 304)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// GETs `url`, sending `etag` as If-None-Match, so an unchanged answer
    /// comes back as `.notModified` with no body.
    func fetch(_ url: URL, etag: String?) async throws -> Fetched {
        var request = URLRequest(url: url)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let apiKey {
            guard MetaServerSettings.canSendKey(to: url) else { throw MetaServerError.insecureKey }
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MetaServerError.notHTTP }
        if http.statusCode == 304, etag != nil { return .notModified }
        guard (200..<300).contains(http.statusCode) else { throw MetaServerError.http(status: http.statusCode) }
        return .fresh(data, etag: http.value(forHTTPHeaderField: "ETag"))
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
