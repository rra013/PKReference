//
//  damageCalculator.swift
//  PKReference
//
//  Created by Rishi Anand on 4/14/26.
//

import SwiftUI
import SwiftData

// MARK: - Data

/// Every type, in the order menus list them, from `type_chart.json`.
let allTypes: [String] = TypeChart.bundled.types

/// Attacking type → defending type → multiplier, from `type_chart.json`.
/// A pair that isn't listed is neutral (1).
nonisolated let typeEffectivenessChart: [String: [String: Double]] = TypeChart.bundled.effectiveness

// MARK: - Damage Engine (Gen V+ formula)

nonisolated private func pokeFloor(_ value: Int, _ modifier: Double) -> Int {
    if modifier == 1.0 { return value }
    return Int(floor(Double(value) * modifier))
}

nonisolated func calcDamageRange(
    level: Int, movePower: Int, userAtk: Int, defenderDef: Int,
    multi: Bool,
    weatherMult: Double, glaiveRush: Bool,
    crit: Bool, critMultiplier: Double,
    stabBonus: Double, typeEffect: Double,
    burnReduction: Double, abilityMods: AbilityModResult,
    zMoveBypass: Bool
) -> (min: Double, max: Double) {
    guard movePower > 0 && userAtk > 0 && defenderDef > 0 else { return (0, 0) }

    let effectiveAtk = Int(floor(Double(userAtk) * abilityMods.atkMultiplier))
    let effectiveDef = Int(floor(Double(defenderDef) * abilityMods.defMultiplier))
    let effectivePower = Int(floor(Double(movePower) * abilityMods.powerMultiplier))

    let scaledLevel = (2 * level / 5) + 2
    var base = scaledLevel * effectivePower * effectiveAtk / max(effectiveDef, 1)
    base = base / 50 + 2

    if multi        { base = pokeFloor(base, 0.75) }
    base = pokeFloor(base, weatherMult)
    if glaiveRush   { base = pokeFloor(base, 2.0) }
    if crit         { base = pokeFloor(base, abilityMods.critMultiplierOverride ?? critMultiplier) }

    let minBase = base * 85 / 100
    let maxBase = base

    func applyPostRandom(_ d: Int) -> Int {
        var v = d
        v = pokeFloor(v, abilityMods.stabOverride ?? stabBonus)
        v = pokeFloor(v, abilityMods.typeEffOverride ?? typeEffect)
        v = pokeFloor(v, burnReduction)
        v = pokeFloor(v, abilityMods.finalMultiplier)
        if zMoveBypass { v = pokeFloor(v, 0.25) }
        return v
    }

    return (Double(applyPostRandom(minBase)), Double(applyPostRandom(maxBase)))
}

nonisolated func computeTypeEffectiveness(moveType: String, defenderTypes: [String]) -> Double {
    var mult = 1.0
    let chart = typeEffectivenessChart[moveType] ?? [:]
    for dt in defenderTypes {
        mult *= chart[dt] ?? 1.0
    }
    return mult
}

// MARK: - Side Model

@Observable
class CalcSide {
    var pokemon: PKMNStats?
    var searchText: String = ""
    var nature: Nature = allNatures.first(where: { $0.id == "adamant" })!
    var level: Int = 50
    var selectedAbility: String?
    var heldItem: HeldItem = .none
    /// The set's Tera type, kept for saving and export; see
    /// `SavedSpread.teraType`.
    var teraType: String?
    var atFullHP: Bool = true
    var loadedSpreadName: String?

    /// User intent to Mega Evolve. Effective only while `availableMegaForm`
    /// is non-nil (right species + right Mega Stone, or Rayquaza knowing
    /// Dragon Ascent). When the prerequisites are removed the flag remains
    /// set but `activeMegaForm` returns nil, so toggling the item back on
    /// re-enables the Mega without forcing the user to flip the switch
    /// again — and the user's set (EVs, IVs, moves, nature, ability pick)
    /// never resets when entering or leaving Mega Evolution.
    var megaActive: Bool = false

    // Moves (4 slots)
    var moves: [MoveData?] = [nil, nil, nil, nil]
    var moveSearchTexts: [String] = ["", "", "", ""]
    var filterLegalMoves: Bool = true

    /// When true, EVs use the Champions 0-32 scale and IVs are fixed at 31.
    var championsMode: Bool = false

    var evHP: Int = 0
    var evAtk: Int = 0
    var evDef: Int = 0
    var evSpAtk: Int = 0
    var evSpDef: Int = 0
    var evSpeed: Int = 0

    var ivHP: Int = 31
    var ivAtk: Int = 31
    var ivDef: Int = 31
    var ivSpAtk: Int = 31
    var ivSpDef: Int = 31
    var ivSpeed: Int = 31

    var atkStage: Int = 0
    var defStage: Int = 0
    var spAtkStage: Int = 0
    var spDefStage: Int = 0
    var speedStage: Int = 0

    // MARK: - Showdown-port conditions (Champions path)
    // These mirror the per-Pokemon / per-side options on calc.pokemonshowdown.com
    // and feed the vendored `champions.ts` pipeline. They default to neutral so
    // existing calculations are unchanged until a user opts in.

    /// Non-volatile status. Drives Facade/Hex/Guts/Marvel Scale/burn, etc.
    var status: ShowdownStatus = .none
    /// Current HP as a percentage (Multiscale, Reversal/Flail, pinch abilities).
    var currentHPPercent: Int = 100
    /// Whether the Pokemon's conditional ability is currently "on"
    /// (Flash Fire, Slow Start, Unburden, Stakeout, Electromorphosis, Intimidate…).
    var abilityOn: Bool = false

    // Side conditions applied while this Pokemon is the DEFENDER.
    var isReflect: Bool = false
    var isLightScreen: Bool = false
    var isAuroraVeil: Bool = false
    var isFriendGuard: Bool = false
    var isProtected: Bool = false
    var isStealthRock: Bool = false
    var spikesLayers: Int = 0

    // Side conditions applied while this Pokemon is the ATTACKER.
    var isHelpingHand: Bool = false
    var isTailwind: Bool = false

    var evPerStatMax: Int { championsMode ? championsMaxEVPerStat : maxEVPerStat }
    var evTotalMax: Int { championsMode ? championsMaxTotalEVs : maxTotalEVs }
    var totalEVs: Int { evHP + evAtk + evDef + evSpAtk + evSpDef + evSpeed }

    func maxAllowedEV(excluding current: Int) -> Int {
        let othersTotal = totalEVs - current
        return min(evPerStatMax, max(0, evTotalMax - othersTotal))
    }

    func cappedEVBinding(_ kp: ReferenceWritableKeyPath<CalcSide, Int>) -> Binding<Int> {
        Binding(
            get: { self[keyPath: kp] },
            set: { newVal in
                let cap = self.maxAllowedEV(excluding: self[keyPath: kp])
                self[keyPath: kp] = max(0, min(newVal, cap))
            }
        )
    }

    // MARK: - Save / Load Spreads

    func toSavedSpread(name: String) -> SavedSpread {
        SavedSpread(
            name: name,
            pokemonID: pokemon?.id,
            pokemonName: pokemon?.name,
            abilityName: selectedAbility,
            itemRawValue: heldItem != .none ? heldItem.rawValue : nil,
            championsMode: championsMode,
            natureID: nature.id,
            level: level,
            evHP: evHP, evAtk: evAtk, evDef: evDef,
            evSpAtk: evSpAtk, evSpDef: evSpDef, evSpeed: evSpeed,
            ivHP: ivHP, ivAtk: ivAtk, ivDef: ivDef,
            ivSpAtk: ivSpAtk, ivSpDef: ivSpDef, ivSpeed: ivSpeed,
            moveID1: moves[0]?.id, moveID2: moves[1]?.id,
            moveID3: moves[2]?.id, moveID4: moves[3]?.id,
            teraType: teraType
        )
    }

    func loadSpread(_ spread: SavedSpread, allPokemon: [PKMNStats], allMoves: [MoveData]) {
        if let pid = spread.pokemonID {
            if let match = allPokemon.first(where: { $0.id == pid }) {
                pokemon = match
            }
        }
        selectedAbility = spread.abilityName
        heldItem = spread.itemRawValue.flatMap { HeldItem(rawValue: $0) } ?? .none
        teraType = spread.teraType
        championsMode = spread.championsMode
        nature = allNatures.first(where: { $0.id == spread.natureID }) ?? allNatures[0]
        level = spread.level
        evHP = spread.evHP; evAtk = spread.evAtk; evDef = spread.evDef
        evSpAtk = spread.evSpAtk; evSpDef = spread.evSpDef; evSpeed = spread.evSpeed
        ivHP = spread.ivHP; ivAtk = spread.ivAtk; ivDef = spread.ivDef
        ivSpAtk = spread.ivSpAtk; ivSpDef = spread.ivSpDef; ivSpeed = spread.ivSpeed

        let moveIDs = [spread.moveID1, spread.moveID2, spread.moveID3, spread.moveID4]
        for i in 0..<4 {
            if let mid = moveIDs[i] {
                moves[i] = allMoves.first(where: { $0.id == mid })
            } else {
                moves[i] = nil
            }
            moveSearchTexts[i] = ""
        }

        loadedSpreadName = spread.name
    }

    private func formulaEV(_ stored: Int) -> Int {
        championsMode ? championsEVToMain(stored) : stored
    }

    private func formulaIV(_ stored: Int) -> Int {
        championsMode ? championsLockedIV : stored
    }

    func setChampionsMode(_ on: Bool) {
        guard on != championsMode else { return }
        if on {
            evHP    = mainEVToChampions(evHP)
            evAtk   = mainEVToChampions(evAtk)
            evDef   = mainEVToChampions(evDef)
            evSpAtk = mainEVToChampions(evSpAtk)
            evSpDef = mainEVToChampions(evSpDef)
            evSpeed = mainEVToChampions(evSpeed)
            let iv = championsLockedIV
            ivHP = iv; ivAtk = iv; ivDef = iv
            ivSpAtk = iv; ivSpDef = iv; ivSpeed = iv
            championsMode = true
        } else {
            evHP    = championsEVToMain(evHP)
            evAtk   = championsEVToMain(evAtk)
            evDef   = championsEVToMain(evDef)
            evSpAtk = championsEVToMain(evSpAtk)
            evSpDef = championsEVToMain(evSpDef)
            evSpeed = championsEVToMain(evSpeed)
            championsMode = false
        }
    }

    // MARK: - Mega Evolution Gating

    /// Names of moves the held Pokemon currently has slotted, used to
    /// detect Dragon Ascent on Rayquaza. We only consult this for the
    /// Rayquaza branch — every other Mega is keyed off the held stone.
    private var slottedMoveNames: [String] {
        moves.compactMap { $0?.name }
    }

    /// The Mega form the currently-selected Pokemon *could* transform into,
    /// given its held item (or, for Rayquaza, the move slots) and, in
    /// Champions mode, the regulation's rules. Returns nil when there's no
    /// eligible form — that's the source of truth for the UI toggle's
    /// enabled state.
    var availableMegaForm: MegaForm? {
        guard let form = triggeredMegaForm else { return nil }
        if championsMode && !ChampionsRegulation.current.rules().allowsMega(form) { return nil }
        return form
    }

    /// The Mega form the held item (or Rayquaza's moves) triggers, whether
    /// or not the regulation allows it.
    private var triggeredMegaForm: MegaForm? {
        guard let p = pokemon else { return nil }
        return MegaForms.form(forSpecies: p.name,
                              heldItem: heldItem,
                              moveNames: slottedMoveNames)
    }

    /// True when the Mega toggle should be enabled. Pure pass-through over
    /// `availableMegaForm` — kept as a separate name so SwiftUI bindings
    /// read cleanly.
    var canMegaEvolve: Bool { availableMegaForm != nil }

    /// True when the currently-selected Pokemon has *any* registered Mega
    /// form in the table — regardless of whether the held item / move slots
    /// currently satisfy the trigger. Used by the UI to decide whether to
    /// surface the Mega toggle at all: an Eevee shouldn't have a disabled
    /// "Mega Evolve" row taking up space, but a Charizard with no stone
    /// equipped should still see the row (disabled, with hint text) so the
    /// player can discover the feature exists.
    var hasAnyMegaForm: Bool {
        guard let p = pokemon else { return false }
        let s = BattleSimSeed.normalize(p.name)
        if s == "rayquaza" { return true }
        return MegaForms.all.contains(where: { $0.speciesKey == s })
    }

    /// User-facing reason the toggle is disabled. nil when the toggle is
    /// enabled, otherwise a short hint like "Hold Charizardite Y" or
    /// "Must know Dragon Ascent". Drives the caption under the row so the
    /// player knows what to change.
    var megaDisabledReason: String? {
        guard hasAnyMegaForm, availableMegaForm == nil, let p = pokemon else { return nil }
        if triggeredMegaForm != nil {
            return "Not allowed in \(ChampionsRegulation.current.displayName)"
        }
        let s = BattleSimSeed.normalize(p.name)
        if s == "rayquaza" {
            return "Must know Dragon Ascent"
        }
        // Find which stones can trigger a Mega for this species; list them.
        let stones = MegaForms.all
            .filter { $0.speciesKey == s }
            .compactMap { $0.stone?.rawValue }
        switch stones.count {
        case 0:  return nil
        case 1:  return "Hold \(stones[0])"
        default: return "Hold \(stones.joined(separator: " or "))"
        }
    }

    /// The Mega form currently in effect for damage calc / stat display.
    /// Returns nil unless the user has toggled `megaActive` on AND the
    /// prerequisites still hold. Acts as the single gate read by every
    /// `effective*` accessor below.
    var activeMegaForm: MegaForm? {
        megaActive ? availableMegaForm : nil
    }

    // MARK: - Effective State (Mega-aware)

    /// Mega's ability when active, the user's pick otherwise. Damage calc
    /// reads this — never `selectedAbility` directly — so a Mega
    /// transforming into Tough Claws / Mega Launcher applies its ability
    /// without overwriting the user's saved-spread choice.
    var effectiveAbility: String? {
        activeMegaForm?.ability ?? selectedAbility
    }

    /// Same idea for typing — Mega Charizard X switches to Fire/Dragon
    /// while the user's pre-Mega "Fire/Flying" selection stays untouched
    /// on the base species record.
    var effectiveTypes: [String] {
        if let m = activeMegaForm {
            var t = [m.type1]
            if let t2 = m.type2 { t.append(t2) }
            return t
        }
        guard let p = pokemon else { return ["Normal"] }
        var t = [p.type1]
        if let t2 = p.type2 { t.append(t2) }
        return t
    }

    /// Effective base stats — Mega's stat block when active, base otherwise.
    /// HP is intentionally always the base value: no canonical Mega
    /// Evolution alters HP.
    var effectiveBaseAtk: Int    { activeMegaForm?.baseAtk    ?? pokemon?.baseAtk    ?? 1 }
    var effectiveBaseDef: Int    { activeMegaForm?.baseDef    ?? pokemon?.baseDef    ?? 1 }
    var effectiveBaseSpAtk: Int  { activeMegaForm?.baseSpAtk  ?? pokemon?.baseSpAtk  ?? 1 }
    var effectiveBaseSpDef: Int  { activeMegaForm?.baseSpDef  ?? pokemon?.baseSpDef  ?? 1 }
    var effectiveBaseSpeed: Int  { activeMegaForm?.baseSpeed  ?? pokemon?.baseSpeed  ?? 1 }

    /// Display name accounting for Mega — `"Mega Charizard Y"` when active,
    /// base species name otherwise. Used by the side card header and the
    /// damage summary line.
    var effectiveDisplayName: String {
        activeMegaForm?.displayName ?? pokemon?.name ?? "???"
    }

    /// Held item that the damage formula should see. Stone-based Megas
    /// consume the stone on transformation, so the calc treats them as
    /// item-less while Mega is active. Rayquaza's `MegaForm.stone` is nil
    /// (Dragon Ascent triggers the form change instead), so a Mega Rayquaza
    /// holding Life Orb still gets the boost.
    var effectiveHeldItem: HeldItem {
        if let m = activeMegaForm, m.stone != nil { return .none }
        return heldItem
    }

    // MARK: - Public computed types / stats

    /// Kept under the old name so existing call sites (type chart, etc.) pick
    /// up the Mega switch automatically.
    var types: [String] { effectiveTypes }

    var hp: Int {
        guard let p = pokemon else { return 1 }
        return calcHP(base: p.baseHP, iv: formulaIV(ivHP), ev: formulaEV(evHP), level: level)
    }
    var atk: Int {
        guard pokemon != nil else { return 1 }
        return Int(Double(calcStat(base: effectiveBaseAtk, iv: formulaIV(ivAtk), ev: formulaEV(evAtk), level: level, natureMod: nature.modifier(for: .atk))) * statStageMultiplier(stage: atkStage))
    }
    var def: Int {
        guard pokemon != nil else { return 1 }
        return Int(Double(calcStat(base: effectiveBaseDef, iv: formulaIV(ivDef), ev: formulaEV(evDef), level: level, natureMod: nature.modifier(for: .def))) * statStageMultiplier(stage: defStage))
    }
    var spAtk: Int {
        guard pokemon != nil else { return 1 }
        return Int(Double(calcStat(base: effectiveBaseSpAtk, iv: formulaIV(ivSpAtk), ev: formulaEV(evSpAtk), level: level, natureMod: nature.modifier(for: .spAtk))) * statStageMultiplier(stage: spAtkStage))
    }
    var spDef: Int {
        guard pokemon != nil else { return 1 }
        return Int(Double(calcStat(base: effectiveBaseSpDef, iv: formulaIV(ivSpDef), ev: formulaEV(evSpDef), level: level, natureMod: nature.modifier(for: .spDef))) * statStageMultiplier(stage: spDefStage))
    }
    var speed: Int {
        guard pokemon != nil else { return 1 }
        return Int(Double(calcStat(base: effectiveBaseSpeed, iv: formulaIV(ivSpeed), ev: formulaEV(evSpeed), level: level, natureMod: nature.modifier(for: .speed))) * statStageMultiplier(stage: speedStage))
    }
}

// MARK: - Per-Move Result

struct MoveResult: Identifiable {
    let id = UUID()
    let move: MoveData
    let damageMin: Double
    let damageMax: Double
    let minPercent: Double
    let maxPercent: Double
    let hitsToKO: String
    let effectiveness: Double
    let effectivenessLabel: String
    let effectivenessColor: Color
    let isSTAB: Bool
    /// What lets the defender live through the hit: Focus Sash or Sturdy
    /// from full HP, or Disguise.
    var survival: SurvivalEffect? = nil
}

// MARK: - View Model

@MainActor
@Observable
class DamageCalcVM {
    var side1 = CalcSide()
    var side2 = CalcSide()

    // Global modifiers
    var crit: Bool = false
    var burn: Bool = false
    var multi: Bool = false
    var glaiveRush: Bool = false
    var zMoveBypass: Bool = false
    var weather: WeatherCondition = .none
    var terrain: TerrainCondition = .none
    var miscMultiplier: Double = 1.0

    // Global field state (Champions/Showdown path)
    var gravity: Bool = false
    var wonderRoom: Bool = false
    var magicRoom: Bool = false

    // MARK: Computed Results

    var side1Results: [MoveResult] {
        computeResults(attacker: side1, defender: side2)
    }

    var side2Results: [MoveResult] {
        computeResults(attacker: side2, defender: side1)
    }

    private func computeResults(attacker: CalcSide, defender: CalcSide) -> [MoveResult] {
        attacker.moves.compactMap { $0 }.map { move in
            computeSingleResult(move: move, attacker: attacker, defender: defender)
        }
    }

    private func computeSingleResult(move: MoveData, attacker: CalcSide, defender: CalcSide) -> MoveResult {
        // Both engines live in `CalcEngine` so the solver can run them off the
        // main actor, and `CalcEngine.evaluate` owns the precedence between
        // them (Champions port first, legacy fallback). This call site only
        // snapshots the inputs and dresses the numeric outcome for display.
        //
        // `snapshot()` is nil-on-no-species, but an empty side reaching here
        // means the user hasn't picked a Pokemon yet — the old code silently
        // computed against 1/1/1 fallback stats, so `emptyResult` preserves
        // that "nothing to show" outcome without inventing a phantom statline.
        guard let attackerSnap = attacker.snapshot(),
              let defenderSnap = defender.snapshot() else {
            return Self.emptyResult(for: move)
        }

        let outcome = CalcEngine.evaluate(
            move: move.snapshot(),
            attacker: attackerSnap,
            defender: defenderSnap,
            field: fieldSnapshot()
        )
        return Self.moveResult(from: outcome, move: move)
    }

    // MARK: - Outcome -> display

    /// Dresses a numeric `CalcOutcome` as the `MoveResult` the UI renders.
    /// The label and colour tables are unchanged from when they were inline.
    static func moveResult(from outcome: CalcOutcome, move: MoveData) -> MoveResult {
        MoveResult(
            move: move,
            damageMin: outcome.damageMin, damageMax: outcome.damageMax,
            minPercent: outcome.minPercent, maxPercent: outcome.maxPercent,
            hitsToKO: outcome.hitsToKOText,
            effectiveness: outcome.effectiveness,
            effectivenessLabel: outcome.effectivenessLabel,
            effectivenessColor: effectivenessColor(outcome.effectiveness),
            isSTAB: outcome.isSTAB,
            survival: outcome.survival
        )
    }

    static func effectivenessColor(_ eff: Double) -> Color {
        switch eff {
        case 0:          return .gray
        case 0.25, 0.5:  return .blue
        case 1:          return .primary
        case 2:          return .orange
        case 4:          return .red
        default:         return .primary
        }
    }

    /// Placeholder for a matchup with no species selected.
    private static func emptyResult(for move: MoveData) -> MoveResult {
        MoveResult(
            move: move,
            damageMin: 0, damageMax: 0,
            minPercent: 0, maxPercent: 0,
            hitsToKO: "--",
            effectiveness: 1,
            effectivenessLabel: "1x",
            effectivenessColor: .primary,
            isSTAB: false
        )
    }

    // MARK: Move Search

    func filteredMoves(for side: CalcSide, slotIndex: Int, allMoves: [MoveData], allPokemon: [PKMNStats]) -> [MoveData] {
        let q = side.moveSearchTexts[slotIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var pool = allMoves
        if side.filterLegalMoves, let pkmn = side.pokemon {
            var legalIDs = Set(pkmn.learnableMoveIDs)
            if legalIDs.isEmpty {
                if let base = allPokemon.first(where: { $0.speciesID == pkmn.speciesID && !$0.isForm }) {
                    legalIDs = Set(base.learnableMoveIDs)
                }
            }
            pool = pool.filter { legalIDs.contains($0.id) }
        }
        return pool.filter { $0.name.lowercased().contains(q) }.prefix(25).map { $0 }
    }
}

// MARK: - Main View

struct DamageCalculatorView: View {
    @State private var vm = DamageCalcVM()
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]
    @AppStorage(AppSettings.defaultGeneration) private var defaultGeneration: String
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        TabNavigationStack {
            ScrollView {
                Group {
                    if allPokemon.isEmpty {
                        SyncingCard()
                    } else if hSize == .regular {
                        // Wide layout: mon inputs on the left, result + global
                        // modifiers on the right so the damage output stays
                        // visible while tweaking either mon.
                        HStack(alignment: .top, spacing: 16) {
                            CardStack {
                                SideCard(title: "Pokemon 1", role: .side1, side: vm.side1, allPokemon: allPokemon, allMoves: allMoves, vm: vm)
                                SideCard(title: "Pokemon 2", role: .side2, side: vm.side2, allPokemon: allPokemon, allMoves: allMoves, vm: vm)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            CardStack {
                                ResultCard(vm: vm)
                                ModifiersCard(vm: vm)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    } else {
                        // Compact layout: original single column, unchanged.
                        CardStack {
                            ResultCard(vm: vm)
                            SideCard(title: "Pokemon 1", role: .side1, side: vm.side1, allPokemon: allPokemon, allMoves: allMoves, vm: vm)
                            SideCard(title: "Pokemon 2", role: .side2, side: vm.side2, allPokemon: allPokemon, allMoves: allMoves, vm: vm)
                            ModifiersCard(vm: vm)
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            #if os(iOS)
            .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            #endif
            .navigationTitle("Damage Calc")
            .cardPage()
            .onAppear {
                let isChampions = defaultGeneration == PokedexFilter.champions.rawValue
                if isChampions != vm.side1.championsMode {
                    vm.side1.setChampionsMode(isChampions)
                }
                if isChampions != vm.side2.championsMode {
                    vm.side2.setChampionsMode(isChampions)
                }
                // After the sync above, so a saved set keeps its own mode.
                openRequestedCalc()
            }
            .onChange(of: AppNavigator.shared.request) { openRequestedCalc() }
        }
        .leaveWarning(vm.side1.pokemon != nil || vm.side2.pokemon != nil
                      ? "The Pokémon you entered will be cleared." : nil)
    }

    /// Loads the calc an App Intent asked for into a new view model, so no
    /// field condition or stat stage left on screen changes its answer; or
    /// loads a saved set as the attacker, as the Load button does, keeping
    /// the defender; or both sides exactly, as the Problem Solver solved
    /// them.
    private func openRequestedCalc() {
        switch AppNavigator.shared.request {
        case .calc(let request):
            AppNavigator.shared.request = nil
            let requested = DamageCalcVM()
            requested.load(request, championsMode: defaultGeneration == PokedexFilter.champions.rawValue,
                           context: modelContext)
            vm = requested
        case .calcSet(let id):
            AppNavigator.shared.request = nil
            let descriptor = FetchDescriptor<SavedSpread>(predicate: #Predicate { $0.persistentModelID == id })
            guard let spread = try? modelContext.fetch(descriptor).first else { return }
            vm.side1.loadSpread(spread, allPokemon: allPokemon, allMoves: allMoves)
        case .calcSides(let sides):
            AppNavigator.shared.request = nil
            let requested = DamageCalcVM()
            guard sides.attacker.apply(to: requested.side1, allPokemon: allPokemon, allMoves: allMoves),
                  sides.defender.apply(to: requested.side2, allPokemon: allPokemon, allMoves: allMoves)
            else { return }
            requested.multi = sides.doubles
            requested.weather = sides.weather
            requested.terrain = sides.terrain
            vm = requested
        default:
            break
        }
    }
}

// MARK: - Syncing Placeholder

private struct SyncingCard: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Downloading Pokemon & move data...")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("This only happens once.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 40)
    }
}

// MARK: - Result Card

private struct ResultCard: View {
    var vm: DamageCalcVM
    @State private var solveRequest: EVSolveRequest?

    var body: some View {
        SectionCard(title: "Results", icon: "bolt.fill") {
            // Field conditions, then each side's modifiers on its own row: a
            // badge's color says what it is (ability, item), and the row's
            // marker says whose it is.
            VStack(alignment: .leading, spacing: 6) {
                if hasFieldConditions {
                    FlowLayout(spacing: 6) {
                        let field = ColorRole.field.color
                        if vm.weather != .none {
                            InfoBadge(text: vm.weather.rawValue, color: field)
                        }
                        if vm.terrain != .none {
                            InfoBadge(text: "\(vm.terrain.rawValue) Terrain", color: field)
                        }
                        if vm.crit { InfoBadge(text: "Crit", color: field) }
                        if vm.burn { InfoBadge(text: "Burn", color: field) }
                        if vm.gravity { InfoBadge(text: "Gravity", color: field) }
                        if vm.wonderRoom { InfoBadge(text: "Wonder Room", color: field) }
                        if vm.magicRoom { InfoBadge(text: "Magic Room", color: field) }
                    }
                }
                if SideModifiersRow.hasModifiers(vm.side1) {
                    SideModifiersRow(role: .side1, name: vm.side1.pokemon?.name ?? "Pokemon 1", side: vm.side1)
                }
                if SideModifiersRow.hasModifiers(vm.side2) {
                    SideModifiersRow(role: .side2, name: vm.side2.pokemon?.name ?? "Pokemon 2", side: vm.side2)
                }
            }

            if vm.side1.pokemon != nil && vm.side2.pokemon != nil {
                DirectionResultsView(
                    attackerRole: .side1,
                    attackerName: vm.side1.pokemon?.name ?? "???",
                    defenderName: vm.side2.pokemon?.name ?? "???",
                    defenderHP: vm.side2.hp,
                    results: vm.side1Results,
                    onSolve: { solveRequest = EVSolveRequest(move: $0, attackerIsSide1: true) }
                )

                Divider()

                DirectionResultsView(
                    attackerRole: .side2,
                    attackerName: vm.side2.pokemon?.name ?? "???",
                    defenderName: vm.side1.pokemon?.name ?? "???",
                    defenderHP: vm.side1.hp,
                    results: vm.side2Results,
                    onSolve: { solveRequest = EVSolveRequest(move: $0, attackerIsSide1: false) }
                )
            } else {
                Text("Select two Mons to see results")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .sheet(item: $solveRequest) { request in
            EVSolverSheet(vm: vm, request: request)
            .sheetSize()
        }
    }

    private var hasFieldConditions: Bool {
        vm.weather != .none || vm.terrain != .none || vm.crit || vm.burn
            || vm.gravity || vm.wonderRoom || vm.magicRoom
    }
}

/// One side's status, ability and item, after the side's marker and name.
private struct SideModifiersRow: View {
    let role: MatchupSide
    let name: String
    let side: CalcSide

    static func hasModifiers(_ side: CalcSide) -> Bool {
        side.status != .none
            || !(side.effectiveAbility ?? "").isEmpty
            || side.effectiveHeldItem != .none
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            HStack(spacing: 6) {
                SideMarker(role: role).font(.caption)
                Text(name)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            if side.status != .none {
                InfoBadge(text: statusLabel(side.status), color: .primary)
            }
            if let ability = side.effectiveAbility, !ability.isEmpty {
                InfoBadge(text: formatAbilityName(ability), color: ColorRole.ability.color)
            }
            if side.effectiveHeldItem != .none {
                InfoBadge(text: side.effectiveHeldItem.rawValue, color: ColorRole.item.color)
            }
        }
    }
}

/// Marks Pokémon 1 or 2 wherever Results names them, matching the marker
/// on each side's card.
private struct SideMarker: View {
    let role: MatchupSide
    @Environment(\.matchupColors) private var matchupColors

    var body: some View {
        Image(systemName: role.symbol)
            .foregroundStyle(matchupColors.color(for: role))
            .accessibilityHidden(true)
    }
}

private struct DirectionResultsView: View {
    let attackerRole: MatchupSide
    let attackerName: String
    let defenderName: String
    let defenderHP: Int
    let results: [MoveResult]
    /// Opens the EV solver for a move in this direction.
    var onSolve: ((MoveData) -> Void)? = nil

    private var defenderRole: MatchupSide { attackerRole == .side1 ? .side2 : .side1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveStack(spacing: 4) {
                FlowLayout(spacing: 4) {
                    HStack(spacing: 4) {
                        SideMarker(role: attackerRole).font(.subheadline)
                        Text(attackerName).font(.subheadline.bold())
                    }
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        SideMarker(role: defenderRole).font(.subheadline)
                        Text(defenderName).font(.subheadline.bold())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(defenderHP) HP")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            if results.isEmpty {
                Text("No moves selected")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(results) { result in
                    MoveResultRow(result: result, onSolve: onSolve.map { f in { f(result.move) } })
                }
            }
        }
    }
}

private struct MoveResultRow: View {
    let result: MoveResult
    var onSolve: (() -> Void)? = nil

    private var isStatus: Bool { result.move.damageClass == "status" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AdaptiveStack(spacing: 6) {
                FlowLayout(spacing: 6) {
                    Text(result.move.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    TypeBadge(type: result.move.type)
                    DamageClassBadge(damageClass: result.move.damageClass)
                    if result.isSTAB && !isStatus {
                        Text("STAB")
                            .scaledFont(size: 9, weight: .bold, relativeTo: .caption2)
                            .fixedSize()
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .foregroundStyle(.yellow)
                            .background(Color.yellow.opacity(0.2), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !isStatus {
                    HStack(spacing: 6) {
                        Text(result.effectivenessLabel)
                            .font(.caption.bold())
                            .fixedSize()
                            .foregroundStyle(result.effectivenessColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(result.effectivenessColor.opacity(0.15), in: Capsule())
                        Text(result.hitsToKO)
                            .font(.caption.bold())
                            .fixedSize()
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.15), in: Capsule())
                    }
                }
            }

            if isStatus {
                Text("Status move — no damage")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                AdaptiveStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text("\(String(format: "%.0f", result.damageMin))-\(String(format: "%.0f", result.damageMax))")
                            .font(.caption.monospacedDigit())
                        Text("(\(String(format: "%.1f", result.minPercent))% - \(String(format: "%.1f", result.maxPercent))%)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let onSolve {
                        Button(action: onSolve) {
                            Label("Solve EVs", systemImage: "wand.and.stars")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityHint("Finds the fewest EVs to survive, KO or outspeed")
                    }
                }

                PercentageBar(minPct: result.minPercent, maxPct: result.maxPercent)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct InfoBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

private struct PercentageBar: View {
    let minPct: Double
    let maxPct: Double
    private func barColor(_ pct: Double) -> Color {
        if pct >= 100 { return .red }
        if pct >= 50  { return .orange }
        return .green
    }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemFill)).frame(height: 10)
                let w = geo.size.width
                let minX = min(minPct / 100 * w, w)
                let maxX = min(maxPct / 100 * w, w)
                Capsule()
                    .fill(LinearGradient(colors: [barColor(minPct), barColor(maxPct)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(maxX, 8), height: 10)
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white).frame(width: 3, height: 14)
                    .offset(x: max(minX - 1.5, 0))
            }
        }
        .frame(height: 14)
    }
}

// MARK: - Pokemon Side Card

/// One side's editor: the Pokémon, its set, investment, stages and
/// conditions. The Problem Solver uses it for the set to beat, without the
/// moves.
struct SideCard: View {
    let title: String
    /// `.side1` or `.side2`; the header's numbered marker is the key for
    /// the markers in Results.
    let role: MatchupSide
    @Bindable var side: CalcSide
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    /// The calc, for the move slots; nil hides them.
    var vm: DamageCalcVM?
    /// The header's symbol, in place of the side's numbered marker.
    var icon: String?

    @Query(sort: \SavedSpread.createdAt, order: .reverse) private var savedSpreads: [SavedSpread]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.matchupColors) private var matchupColors
    @State private var showSaveSheet = false
    @State private var showLoadSheet = false
    @State private var showPasteSheet = false

    @ViewBuilder
    private var spreadButtons: some View {
        Button { showSaveSheet = true } label: {
            Label("Save Spread", systemImage: "square.and.arrow.down")
                .font(.caption).lineLimit(1)
        }
        .buttonStyle(.bordered)

        Button { showLoadSheet = true } label: {
            Label("Load", systemImage: "tray.and.arrow.up")
                .font(.caption).lineLimit(1)
        }
        .buttonStyle(.bordered).tint(.secondary)
        .disabled(savedSpreads.isEmpty)
    }

    /// Showdown paste import, plus export once there's a set to export.
    /// Export leads with Copy: pasting into Showdown is the common case, and
    /// not every share sheet offers Copy up front.
    @ViewBuilder
    private var pasteButtons: some View {
        Button { showPasteSheet = true } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
                .font(.caption).lineLimit(1)
        }
        .buttonStyle(.bordered).tint(.secondary)

        if let set = side.showdownPasteSet() {
            let text = set.showdownText()
            Menu {
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = text
                    #else
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    #endif
                } label: {
                    Label("Copy Paste", systemImage: "doc.on.doc")
                }
                ShareLink(item: text, preview: SharePreview("\(set.species) set")) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.caption).lineLimit(1)
            }
            .buttonStyle(.bordered).tint(.secondary)
        }
    }

    private var filteredPokemon: [PKMNStats] {
        let q = side.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return allPokemon.filter { $0.name.lowercased().contains(q) || String($0.id).contains(q) }.prefix(20).map { $0 }
    }

    var body: some View {
        SectionCard(title: title, icon: icon ?? role.symbol,
                    iconColor: matchupColors.color(for: role), types: side.effectiveTypes) {
            // Pokemon Picker
            VStack(alignment: .leading, spacing: 8) {
                if let p = side.pokemon {
                    HStack {
                        AdaptiveStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(side.effectiveDisplayName).font(.title3.bold())
                                if side.activeMegaForm != nil {
                                    Text("Mega Evolved")
                                        .font(.caption.bold())
                                        .foregroundStyle(.purple)
                                } else if p.isForm, let form = p.formName {
                                    Text(form.split(separator: "-").map { $0.capitalized }.joined(separator: " "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            HStack { ForEach(side.effectiveTypes, id: \.self) { TypeBadge(type: $0) } }
                        }
                        Button {
                            side.pokemon = nil
                            side.searchText = ""
                            side.selectedAbility = nil
                            side.teraType = nil
                            // Clear Mega state too — the toggle isn't meaningful
                            // without a species, and we don't want it to silently
                            // re-arm when the next Pokemon is picked.
                            side.megaActive = false
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }

                    // Mega Evolve toggle — surfaces for any species with a
                    // registered Mega form, even when the prerequisites
                    // (stone or Dragon Ascent) aren't met. Disabling instead
                    // of hiding makes the feature discoverable while still
                    // enforcing the canonical trigger. Flipping it never
                    // resets any other field on the set.
                    if side.hasAnyMegaForm {
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle(isOn: $side.megaActive) {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(side.canMegaEvolve ? .purple : .secondary)
                                    Text("Mega Evolve")
                                        .font(.subheadline.bold())
                                    if let form = side.availableMegaForm {
                                        Text("(\(form.displayName))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                            }
                            .tint(.purple)
                            .disabled(!side.canMegaEvolve)

                            if let hint = side.megaDisabledReason {
                                Text(hint)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        StatMini(label: "HP",  value: p.baseHP)
                        StatMini(label: "Atk", value: side.effectiveBaseAtk)
                        StatMini(label: "Def", value: side.effectiveBaseDef)
                        StatMini(label: "SpA", value: side.effectiveBaseSpAtk)
                        StatMini(label: "SpD", value: side.effectiveBaseSpDef)
                        StatMini(label: "Spe", value: side.effectiveBaseSpeed)
                    }
                    .font(.caption2)
                } else {
                    TextField("Search Mons...", text: $side.searchText)
                        .textFieldStyle(.roundedBorder)

                    if !filteredPokemon.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(filteredPokemon) { p in
                                    Button {
                                        side.pokemon = p
                                        side.searchText = ""
                                        side.selectedAbility = p.ability1
                                        side.teraType = nil
                                        side.moves = [nil, nil, nil, nil]
                                        side.moveSearchTexts = ["", "", "", ""]
                                        side.loadedSpreadName = nil
                                    } label: {
                                        HStack {
                                            Text(p.dexLabel).foregroundStyle(.secondary).lineLimit(1).scaledWidth(50, alignment: .leading)
                                            Text(p.name)
                                            Spacer()
                                            TypeBadge(type: p.type1)
                                            if let t2 = p.type2 { TypeBadge(type: t2) }
                                        }
                                        .padding(.vertical, 6).padding(.horizontal, 8)
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .background(Color(.tertiarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: CardMetrics.insetCornerRadius, style: .continuous))
                    }
                }
            }

            // Moves section
            if side.pokemon != nil, let vm {
                Divider()
                MoveSlotsSection(side: side, allMoves: allMoves, allPokemon: allPokemon, vm: vm)
            }

            // Save / Load Spreads
            Divider()
            if let spreadName = side.loadedSpreadName {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2).foregroundStyle(.red)
                    Text(spreadName)
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        side.loadedSpreadName = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            // Four buttons don't fit one row on a phone without wrapping
            // "Save Spread", so fall back to two rows when they won't.
            ViewThatFits(in: .horizontal) {
                HStack { spreadButtons; pasteButtons }
                VStack(alignment: .leading) {
                    HStack { spreadButtons }
                    HStack { pasteButtons }
                }
            }

            if let pkmn = side.pokemon {
                Divider()

                // Ability Picker — when Mega is active, lock the row to the
                // Mega's canonical ability so the UI reflects what the damage
                // calc is actually using (`effectiveAbility`). The underlying
                // `selectedAbility` storage is intentionally NOT mutated so
                // toggling Mega off restores the user's pre-Mega pick.
                // At accessibility sizes each picker gets its own line: a menu
                // picker doesn't grow taller when its value wraps.
                AdaptiveStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ability").font(.caption).foregroundStyle(.secondary)
                        if let mega = side.activeMegaForm {
                            HStack(spacing: 4) {
                                Text(formatAbilityName(mega.ability))
                                    .font(.body)
                                Text("· Mega")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Picker("Ability", selection: $side.selectedAbility) {
                                Text("None").tag(String?.none)
                                ForEach(pkmn.allAbilities, id: \.self) { a in
                                    Text(formatAbilityName(a)).tag(Optional(a))
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Item").font(.caption).foregroundStyle(.secondary)
                        Picker("Item", selection: $side.heldItem) {
                            ForEach(HeldItem.pickerOptions(forSpeciesNamed: pkmn.name,
                                                           championsMode: side.championsMode,
                                                           keeping: side.heldItem)) { item in
                                Text(item.pickerLabel(championsMode: side.championsMode)).tag(item)
                            }
                        }
                        .labelsHidden()
                    }
                }

                // Status + Current HP (Showdown-parity per-Pokemon options).
                AdaptiveStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Status").font(.caption).foregroundStyle(.secondary)
                        Picker("Status", selection: $side.status) {
                            ForEach(statusPickerOptions, id: \.0) { opt in
                                Text(opt.1).tag(opt.0)
                            }
                        }
                        .labelsHidden()
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current HP %").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            TextField("HP", value: Binding(
                                get: { side.currentHPPercent },
                                set: { v in
                                    let c = max(1, min(100, v))
                                    side.currentHPPercent = c
                                    side.atFullHP = c >= 100
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder).scaledWidth(54)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            Text("%").foregroundStyle(.secondary)
                        }
                    }
                }

                Toggle("Ability Active", isOn: $side.abilityOn)
                    .font(.subheadline)
                    .tint(.red)

                // Level + Nature
                AdaptiveStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Level").font(.caption).foregroundStyle(.secondary)
                        TextField("Lv", value: $side.level, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .scaledWidth(60)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nature").font(.caption).foregroundStyle(.secondary)
                        Picker("Nature", selection: $side.nature) {
                            ForEach(allNatures) { n in
                                Text("\(n.name) \(n.summary)").tag(n)
                            }
                        }
                        .labelsHidden()
                    }
                }

                // Champions Mode Toggle
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Champions Mode", isOn: Binding(
                        get: { side.championsMode },
                        set: { side.setChampionsMode($0) }
                    ))
                    .font(.subheadline)
                    .tint(.red)

                    if side.championsMode {
                        Text("EVs: 0-\(championsMaxEVPerStat) scale (\(championsMaxEVPerStat) = max). IVs fixed at \(championsLockedIV).")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    HStack {
                        let pct = side.evTotalMax > 0
                            ? Double(side.totalEVs) / Double(side.evTotalMax)
                            : 0
                        Text("\(side.totalEVs)/\(side.evTotalMax) EVs")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(side.totalEVs > side.evTotalMax ? .red : .secondary)
                        ProgressView(value: min(pct, 1.0))
                            .tint(pct >= 1.0 ? .red : .accentColor)
                            .frame(maxWidth: 80)
                        Spacer()
                        Button("Reset") {
                            side.evHP = 0; side.evAtk = 0; side.evDef = 0
                            side.evSpAtk = 0; side.evSpDef = 0; side.evSpeed = 0
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }
                }

                let evStep = side.championsMode ? 1 : 4
                DisclosureGroup("EVs (\(side.totalEVs)/\(side.evTotalMax))") {
                    CappedEVRow(label: "HP", side: side, keyPath: \.evHP, step: evStep)
                    CappedEVRow(label: "Atk", side: side, keyPath: \.evAtk, step: evStep)
                    CappedEVRow(label: "Def", side: side, keyPath: \.evDef, step: evStep)
                    CappedEVRow(label: "Sp.Atk", side: side, keyPath: \.evSpAtk, step: evStep)
                    CappedEVRow(label: "Sp.Def", side: side, keyPath: \.evSpDef, step: evStep)
                    CappedEVRow(label: "Speed", side: side, keyPath: \.evSpeed, step: evStep)
                }
                .font(.subheadline)

                if !side.championsMode {
                    DisclosureGroup("IVs") {
                        EVIVRow(label: "HP", value: $side.ivHP, range: 0...31, step: 1)
                        EVIVRow(label: "Atk", value: $side.ivAtk, range: 0...31, step: 1)
                        EVIVRow(label: "Def", value: $side.ivDef, range: 0...31, step: 1)
                        EVIVRow(label: "Sp.Atk", value: $side.ivSpAtk, range: 0...31, step: 1)
                        EVIVRow(label: "Sp.Def", value: $side.ivSpDef, range: 0...31, step: 1)
                        EVIVRow(label: "Speed", value: $side.ivSpeed, range: 0...31, step: 1)
                    }
                    .font(.subheadline)
                }

                DisclosureGroup("Stat Stages") {
                    StageRow(label: "Atk", stage: $side.atkStage)
                    StageRow(label: "Def", stage: $side.defStage)
                    StageRow(label: "Sp.Atk", stage: $side.spAtkStage)
                    StageRow(label: "Sp.Def", stage: $side.spDefStage)
                    StageRow(label: "Speed", stage: $side.speedStage)
                }
                .font(.subheadline)

                // Per-side field conditions. When this Pokemon is attacking, the
                // "attacking" rows apply; when defending, the "defending" rows do.
                DisclosureGroup("Field Conditions") {
                    Text("While attacking").font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("Helping Hand", isOn: $side.isHelpingHand).font(.subheadline)
                    Toggle("Tailwind", isOn: $side.isTailwind).font(.subheadline)

                    Divider()
                    Text("While defending").font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("Reflect", isOn: $side.isReflect).font(.subheadline)
                    Toggle("Light Screen", isOn: $side.isLightScreen).font(.subheadline)
                    Toggle("Aurora Veil", isOn: $side.isAuroraVeil).font(.subheadline)
                    Toggle("Friend Guard", isOn: $side.isFriendGuard).font(.subheadline)
                    Toggle("Protect", isOn: $side.isProtected).font(.subheadline)
                    Toggle("Stealth Rock", isOn: $side.isStealthRock).font(.subheadline)
                    Stepper(value: $side.spikesLayers, in: 0...3) {
                        Text("Spikes: \(side.spikesLayers)").font(.subheadline)
                    }
                }
                .font(.subheadline)
                .tint(.red)

                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Final Stats").font(.caption.bold()).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        StatMini(label: "HP", value: side.hp)
                        StatMini(label: "Atk", value: side.atk)
                        StatMini(label: "Def", value: side.def)
                        StatMini(label: "SpA", value: side.spAtk)
                        StatMini(label: "SpD", value: side.spDef)
                        StatMini(label: "Spe", value: side.speed)
                    }
                    .font(.caption2)
                }
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveSpreadSheet(side: side, modelContext: modelContext, isPresented: $showSaveSheet)
            .sheetSize()
        }
        .sheet(isPresented: $showPasteSheet) {
            PasteImportSheet(side: side, allPokemon: allPokemon, allMoves: allMoves)
            .sheetSize()
        }
        .sheet(isPresented: $showLoadSheet) {
            LoadSpreadSheet(side: side, spreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves, modelContext: modelContext, isPresented: $showLoadSheet)
            .sheetSize()
        }
        #if DEBUG && os(macOS)
        .task {
            await DebugSnapshot.openSheet("save") { showSaveSheet = true }
            await DebugSnapshot.openSheet("paste") { showPasteSheet = true }
            await DebugSnapshot.openSheet("load") { showLoadSheet = true }
        }
        #endif
    }
}

// MARK: - Move Slots Section

private struct MoveSlotsSection: View {
    @Bindable var side: CalcSide
    let allMoves: [MoveData]
    let allPokemon: [PKMNStats]
    var vm: DamageCalcVM

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Moves").font(.subheadline.bold())
                Spacer()
                if side.pokemon != nil {
                    Toggle("Legal only", isOn: $side.filterLegalMoves)
                        .font(.caption)
                        .tint(.red)
                        .fixedSize()
                }
            }

            ForEach(0..<4, id: \.self) { index in
                MoveSlotView(index: index, side: side, allMoves: allMoves, allPokemon: allPokemon, vm: vm)
            }
        }
    }
}

private struct MoveSlotView: View {
    let index: Int
    @Bindable var side: CalcSide
    let allMoves: [MoveData]
    let allPokemon: [PKMNStats]
    var vm: DamageCalcVM

    var body: some View {
        if let move = side.moves[index] {
            HStack(spacing: 6) {
                Text("\(index + 1).").font(.caption).foregroundStyle(.tertiary)
                FlowLayout(spacing: 6) {
                    Text(move.name).font(.subheadline.bold()).lineLimit(1)
                    TypeBadge(type: move.type)
                    Text("\(move.power ?? 0) BP")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize()
                    DamageClassBadge(damageClass: move.damageClass)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { side.moves[index] = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(index + 1).").font(.caption).foregroundStyle(.tertiary)
                    TextField("Move \(index + 1)...", text: Binding(
                        get: { side.moveSearchTexts[index] },
                        set: { side.moveSearchTexts[index] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                }

                let results = vm.filteredMoves(for: side, slotIndex: index, allMoves: allMoves, allPokemon: allPokemon)
                if !results.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(results) { move in
                                Button {
                                    side.moves[index] = move
                                    side.moveSearchTexts[index] = ""
                                } label: {
                                    HStack {
                                        Text(move.name)
                                        Spacer()
                                        TypeBadge(type: move.type)
                                        Text("\(move.power ?? 0) BP")
                                            .font(.caption).foregroundStyle(.secondary)
                                        DamageClassBadge(damageClass: move.damageClass)
                                    }
                                    .padding(.vertical, 4).padding(.horizontal, 8)
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .background(Color(.tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: CardMetrics.insetCornerRadius, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Modifiers Card

private struct ModifiersCard: View {
    @Bindable var vm: DamageCalcVM

    var body: some View {
        SectionCard(title: "Modifiers", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Weather").font(.subheadline).foregroundStyle(.secondary)
                Picker("Weather", selection: $vm.weather) {
                    ForEach(WeatherCondition.allCases) { w in
                        Text(w.rawValue).tag(w)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if vm.weather == .sand {
                    Text("Rock-type defenders get 1.5x Sp.Def in Sand")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if vm.weather == .snow {
                    Text("Ice-type defenders get 1.5x Def in Snow")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Terrain").font(.subheadline).foregroundStyle(.secondary)
                Picker("Terrain", selection: $vm.terrain) {
                    ForEach(TerrainCondition.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if vm.terrain == .electric {
                    Text("1.3x Electric moves for grounded Pokemon")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if vm.terrain == .grassy {
                    Text("1.3x Grass moves for grounded Pokemon")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if vm.terrain == .misty {
                    Text("0.5x Dragon moves against grounded Pokemon")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if vm.terrain == .psychic {
                    Text("1.3x Psychic moves for grounded Pokemon")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Field").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    ToggleBadge(label: "Gravity", on: $vm.gravity)
                    ToggleBadge(label: "Wonder Room", on: $vm.wonderRoom)
                }
                HStack {
                    ToggleBadge(label: "Magic Room", on: $vm.magicRoom)
                    ToggleBadge(label: "Doubles (Spread)", on: $vm.multi)
                }
            }

            HStack {
                ToggleBadge(label: "Crit", on: $vm.crit)
                ToggleBadge(label: "Burn", on: $vm.burn)
            }
            HStack {
                ToggleBadge(label: "Glaive Rush", on: $vm.glaiveRush)
                ToggleBadge(label: "Z-Move Bypass", on: $vm.zMoveBypass)
            }

            HStack {
                Text("Misc Multiplier").font(.subheadline)
                Spacer()
                TextField("x", value: $vm.miscMultiplier, format: .number)
                    .textFieldStyle(.roundedBorder).scaledWidth(70)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
        }
    }
}

// MARK: - Save / Load Spread Sheets

private struct SaveSpreadSheet: View {
    var side: CalcSide
    var modelContext: ModelContext
    @Binding var isPresented: Bool
    @State private var name: String

    init(side: CalcSide, modelContext: ModelContext, isPresented: Binding<Bool>) {
        self.side = side
        self.modelContext = modelContext
        self._isPresented = isPresented
        self._name = State(initialValue: side.loadedSpreadName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Spread Name") {
                    TextField("Spread Name", text: $name, prompt: Text("e.g. Physical Sweeper"))
                        .labelsHidden()
                }
                Section("Summary") {
                    if let pkmn = side.pokemon {
                        LabeledContent("Pokemon", value: pkmn.name)
                    }
                    LabeledContent("Nature", value: side.nature.name)
                    LabeledContent("EVs", value: "\(side.evHP)/\(side.evAtk)/\(side.evDef)/\(side.evSpAtk)/\(side.evSpDef)/\(side.evSpeed)")
                    if !side.championsMode {
                        LabeledContent("IVs", value: "\(side.ivHP)/\(side.ivAtk)/\(side.ivDef)/\(side.ivSpAtk)/\(side.ivSpDef)/\(side.ivSpeed)")
                    }
                    if side.championsMode {
                        LabeledContent("Mode", value: "Champions")
                    }
                    let moveNames = side.moves.compactMap { $0?.name }
                    if !moveNames.isEmpty {
                        LabeledContent("Moves", value: moveNames.joined(separator: ", "))
                    }
                }
            }
            .navigationTitle("Save Spread")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let finalName = name.isEmpty ? "Untitled" : name
                        let spread = side.toSavedSpread(name: finalName)
                        modelContext.insert(spread)
                        side.loadedSpreadName = finalName
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct LoadSpreadSheet: View {
    var side: CalcSide
    let spreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    var modelContext: ModelContext
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(spreads) { spread in
                    Button {
                        side.loadSpread(spread, allPokemon: allPokemon, allMoves: allMoves)
                        isPresented = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(spread.name).font(.headline)
                                Spacer()
                                if spread.championsMode {
                                    Text("Champions")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .foregroundStyle(.red)
                                        .background(Color.red.opacity(0.15), in: Capsule())
                                }
                            }
                            HStack(spacing: 8) {
                                if let pkmn = spread.pokemonName {
                                    Text(pkmn).font(.caption).foregroundStyle(.secondary)
                                }
                                if let ability = spread.abilityName {
                                    Text(formatAbilityName(ability))
                                        .font(.caption2)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .foregroundStyle(ColorRole.ability.color)
                                        .background(ColorRole.ability.color.opacity(0.12), in: Capsule())
                                }
                                if let item = spread.itemRawValue, item != HeldItem.none.rawValue {
                                    Text(HeldItem.currentName(item))
                                        .font(.caption2)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .foregroundStyle(ColorRole.item.color)
                                        .background(ColorRole.item.color.opacity(0.12), in: Capsule())
                                }
                                // The same chips, in the same order, as the set list.
                                if let nature = allNatures.first(where: { $0.id == spread.natureID }) {
                                    Text(nature.name)
                                        .font(.caption2)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .foregroundStyle(ColorRole.nature.color)
                                        .background(ColorRole.nature.color.opacity(0.12), in: Capsule())
                                }
                            }
                            Text("EVs: \(spread.evHP)/\(spread.evAtk)/\(spread.evDef)/\(spread.evSpAtk)/\(spread.evSpDef)/\(spread.evSpeed)")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    // Swiping to delete needs a trackpad on the Mac, and
                    // there's no edit mode.
                    .contextMenu {
                        Button("Delete", role: .destructive) { modelContext.delete(spread) }
                    }
                    #endif
                }
                .onDelete { indices in
                    for i in indices {
                        modelContext.delete(spreads[i])
                    }
                }
            }
            .navigationTitle("Load Spread")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
                #endif
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Reusable Components

struct DamageClassBadge: View {
    let damageClass: String
    private var label: String {
        switch damageClass {
        case "physical": return "Phys"
        case "special":  return "Spec"
        case "status":   return "Status"
        default:         return damageClass.capitalized
        }
    }
    private var color: Color {
        switch damageClass {
        case "physical": return .orange
        case "special":  return .indigo
        case "status":   return .gray
        default:         return .secondary
        }
    }
    var body: some View {
        Text(label)
            .scaledFont(size: 9, weight: .semibold, relativeTo: .caption2)
            .fixedSize()
            .padding(.horizontal, 4).padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct StatMini: View {
    let label: String
    let value: Int
    var body: some View {
        VStack(spacing: 1) {
            Text(label).foregroundStyle(.secondary)
            Text("\(value)").bold()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CappedEVRow: View {
    let label: String
    var side: CalcSide
    let keyPath: ReferenceWritableKeyPath<CalcSide, Int>
    var step: Int = 4

    private var cap: Int {
        side.maxAllowedEV(excluding: side[keyPath: keyPath])
    }

    var body: some View {
        let perStatMax = side.evPerStatMax
        HStack {
            Text(label).lineLimit(1).scaledWidth(58, alignment: .leading)
            Slider(value: Binding(
                get: { Double(side[keyPath: keyPath]) },
                set: { newVal in
                    let clamped = max(0, min(Int(newVal), cap))
                    side[keyPath: keyPath] = clamped
                    side.loadedSpreadName = nil
                }
            ), in: 0...Double(max(perStatMax, 1)), step: Double(step))
            .tint(.red)
            TextField("", value: Binding(
                get: { side[keyPath: keyPath] },
                set: { newVal in
                    let clamped = max(0, min(newVal, cap))
                    side[keyPath: keyPath] = clamped
                    side.loadedSpreadName = nil
                }
            ), format: .number)
                .textFieldStyle(.roundedBorder).scaledWidth(50)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        }
    }
}

private struct EVIVRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 4

    var body: some View {
        HStack {
            Text(label).lineLimit(1).scaledWidth(58, alignment: .leading)
            Slider(value: Binding(
                get: { Double(min(max(value, range.lowerBound), range.upperBound)) },
                set: { value = max(range.lowerBound, min(Int($0), range.upperBound)) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
            .tint(.red)
            TextField("", value: Binding(
                get: { min(max(value, range.lowerBound), range.upperBound) },
                set: { value = max(range.lowerBound, min($0, range.upperBound)) }
            ), format: .number)
                .textFieldStyle(.roundedBorder).scaledWidth(50)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        }
    }
}

private struct StageRow: View {
    let label: String
    @Binding var stage: Int
    var body: some View {
        HStack {
            Text(label).lineLimit(1).scaledWidth(58, alignment: .leading)
            Stepper(value: $stage, in: -6...6) {
                Text(stage > 0 ? "+\(stage)" : "\(stage)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(stage > 0 ? .green : stage < 0 ? .red : .secondary)
            }
        }
    }
}

private struct ToggleBadge: View {
    let label: String
    @Binding var on: Bool
    var body: some View {
        Toggle(isOn: $on) { Text(label).font(.subheadline) }
            .toggleStyle(.button).buttonStyle(.bordered)
            .tint(on ? .red : .secondary).frame(maxWidth: .infinity)
    }
}

// MARK: - Helpers

/// An ability's official name from its PokeAPI slug: "beads-of-ruin" is
/// "Beads of Ruin". A name that's already formatted comes back unchanged.
nonisolated func formatAbilityName(_ raw: String) -> String {
    // Keyed by the slug, so an already-formatted name finds its entry too.
    let key = raw.lowercased()
        .replacingOccurrences(of: " ", with: "-")
        .filter { !"'()".contains($0) }
    if let name = abilityNameExceptions[key] { return name }
    let words = raw.lowercased().split { $0 == "-" || $0 == " " }
    return words.enumerated().map { index, word in
        index > 0 && ["of", "to"].contains(word) ? String(word) : word.capitalized
    }.joined(separator: " ")
}

/// Official names that splitting a slug at its hyphens gets wrong.
nonisolated private let abilityNameExceptions: [String: String] = [
    "minds-eye": "Mind's Eye",
    "soul-heart": "Soul-Heart",
    "well-baked-body": "Well-Baked Body",
    "rks-system": "RKS System",
    // PokeAPI splits As One by Calyrex's steed; the games call both "As One".
    "as-one-glastrier": "As One (Glastrier)",
    "as-one-spectrier": "As One (Spectrier)",
]

/// Ordered (value, label) pairs for the per-Pokemon Status picker.
let statusPickerOptions: [(ShowdownStatus, String)] = [
    (.none, "Healthy"), (.brn, "Burn"), (.psn, "Poison"), (.tox, "Badly Poisoned"),
    (.par, "Paralysis"), (.slp, "Sleep"), (.frz, "Freeze"),
]

func statusLabel(_ status: ShowdownStatus) -> String {
    statusPickerOptions.first { $0.0 == status }?.1 ?? "Healthy"
}

// MARK: - Preview

#Preview {
    DamageCalculatorView()
        .modelContainer(for: [PKMNStats.self, MoveData.self])
}
