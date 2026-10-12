//
//  MetaServerKeyTests.swift
//  PKReferenceTests
//
//  Signing in to the PK Reference server from the app: the API key, kept in
//  the Keychain, is traded for an access token, and the token is what
//  requests carry; both go only over HTTPS or to this device. The backend's
//  ApiAuthFilterTest and TokenServiceTest check the server.
//

import Testing
import Foundation
@testable import PKReference

/// A server that signs in as the real one does: POST /v1/auth/token gives a
/// token for the right key, and anything else needs the newest token.
final class MetaServerKeyStubProtocol: URLProtocol {
    /// What the stub has seen and will answer. Requests come in on other
    /// threads, so every use is under the lock.
    struct State {
        var key = "pkr_test-key-only-for-tests"
        var expiresIn = 900
        /// When false, the token path answers 404, as a server from before tokens does.
        var givesTokens = true
        /// Tokens given out so far: the newest is "token-<count>", and the only one accepted.
        var given = 0
        var requests: [URLRequest] = []

        var trades: [URLRequest] { requests.filter { $0.url?.path() == "/v1/auth/token" } }
        var data: [URLRequest] { requests.filter { $0.url?.path() != "/v1/auth/token" } }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()

    static func with<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let (status, body): (Int, String) = Self.with { state in
            state.requests.append(request)
            if request.url?.path() == "/v1/auth/token" {
                guard state.givesTokens else { return (404, "{}") }
                guard request.httpMethod == "POST", authorization == "Bearer \(state.key)" else {
                    return (401, #"{"error":"no","code":"invalid_key"}"#)
                }
                state.given += 1
                return (200, #"{"token":"token-\#(state.given)","tokenType":"Bearer","expiresIn":\#(state.expiresIn)}"#)
            }
            guard state.given > 0, authorization == "Bearer token-\(state.given)" else {
                return (401, #"{"error":"no","code":"invalid_token"}"#)
            }
            return (200, #"{"formats":[]}"#)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                                              httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A clock the test moves.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_791_288_000)
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date += seconds } }
}

@Suite(.serialized)
struct MetaServerKeyTests {
    private let key = "pkr_test-key-only-for-tests"
    private let clock = TestClock()

    /// A client for `address`, with its own tokens and a fresh server.
    private func client(_ address: String, key: String?) -> MetaServerClient {
        let configuration = MetaServerClient.configuration()
        configuration.protocolClasses = [MetaServerKeyStubProtocol.self]
        var client = MetaServerClient(baseURL: URL(string: address)!, session: URLSession(configuration: configuration))
        client.apiKey = key
        client.tokens = MetaServerTokens(now: { [clock] in clock.now })
        MetaServerKeyStubProtocol.with { $0 = .init() }
        return client
    }

    private func fetch(_ client: MetaServerClient) async throws {
        _ = try await client.fetch(MetaAPI.formats.url(on: client.baseURL), etag: nil)
    }

    private var server: MetaServerKeyStubProtocol.State { MetaServerKeyStubProtocol.with { $0 } }

    @Test func whereTheKeyMayGo() {
        func allowed(_ address: String) -> Bool { MetaServerSettings.canSendKey(to: URL(string: address)!) }
        #expect(allowed("https://my-mac.tailnet.ts.net/v1/formats"))
        #expect(allowed("https://192.168.1.20:8443/v1/formats"))
        #expect(allowed("http://localhost:8080/v1/formats"))
        #expect(allowed("http://127.0.0.1:8080/v1/formats"))
        #expect(allowed("http://[::1]:8080/v1/formats"))
        #expect(!allowed("http://192.168.1.20:8080/v1/formats"), "plain HTTP over a network")
        #expect(!allowed("http://my-mac.tailnet.ts.net/v1/formats"))
        #expect(!allowed("http://localhost.example.com/v1/formats"))
    }

    /// The key goes to the token request, once; everything else carries the token.
    @Test func tradesTheKeyForATokenOnce() async throws {
        let client = client("https://my-mac.tailnet.ts.net", key: key)
        try await fetch(client)
        try await fetch(client)
        try await fetch(client)

        #expect(server.trades.count == 1)
        #expect(server.trades[0].httpMethod == "POST")
        #expect(server.trades[0].value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
        #expect(server.data.count == 3)
        #expect(server.data.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token-1" })
        #expect(server.requests.allSatisfy { $0.url?.query() == nil }, "neither is ever in the URL")
    }

    /// A token is replaced a minute before it runs out, not before.
    @Test func getsANewTokenBeforeTheOldOneRunsOut() async throws {
        let client = client("https://my-mac.tailnet.ts.net", key: key)
        try await fetch(client)
        clock.advance(13 * 60)
        try await fetch(client)
        #expect(server.trades.count == 1, "13 of its 15 minutes in, it's still good")

        clock.advance(90)
        try await fetch(client)
        #expect(server.trades.count == 2, "within a minute of running out")
        #expect(server.data.last?.value(forHTTPHeaderField: "Authorization") == "Bearer token-2")
    }

    /// The server restarted, or the token ran out early: one new token, one more try.
    @Test func aRefusedTokenIsReplacedAndTheRequestSentAgain() async throws {
        let client = client("https://my-mac.tailnet.ts.net", key: key)
        try await fetch(client)
        // The server forgets the token it gave, as a restart does.
        MetaServerKeyStubProtocol.with { $0.given += 1 }
        try await fetch(client)

        #expect(server.trades.count == 2)
        #expect(server.data.map { $0.value(forHTTPHeaderField: "Authorization") }
                == ["Bearer token-1", "Bearer token-1", "Bearer token-3"], "refused, then sent again")
    }

    /// Several requests at once share one trade.
    @Test func requestsAtOnceShareOneToken() async throws {
        let client = client("https://my-mac.tailnet.ts.net", key: key)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { try await fetch(client) } }
            try await group.waitForAll()
        }
        #expect(server.trades.count == 1)
        #expect(server.data.count == 8)
    }

    @Test func aRefusedKeySaysSo() async {
        let client = client("https://my-mac.tailnet.ts.net", key: "pkr_wrong")
        await #expect(throws: MetaServerError.http(status: 401)) { try await fetch(client) }
        #expect(server.trades.count == 1)
        #expect(server.data.isEmpty, "nothing is asked for without a token")
        #expect(MetaFailure.http(status: 401).message
                == "The server needs an API key: add yours in Settings, or check it's the right one.")
    }

    /// A server from before tokens has no token request to answer.
    @Test func aServerWithoutTokens() async {
        let client = client("https://my-mac.tailnet.ts.net", key: key)
        MetaServerKeyStubProtocol.with { $0.givesTokens = false }
        await #expect(throws: MetaServerError.unreadable) { try await fetch(client) }
        #expect(server.data.isEmpty)
    }

    @Test func keepsTheKeyAndTokenOffPlainHTTP() async throws {
        let lan = client("http://192.168.1.20:8080", key: key)
        await #expect(throws: MetaServerError.insecureKey) { try await fetch(lan) }
        #expect(server.requests.isEmpty, "nothing was sent, not even the token request")
        #expect(MetaFailure(MetaServerError.insecureKey) == .insecureKey)

        // Without a key, plain HTTP is as before: no token request, no header.
        let open = client("http://192.168.1.20:8080", key: nil)
        MetaServerKeyStubProtocol.with { $0.given = 1 }
        await #expect(throws: MetaServerError.http(status: 401)) { try await fetch(open) }
        #expect(server.trades.isEmpty)
        #expect(server.data.first?.value(forHTTPHeaderField: "Authorization") == nil)

        // This device gets both over HTTP.
        let local = client("http://localhost:8080", key: key)
        try await fetch(local)
        #expect(server.trades.count == 1 && server.data.count == 1)
    }

    @Test func theKeychain() {
        let account = "test-\(UUID().uuidString)"
        defer { MetaServerKeychain.remove(account: account) }
        #expect(MetaServerKeychain.read(account: account) == nil)
        #expect(MetaServerKeychain.save("  \(key)\n", account: account))
        #expect(MetaServerKeychain.read(account: account) == key, "trimmed")
        #expect(MetaServerKeychain.save("pkr_another", account: account))
        #expect(MetaServerKeychain.read(account: account) == "pkr_another", "replaced")
        #expect(MetaServerKeychain.save("", account: account))
        #expect(MetaServerKeychain.read(account: account) == nil, "a blank key removes it")
        #expect(MetaServerKeychain.remove(account: account), "removing nothing is fine")
    }
}
