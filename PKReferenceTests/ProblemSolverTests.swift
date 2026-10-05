//
//  ProblemSolverTests.swift
//  PKReferenceTests
//
//  Covers the Problem Solver's search (HANDOFF.md's feature notes): every answer
//  is a guaranteed OHKO by the calc itself, at the fewest points (one fewer
//  fails), in the right group; a resisted move isn't an answer; a Speed
//  nature or Choice Scarf is used when it's what moves first; the problem
//  set's Intimidate lowers or raises the counters' stats as their abilities
//  say; abilities with the same result are listed together; and moves with
//  drawbacks are marked. In two-hit mode, what happens between the hits
//  (Sitrus Berry, Leftovers, Multiscale, Draco Meteor's drop, Knock Off)
//  is allowed for, and the battle simulator agrees. Usage comes from
//  tournament teams, a Mega counted by its stone. The Pokémon are in a
//  store in memory, with their real base stats. A timing test runs the
//  whole regulation against the simulator's downloaded Pokédex when it's
//  there.
//

import Testing
import Foundation
import SwiftData
@testable import PKReference

/// Limitless, serving one event.
private actor CannedLimitless: TeamCorpusFetching {
    let events: [CorpusEvent]

    init(_ events: [CorpusEvent]) { self.events = events }

    func tournaments(format: String, page: Int, limit: Int) async throws -> [LimitlessTournament] {
        page == 1 ? events.map(\.tournament) : []
    }

    func standings(tournamentID: String) async throws -> [LimitlessStanding] {
        events.first { $0.tournament.id == tournamentID }?.standings ?? []
    }
}

@MainActor
@Suite("Problem Solver")
struct ProblemSolverTests {

    private struct Store {
        let container: ModelContainer
        let pokemon: [String: PKMNStats]
        let moves: [String: MoveData]
        var all: [PKMNStats] { Array(pokemon.values) }
    }

    private func store() throws -> Store {
        let container = try ModelContainer(
            for: PKMNStats.self, MoveData.self, SavedSpread.self, PKMN.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let rows = [
            PKMNStats(id: 445, speciesID: 445, name: "Garchomp", type1: "Dragon", type2: "Ground",
                      baseHP: 108, baseAtk: 130, baseDef: 95, baseSpAtk: 80, baseSpDef: 85, baseSpeed: 102,
                      ability1: "sand-veil", hiddenAbility: "rough-skin"),
            PKMNStats(id: 485, speciesID: 485, name: "Heatran", type1: "Fire", type2: "Steel",
                      baseHP: 91, baseAtk: 90, baseDef: 106, baseSpAtk: 130, baseSpDef: 106, baseSpeed: 77,
                      ability1: "flash-fire", hiddenAbility: "flame-body"),
            PKMNStats(id: 727, speciesID: 727, name: "Incineroar", type1: "Fire", type2: "Dark",
                      baseHP: 95, baseAtk: 115, baseDef: 90, baseSpAtk: 80, baseSpDef: 90, baseSpeed: 60,
                      ability1: "blaze", hiddenAbility: "intimidate"),
            PKMNStats(id: 983, speciesID: 983, name: "Kingambit", type1: "Dark", type2: "Steel",
                      baseHP: 100, baseAtk: 135, baseDef: 120, baseSpAtk: 60, baseSpDef: 85, baseSpeed: 50,
                      ability1: "defiant", ability2: "supreme-overlord", hiddenAbility: "pressure"),
            PKMNStats(id: 887, speciesID: 887, name: "Dragapult", type1: "Dragon", type2: "Ghost",
                      baseHP: 88, baseAtk: 120, baseDef: 75, baseSpAtk: 100, baseSpDef: 75, baseSpeed: 142,
                      ability1: "clear-body", ability2: "infiltrator", hiddenAbility: "cursed-body"),
            PKMNStats(id: 94, speciesID: 94, name: "Gengar", type1: "Ghost", type2: "Poison",
                      baseHP: 60, baseAtk: 65, baseDef: 60, baseSpAtk: 130, baseSpDef: 75, baseSpeed: 110,
                      ability1: "cursed-body"),
            PKMNStats(id: 730, speciesID: 730, name: "Primarina", type1: "Water", type2: "Fairy",
                      baseHP: 80, baseAtk: 74, baseDef: 74, baseSpAtk: 126, baseSpDef: 116, baseSpeed: 60,
                      ability1: "torrent", hiddenAbility: "liquid-voice"),
        ]
        let moves = [
            MoveData(id: 89, name: "Earthquake", type: "Ground", damageClass: "physical",
                     power: 100, accuracy: 100, pp: 10, generationId: 1),
            MoveData(id: 337, name: "Dragon Claw", type: "Dragon", damageClass: "physical",
                     power: 80, accuracy: 100, pp: 15, makesContact: true, generationId: 3),
            MoveData(id: 389, name: "Sucker Punch", type: "Dark", damageClass: "physical",
                     power: 70, accuracy: 100, pp: 5, priority: 1, makesContact: true, generationId: 4),
            MoveData(id: 264, name: "Focus Punch", type: "Fighting", damageClass: "physical",
                     power: 150, accuracy: 100, pp: 20, priority: -3, makesContact: true, generationId: 3),
            MoveData(id: 434, name: "Draco Meteor", type: "Dragon", damageClass: "special",
                     power: 130, accuracy: 90, pp: 5, generationId: 4),
            MoveData(id: 282, name: "Knock Off", type: "Dark", damageClass: "physical",
                     power: 65, accuracy: 100, pp: 20, makesContact: true, generationId: 3),
            MoveData(id: 917, name: "Psychic Noise", type: "Psychic", damageClass: "special",
                     power: 75, accuracy: 100, pp: 10, generationId: 9),
        ]
        rows.forEach { context.insert($0) }
        moves.forEach { context.insert($0) }
        try context.save()
        return Store(container: container,
                     pokemon: Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0) }),
                     moves: Dictionary(uniqueKeysWithValues: moves.map { ($0.name, $0) }))
    }

    private func side(_ name: String, in store: Store, ability: String? = nil,
                      configure: (CalcSide) -> Void = { _ in }) throws -> CalcSide {
        let side = CalcSide()
        side.loadUninvested(try #require(store.pokemon[name]), championsMode: true, allPokemon: store.all)
        if let ability { side.selectedAbility = ability }
        configure(side)
        return side
    }

    private func candidate(_ name: String, _ move: String, in store: Store,
                           ability: String? = nil) throws -> ProblemSolver.Candidate {
        let move = try #require(store.moves[move])
        return ProblemSolver.Candidate(
            pokemonID: try #require(store.pokemon[name]).id,
            attacker: try #require(try side(name, in: store, ability: ability).snapshot()),
            move: move.snapshot(), accuracy: move.accuracy, priority: move.priority,
            marks: ProblemSolver.marks(for: move.name),
            selfStatChanges: ProblemSolver.selfStatChanges(for: move.name))
    }

    private func problem(_ name: String, in store: Store, ability: String? = nil, intimidate: Bool = true,
                         configure: (CalcSide) -> Void = { _ in }) throws -> ProblemSolver.Problem {
        ProblemSolver.Problem(
            defender: try #require(try side(name, in: store, ability: ability, configure: configure).snapshot()),
            intimidate: intimidate)
    }

    /// Every answer is a guaranteed OHKO by the calc, at the fewest points:
    /// one fewer attacking point fails, and one fewer Speed point doesn't
    /// outspeed (under Trick Room, moving first means being slower).
    private func expectMinimal(_ counter: ProblemSolver.Counter, _ problem: ProblemSolver.Problem) {
        let damage = { (attacker: CalcSnapshot) in
            CalcEngine.evaluate(move: counter.move, attacker: attacker, defender: problem.defender,
                                field: problem.field)
        }
        #expect(damage(counter.attacker).isGuaranteedOHKO)
        if let stat = counter.attackStat?.natureKey, counter.attackPoints > 0 {
            #expect(!damage(counter.attacker.settingEV(stat, to: counter.attackPoints - 1)).isGuaranteedOHKO)
        }
        let target = ProblemSolver.speed(problem.defender, problem.field)
        if problem.trickRoom, counter.group == .outspeeds {
            // Under Trick Room, first means slower, with no Speed points.
            #expect(counter.speed < target && counter.speedPoints == 0)
        } else if let points = counter.speedPoints {
            #expect(counter.speed > target)
            if points > 0 {
                #expect(ProblemSolver.speed(counter.attacker.settingEV(.speed, to: points - 1), problem.field) <= target)
            }
        }
    }

    // MARK: Finding answers

    /// Full HP and Defense Heatran: Garchomp's Earthquake, a spread move at
    /// 0.75×, still KOs, and Garchomp is faster.
    @Test("A guaranteed OHKO is found at its fewest points, and moves first")
    func findsOHKO() throws {
        let store = try store()
        let problem = try problem("Heatran", in: store) { $0.evHP = 32; $0.evDef = 32 }
        let counters = ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Earthquake", in: store, ability: "rough-skin"),
        ])
        let counter = try #require(counters.first)
        #expect(counter.group == .outspeeds)
        #expect(counter.attacker.heldItem == .softSand)
        #expect(counter.attackStat == .atk)
        expectMinimal(counter, problem)
    }

    @Test("A resisted move that can't KO isn't an answer")
    func noKO() throws {
        let store = try store()
        let problem = try problem("Heatran", in: store)
        #expect(ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Dragon Claw", in: store),
        ]).isEmpty)
    }

    @Test("A priority move KOs without needing Speed")
    func priority() throws {
        let store = try store()
        let problem = try problem("Dragapult", in: store)
        let counter = try #require(ProblemSolver.solve(problem, candidates: [
            try candidate("Kingambit", "Sucker Punch", in: store, ability: "supreme-overlord"),
        ]).first)
        #expect(counter.group == .priority && counter.speedPoints == nil)
        #expect(counter.attacker.heldItem == .blackGlasses)
        expectMinimal(counter, problem)
    }

    /// Focus Punch has -3 priority: however fast the user, it goes last.
    @Test("A negative-priority move is slower, and marked")
    func movesLast() throws {
        let store = try store()
        let problem = try problem("Kingambit", in: store)
        let counter = try #require(ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Focus Punch", in: store),
        ]).first)
        #expect(counter.group == .slower && counter.speedPoints == nil)
        #expect(counter.marks.isSuperset(of: [.movesLast, .failsIfHit]))
        expectMinimal(counter, problem)
    }

    /// Full-Speed Gengar (neutral) is faster than Adamant Garchomp at full
    /// Speed, but not Jolly Garchomp.
    @Test("A Speed nature is used when it's what moves first")
    func speedNature() throws {
        let store = try store()
        let problem = try problem("Gengar", in: store) { $0.evSpeed = 32 }
        let counter = try #require(ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Earthquake", in: store),
        ]).first)
        #expect(counter.group == .outspeeds)
        #expect(counter.attacker.nature.id == "jolly")
        expectMinimal(counter, problem)
    }

    /// Jolly, full-Speed Dragapult outspeeds any Garchomp without an item,
    /// but not a Jolly one holding Choice Scarf, whose Dragon Claw still KOs
    /// without Dragon Fang.
    @Test("Choice Scarf is tried when nothing else moves first")
    func choiceScarf() throws {
        let store = try store()
        let problem = try problem("Dragapult", in: store) {
            $0.evSpeed = 32
            $0.nature = allNatures.first { $0.id == "jolly" }!
        }
        let counters = ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Dragon Claw", in: store),
        ])
        let slower = try #require(counters.first { $0.group == .slower })
        #expect(slower.attacker.heldItem == .dragonFang)
        let scarfed = try #require(counters.first { $0.group == .outspeeds })
        #expect(scarfed.attacker.heldItem == .choiceScarf)
        #expect(counters.first?.id == scarfed.id)
        expectMinimal(scarfed, problem)
    }

    // MARK: Intimidate

    @Test("Intimidate's effect on each kind of ability")
    func intimidateTable() {
        #expect(ProblemSolver.intimidated(ability: "rough-skin") == (-1, 0, 0))
        #expect(ProblemSolver.intimidated(ability: "clear-body") == (0, 0, 0))
        #expect(ProblemSolver.intimidated(ability: "defiant") == (1, 0, 0))
        #expect(ProblemSolver.intimidated(ability: "competitive") == (-1, 2, 0))
        #expect(ProblemSolver.intimidated(ability: "simple") == (-2, 0, 0))
        #expect(ProblemSolver.intimidated(ability: "rattled") == (-1, 0, 1))
    }

    /// Uninvested Incineroar with Intimidate: Garchomp's Earthquake KOs it
    /// at full Attack, but not at -1, and turning the switch off gives the
    /// KO back. Clear Body ignores Intimidate; Defiant gains from it.
    @Test("The problem set's Intimidate lowers or raises the counters' Attack")
    func intimidate() throws {
        let store = try store()
        let on = try problem("Incineroar", in: store, ability: "intimidate")
        let off = try problem("Incineroar", in: store, ability: "intimidate", intimidate: false)
        let chomp = try candidate("Garchomp", "Earthquake", in: store, ability: "rough-skin")
        #expect(ProblemSolver.solve(on, candidates: [chomp]).isEmpty)
        let plain = try #require(ProblemSolver.solve(off, candidates: [chomp]).first)
        #expect(plain.attacker.atkStage == 0)
        expectMinimal(plain, off)

        #expect(ProblemSolver.prepared(chomp, on).atkStage == -1)
        #expect(ProblemSolver.prepared(try candidate("Dragapult", "Dragon Claw", in: store, ability: "clear-body"), on)
                    .atkStage == 0)
        #expect(ProblemSolver.prepared(try candidate("Kingambit", "Sucker Punch", in: store, ability: "defiant"), on)
                    .atkStage == 1)
    }

    // MARK: Listing

    @Test("Abilities with the same result are listed together")
    func mergesAbilities() throws {
        let store = try store()
        let problem = try problem("Heatran", in: store)
        let counters = ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Earthquake", in: store, ability: "sand-veil"),
            try candidate("Garchomp", "Earthquake", in: store, ability: "rough-skin"),
        ])
        #expect(counters.count == 1)
        #expect(Set(try #require(counters.first).abilities) == ["sand-veil", "rough-skin"])
    }

    @Test("Moves with drawbacks are marked")
    func marks() {
        #expect(ProblemSolver.marks(for: "Hyper Beam") == [.mustRecharge])
        #expect(ProblemSolver.marks(for: "Explosion") == [.faintsUser])
        #expect(ProblemSolver.marks(for: "Solar Beam") == [.chargesFirst])
        #expect(ProblemSolver.marks(for: "Fake Out") == [.firstTurnOnly])
        #expect(ProblemSolver.marks(for: "Focus Punch") == [.failsIfHit])
        #expect(ProblemSolver.marks(for: "Earthquake").isEmpty)
    }

    // MARK: The whole regulation

    /// Against the simulator's downloaded Pokédex, when it's there: every
    /// Regulation M-C Pokémon, form and Mega against full HP and Defense
    /// Intimidate Incineroar, within a budget, and every answer checks out.
    @Test("The whole regulation, timed")
    func wholeRegulation() throws {
        let context = AppModelContainer.shared.mainContext
        guard let incineroar = try context.fetch(FetchDescriptor<PKMNStats>(
            predicate: #Predicate { $0.name == "Incineroar" })).first else {
            print("[ProblemSolverTests] No downloaded Pokédex; skipping the timing test.")
            return
        }
        let all = try context.fetch(FetchDescriptor<PKMNStats>())
        let dexNames = Dictionary(try context.fetch(FetchDescriptor<PKMN>()).map { ($0.nationalPokedexNumber, $0.name) },
                                  uniquingKeysWith: { first, _ in first })
        let unmatched = ProblemSolver.rosterRows(for: .mC, allPokemon: all, dexNames: dexNames)
            .filter { $0.row == nil }.map(\.name)
        #expect(unmatched.isEmpty, "Regulation species without a Pokédex match: \(unmatched)")
        let target = CalcSide()
        target.loadUninvested(incineroar, championsMode: true, allPokemon: all)
        target.selectedAbility = "intimidate"
        target.evHP = 32
        target.evDef = 32
        let problem = ProblemSolver.Problem(defender: try #require(target.snapshot()))

        let started = Date()
        let candidates = ProblemSolver.candidates(for: .mC, in: context)
        let built = Date()
        let counters = ProblemSolver.solve(problem, candidates: candidates)
        let finished = Date()
        let species = Set(candidates.map(\.attacker.species.name)).count
        print(String(format: "[ProblemSolverTests] %d candidates from %d species in %.2fs; %d counters in %.2fs",
                     candidates.count, species, built.timeIntervalSince(started),
                     counters.count, finished.timeIntervalSince(built)))
        for group in ProblemSolver.Group.allCases {
            let top = counters.filter { $0.group == group }.prefix(3)
                .map { "\($0.name) \($0.move.name) \($0.attackPoints)+\($0.speedPoints ?? 0)" }
            print("[ProblemSolverTests] \(group): \(counters.filter { $0.group == group }.count), e.g. \(top)")
        }

        #expect(!counters.isEmpty)
        #expect(finished.timeIntervalSince(started) < 30)
        for counter in counters { expectMinimal(counter, problem) }

        // Every candidate's move is one its species (or a form of it)
        // learns in the regulation.
        let learnsets = ChampionsLearnsetStore.store(for: .mC)
        var learnable: [Int: Set<String>] = [:]
        for (name, row) in ProblemSolver.rosterRows(for: .mC, allPokemon: all, dexNames: dexNames) {
            guard let row, let data = learnsets.data(for: name) else { continue }
            let moves = data.moves + data.alternateForms.flatMap { $0.moves ?? [] }
            learnable[row.speciesID, default: []].formUnion(moves.map(IntentNames.key))
        }
        let rows = Dictionary(all.map { ($0.id, $0.speciesID) }, uniquingKeysWith: { first, _ in first })
        let unlearnable = candidates.filter { candidate in
            guard let species = rows[candidate.pokemonID] else { return true }
            return !(learnable[species]?.contains(IntentNames.key(candidate.move.name)) ?? false)
        }.map { "\($0.attacker.species.name) \($0.move.name)" }
        #expect(unlearnable.isEmpty, "Candidates with moves they don't learn: \(unlearnable.prefix(10))")
        #expect(!candidates.contains { $0.attacker.species.name == "Garchomp" && $0.move.name == "Knock Off" })
    }

    /// Two hits against full HP and Defense Intimidate Incineroar holding
    /// a Sitrus Berry: the fast check over the whole regulation, then the
    /// simulator over every answer, each within a budget. The simulator
    /// confirms nearly all of them as they are.
    @Test("The whole regulation in two hits, timed")
    func wholeRegulationTwoHits() throws {
        let context = AppModelContainer.shared.mainContext
        guard let incineroar = try context.fetch(FetchDescriptor<PKMNStats>(
            predicate: #Predicate { $0.name == "Incineroar" })).first else {
            print("[ProblemSolverTests] No downloaded Pokédex; skipping the two-hit timing test.")
            return
        }
        let all = try context.fetch(FetchDescriptor<PKMNStats>())
        let moves = try context.fetch(FetchDescriptor<MoveData>())
        let target = CalcSide()
        target.loadUninvested(incineroar, championsMode: true, allPokemon: all)
        target.selectedAbility = "intimidate"
        target.evHP = 32
        target.evDef = 32
        target.heldItem = .sitrusBerry
        let problem = ProblemSolver.Problem(defender: try #require(target.snapshot()), twoHits: true)

        let candidates = ProblemSolver.candidates(for: .mC, in: context)
        let started = Date()
        let counters = ProblemSolver.solve(problem, candidates: candidates)
        let solved = Date()
        let vm = DamageCalcVM()
        vm.multi = true
        #expect(try #require(SideSetup(target)).apply(to: vm.side2, allPokemon: all, allMoves: moves))
        let byID = Dictionary(moves.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var (confirmed, raised, dropped) = (0, 0, [String]())
        for counter in counters {
            #expect(ProblemSolver.needsSimulation(counter, problem))
            let move = try #require(byID[counter.move.id])
            switch ProblemSolver.simulated(counter, problem, vm: vm, move: move, allPokemon: all, allMoves: moves) {
            case let checked? where checked.attackPoints == counter.attackPoints: confirmed += 1
            case .some: raised += 1
            case nil: dropped.append("\(counter.name) \(counter.move.name)")
            }
        }
        let finished = Date()
        print(String(format: "[ProblemSolverTests] Two hits: %d counters from %d Pokémon in %.2fs; simulator in %.2fs: %d confirmed, %d raised, %d dropped %@",
                     counters.count, Set(counters.map(\.name)).count, solved.timeIntervalSince(started),
                     finished.timeIntervalSince(solved), confirmed, raised, dropped.count, dropped.prefix(8).description))

        #expect(!counters.isEmpty)
        #expect(solved.timeIntervalSince(started) < 30)
        #expect(finished.timeIntervalSince(solved) < 60)
        #expect(confirmed * 100 >= counters.count * 95)
    }

    // MARK: The screen's pieces

    /// A side with a bit of everything survives the trip into a setup and
    /// back.
    @Test("A calc side loads back exactly")
    func sideSetupRoundTrip() throws {
        let store = try store()
        let side = try side("Garchomp", in: store, ability: "rough-skin") {
            $0.heldItem = .softSand
            $0.nature = allNatures.first { $0.id == "jolly" }!
            $0.evAtk = 28; $0.evSpeed = 20
            $0.atkStage = -1
            $0.status = .brn
            $0.isReflect = true
            $0.moves = [store.moves["Earthquake"], nil, store.moves["Dragon Claw"], nil]
        }
        let setup = try #require(SideSetup(side))
        let loaded = CalcSide()
        #expect(setup.apply(to: loaded, allPokemon: store.all, allMoves: Array(store.moves.values)))
        #expect(loaded.snapshot() == side.snapshot())
    }

    /// Opening an answer in the calc loads the attacker exactly as solved,
    /// Intimidate's stage included.
    @Test("An answer opens in the calc as solved")
    func answerInCalc() throws {
        let store = try store()
        let problem = try problem("Incineroar", in: store, ability: "intimidate", intimidate: false)
        let counter = try #require(ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Earthquake", in: store, ability: "rough-skin"),
        ]).first)
        let side = CalcSide()
        #expect(SideSetup(counter.attacker, pokemonID: counter.pokemonID)
            .apply(to: side, allPokemon: store.all, allMoves: Array(store.moves.values)))
        #expect(side.snapshot() == counter.attacker)
        let calc = CalcEngine.evaluate(move: counter.move, attacker: try #require(side.snapshot()),
                                       defender: problem.defender, field: problem.field)
        #expect(calc == counter.outcome)
    }

    @Test("How an answer is described")
    func wording() throws {
        let store = try store()
        let problem = try problem("Dragapult", in: store) {
            $0.evSpeed = 32
            $0.nature = allNatures.first { $0.id == "jolly" }!
        }
        let counters = ProblemSolver.solve(problem, candidates: [try candidate("Garchomp", "Dragon Claw", in: store)])
        let scarfed = try #require(counters.first { $0.group == .outspeeds })
        #expect(scarfed.itemName == "Choice Scarf")
        #expect(scarfed.pointsLabel.hasSuffix("Spe"))
        #expect(scarfed.percentLabel.contains("% – "))

        var marked = scarfed
        marked.accuracy = 90
        marked.marks = [.mustRecharge, .speedTie]
        #expect(marked.notes == ["90% accurate", "Must recharge", "Can only tie on Speed"])

        let spread = scarfed.savedSpread(named: "Scarf Chomp")
        #expect(spread.pokemonID == 445 && spread.itemRawValue == "Choice Scarf" && spread.moveID1 == 337)
        #expect(spread.evSpeed == scarfed.attacker.evSpeed && spread.natureID == scarfed.attacker.nature.id)
        #expect(spread.championsMode)
    }

    /// The screen's model builds the candidates from the regulation and the
    /// store, and solves off the main thread.
    @Test("The screen's model solves from the store")
    func model() async throws {
        let store = try store()
        let context = store.container.mainContext
        let problem = try problem("Heatran", in: store)
        let model = ProblemSolverModel()
        #expect(model.status == .waiting)
        await model.solve(problem, target: nil, regulation: .mC, context: context)
        #expect(model.status == .solved)
        #expect(model.candidateCount > 0)
        #expect(model.counters.contains { $0.name == "Garchomp" && $0.move.name == "Earthquake" })
        await model.solve(nil, target: nil, regulation: .mC, context: context)
        #expect(model.status == .waiting && model.counters.isEmpty)
    }

    // MARK: The field

    private func fastDragapult(in store: Store, trickRoom: Bool = false, tailwind: Bool = false) throws
        -> ProblemSolver.Problem {
        let base = try problem("Dragapult", in: store) {
            $0.evSpeed = 32
            $0.nature = allNatures.first { $0.id == "jolly" }!
        }
        return ProblemSolver.Problem(defender: base.defender, tailwind: tailwind, trickRoom: trickRoom)
    }

    /// Under Trick Room the slower Pokémon moves first, so Garchomp wants a
    /// Speed-lowering nature and no Speed points, and no Choice Scarf.
    @Test("Trick Room puts the slower Pokémon first")
    func trickRoom() throws {
        let store = try store()
        let problem = try fastDragapult(in: store, trickRoom: true)
        let counters = ProblemSolver.solve(problem, candidates: [try candidate("Garchomp", "Dragon Claw", in: store)])
        let counter = try #require(counters.first)
        #expect(counters.count == 1)
        #expect(counter.group == .outspeeds && counter.speedPoints == 0)
        #expect(counter.attacker.nature.id == "brave" && counter.attacker.heldItem == .dragonFang)
        #expect(counter.speed < ProblemSolver.speed(problem.defender, problem.field))
        expectMinimal(counter, problem)
    }

    /// Tailwind doubles Garchomp's Speed, so it outspeeds Jolly Dragapult
    /// holding Dragon Fang, with no need for Choice Scarf.
    @Test("Tailwind doubles the counters' Speed")
    func tailwind() throws {
        let store = try store()
        let problem = try fastDragapult(in: store, tailwind: true)
        let counter = try #require(ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Dragon Claw", in: store),
        ]).first)
        #expect(counter.group == .outspeeds && counter.attacker.heldItem == .dragonFang)
        #expect(counter.attacker.isTailwind)
        expectMinimal(counter, problem)
    }

    @Test("Helping Hand powers up the counters")
    func helpingHand() throws {
        let store = try store()
        let bulky: (CalcSide) -> Void = { $0.evHP = 32; $0.evDef = 32 }
        let plain = try problem("Heatran", in: store, configure: bulky)
        let helped = ProblemSolver.Problem(defender: plain.defender, helpingHand: true)
        let chomp = try candidate("Garchomp", "Earthquake", in: store, ability: "rough-skin")
        let alone = try #require(ProblemSolver.solve(plain, candidates: [chomp]).first)
        let boosted = try #require(ProblemSolver.solve(helped, candidates: [chomp]).first)
        #expect(boosted.attackPoints <= alone.attackPoints)
        #expect(ProblemSolver.prepared(chomp, helped).isHelpingHand)
        expectMinimal(boosted, helped)
    }

    /// A two-turn move that weather skips (Solar Beam in sun) isn't marked
    /// as charging first in that weather.
    @Test("Weather that skips a charge turn clears the mark")
    func chargeInWeather() throws {
        let store = try store()
        var solarLike = try candidate("Garchomp", "Earthquake", in: store)
        solarLike.marks = [.chargesFirst]
        solarLike.chargeSkipWeather = .sun
        let defender = try problem("Heatran", in: store).defender
        let sunny = try #require(ProblemSolver.solve(ProblemSolver.Problem(defender: defender, weather: .sun),
                                                     candidates: [solarLike]).first)
        let clear = try #require(ProblemSolver.solve(ProblemSolver.Problem(defender: defender),
                                                     candidates: [solarLike]).first)
        #expect(!sunny.marks.contains(.chargesFirst) && clear.marks.contains(.chargesFirst))
    }

    @Test("Psychic Terrain stops priority moves on a grounded target")
    func psychicTerrain() throws {
        let store = try store()
        let defender = try problem("Dragapult", in: store).defender
        let sucker = try candidate("Kingambit", "Sucker Punch", in: store, ability: "supreme-overlord")
        let terrain = ProblemSolver.Problem(defender: defender, terrain: .psychic)
        #expect(terrain.blocksPriority)
        #expect(ProblemSolver.solve(terrain, candidates: [sucker]).isEmpty)
        #expect(!ProblemSolver.solve(ProblemSolver.Problem(defender: defender), candidates: [sucker]).isEmpty)
    }

    @Test("The results filter finds answers by Pokémon, move or ability")
    func filter() throws {
        let store = try store()
        let counter = try #require(ProblemSolver.solve(try problem("Heatran", in: store), candidates: [
            try candidate("Garchomp", "Earthquake", in: store, ability: "sand-veil"),
            try candidate("Garchomp", "Earthquake", in: store, ability: "rough-skin"),
        ]).first)
        for text in ["", "garch", "Earthquake", "rough skin", "Rough-Skin", "SAND"] {
            #expect(counter.matches(filter: text), "\(text)")
        }
        #expect(!counter.matches(filter: "levitate"))
        #expect(counter.abilityMatching(filter: "skin") == "rough-skin")
        // Found by its name, so no ability to point out.
        #expect(counter.abilityMatching(filter: "garchomp") == nil)
        #expect(counter.abilityMatching(filter: "") == nil)
    }

    @Test("Answers group by Pokémon, in order")
    func grouping() throws {
        let store = try store()
        let problem = try problem("Kingambit", in: store)
        let counters = ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Earthquake", in: store),
            try candidate("Garchomp", "Focus Punch", in: store),
        ])
        let grouped = ProblemSolver.byPokemon(counters)
        #expect(grouped.count == 1 && grouped[0].count == counters.count)
        #expect(grouped[0].map(\.id) == counters.map(\.id))
    }

    // MARK: Two hits

    private func twoHitProblem(_ name: String, in store: Store, ability: String? = nil,
                               configure: (CalcSide) -> Void = { _ in }) throws -> ProblemSolver.Problem {
        let target = try side(name, in: store, ability: ability, configure: configure)
        return ProblemSolver.Problem(defender: try #require(target.snapshot()), twoHits: true)
    }

    /// Every two-hit answer KOs by the fast check, and one fewer attacking
    /// point doesn't.
    private func expectTwoHitMinimal(_ counter: ProblemSolver.Counter, _ problem: ProblemSolver.Problem) {
        let hits = { (attacker: CalcSnapshot) in
            ProblemSolver.twoHits(counter.move, attacker, problem,
                                  selfStatChanges: ProblemSolver.selfStatChanges(for: counter.move.name))
        }
        #expect(hits(counter.attacker).isGuaranteedKO)
        if let stat = counter.attackStat?.natureKey, counter.attackPoints > 0 {
            #expect(!hits(counter.attacker.settingEV(stat, to: counter.attackPoints - 1)).isGuaranteedKO)
        }
    }

    /// The battle simulator, with `problem`'s target as side 2.
    private func simulator(for problem: ProblemSolver.Problem, target: CalcSide, in store: Store) throws -> DamageCalcVM {
        let vm = DamageCalcVM()
        vm.multi = true
        let setup = try #require(SideSetup(target))
        #expect(setup.apply(to: vm.side2, allPokemon: store.all, allMoves: Array(store.moves.values)))
        return vm
    }

    /// The simulator confirms the answer at its points, and from one point
    /// fewer finds its way back up to them.
    private func expectSimulatorAgrees(_ counter: ProblemSolver.Counter, _ problem: ProblemSolver.Problem,
                                       target: CalcSide, in store: Store) throws {
        let vm = try simulator(for: problem, target: target, in: store)
        let move = try #require(store.moves[counter.move.name])
        let (all, moves) = (store.all, Array(store.moves.values))
        let checked = try #require(ProblemSolver.simulated(counter, problem, vm: vm, move: move,
                                                                 allPokemon: all, allMoves: moves))
        #expect(checked.simulated && checked.attackPoints == counter.attackPoints)
        guard let stat = counter.attackStat?.natureKey, counter.attackPoints > 0 else { return }
        var weaker = counter
        weaker.attacker = counter.attacker.settingEV(stat, to: counter.attackPoints - 1)
        weaker.attackPoints -= 1
        let climbed = ProblemSolver.simulated(weaker, problem, vm: vm, move: move, allPokemon: all, allMoves: moves)
        #expect(climbed?.attackPoints == counter.attackPoints)
    }

    /// Full HP and Defense Garchomp takes a little over half from Dragon
    /// Claw: no one-hit KO, but two hits do it.
    @Test("Two hits find what one can't, at the fewest points")
    func twoHits() throws {
        let store = try store()
        let bulky: (CalcSide) -> Void = { $0.evHP = 32; $0.evDef = 32 }
        let claw = try candidate("Garchomp", "Dragon Claw", in: store, ability: "rough-skin")
        #expect(ProblemSolver.solve(try problem("Garchomp", in: store, configure: bulky), candidates: [claw]).isEmpty)
        let problem = try twoHitProblem("Garchomp", in: store, configure: bulky)
        let counter = try #require(ProblemSolver.solve(problem, candidates: [claw]).first)
        let hits = try #require(counter.twoHits)
        #expect(hits.first == counter.outcome && !counter.outcome.isGuaranteedOHKO)
        #expect(hits.second.damageMin * 2 >= Double(counter.outcome.defenderHP))
        #expect(counter.damageSummary.hasSuffix("a guaranteed two-hit KO."))
        expectTwoHitMinimal(counter, problem)
    }

    /// A Sitrus Berry heals a quarter once the first hit takes Garchomp to
    /// half, so Dragon Claw needs Attack points it didn't before.
    @Test("A Sitrus Berry between the hits needs more, and the simulator agrees")
    func sitrus() throws {
        let store = try store()
        let setup: (CalcSide) -> Void = { $0.evHP = 32; $0.evDef = 32; $0.heldItem = .sitrusBerry }
        let problem = try twoHitProblem("Garchomp", in: store, configure: setup)
        let claw = try candidate("Garchomp", "Dragon Claw", in: store, ability: "rough-skin")
        let counter = try #require(ProblemSolver.solve(problem, candidates: [claw]).first)
        #expect(counter.attackPoints > 0)
        let hits = try #require(counter.twoHits)
        #expect(hits.hpBeforeSecond > counter.outcome.defenderHP - Int(counter.outcome.damageMin))
        expectTwoHitMinimal(counter, problem)
        #expect(ProblemSolver.needsSimulation(counter, problem))
        try expectSimulatorAgrees(counter, problem, target: try side("Garchomp", in: store, configure: setup), in: store)
    }

    /// Multiscale halves only the first hit, from full HP.
    @Test("Multiscale only softens the first hit, and the simulator agrees")
    func multiscale() throws {
        let store = try store()
        let setup: (CalcSide) -> Void = { $0.evHP = 32; $0.evDef = 32 }
        let problem = try twoHitProblem("Garchomp", in: store, ability: "multiscale", configure: setup)
        let claw = try candidate("Garchomp", "Dragon Claw", in: store, ability: "rough-skin")
        let counter = try #require(ProblemSolver.solve(problem, candidates: [claw]).first)
        let hits = try #require(counter.twoHits)
        #expect(hits.second.damageMin > hits.first.damageMin * 1.9)
        expectTwoHitMinimal(counter, problem)
        try expectSimulatorAgrees(counter, problem,
                                        target: try side("Garchomp", in: store, ability: "multiscale", configure: setup),
                                        in: store)
    }

    /// Draco Meteor's second hit is at -2 Sp. Atk; Knock Off's has no
    /// item to boost it once the first has taken it.
    @Test("A move that changes after the first hit, and the simulator agrees")
    func changingMoves() throws {
        let store = try store()
        let draco = try twoHitProblem("Garchomp", in: store) { $0.evHP = 32; $0.evSpDef = 32 }
        let meteor = try #require(ProblemSolver.solve(draco, candidates: [
            try candidate("Dragapult", "Draco Meteor", in: store, ability: "clear-body"),
        ]).first)
        let meteorHits = try #require(meteor.twoHits)
        #expect(meteorHits.second.damageMin < meteorHits.first.damageMin * 0.6)
        #expect(ProblemSolver.needsSimulation(meteor, draco))
        expectTwoHitMinimal(meteor, draco)

        let setup: (CalcSide) -> Void = { $0.evHP = 32; $0.evDef = 32; $0.heldItem = .sitrusBerry }
        let knock = try twoHitProblem("Dragapult", in: store, configure: setup)
        let counters = ProblemSolver.solve(knock, candidates: [
            try candidate("Kingambit", "Knock Off", in: store, ability: "defiant"),
        ])
        let scarfed = try #require(counters.first { $0.attacker.heldItem == .choiceScarf })
        let knockHits = try #require(scarfed.twoHits)
        #expect(knockHits.second.damageMin < knockHits.first.damageMin)
        expectTwoHitMinimal(scarfed, knock)
        try expectSimulatorAgrees(scarfed, knock, target: try side("Dragapult", in: store, configure: setup),
                                        in: store)
    }

    @Test("Only moves that can land on two turns running")
    func hitsTwice() throws {
        let store = try store()
        let problem = try twoHitProblem("Heatran", in: store)
        var move = try candidate("Garchomp", "Earthquake", in: store)
        #expect(ProblemSolver.canHitTwice(move, problem))
        for mark in [ProblemSolver.Mark.mustRecharge, .faintsUser, .firstTurnOnly, .chargesFirst] {
            move.marks = [mark]
            #expect(!ProblemSolver.canHitTwice(move, problem))
            #expect(ProblemSolver.solve(problem, candidates: [move]).isEmpty)
        }
        move.chargeSkipWeather = .sun
        #expect(ProblemSolver.canHitTwice(move, ProblemSolver.Problem(defender: problem.defender, weather: .sun,
                                                                       twoHits: true)))
    }

    @Test("How a two-hit answer is described")
    func twoHitWording() throws {
        let store = try store()
        let setup: (CalcSide) -> Void = { $0.evHP = 32; $0.evDef = 32; $0.heldItem = .sitrusBerry }
        let problem = try twoHitProblem("Garchomp", in: store, configure: setup)
        let counter = try #require(ProblemSolver.solve(problem, candidates: [
            try candidate("Garchomp", "Dragon Claw", in: store, ability: "rough-skin"),
        ]).first)
        #expect(counter.twoHitNotes(problem, targetName: "Garchomp") == ["Allows for Garchomp's Sitrus Berry."])
        var checked = counter
        checked.simulated = true
        #expect(checked.twoHitNotes(problem, targetName: "Garchomp").last == "Checked in the battle simulator.")
        let helped = ProblemSolver.Problem(defender: problem.defender, helpingHand: true, twoHits: true)
        #expect(!ProblemSolver.needsSimulation(counter, helped))
        #expect(counter.twoHitNotes(helped, targetName: "Garchomp").last?.contains("Helping Hand") == true)
        #expect(ProblemSolver.Group.outspeeds.title(trickRoom: false, twoHits: true) == "Outspeeds and 2HKOs")
        #expect(ProblemSolver.Group.slower.title(trickRoom: true, twoHits: true) == "2HKOs but moves later")
    }

    /// Two things the simulator got wrong, found by re-checking the whole
    /// regulation: it read a Liquid Voice Psychic Noise as having no effect
    /// on Dark-type Incineroar (the calc reported the Psychic type's
    /// effectiveness, not the Water type's), and it added Knock Off's 1.5×
    /// on top of the Champions calc's own.
    @Test("The simulator's single hits match the calc: Liquid Voice, Knock Off")
    func simulatorMatchesCalc() throws {
        let store = try store()
        let vm = DamageCalcVM()
        func expectSameHit(_ attacker: CalcSide, _ defender: CalcSide, _ moveName: String) throws -> CalcOutcome {
            let move = try #require(store.moves[moveName])
            let calc = CalcEngine.evaluate(move: move.snapshot(), attacker: try #require(attacker.snapshot()),
                                           defender: try #require(defender.snapshot()), field: FieldSnapshot())
            let run = TwoHitSolver.simulate(vm: vm, attacker: attacker, defender: defender, move: move,
                                            rolls: (.max, .max), hits: 1)
            #expect(run.defenderHPLost == Int(calc.damageMax), "\(moveName)")
            return calc
        }

        let voice = try expectSameHit(try side("Primarina", in: store, ability: "liquid-voice"),
                                      try side("Incineroar", in: store) { $0.evHP = 32; $0.evSpDef = 32 },
                                      "Psychic Noise")
        #expect(voice.effectiveness == 2 && voice.isSTAB)
        let knock = try expectSameHit(try side("Kingambit", in: store, ability: "defiant"),
                                      try side("Incineroar", in: store) { $0.heldItem = .choiceScarf },
                                      "Knock Off")
        #expect(knock.damageMax < Double(knock.defenderHP) / 2)
    }

    /// The model shows the fast answers, then has the simulator re-check
    /// each one against the Sitrus Berry.
    @Test("The screen's model re-checks two-hit answers in the simulator")
    func modelSimulates() async throws {
        let store = try store()
        let target = try side("Garchomp", in: store) { $0.evHP = 32; $0.evDef = 32; $0.heldItem = .sitrusBerry }
        let problem = ProblemSolver.Problem(defender: try #require(target.snapshot()), twoHits: true)
        let model = ProblemSolverModel()
        await model.solve(problem, target: SideSetup(target), regulation: .mC, context: store.container.mainContext)
        #expect(model.status == .solved && model.simulating == nil)
        #expect(!model.counters.isEmpty)
        #expect(model.counters.allSatisfy { $0.simulated })
        #expect(model.counters == ProblemSolver.sorted(model.counters))
    }

    // MARK: Usage

    private typealias F = TeamSearchFixtures

    private static let megaGarchomp = MegaForms.all.first { $0.displayName.hasPrefix("Mega Garchomp") && $0.stone != nil }!

    /// Four teams: Garchomp on three (one holding its stone), Incineroar on
    /// three, Kingambit on two.
    private static func usageEvent() -> CorpusEvent {
        F.event("e1", [
            F.standing("a", placing: 1, [F.member("Garchomp", item: megaGarchomp.stone!.rawValue), F.member("Incineroar")]),
            F.standing("b", placing: 2, [F.member("Garchomp"), F.member("Incineroar")]),
            F.standing("c", placing: 3, [F.member("Garchomp"), F.member("Kingambit")]),
            F.standing("d", placing: 4, [F.member("Incineroar"), F.member("Kingambit")]),
        ])
    }

    @Test("Usage is the share of tournament teams, a Mega counted by its stone")
    func usage() throws {
        let store = try store()
        let garchomp = try #require(ProblemSolver.solve(try problem("Heatran", in: store), candidates: [
            try candidate("Garchomp", "Earthquake", in: store, ability: "rough-skin"),
        ]).first)
        var kingambit = garchomp
        kingambit.attacker.species.name = "Kingambit"
        var mega = garchomp
        mega.attacker.megaForm = Self.megaGarchomp
        mega.attacker.heldItem = try #require(Self.megaGarchomp.stone)
        var slower = garchomp
        slower.attacker.species.name = "Incineroar"
        slower.group = .slower

        let usage = TournamentUsage(corpus: TeamCorpus(format: "M-C", events: [Self.usageEvent()],
                                                       listFetchedAt: F.now, missingEvents: []),
                                    vocabulary: F.vocabulary)
        #expect(usage.teamCount == 4 && usage.eventCount == 1)
        #expect(usage.share(of: garchomp) == 0.75)
        #expect(usage.share(of: kingambit) == 0.5)
        #expect(usage.share(of: mega) == 0.25)
        // Most used first, but never ahead of a better group.
        #expect(usage.sorted([mega, slower, kingambit, garchomp]).map(\.name)
                    == ["Garchomp", "Kingambit", mega.name, "Incineroar"])
        #expect(TournamentUsage.percent(0.141) == "14%")
        #expect(TournamentUsage.percent(0.004) == "0.4%")
        #expect(TournamentUsage.percent(0.0003) == "<0.1%")
        #expect(TournamentUsage.percent(0) == "0%")
    }

    /// Usage loads from Team Search's cache without the network, and is
    /// fetched from Limitless only for "Most used".
    @Test("The screen's model fetches tournament teams only when asked")
    func modelUsage() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ProblemSolverUsage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let corpusStore = TeamCorpusStore(fetcher: CannedLimitless([Self.usageEvent()]), directory: directory,
                                          now: { F.now }, sleep: { _ in })
        let model = ProblemSolverModel(corpusStore: corpusStore)
        await model.loadUsage(for: .mC, download: false)
        #expect(model.usage == nil && model.usageStatus == .idle)
        await model.loadUsage(for: .mC, download: true)
        let usage = try #require(model.usage)
        #expect(usage.teamCount == 4 && usage.eventCount == 1)
        #expect(model.usageStatus == .idle)
    }

    // MARK: Siri: what beats a Pokémon

    @Test("Siri offers three investments for the Pokémon to beat, then its saved sets")
    func targetChoices() throws {
        let store = try store()
        let context = store.container.mainContext
        let set = SavedSpread(name: "Bulky Roar", pokemonID: 727, abilityName: "intimidate", championsMode: true,
                              natureID: "careful", evHP: 32, evSpDef: 32)
        context.insert(set)
        try context.save()

        let offered = IntentData.targetStatsChoices(for: 727, in: context)
        #expect(offered.map(\.title) == ["No investment", "Full HP and Defense", "Full HP and Sp. Def", "Bulky Roar"])
        #expect(offered[3].choice == .savedSet(set.persistentModelID))
        #expect(IntentData.targetStatsChoices(for: nil, in: context).count == 3)

        for (said, id) in [("max def", "physical"), ("Max Defense", "physical"), ("max SpD", "special"),
                           ("max special defense", "special"), ("uninvested", "none")] {
            #expect(IntentData.targetStatsEntities(matching: said, in: context).first?.id == id, "\(said)")
        }
        #expect(IntentData.targetStatsEntities(matching: "max speed", in: context).isEmpty)
        #expect(IntentData.targetStatsEntities(matching: "bulky roar", in: context).first?.title == "Bulky Roar")
    }

    /// Without a saved set, the Pokémon gets the ability tournament teams
    /// run most; a mainline set comes over to Champions rules.
    @Test("The Pokémon to beat is loaded as chosen, with its tournament ability")
    func targetLoading() throws {
        let store = try store()
        let context = store.container.mainContext
        let bulky = try IntentData.counterTarget(CountersRequest(pokemonID: 727, stats: .physicallyBulky),
                                                 usage: nil, in: context)
        #expect(bulky.championsMode && bulky.selectedAbility == "blaze")
        #expect(bulky.evHP == bulky.evPerStatMax && bulky.evDef == bulky.evPerStatMax && bulky.evSpDef == 0)

        let usage = TournamentUsage(corpus: TeamCorpus(format: "M-C", events: [F.event("e1", [
            F.standing("a", placing: 1, [F.member("Incineroar", ability: "Intimidate")]),
            F.standing("b", placing: 2, [F.member("Incineroar", ability: "Intimidate")]),
            F.standing("c", placing: 3, [F.member("Incineroar", ability: "Blaze")]),
        ])], listFetchedAt: F.now, missingEvents: []), vocabulary: F.vocabulary)
        #expect(usage.mostUsedAbility(of: "Incineroar") == "Intimidate")
        let special = try IntentData.counterTarget(CountersRequest(pokemonID: 727, stats: .speciallyBulky),
                                                   usage: usage, in: context)
        #expect(special.selectedAbility == "intimidate")
        #expect(special.evHP == special.evPerStatMax && special.evSpDef == special.evPerStatMax && special.evDef == 0)

        let mainline = SavedSpread(name: "Old Roar", pokemonID: 727, abilityName: "intimidate", championsMode: false,
                                   natureID: "careful", evHP: 252, evSpDef: 252)
        context.insert(mainline)
        try context.save()
        let set = try IntentData.counterTarget(CountersRequest(pokemonID: 727, stats: .savedSet(mainline.persistentModelID)),
                                               usage: nil, in: context)
        #expect(set.championsMode && set.evHP == set.evPerStatMax && set.nature.id == "careful")
        #expect(set.loadedSpreadName == "Old Roar")
        // Another Pokémon's set isn't used for this one.
        #expect(throws: (any Error).self) {
            try IntentData.counterTarget(CountersRequest(pokemonID: 485, stats: .savedSet(mainline.persistentModelID)),
                                         usage: nil, in: context)
        }
    }

    @Test("What beats a Pokémon, from the Problem Solver")
    func countersAnswer() async throws {
        let store = try store()
        let answer = try await IntentData.counters(CountersRequest(pokemonID: 485, stats: .physicallyBulky),
                                                   regulation: .mC, usage: nil, in: store.container.mainContext)
        let best = try #require(answer.top.first)
        #expect(best.name == "Garchomp" && best.move == "Earthquake" && best.group == .outspeeds)
        #expect(answer.target == "Flash Fire Heatran")
        #expect(answer.setup == "Heatran: Flash Fire, full HP and Defense, a neutral nature")
        #expect(answer.pokemonCount >= 1 && answer.wayCount >= answer.pokemonCount)
        #expect(answer.spoken.contains("Garchomp's Earthquake"))

        // Forms are said as people say them, and Megas by their own names.
        var counter = try #require(ProblemSolver.solve(try problem("Heatran", in: store), candidates: [
            try candidate("Garchomp", "Earthquake", in: store),
        ]).first)
        let alolan = PKMNStats(id: 10104, speciesID: 38, name: "Ninetales-Alola", formName: "alola",
                               type1: "Ice", type2: "Fairy", baseHP: 73, baseAtk: 67, baseDef: 75,
                               baseSpAtk: 81, baseSpDef: 100, baseSpeed: 109, ability1: "snow-cloak")
        #expect(counter.spokenName(row: alolan) == "Alolan Ninetales")
        #expect(counter.spokenName(row: nil) == "Garchomp")
        counter.attacker.megaForm = Self.megaGarchomp
        #expect(counter.spokenName(row: nil) == Self.megaGarchomp.displayName)
    }

    @Test("How the answer to what beats a Pokémon is said")
    func countersWording() {
        func pick(_ name: String, _ move: String, _ investment: String = "no investment",
                  _ group: ProblemSolver.Group = .outspeeds) -> CountersAnswer.Pick {
            .init(name: name, types: [], move: move, item: "", investment: investment, group: group,
                  damage: "", notes: [])
        }
        func answer(_ top: [CountersAnswer.Pick], count: Int? = nil) -> String {
            CountersAnswer(target: "Intimidate Incineroar", setup: "", regulation: "Regulation M-C",
                           pokemonCount: count ?? top.count, wayCount: top.count, top: top).spoken
        }
        #expect(answer([]) == "Nothing in Regulation M-C knocks out Intimidate Incineroar in one hit, guaranteed.")
        #expect(answer([pick("Milotic", "Scald")])
                == "One Pokémon in Regulation M-C can knock out Intimidate Incineroar in one hit. The best: Milotic's Scald, with no investment, moving first.")
        #expect(answer([pick("Milotic", "Scald"), pick("Empoleon", "Surf"), pick("Falinks", "Close Combat")], count: 84)
                == "84 Pokémon in Regulation M-C can knock out Intimidate Incineroar in one hit. The best three: Milotic's Scald, Empoleon's Surf and Falinks's Close Combat, each with no investment, moving first.")
        #expect(answer([pick("Garchomp", "Earthquake", "12 Attack points"), pick("Kingambit", "Sucker Punch", "no investment", .priority)])
                == "2 Pokémon in Regulation M-C can knock out Intimidate Incineroar in one hit. The best two: Garchomp's Earthquake, with 12 Attack points, moving first; and Kingambit's Sucker Punch, with no investment, using priority.")
    }

    // MARK: Sturdy, Focus Sash and Disguise

    private func evaluate(_ attacker: CalcSide, _ move: MoveSnapshot, _ defender: CalcSide,
                          field: FieldSnapshot = FieldSnapshot()) throws -> CalcOutcome {
        CalcEngine.evaluate(move: move, attacker: try #require(attacker.snapshot()),
                            defender: try #require(defender.snapshot()), field: field)
    }

    /// Earthquake does four times damage to Heatran, far more than its HP,
    /// yet Focus Sash or Sturdy leaves it at 1 HP from full HP.
    @Test("The calc lets Focus Sash, Sturdy and Disguise take one hit")
    func survivalInCalc() throws {
        let store = try store()
        let quake = try #require(store.moves["Earthquake"]).snapshot()
        let chomp = try side("Garchomp", in: store, ability: "rough-skin")
        let sash = try side("Heatran", in: store) { $0.heldItem = .focusSash }

        let blocked = try evaluate(chomp, quake, sash)
        #expect(blocked.damageMin > Double(blocked.defenderHP))
        #expect(blocked.survival == .focusSash && !blocked.isGuaranteedOHKO && blocked.isGuaranteedSurvival)
        #expect(blocked.ohkoChance == 0)
        #expect(blocked.hitsToKOText == "2HKO (Focus Sash)")
        sash.currentHPPercent = 99
        #expect(try evaluate(chomp, quake, sash).isGuaranteedOHKO)
        sash.currentHPPercent = 100
        var magicRoom = FieldSnapshot()
        magicRoom.magicRoom = true
        #expect(try evaluate(chomp, quake, sash, field: magicRoom).isGuaranteedOHKO)

        // A move that hits more than once gets past Focus Sash and Sturdy.
        var twice = quake
        twice.minHits = 2
        #expect(try evaluate(chomp, twice, sash).survival == nil)

        let sturdy = try side("Heatran", in: store, ability: "sturdy")
        #expect(try evaluate(chomp, quake, sturdy).survival == .sturdy)
        #expect(try evaluate(chomp, twice, sturdy).survival == nil)
        let breaker = try side("Garchomp", in: store, ability: "mold-breaker")
        #expect(try evaluate(breaker, quake, sturdy).isGuaranteedOHKO)

        // Disguise blocks the first hit at any HP; only Mold Breaker gets past it.
        let disguised = try side("Heatran", in: store, ability: "disguise") { $0.currentHPPercent = 50 }
        #expect(try evaluate(chomp, twice, disguised).survival == .disguise)
        #expect(try evaluate(breaker, quake, disguised).survival == nil)

        let answer = DamageAnswer(attacker: "Garchomp", defender: "Heatran", move: "Earthquake",
                                  minPercent: 300, maxPercent: 350, minDamage: 0, maxDamage: 0,
                                  attackerSetup: "", defenderSetup: "", championsRules: true, survival: .sturdy)
        #expect(answer.knockOut == "a guaranteed two-hit KO, since Sturdy leaves it at 1 HP from full HP")
    }

    @Test("Only answers that get past Focus Sash or Sturdy count in one hit; two hits do")
    func survivalInSolver() throws {
        let store = try store()
        let quake = try candidate("Garchomp", "Earthquake", in: store, ability: "rough-skin")
        let sash = try problem("Heatran", in: store) { $0.heldItem = .focusSash }
        #expect(sash.survival == .focusSash)
        #expect(ProblemSolver.solve(sash, candidates: [quake]).isEmpty)

        let twoHits = ProblemSolver.Problem(defender: sash.defender, twoHits: true)
        let counter = try #require(ProblemSolver.solve(twoHits, candidates: [quake]).first)
        #expect(counter.twoHits?.hpBeforeSecond == 1)
        expectTwoHitMinimal(counter, twoHits)
        #expect(ProblemSolver.needsSimulation(counter, twoHits))
        #expect(counter.twoHitNotes(twoHits, targetName: "Heatran").first == "Allows for Heatran's Focus Sash.")

        let sturdy = try problem("Heatran", in: store, ability: "sturdy")
        #expect(ProblemSolver.solve(sturdy, candidates: [quake]).isEmpty)
        let breaker = try #require(ProblemSolver.solve(sturdy, candidates: [
            try candidate("Garchomp", "Earthquake", in: store, ability: "mold-breaker"),
        ]).first)
        #expect(breaker.marks.contains(.getsPast(.sturdy)) && breaker.notes.contains("Gets past Sturdy"))
        expectMinimal(breaker, sturdy)

        let none = CountersAnswer(target: "Sturdy Heatran", setup: "", regulation: "Regulation M-C",
                                  pokemonCount: 0, wayCount: 0, top: [], survival: .sturdy)
        #expect(none.spoken == "Nothing in Regulation M-C knocks out Sturdy Heatran in one hit, guaranteed: its Sturdy leaves it at 1 HP from full HP.")
    }

    @Test("The battle simulator keeps a Sturdy Pokémon at 1 HP from full, unless Mold Breaker")
    func survivalInSimulator() throws {
        let store = try store()
        let quake = try #require(store.moves["Earthquake"])
        let vm = DamageCalcVM()
        let sturdy = try side("Heatran", in: store, ability: "sturdy")
        let chomp = try side("Garchomp", in: store, ability: "rough-skin")
        let once = TwoHitSolver.simulate(vm: vm, attacker: chomp, defender: sturdy, move: quake,
                                         rolls: (.max, .max), hits: 1)
        let hp = try evaluate(chomp, quake.snapshot(), sturdy).defenderHP
        #expect(!once.defenderFainted && once.defenderHPLost == hp - 1)
        #expect(TwoHitSolver.simulate(vm: vm, attacker: chomp, defender: sturdy, move: quake,
                                      rolls: (.max, .max)).defenderFainted)
        let breaker = try side("Garchomp", in: store, ability: "mold-breaker")
        #expect(TwoHitSolver.simulate(vm: vm, attacker: breaker, defender: sturdy, move: quake,
                                      rolls: (.min, .min), hits: 1).defenderFainted)
    }
}
