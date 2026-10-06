//
//  MetaServerTests.swift
//  PKReferenceTests
//
//  The PK Reference server as Team Search's corpus source: the switch, the
//  address, the fallback to Limitless, and the server's two calls. The
//  backend's CorpusRepositoryTest checks the other side: that it answers in
//  Limitless's shapes.
//

import Testing
import Foundation
@testable import PKReference

/// Answers requests from a table of paths, and records them.
final class MetaServerStubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, Data)] = [:]
    nonisolated(unsafe) static var requested: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requested.append(url)
        let (status, data) = Self.responses[url.path()] ?? (404, Data("{}".utf8))
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                              headerFields: ["Content-Type": "application/json"])!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A corpus source with canned answers, or a failure.
private struct CannedFetcher: TeamCorpusFetching {
    var tournaments: [LimitlessTournament] = []
    var fails = false

    func tournaments(format: String, page: Int, limit: Int) async throws -> [LimitlessTournament] {
        if fails { throw MetaServerError.http(status: 503) }
        return tournaments
    }

    func standings(tournamentID: String) async throws -> [LimitlessStanding] {
        if fails { throw MetaServerError.http(status: 503) }
        return []
    }
}

private func tournament(_ id: String) -> LimitlessTournament {
    LimitlessTournament(id: id, name: id, game: "VGC", format: "M-C", date: "2026-10-05T18:00:00.000Z", players: 40)
}

@Suite(.serialized)
struct MetaServerTests {
    @Test func addresses() {
        #expect(MetaServerSettings.url(from: "http://localhost:8080")?.absoluteString == "http://localhost:8080")
        #expect(MetaServerSettings.url(from: "localhost:8080/")?.absoluteString == "http://localhost:8080")
        #expect(MetaServerSettings.url(from: " https://pk.example.com ")?.absoluteString == "https://pk.example.com")
        #expect(MetaServerSettings.url(from: "192.168.1.20:8080")?.absoluteString == "http://192.168.1.20:8080")
        #expect(MetaServerSettings.url(from: "") == nil)
        #expect(MetaServerSettings.url(from: "ftp://localhost") == nil)
    }

    @Test func theSwitch() throws {
        let suite = "MetaServerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(MetaServerSettings.baseURL(defaults) == nil, "off by default")
        defaults.set(true, forKey: MetaServerSettings.enabledKey)
        #expect(MetaServerSettings.baseURL(defaults)?.absoluteString == "http://localhost:8080")
        defaults.set("not a url at all", forKey: MetaServerSettings.addressKey)
        #expect(MetaServerSettings.baseURL(defaults) == nil)
    }

    @Test func usesTheServerAndFallsBack() async throws {
        let url = URL(string: "http://localhost:8080")!
        let limitless = CannedFetcher(tournaments: [tournament("from-limitless")])

        let on = PreferredCorpusFetcher(serverURL: { url },
                                        server: { _ in CannedFetcher(tournaments: [tournament("from-server")]) },
                                        limitless: limitless)
        #expect(try await on.tournaments(format: "M-C", page: 1, limit: 50).map(\.id) == ["from-server"])

        let down = PreferredCorpusFetcher(serverURL: { url }, server: { _ in CannedFetcher(fails: true) },
                                          limitless: limitless)
        #expect(try await down.tournaments(format: "M-C", page: 1, limit: 50).map(\.id) == ["from-limitless"])

        let off = PreferredCorpusFetcher(serverURL: { nil },
                                         server: { _ in CannedFetcher(tournaments: [tournament("from-server")]) },
                                         limitless: limitless)
        #expect(try await off.tournaments(format: "M-C", page: 1, limit: 50).map(\.id) == ["from-limitless"])
    }

    /// The server's two calls, and what it sends: Limitless's shapes, with
    /// no deck label.
    @Test func theServersCalls() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MetaServerStubProtocol.self]
        let client = MetaServerClient(baseURL: URL(string: "http://localhost:8080")!,
                                      session: URLSession(configuration: configuration))
        MetaServerStubProtocol.requested = []
        MetaServerStubProtocol.responses = [
            "/v1/formats/M-C/tournaments": (200, Data("""
                [{"id":"e1","name":"Test Event","game":"VGC","format":"M-C","date":"2026-10-05T18:00:00.000Z","players":83}]
                """.utf8)),
            "/v1/tournaments/e1/standings": (200, Data("""
                [{"player":"p1","name":"Player 01","country":"JP","placing":1,"record":{"wins":8,"losses":2,"ties":0},
                  "deck":null,"decklist":[{"name":"Grimmsnarl","id":"grimmsnarl","item":"Light Clay","ability":"Prankster",
                  "attacks":["Reflect","Light Screen","Spirit Break","Parting Shot"],"nature":"Careful","tera":"Dark"}],"drop":null},
                 {"player":"p2","name":"Player 02","country":null,"placing":null,"record":null,"deck":null,"decklist":null,"drop":1}]
                """.utf8)),
        ]
        let server = ServerCorpusFetcher(client: client)

        let list = try await server.tournaments(format: "M-C", page: 2, limit: 50)
        #expect(list.map(\.id) == ["e1"])
        #expect(list.first?.parsedDate != nil)
        let query = MetaServerStubProtocol.requested.first.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        #expect(query?.queryItems?.contains(URLQueryItem(name: "page", value: "2")) == true)

        let standings = try await server.standings(tournamentID: "e1")
        #expect(standings.count == 2)
        #expect(standings[0].decklist?.first?.limitlessID == "grimmsnarl")
        #expect(standings[0].decklist?.first?.attacks?.count == 4)
        #expect(standings[1].placing == nil && standings[1].drop == 1)

        await #expect(throws: MetaServerError.http(status: 404)) {
            try await server.standings(tournamentID: "missing")
        }
    }
}
