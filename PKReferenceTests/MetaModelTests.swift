//
//  MetaModelTests.swift
//  PKReferenceTests
//
//  The Meta tab's source rule and what it says in each state
//  (BackendIntegration-PHASE4.md §6), with a stubbed server, a corpus store
//  in a temporary folder, and no network.
//

import Testing
import Foundation
@testable import PKReference

/// A server that answers from a table of paths, or fails as if nothing were
/// listening.
final class MetaModelStubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: Data] = [:]
    nonisolated(unsafe) static var unreachable = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if Self.unreachable {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let url = request.url!
        let body = Self.responses[url.path()]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200,
                                                              httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body ?? Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Limitless, as the corpus store sees it: the backend's fixture event.
private struct FixtureFetcher: TeamCorpusFetching {
    let date: String

    func tournaments(format: String, page: Int, limit: Int) async throws -> [LimitlessTournament] {
        page == 1 ? [LimitlessTournament(id: "event-83", name: "Test Event", game: "VGC", format: format,
                                         date: date, players: 83)] : []
    }

    func standings(tournamentID: String) async throws -> [LimitlessStanding] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "backend/src/test/resources/limitless/event-83/standings.json")
        return try JSONDecoder().decode([LimitlessStanding].self, from: Data(contentsOf: url))
    }
}

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "MetaFixtures/\(name).json"))
}

/// 2026-10-06T12:00:00Z, the day after the fixture event.
private let now = Date(timeIntervalSince1970: 1_791_288_000)

@MainActor
@Suite(.serialized)
struct MetaModelTests {
    private let folder = URL.temporaryDirectory.appending(path: "MetaModelTests-\(UUID().uuidString)")

    private func model(server: Bool, recent: [LimitlessTournament] = []) -> (MetaModel, TeamCorpusStore) {
        let configuration = MetaServerClient.configuration()
        configuration.protocolClasses = [MetaModelStubProtocol.self]
        let store = TeamCorpusStore(fetcher: FixtureFetcher(date: "2026-10-05T18:00:00.000Z"),
                                    directory: folder.appending(path: "corpus"), now: { now },
                                    sleep: { _ in })
        let model = MetaModel(serverURL: { server ? URL(string: "http://localhost:8080")! : nil },
                              session: URLSession(configuration: configuration),
                              cache: MetaCache(directory: folder.appending(path: "meta")),
                              corpusStore: store, recentFromLimitless: { _ in recent }, now: { now })
        return (model, store)
    }

    private func serve() throws {
        MetaModelStubProtocol.unreachable = false
        MetaModelStubProtocol.responses = [
            "/v1/formats": try fixture("formats"),
            "/v1/formats/M-C/pokemon": try fixture("pokemon-M-C-30d"),
            "/v1/formats/M-C/events": try fixture("events-M-C"),
        ]
    }

    @Test func switchOffNothingDownloaded() async {
        let recent = LimitlessTournament(id: "e1", name: "Live Event", game: "VGC", format: "M-C",
                                         date: "2026-10-05T18:00:00.000Z", players: 40)
        let (model, _) = model(server: false, recent: [recent])
        await model.load(.mC, window: .days30)
        #expect(model.status == .needsDownload)
        #expect(model.snapshot == nil)
        #expect(model.serverProblem == nil)
        #expect(model.limitlessEvents.map(\.id) == ["e1"], "Recent events from Limitless")
    }

    @Test func switchOffDownloadThenTheDevicesNumbers() async {
        let (model, _) = model(server: false)
        await model.load(.mC, window: .days30)
        #expect(model.status == .needsDownload)

        await model.download(.mC, window: .days30)
        #expect(model.status == .ready)
        let snapshot = model.snapshot
        #expect(snapshot?.source == .device)
        #expect(snapshot?.list.sample.teams == 83)
        #expect(snapshot?.list.pokemon.first?.key == "rillaboom")
        #expect(snapshot?.events.first?.winner?.player == "Player 01")
        #expect(model.limitlessEvents.isEmpty)
        #expect(model.warning == nil)

        // The 14-day window still has the event; a regulation with none says so.
        await model.load(.mC, window: .days14)
        #expect(model.snapshot?.list.sample.teams == 83)
    }

    @Test func theServersNumbers() async throws {
        try serve()
        let (model, _) = model(server: true)
        await model.load(.mC, window: .days30)
        #expect(model.status == .ready)
        let snapshot = try #require(model.snapshot)
        #expect(snapshot.source == .server)
        #expect(snapshot.list.sample.teams > 0)
        #expect(!snapshot.events.isEmpty)
        #expect(snapshot.updated != nil, "the format's lastFetched")
        #expect(model.serverProblem == nil && model.warning == nil)
    }

    @Test func serverUnreachableFallsBackToTheDevice() async throws {
        let (model, store) = model(server: true)
        _ = try await store.corpus(for: .mC)
        MetaModelStubProtocol.unreachable = true
        await model.load(.mC, window: .days30)
        #expect(model.snapshot?.source == .device)
        if case .unreachable? = model.serverProblem {} else { Issue.record("\(String(describing: model.serverProblem))") }

        // Once the server answers, its numbers replace the device's.
        try serve()
        await model.load(.mC, window: .days30, force: true)
        #expect(model.snapshot?.source == .server)
        #expect(model.serverProblem == nil)

        // Then, unreachable again, its cached answers stay, with the reason.
        MetaModelStubProtocol.unreachable = true
        await model.load(.mC, window: .days30, force: true)
        #expect(model.snapshot?.source == .server)
        if case .unreachable? = model.serverProblem {} else { Issue.record("\(String(describing: model.serverProblem))") }
    }

    @Test func serverUnreachableNothingDownloaded() async {
        MetaModelStubProtocol.unreachable = true
        let (model, _) = model(server: true)
        await model.load(.mC, window: .days30)
        #expect(model.status == .needsDownload)
        #expect(model.serverProblem != nil)
    }

    /// The server has no events for Settings' regulation: it says which it has.
    @Test func serverHasNothingForTheRegulation() async throws {
        try serve()
        let (model, _) = model(server: true)
        await model.load(.mB, window: .days30)
        #expect(model.snapshot == nil)
        #expect(model.status == .ready)
        #expect(model.warning?.hasPrefix("The server has no M-B events. It has M-C (") == true)
        #expect(model.warning?.contains("CUSTOM") == false, "formats the app doesn't know aren't offered")
    }

    @Test func emptyWindow() async throws {
        let (model, store) = model(server: false)
        _ = try await store.corpus(for: .mC)
        // A week later the event is outside the 14-day window, but not the regulation's.
        let later = MetaModel(serverURL: { nil }, corpusStore: store, now: { now.addingTimeInterval(20 * 86_400) })
        await later.load(.mC, window: .days14)
        #expect(later.snapshot?.list.sample.teams == 0)
        #expect(later.warning == "No M-C events in the last 14 days. The regulation so far has 1 event: try a longer window.")
        await model.load(.mC, window: .regulation)
        #expect(model.warning == nil)
    }

    // MARK: Words

    @Test func words() {
        let sample = MetaAPI.Sample(events: 46, teams: 2633, topCutTeams: 484)
        #expect(MetaText.sample(sample, source: .server) == "46 events · 2,633 teams · 484 in top cuts")
        #expect(MetaText.sample(MetaAPI.Sample(events: 1, teams: 83, topCutTeams: 8), source: .device)
                == "1 event · 83 teams · 8 in the top 8")

        let en = Locale(identifier: "en_US")
        #expect(MetaText.source(.server, updated: now.addingTimeInterval(-12 * 60), now: now, locale: en)
                == "Limitless, through your PK Reference server · updated 12 minutes ago")
        #expect(MetaText.source(.device, updated: now.addingTimeInterval(-30), now: now, locale: en)
                == "Limitless, from the events Team Search downloaded to this device · updated just now")
        #expect(MetaText.source(.server, updated: nil, now: now) == "Limitless, through your PK Reference server")

        let formats = [MetaAPI.Format(format: "M-C", events: 46, teams: 2633, firstEvent: nil, lastEvent: nil,
                                      lastFetched: nil),
                       MetaAPI.Format(format: "CUSTOM", events: 2, teams: 50, firstEvent: nil, lastEvent: nil,
                                      lastFetched: nil)]
        #expect(MetaText.serverHasNoEvents(.mB, formats) == "The server has no M-B events. It has M-C (46 events). "
                + "Change the regulation in Settings, or add M-B to the server's LIMITLESS_FORMATS.")
        #expect(MetaText.serverHasNoEvents(.mB, []) == "The server has no M-B events. "
                + "Change the regulation in Settings, or add M-B to the server's LIMITLESS_FORMATS.")
        #expect(MetaText.emptyWindow(.mC, .regulation, allEvents: 0) == "No M-C events in the regulation so far.")

        #expect(MetaText.winner(MetaAPI.EventWinner(player: "Player 01", wins: 7, losses: 1, ties: 0, team: []))
                == "Won by Player 01, 7–1")
        #expect(MetaText.serverProblem(.http(status: 503), showing: .device, updated: nil, now: now)
                == "The server answered HTTP 503. Showing what this device worked out.")
        #expect(MetaText.serverProblem(.unreachable("Could not connect to the server."), showing: .server,
                                       updated: now.addingTimeInterval(-7200), now: now, locale: en)
                == "Couldn't reach the server: Could not connect to the server. Showing its answers from 2 hours ago.")
    }
}
