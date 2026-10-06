//
//  MetaInsightsTests.swift
//  PKReferenceTests
//
//  The PK Reference server's /v1 insights: reading its real answers (saved
//  once from a running server, in MetaFixtures/), the cache's rule for when
//  to ask again, the connection test that showed stale counts, and naming
//  the server's species keys.
//

import Testing
import Foundation
@testable import PKReference

/// A server whose answers the test sets, with ETags and the server's own
/// Cache-Control, that counts what it's asked.
final class MetaInsightsStubProtocol: URLProtocol {
    struct Answer {
        var status = 200
        var body = Data()
        var etag: String?
    }

    nonisolated(unsafe) static var answer = Answer()
    /// Fails every request as if nothing were listening.
    nonisolated(unsafe) static var unreachable = false
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        if Self.unreachable {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        var answer = Self.answer
        if let etag = answer.etag, request.value(forHTTPHeaderField: "If-None-Match") == etag {
            answer.status = 304
            answer.body = Data()
        }
        var headers = ["Content-Type": "application/json", "Cache-Control": "max-age=900, public"]
        headers["ETag"] = answer.etag
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: answer.status,
                                                              httpVersion: "HTTP/1.1", headerFields: headers)!,
                            cacheStoragePolicy: .allowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A clock the test moves.
private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
}

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "MetaFixtures/\(name).json"))
}

private func formats(_ events: Int) -> Data {
    Data("""
        {"generatedAt":"2026-10-06T17:25:46.644643Z","formats":[{"format":"M-C","events":\(events),"teams":\(events * 50),
         "firstEvent":"2026-09-30T12:30:00Z","lastEvent":"2026-10-05T23:30:00Z","lastFetched":"2026-10-06T17:23:04.270436Z"}]}
        """.utf8)
}

@Suite(.serialized)
struct MetaInsightsTests {
    private let base = URL(string: "http://localhost:8080")!
    private let clock = TestClock()
    private let cacheDirectory = URL.temporaryDirectory.appending(path: "MetaInsightsTests-\(UUID().uuidString)")

    private var session: URLSession {
        let configuration = MetaServerClient.configuration()
        configuration.protocolClasses = [MetaInsightsStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func insights(cache: MetaCache? = nil) -> MetaInsights {
        let clock = clock
        return MetaInsights(baseURL: base, session: session, cache: cache ?? MetaCache(directory: cacheDirectory),
                            now: { clock.now })
    }

    private func reset(_ answer: MetaInsightsStubProtocol.Answer) {
        MetaInsightsStubProtocol.answer = answer
        MetaInsightsStubProtocol.unreachable = false
        MetaInsightsStubProtocol.requests = []
    }

    // MARK: Reading the server's answers

    @Test func readsTheServersAnswers() throws {
        let formats = try MetaAPI.decode(MetaAPI.Formats.self, from: fixture("formats"))
        let mc = try #require(formats.formats.first { $0.format == "M-C" })
        #expect(mc.events > 0 && mc.teams > 0)
        #expect(mc.lastEvent != nil, "a date without fractional seconds")
        #expect(mc.lastFetched != nil, "a date with them")

        let list = try MetaAPI.decode(MetaAPI.PokemonList.self, from: fixture("pokemon-M-C-30d"))
        #expect(list.window == "30d")
        #expect(list.sample.teams > 0 && list.sample.topCutTeams <= list.sample.teams)
        #expect(list.pokemon.count > 100)
        let top = try #require(list.pokemon.first)
        #expect(top.usage > 0 && top.usage <= 1)
        #expect(top.record?.winRate != nil)
        #expect(list.pokemon.contains { $0.record != nil && $0.record?.winRate == nil },
                "under 30 matches, no rate")

        let detail = try MetaAPI.decode(MetaAPI.PokemonDetail.self, from: fixture("pokemon-M-C-rillaboom-30d"))
        #expect(detail.key == "rillaboom")
        #expect(!detail.sets.isEmpty && detail.sets[0].moves.count == 4)
        #expect(!detail.items.isEmpty && !detail.teammates.isEmpty && !detail.weekly.isEmpty)

        let cores = try MetaAPI.decode(MetaAPI.Cores.self, from: fixture("cores-M-C-30d"))
        #expect(cores.pairs.allSatisfy { $0.members.count == 2 })
        #expect(cores.trios.allSatisfy { $0.members.count == 3 })

        let archetypes = try MetaAPI.decode(MetaAPI.Archetypes.self, from: fixture("archetypes-M-C-30d"))
        #expect(!archetypes.archetypes.isEmpty)
        #expect(archetypes.archetypes.allSatisfy { $0.core.count == 4 })
        #expect(Set(archetypes.archetypes.map(\.id)).count == archetypes.archetypes.count)
    }

    /// What a newer server might leave out doesn't stop the app reading it.
    @Test func toleratesMissingExtras() throws {
        let detail = try MetaAPI.decode(MetaAPI.PokemonDetail.self, from: Data("""
            {"format":"M-C","key":"rillaboom","window":"30d","sample":{"events":1,"teams":2,"topCutTeams":0}}
            """.utf8))
        #expect(detail.usage == nil && detail.sets.isEmpty && detail.weekly.isEmpty)
        #expect(throws: DecodingError.self) {
            try MetaAPI.decode(MetaAPI.PokemonList.self, from: Data(#"{"format":"M-C"}"#.utf8))
        }
    }

    @Test func endpoints() {
        #expect(MetaAPI.pokemon(format: "M-C", window: .days14).url(on: base).absoluteString
                == "http://localhost:8080/v1/formats/M-C/pokemon?window=14d")
        #expect(MetaAPI.pokemon(format: "M-C", key: "arcanine:hisui", window: .regulation).url(on: base).path()
                == "/v1/formats/M-C/pokemon/arcanine:hisui")
        #expect(MetaAPI.formats.url(on: base).absoluteString == "http://localhost:8080/v1/formats")
    }

    // MARK: The cache's rule

    @Test func cachedAnswersAndWhenToAskAgain() async throws {
        reset(.init(body: formats(10), etag: #"W/"one""#))
        let insights = insights()

        #expect(await insights.cached(MetaAPI.formats) == nil)
        let first = try await insights.load(MetaAPI.formats)
        #expect(first.value.formats[0].events == 10)
        #expect(MetaInsightsStubProtocol.requests.count == 1)

        // Current: no request.
        clock.now += 14 * 60
        _ = try await insights.load(MetaAPI.formats)
        #expect(MetaInsightsStubProtocol.requests.count == 1)
        #expect(await insights.cached(MetaAPI.formats)?.value.formats[0].events == 10)

        // Old: asked, with the ETag; unchanged, so a 304 keeps the answer and
        // makes it current again.
        clock.now += 2 * 60
        let revalidated = try await insights.load(MetaAPI.formats)
        #expect(MetaInsightsStubProtocol.requests.count == 2)
        #expect(MetaInsightsStubProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match") == #"W/"one""#)
        #expect(revalidated.value.formats[0].events == 10 && revalidated.fetchedAt == clock.now)
        #expect(revalidated.refreshError == nil)

        // Forced: asked even though current, and a changed answer replaces it.
        MetaInsightsStubProtocol.answer = .init(body: formats(12), etag: #"W/"two""#)
        let forced = try await insights.load(MetaAPI.formats, force: true)
        #expect(MetaInsightsStubProtocol.requests.count == 3)
        #expect(forced.value.formats[0].events == 12)
        #expect(await insights.cached(MetaAPI.formats)?.value.formats[0].events == 12)
    }

    @Test func failingToAsk() async throws {
        reset(.init(body: formats(10)))
        let insights = insights()

        MetaInsightsStubProtocol.unreachable = true
        let failure = await #expect(throws: MetaFailure.self) {
            try await insights.load(MetaAPI.formats)
        }
        if case .unreachable? = failure {} else { Issue.record("\(String(describing: failure))") }

        // With a cached answer, it's shown, and says why it's old.
        MetaInsightsStubProtocol.unreachable = false
        _ = try await insights.load(MetaAPI.formats)
        MetaInsightsStubProtocol.unreachable = true
        let offline = try await insights.load(MetaAPI.formats, force: true)
        #expect(offline.value.formats[0].events == 10)
        if case .unreachable = offline.refreshError {} else { Issue.record("\(String(describing: offline.refreshError))") }

        MetaInsightsStubProtocol.unreachable = false
        MetaInsightsStubProtocol.answer = .init(status: 503, body: Data("{}".utf8))
        #expect(try await insights.load(MetaAPI.formats, force: true).refreshError == .http(status: 503))

        // An answer this version can't read isn't kept.
        MetaInsightsStubProtocol.answer = .init(body: Data(#"{"formats":"soon"}"#.utf8))
        #expect(try await insights.load(MetaAPI.formats, force: true).refreshError == .unreadable)
        #expect(await insights.cached(MetaAPI.formats)?.value.formats[0].events == 10)
    }

    /// A cached answer an older version wrote, which this one can't read, is
    /// thrown away and asked for again.
    @Test func anOldCachedAnswer() async throws {
        reset(.init(body: formats(10)))
        let cache = MetaCache(directory: cacheDirectory)
        let url = MetaAPI.formats.url(on: base)
        await cache.store(.init(url: url.absoluteString, etag: #"W/"old""#, fetchedAt: clock.now,
                                body: Data(#"{"version":0}"#.utf8)))
        let insights = insights(cache: cache)
        #expect(await insights.cached(MetaAPI.formats) == nil)
        #expect(await cache.entry(for: url) == nil)
        #expect(try await insights.load(MetaAPI.formats).value.formats[0].events == 10)
        #expect(MetaInsightsStubProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    /// Answers are kept by server, so another address asks its own server.
    @Test func anotherServer() async throws {
        reset(.init(body: formats(10)))
        let cache = MetaCache(directory: cacheDirectory)
        _ = try await insights(cache: cache).load(MetaAPI.formats)
        let other = MetaInsights(baseURL: URL(string: "http://192.168.1.20:8080")!, session: session, cache: cache,
                                 now: { [clock] in clock.now })
        #expect(await other.cached(MetaAPI.formats) == nil)
        _ = try await other.load(MetaAPI.formats)
        #expect(MetaInsightsStubProtocol.requests.count == 2)
        #expect(MetaInsightsStubProtocol.requests.last?.url?.host() == "192.168.1.20")
    }

    @Test func clearing() async throws {
        reset(.init(body: formats(10)))
        let cache = MetaCache(directory: cacheDirectory)
        _ = try await insights(cache: cache).load(MetaAPI.formats)
        #expect(await cache.size() > 0)
        try await cache.clear()
        #expect(await cache.size() == 0)
        #expect(await insights(cache: cache).cached(MetaAPI.formats) == nil)
    }

    /// Settings' Test Connection showed old counts: the client's URLSession
    /// kept the server's answers for their 15-minute Cache-Control. Asking
    /// twice must reach the server twice and see the new answer. URLSession
    /// doesn't cache a stub protocol's answers, so the stub can't show the
    /// old behavior; the check on the configuration is what fails without
    /// the fix (checked against a real server when it was made).
    @Test func theConnectionTestIsNeverStale() async throws {
        reset(.init(body: formats(10)))
        let client = MetaServerClient(baseURL: base, session: session)
        let url = MetaAPI.formats.url(on: base)
        guard case .fresh(let first, _) = try await client.fetch(url, etag: nil) else { Issue.record(); return }
        #expect(try MetaAPI.decode(MetaAPI.Formats.self, from: first).formats[0].events == 10)

        MetaInsightsStubProtocol.answer = .init(body: formats(12))
        guard case .fresh(let second, _) = try await client.fetch(url, etag: nil) else { Issue.record(); return }
        #expect(try MetaAPI.decode(MetaAPI.Formats.self, from: second).formats[0].events == 12)
        #expect(MetaInsightsStubProtocol.requests.count == 2)
        #expect(MetaServerClient.configuration().urlCache == nil)
    }

    // MARK: Species keys

    /// Every key the backend makes for a species in the regulation names
    /// that species, and reads back as the same key.
    @Test func namesTheServersSpeciesKeys() throws {
        struct Golden: Decodable {
            let cases: [Case]
            struct Case: Decodable { let format: String; let key: String }
        }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "backend/src/test/resources/golden/species-identity.json")
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
        var vocabularies: [ChampionsRegulation: TeamSearchVocabulary] = [:]
        var named = 0
        for c in golden.cases {
            guard let regulation = ChampionsRegulation(rawValue: c.format.lowercased()) else { continue }
            let vocabulary = try vocabularies[regulation] ?? TeamSearchVocabulary.bundled(for: regulation)
            vocabularies[regulation] = vocabulary
            let speciesID = String(c.key.split(separator: ":")[0])
            guard vocabulary.speciesByID[speciesID] != nil else {
                #expect(vocabulary.species(forKey: c.key) == nil, "\(c.key) is outside \(c.format)")
                continue
            }
            let term = try #require(vocabulary.species(forKey: c.key), "\(c.format) \(c.key)")
            #expect(vocabulary.identity(name: term.displayName, slug: nil).key == c.key,
                    "\(c.key) → \(term.displayName)")
            named += 1
        }
        #expect(named > 100)

        let vocabulary = try TeamSearchVocabulary.bundled(for: .mC)
        #expect(vocabulary.species(forKey: "arcanine:hisui")?.displayName == "Arcanine (Hisui)")
        #expect(vocabulary.species(forKey: "rillaboom")?.displayName == "Rillaboom")
        #expect(vocabulary.species(forKey: "rillaboom:galar") == nil)
        #expect(vocabulary.species(forKey: "notapokemon") == nil)
    }
}
