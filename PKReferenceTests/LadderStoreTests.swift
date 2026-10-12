//
//  LadderStoreTests.swift
//  PKReferenceTests
//
//  Where a ladder's record comes from (LadderStore): the PK Reference
//  server's /v1/ladder, read through its cache, and otherwise the device's
//  own reduction of Smogon's files. The server's answers in MetaFixtures/
//  were saved once from a running server (ladder.json whole; the M-B record
//  cut down to five Pokémon).
//

import Testing
import Foundation
@testable import PKReference

/// A server answering by path, that counts what it's asked.
final class LadderStubProtocol: URLProtocol {
    struct State {
        /// Path (with its query) to the answer; anything else is a 404.
        var answers: [String: (status: Int, body: Data)] = [:]
        var unreachable = false
        var requests: [String] = []
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
        let url = request.url!
        let path = url.path() + (url.query().map { "?" + $0 } ?? "")
        let (unreachable, answer) = Self.with { state in
            state.requests.append(path)
            return (state.unreachable, state.answers[path])
        }
        if unreachable {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: answer?.status ?? 404,
                                                              httpVersion: "HTTP/1.1",
                                                              headerFields: ["Content-Type": "application/json"])!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer?.body ?? Data(#"{"error":"not here"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// One month of M-B doubles at 1760 on smogon.com, counting downloads.
private actor CountingSmogon: SmogonFetching {
    private(set) var downloads = 0
    var offline = false

    func months() async throws -> [String] {
        if offline { throw URLError(.notConnectedToInternet) }
        return ["2026-08"]
    }

    func chaosFiles(month: String) async throws -> [SmogonFile] {
        [SmogonFile(name: "gen9championsvgc2026regmb-1760.json", bytes: 4_661_000)]
    }

    func chaos(month: String, file: String) async throws -> Data {
        downloads += 1
        return Data(TeamSearchFixtures.smogonChaosJSON.utf8)
    }

    func leads(month: String, file: String) async throws -> String? { nil }

    func setOffline(_ value: Bool) { offline = value }
}

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "MetaFixtures/\(name).json"))
}

@Suite(.serialized)
struct LadderStoreTests {
    private let base = URL(string: "http://localhost:8080")!
    private let directory = URL.temporaryDirectory.appending(path: "LadderStoreTests-\(UUID().uuidString)")
    private let smogon = CountingSmogon()
    private static let mbPath = "/v1/ladder/gen9championsvgc2026regmb?rating=1760&month=2026-09"
    private static let mb = LadderRequest.teamSearch(.mB)

    /// A store on a fresh server and a fresh device; `serverOn` is Settings' switch.
    private func store(serverOn: Bool = true) -> LadderStore {
        LadderStubProtocol.with { $0 = .init() }
        let configuration = MetaServerClient.configuration()
        configuration.protocolClasses = [LadderStubProtocol.self]
        let session = URLSession(configuration: configuration)
        let cache = MetaCache(directory: directory.appending(path: "server"))
        let base = base
        return LadderStore(
            serverURL: { serverOn ? base : nil },
            insights: { MetaInsights(baseURL: $0, session: session, cache: cache) },
            device: SmogonLadderStore(fetcher: smogon, directory: directory.appending(path: "smogon"),
                                      now: { TeamSearchFixtures.now }))
    }

    private func serve(index: Bool = true, record: Bool = true) throws {
        let indexBody = try fixture("ladder")
        let recordBody = try fixture("ladder-gen9championsvgc2026regmb-1760")
        LadderStubProtocol.with { state in
            if index { state.answers["/v1/ladder"] = (200, indexBody) }
            if record { state.answers[Self.mbPath] = (200, recordBody) }
        }
    }

    private var requests: [String] { LadderStubProtocol.with { $0.requests } }

    // MARK: Reading the server's answers

    @Test func readsTheServersAnswers() throws {
        let index = try MetaAPI.decode(MetaAPI.LadderIndex.self, from: fixture("ladder"))
        #expect(index.stats.count == 36)
        let entry = try #require(index.stats.first { $0.format == "gen9championsbssregmc" && $0.rating == 1760 })
        #expect(entry.regulation == "M-C" && entry.mode == "singles" && entry.bestOf == 1)
        #expect(entry.month == "2026-09" && entry.battles == 69_462)
        #expect(entry.fetchedAt != nil)

        let stats = try MetaAPI.decode(MetaAPI.LadderStats.self,
                                       from: fixture("ladder-gen9championsvgc2026regmb-1760"))
        #expect(stats.reduction == 1 && stats.regulation == "M-B" && stats.mode == "doubles" && stats.bestOf == 1)
        #expect(stats.month == "2026-09" && stats.previousMonth == "2026-08" && stats.rating == 1760)
        #expect(stats.ratings == [0, 1500, 1630, 1760])
        #expect(stats.fetchedAt != nil)
        let kingambit = try #require(stats.pokemon.first)
        #expect(kingambit.name == "Kingambit" && kingambit.key == "kingambit" && kingambit.megaStone == nil)
        #expect(kingambit.usage > 0.5 && kingambit.trend != nil)
        #expect(kingambit.usageByRating.map(\.rating) == [0, 1500, 1630, 1760])
        #expect(kingambit.leadShare != nil)
        #expect(!kingambit.items.isEmpty && !kingambit.spreads.isEmpty && !kingambit.teammates.isEmpty)
        #expect(stats.pokemon.first { $0.name == "Charizard-Mega-Y" }?.megaStone == "Charizardite Y")

        // An older server's record, or a newer one's, still reads.
        let sparse = try MetaAPI.decode(MetaAPI.LadderStats.self, from: Data("""
            {"format":"f","regulation":"M-B","mode":"doubles","bestOf":1,"month":"2026-09","rating":0,"someday":true,
             "pokemon":[{"name":"Kingambit","usage":0.5,"someday":1}]}
            """.utf8))
        #expect(sparse.pokemon[0].key == nil && sparse.pokemon[0].items.isEmpty && sparse.ratings.isEmpty)
    }

    // MARK: The server first

    @Test func theServersRecordIsUsedAndCached() async throws {
        let store = store()
        try serve()

        #expect(await store.cached(Self.mb) == nil)
        let loaded = await store.load(Self.mb)
        #expect(loaded.answer?.source == .server)
        #expect(loaded.answer?.stats.month == "2026-09")
        #expect(loaded.answer?.stats.pokemon.first?.trend != nil)
        #expect(loaded.serverProblem == nil)
        #expect(requests == ["/v1/ladder", Self.mbPath])

        // Current answers aren't asked for again; `cached` asks no one.
        #expect(await store.load(Self.mb).answer == loaded.answer)
        #expect(await store.cached(Self.mb) == loaded.answer)
        #expect(requests.count == 2)
        // Pull to refresh asks for both.
        #expect(await store.load(Self.mb, force: true).answer == loaded.answer)
        #expect(requests.count == 4)
        #expect(await smogon.downloads == 0)
    }

    @Test func choosesFromTheServersIndex() throws {
        let entries = try MetaAPI.decode(MetaAPI.LadderIndex.self, from: fixture("ladder")).stats
        func choose(_ request: LadderRequest, fallBack: Bool = false) -> String? {
            LadderStore.choose(request, from: entries, fallBack: fallBack).map { "\($0.format) \($0.month) \($0.rating)" }
        }
        // The newest of the regulation's own months.
        #expect(choose(Self.mb) == "gen9championsvgc2026regmb 2026-09 1760")
        #expect(choose(LadderRequest(regulation: .mC, mode: .singles, rating: 0)) == "gen9championsbssregmc 2026-09 0")
        #expect(choose(LadderRequest(regulation: .mC, bestOf: 3, rating: 1630)) == "gen9championsvgc2026regmcbo3 2026-09 1630")
        // Nothing for M-A, a rating Smogon doesn't have, or singles best of three.
        #expect(choose(.teamSearch(.mA)) == nil)
        #expect(choose(LadderRequest(regulation: .mC, rating: 1700)) == nil)
        #expect(choose(LadderRequest(regulation: .mC, mode: .singles, bestOf: 3)) == nil)

        // Team Search falls back to an earlier regulation's newest month, never a later one's.
        let augustOnly = entries.filter { $0.month == "2026-08" }
        #expect(LadderStore.choose(.teamSearch(.mC), from: augustOnly, fallBack: false) == nil)
        #expect(LadderStore.choose(.teamSearch(.mC), from: augustOnly, fallBack: true)?.regulation == "M-B")
        #expect(LadderStore.choose(.teamSearch(.mA), from: entries, fallBack: true) == nil)
    }

    // MARK: Without the server

    @Test func withTheSwitchOffTheDeviceMakesIt() async throws {
        let store = store(serverOn: false)
        try serve()

        // Showing what there is never downloads from Smogon.
        let shown = await store.load(Self.mb)
        #expect(shown.answer == nil && shown.serverProblem == nil)
        #expect(await smogon.downloads == 0)

        // Team Search's fetch does, once.
        let fetched = try await store.fetch(Self.mb)
        #expect(fetched.answer?.source == .device)
        #expect(fetched.answer?.stats.month == "2026-08")
        #expect(fetched.answer?.stats.pokemon.first?.trend == nil, "one file can't say what changed")
        #expect(await smogon.downloads == 1)
        #expect(await store.load(Self.mb).answer == fetched.answer)
        #expect(await store.cached(Self.mb) == fetched.answer)
        #expect(try await store.fetch(Self.mb).answer == fetched.answer)
        #expect(await smogon.downloads == 1)
        #expect(requests.isEmpty, "the server is never asked")
    }

    @Test func aServerThatCantAnswerFailsOverToTheDevice() async throws {
        let store = store()
        LadderStubProtocol.with { $0.unreachable = true }

        let shown = await store.load(Self.mb)
        #expect(shown.answer == nil)
        guard case .unreachable = shown.serverProblem else {
            Issue.record("expected the server to be unreachable, got \(String(describing: shown.serverProblem))")
            return
        }
        let fetched = try await store.fetch(Self.mb)
        #expect(fetched.answer?.source == .device)
        #expect(fetched.serverProblem != nil, "and says why the server's isn't shown")
        #expect(await store.load(Self.mb).answer?.source == .device)

        // The server comes back: its record is the one shown.
        LadderStubProtocol.with { $0.unreachable = false }
        try serve()
        let back = await store.load(Self.mb)
        #expect(back.answer?.source == .server && back.serverProblem == nil)

        // And goes again: its last answer stays, with the reason.
        LadderStubProtocol.with { $0.unreachable = true }
        let stale = await store.load(Self.mb, force: true)
        #expect(stale.answer == back.answer)
        #expect(stale.serverProblem != nil)
    }

    /// A server from before /v1/ladder answers 404.
    @Test func anOlderServerHasNoLadder() async throws {
        let store = store()
        let shown = await store.load(Self.mb)
        #expect(shown.answer == nil)
        #expect(shown.serverProblem == .http(status: 404))
        #expect(try await store.fetch(Self.mb).answer?.source == .device)
    }

    @Test func aServerWithNothingForTheRegulation() async throws {
        let store = store()
        try serve()
        // The server has no M-A. Nothing is wrong with it; the device is asked.
        let shown = await store.load(.teamSearch(.mA))
        #expect(shown.answer == nil && shown.serverProblem == nil)
        #expect(requests == ["/v1/ladder"])

        // It lists M-B but the record itself fails: the device's is used.
        let partial = self.store()
        try serve(record: false)
        let fetched = try await partial.fetch(Self.mb)
        #expect(fetched.answer?.source == .device)
        #expect(fetched.serverProblem == .http(status: 404))
    }

    @Test func nothingAnywhere() async throws {
        let store = store(serverOn: false)
        await smogon.setOffline(true)
        await #expect(throws: URLError.self) { try await store.fetch(Self.mb) }
        #expect(await store.cached(Self.mb) == nil)
        // Smogon has only M-B doubles at 1760.
        await smogon.setOffline(false)
        #expect(try await store.fetch(LadderRequest(regulation: .mB, mode: .singles)).answer == nil)
    }
}
