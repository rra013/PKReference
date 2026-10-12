//
//  SmogonLadderStoreTests.swift
//  PKReferenceTests
//
//  The device's own ladder records (SmogonLadderStore): choosing which
//  month's stats to use (the regulation's own, or for Team Search the latest
//  earlier one while it has none), for doubles and singles at each rating;
//  downloading only when asked; the cache, and offline. A fake directory
//  listing stands in for smogon.com.
//

import Testing
import Foundation
@testable import PKReference

/// A canned smogon.com stats directory, recording requests.
private actor FakeSmogon: SmogonFetching {
    let monthFiles: [String: [String]]
    var offline = false
    var leadsText: String? = " | 1    | Incineroar         | 12.50000% | 10     | 12.500% |\n"
    private(set) var monthRequests = 0
    private(set) var chaosRequested: [String] = []
    private(set) var leadsRequested: [String] = []

    init(_ monthFiles: [String: [String]]) { self.monthFiles = monthFiles }

    func months() async throws -> [String] {
        monthRequests += 1
        if offline { throw URLError(.notConnectedToInternet) }
        return Array(monthFiles.keys)
    }

    func chaosFiles(month: String) async throws -> [SmogonFile] {
        if offline { throw URLError(.notConnectedToInternet) }
        return (monthFiles[month] ?? []).map { SmogonFile(name: $0, bytes: 5_850_354) }
    }

    func chaos(month: String, file: String) async throws -> Data {
        if offline { throw URLError(.notConnectedToInternet) }
        chaosRequested.append("\(month)/\(file)")
        return Data(TeamSearchFixtures.smogonChaosJSON.utf8)
    }

    func leads(month: String, file: String) async throws -> String? {
        if offline { throw URLError(.notConnectedToInternet) }
        leadsRequested.append("\(month)/\(file)")
        return leadsText
    }

    func setOffline(_ value: Bool) { offline = value }
    func setLeads(_ text: String?) { leadsText = text }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var now: Date { lock.withLock { current } }
    func advance(hours: Double) { lock.withLock { current += hours * 3600 } }
}

@Suite("Smogon Ladder Store")
struct SmogonLadderStoreTests {

    private static let mb = "gen9championsvgc2026regmb-1760.json"
    private static let maFile = "gen9championsvgc2026regma-1760.json"
    private static let teamSearchMB = LadderRequest.teamSearch(.mB)

    private static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "SmogonLadderStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private static func store(_ fetcher: FakeSmogon, clock: TestClock = TestClock(TeamSearchFixtures.now),
                              directory: URL, lookback: Int = 4) -> SmogonLadderStore {
        var configuration = SmogonLadderConfiguration()
        configuration.lookbackMonths = lookback
        return SmogonLadderStore(fetcher: fetcher, directory: directory, configuration: configuration,
                                 now: { clock.now })
    }

    // MARK: Choosing a month

    @Test("A regulation's own newest month is used, for the mode, best-of and rating asked for")
    func ownNewestMonth() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb, "gen9championsvgc2026regmbbo3-1760.json",
                                           "gen9championsbssregmb-1760.json", "gen9championsvgc2026regmb-1500.json"],
                               "2026-07": [Self.mb, "gen9championsbssregmb-1500.json"]])
        let store = Self.store(fake, directory: dir)

        let stats = try #require(try await store.stats(Self.teamSearchMB))
        #expect(stats.month == "2026-08")
        #expect(stats.format == "gen9championsvgc2026regmb")
        #expect(stats.regulation == "M-B" && stats.mode == "doubles" && stats.bestOf == 1 && stats.rating == 1760)
        #expect(stats.reduction == SmogonLadder.reduction)
        #expect(await fake.chaosRequested == ["2026-08/\(Self.mb)"])
        // Its leads table comes with it.
        #expect(await fake.leadsRequested == ["2026-08/gen9championsvgc2026regmb-1760.txt"])
        #expect(stats.pokemon.first?.name == "Incineroar")
        #expect(stats.pokemon.first?.leadShare == 0.125)

        let bestOfThree = try #require(try await store.stats(LadderRequest(regulation: .mB, bestOf: 3)))
        #expect(bestOfThree.format == "gen9championsvgc2026regmbbo3" && bestOfThree.bestOf == 3)
        let singles = try #require(try await store.stats(LadderRequest(regulation: .mB, mode: .singles, rating: 1500)))
        #expect(singles.format == "gen9championsbssregmb" && singles.mode == "singles" && singles.rating == 1500)
        #expect(singles.month == "2026-07", "August has no singles at 1500")
        // Smogon has no best of three for singles.
        #expect(try await store.stats(LadderRequest(regulation: .mB, mode: .singles, bestOf: 3)) == nil)
    }

    @Test("Without its own stats, a regulation falls back to the latest earlier one only when asked to")
    func fallsBackToEarlierRegulation() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb], "2026-07": [Self.mb]])
        let store = Self.store(fake, directory: dir)

        // The Meta tab's ladder shows the regulation's own numbers or none.
        #expect(try await store.stats(.teamSearch(.mC)) == nil)
        #expect(await fake.chaosRequested.isEmpty)
        // Team Search takes the latest earlier regulation's.
        let stats = try #require(try await store.stats(.teamSearch(.mC), fallBack: true))
        #expect(stats.regulation == "M-B")
        #expect(stats.month == "2026-08")
        // The two choices are kept apart.
        #expect(await store.cached(.teamSearch(.mC)) == nil)
        #expect(await store.cached(.teamSearch(.mC), fallBack: true) == stats)
    }

    @Test("A regulation's own older month beats a newer month of another")
    func ownOlderMonthWins() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb], "2026-07": [Self.mb],
                               "2026-06": [Self.maFile, Self.mb]])
        let stats = try #require(try await Self.store(fake, directory: dir).stats(.teamSearch(.mA), fallBack: true))
        #expect(stats.month == "2026-06")
        #expect(stats.regulation == "M-A")
    }

    @Test("Nothing usable within the lookback is nil")
    func nothingUsable() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb], "2026-07": [Self.mb], "2026-06": [Self.maFile]])
        let store = Self.store(fake, directory: dir, lookback: 2)
        // M-A's own month is outside the lookback, and M-B is later than M-A.
        #expect(try await store.stats(.teamSearch(.mA), fallBack: true) == nil)

        let other = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: other) }
        #expect(try await Self.store(FakeSmogon(["2026-08": ["gen9championsou-1760.json"]]),
                                     directory: other).stats(Self.teamSearchMB, fallBack: true) == nil)
    }

    // MARK: Downloading only when asked

    @Test("An offer names the month, the file and its size, without downloading it")
    func offers() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb]])
        let store = Self.store(fake, directory: dir)

        #expect(await store.cached(Self.teamSearchMB) == nil)
        let offer = try #require(try await store.offer(Self.teamSearchMB))
        #expect(offer == SmogonLadderStore.Offer(month: "2026-08", file: Self.mb, bytes: 5_850_354))
        #expect(await store.isDownloaded(offer) == false)
        #expect(await store.cached(Self.teamSearchMB) == nil, "chosen, not downloaded")
        #expect(await fake.chaosRequested.isEmpty)
        #expect(await fake.leadsRequested.isEmpty)

        let stats = try await store.stats(Self.teamSearchMB)
        #expect(await store.isDownloaded(offer))
        #expect(await store.cached(Self.teamSearchMB) == stats)
        #expect(try await store.offer(LadderRequest(regulation: .mB, mode: .singles)) == nil)
    }

    @Test("A month without a leads table still reduces, with no lead shares")
    func withoutLeads() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb]])
        await fake.setLeads(nil)
        let stats = try #require(try await Self.store(fake, directory: dir).stats(Self.teamSearchMB))
        #expect(stats.pokemon.count == 3)
        #expect(stats.pokemon.allSatisfy { $0.leadShare == nil })
    }

    // MARK: Caching

    @Test("The choice and the stats are cached; a stale choice is checked again")
    func caching() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb]])
        let clock = TestClock(TeamSearchFixtures.now)
        let store = Self.store(fake, clock: clock, directory: dir)
        let first = try await store.stats(Self.teamSearchMB)

        #expect(try await store.stats(Self.teamSearchMB) == first)
        #expect(await store.cached(Self.teamSearchMB) == first)
        #expect(await fake.monthRequests == 1)

        clock.advance(hours: 13)                     // past the 12 h choice TTL
        #expect(try await store.stats(Self.teamSearchMB) == first)
        #expect(await fake.monthRequests == 2)
        #expect(await fake.chaosRequested.count == 1)   // the month itself isn't refetched

        // Another store on the same directory reads what this one kept.
        let again = Self.store(FakeSmogon([:]), clock: clock, directory: dir)
        #expect(await again.cached(Self.teamSearchMB) == first)
    }

    @Test("When the month chosen isn't downloaded yet, the newest month on the device is what's cached")
    func newestDownloaded() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = TestClock(TeamSearchFixtures.now)
        let august = try await Self.store(FakeSmogon(["2026-08": [Self.mb]]), clock: clock, directory: dir)
            .stats(Self.teamSearchMB)

        // September comes out; the listing is read again after 12 hours, and nothing is downloaded.
        clock.advance(hours: 13)
        let later = FakeSmogon(["2026-08": [Self.mb, "gen9championsbssregmb-1760.json"], "2026-09": [Self.mb]])
        let store = Self.store(later, clock: clock, directory: dir)
        let offer = try #require(try await store.offer(Self.teamSearchMB))
        #expect(offer.month == "2026-09")
        #expect(await store.isDownloaded(offer) == false)
        #expect(await store.cached(Self.teamSearchMB) == august)
        #expect(await later.chaosRequested.isEmpty)
        // Only the same ladder's: nothing for singles, another rating, or a later regulation's request.
        #expect(await store.cached(LadderRequest(regulation: .mB, mode: .singles)) == nil)
        #expect(await store.cached(LadderRequest(regulation: .mB, rating: 1500)) == nil)
        #expect(await store.cached(.teamSearch(.mC)) == nil)
        #expect(await store.cached(.teamSearch(.mC), fallBack: true) == august, "Team Search takes an earlier regulation's")
        #expect(await store.cached(.teamSearch(.mA), fallBack: true) == nil)

        let september = try await store.stats(Self.teamSearchMB)
        #expect(september?.month == "2026-09")
        #expect(await store.cached(Self.teamSearchMB) == september)
    }

    @Test("Offline, the last choice is used; with none cached it throws")
    func offline() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeSmogon(["2026-08": [Self.mb]])
        let clock = TestClock(TeamSearchFixtures.now)
        let store = Self.store(fake, clock: clock, directory: dir)
        let first = try await store.stats(Self.teamSearchMB)

        await fake.setOffline(true)
        clock.advance(hours: 13)
        #expect(try await store.stats(Self.teamSearchMB) == first)

        let emptyDir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: emptyDir) }
        let empty = Self.store(fake, clock: clock, directory: emptyDir)
        await #expect(throws: URLError.self) { try await empty.stats(Self.teamSearchMB) }
    }

    @Test("Clearing the cache removes choices and stats, and an older version's cache goes too")
    func clearCache() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // What the version before ladder records left: usage and teammates only.
        let old = dir.appending(path: "v1/usage")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: old.appending(path: "2026-08-\(Self.mb)"))

        let store = Self.store(FakeSmogon(["2026-08": [Self.mb]]), directory: dir)
        _ = try await store.stats(Self.teamSearchMB)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "v1").path()))
        #expect(await store.cacheSize() > 0)
        try await store.clearCache()
        #expect(await store.cached(Self.teamSearchMB) == nil)
        #expect(await store.cacheSize() == 0)
    }

    // MARK: Smogon's listing

    @Test("A listing page reads as file names and sizes")
    func listing() {
        let files = SmogonLiveFetcher.listing("""
            <html><body><pre><a href="../">../</a>
            <a href="gen9championsbssregmc-0.json">gen9championsbssregmc-0.json</a>     01-Oct-2026 14:40    612931
            <a href="gen9championsvgc2026regmc-1760.json">gen9championsvgc2026regmc-1760.json</a>  01-Oct-2026 14:40   5850354
            <a href="2026-09/">2026-09/</a>                                           01-Oct-2026 14:40       -
            </pre></body></html>
            """)
        #expect(files == [SmogonFile(name: "../", bytes: nil),
                          SmogonFile(name: "gen9championsbssregmc-0.json", bytes: 612_931),
                          SmogonFile(name: "gen9championsvgc2026regmc-1760.json", bytes: 5_850_354),
                          SmogonFile(name: "2026-09/", bytes: nil)])
    }
}
