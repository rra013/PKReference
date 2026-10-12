//
//  MetaLadderModelTests.swift
//  PKReferenceTests
//
//  The Meta tab's ladder: what LadderModel shows from the server and from
//  the device, that it never downloads from Smogon unasked, and the views'
//  words, names and definitions (BackendIntegration-PHASE5.md §6).
//

import Testing
import Foundation
@testable import PKReference

/// A server answering by path; its own, so no other suite's requests mix in.
final class LadderModelStubProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: Data] = [:]
    nonisolated(unsafe) private static var unreachable = false

    static func set(_ answers: [String: Data], unreachable: Bool = false) {
        lock.withLock {
            self.answers = answers
            self.unreachable = unreachable
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let path = url.path() + (url.query().map { "?" + $0 } ?? "")
        let (down, body) = Self.lock.withLock { (Self.unreachable, Self.answers[path]) }
        if down {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200,
                                                              httpVersion: "HTTP/1.1", headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body ?? Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// smogon.com with the months a test gives it, counting downloads.
private actor ListedSmogon: SmogonFetching {
    var monthFiles: [String: [String]]
    var offline = false
    private(set) var downloads: [String] = []

    init(_ monthFiles: [String: [String]]) { self.monthFiles = monthFiles }

    func months() async throws -> [String] {
        if offline { throw URLError(.notConnectedToInternet) }
        return Array(monthFiles.keys)
    }

    func chaosFiles(month: String) async throws -> [SmogonFile] {
        (monthFiles[month] ?? []).map { SmogonFile(name: $0, bytes: 5_850_354) }
    }

    func chaos(month: String, file: String) async throws -> Data {
        if offline { throw URLError(.notConnectedToInternet) }
        downloads.append("\(month)/\(file)")
        return Data(TeamSearchFixtures.smogonChaosJSON.utf8)
    }

    func leads(month: String, file: String) async throws -> String? { nil }

    func set(_ monthFiles: [String: [String]]) { self.monthFiles = monthFiles }
    func setOffline(_ value: Bool) { offline = value }
}

private final class MovingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = TeamSearchFixtures.now
    var now: Date { lock.withLock { current } }
    func advance(hours: Double) { lock.withLock { current += hours * 3600 } }
}

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "MetaFixtures/\(name).json"))
}

@MainActor
@Suite(.serialized)
struct MetaLadderModelTests {
    private let directory = URL.temporaryDirectory.appending(path: "MetaLadderModelTests-\(UUID().uuidString)")
    private let clock = MovingClock()
    private static let mbFile = "gen9championsvgc2026regmb-1760.json"
    private static let mb = LadderRequest.teamSearch(.mB)
    private static let mbPath = "/v1/ladder/gen9championsvgc2026regmb?rating=1760&month=2026-09"

    private func model(_ smogon: ListedSmogon, server: Bool) -> LadderModel {
        let configuration = MetaServerClient.configuration()
        configuration.protocolClasses = [LadderModelStubProtocol.self]
        let session = URLSession(configuration: configuration)
        let cache = MetaCache(directory: directory.appending(path: "server"))
        let base = URL(string: "http://localhost:8080")!
        let clock = clock
        return LadderModel(store: LadderStore(
            serverURL: { server ? base : nil },
            insights: { MetaInsights(baseURL: $0, session: session, cache: cache) },
            device: SmogonLadderStore(fetcher: smogon, directory: directory.appending(path: "smogon"),
                                      now: { clock.now })))
    }

    private func stats() throws -> MetaAPI.LadderStats {
        try MetaAPI.decode(MetaAPI.LadderStats.self, from: fixture("ladder-gen9championsvgc2026regmb-1760"))
    }

    // MARK: The model

    @Test func showsTheServersRecord() async throws {
        LadderModelStubProtocol.set(["/v1/ladder": try fixture("ladder"),
                                     Self.mbPath: try fixture("ladder-gen9championsvgc2026regmb-1760")])
        let smogon = ListedSmogon(["2026-08": [Self.mbFile]])
        let model = model(smogon, server: true)
        #expect(model.status == .loading)

        await model.load(Self.mb)
        #expect(model.status == .ready)
        #expect(model.answer?.source == .server)
        #expect(model.answer?.stats.month == "2026-09")
        #expect(model.shown == Self.mb)
        // The server's record needs nothing from Smogon: nothing is offered, or asked of it.
        #expect(model.offer == nil && model.notice == nil && model.serverProblem == nil)
        #expect(await smogon.downloads.isEmpty)

        // Another ladder clears what was shown while it loads; the server has no M-A.
        await model.load(.teamSearch(.mA))
        #expect(model.answer == nil)
        #expect(model.notice == LadderText.nothingPublished(.teamSearch(.mA)))
    }

    @Test func withoutTheServerItOffersTheDownloadAndWaits() async throws {
        let smogon = ListedSmogon(["2026-08": [Self.mbFile]])
        let model = model(smogon, server: false)

        await model.load(Self.mb)
        #expect(model.status == .ready)
        #expect(model.answer == nil)
        #expect(model.offer == SmogonLadderStore.Offer(month: "2026-08", file: Self.mbFile, bytes: 5_850_354))
        #expect(model.notice == nil)
        #expect(await smogon.downloads.isEmpty, "opening the ladder downloads nothing")

        await model.download(Self.mb)
        #expect(model.status == .ready)
        #expect(model.answer?.source == .device)
        #expect(model.answer?.stats.month == "2026-08")
        #expect(model.offer == nil)
        #expect(await smogon.downloads == ["2026-08/\(Self.mbFile)"])

        // Next time it's there, with nothing to offer and nothing downloaded again.
        let again = self.model(smogon, server: false)
        await again.load(Self.mb)
        #expect(again.answer == model.answer)
        #expect(again.offer == nil)
        #expect(await smogon.downloads.count == 1)
    }

    @Test func aNewerMonthIsOfferedOverTheOneShown() async throws {
        let smogon = ListedSmogon(["2026-08": [Self.mbFile]])
        let model = model(smogon, server: false)
        await model.download(Self.mb)

        // September comes out. The choice of month is checked again after 12 hours.
        await smogon.set(["2026-08": [Self.mbFile], "2026-09": [Self.mbFile]])
        await model.load(Self.mb)
        #expect(model.offer == nil)
        clock.advance(hours: 13)
        await model.load(Self.mb)
        #expect(model.answer?.stats.month == "2026-08", "August stays while September waits to be asked for")
        #expect(model.offer?.month == "2026-09")

        // And after a restart, with September chosen but not downloaded.
        let restarted = self.model(smogon, server: false)
        await restarted.load(Self.mb)
        #expect(restarted.answer?.stats.month == "2026-08")
        #expect(restarted.offer?.month == "2026-09")

        await restarted.download(Self.mb)
        #expect(restarted.answer?.stats.month == "2026-09")
        #expect(restarted.offer == nil)
    }

    @Test func nothingToShowAndNothingToDownload() async throws {
        // Smogon has no singles for M-B.
        let smogon = ListedSmogon(["2026-08": [Self.mbFile]])
        let model = model(smogon, server: false)
        let singles = LadderRequest(regulation: .mB, mode: .singles)
        await model.load(singles)
        #expect(model.answer == nil && model.offer == nil)
        #expect(model.notice == LadderText.nothingPublished(singles))

        // Smogon can't be reached.
        await smogon.setOffline(true)
        await model.load(Self.mb)
        #expect(model.answer == nil && model.offer == nil)
        #expect(model.notice?.hasPrefix("Couldn't reach Smogon to look for this ladder's stats: ") == true)
    }

    @Test func aServerThatCantAnswer() async throws {
        LadderModelStubProtocol.set([:], unreachable: true)
        let smogon = ListedSmogon(["2026-08": [Self.mbFile]])
        let model = model(smogon, server: true)
        await model.load(Self.mb)
        #expect(model.serverProblem != nil)
        #expect(model.answer == nil)
        #expect(model.offer?.month == "2026-08", "Smogon's own file is offered in its place")

        await model.download(Self.mb)
        #expect(model.answer?.source == .device)

        // A failed download says so and keeps the offer.
        let failing = ListedSmogon(["2026-08": [Self.mbFile]])
        let other = self.model(failing, server: false)
        await other.load(LadderRequest(regulation: .mB, rating: 1760))
        #expect(other.answer?.source == .device, "the first model's download is on the device")
        try await SmogonLadderStore(fetcher: failing, directory: directory.appending(path: "smogon")).clearCache()
        await other.load(Self.mb, force: true)
        await failing.setOffline(true)
        await other.download(Self.mb)
        guard case .downloadFailed = other.status else {
            Issue.record("expected a failed download, got \(other.status)")
            return
        }
    }

    // MARK: Words

    @Test func words() throws {
        let stats = try stats()
        let en = Locale(identifier: "en_US")
        #expect(LadderText.rating(0) == "All" && LadderText.rating(1760) == "1760+")
        #expect(LadderText.players(0) == "all players" && LadderText.players(1500) == "players rated 1500+")
        #expect(LadderText.month("2026-09", locale: en) == "September 2026")
        #expect(LadderText.month("2027-01", locale: en) == "January 2027")
        #expect(LadderText.month("soon", locale: en) == "soon" && LadderText.month("2026-13", locale: en) == "2026-13")
        #expect(LadderText.sample(stats, locale: en) == "326,464 battles · September 2026")

        let now = Date(timeIntervalSince1970: 1_791_288_000)
        #expect(LadderText.source(.server, fetched: now.addingTimeInterval(-2 * 3600), now: now, locale: en)
                == "Pokémon Showdown's ladder, from Smogon's stats through your PK Reference server · fetched 2 hours ago")
        #expect(LadderText.source(.server, fetched: nil, now: now, locale: en)
                == "Pokémon Showdown's ladder, from Smogon's stats through your PK Reference server")
        #expect(LadderText.source(.device, fetched: now, now: now, locale: en)
                == "Pokémon Showdown's ladder, from Smogon's stats downloaded to this device")

        #expect(LadderText.ladder(.teamSearch(.mC)) == "Doubles, best of 1, players rated 1760+")
        #expect(LadderText.ladder(LadderRequest(regulation: .mC, mode: .singles, rating: 0)) == "Singles, all players")

        #expect(LadderText.percent(0.4659939) == "47%")
        #expect(LadderText.percent(0.0659479) == "6.6%")
        #expect(LadderText.percent(0.1) == "10%")
        #expect(LadderText.percent(0.0004) == "<0.1%")
        #expect(LadderText.percent(0) == "0.0%")
        #expect(LadderText.percent(1) == "100%")

        let namer = LadderNamer(stats, regulation: .mB)
        #expect(LadderText.mostUsed(stats, name: namer.name)
                == "Kingambit is on 58% of teams of players rated 1760+, then Basculegion on 42%.")
        let everyone = MetaAPI.LadderStats(reduction: 1, format: "f", regulation: "M-B", mode: "singles", bestOf: 1,
                                           month: "2026-09", rating: 0, battles: 1, pokemon: [stats.pokemon[0]])
        #expect(LadderText.mostUsed(everyone, name: namer.name) == "Kingambit is on 58% of teams.")
        #expect(LadderText.mostUsed(MetaAPI.LadderStats(reduction: 1, format: "f", regulation: "M-B", mode: "singles",
                                                        bestOf: 1, month: "m", rating: 0, battles: 0, pokemon: []),
                                    name: namer.name) == nil)

        #expect(LadderText.size(5_850_354) != nil && LadderText.size(nil) == nil)
        let offer = SmogonLadderStore.Offer(month: "2026-09", file: "x", bytes: nil)
        #expect(LadderText.download(offer, for: .teamSearch(.mC), showing: nil, locale: en)
                == "Smogon's September 2026 stats for this ladder (doubles, best of 1, players rated 1760+) aren't on "
                + "this device yet.")
        #expect(LadderText.download(offer, for: .teamSearch(.mC), showing: "2026-08", locale: en)
                == "Smogon has published September 2026's stats. Showing August 2026's.")
        #expect(LadderText.download(SmogonLadderStore.Offer(month: "2026-09", file: "x", bytes: 5_850_354),
                                    for: .teamSearch(.mC), showing: nil, locale: en).contains(" The download is "))
        #expect(LadderText.nothingPublished(LadderRequest(regulation: .mC, bestOf: 3))
                .hasPrefix("Smogon has no M-C best-of-three doubles stats at this rating yet."))
        #expect(LadderText.nothingPublished(LadderRequest(regulation: .mA, mode: .singles))
                .hasPrefix("Smogon has no M-A singles stats at this rating yet."))
    }

    @Test func leadsAndSpreads() throws {
        func pokemon(usage: Double, lead: Double?) -> MetaAPI.LadderPokemon {
            MetaAPI.LadderPokemon(name: "Sneasler", key: "sneasler", megaStone: nil, usage: usage, leadShare: lead)
        }
        // Doubles: 6.6% of all leads is 13.2% of teams leading with it, of the 37% that have it.
        let sneasler = pokemon(usage: 0.3707538, lead: 0.0659479)
        #expect(abs(try #require(LadderText.leadRate(sneasler, mode: "doubles")) - 0.35575) < 0.0001)
        #expect(LadderText.leadRateSentence(sneasler, mode: "doubles") == "Leads on about 36% of the teams with it.")
        // Singles: one lead a team.
        #expect(abs(try #require(LadderText.leadRate(sneasler, mode: "singles")) - 0.17788) < 0.0001)
        // Never more than every team with it; nothing without a lead share.
        #expect(LadderText.leadRate(pokemon(usage: 0.01, lead: 0.02), mode: "doubles") == 1)
        #expect(LadderText.leadRate(pokemon(usage: 0.3, lead: nil), mode: "doubles") == nil)
        #expect(LadderText.leadRateSentence(pokemon(usage: 0.3, lead: nil), mode: "doubles") == nil)

        #expect(LadderSpread("Adamant:2/32/0/0/0/32") == LadderSpread("Adamant:2/32/0/0/0/32"))
        #expect(LadderSpread("Adamant:2/32/0/0/0/32")?.points == [2, 32, 0, 0, 0, 32])
        #expect(LadderSpread("broken") == nil && LadderSpread("Jolly:1/2/3") == nil && LadderSpread("Jolly:a/b/c/d/e/f") == nil)
        #expect(LadderText.spread("Adamant:2/32/0/0/0/32") == "Adamant · 2 HP / 32 Atk / 32 Spe")
        #expect(LadderText.spread("Sassy:32/0/4/0/30/0") == "Sassy · 32 HP / 4 Def / 30 SpD")
        #expect(LadderText.spread("Hardy:0/0/0/0/0/0") == "Hardy · no stat points")
        #expect(LadderText.spread("broken") == "broken")

        func share(_ value: String, _ share: Double) -> MetaAPI.LadderShare { MetaAPI.LadderShare(value: value, share: share) }
        #expect(LadderText.spreadsCover([share("a", 0.29624), share("b", 0.17654)]) == "These 2 cover 47% of its teams.")
        #expect(LadderText.spreadsCover([share("a", 0.04411)]) == "This one covers 4.4% of its teams.")
        #expect(LadderText.spreadsCover([]) == nil)
    }

    @Test func byRatingAndSpoken() throws {
        let stats = try stats()
        let gaps = LadderText.ratingGaps(stats)
        #expect(gaps.count == stats.pokemon.count)
        let kingambit = try #require(gaps.first { $0.pokemon.name == "Kingambit" })
        #expect(kingambit.low == stats.pokemon[0].usageByRating.first?.usage)
        #expect(kingambit.high == stats.pokemon[0].usage, "the page's rating, 1760, is the highest")
        // The device's record has one rating: nothing to compare.
        let device = MetaAPI.LadderStats(reduction: 1, format: stats.format, regulation: "M-B", mode: "doubles",
                                         bestOf: 1, month: "2026-09", rating: 1760, battles: 1, pokemon: stats.pokemon)
        #expect(LadderText.ratingGaps(device).isEmpty)

        #expect(LadderText.spoken(stats.pokemon[0], name: "Kingambit").hasPrefix("Kingambit. On 58% of teams. Up "))
        let plain = MetaAPI.LadderPokemon(name: "x", key: nil, megaStone: nil, usage: 0.031, leadShare: nil)
        #expect(LadderText.spoken(plain, name: "Rotom-Wash") == "Rotom-Wash. On 3.1% of teams.")
    }

    // MARK: Names

    @Test func namesEntriesTheAppsWayAndTellsThemApart() throws {
        func entry(_ name: String) -> MetaAPI.LadderPokemon {
            MetaAPI.LadderPokemon(name: name, key: nil, megaStone: nil, usage: 0.1, leadShare: nil)
        }
        let stats = MetaAPI.LadderStats(
            reduction: 1, format: "f", regulation: "M-C", mode: "doubles", bestOf: 1, month: "2026-09", rating: 1760,
            battles: 1, pokemon: ["Salamence-Mega", "Salamence", "Charizard-Mega-Y", "Arcanine-Hisui", "Indeedee-F",
                                  "Basculegion", "Basculegion-F", "Rotom-Wash", "Rotom-Heat", "Sirfetch'd",
                                  "Newmon"].map(entry))
        let namer = LadderNamer(stats, regulation: .mC)
        #expect(namer.name("Salamence-Mega") == "Mega Salamence")
        #expect(namer.name("Salamence") == "Salamence")
        #expect(namer.name("Charizard-Mega-Y") == "Mega Charizard Y")
        #expect(namer.name("Arcanine-Hisui") == "Arcanine (Hisui)")
        #expect(namer.name("Indeedee-F") == "Indeedee (Female)")
        #expect(namer.name("Sirfetch'd") == "Sirfetchd" || namer.name("Sirfetch'd") == "Sirfetch'd")
        // The regulation's data doesn't list these forms, so Smogon's names tell them apart.
        #expect(namer.name("Basculegion") == "Basculegion" && namer.name("Basculegion-F") == "Basculegion-F")
        #expect(namer.name("Rotom-Wash") == "Rotom-Wash" && namer.name("Rotom-Heat") == "Rotom-Heat")
        // Outside the regulation's data, and a teammate too rare for the record.
        #expect(namer.name("Newmon") == "Newmon")
        #expect(namer.name("Ninetales-Alola") == "Ninetales (Alola)")
        #expect(LadderNamer(nil, vocabulary: nil).name("Salamence-Mega") == "Salamence-Mega")
    }

    // MARK: Definitions

    /// The info sheets say what the Phase 5 file's §6.4 says, word for word.
    @Test func definitionsMatchThePlan() throws {
        let plan = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "BackendIntegration-PHASE5.md"), encoding: .utf8)
        let section = try #require(plan.components(separatedBy: "### 6.4 Info sheets").last?
            .components(separatedBy: "### 6.5").first)
        var planned: [String: String] = [:]
        for item in section.components(separatedBy: "\n- **").dropFirst() {
            guard let colon = item.range(of: ":**") else { continue }
            let text = item[colon.upperBound...].split(whereSeparator: \.isWhitespace).joined(separator: " ")
            // A bullet runs on from its title; a sheet's text starts a sentence.
            planned[item[..<colon.lowerBound].lowercased()] = text.prefix(1).uppercased() + text.dropFirst()
        }
        #expect(planned.count == LadderDefinition.allCases.count)
        for definition in LadderDefinition.allCases {
            let title = definition == .usage ? "ladder usage" : definition.title.lowercased()
            #expect(planned[title] == definition.text, "\(definition.title)")
        }
        #expect(LadderDefinition.usage.info == MetaInfo(title: "Ladder Usage", text: LadderDefinition.usage.text, note: nil))
        #expect(MetaDefinition.topEight.info.note != nil && MetaDefinition.usage.info.note == nil)
    }

    @Test func theSwitch() {
        #expect(MetaView.allCases.map(\.title) == ["Tournaments", "Doubles Ladder", "Singles Ladder"])
        #expect(MetaView.tournaments.mode == nil)
        #expect(MetaView.doublesLadder.mode == .doubles && MetaView.singlesLadder.mode == .singles)
        #expect(MetaView(rawValue: "doublesLadder") == .doublesLadder)
    }
}
