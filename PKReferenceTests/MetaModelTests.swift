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

    // MARK: Pages

    @Test func aPageFromTheServer() async throws {
        try serve()
        MetaModelStubProtocol.responses["/v1/formats/M-C/pokemon/rillaboom"] = try fixture("pokemon-M-C-rillaboom-30d")
        MetaModelStubProtocol.responses["/v1/formats/M-C/cores"] = try fixture("cores-M-C-30d")
        let (model, _) = model(server: true)
        await model.load(.mC, window: .days30)
        let snapshot = try #require(model.snapshot)
        let page = try #require(await MetaModel.page("rillaboom", in: snapshot))
        #expect(page.source == .server)
        #expect(page.detail.key == "rillaboom")
        #expect(!page.detail.sets.isEmpty)
        #expect(!page.pairs.isEmpty && page.pairs.allSatisfy { $0.members.contains("rillaboom") })
        #expect(await MetaModel.page("missingno", in: snapshot) == nil)
    }

    @Test func aPageFromTheDevice() async throws {
        let (model, store) = model(server: false)
        _ = try await store.corpus(for: .mC)
        await model.load(.mC, window: .days30)
        let snapshot = try #require(model.snapshot)
        let page = try #require(await MetaModel.page("rillaboom", in: snapshot))
        #expect(page.source == .device)
        #expect(page.detail.usage?.teams == 44)
        #expect(page.detail.sets.first?.moves == ["Fake Out", "Grassy Glide", "High Horsepower", "Wood Hammer"])
        #expect(page.trios.allSatisfy { $0.members.contains("rillaboom") })
    }

    // MARK: Archetypes

    @Test func archetypesFromTheServer() async throws {
        try serve()
        MetaModelStubProtocol.responses["/v1/formats/M-C/archetypes"] = try fixture("archetypes-M-C-30d")
        MetaModelStubProtocol.responses["/v1/formats/M-C/archetypes/garchomp+gholdengo+incineroar+rillaboom"]
            = try fixture("archetype-M-C-30d")
        let (model, _) = model(server: true)
        await model.load(.mC, window: .days30)
        let snapshot = try #require(model.snapshot)
        let teams = try #require(MetaTeamsToBeatCard.teams(snapshot))
        #expect(teams.count == 5)
        #expect(zip(teams, teams.dropFirst()).allSatisfy { $0.topCutTeams >= $1.topCutTeams }, "most top-cut teams first")

        let page = try #require(await MetaModel.archetype("garchomp+gholdengo+incineroar+rillaboom", in: snapshot))
        #expect(page.archetype.core.count == 4)
        #expect(!page.archetype.matchups.isEmpty)
        #expect(page.examples.count == 5)
        #expect(await MetaModel.archetype("a+b+c+d", in: snapshot) == nil)
    }

    @Test func archetypesFromTheDevice() async throws {
        let (model, store) = model(server: false)
        _ = try await store.corpus(for: .mC)
        await model.load(.mC, window: .days30)
        let snapshot = try #require(model.snapshot)
        let teams = try #require(MetaTeamsToBeatCard.teams(snapshot))
        #expect(!teams.isEmpty)
        let page = try #require(await MetaModel.archetype("garchomp+gholdengo+rillaboom+volcarona", in: snapshot))
        #expect(page.archetype.matchups.isEmpty, "the device has no pairings")
        #expect(page.examples.map(\.placing) == [19, 23, 26, 33, 46])
    }

    /// An example team opens the team sheet Events shows, with its save buttons.
    @Test func anExampleTeamAsAStanding() {
        let team = MetaAPI.ExampleTeam(
            eventId: "e1", eventName: "Test Event", eventDate: nil, players: 83, player: "Player 19", placing: 19,
            wins: 3, losses: 1, ties: 0,
            members: [MetaAPI.ExampleMember(key: "arcanine:hisui", name: "Hisuian Arcanine", item: "No Item",
                                            ability: "Intimidate", nature: "Jolly", moves: ["Flare Blitz"])])
        let standing = team.standing
        #expect(standing.name == "Player 19")
        #expect(standing.placing == 19)
        #expect(standing.record?.wins == 3 && standing.record?.losses == 1)
        let member = standing.decklist?.first
        #expect(member?.limitlessID == "arcanine-hisui")
        #expect(member?.item == nil, "No Item is no item")
        #expect(member?.attacks == ["Flare Blitz"])
    }

    @Test func archetypeWords() {
        let archetype = MetaAPI.Archetype(id: "a", name: "rillaboom+incineroar+gholdengo", core: [], teams: 1, usage: 0,
                                          topCutTeams: 0, topCutUsage: nil, record: nil, matchups: [])
        #expect(MetaText.archetypeName(archetype, name: { $0.capitalized }) == "Rillaboom + Incineroar + Gholdengo")
        #expect(MetaText.placing(1, of: 83) == "1st of 83")
        #expect(MetaText.placing(22, of: 1200) == "22nd of 1,200")
        #expect(MetaText.placing(13, of: 83) == "13th of 83")
        #expect(MetaText.placing(nil, of: 83) == "Unplaced")
    }

    @Test func aSetToSaveOrCalc() {
        let set = MetaAPI.PokemonSet(item: "No Item", ability: "Intimidate", nature: "Adamant",
                                     moves: ["Flare Blitz", "Extreme Speed"], count: 3, share: 0.1)
        let member = MetaSetRequest(key: "arcanine:hisui", name: "Arcanine (Hisui)", set: set).member
        #expect(member.name == "Arcanine (Hisui)")
        #expect(member.limitlessID == "arcanine-hisui")
        #expect(member.item == nil, "No Item is no item")
        #expect(member.attacks == ["Flare Blitz", "Extreme Speed"])
        #expect(LimitlessSpeciesResolver([.init(name: "arcanine", isDefaultForm: true),
                                          .init(name: "arcanine-hisui", isDefaultForm: false)])
            .resolve(name: member.name, slug: member.limitlessID) == "arcanine-hisui")
    }

    // MARK: Words

    @Test func cardWords() {
        #expect(MetaText.percent(0.5452) == "55%")
        #expect(MetaText.percent(0.004) == "<1%")
        #expect(MetaText.percent(0) == "0%")
        #expect(MetaText.trend(0.0612) == "▲ 6.1 points")
        #expect(MetaText.trend(-0.0024) == "▼ 0.2 points")
        #expect(MetaText.trend(0.12) == "▲ 12 points")
        #expect(MetaText.trend(0.0001) == "no change")
        #expect(MetaText.trend(nil) == nil)
        let record = MetaAPI.WinRecord(wins: 1435, losses: 1528, ties: 2, matches: 2965, winRate: 0.4843,
                                       winRateLow: 0.4664, winRateHigh: 0.5023)
        #expect(MetaText.record(record, source: .server) == "Wins 48% (47–50%) of 2,965 matches")
        #expect(MetaText.record(record, source: .device) == "Team record 48% (47–50%) of 2,965 matches")
        #expect(MetaText.record(MetaAPI.WinRecord(wins: 10, losses: 19, ties: 0, matches: 29, winRate: nil,
                                                  winRateLow: nil, winRateHigh: nil), source: .server)
                == "29 matches: too few for a rate")

        func usage(_ key: String, _ usage: Double, _ top: Double?, trend: Double? = nil) -> MetaAPI.PokemonUsage {
            MetaAPI.PokemonUsage(key: key, teams: 10, usage: usage, topCutTeams: 1, topCutUsage: top, trend: trend,
                                 record: nil)
        }
        let list = [usage("rillaboom", 0.5452, 0.5352), usage("incineroar", 0.40, 0.38), usage("gholdengo", 0.34, 0.41)]
        #expect(MetaText.whatsWinning(list, source: .server, name: { $0.capitalized })
                == "Rillaboom is on 55% of teams and 54% of top-cut teams. Gholdengo does better than its usage "
                + "says: 34% of teams, 41% of top-cut teams.")
        #expect(MetaText.whatsWinning(Array(list.prefix(2)), source: .device, name: { $0.capitalized })
                == "Rillaboom is on 55% of teams and 54% of top-8 teams.")
        #expect(MetaText.spoken(usage("rillaboom", 0.5452, 0.5352, trend: -0.02), name: "Rillaboom", source: .server)
                == "Rillaboom. On 55% of teams, 54% of top-cut teams. Trend down 2.0 points.")
    }

    /// The info sheets say what the plan's §4.2 says, word for word.
    @Test func definitionsMatchThePlan() throws {
        let plan = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "BackendIntegration-PLAN.md"), encoding: .utf8)
        let section = try #require(plan.components(separatedBy: "### 4.2 Metrics").last?
            .components(separatedBy: "### 4.3").first)
        var planned: [String: String] = [:]
        // "- **Usage:** the share…", "- **Top-8 rate** (worked out on the device…): its share…"
        for item in section.components(separatedBy: "\n- **").dropFirst() {
            guard let bold = item.range(of: "**") else { continue }
            let heading = item[..<bold.lowerBound]
            // The colon ends the bold title, or follows its parenthesis.
            let start = heading.hasSuffix(":") ? bold.upperBound
                : item[bold.upperBound...].firstIndex(of: ":").map(item.index(after:))
            guard let start else { continue }
            let title = heading.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            var text = item[start...].replacingOccurrences(of: "**", with: "")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            text = text.prefix(1).uppercased() + text.dropFirst()
            planned[title.lowercased()] = text
        }
        #expect(planned.count == MetaDefinition.allCases.count)
        for definition in MetaDefinition.allCases {
            #expect(planned[definition.title.lowercased()] == definition.text, "\(definition.title)")
        }
    }

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
