//
//  MetaCache.swift
//  PKReference
//
//  The server's /v1 answers, kept on disk, and the rule for when to ask the
//  server again (BackendIntegration-PHASE4.md §4.3):
//
//  1. Show what's cached straight away, however old, with its age.
//  2. Ask again when the cached answer is more than 15 minutes old, the
//     server's own max-age, or there's none.
//  3. Always ask when told to (pull to refresh, Test Connection, the switch
//     turned on).
//  4. Send the cached ETag, so an unchanged answer costs a 304.
//  5. When asking fails, keep showing the cached answer, and say why.
//  6. A cached answer that no longer decodes is deleted and asked for again.
//
//  Answers are kept by their full URL, so two servers' answers never mix.
//

import CryptoKit
import Foundation

/// The cached answers: one file each, holding the body as the server sent
/// it, its ETag, and when the app fetched it.
actor MetaCache {
    static let shared = MetaCache()

    /// How long an answer counts as current: the server's `max-age`.
    nonisolated static let maxAge: TimeInterval = 15 * 60

    struct Entry: Codable, Sendable, Equatable {
        let url: String
        let etag: String?
        let fetchedAt: Date
        let body: Data
    }

    /// Bump when the file layout changes; older caches are ignored.
    nonisolated private static let cacheVersion = "v1"

    nonisolated static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "MetaServer", directoryHint: .isDirectory)
    }

    private let directory: URL

    init(directory: URL = MetaCache.defaultDirectory) {
        self.directory = directory.appending(path: Self.cacheVersion, directoryHint: .isDirectory)
    }

    func entry(for url: URL) -> Entry? {
        guard let data = try? Data(contentsOf: file(for: url)),
              let entry = try? PropertyListDecoder().decode(Entry.self, from: data),
              entry.url == url.absoluteString else { return nil }
        return entry
    }

    func store(_ entry: Entry) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let url = URL(string: entry.url), let data = try? encoder.encode(entry) else { return }
        try? data.write(to: file(for: url), options: .atomic)
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: file(for: url))
    }

    /// Deletes every cached answer.
    func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path()) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// Bytes on disk, for Settings.
    func size() -> Int {
        guard let files = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in files {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    private func file(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: name + ".plist")
    }
}

/// An answer and where it stands.
nonisolated struct MetaAnswer<Value: Sendable>: Sendable {
    let value: Value
    /// When the app last got it, or heard from the server that it's current.
    let fetchedAt: Date
    /// Why asking the server failed, when this is the cached answer shown
    /// in its place.
    let refreshError: MetaFailure?
}

/// Why the server couldn't answer, told apart because each is shown
/// differently.
nonisolated enum MetaFailure: Error, Equatable, Sendable {
    /// No connection, a timeout, or nothing listening at the address.
    case unreachable(String)
    /// The server answered with an error.
    case http(status: Int)
    /// The answer came, in a shape this version can't read.
    case unreadable

    init(_ error: any Error) {
        switch error {
        case let failure as MetaFailure: self = failure
        case MetaServerError.http(let status): self = .http(status: status)
        case MetaServerError.unreadable, is DecodingError: self = .unreadable
        default: self = .unreachable(error.localizedDescription)
        }
    }

    var message: String {
        switch self {
        case .unreachable(let reason): return "Couldn't reach the server: \(reason)"
        case .http(let status): return MetaServerError.http(status: status).localizedDescription
        case .unreadable: return MetaServerError.unreadable.localizedDescription
        }
    }
}

/// Reads the server's insights through the cache, by the rule at the top of
/// this file.
nonisolated struct MetaInsights: Sendable {
    let client: MetaServerClient
    var cache: MetaCache = .shared
    var now: @Sendable () -> Date = { Date() }

    init(baseURL: URL, session: URLSession = MetaServerClient.session, cache: MetaCache = .shared,
         now: @escaping @Sendable () -> Date = { Date() }) {
        client = MetaServerClient(baseURL: baseURL, session: session)
        self.cache = cache
        self.now = now
    }

    /// The server from Settings, or nil when the switch is off.
    static func fromSettings(_ defaults: UserDefaults = .standard) -> MetaInsights? {
        MetaServerSettings.baseURL(defaults).map { MetaInsights(baseURL: $0) }
    }

    /// The cached answer, however old, without asking the server (rule 1).
    /// nil when there's none, or it no longer decodes (rule 6).
    func cached<T>(_ endpoint: MetaAPI.Endpoint<T>) async -> MetaAnswer<T>? {
        let url = endpoint.url(on: client.baseURL)
        guard let entry = await cache.entry(for: url) else { return nil }
        guard let value = try? MetaAPI.decode(T.self, from: entry.body) else {
            await cache.remove(url)
            return nil
        }
        return MetaAnswer(value: value, fetchedAt: entry.fetchedAt, refreshError: nil)
    }

    /// The answer, from the cache while it's current and from the server
    /// otherwise, or always from the server when `force`d (rules 2 to 5).
    /// Throws only when the server can't answer and nothing is cached.
    func load<T>(_ endpoint: MetaAPI.Endpoint<T>, force: Bool = false) async throws(MetaFailure) -> MetaAnswer<T> {
        let url = endpoint.url(on: client.baseURL)
        let cached = await cached(endpoint)
        let entry = cached == nil ? nil : await cache.entry(for: url)
        if !force, let cached, now().timeIntervalSince(cached.fetchedAt) < MetaCache.maxAge {
            return cached
        }
        do {
            switch try await client.fetch(url, etag: entry?.etag) {
            case .notModified:
                guard let cached, let entry else { throw MetaFailure.unreadable }
                let fetchedAt = now()
                await cache.store(MetaCache.Entry(url: entry.url, etag: entry.etag, fetchedAt: fetchedAt,
                                                  body: entry.body))
                return MetaAnswer(value: cached.value, fetchedAt: fetchedAt, refreshError: nil)
            case .fresh(let body, let etag):
                guard let value = try? MetaAPI.decode(T.self, from: body) else { throw MetaFailure.unreadable }
                let fetchedAt = now()
                await cache.store(MetaCache.Entry(url: url.absoluteString, etag: etag, fetchedAt: fetchedAt,
                                                  body: body))
                return MetaAnswer(value: value, fetchedAt: fetchedAt, refreshError: nil)
            }
        } catch {
            let failure = MetaFailure(error)
            guard let cached else { throw failure }
            return MetaAnswer(value: cached.value, fetchedAt: cached.fetchedAt, refreshError: failure)
        }
    }
}
