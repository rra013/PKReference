//
//  TeamSearchModelTests.swift
//  PKReferenceTests
//
//  Covers `TeamSearchModel`, the state behind the Team Search tab: loading
//  and indexing a corpus, typing into chips and results, chip edits, how
//  load failures show, not refetching on every visit, switching regulation,
//  Smogon's suggestions, and reading unrecognized words with Apple
//  Intelligence. A canned Limitless serves the teams, a canned Smogon (or
//  none) the usage stats, a fake interpreter the model's answers, and the
//  fixture vocabulary stands in for the bundled one.
//

import Testing
import Foundation
@testable import PKReference

/// Serves the same events for any format, recording what was asked for.
private actor CannedLimitless: TeamCorpusFetching {
    let events: [CorpusEvent]
    var listError: Error?
    private(set) var formatsRequested: [String] = []

    init(_ events: [CorpusEvent]) { self.events = events }

    func tournaments(format: String, page: Int, limit: Int) async throws -> [LimitlessTournament] {
        formatsRequested.append(format)
        if let listError { throw listError }
        return page == 1 ? events.map(\.tournament) : []
    }

    func standings(tournamentID: String) async throws -> [LimitlessStanding] {
        events.first { $0.tournament.id == tournamentID }?.standings ?? []
    }

    func failList(with error: Error?) { listError = error }
}

/// One month of M-B stats from the fixtures, or none, or offline.
private struct CannedSmogon: SmogonFetching {
    enum Mode { case stats, empty, offline }
    let mode: Mode

    func months() async throws -> [String] {
        switch mode {
        case .stats: return ["2026-08"]
        case .empty: return []
        case .offline: throw URLError(.notConnectedToInternet)
        }
    }

    func chaosFiles(month: String) async throws -> [SmogonFile] {
        [SmogonFile(name: "gen9championsvgc2026regmb-1760.json", bytes: nil)]
    }

    func chaos(month: String, file: String) async throws -> Data {
        Data(TeamSearchFixtures.smogonChaosJSON.utf8)
    }

    func leads(month: String, file: String) async throws -> String? { nil }
}

/// Holds an answer back until opened.
private actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

/// Canned Apple Intelligence answers, by phrase.
private struct FakeInterpreter: TeamQueryInterpreting {
    var availability: TeamInterpreterAvailability = .available
    var answers: [String: String] = [:]
    var error: TeamInterpretationError?
    var gate: Gate?

    func meanings(of phrases: [String], in description: String,
                  vocabulary: TeamSearchVocabulary) async throws -> [String: String] {
        await gate?.wait()
        if let error { throw error }
        return answers.filter { phrases.contains($0.key) }
    }
}

@MainActor
@Suite("Team Search Model")
struct TeamSearchModelTests {

    private typealias F = TeamSearchFixtures

    private static let trickRoomTeam: [LimitlessStanding.TeamMember] = [
        F.member("Incineroar", moves: ["Fake Out"]), F.member("Garchomp"),
        F.member("Gardevoir", item: "Gardevoirite"), F.member("Rillaboom"),
        F.member("Farigiraf", moves: ["Trick Room"]), F.member("Kingambit"),
    ]
    private static let rainTeam: [LimitlessStanding.TeamMember] = F.six(
        ["Pelipper", "Charizard", "Dragonite", "Sneasler", "Torkoal", "Whimsicott"])

    private static func events() -> [CorpusEvent] {
        [F.event("e1", players: 32, [F.standing("alex", placing: 1, trickRoomTeam),
                                     F.standing("sam", placing: 2, rainTeam)])]
    }

    private static func model(_ fetcher: CannedLimitless, directory: URL,
                              regulation: ChampionsRegulation = .mC,
                              smogon: CannedSmogon.Mode = .empty,
                              interpreter: FakeInterpreter = FakeInterpreter(availability: .unsupported)
    ) -> TeamSearchModel {
        TeamSearchModel(
            regulation: regulation,
            store: TeamCorpusStore(fetcher: fetcher, directory: directory,
                                   now: { F.now }, sleep: { _ in }),
            // No server: the ladder's record is made from Smogon's files.
            ladderStore: LadderStore(serverURL: { nil },
                                     device: SmogonLadderStore(fetcher: CannedSmogon(mode: smogon),
                                                               directory: directory.appending(path: "smogon"),
                                                               now: { F.now })),
            loadVocabulary: { _ in F.vocabulary },
            interpreter: interpreter,
            now: { F.now })
    }

    private static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "TeamSearchModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("Loading shows popular compositions and where they came from")
    func loads() async {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = Self.model(CannedLimitless(Self.events()), directory: dir)

        await model.load()

        #expect(model.status == .ready)
        #expect(model.results.count == 2)
        #expect(model.teamCount == 2)
        #expect(model.eventCount == 1)
        #expect(model.missingEventCount == 0)
        #expect(model.updatedAt == F.now)
        #expect(model.chips.isEmpty)
    }

    @Test("Typing becomes chips and filters the results")
    func typing() async {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = Self.model(CannedLimitless(Self.events()), directory: dir)
        await model.load()

        model.setText("mega gardevoir, no pelipper, bulky")

        #expect(model.chips.map(\.label) == ["Mega Gardevoir", "No Pelipper", "bulky"])
        #expect(model.results.map { $0.teams[0].team.team.standing.player } == ["alex"])
    }

    @Test("Chips can flip between include and exclude, or be removed")
    func chipEdits() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = Self.model(CannedLimitless(Self.events()), directory: dir)
        await model.load()
        model.setText("trick room")
        #expect(model.results.map { $0.teams[0].team.team.standing.player } == ["alex"])

        let style = try #require(model.chips.first)
        model.invert(style)
        #expect(model.chips.map(\.label) == ["No Trick Room"])
        #expect(model.results.map { $0.teams[0].team.team.standing.player } == ["sam"])

        model.remove(try #require(model.chips.first))
        #expect(model.chips.isEmpty)
        #expect(model.results.count == 2)

        // Submitting the same text keeps the edits; changing it starts over.
        model.setText("trick room")
        #expect(model.chips.isEmpty)
        model.setText("Trick Room")
        #expect(model.chips.map(\.label) == ["Trick Room"])
    }

    @Test("A failed first load shows the error; a failed refresh keeps the results")
    func failures() async {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fetcher = CannedLimitless(Self.events())
        await fetcher.failList(with: LimitlessAPIError.http(status: 500))
        let model = Self.model(fetcher, directory: dir)

        await model.load()
        #expect(model.status == .failed("Limitless returned an error (HTTP 500)."))

        await fetcher.failList(with: nil)
        await model.load(forceRefresh: true)
        #expect(model.status == .ready)

        await fetcher.failList(with: LimitlessAPIError.http(status: 404))
        await model.load(forceRefresh: true)
        #expect(model.status == .ready)
        #expect(model.results.count == 2)
        #expect(model.refreshError == "Limitless returned an error (HTTP 404).")
    }

    @Test("Coming back to the tab doesn't refetch while the data is fresh")
    func noRefetchWhileFresh() async {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fetcher = CannedLimitless(Self.events())
        let model = Self.model(fetcher, directory: dir)

        await model.load()
        await model.load()
        #expect(await fetcher.formatsRequested == ["M-C"])

        await model.load(forceRefresh: true)
        #expect(await fetcher.formatsRequested == ["M-C", "M-C"])
    }

    @Test("Smogon suggestions follow the query and add nothing by themselves")
    func smogonSuggestions() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = Self.model(CannedLimitless(Self.events()), directory: dir, smogon: .stats)
        await model.load()

        let insights = try #require(model.insights)
        #expect(insights.usage.regulation == .mB)        // M-C has none yet: the latest earlier
        #expect(model.suggestions.isEmpty)               // nothing named yet

        model.setText("incineroar")
        #expect(model.suggestions.map(\.term.displayName) == ["Garchomp", "Mega Charizard Y"])
        #expect(model.chips.map(\.label) == ["Incineroar"])

        model.setText("incineroar and garchomp")
        #expect(model.suggestions.map(\.term.displayName) == ["Mega Charizard Y"])
    }

    @Test("Without Smogon, search works as before")
    func withoutSmogon() async {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = Self.model(CannedLimitless(Self.events()), directory: dir, smogon: .offline)
        await model.load()
        model.setText("incineroar")

        #expect(model.insights == nil)
        #expect(model.suggestions.isEmpty)
        #expect(model.status == .ready)
        #expect(model.results.count == 1)
    }

    @Test("Switching regulation loads that regulation's teams")
    func switchingRegulation() async {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fetcher = CannedLimitless(Self.events())
        let model = Self.model(fetcher, directory: dir)
        await model.load()
        model.setText("trick room")

        model.regulation = .mB
        await model.load()

        #expect(await fetcher.formatsRequested == ["M-C", "M-B"])
        #expect(model.status == .ready)
        // The text is parsed again with the new regulation's vocabulary.
        #expect(model.chips.map(\.label) == ["Trick Room"])
    }

    // MARK: Apple Intelligence

    @Test("Apple Intelligence reads unrecognized words, and what it adds is marked")
    func interprets() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let interpreter = FakeInterpreter(answers: ["slow": "Trick Room", "big fire cat": "Incineroar",
                                                    "grass monkey": "none"])
        let model = Self.model(CannedLimitless(Self.events()), directory: dir, interpreter: interpreter)
        await model.load()
        model.setText("slow team with the big fire cat and the grass monkey")
        #expect(model.offersInterpretation)
        #expect(model.results.count == 2)                 // nothing understood yet

        await model.interpret()

        #expect(model.interpretation == .finished(added: ["Incineroar", "Trick Room"]))
        #expect(model.chips.map(\.label) == ["Incineroar", "Trick Room", "grass", "monkey"])
        #expect(model.chips.map(model.isInterpreted) == [true, true, false, false])
        #expect(model.results.map { $0.teams[0].team.team.standing.player } == ["alex"])
        #expect(model.offersInterpretation)               // still shows what happened

        // New text starts over.
        model.setText("incineroar")
        #expect(model.interpretation == .idle)
        #expect(model.chips.map(model.isInterpreted) == [false])
        #expect(!model.offersInterpretation)
    }

    @Test("Chips the user removed don't come back; answers that aren't names add nothing")
    func interpretationKeepsEdits() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let interpreter = FakeInterpreter(answers: ["big fire cat": "Incineroar", "bulky": "Bulky Pokémon"])
        let model = Self.model(CannedLimitless(Self.events()), directory: dir, interpreter: interpreter)
        await model.load()
        model.setText("trick room, no big fire cat, bulky")
        model.remove(try #require(model.chips.first { $0.label == "Trick Room" }))

        await model.interpret()

        #expect(model.chips.map(\.label) == ["No Incineroar", "bulky"])
        #expect(model.interpretation == .finished(added: ["No Incineroar"]))
    }

    @Test("A word left in one phrase stays once, even when another phrase with it was read")
    func repeatedWords() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let interpreter = FakeInterpreter(answers: ["hisui fire dog": "Hisuian Arcanine"])
        let model = Self.model(CannedLimitless(Self.events()), directory: dir, interpreter: interpreter)
        await model.load()
        model.setText("hisuian fire dog, no big fire cat, slow")
        #expect(model.chips.map(\.label) == ["fire", "dog", "big", "cat", "slow", "hisui"])
        model.remove(try #require(model.chips.first { $0.label == "slow" }))

        await model.interpret()

        #expect(model.chips.map(\.label) == ["Arcanine (Hisui)", "big", "fire", "cat"])
    }

    @Test("A failure shows its message; a stale answer is dropped")
    func interpretationFailures() async throws {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let failing = Self.model(CannedLimitless(Self.events()), directory: dir,
                                 interpreter: FakeInterpreter(error: .init(message: "Busy.")))
        await failing.load()
        failing.setText("big fire cat")
        await failing.interpret()
        #expect(failing.interpretation == .failed("Busy."))
        #expect(failing.chips.map(\.label) == ["big", "fire", "cat"])

        let other = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: other) }
        let gate = Gate()
        let model = Self.model(CannedLimitless(Self.events()), directory: other,
                               interpreter: FakeInterpreter(answers: ["big fire cat": "Incineroar"], gate: gate))
        await model.load()
        model.setText("big fire cat")
        let running = Task { await model.interpret() }
        while model.interpretation != .running { await Task.yield() }
        model.setText("garchomp")                         // typed on while it ran
        await gate.open()
        await running.value
        #expect(model.interpretation == .idle)
        #expect(model.chips.map(\.label) == ["Garchomp"])
    }

    @Test("Offered only with unrecognized words, on a device that has Apple Intelligence")
    func availability() async {
        let dir = Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for (availability, offered) in [(TeamInterpreterAvailability.available, true), (.notEnabled, true),
                                        (.notReady, true), (.unsupported, false)] {
            let model = Self.model(CannedLimitless(Self.events()), directory: dir,
                                   interpreter: FakeInterpreter(availability: availability))
            await model.load()
            model.setText("incineroar")
            #expect(!model.offersInterpretation)
            model.setText("incineroar with the land shark")
            #expect(model.offersInterpretation == offered, "\(availability)")
            #expect(model.interpreterAvailability == availability)

            // Only an available model runs.
            await model.interpret()
            #expect((model.interpretation == .idle) == (availability != .available), "\(availability)")
        }
    }
}
