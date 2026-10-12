//
//  MetaServerTokens.swift
//  PKReference
//
//  The PK Reference server's access tokens. A server that needs signing in
//  takes the API key only at POST /v1/auth/token, and answers with a token
//  (a JWT) good for about 15 minutes; every other request carries the token.
//  So the long-lived key, which is in the Keychain, travels once every few
//  minutes rather than with every request, and a token that leaks stops
//  working by itself.
//
//  Tokens are kept in memory only: they're short-lived, and the key gets
//  another whenever the app starts. The app never reads what's inside one;
//  the server's "expires in" says how long it's good for, measured on this
//  device's clock, so a device and a server whose clocks disagree still agree
//  on that.
//

import CryptoKit
import Foundation

actor MetaServerTokens {
    static let shared = MetaServerTokens()

    /// A token is replaced this long before it runs out, so a request that
    /// starts with it doesn't arrive after it has.
    static let margin: TimeInterval = 60
    static let path = "v1/auth/token"

    private struct Token {
        let value: String
        let expires: Date
    }

    /// The server's answer to a token request.
    private struct Answer: Decodable {
        let token: String
        let expiresIn: Double
    }

    private var tokens: [String: Token] = [:]
    /// The requests under way, so several callers at once share one.
    private var pending: [String: Task<Token, any Error>] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// A token for `server`, traded for `apiKey` unless one in hand is still
    /// good. Throws `MetaServerError.http(status: 401)` when the server
    /// doesn't accept the key.
    func token(server: URL, apiKey: String, session: URLSession) async throws -> String {
        let id = Self.id(server, apiKey)
        if let held = tokens[id], held.expires.timeIntervalSince(now()) > Self.margin {
            return held.value
        }
        if let underway = pending[id] { return try await underway.value.value }
        let now = now
        let request = Task { try await Self.trade(apiKey, at: server, session: session, now: now) }
        pending[id] = request
        defer { pending[id] = nil }
        let token = try await request.value
        tokens[id] = token
        return token.value
    }

    /// Drops the token in hand, after the server refused it: it ran out
    /// early, or the server restarted and no longer knows it.
    func forget(server: URL, apiKey: String) {
        tokens[Self.id(server, apiKey)] = nil
    }

    private static func trade(_ apiKey: String, at server: URL, session: URLSession,
                              now: @Sendable () -> Date) async throws -> Token {
        let url = server.appending(path: path)
        guard MetaServerSettings.canSendKey(to: url) else { throw MetaServerError.insecureKey }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MetaServerError.notHTTP }
        // A server from before tokens has no such path.
        if http.statusCode == 404 { throw MetaServerError.unreadable }
        guard (200..<300).contains(http.statusCode) else { throw MetaServerError.http(status: http.statusCode) }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data), !answer.token.isEmpty else {
            throw MetaServerError.unreadable
        }
        return Token(value: answer.token, expires: now().addingTimeInterval(answer.expiresIn))
    }

    /// One server and one key: the key by its hash, so it isn't kept again here.
    private static func id(_ server: URL, _ apiKey: String) -> String {
        let hash = SHA256.hash(data: Data(apiKey.utf8)).map { String(format: "%02x", $0) }.joined()
        return server.absoluteString + "|" + hash
    }
}
