//
//  MetaServerKeyTests.swift
//  PKReferenceTests
//
//  The PK Reference server's API key in the app: kept in the Keychain, sent
//  as `Authorization: Bearer` only over HTTPS or to this device, and a
//  refusal said plainly. The backend's ApiKeyFilterTest checks the server.
//

import Testing
import Foundation
@testable import PKReference

/// Records the requests it gets, and answers each with `status`.
final class MetaServerKeyStubProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var status = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                                              httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"formats":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct MetaServerKeyTests {
    private let key = "pkr_test-key-only-for-tests"

    private func client(_ address: String, key: String?) -> MetaServerClient {
        let configuration = MetaServerClient.configuration()
        configuration.protocolClasses = [MetaServerKeyStubProtocol.self]
        var client = MetaServerClient(baseURL: URL(string: address)!, session: URLSession(configuration: configuration))
        client.apiKey = key
        MetaServerKeyStubProtocol.requests = []
        MetaServerKeyStubProtocol.status = 200
        return client
    }

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

    @Test func sendsTheKeyOverHTTPS() async throws {
        let client = client("https://my-mac.tailnet.ts.net", key: key)
        _ = try await client.fetch(MetaAPI.formats.url(on: client.baseURL), etag: nil)
        #expect(MetaServerKeyStubProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
        #expect(MetaServerKeyStubProtocol.requests.first?.url?.query() == nil, "never in the URL")
    }

    @Test func keepsTheKeyOffPlainHTTP() async throws {
        let client = client("http://192.168.1.20:8080", key: key)
        await #expect(throws: MetaServerError.insecureKey) {
            try await client.fetch(MetaAPI.formats.url(on: client.baseURL), etag: nil)
        }
        #expect(MetaServerKeyStubProtocol.requests.isEmpty, "nothing was sent")
        #expect(MetaFailure(MetaServerError.insecureKey) == .insecureKey)

        // Without a key, plain HTTP is as before.
        let open = self.client("http://192.168.1.20:8080", key: nil)
        _ = try await open.fetch(MetaAPI.formats.url(on: open.baseURL), etag: nil)
        #expect(MetaServerKeyStubProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)

        // This device gets it over HTTP.
        let local = self.client("http://localhost:8080", key: key)
        _ = try await local.fetch(MetaAPI.formats.url(on: local.baseURL), etag: nil)
        #expect(MetaServerKeyStubProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
    }

    @Test func aRefusedKeySaysSo() async {
        let client = client("https://my-mac.tailnet.ts.net", key: "pkr_wrong")
        MetaServerKeyStubProtocol.status = 401
        await #expect(throws: MetaServerError.http(status: 401)) {
            try await client.fetch(MetaAPI.formats.url(on: client.baseURL), etag: nil)
        }
        #expect(MetaFailure.http(status: 401).message
                == "The server needs an API key: add yours in Settings, or check it's the right one.")
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
