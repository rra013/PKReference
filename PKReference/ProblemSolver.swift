//
//  ProblemSolver.swift
//  PKReference
//
//  Finds the Pokémon, move and investment combinations that knock out a
//  chosen set in one hit (or two), guaranteed, under Champions doubles
//  rules, and says which of them move first. HANDOFF.md's feature notes
//  have the owner's decisions.
//
//  Every answer comes from the calc itself (`CalcEngine.evaluate`, through
//  `EVSolver` for the scaling down), never from an estimate, so the solver
//  and the calc screen can't disagree. The search is exhaustive: at about
//  40 µs a calc the whole roster takes a second or two (measured 2026-09-30).
//
//  `nonisolated`, like `CalcEngine` and `EVSolver`: the candidates are
//  built on the main actor as `Sendable` snapshots, and the search runs
//  anywhere.
//

import Foundation
import SwiftData

nonisolated enum ProblemSolver {

    // MARK: - Inputs

    /// The set to beat, and the field it's beaten on.
    struct Problem: Sendable {
        var defender: CalcSnapshot
        /// Champions doubles: `multi` is on, so spread moves take 0.75×.
        /// Weather and terrain are the field's.
        var field: FieldSnapshot
        /// Whether the defender's Intimidate lowers the counters' Attack.
        var intimidate = true
        /// A partner's Helping Hand powers up every counter's move.
        var helpingHand = false
        /// Tailwind on the counters' side doubles their Speed.
        var tailwind = false
        /// Under Trick Room the slower Pokémon moves first.
        var trickRoom = false
        /// Two hits of the same move on consecutive turns rather than one.
        var twoHits = false

        init(defender: CalcSnapshot, intimidate: Bool = true, weather: WeatherCondition = .none,
             terrain: TerrainCondition = .none, helpingHand: Bool = false, tailwind: Bool = false,
             trickRoom: Bool = false, twoHits: Bool = false) {
            self.defender = defender
            var field = FieldSnapshot()
            field.multi = true
            field.weather = weather
            field.terrain = terrain
            self.field = field
            self.intimidate = intimidate
            self.helpingHand = helpingHand
            self.tailwind = tailwind
            self.trickRoom = trickRoom
            self.twoHits = twoHits
        }

        /// Psychic Terrain stops priority moves hitting a grounded target.
        var blocksPriority: Bool { field.terrain == .psychic && targetIsGrounded }

        /// What lets the target live through any one hit: Sturdy or Focus
        /// Sash from full HP, or Disguise. Only answers that get past it
        /// knock it out in one hit.
        var survival: SurvivalEffect? { CalcEngine.survivalEffects(of: defender, field: field).first }

        /// Not Flying type, Levitating or holding Air Balloon.
        var targetIsGrounded: Bool {
            !defender.effectiveTypes.contains("Flying")
                && defender.effectiveAbility != "levitate"
                && defender.heldItem.rawValue != "Air Balloon"
        }
    }

    /// One Pokémon, ability and move to try: its species, form or Mega at
    /// level 50 on Champions rules, with no investment and no item (a Mega
    /// holds its stone). The solver chooses the rest.
    struct Candidate: Sendable {
        /// `PKMNStats.id` of the Pokémon: its form, or for a Mega its species.
        var pokemonID: Int
        var attacker: CalcSnapshot
        var move: MoveSnapshot
        /// Percent, or nil for a move that can't miss.
        var accuracy: Int?
        var priority: Int
        var marks: Set<Mark>
        /// For a two-turn move, the weather that skips the charge (Solar
        /// Beam in sun).
        var chargeSkipWeather: WeatherCondition? = nil
        /// Stages the move costs its user each time it hits (Draco Meteor's
        /// Sp. Atk -2), for a second hit.
        var selfStatChanges: [Nature.StatKey: Int] = [:]
    }

    // MARK: - Results

    /// How a counter gets its hit in, best first.
    enum Group: Int, Comparable, CaseIterable, Sendable {
        /// Faster than the problem set, so it knocks it out first.
        case outspeeds
        /// A priority move, so Speed doesn't matter.
        case priority
        /// Slower: it needs Trick Room, Tailwind or a switch-in.
        case slower

        static func < (a: Group, b: Group) -> Bool { a.rawValue < b.rawValue }
    }

    /// Something to know about a counter.
    enum Mark: Hashable, Sendable {
        case mustRecharge
        case faintsUser
        case chargesFirst
        case firstTurnOnly
        case failsIfHit
        /// Negative priority: it moves after everything else, whatever the
        /// Speeds (Focus Punch).
        case movesLast
        /// It can only tie the problem set's Speed, not beat it.
        case speedTie
        /// It gets past the target's Sturdy, Focus Sash or Disguise, with a
        /// move that hits more than once or with Mold Breaker.
        case getsPast(SurvivalEffect)
    }

    struct Counter: Identifiable, Equatable, Hashable, Sendable {
        /// `PKMNStats.id`, as the candidate's.
        var pokemonID: Int
        /// As solved: nature, stat points, item, and any stages from the
        /// problem set's Intimidate.
        var attacker: CalcSnapshot
        /// Every ability that gives this result.
        var abilities: [String]
        var move: MoveSnapshot
        var outcome: CalcOutcome
        /// The stat the damage depends on, or nil when none does (Foul Play).
        var attackStat: EVSolver.Stat?
        var attackPoints: Int
        /// Points in Speed to outspeed, or nil for a priority move or a
        /// counter that can't.
        var speedPoints: Int?
        /// Final Speed as solved.
        var speed: Int
        var group: Group
        var accuracy: Int?
        var marks: Set<Mark>
        /// In two-hit mode, both hits as the fast check played them.
        /// `outcome` is the first.
        var twoHits: TwoHits?
        /// Whether the battle simulator re-checked the two hits.
        var simulated = false

        var totalPoints: Int { attackPoints + (speedPoints ?? 0) }

        /// The Pokémon as named in the results: its Mega, or its species.
        var name: String { attacker.megaForm?.displayName ?? attacker.species.name }

        var id: String {
            "\(name)|\(move.id)|\(attacker.heldItem.rawValue)|\(attacker.nature.id)|\(group)"
        }

        static func == (a: Counter, b: Counter) -> Bool {
            a.id == b.id && a.abilities == b.abilities && a.attackPoints == b.attackPoints
                && a.simulated == b.simulated
        }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    // MARK: - Solving

    /// Every counter among `candidates`, best first (see `sorted`). Stops
    /// early, returning what it has, when `isCancelled` says so.
    static func solve(_ problem: Problem, candidates: [Candidate],
                      isCancelled: () -> Bool = { false }) -> [Counter] {
        let targetSpeed = speed(problem.defender, problem.field)
        var byKey: [String: Counter] = [:]
        var order: [String] = []
        // Abilities that give the same damage share one scaling down; see
        // `scaledKey`.
        var scaled: [String: [Counter]] = [:]

        for candidate in candidates {
            if isCancelled() { break }
            guard !candidate.move.isStatus, (candidate.move.power ?? 0) > 0 else { continue }
            if candidate.priority > 0, problem.blocksPriority { continue }
            if problem.twoHits, !canHitTwice(candidate, problem) { continue }

            let attacker = prepared(candidate, problem)
            let stat = offensiveStat(for: candidate.move)
            let strongest = attacker.settingNature(attackingNature(for: stat))
                .settingEV(stat.natureKey!, to: attacker.evPerStatMax)
            let best: CalcOutcome
            var second: CalcOutcome?
            if problem.twoHits {
                let hits = twoHits(candidate.move, strongest, problem, selfStatChanges: candidate.selfStatChanges)
                guard hits.isGuaranteedKO else { continue }
                (best, second) = (hits.first, hits.second)
            } else {
                best = CalcEngine.evaluate(move: candidate.move, attacker: strongest,
                                           defender: problem.defender, field: problem.field)
                guard best.isGuaranteedOHKO else { continue }
            }

            let key = scaledKey(candidate, attacker, best, second)
            let counters = scaled[key] ?? scaleDown(candidate, attacker, stat, problem, targetSpeed)
            scaled[key] = counters

            let ability = candidate.attacker.megaForm?.ability ?? candidate.attacker.selectedAbility
            for var counter in counters {
                if let existing = byKey[counter.id] {
                    counter = existing
                    if let ability, !counter.abilities.contains(ability) { counter.abilities.append(ability) }
                } else {
                    counter.abilities = ability.map { [$0] } ?? []
                    order.append(counter.id)
                }
                byKey[counter.id] = counter
            }
        }

        return sorted(order.compactMap { byKey[$0] })
    }

    /// Best first: by group, then fewest points, then accuracy, then fewest
    /// marks.
    static func sorted(_ counters: [Counter]) -> [Counter] {
        counters.sorted { a, b in
            (a.group, a.totalPoints, -(a.accuracy ?? 101), a.marks.count, a.name, a.move.name)
                < (b.group, b.totalPoints, -(b.accuracy ?? 101), b.marks.count, b.name, b.move.name)
        }
    }

    /// The candidate as it enters the battle: the move's type booster (a
    /// Mega keeps its stone), and the problem set's Intimidate.
    static func prepared(_ candidate: Candidate, _ problem: Problem) -> CalcSnapshot {
        var attacker = candidate.attacker
        attacker.moves = [candidate.move]
        attacker.isHelpingHand = problem.helpingHand
        attacker.isTailwind = problem.tailwind
        if attacker.megaForm == nil {
            attacker.heldItem = booster(for: candidate.move.type) ?? .none
        }
        if problem.intimidate, problem.defender.effectiveAbility == "intimidate" {
            // Intimidate lands on switch-in, before a Mega Evolves, so the
            // ability that answers it is the one chosen, not the Mega's.
            let stages = intimidated(ability: attacker.selectedAbility)
            attacker.atkStage += stages.atk
            attacker.spAtkStage += stages.spAtk
            attacker.speedStage += stages.speed
        }
        return attacker
    }

    /// Two abilities with the same damage at full investment scale down the
    /// same way, so they share the work.
    private static func scaledKey(_ candidate: Candidate, _ attacker: CalcSnapshot,
                                  _ best: CalcOutcome, _ second: CalcOutcome?) -> String {
        [candidate.attacker.species.name, candidate.attacker.megaForm?.displayName ?? "",
         "\(candidate.move.id)", "\(best.damageMin)", "\(best.damageMax)", "\(second?.damageMin ?? 0)",
         "\(attacker.atkStage)", "\(attacker.spAtkStage)", "\(attacker.speedStage)"].joined(separator: "|")
    }

    /// The fewest points that guarantee the KO, and the Speed to go with
    /// them, with each nature; then, for a counter left slower, the same
    /// holding Choice Scarf instead of its booster.
    private static func scaleDown(_ candidate: Candidate, _ attacker: CalcSnapshot, _ stat: EVSolver.Stat,
                                  _ problem: Problem, _ targetSpeed: Int) -> [Counter] {
        guard let best = bestOption(candidate, attacker, stat, problem, targetSpeed) else { return [] }
        var counters = [best]
        // Choice Scarf only helps when faster is first, so not under Trick
        // Room.
        if best.group == .slower, attacker.megaForm == nil, candidate.priority == 0, !problem.trickRoom {
            var scarfed = attacker
            scarfed.heldItem = .choiceScarf
            if let withScarf = bestOption(candidate, scarfed, stat, problem, targetSpeed),
               withScarf.group == .outspeeds {
                counters.append(withScarf)
            }
        }
        return counters
    }

    /// Of an attacking nature and a Speed nature, the one that gets the
    /// better group, then the fewer points. nil when neither KOs.
    private static func bestOption(_ candidate: Candidate, _ attacker: CalcSnapshot, _ stat: EVSolver.Stat,
                                   _ problem: Problem, _ targetSpeed: Int) -> Counter? {
        // Speed decides nothing for a priority move, first or last. Under
        // Trick Room a nature lowering Speed is as strong and slower, so
        // it's the only one worth trying.
        let natures = candidate.priority != 0 ? [attackingNature(for: stat)]
            : problem.trickRoom ? [trickRoomNature(for: stat)]
            : [attackingNature(for: stat), speedNature(for: stat)]
        return natures.compactMap { nature in
            option(candidate, attacker.settingNature(nature), problem, targetSpeed)
        }.min { ($0.group, $0.totalPoints) < ($1.group, $1.totalPoints) }
    }

    /// The fewest points that KO, and the attacker holding them.
    private struct Attack {
        var solved: CalcSnapshot
        var outcome: CalcOutcome
        var stat: EVSolver.Stat?
        var points: Int
        var twoHits: TwoHits?
    }

    private static func oneHit(_ candidate: Candidate, _ attacker: CalcSnapshot, _ problem: Problem) -> Attack? {
        switch EVSolver.minimumToKO(move: candidate.move, attacker: attacker,
                                    defender: problem.defender, field: problem.field) {
        case .success(let solution):
            guard let outcome = solution.outcome else { return nil }
            return Attack(solved: solution.snapshot, outcome: outcome, stat: solution.evs.keys.first,
                          points: solution.cost)
        case .failure(.noRelevantStat):
            // Damage that doesn't depend on the attacker's stats (Foul Play).
            let outcome = CalcEngine.evaluate(move: candidate.move, attacker: attacker,
                                              defender: problem.defender, field: problem.field)
            guard outcome.isGuaranteedOHKO else { return nil }
            return Attack(solved: attacker, outcome: outcome, stat: nil, points: 0)
        case .failure:
            return nil
        }
    }

    /// The fewest points in the move's stat that knock the target out in
    /// two hits. Found by halving the range rather than counting up, as
    /// there are ten times as many two-hit answers as one-hit ones; more
    /// points almost always help, and where they don't (a bigger first hit
    /// setting off a Sitrus Berry) the answer found still KOs, just maybe
    /// not with the very fewest points.
    private static func twoHit(_ candidate: Candidate, _ attacker: CalcSnapshot, _ problem: Problem) -> Attack? {
        let stat = offensiveStat(for: candidate.move)
        let key = stat.natureKey!
        let domain = attacker.evDomain
        func hits(_ index: Int) -> TwoHits {
            twoHits(candidate.move, attacker.settingEV(key, to: domain[index]), problem,
                    selfStatChanges: candidate.selfStatChanges)
        }
        var (low, high) = (0, domain.count - 1)
        var found = hits(high)
        guard found.isGuaranteedKO else { return nil }
        while low < high {
            let middle = (low + high) / 2
            let tried = hits(middle)
            if tried.isGuaranteedKO {
                (high, found) = (middle, tried)
            } else {
                low = middle + 1
            }
        }
        return Attack(solved: attacker.settingEV(key, to: domain[high]), outcome: found.first, stat: stat,
                      points: domain[high], twoHits: found)
    }

    private static func option(_ candidate: Candidate, _ attacker: CalcSnapshot,
                               _ problem: Problem, _ targetSpeed: Int) -> Counter? {
        guard let attack = problem.twoHits ? twoHit(candidate, attacker, problem)
                                           : oneHit(candidate, attacker, problem) else { return nil }
        let solved = attack.solved

        var marks = candidate.marks
        if let weather = candidate.chargeSkipWeather, weather == problem.field.weather {
            marks.remove(.chargesFirst)
        }
        if let effect = problem.survival, CalcEngine.getsPast(effect, move: candidate.move, attacker: solved) {
            marks.insert(.getsPast(effect))
        }
        let speedOf = { (side: CalcSnapshot) in speed(side, problem.field) }
        let group: Group
        var speedPoints: Int?
        var final = solved
        if candidate.priority > 0 {
            group = .priority
        } else if candidate.priority < 0 {
            group = .slower
            marks.insert(.movesLast)
        } else if problem.trickRoom {
            // No Speed points: under Trick Room the slower one moves first.
            let own = speedOf(solved)
            if own < targetSpeed {
                group = .outspeeds
                speedPoints = 0
            } else {
                group = .slower
                if own == targetSpeed { marks.insert(.speedTie) }
            }
        } else if case .success(let fast) = EVSolver.minimumToOutspeed(solved, targetSpeed: targetSpeed,
                                                                      speedOf: speedOf) {
            group = .outspeeds
            speedPoints = fast.cost
            final = fast.snapshot
        } else {
            group = .slower
            if case .success = EVSolver.minimumToOutspeed(solved, targetSpeed: targetSpeed, allowTie: true,
                                                         speedOf: speedOf) {
                marks.insert(.speedTie)
            }
        }
        return Counter(pokemonID: candidate.pokemonID, attacker: final, abilities: [], move: candidate.move,
                       outcome: attack.outcome,
                       attackStat: attack.stat, attackPoints: attack.points, speedPoints: speedPoints,
                       speed: speedOf(final), group: group, accuracy: candidate.accuracy, marks: marks,
                       twoHits: attack.twoHits)
    }

    // MARK: - Two hits

    /// Two hits of one move on consecutive turns, as the fast check plays
    /// them: the first on the target as it is; the second once Multiscale
    /// and a resist berry are spent, Knock Off has taken the item, and the
    /// attacker has paid for its move (Draco Meteor); between them, an HP
    /// berry at half HP, then Leftovers or Grassy Terrain at the end of the
    /// turn.
    struct TwoHits: Sendable {
        var first: CalcOutcome
        var second: CalcOutcome
        /// The first hit's damage that leaves the target best placed for
        /// the second; nil when every first hit KOs.
        var worstFirstHit: Int?
        /// The target's HP when the second hit lands, at worst.
        var hpBeforeSecond: Int

        /// Even the lowest second hit KOs.
        var isGuaranteedKO: Bool { second.damageMin >= Double(hpBeforeSecond) }
    }

    /// Moves that can land on two turns running: not ones that recharge,
    /// faint the user, only work on the first turn, or charge first
    /// (unless the weather skips the charge).
    static func canHitTwice(_ candidate: Candidate, _ problem: Problem) -> Bool {
        let charges = candidate.marks.contains(.chargesFirst) && candidate.chargeSkipWeather != problem.field.weather
        return !charges && candidate.marks.isDisjoint(with: [.mustRecharge, .faintsUser, .firstTurnOnly])
    }

    /// Abilities that change the second hit or the target between hits.
    /// The fast check covers Multiscale and Shadow Shield; the battle
    /// simulator covers the rest.
    static let betweenHitAbilities: Set<String> = [
        "multiscale", "shadow-shield", "stamina", "weak-armor", "disguise", "ice-face",
    ]

    /// Moves whose power falls with the target's HP, left to the simulator.
    static let targetHPMoves: Set<String> = ["crushgrip", "wringout", "hardpress"]

    static func twoHits(_ move: MoveSnapshot, _ attacker: CalcSnapshot, _ problem: Problem,
                        selfStatChanges: [Nature.StatKey: Int]) -> TwoHits {
        let defender = problem.defender
        let first = CalcEngine.evaluate(move: move, attacker: attacker, defender: defender, field: problem.field)
        let maxHP = max(first.defenderHP, 1)
        let startHP = first.hpBeforeHit
        // `effectiveHeldItem` is nothing for a Mega, whose stone stays put.
        let item = defender.effectiveHeldItem
        let knockedOff = BattleSimSeed.normalize(move.name) == "knockoff" && item != .none
        let resisted = item == .chilanBerry ? move.type == "Normal"
            : typeResistBerryMap[item] == move.type && first.effectiveness > 1

        var second = first
        let fullHPAbility = defender.currentHPPercent >= 100
            && ["multiscale", "shadow-shield"].contains(defender.effectiveAbility ?? "")
        if resisted || knockedOff || fullHPAbility || !selfStatChanges.isEmpty
            || targetHPMoves.contains(BattleSimSeed.normalize(move.name)) {
            var target = defender
            target.currentHPPercent = min(99, max(1, (startHP - Int(first.damageMin)) * 100 / maxHP))
            target.atFullHP = false
            if resisted || knockedOff { target.heldItem = .none }
            var user = attacker
            for (stat, change) in selfStatChanges {
                switch stat {
                case .atk: user.atkStage = max(-6, min(6, user.atkStage + change))
                case .def: user.defStage = max(-6, min(6, user.defStage + change))
                case .spAtk: user.spAtkStage = max(-6, min(6, user.spAtkStage + change))
                case .spDef: user.spDefStage = max(-6, min(6, user.spDefStage + change))
                case .speed: user.speedStage = max(-6, min(6, user.speedStage + change))
                }
            }
            second = CalcEngine.evaluate(move: move, attacker: user, defender: target, field: problem.field)
        }

        // Knock Off takes Leftovers before the end of the turn; an HP berry
        // has already been eaten by then.
        let endOfTurnHeal = (item == .leftovers && !knockedOff ? max(1, maxHP / 16) : 0)
            + (problem.field.terrain == .grassy && problem.targetIsGrounded ? max(1, maxHP / 16) : 0)
        // Sturdy or Focus Sash leaves 1 HP from full; Disguise takes the
        // first hit, costing an eighth of the target's HP.
        var firstHits = Set(first.rolls ?? [Int(first.damageMin), Int(first.damageMax)])
        if first.survival == .disguise { firstHits = [max(1, maxHP / 8)] }
        var worst: (hp: Int, damage: Int)?
        for damage in firstHits.sorted() {
            var hp = startHP - damage
            if hp <= 0 {
                guard first.survival == .sturdy || first.survival == .focusSash else { continue }
                hp = 1
            }
            if hp * 2 <= maxHP, item == .sitrusBerry { hp += max(1, maxHP / 4) }
            if hp * 2 <= maxHP, item == .oranBerry { hp += 10 }
            if hp < maxHP { hp += endOfTurnHeal }
            hp = min(hp, maxHP)
            if hp > worst?.hp ?? 0 { worst = (hp, damage) }
        }
        return TwoHits(first: first, second: second, worstFirstHit: worst?.damage, hpBeforeSecond: worst?.hp ?? 0)
    }

    // MARK: - Rules

    /// Final Speed as the calc works it out: items (Choice Scarf), Megas and
    /// stages, through the Champions port.
    static func speed(_ side: CalcSnapshot, _ field: FieldSnapshot) -> Int {
        CalcEngine.finalSpeed(side, field: field) ?? side.speed
    }

    /// The stat a move's damage comes from on the attacker's side: Defense
    /// for Body Press, else Attack or Special Attack.
    static func offensiveStat(for move: MoveSnapshot) -> EVSolver.Stat {
        if BattleSimSeed.normalize(move.name) == "bodypress" { return .def }
        return move.isPhysical ? .atk : .spAtk
    }

    /// A nature raising `stat` and lowering one the move doesn't use.
    static func attackingNature(for stat: EVSolver.Stat) -> Nature {
        nature(stat == .spAtk ? "modest" : stat == .def ? "bold" : "adamant")
    }

    /// A nature raising Speed and lowering one the move doesn't use.
    static func speedNature(for stat: EVSolver.Stat) -> Nature {
        nature(stat == .atk ? "jolly" : "timid")
    }

    /// For Trick Room: a nature raising `stat` and lowering Speed.
    static func trickRoomNature(for stat: EVSolver.Stat) -> Nature {
        nature(stat == .spAtk ? "quiet" : stat == .def ? "relaxed" : "brave")
    }

    /// Answers grouped by Pokémon (a Mega apart from its species), in the
    /// order each Pokémon first appears.
    static func byPokemon(_ counters: [Counter]) -> [[Counter]] {
        var index: [String: Int] = [:]
        var grouped: [[Counter]] = []
        for counter in counters {
            if let at = index[counter.name] {
                grouped[at].append(counter)
            } else {
                index[counter.name] = grouped.count
                grouped.append([counter])
            }
        }
        return grouped
    }

    private static func nature(_ id: String) -> Nature {
        allNatures.first { $0.id == id } ?? allNatures[0]
    }

    /// The 1.2× item for a type. Every type has one.
    static func booster(for type: String) -> HeldItem? {
        typeBoostingItemMap.first { $0.value == type }?.key
    }

    /// What the problem set's Intimidate does to a Pokémon with `ability`,
    /// in stages: blocked by Clear Body and the like, turned around by
    /// Defiant, Competitive, Contrary and Guard Dog, doubled by Simple.
    static func intimidated(ability: String?) -> (atk: Int, spAtk: Int, speed: Int) {
        switch ability {
        case "clear-body", "white-smoke", "full-metal-body", "hyper-cutter", "inner-focus",
             "oblivious", "own-tempo", "scrappy", "mirror-armor":
            return (0, 0, 0)
        case "guard-dog", "contrary", "defiant":
            // Defiant takes the drop, then +2.
            return (1, 0, 0)
        case "competitive":
            return (-1, 2, 0)
        case "simple":
            return (-2, 0, 0)
        case "rattled":
            return (-1, 0, 1)
        default:
            return (-1, 0, 0)
        }
    }
}

// MARK: - Snapshot helpers

nonisolated extension CalcSnapshot {
    func settingNature(_ nature: Nature) -> CalcSnapshot {
        var copy = self
        copy.nature = nature
        return copy
    }
}

// MARK: - Building the candidates

extension ProblemSolver {
    /// Every Pokémon, form and Mega `regulation` allows, with each of its
    /// abilities and legal damaging moves, as candidates. Names are matched
    /// between the regulation's files and the Pokédex by `IntentNames.key`,
    /// as Check Legality matches them.
    @MainActor
    static func candidates(for regulation: ChampionsRegulation, in context: ModelContext) -> [Candidate] {
        let allPokemon = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
        let moves = (try? context.fetch(FetchDescriptor<MoveData>())) ?? []
        let dexNames = Dictionary(((try? context.fetch(FetchDescriptor<PKMN>())) ?? [])
            .map { ($0.nationalPokedexNumber, $0.name) }, uniquingKeysWith: { first, _ in first })
        let store = ChampionsLearnsetStore.store(for: regulation)
        let rules = regulation.rules()
        let moveByKey = Dictionary(moves.map { (IntentNames.key($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        func damaging(_ names: [String]) -> [MoveData] {
            names.compactMap { moveByKey[IntentNames.key($0)] }
                .filter { $0.damageClass != "status" && ($0.power ?? 0) > 0 }
        }

        var candidates: [Candidate] = []
        func add(_ side: CalcSide, abilities: [String?], moves: [MoveData]) {
            for ability in abilities {
                side.selectedAbility = ability
                guard let attacker = side.snapshot(), let pokemonID = side.pokemon?.id else { continue }
                for move in moves {
                    candidates.append(Candidate(
                        pokemonID: pokemonID, attacker: attacker, move: move.snapshot(),
                        accuracy: move.accuracy, priority: move.priority, marks: marks(for: move.name),
                        chargeSkipWeather: BattleMoveEffects.chargeMoves[BattleSimSeed.normalize(move.name)]?.skipInWeather,
                        selfStatChanges: selfStatChanges(for: move.name)))
                }
            }
        }

        for (name, row) in rosterRows(for: regulation, allPokemon: allPokemon, dexNames: dexNames) {
            guard let data = store.data(for: name), let row else { continue }
            let moves = damaging(data.moves)

            let base = CalcSide()
            base.loadUninvested(row, championsMode: true, allPokemon: allPokemon)
            add(base, abilities: abilityIDs(data.abilities, on: row), moves: moves)

            for form in data.alternateForms {
                let keys = PokemonLegality.formKeys(form.name)
                guard let formRow = allPokemon.first(where: { other in
                    other.speciesID == row.speciesID && other.isForm
                        && keys.contains { IntentNames.key(other.formName ?? "").hasPrefix($0) }
                }) else { continue }
                let side = CalcSide()
                side.loadUninvested(formRow, championsMode: true, allPokemon: allPokemon)
                add(side, abilities: abilityIDs(form.abilities, on: formRow), moves: damaging(form.moves ?? data.moves))
            }

            guard rules.megaEvolutionsAllowed else { continue }
            for mega in data.megas {
                guard let form = MegaForms.all.first(where: { IntentNames.key($0.displayName) == IntentNames.key(mega.name) }),
                      let stone = form.stone,
                      rules.allowsMega(form) else { continue }
                let side = CalcSide()
                side.loadUninvested(row, championsMode: true, allPokemon: allPokemon)
                side.heldItem = stone
                side.megaActive = true
                // A Mega has one ability; the one chosen before it Mega
                // Evolves is its species' first.
                add(side, abilities: [row.ability1], moves: moves)
            }
        }
        return candidates
    }

    /// Each species the regulation lists, sorted, with its Pokédex row: by
    /// any name the Pokédex might give it ("Kommo-O" for "Kommo-o",
    /// "Lycanroc-Midday" for "Lycanroc"). nil where there's none.
    @MainActor
    static func rosterRows(for regulation: ChampionsRegulation, allPokemon: [PKMNStats],
                           dexNames: [Int: String]) -> [(name: String, row: PKMNStats?)] {
        var species: [String: PKMNStats] = [:]
        for row in allPokemon where !row.isForm {
            for name in [row.name, ChampionsFormat.canonicalChampionsSpecies(row.name), dexNames[row.speciesID]]
                .compactMap({ $0 }) where species[IntentNames.key(name)] == nil {
                species[IntentNames.key(name)] = row
            }
        }
        return regulation.speciesWhitelist().sorted().map { ($0, species[IntentNames.key($0)]) }
    }

    /// The regulation's abilities for a Pokémon ("Rough Skin") as the calc
    /// names them ("rough-skin").
    @MainActor
    static func abilityIDs(_ names: [String], on row: PKMNStats) -> [String?] {
        let ids = names.map { name in
            row.allAbilities.first { IntentNames.key(formatAbilityName($0)) == IntentNames.key(name) }
                ?? name.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: " ", with: "-")
        }
        return ids.isEmpty ? [row.ability1] : ids
    }

    /// What the move costs its user's stats each time it hits.
    @MainActor
    static func selfStatChanges(for moveName: String) -> [Nature.StatKey: Int] {
        let changes = BattleMoveEffects.selfStatChangesOnHit[BattleSimSeed.normalize(moveName)] ?? []
        return Dictionary(changes, uniquingKeysWith: +)
    }

    @MainActor
    static func marks(for moveName: String) -> Set<Mark> {
        let key = BattleSimSeed.normalize(moveName)
        var marks: Set<Mark> = []
        if BattleMoveEffects.rechargeMoves.contains(key) { marks.insert(.mustRecharge) }
        if BattleMoveEffects.selfKOMoves.contains(key) { marks.insert(.faintsUser) }
        if BattleMoveEffects.chargeMoves[key] != nil { marks.insert(.chargesFirst) }
        if BattleMoveEffects.firstTurnOnlyMoves.contains(key) { marks.insert(.firstTurnOnly) }
        if BattleMoveEffects.failsIfHitMoves.contains(key) { marks.insert(.failsIfHit) }
        return marks
    }
}

// MARK: - Checking two hits in the battle simulator

extension ProblemSolver {
    /// Whether the battle simulator should re-check a two-hit answer:
    /// something acts between the hits, on the target (an HP berry,
    /// Leftovers, the resist berry for this move, Multiscale, Stamina,
    /// Disguise…) or the attacker (Draco Meteor's drop, Knock Off, Crush
    /// Grip). The simulator doesn't model Helping Hand, so with it on the
    /// fast check stands.
    @MainActor
    static func needsSimulation(_ counter: Counter, _ problem: Problem) -> Bool {
        guard problem.twoHits, !problem.helpingHand else { return false }
        let item = problem.defender.effectiveHeldItem
        let key = BattleSimSeed.normalize(counter.move.name)
        return [.sitrusBerry, .oranBerry, .leftovers, .focusSash].contains(item)
            || problem.survival != nil
            || typeResistBerryMap[item] == counter.move.type
            || item == .chilanBerry && counter.move.type == "Normal"
            || betweenHitAbilities.contains(problem.defender.effectiveAbility ?? "")
            || key == "knockoff" && item != .none
            || targetHPMoves.contains(key)
            || !selfStatChanges(for: counter.move.name).isEmpty
    }

    /// Re-checks a two-hit answer in the battle simulator, as
    /// `TwoHitSolver` does: the counter uses its move on two turns running
    /// and the target does nothing. The first hit is played at the roll the
    /// fast check found worst and at the lowest, the second at the lowest.
    /// Where the simulator needs more points they're found by halving the
    /// range above; nil when even full investment doesn't do it.
    ///
    /// `vm` holds the field and, as side 2, the target; side 1 is
    /// overwritten. A few milliseconds a time, so the caller yields between
    /// answers.
    @MainActor
    static func simulated(_ counter: Counter, _ problem: Problem, vm: DamageCalcVM, move: MoveData,
                          allPokemon: [PKMNStats], allMoves: [MoveData]) -> Counter? {
        let changes = selfStatChanges(for: move.name)
        let key = counter.attackStat?.natureKey
        func check(_ points: Int) -> Counter? {
            var attacker = counter.attacker
            if let key { attacker = attacker.settingEV(key, to: points) }
            let hits = twoHits(counter.move, attacker, problem, selfStatChanges: changes)
            SideSetup(attacker, pokemonID: counter.pokemonID).apply(to: vm.side1, allPokemon: allPokemon, allMoves: allMoves)
            var firstRolls: [BattleEngine.RollOverride.Roll] = [.min]
            let (low, high) = (Int(hits.first.damageMin), Int(hits.first.damageMax))
            if let worst = hits.worstFirstHit, worst > low, high > low {
                firstRolls.append(.fraction(Double(worst - low) / Double(high - low)))
            }
            for first in firstRolls {
                let run = TwoHitSolver.simulate(vm: vm, attacker: vm.side1, defender: vm.side2, move: move,
                                                rolls: (first, .min))
                if !run.defenderFainted { return nil }
            }
            var checked = counter
            checked.attacker = attacker
            checked.attackPoints = points
            checked.outcome = hits.first
            checked.twoHits = hits
            checked.simulated = true
            return checked
        }

        if let checked = check(counter.attackPoints) { return checked }
        guard key != nil else { return nil }
        let domain = counter.attacker.evDomain.filter { $0 > counter.attackPoints }
        guard !domain.isEmpty, var found = check(domain[domain.count - 1]) else { return nil }
        var (low, high) = (0, domain.count - 1)
        while low < high {
            let middle = (low + high) / 2
            if let checked = check(domain[middle]) {
                (high, found) = (middle, checked)
            } else {
                low = middle + 1
            }
        }
        return found
    }
}

// MARK: - Tournament usage

/// How often each Pokémon is brought to tournaments: the share of Team
/// Search's Limitless teams that have it. A Mega counts where it holds its
/// stone; any other answer counts its species or form however it's held.
/// Megas are found by the app's own stones (`MegaForms`).
nonisolated struct TournamentUsage: Sendable {
    let teamCount: Int
    let eventCount: Int
    private let vocabulary: TeamSearchVocabulary
    /// Teams with each species identity, and with "identity|stone" for a
    /// Mega.
    private let teams: [String: Int]
    /// How many brought each ability, as Limitless names it, by species
    /// identity.
    private let abilities: [String: [String: Int]]

    init(corpus: TeamCorpus, vocabulary: TeamSearchVocabulary) {
        let stones = Set(MegaForms.all.compactMap { $0.stone.map { IntentNames.key($0.rawValue) } })
        var teams: [String: Int] = [:]
        var abilities: [String: [String: Int]] = [:]
        for team in corpus.teams {
            var keys = Set<String>()
            for member in team.members {
                let identity = vocabulary.identity(name: member.name, slug: member.limitlessID).key
                keys.insert(identity)
                if let item = member.item.map(IntentNames.key), stones.contains(item) {
                    keys.insert(identity + "|" + item)
                }
                if let ability = member.ability, !ability.isEmpty {
                    abilities[identity, default: [:]][ability, default: 0] += 1
                }
            }
            for key in keys { teams[key, default: 0] += 1 }
        }
        self.teams = teams
        self.abilities = abilities
        self.vocabulary = vocabulary
        teamCount = corpus.teams.count
        eventCount = Set(corpus.teams.map(\.tournament.id)).count
    }

    /// The share of teams, 0 to 1, with this answer's Pokémon.
    func share(of counter: ProblemSolver.Counter) -> Double {
        guard teamCount > 0 else { return 0 }
        var key = vocabulary.identity(name: counter.attacker.species.name, slug: nil).key
        if counter.attacker.megaForm != nil { key += "|" + IntentNames.key(counter.attacker.heldItem.rawValue) }
        return Double(teams[key] ?? 0) / Double(teamCount)
    }

    /// The ability tournament teams run most on a species or form
    /// ("Arcanine-Hisui"), as Limitless names it ("Intimidate"); nil when
    /// none bring it.
    func mostUsedAbility(of speciesName: String) -> String? {
        let key = vocabulary.identity(name: speciesName, slug: nil).key
        return abilities[key]?.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// "14%", "0.4%" under one percent, or "<0.1%" for the few under that.
    static func percent(_ share: Double) -> String {
        let percent = share * 100
        if percent > 0 && percent < 0.05 { return "<0.1%" }
        return percent > 0 && percent < 1 ? String(format: "%.1f%%", percent) : "\(Int(percent.rounded()))%"
    }

    /// The most used Pokémon first within each group; otherwise as they
    /// were, so each Pokémon's best answer still leads its others.
    func sorted(_ counters: [ProblemSolver.Counter]) -> [ProblemSolver.Counter] {
        var shares: [String: Double] = [:]
        for counter in counters where shares[counter.name] == nil { shares[counter.name] = share(of: counter) }
        return counters.enumerated().sorted { a, b in
            (a.element.group, -(shares[a.element.name] ?? 0), a.offset)
                < (b.element.group, -(shares[b.element.name] ?? 0), b.offset)
        }.map(\.element)
    }
}
