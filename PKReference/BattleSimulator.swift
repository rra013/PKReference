//
//  BattleSimulator.swift
//  PKReference
//
//  Created by Rishi Anand on 5/17/26.
//

import SwiftUI
import SwiftData

// MARK: - Format

enum BattleFormat: String, CaseIterable, Identifiable {
    case singles, doubles
    var id: String { rawValue }
    var label: String { self == .singles ? "Singles" : "Doubles" }
    var activeSlots: Int { self == .singles ? 1 : 2 }
    /// Official VGC-style "bring 6 pick N": singles brings 3, doubles brings 4.
    var bringCount: Int { self == .singles ? 3 : 4 }
}

// MARK: - Status & Move Effects

enum BattleStatus: String, Equatable {
    case none, burn, paralysis, poison, toxic, sleep, freeze

    var shortLabel: String {
        switch self {
        case .none: return ""
        case .burn: return "BRN"
        case .paralysis: return "PAR"
        case .poison: return "PSN"
        case .toxic: return "TOX"
        case .sleep: return "SLP"
        case .freeze: return "FRZ"
        }
    }

    var color: Color {
        switch self {
        case .burn: return .red
        case .paralysis: return .yellow
        case .poison, .toxic: return .purple
        case .sleep: return .gray
        case .freeze: return .cyan
        case .none: return .clear
        }
    }
}

enum BattleStatChange {
    case selfMod([(Nature.StatKey, Int)])
    case opponentMod([(Nature.StatKey, Int)])
}

enum BattleHazard: CaseIterable {
    case stealthRock, spikes, stickyWeb, toxicSpikes
}

/// Lookup tables for non-damaging move effects. Keys are normalized via
/// `BattleSimSeed.normalize` (lowercased, alphanumerics only) so the engine works
/// whether `MoveData.name` arrives as "Swords Dance", "swords-dance", or "SwordsDance".
enum BattleMoveEffects {

    /// Whether a move hits more than one Pokemon in doubles. Reads the move's
    /// target from the Showdown data via `SpreadMoves`; this used to be a
    /// hand-written list that was missing half the spread moves and wrongly
    /// included Earth Power.
    static func isSpread(_ moveName: String) -> Bool {
        SpreadMoves.isSpread(moveName)
    }

    // MARK: Data tables
    //
    // Read from `battle_moves.json`, whose notes describe each table. The
    // kinds they name (PivotKind, ScreenKind…) stay declared here.

    private static let data = BattleMovesData.loadBundled()

    /// Moves that only succeed on the user's first action since switching in.
    /// Mirrors Showdown's `onTry { if (source.activeMoveActions > 1) return false }`.
    static let firstTurnOnlyMoves: Set<String> = data.firstTurnOnly
    static let statChanges: [String: BattleStatChange] = data.statChanges
    static let statusInflicts: [String: BattleStatus] = data.statusInflicts
    /// Status moves that confuse the target. Some (Swagger, Flatter) also apply a
    /// stat boost on the target before confusing — handled in `applyStatusMoveEffect`.
    static let confusionInflicts: Set<String> = data.confusionInflicts
    static let weatherSetters: [String: WeatherCondition] = data.weatherSetters
    static let terrainSetters: [String: TerrainCondition] = data.terrainSetters
    static let hazardSetters: [String: BattleHazard] = data.hazardSetters
    /// Protect-family moves. The shared logic (turn-skip, diminishing chance,
    /// consecutive counter) lives in `applyProtectFamily`. Each variant layers a
    /// secondary effect on the attacker via `protectContactEffect`.
    static let protectFamily: Set<String> = data.protectFamily

    /// Moves that pivot the user out after dealing damage (or always, for the
    /// status pivots). `force` = always switch even if the move dealt no damage
    /// (Teleport, Parting Shot, Baton Pass, Shed Tail). Damage-pivots only swap
    /// out when the move connected.
    enum PivotKind: CaseIterable { case damage, force }
    static let pivotMoves: [String: PivotKind] = data.pivotMoves

    /// Screen-setting status moves. Each lasts 5 turns (8 with Light Clay).
    /// Aurora Veil only succeeds in hail/snow weather.
    enum ScreenKind: CaseIterable { case light, reflect, aurora, safeguard }
    static let screenSetters: [String: ScreenKind] = data.screenSetters

    /// Global room/field-effect status moves. Each toggles its respective
    /// engine-level counter (5 turns).
    enum RoomKind: CaseIterable { case trickRoom, wonderRoom, magicRoom, gravity }
    static let roomSetters: [String: RoomKind] = data.roomSetters

    /// Side-tailwind setter. 4 turns of doubled Speed for the user's side.
    static let tailwindKey = "tailwind"

    /// Status moves whose "target" is fixed (the user, the user's side, or the
    /// field) and therefore should never pop a target picker. The action chooser
    /// records these with the actor's own (side, slot) as the target — the
    /// engine ignores the target field for moves whose effect doesn't depend
    /// on it (Protect, Calm Mind, Tailwind, Trick Room, Sunny Day, Spikes…).
    /// Built once from the categorical tables above so any new entry in those
    /// dictionaries automatically participates.
    static let fixedSelfOrFieldTarget: Set<String> = {
        var s = Set<String>()
        // Protect family — every variant is self-target.
        s.formUnion(protectFamily)
        // Self stat boosts: anything in statChanges with a `.selfMod` is self-target.
        for (k, v) in statChanges {
            if case .selfMod = v { s.insert(k) }
        }
        // Side / field-wide toggles.
        s.formUnion(screenSetters.keys)
        s.formUnion(roomSetters.keys)
        s.formUnion(weatherSetters.keys)
        s.formUnion(terrainSetters.keys)
        s.formUnion(hazardSetters.keys)
        s.insert(tailwindKey)
        // Pivot moves that switch the USER out (Teleport, Baton Pass, Shed Tail,
        // Chilly Reception). Parting Shot debuffs the opponent, so it stays a
        // single-target enemy move.
        for (k, kind) in pivotMoves where kind == .force {
            if k == "partingshot" { continue }
            s.insert(k)
        }
        // Heals, recovery, and self-volatile moves that don't have a clean
        // categorical home above. Each entry is the BattleSimSeed.normalize'd
        // form (lowercase, alphanumerics only).
        let curated: Set<String> = [
            "substitute", "recover", "roost", "softboiled", "milkdrink",
            "moonlight", "morningsun", "synthesis", "slackoff", "rest",
            "wish", "aquaring", "ingrain", "bellydrum", "destinybond",
            "endure", "minimize", "withdraw", "harden", "splash",
            "stockpile", "swallow", "spitup", "focusenergy",
            "haze", "courtchange", "magneticflux", "powertrick",
            "purify", "refresh", "healbell", "aromatherapy",
        ]
        s.formUnion(curated)
        return s
    }()

    /// True if `moveName` is one of the fixed-target status moves above. Helper
    /// for the action chooser so it can skip the target picker.
    static func isFixedSelfOrFieldTarget(_ moveName: String) -> Bool {
        fixedSelfOrFieldTarget.contains(BattleSimSeed.normalize(moveName))
    }

    /// Hazard-removal moves. `removeFromOwn` = user-side hazards (Rapid Spin,
    /// Tidy Up, Mortal Spin); Defog removes from BOTH sides; Tidy Up additionally
    /// removes all screens. Mortal Spin also poisons every opposing active mon.
    enum HazardRemoval: CaseIterable { case ownSide, bothSides, tidyUp, mortalSpin }
    static let hazardRemovers: [String: HazardRemoval] = data.hazardRemovers

    /// Tier 3 status-move keys that need bespoke logic (Pain Split, Wish,
    /// Heal Bell, Substitute, etc.). Routed through `applyTier3StatusMove`.
    static let tier3StatusMoves: Set<String> = [
        "painsplit", "healpulse", "lifedew", "healbell", "aromatherapy",
        "strengthsap", "wish", "yawn", "leechseed", "endure",
        "encore", "disable", "destinybond", "substitute", "roost",
        "curse",
    ]

    /// Tier 5 status moves — bespoke logic routed through `applyTier5StatusMove`.
    static let tier5StatusMoves: Set<String> = [
        "trick", "switcheroo", "memento", "bellydrum", "clangoroussoul",
        "healingwish", "lunardance",
        "roar", "whirlwind", "dragontail", "circlethrow",
        "endeavor",
    ]

    /// Tier 5 fixed-damage / damage-return moves. Routed through
    /// `applyTier5FixedDamage` before the normal damage path runs.
    static let tier5FixedDamage: Set<String> = [
        "seismictoss", "nightshade", "dragonrage", "sonicboom",
        "superfang", "finalgambit", "counter", "mirrorcoat",
    ]

    /// OHKO moves, routed through `applyOHKO`. Accuracy uses the canon
    /// level-diff formula.
    static let ohkoMoves: Set<String> = data.ohkoMoves
    /// Trap moves: deal damage normally and apply the trap volatile on hit.
    static let trapMoves: Set<String> = data.trapMoves

    /// Power/stat modifier keys for damage-class moves. Tier 5 additions:
    /// Body Press / Foul Play swap the attacking stat; Acrobatics, Hex,
    /// Venoshock, Stored Power, Power Trip apply a conditional power multi.
    /// Tier 9 additions (weight-based): Heat Crash & Heavy Slam scale power
    /// by attacker/defender weight ratio; Grass Knot & Low Kick by defender
    /// weight alone.
    static let damageModifierKeys: Set<String> = [
        "bodypress", "foulplay", "acrobatics", "hex", "venoshock",
        "storedpower", "powertrip",
        "heatcrash", "heavyslam", "grassknot", "lowkick",
    ]

    /// Ballistic-class moves — blocked by Bulletproof.
    static let ballisticMoves: Set<String> = data.ballisticMoves

    /// Two-turn charge moves. Turn 1 the user charges (no damage); turn 2
    /// the move releases at full power. Some skip the charge turn under the
    /// matching weather (Solar Beam in sun, Electro Shot in rain). Some apply
    /// a self-boost during the charge (Meteor Beam +SpA, Skull Bash +Def,
    /// Electro Shot +SpA). Geomancy is a status-class charge — the release
    /// turn applies the +2 SpA/SpD/Spe boost instead of dealing damage.
    ///
    /// Tier 8 extension: `invulnerabilityKind` makes the user untargetable
    /// during the charge turn except by listed exceptions. `bypassesProtect`
    /// lets Phantom Force / Shadow Force ignore the defender's Protect.
    enum InvulnerabilityKind: CaseIterable {
        case underground   // Dig
        case airborne      // Fly / Bounce
        case underwater    // Dive
        case vanished      // Phantom Force / Shadow Force
    }
    struct ChargeBehavior {
        var chargeLog: String                 // "{user} absorbed light!"
        var skipInWeather: WeatherCondition? = nil
        var selfBoostsOnCharge: [(Nature.StatKey, Int)] = []
        var statusOnRelease: [(Nature.StatKey, Int)] = []
        var invulnerabilityKind: InvulnerabilityKind? = nil
        var bypassesProtect: Bool = false
    }
    static let chargeMoves: [String: ChargeBehavior] = data.chargeMoves

    /// Approximate species weight (kg) for weight-based moves. Hardcoded for
    /// common Champions species; falls back to 50 kg for unlisted entries via
    /// `weightForSpecies`. PokeAPI's canonical weights stored × 10 in the
    /// original game data — we use whole kg because the move-power thresholds
    /// have plenty of room.
    static let weightKg: [String: Int] = [
        // VGC mainstays
        "Charizard": 91, "Blastoise": 86, "Venusaur": 100,
        "Tyranitar": 202, "Garchomp": 95, "Salamence": 102,
        "Metagross": 550, "Snorlax": 460, "Aegislash": 53,
        "Aegislash-Shield": 53, "Aegislash-Blade": 53,
        "Gyarados": 235, "Dragonite": 210, "Gardevoir": 48,
        "Greninja": 40, "Talonflame": 24, "Sylveon": 23,
        "Incineroar": 83, "Decidueye": 36, "Primarina": 44,
        "Mimikyu": 1, "Mimikyu-Disguised": 1, "Mimikyu-Busted": 1,
        "Kommo-o": 78, "Toxapex": 14, "Mudsdale": 920,
        "Excadrill": 40, "Conkeldurr": 87, "Hydreigon": 160,
        "Magnezone": 180, "Heatran": 430, "Zapdos": 52,
        "Landorus": 68, "Tornadus": 63, "Thundurus": 61,
        "Kyurem": 325, "Reshiram": 330, "Zekrom": 345,
        "Palafin": 60, "Palafin-Hero": 97,
        "Iron Hands": 380, "Iron Bundle": 11, "Roaring Moon": 380,
        "Flutter Mane": 4, "Iron Valiant": 35,
        "Annihilape": 56, "Tinkaton": 113, "Ceruledge": 62,
        "Armarouge": 85, "Maushold": 23, "Basculegion": 110,
        "Basculegion-Male": 110, "Basculegion-Female": 110,
        "Farigiraf": 160, "Wo-Chien": 74, "Chien-Pao": 152,
        "Ting-Lu": 700, "Chi-Yu": 5, "Gholdengo": 30,
        "Ogerpon": 40, "Pelipper": 28, "Indeedee": 28, "Indeedee-Female": 28,
        "Rillaboom": 90, "Cinderace": 33, "Inteleon": 46,
        "Grimmsnarl": 61, "Dragapult": 50, "Toxtricity": 40,
        "Sableye": 11, "Volcarona": 46, "Whimsicott": 7,
        "Klefki": 3, "Pachirisu": 4, "Cresselia": 86,
    ]

    /// Look up a species' weight in kg, defaulting to 50 for unknown entries.
    /// Used by Heat Crash / Heavy Slam / Grass Knot / Low Kick.
    static func weightForSpecies(_ name: String) -> Int {
        weightKg[name] ?? 50
    }

    /// Heat Crash / Heavy Slam power table: power scales with how much heavier
    /// the user is than the target. Canon thresholds (Gen V+):
    ///   target ≤ 1/5 user weight   → 120
    ///   target ≤ 1/4 user weight   → 100
    ///   target ≤ 1/3 user weight   →  80
    ///   target ≤ 1/2 user weight   →  60
    ///   otherwise                  →  40
    static func heavySlamPower(attackerWeight: Int, defenderWeight: Int) -> Int {
        guard defenderWeight > 0 else { return 40 }
        let ratio = Double(defenderWeight) / Double(max(1, attackerWeight))
        if ratio <= 0.2 { return 120 }
        if ratio <= 0.25 { return 100 }
        if ratio <= 1.0 / 3.0 { return 80 }
        if ratio <= 0.5 { return 60 }
        return 40
    }

    /// Grass Knot / Low Kick power table based on TARGET weight alone:
    ///   <10 kg  →  20
    ///   <25 kg  →  40
    ///   <50 kg  →  60
    ///   <100 kg →  80
    ///   <200 kg → 100
    ///   ≥200 kg → 120
    static func weightPower(defenderWeight: Int) -> Int {
        if defenderWeight < 10 { return 20 }
        if defenderWeight < 25 { return 40 }
        if defenderWeight < 50 { return 60 }
        if defenderWeight < 100 { return 80 }
        if defenderWeight < 200 { return 100 }
        return 120
    }

    /// Moves that can hit a semi-invulnerable defender. Each invulnerability
    /// kind has its own list; anything else misses entirely.
    static let invulnerabilityExceptions: [InvulnerabilityKind: Set<String>] = data.invulnerabilityExceptions
    /// Of the exception moves above, these deal DOUBLE damage to the
    /// invulnerable defender (canon: Earthquake on Dig, Surf on Dive, …).
    static let invulnerabilityDoubleDamage: [InvulnerabilityKind: Set<String>] = data.invulnerabilityDoubleDamage
    /// Sound-class moves — blocked by Soundproof.
    static let soundMoves: Set<String> = data.soundMoves

    /// Abilities that automatically set weather when the Pokemon enters the field
    /// (initial send-out, regular switch, forced switch after a KO, or Mega Evolution).
    /// Keyed by ability ID (matching `computeAbilityModifiers`), not by move name.
    static let weatherAbilities: [String: WeatherCondition] = [
        "drought":         .sun,
        "drizzle":         .rain,
        "sand-stream":     .sand,
        "snow-warning":    .snow,
        "desolate-land":   .sun,
        "primordial-sea":  .rain,
        "orichalcum-pulse": .sun,
    ]

    /// Abilities that automatically set terrain on entry.
    static let terrainAbilities: [String: TerrainCondition] = [
        "electric-surge": .electric,
        "grassy-surge":   .grassy,
        "misty-surge":    .misty,
        "psychic-surge":  .psychic,
        "hadron-engine":  .electric,
    ]

    /// Fallback for moves whose GraphQL sync didn't populate `minHits`/`maxHits`.
    /// `(min, max)` — fixed-count moves use the same value for both.
    static let multiHitFallback: [String: (Int, Int)] = data.multiHitFallback
    /// Fallback contact-move table for when the synced `MoveData.makesContact`
    /// is unreliable. Final contact check is `move.makesContact || contactMoves.contains(key)`.
    static let contactMoves: Set<String> = data.contactMoves
    /// Probabilistic on-hit effects (target must survive).
    static let secondaryEffects: [String: SecondaryEffect] = data.secondaryEffects
    /// ALWAYS-on self stat changes after a damaging hit (not probabilistic).
    static let selfStatChangesOnHit: [String: [(Nature.StatKey, Int)]] = data.selfStatChangesOnHit
    /// Setup moves (stat boosts and the like). The Champions validator flags
    /// one on a set holding a Choice item.
    static let setupMoves: Set<String> = data.setupMoves
    /// Moves the user must recharge after, moves that faint the user, and
    /// moves that fail if the user is hit first. The sim doesn't model these
    /// yet; the Problem Solver marks them.
    static let rechargeMoves: Set<String> = data.rechargeMoves
    static let selfKOMoves: Set<String> = data.selfKOMoves
    static let failsIfHitMoves: Set<String> = data.failsIfHitMoves
}

/// Encoded secondary effect for a damaging move. `chance` is the printed percent;
/// `status` (if non-nil) is inflicted on the target; `flinch` causes a flinch flag;
/// `targetDrops` lists negative stat-stage deltas on the target.
///
/// Tier 2 fields:
/// - `selfBoosts` — self stat-stage changes (Power-Up Punch +Atk, Charge Beam +SpA).
/// - `setsHazardOnFoe` — drop a hazard on the foe side after the hit (Stone Axe,
///   Ceaseless Edge → Spikes).
/// - `groundsTarget` — set the target's `grounded` flag (Smack Down).
/// - `curesTargetBurn` — heal the target's burn on hit (Sparkling Aria — in canon
///   this also cures allies in doubles; Tier 2 only cures the direct target).
/// - `saltCureVolatile` — apply Salt Cure to the target (per-turn HP chip,
///   doubled vs Water/Steel types).
/// - `requiresTargetBoost` — only fire the rest of the effect if the target has
///   at least one positive stat stage (Burning Jealousy).
struct SecondaryEffect {
    var chance: Int
    var status: BattleStatus? = nil
    var flinch: Bool = false
    var targetDrops: [(Nature.StatKey, Int)] = []
    var selfBoosts: [(Nature.StatKey, Int)] = []
    var setsHazardOnFoe: BattleHazard? = nil
    var groundsTarget: Bool = false
    var curesTargetBurn: Bool = false
    var saltCureVolatile: Bool = false
    var requiresTargetBoost: Bool = false
}

// MARK: - Stance Form (Aegislash)

/// Stat override for non-Mega in-battle form changes. Today only Aegislash uses
/// this (Stance Change), but the shape is generic so additional form-changers
/// (Mimikyu's Busted form, Wishiwashi's school, etc.) can slot in later.
/// HP is intentionally omitted — Stance Change preserves HP, so the base
/// species' HP stat carries over.
struct StanceForm: Equatable {
    let displayName: String
    let baseAtk: Int
    let baseDef: Int
    let baseSpAtk: Int
    let baseSpDef: Int
    let baseSpeed: Int

    /// Aegislash-Shield — 60/50/150/50/150/60. Defensive Forme; default stance.
    static let aegislashShield = StanceForm(
        displayName: "Aegislash-Shield",
        baseAtk: 50, baseDef: 150,
        baseSpAtk: 50, baseSpDef: 150, baseSpeed: 60
    )

    /// Aegislash-Blade — 60/150/50/150/50/60. Offensive Forme.
    static let aegislashBlade = StanceForm(
        displayName: "Aegislash-Blade",
        baseAtk: 150, baseDef: 50,
        baseSpAtk: 150, baseSpDef: 50, baseSpeed: 60
    )
}

// MARK: - Live Participant

@Observable
final class BattleParticipant: Identifiable {
    let id = UUID()
    let slot: TeamSlotInfo
    let stats: PKMNStats?
    let moves: [MoveData]
    let nature: Nature
    /// Mutable because Trick / Switcheroo / Pickpocket can swap items between
    /// participants mid-battle. Reverts on switch only for the *holder* — the
    /// stolen-from / swapped-to participant carries the new item until they
    /// also switch.
    var heldItem: HeldItem
    let maxHP: Int

    var currentHP: Int
    var pp: [Int]
    var status: BattleStatus = .none
    var sleepTurnsRemaining: Int = 0
    var toxicCounter: Int = 0

    var atkStage: Int = 0
    var defStage: Int = 0
    var spAtkStage: Int = 0
    var spDefStage: Int = 0
    var speedStage: Int = 0

    /// Set when this Pokemon has Mega Evolved this battle. Persists across switches.
    var megaForm: MegaForm? = nil

    /// In-battle form override for non-Mega form changers (Stance Change). Reset on
    /// switch via `resetVolatile()`. When non-nil it shadows the participant's
    /// base stats / display name in the same way `megaForm` does, but with looser
    /// priority (a Mega still wins). Currently only Aegislash uses this.
    var stanceForm: StanceForm? = nil

    /// True after a one-shot held item (berry, Focus Sash, Mental/White Herb) has
    /// been used. After this point `effectiveHeldItem` returns `.none`.
    var consumedItem: Bool = false

    /// True after Knock Off (or a future item-removal move) has stripped the item.
    var knockedOff: Bool = false

    /// Set when a hit that procced King's Rock (or any future flinch source) hit
    /// this participant. Checked at the start of their move and cleared at end of
    /// turn so it never carries across turns.
    var flinched: Bool = false

    /// Number of moves the holder has successfully dispatched since they were
    /// last sent in (initial send-out or switch). Bumped at move-dispatch
    /// time after PP is consumed — both successful and failed/missed moves
    /// count, so first-turn-only moves (Fake Out, First Impression) reject
    /// even when turn 1's attempt missed. Reset to 0 on switch-in.
    var movesUsedSinceSwitchIn: Int = 0

    /// While holding a Choice item (Band/Specs/Scarf), the holder is locked into
    /// the first move they successfully execute until they switch out. The index
    /// is into `moves`; switching clears it via `resetVolatile()`.
    var choiceLockedMoveIndex: Int? = nil

    /// Confusion volatile. `confusionTurnsRemaining` counts down at the start of
    /// the holder's move; while > 0, the holder has a 33% chance to hurt itself
    /// for a typeless 40 BP physical hit instead of attacking. Cleared on switch.
    var confused: Bool = false
    var confusionTurnsRemaining: Int = 0

    /// Taunt volatile. While > 0, the holder cannot select a status move; the
    /// engine logs a refusal and the action fizzles. Cleared on switch.
    var tauntTurnsRemaining: Int = 0

    /// Perish Song timer. Set to 3 by Perish Song; ticks down once per end of
    /// turn while the holder is on the field. Faints the holder the turn it
    /// reaches 0. Cleared on switch — switching is the canon escape from
    /// Perish Song.
    var perishCounter: Int = 0

    /// True for the turn the holder successfully used a Protect-family move.
    /// The next incoming move is blocked. Cleared at end-of-turn.
    var protectedThisTurn: Bool = false
    /// Counts back-to-back successful Protect uses. Each consecutive turn the
    /// success chance halves (100, 50, 25, …). Reset to 0 whenever the holder
    /// takes any non-protect action OR a protect attempt fails its roll.
    var consecutiveProtectCount: Int = 0
    /// Normalized name of the protect-family move the holder used this turn.
    /// Read by the contact-penalty path to fire the right side effect (poison
    /// for Baneful Bunker, burn for Burning Bulwark, etc.). Cleared at EOT.
    var lastProtectKey: String? = nil

    /// Mimikyu's Disguise busts after the first damaging hit lands. While true
    /// (the default for Mimikyu), the next damaging hit is reduced to a sliver
    /// of chip and the disguise flips to false (form change is cosmetic).
    var disguiseIntact: Bool = false
    /// Eiscue's Ice Face. Like Disguise but only blocks the first *physical*
    /// hit, and is restored when snow/hail weather starts. Flag is reset on
    /// switch (the holder remembers their Ice form across turns but a fresh
    /// entry presents Ice Face again).
    var iceFaceIntact: Bool = false
    /// True if the holder is currently grounded by Smack Down / Thousand Arrows
    /// or while Gravity is active. Levitate / Flying typing is overridden when
    /// this is true.
    var grounded: Bool = false
    /// Set by Salt Cure on hit. While true the holder takes 1/8 max HP per
    /// end-of-turn (1/4 if it's Water or Steel type). Cleared on switch.
    var saltCured: Bool = false

    // MARK: Tier 3 volatiles

    /// Index of the last move the holder successfully executed. Used by Encore
    /// to lock the target, by Disable to block a specific move, and by Mirror
    /// Move / Mimic if those ever ship. Reset on switch.
    var lastMoveIndex: Int? = nil

    /// Yawn — places a 1-turn countdown that puts the holder to sleep at the
    /// END of the next turn (canon: the turn after Yawn lands). Decremented
    /// in `endOfTurnEffects` and inflicts sleep when it reaches 0.
    var yawnCounter: Int = 0
    /// Leech Seed — drains 1/8 maxHP per EOT from the holder; the drained HP
    /// goes to whoever seeded them. `(sideIdx, slotIdx)` of the seeder so the
    /// transfer survives swaps on the seeder side.
    var leechSeededBy: (side: Int, slot: Int)? = nil
    /// Endure — capped HP loss at 1 for this turn (engage with Reversal /
    /// Flail combos). Cleared at end-of-turn.
    var endureThisTurn: Bool = false
    /// Encore — locks the holder into their `lastMoveIndex` for the next 3
    /// turns. Ticks down in `endOfTurnEffects`; on expiry the lock clears.
    var encoreTurns: Int = 0
    var encoreLockedIndex: Int? = nil
    /// Disable — blocks a specific move index for 4 turns. The holder can
    /// still pick other moves; Tier 3 only enforces if the selected move
    /// equals `disabledMoveIndex` at pre-move time.
    var disableTurns: Int = 0
    var disabledMoveIndex: Int? = nil
    /// Destiny Bond — if the holder faints to an attacker's hit before the
    /// next time the holder moves, the attacker is also KO'd. Set when the
    /// holder uses Destiny Bond; cleared the next time the holder acts.
    var destinyBondActive: Bool = false
    /// Substitute HP. > 0 means a substitute is up; incoming damage hits the
    /// sub first, status effects and stat drops are blocked. Cleared on switch.
    var subHP: Int = 0
    /// Roost — temporary Flying-type strip for the turn the holder uses Roost.
    /// While true, the holder's Flying typing doesn't apply (used by Ground-
    /// type immunity checks). Cleared at EOT.
    var roostedThisTurn: Bool = false
    /// Berserk one-shot flag — set when the holder's HP first drops to ≤ 50%
    /// from a damaging hit, after which the +1 SpA fires. Cleared on switch.
    var berserkFired: Bool = false

    // MARK: Tier 5 volatiles

    /// Bind/Wrap/Fire Spin/Sand Tomb/Whirlpool/Infestation/Snap Trap. While
    /// `> 0` the holder can't switch out (only force-switch moves work) and
    /// takes 1/8 maxHP at end-of-turn. Counter ticks down at EOT. Cleared on
    /// successful switch (force-switch only).
    var trapTurnsRemaining: Int = 0
    var trapMoveName: String? = nil

    /// Damage taken this turn for Counter / Mirror Coat. Tracked per category
    /// because Counter returns physical only, Mirror Coat returns special only.
    /// Cleared at the start of the holder's own action and at EOT.
    var lastPhysicalDamageThisTurn: Int = 0
    var lastSpecialDamageThisTurn: Int = 0

    // MARK: Tier 6 volatiles / persistent flags

    /// Cute Charm infatuation. While true, the holder has a 50% chance to
    /// fizzle each turn (canon is gender-aware; Tier 6 skips the gender check).
    /// Cleared on switch.
    var infatuated: Bool = false
    /// Battle Bond — set after the holder KOs an opposing Pokemon (Gen 9
    /// version: +1 SpA on KO). Tracked so the boost only happens once per
    /// switch-in cycle.
    var battleBondTriggered: Bool = false
    /// Zero to Hero / Palafin — the moment the holder switches out for the
    /// first time, this flag flips on and stays on for the rest of the battle.
    /// While true the engine treats the holder as the Hero form (higher stats
    /// + display tag). Survives switches because the canon transform persists.
    var palafinHeroActive: Bool = false
    /// Imposter — set when the holder copied an opponent on entry. While true
    /// the engine pulls stat / move / type / ability data from the snapshot.
    /// Cleared on switch (the copy doesn't persist).
    var imposterSnapshot: ImposterSnapshot? = nil

    /// Charge state for two-turn moves (Solar Beam / Sky Attack / Meteor Beam
    /// / Electro Shot / Skull Bash / Geomancy). When set, the holder is on
    /// their charge turn — their next action releases the move regardless of
    /// what was queued. Cleared after release or on switch. The KEY pins the
    /// canonical move (so swap-attack tricks don't release a different move);
    /// the INDEX is what gets executed.
    var chargedMoveKey: String? = nil
    var chargedMoveIndex: Int? = nil

    /// Snapshot of the copied opponent used by Imposter (and by Transform if
    /// that ever ships). HP isn't copied — only stats / types / ability /
    /// move slot names. Stat stages start at 0 and accumulate normally.
    struct ImposterSnapshot {
        let displayName: String
        let type1: String
        let type2: String?
        let baseAtk: Int
        let baseDef: Int
        let baseSpAtk: Int
        let baseSpDef: Int
        let baseSpeed: Int
        let ability: String?
    }

    init(slot: TeamSlotInfo, allPokemon: [PKMNStats], allMoves: [MoveData]) {
        self.slot = slot
        self.stats = allPokemon.first(where: { $0.id == slot.pokemonID })
        self.moves = slot.moveSlots.compactMap { tm in allMoves.first(where: { $0.id == tm.moveID }) }
        self.pp = self.moves.map { $0.pp }
        self.nature = allNatures.first(where: { $0.id == slot.natureID }) ?? allNatures[0]
        self.heldItem = slot.itemRawValue.flatMap { HeldItem(rawValue: $0) } ?? .none

        let base = self.stats?.baseHP ?? 1
        let evHP = slot.championsMode ? championsEVToMain(slot.evHP) : slot.evHP
        let hp = calcHP(base: base, iv: 31, ev: evHP, level: slot.level)
        self.maxHP = hp
        self.currentHP = hp

        // Aegislash always starts in Shield Forme regardless of which form's stat
        // block the team picker saved. Stance Change flips it to Blade the first
        // time it uses a damaging move.
        if slot.abilityName == "stance-change" {
            self.stanceForm = .aegislashShield
        }
        // Mimikyu / Mimikyu-Disguised enters with its Disguise intact. The first
        // damaging hit chips it off (handled in `applyDamageHit`).
        if slot.abilityName == "disguise" {
            self.disguiseIntact = true
        }
        // Eiscue presents Ice Face on entry — first physical hit gets blocked.
        if slot.abilityName == "ice-face" {
            self.iceFaceIntact = true
        }
    }

    var fainted: Bool { currentHP <= 0 }
    var atFullHP: Bool { currentHP >= maxHP }

    // Display + active accessors — swap to the Mega form's values once evolved.
    // Stance form is consulted after Mega so a hypothetical Mega Aegislash would
    // still win; the current canon has no such conflict but the ordering keeps
    // the priority predictable.
    //
    // Imposter snapshot wins over everything (a transformed Ditto is supposed
    // to behave like its target). Palafin Hero form wins over the base when
    // the persistent flag is set.
    var displayName: String {
        if let s = imposterSnapshot { return s.displayName }
        if palafinHeroActive { return "Palafin-Hero" }
        return megaForm?.displayName ?? stanceForm?.displayName ?? slot.pokemonName
    }
    var activeType1: String {
        imposterSnapshot?.type1 ?? megaForm?.type1 ?? slot.type1
    }
    var activeType2: String? {
        if let s = imposterSnapshot { return s.type2 }
        return megaForm?.type2 ?? slot.type2
    }
    /// Active ability resolution priority: Imposter copy > Mega form > Trace
    /// copy > slot. Trace only fires on entry and the copied ID lives in
    /// `tracedAbility` until the holder switches out (when `resetVolatile`
    /// clears it). A Mega still wins — the new form's ability supersedes any
    /// Trace. An Imposter wins above all (it stole everything).
    var activeAbility: String? {
        imposterSnapshot?.ability ?? megaForm?.ability ?? tracedAbility ?? slot.abilityName
    }
    /// Set by Trace when the holder enters; cleared on switch.
    var tracedAbility: String? = nil

    var types: [String] {
        var t = [activeType1]
        if let t2 = activeType2 { t.append(t2) }
        // Roost — while the holder roosted this turn, their Flying typing is
        // suppressed. Mono-Flying becomes typeless; dual types lose just the
        // Flying entry.
        if roostedThisTurn {
            t.removeAll { $0 == "Flying" }
        }
        return t
    }

    var baseAtk: Int {
        if let s = imposterSnapshot { return s.baseAtk }
        let raw = megaForm?.baseAtk ?? stanceForm?.baseAtk ?? stats?.baseAtk ?? 1
        return palafinHeroActive ? raw + 60 : raw
    }
    var baseDef: Int {
        imposterSnapshot?.baseDef ?? megaForm?.baseDef ?? stanceForm?.baseDef ?? stats?.baseDef ?? 1
    }
    var baseSpAtk: Int {
        imposterSnapshot?.baseSpAtk ?? megaForm?.baseSpAtk ?? stanceForm?.baseSpAtk ?? stats?.baseSpAtk ?? 1
    }
    var baseSpDef: Int {
        imposterSnapshot?.baseSpDef ?? megaForm?.baseSpDef ?? stanceForm?.baseSpDef ?? stats?.baseSpDef ?? 1
    }
    var baseSpeed: Int {
        if let s = imposterSnapshot { return s.baseSpeed }
        let raw = megaForm?.baseSpeed ?? stanceForm?.baseSpeed ?? stats?.baseSpeed ?? 1
        // Zero to Hero (Palafin) — the Hero form is significantly faster.
        return palafinHeroActive ? raw + 60 : raw
    }

    var speed: Int {
        let ev = slot.championsMode ? championsEVToMain(slot.evSpeed) : slot.evSpeed
        let raw = calcStat(base: baseSpeed, iv: 31, ev: ev,
                           level: slot.level, natureMod: nature.modifier(for: .speed))
        var v = Int(Double(raw) * statStageMultiplier(stage: speedStage))
        if status == .paralysis { v /= 2 }
        if effectiveHeldItem == .choiceScarf { v = Int(Double(v) * 1.5) }
        // Unburden — doubles speed once the holder's item is gone via consumption
        // (berries, Focus Sash, Mental/White Herb) or Knock Off. Mega Evolution does
        // NOT trigger Unburden in canon: the stone isn't considered "lost" since
        // it's intrinsic to the transformation. The ability check uses `activeAbility`
        // so a Mega's replacement ability (no longer "unburden") correctly suppresses
        // the boost post-evolution.
        if activeAbility == "unburden", megaForm == nil, (consumedItem || knockedOff) {
            v *= 2
        }
        return v
    }

    /// Volatile state that doesn't survive a switch. Status and mega state persist;
    /// the toxic counter resets and stat stages clear. Stance Change resets to
    /// Shield Forme since the form is shed when Aegislash leaves the field.
    /// Disguise refreshes if the holder still has the ability — leaving the field
    /// resets Mimikyu's form (the engine treats this as the canon "Disguise
    /// regenerates on switch" houserule, since the in-game truth — single-use
    /// per battle — is annoying when the user wants to practice combos).
    func resetVolatile() {
        atkStage = 0; defStage = 0; spAtkStage = 0; spDefStage = 0; speedStage = 0
        toxicCounter = 0
        choiceLockedMoveIndex = nil
        movesUsedSinceSwitchIn = 0
        confused = false
        confusionTurnsRemaining = 0
        tauntTurnsRemaining = 0
        perishCounter = 0
        protectedThisTurn = false
        consecutiveProtectCount = 0
        lastProtectKey = nil
        grounded = false
        saltCured = false
        tracedAbility = nil
        // Tier 3 volatiles
        lastMoveIndex = nil
        yawnCounter = 0
        leechSeededBy = nil
        endureThisTurn = false
        encoreTurns = 0
        encoreLockedIndex = nil
        disableTurns = 0
        disabledMoveIndex = nil
        destinyBondActive = false
        subHP = 0
        roostedThisTurn = false
        berserkFired = false
        trapTurnsRemaining = 0
        trapMoveName = nil
        lastPhysicalDamageThisTurn = 0
        lastSpecialDamageThisTurn = 0
        infatuated = false
        battleBondTriggered = false
        imposterSnapshot = nil
        chargedMoveKey = nil
        chargedMoveIndex = nil
        // palafinHeroActive persists by design — the Hero form sticks for the
        // rest of the battle, even across subsequent switches.
        if slot.abilityName == "stance-change" {
            stanceForm = .aegislashShield
        }
        if slot.abilityName == "disguise" {
            disguiseIntact = true
        }
        if slot.abilityName == "ice-face" {
            iceFaceIntact = true
        }
    }

    var hasAnyPP: Bool { pp.contains(where: { $0 > 0 }) }

    /// The held item the damage calc should treat this Pokemon as carrying. Returns
    /// `.none` after Mega Evolution (stone is spent), Knock Off, or one-shot
    /// consumption (Focus Sash, berries, etc.).
    var effectiveHeldItem: HeldItem {
        if megaForm != nil { return .none }
        if knockedOff || consumedItem { return .none }
        return heldItem
    }

    /// Move names that show up in this participant's move slots — used by Rayquaza's
    /// Mega Evolution eligibility check (needs Dragon Ascent).
    var moveNames: [String] { moves.map { $0.name } }

    /// True when the move at `moveIndex` is a first-turn-only move (Fake Out
    /// / First Impression) AND the holder has already dispatched at least one
    /// move since switching in. Both the UI (to gray out the button so the
    /// user can't click an illegal move) and the engine (to redirect Encore-
    /// locked attempts to Struggle) consult this predicate, so the contract
    /// stays in one place.
    func isFirstTurnOnlyMoveLockedOut(at moveIndex: Int) -> Bool {
        guard moves.indices.contains(moveIndex) else { return false }
        let key = BattleSimSeed.normalize(moves[moveIndex].name)
        return BattleMoveEffects.firstTurnOnlyMoves.contains(key)
            && movesUsedSinceSwitchIn > 0
    }
}

// MARK: - Side

@Observable
final class BattleSide: Identifiable {
    let id = UUID()
    let label: String
    var participants: [BattleParticipant]
    var activeIndices: [Int]

    // Hazards on this side's field — affect Pokemon switching IN on this side.
    var stealthRock: Bool = false
    var spikesLayers: Int = 0
    var stickyWeb: Bool = false
    var toxicSpikesLayers: Int = 0

    /// Screen counters. Each is the number of turns remaining (>0 means active).
    /// Decrement at end-of-turn. Aurora Veil only sticks if hail/snow is active
    /// when it's used — but once up it functions even if weather drops.
    var lightScreenTurns: Int = 0
    var reflectTurns: Int = 0
    var auroraVeilTurns: Int = 0
    /// Tailwind doubles the effective Speed of every active Pokemon on this side.
    var tailwindTurns: Int = 0
    /// Safeguard blocks new major status conditions and confusion from being
    /// inflicted on this side's active Pokemon. Doesn't cure existing status.
    var safeguardTurns: Int = 0

    /// Set on the attacker's side for one turn by Helping Hand. While true the
    /// damage calc applies a 1.5x final multiplier to the partner's move.
    var helpingHandPending: [Bool] = []
    /// Set when a side-mate used Follow Me / Rage Powder this turn. Other side's
    /// targetable moves get redirected to this slot. Reset at end-of-turn.
    var redirectionTargetSlot: Int? = nil
    /// Wide Guard blocks incoming spread/multi-target moves for one turn.
    /// Quick Guard blocks incoming priority moves for one turn. Reset at EOT.
    var wideGuardActive: Bool = false
    var quickGuardActive: Bool = false

    /// Pending Wish heals. Each entry counts down at EOT; when it hits zero,
    /// whichever Pokemon currently occupies `slot` gets healed for `amount`.
    /// Set by Wish, popped in `endOfTurnEffects`.
    struct PendingWish: Equatable {
        var slot: Int
        var turnsRemaining: Int   // 1 = lands at the end of THIS turn (next EOT)
        var amount: Int
    }
    var wishQueue: [PendingWish] = []

    /// Per-slot Healing Wish / Lunar Dance pending flags. Set when the user
    /// faints to those moves. When the next switch-in lands on that slot, they
    /// get full HP, full status, and the flag clears.
    var healingWishPending: [Bool] = []

    /// Each side may Mega Evolve only one Pokemon per battle.
    var hasUsedMega: Bool = false

    init(label: String, slots: [TeamSlotInfo], format: BattleFormat,
         allPokemon: [PKMNStats], allMoves: [MoveData]) {
        self.label = label
        let parts = slots.map { BattleParticipant(slot: $0, allPokemon: allPokemon, allMoves: allMoves) }
        self.participants = parts
        self.activeIndices = Array(0..<min(format.activeSlots, parts.count))
        self.helpingHandPending = Array(repeating: false, count: format.activeSlots)
        self.healingWishPending = Array(repeating: false, count: format.activeSlots)
    }

    var hasUnfainted: Bool { participants.contains(where: { !$0.fainted }) }

    func active(at slot: Int) -> BattleParticipant? {
        guard slot < activeIndices.count else { return nil }
        let i = activeIndices[slot]
        return participants.indices.contains(i) ? participants[i] : nil
    }

    func benchIndices() -> [Int] {
        participants.indices.filter { !activeIndices.contains($0) && !participants[$0].fainted }
    }

    var hazardSummary: String {
        var parts: [String] = []
        if stealthRock { parts.append("SR") }
        if spikesLayers > 0 { parts.append("Spikes×\(spikesLayers)") }
        if toxicSpikesLayers > 0 { parts.append("T-Spikes×\(toxicSpikesLayers)") }
        if stickyWeb { parts.append("Web") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Action

enum BattleAction {
    case move(moveIndex: Int, targetSide: Int, targetSlot: Int)
    case spreadMove(moveIndex: Int)
    case switchTo(benchIndex: Int)
    case struggle(targetSide: Int, targetSlot: Int)
}

private struct PlannedAction {
    let sideIndex: Int
    let actorSlot: Int
    let action: BattleAction
    var key: ActorKey { ActorKey(side: sideIndex, slot: actorSlot) }
}

private struct ActorKey: Hashable {
    let side: Int
    let slot: Int
}

// MARK: - Log

struct BattleLogEntry: Identifiable {
    let id = UUID()
    let text: String
    var emphasis: Bool = false
}

// MARK: - Engine

@MainActor
@Observable
final class BattleEngine {
    let format: BattleFormat
    let side1: BattleSide
    let side2: BattleSide
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    /// The Champions regulation's rules for a Champions battle, which
    /// decide whether Mega Evolution is allowed; nil for a free battle.
    let championsRules: ChampionsRules?

    var log: [BattleLogEntry] = []
    var turn: Int = 1
    var winner: Int? = nil
    var pendingActions: [[BattleAction?]]
    var pendingForceSwitches: [ForceSwitch] = []

    var weather: WeatherCondition = .none
    var weatherTurns: Int = 0
    var terrain: TerrainCondition = .none
    var terrainTurns: Int = 0

    /// Global room effects. While `trickRoomTurns > 0`, slower Pokemon move
    /// first within each priority bracket. `wonderRoomTurns` swaps Def↔SpDef
    /// for the duration. `magicRoomTurns` suppresses all held item effects.
    /// `gravityTurns` grounds Flying-types and raises every move's accuracy.
    var trickRoomTurns: Int = 0
    var wonderRoomTurns: Int = 0
    var magicRoomTurns: Int = 0
    var gravityTurns: Int = 0

    /// Pins the engine's damage randomness. nil (the default) is normal play.
    ///
    /// Tests that compare two engine runs need this: every damaging hit rolls
    /// both a crit and a damage value, and at low power the roll alone can
    /// swing damage by 3x, which swamps the effect a ratio test is measuring.
    /// Pinning both makes those comparisons deterministic without loosening
    /// the assertion.
    var rollOverride: RollOverride?

    struct RollOverride {
        enum Roll {
            case min, max
            /// A point in the damage range: 0 is the minimum, 1 the maximum.
            case fraction(Double)
        }
        /// Whether every crit check succeeds.
        var crit: Bool
        /// Which part of each damage range to take. A two-hit solve changes it
        /// between turns to give each hit its own roll.
        var roll: Roll
        /// When true, luck-based events don't happen and accuracy always
        /// hits: secondary effects, full paralysis, confusion self-hits,
        /// infatuation, Quick Claw, Focus Band, King's Rock, contact abilities,
        /// Harvest. Multi-hit counts follow `roll` (min → 2 hits, else 5).
        /// This is the standard damage-calc reading of "guaranteed". Off by
        /// default so existing pinned tests keep their behaviour.
        var suppressChanceEvents: Bool = false
    }

    /// A luck-based event with probability `p`. Never happens when a pinned
    /// run suppresses chance events.
    private func luck(_ p: Double) -> Bool {
        if rollOverride?.suppressChanceEvents == true { return false }
        return Double.random(in: 0..<1) < p
    }

    /// An accuracy roll on the 1...100 scale; always 1 (a hit) when chance
    /// events are suppressed.
    private func accuracyRoll() -> Int {
        rollOverride?.suppressChanceEvents == true ? 1 : Int.random(in: 1...100)
    }

    /// When true for a given [side][slot], that actor will Mega Evolve at the start of
    /// the next executed turn (before any action). Cleared once processed.
    var pendingMega: [[Bool]]

    struct ForceSwitch: Identifiable, Equatable {
        let side: Int
        let slot: Int
        var id: String { "\(side)-\(slot)" }
    }

    init(format: BattleFormat, side1: BattleSide, side2: BattleSide,
         allPokemon: [PKMNStats], allMoves: [MoveData],
         championsRules: ChampionsRules? = nil) {
        self.format = format
        self.side1 = side1
        self.side2 = side2
        self.allPokemon = allPokemon
        self.allMoves = allMoves
        self.championsRules = championsRules
        let slots = format.activeSlots
        self.pendingActions = [Array(repeating: nil, count: slots),
                               Array(repeating: nil, count: slots)]
        self.pendingMega = [Array(repeating: false, count: slots),
                            Array(repeating: false, count: slots)]
        self.log.append(BattleLogEntry(text: "Turn 1 begin", emphasis: true))
        for s in 0..<2 {
            let side = self.side(at: s)
            for slot in 0..<format.activeSlots {
                if let p = side.active(at: slot) {
                    self.log.append(BattleLogEntry(text: "\(side.label) sent out \(p.displayName)!"))
                    self.activateEntryAbility(for: p, ownSide: s)
                }
            }
        }
    }

    func side(at i: Int) -> BattleSide { i == 0 ? side1 : side2 }

    func setAction(side: Int, slot: Int, action: BattleAction) {
        pendingActions[side][slot] = action
    }

    func clearAction(side: Int, slot: Int) {
        pendingActions[side][slot] = nil
        pendingMega[side][slot] = false
    }

    // MARK: Mega Evolution

    /// Returns true if the actor at (side, slot) is eligible to Mega Evolve right now:
    /// their side hasn't used its mega yet, they aren't already mega'd, their
    /// species + held item (or Dragon Ascent, for Rayquaza) maps to a known Mega form,
    /// and a Champions battle's regulation allows it.
    func canMegaEvolve(side sIdx: Int, slot: Int) -> Bool {
        if side(at: sIdx).hasUsedMega { return false }
        guard let actor = side(at: sIdx).active(at: slot), !actor.fainted else { return false }
        if actor.megaForm != nil { return false }
        return allowedMegaForm(for: actor) != nil
    }

    /// The Mega form `actor` can use: the one its item (or Dragon Ascent)
    /// triggers, if the regulation allows it.
    private func allowedMegaForm(for actor: BattleParticipant) -> MegaForm? {
        guard let form = MegaForms.form(forSpecies: actor.slot.pokemonName,
                                        heldItem: actor.heldItem,
                                        moveNames: actor.moveNames) else { return nil }
        if let rules = championsRules, !rules.allowsMega(form) { return nil }
        return form
    }

    func megaBinding(side: Int, slot: Int) -> Binding<Bool> {
        Binding(
            get: { self.pendingMega[side][slot] },
            set: { self.pendingMega[side][slot] = $0 }
        )
    }

    /// Evolves any actors that asked to Mega Evolve this turn, in speed order. Honors
    /// the once-per-side limit even if both slots in doubles toggled it on.
    private func processPendingMegas() {
        struct Candidate { let side: Int; let slot: Int; let speed: Int }
        var candidates: [Candidate] = []
        for s in 0..<2 {
            for slot in 0..<format.activeSlots {
                guard pendingMega[s][slot] else { continue }
                guard canMegaEvolve(side: s, slot: slot) else { continue }
                let speed = side(at: s).active(at: slot)?.speed ?? 0
                candidates.append(Candidate(side: s, slot: slot, speed: speed))
            }
        }
        candidates.sort { $0.speed > $1.speed }

        for c in candidates {
            // The first mega on a side disqualifies any second candidate on the same side.
            if side(at: c.side).hasUsedMega { continue }
            guard let actor = side(at: c.side).active(at: c.slot) else { continue }
            guard let form = allowedMegaForm(for: actor) else { continue }
            actor.megaForm = form
            side(at: c.side).hasUsedMega = true
            log.append(BattleLogEntry(text: "\(actor.slot.pokemonName) Mega Evolved into \(form.displayName)!", emphasis: true))
            // The post-Mega ability is now active and may set weather/terrain/Intimidate.
            activateEntryAbility(for: actor, ownSide: c.side)
        }

        let slots = format.activeSlots
        pendingMega = [Array(repeating: false, count: slots),
                       Array(repeating: false, count: slots)]
    }

    var allActionsChosen: Bool {
        if winner != nil { return false }
        if !pendingForceSwitches.isEmpty { return false }
        for s in 0..<2 {
            for i in 0..<format.activeSlots {
                guard let active = side(at: s).active(at: i) else { continue }
                if active.fainted { continue }
                // A participant with no moves and no bench cannot act at all; skip.
                if active.moves.isEmpty && side(at: s).benchIndices().isEmpty { continue }
                if pendingActions[s][i] == nil { return false }
            }
        }
        return true
    }

    // MARK: Turn Execution

    func executeTurn() {
        // Mega Evolutions resolve before any action this turn.
        processPendingMegas()

        var actions: [PlannedAction] = []
        for s in 0..<2 {
            for i in 0..<format.activeSlots {
                guard let active = side(at: s).active(at: i), !active.fainted else { continue }
                guard let a = pendingActions[s][i] else { continue }
                actions.append(PlannedAction(sideIndex: s, actorSlot: i, action: a))
            }
        }

        // Quick Claw — 20% per turn for the holder to bypass speed (within their
        // priority bracket). Rolled once per move action; cleared automatically by
        // virtue of being local to this turn.
        var quickClawWinners: Set<ActorKey> = []
        for action in actions {
            guard let actor = side(at: action.sideIndex).active(at: action.actorSlot) else { continue }
            if actor.effectiveHeldItem == .quickClaw, luck(0.2) {
                quickClawWinners.insert(action.key)
                log.append(BattleLogEntry(text: "\(actor.displayName)'s Quick Claw activated!"))
            }
        }

        // Pre-roll a stable random tie-breaker per actor. Swift's `sort` can call the
        // comparator multiple times for the same pair, so a `Bool.random()` inside
        // the comparator would violate strict weak ordering and could crash or
        // produce nonsensical sorts. Pre-rolling once gives true speed ties a
        // game-accurate random resolution AND a sound comparator.
        var tieBreaker: [ActorKey: UInt64] = [:]
        for action in actions {
            tieBreaker[action.key] = UInt64.random(in: 0...UInt64.max)
        }

        // Effective speed: Tailwind doubles the side's Speed for 4 turns, paralysis
        // already halves it inside `BattleParticipant.speed`. Trick Room inverts
        // the comparison within each priority bracket.
        func effectiveSpeed(side s: Int, slot: Int) -> Int {
            let raw = side(at: s).active(at: slot)?.speed ?? 0
            return side(at: s).tailwindTurns > 0 ? raw * 2 : raw
        }

        // Switches first, then by move priority (desc), then Quick Claw winners, then
        // speed (desc, or asc under Trick Room), with deterministic per-actor random
        // tie-breaker last.
        actions.sort { a, b in
            let tieA = tieBreaker[a.key] ?? 0
            let tieB = tieBreaker[b.key] ?? 0

            let aIsSwitch = isSwitchAction(a.action)
            let bIsSwitch = isSwitchAction(b.action)
            if aIsSwitch != bIsSwitch { return aIsSwitch }
            if aIsSwitch && bIsSwitch { return tieA > tieB }

            let pa = priority(side: a.sideIndex, slot: a.actorSlot, action: a.action)
            let pb = priority(side: b.sideIndex, slot: b.actorSlot, action: b.action)
            if pa != pb { return pa > pb }

            // Quick Claw winners go first within the same priority bracket.
            let aQC = quickClawWinners.contains(a.key)
            let bQC = quickClawWinners.contains(b.key)
            if aQC != bQC { return aQC }

            let sa = effectiveSpeed(side: a.sideIndex, slot: a.actorSlot)
            let sb = effectiveSpeed(side: b.sideIndex, slot: b.actorSlot)
            if sa != sb {
                return trickRoomTurns > 0 ? sa < sb : sa > sb
            }
            return tieA > tieB
        }

        for action in actions {
            performAction(action)
            checkForKOsAndEnd()
            if winner != nil { break }
        }

        if winner == nil {
            endOfTurnEffects()
            checkForKOsAndEnd()
        }

        let slots = format.activeSlots
        pendingActions = [Array(repeating: nil, count: slots),
                          Array(repeating: nil, count: slots)]

        if winner == nil {
            updateForceSwitchQueue()
            if pendingForceSwitches.isEmpty {
                turn += 1
                log.append(BattleLogEntry(text: "—"))
                log.append(BattleLogEntry(text: "Turn \(turn) begin", emphasis: true))
            }
        }
    }

    private func isSwitchAction(_ a: BattleAction) -> Bool {
        if case .switchTo = a { return true }
        return false
    }

    private func priority(side: Int, slot: Int, action: BattleAction) -> Int {
        guard let actor = self.side(at: side).active(at: slot) else { return 0 }
        switch action {
        case .move(let mi, _, _), .spreadMove(let mi):
            return actor.moves.indices.contains(mi) ? actor.moves[mi].priority : 0
        case .struggle:
            return 0
        case .switchTo:
            return 6
        }
    }

    private func performAction(_ pa: PlannedAction) {
        guard let actor = side(at: pa.sideIndex).active(at: pa.actorSlot), !actor.fainted else { return }
        _ = actor
        switch pa.action {
        case .switchTo(let bench):
            performSwitch(sideIndex: pa.sideIndex, slot: pa.actorSlot, benchIndex: bench)
        case .move(let mi, let ts, let tslot):
            performMove(attackerSide: pa.sideIndex, attackerSlot: pa.actorSlot,
                        moveIndex: mi, defenderSide: ts, defenderSlot: tslot)
        case .spreadMove(let mi):
            performSpreadMove(attackerSide: pa.sideIndex, attackerSlot: pa.actorSlot, moveIndex: mi)
        case .struggle(let ts, let tslot):
            performStruggle(attackerSide: pa.sideIndex, attackerSlot: pa.actorSlot,
                            defenderSide: ts, defenderSlot: tslot)
        }
    }

    // MARK: Switches & Hazards

    private func performSwitch(sideIndex i: Int, slot: Int, benchIndex: Int) {
        let s = side(at: i)
        guard benchIndex < s.participants.count,
              !s.participants[benchIndex].fainted,
              !s.activeIndices.contains(benchIndex) else { return }
        let outgoing = s.active(at: slot)
        // Regenerator — heal 1/3 max HP on the way out, before volatile reset.
        // Suppressed if the holder is at full HP, fainted, or has consumed its
        // healing this turn through other means; Tier 1 just checks fainted +
        // already-full.
        if let out = outgoing, !out.fainted,
           out.activeAbility == "regenerator",
           out.currentHP < out.maxHP {
            let heal = max(1, out.maxHP / 3)
            out.currentHP = min(out.maxHP, out.currentHP + heal)
            log.append(BattleLogEntry(text: "\(out.displayName)'s Regenerator restored some HP."))
        }
        // Zero to Hero (Palafin) — first switch-out flips the persistent Hero
        // flag. The boost is then live the next time it walks in.
        if let out = outgoing, !out.fainted,
           out.activeAbility == "zero-to-hero", !out.palafinHeroActive {
            out.palafinHeroActive = true
            log.append(BattleLogEntry(text: "\(out.displayName) is ready to transform into its Hero form!"))
        }
        outgoing?.resetVolatile()
        s.activeIndices[slot] = benchIndex
        let incoming = s.participants[benchIndex]
        // Reset the first-turn-only counter on the way in. `resetVolatile`
        // already does this for the outgoing side, but the explicit set
        // covers force-switch paths where the outgoing was bypassed.
        incoming.movesUsedSinceSwitchIn = 0
        if let outName = outgoing?.displayName {
            log.append(BattleLogEntry(text: "\(s.label) withdrew \(outName)."))
        }
        log.append(BattleLogEntry(text: "\(s.label) sent out \(incoming.displayName)!"))
        applyHazardsOnSwitchIn(p: incoming, side: s)
        // Healing Wish / Lunar Dance — if the slot has a pending heal, restore
        // the incoming mon to full HP + clear status, then clear the flag.
        if slot < s.healingWishPending.count, s.healingWishPending[slot] {
            s.healingWishPending[slot] = false
            if !incoming.fainted {
                incoming.currentHP = incoming.maxHP
                incoming.status = .none
                incoming.toxicCounter = 0
                incoming.sleepTurnsRemaining = 0
                log.append(BattleLogEntry(text: "\(incoming.displayName) was healed by Healing Wish!"))
            }
        }
        if !incoming.fainted { activateEntryAbility(for: incoming, ownSide: i) }
    }

    func forceSwitch(side: Int, slot: Int, benchIndex: Int) {
        let s = self.side(at: side)
        guard benchIndex < s.participants.count,
              !s.participants[benchIndex].fainted,
              !s.activeIndices.contains(benchIndex) else { return }
        s.activeIndices[slot] = benchIndex
        let p = s.participants[benchIndex]
        // Force-switch paths skip the outgoing `resetVolatile`, so reset the
        // first-turn-only counter on the incoming side directly.
        p.movesUsedSinceSwitchIn = 0
        log.append(BattleLogEntry(text: "\(s.label) sent out \(p.displayName)!"))
        applyHazardsOnSwitchIn(p: p, side: s)
        // Healing Wish / Lunar Dance landing on the replacement.
        if slot < s.healingWishPending.count, s.healingWishPending[slot] {
            s.healingWishPending[slot] = false
            if !p.fainted {
                p.currentHP = p.maxHP
                p.status = .none
                p.toxicCounter = 0
                p.sleepTurnsRemaining = 0
                log.append(BattleLogEntry(text: "\(p.displayName) was healed by Healing Wish!"))
            }
        }
        if !p.fainted { activateEntryAbility(for: p, ownSide: side) }
        pendingForceSwitches.removeAll { $0.side == side && $0.slot == slot }
        checkForKOsAndEnd()
        if pendingForceSwitches.isEmpty && winner == nil {
            turn += 1
            log.append(BattleLogEntry(text: "—"))
            log.append(BattleLogEntry(text: "Turn \(turn) begin", emphasis: true))
        }
    }

    /// Stealth Rock entry damage: maxHP x effectiveness / 8, rounded down,
    /// at least 1. Matches Pokemon Showdown's `damage(maxhp * 2^typeMod / 8)`,
    /// whose `damage()` floors and clamps to 1. (This used to round to
    /// nearest, which was off by one for many HP values.)
    static func stealthRockDamage(maxHP: Int, effectiveness: Double) -> Int {
        guard effectiveness > 0 else { return 0 }
        return max(1, Int((Double(maxHP) * effectiveness / 8).rounded(.down)))
    }

    /// Spikes entry damage for 1 / 2 / 3 layers: 1/8, 1/6, 1/4 of max HP,
    /// rounded down, at least 1. Showdown: `[0, 3, 4, 6][layers] * maxhp / 24`.
    static func spikesDamage(maxHP: Int, layers: Int) -> Int {
        let amounts = [0, 3, 4, 6]
        let n = amounts[max(0, min(3, layers))]
        guard n > 0 else { return 0 }
        return max(1, n * maxHP / 24)
    }

    /// Whether `move` goes through the spread path for `attacker`: a spread
    /// move in doubles, or Expanding Force in Psychic Terrain with a grounded
    /// user. Both move paths use this, so a redirect (Encore, a charged move)
    /// lands on the right path and they can't hand a move back and forth.
    private func usesSpreadPath(_ move: MoveData, attacker: BattleParticipant) -> Bool {
        guard format == .doubles, move.damageClass != "status" else { return false }
        if SpreadMoves.isSpread(move.name) { return true }
        return BattleSimSeed.normalize(move.name) == "expandingforce"
            && terrain == .psychic && isGrounded(attacker)
    }

    /// Whether `p` is on the ground: always under Gravity or after Smack Down,
    /// otherwise not if it's Flying-type or floats (Levitate, Eelevate). Air
    /// Balloon and Iron Ball aren't modelled.
    func isGrounded(_ p: BattleParticipant) -> Bool {
        if gravityTurns > 0 || p.grounded { return true }
        let floats = p.activeAbility == "levitate" || p.activeAbility == "eelevate"
        return !p.types.contains("Flying") && !floats
    }

    private func applyHazardsOnSwitchIn(p: BattleParticipant, side: BattleSide) {
        // Hazards only affect grounded Pokemon. Flying-types and ability
        // holders that float (Levitate, Pokemon Champions' Eelevate) skip
        // Spikes / Sticky Web / Toxic Spikes. Stealth Rock is type-based,
        // not ground-based, and is handled separately below.
        let grounded = isGrounded(p)
        let magicGuard = p.activeAbility == "magic-guard"

        if side.stealthRock, !magicGuard {
            let rockEff = computeTypeEffectiveness(moveType: "Rock", defenderTypes: p.types)
            let dmg = Self.stealthRockDamage(maxHP: p.maxHP, effectiveness: rockEff)
            if dmg > 0 {
                p.currentHP = max(0, p.currentHP - dmg)
                log.append(BattleLogEntry(text: "\(p.displayName) is hurt by Stealth Rock! (-\(dmg) HP)"))
            }
        }
        if side.spikesLayers > 0 && grounded && !magicGuard {
            let dmg = Self.spikesDamage(maxHP: p.maxHP, layers: side.spikesLayers)
            p.currentHP = max(0, p.currentHP - dmg)
            log.append(BattleLogEntry(text: "\(p.displayName) is hurt by Spikes! (-\(dmg) HP)"))
        }
        if side.stickyWeb && grounded {
            p.speedStage = max(-6, p.speedStage - 1)
            log.append(BattleLogEntry(text: "\(p.displayName) was caught in Sticky Web! Speed fell."))
        }
        // Toxic Spikes: 1 layer = poison, 2 layers = badly-poisoned. Poison-type
        // mons that walk in absorb every layer (remove from field). Steel and
        // Flying are immune. Other immunities (already-statused, abilities) fall
        // through `tryInflictStatus` so this stays consistent.
        if side.toxicSpikesLayers > 0 && grounded {
            if p.types.contains("Poison") {
                side.toxicSpikesLayers = 0
                log.append(BattleLogEntry(text: "\(p.displayName) absorbed the Toxic Spikes!"))
            } else if !p.types.contains("Steel") && p.status == .none {
                let s: BattleStatus = side.toxicSpikesLayers >= 2 ? .toxic : .poison
                tryInflictStatus(s, on: p)
            }
        }
        if p.fainted {
            log.append(BattleLogEntry(text: "\(p.displayName) fainted!", emphasis: true))
        }
    }

    // MARK: Move Execution

    private func preMoveStatusCheck(_ p: BattleParticipant) -> Bool {
        if p.flinched {
            log.append(BattleLogEntry(text: "\(p.displayName) flinched and couldn't move!"))
            return false
        }
        if p.status == .sleep {
            p.sleepTurnsRemaining -= 1
            if p.sleepTurnsRemaining <= 0 {
                p.status = .none
                log.append(BattleLogEntry(text: "\(p.displayName) woke up!"))
            } else {
                log.append(BattleLogEntry(text: "\(p.displayName) is fast asleep."))
                return false
            }
        }
        if p.status == .freeze {
            // 20% thaw-and-act each turn.
            if luck(0.2) {
                p.status = .none
                log.append(BattleLogEntry(text: "\(p.displayName) thawed out!"))
            } else {
                log.append(BattleLogEntry(text: "\(p.displayName) is frozen solid!"))
                return false
            }
        }
        if p.status == .paralysis && luck(0.25) {
            log.append(BattleLogEntry(text: "\(p.displayName) is fully paralyzed! It can't move!"))
            return false
        }
        if p.infatuated {
            // 50% chance to fizzle the move ("immobilized by love"). No turn
            // counter — infatuation lasts until the holder switches.
            if luck(0.5) {
                log.append(BattleLogEntry(text: "\(p.displayName) is immobilized by love!"))
                return false
            }
        }
        if p.confused {
            // Confusion lasts 1-4 turns and ticks down at the start of every move.
            p.confusionTurnsRemaining -= 1
            if p.confusionTurnsRemaining <= 0 {
                p.confused = false
                log.append(BattleLogEntry(text: "\(p.displayName) snapped out of confusion!"))
            } else {
                log.append(BattleLogEntry(text: "\(p.displayName) is confused!"))
                if luck(1.0 / 3.0) {
                    let dmg = confusionSelfDamage(p)
                    p.currentHP = max(0, p.currentHP - dmg)
                    log.append(BattleLogEntry(text: "\(p.displayName) hurt itself in its confusion! (-\(dmg) HP)"))
                    if p.fainted {
                        log.append(BattleLogEntry(text: "\(p.displayName) fainted!", emphasis: true))
                    }
                    return false
                }
            }
        }
        return true
    }

    /// Typeless 40 BP physical self-hit damage used by confusion. Mirrors the
    /// damage formula used by Struggle (no STAB, no type effect, no abilities).
    private func confusionSelfDamage(_ p: BattleParticipant) -> Int {
        let proxyA = CalcSide(); configure(side: proxyA, from: p, withMove: nil)
        let proxyD = CalcSide(); configure(side: proxyD, from: p, withMove: nil)
        let burn = p.status == .burn ? 0.5 : 1.0
        let raw = calcDamageRange(
            level: p.slot.level, movePower: 40,
            userAtk: proxyA.atk, defenderDef: proxyD.def,
            multi: false, weatherMult: 1.0, glaiveRush: false,
            crit: false, critMultiplier: 1.5,
            stabBonus: 1.0, typeEffect: 1.0,
            burnReduction: burn, abilityMods: AbilityModResult(),
            zMoveBypass: false
        )
        let dMin = Int(raw.min)
        let dMax = max(Int(raw.max), dMin)
        return rollDamage(dMin, dMax)
    }

    /// Effective accuracy the move needs to clear against this target. Compound
    /// Eyes on the attacker boosts accuracy 1.3x; Bright Powder on the defender
    /// shaves 10% off. The composed value isn't capped at 100 — the engine's
    /// roll is `Int.random(in: 1...100)`, so anything > 100 always hits, which
    /// matches the canon behavior of Compound Eyes turning a 95-acc move into
    /// effectively-perfect.
    ///
    /// Internal rather than private so tests can check the arithmetic exactly
    /// instead of inferring it from sampled hit rates.
    func effectiveAccuracy(_ move: MoveData,
                                   attacker: BattleParticipant?,
                                   against defender: BattleParticipant?) -> Int? {
        guard let acc = move.accuracy else { return nil }
        var effective = Double(acc)
        if attacker?.activeAbility == "compound-eyes" {
            effective *= 1.3
        }
        if defender?.effectiveHeldItem == .brightPowder {
            effective *= 0.9
        }
        return Int(effective)
    }

    private func firstLiveDefender(in side: BattleSide) -> BattleParticipant? {
        (0..<format.activeSlots).compactMap { side.active(at: $0) }
            .first(where: { !$0.fainted })
    }

    /// True if the participant currently holds a Choice item and is therefore
    /// move-locked once they pick a move. Reads `effectiveHeldItem` so a knocked-off
    /// or consumed item correctly frees the holder.
    func isChoiceLocked(_ p: BattleParticipant) -> Bool {
        switch p.effectiveHeldItem {
        case .choiceBand, .choiceSpecs, .choiceScarf: return true
        default: return false
        }
    }

    /// Perish Song — every active Pokemon on the field (both sides) gets a
    /// 3-turn faint countdown. Soundproof on a participant blocks the effect on
    /// just that participant. Re-application during an existing countdown is a
    /// no-op (canon: doesn't reset the timer).
    private func applyPerishSong() {
        log.append(BattleLogEntry(text: "All Pokemon hearing the song will faint in 3 turns!"))
        for s in 0..<2 {
            for slot in 0..<format.activeSlots {
                guard let p = side(at: s).active(at: slot), !p.fainted else { continue }
                if p.activeAbility == "soundproof" {
                    log.append(BattleLogEntry(text: "\(p.displayName)'s Soundproof blocks Perish Song!"))
                    continue
                }
                if p.perishCounter == 0 {
                    p.perishCounter = 3
                }
            }
        }
    }

    /// Aegislash's Stance Change ability. Damaging moves flip Shield→Blade, King's
    /// Shield flips Blade→Shield. The flip resolves before the move's damage roll
    /// so the post-flip stats drive the calculation. No-op for any other ability.
    private func maybeApplyStanceChange(for p: BattleParticipant, move: MoveData) {
        guard p.activeAbility == "stance-change" else { return }
        let isKingsShield = BattleSimSeed.normalize(move.name) == "kingsshield"
        if move.damageClass != "status" {
            // Any damaging move flips Shield → Blade.
            if p.stanceForm == .aegislashShield {
                p.stanceForm = .aegislashBlade
                log.append(BattleLogEntry(text: "\(p.slot.pokemonName) changed to Blade Forme!"))
            }
        } else if isKingsShield {
            if p.stanceForm == .aegislashBlade {
                p.stanceForm = .aegislashShield
                log.append(BattleLogEntry(text: "\(p.slot.pokemonName) changed to Shield Forme!"))
            }
        }
    }

    private func performMove(attackerSide: Int, attackerSlot: Int,
                             moveIndex: Int, defenderSide: Int, defenderSlot: Int) {
        let aSide = side(at: attackerSide)
        let dSide = side(at: defenderSide)
        guard let attacker = aSide.active(at: attackerSlot), !attacker.fainted else { return }
        guard moveIndex < attacker.moves.count else { return }

        // Choice item lock — if the holder is locked into a different move index,
        // redirect to the locked one as a defensive fallback. The UI already
        // disables the other buttons, but engine-level enforcement keeps things
        // sound if an action was queued before the lock was set.
        var resolvedMoveIndex = moveIndex
        if isChoiceLocked(attacker),
           let locked = attacker.choiceLockedMoveIndex,
           locked != moveIndex, attacker.moves.indices.contains(locked) {
            resolvedMoveIndex = locked
        }
        var move = attacker.moves[resolvedMoveIndex]

        // Expanding Force hits both foes in Psychic Terrain when the user is
        // grounded. Decided here, when the move is used, because terrain can
        // change earlier in the turn. The Showdown port applies its 1.5x
        // boost; the spread path applies 0.75x when two foes remain.
        if usesSpreadPath(move, attacker: attacker),
           BattleSimSeed.normalize(move.name) == "expandingforce" {
            performSpreadMove(attackerSide: attackerSide, attackerSlot: attackerSlot,
                              moveIndex: moveIndex)
            return
        }

        // A Fire-type move thaws the frozen user before the status check resolves.
        if attacker.status == .freeze && move.type == "Fire" {
            attacker.status = .none
            log.append(BattleLogEntry(text: "\(attacker.displayName) thawed out by its move!"))
        }

        // Taunt — status moves fizzle while taunted (canon: 3 turns). Damaging moves
        // are unaffected.
        if attacker.tauntTurnsRemaining > 0 && move.damageClass == "status" {
            log.append(BattleLogEntry(text: "\(attacker.displayName) can't use \(move.name) after the taunt!"))
            return
        }

        // Disable — block the specific move index that was disabled by the last
        // Disable use. Holder can still pick other moves; only the disabled one
        // fizzles. UI ideally enforces this; engine-level check covers stale
        // queued actions.
        if attacker.disableTurns > 0, attacker.disabledMoveIndex == resolvedMoveIndex {
            log.append(BattleLogEntry(text: "\(attacker.displayName)'s \(move.name) is disabled!"))
            return
        }
        // Encore — force the holder into their previously-locked move index.
        // If the locked move is no longer available (out of PP, gone), Encore
        // silently falls through and the engine continues with the queued one.
        if attacker.encoreTurns > 0,
           let locked = attacker.encoreLockedIndex,
           locked != resolvedMoveIndex,
           attacker.moves.indices.contains(locked),
           attacker.pp.indices.contains(locked),
           attacker.pp[locked] > 0 {
            resolvedMoveIndex = locked
            move = attacker.moves[resolvedMoveIndex]
        }

        // Two-turn charge override: if the user is mid-charge, force the
        // queued action to be the charged move regardless of what was picked.
        // Canon: charging locks the user into the second-turn release.
        if let chargedIdx = attacker.chargedMoveIndex,
           attacker.moves.indices.contains(chargedIdx) {
            resolvedMoveIndex = chargedIdx
            move = attacker.moves[resolvedMoveIndex]
        }

        // Encore or a charge swapped in a spread move: run it on the spread
        // path, which repeats these checks for the new move. The index is
        // passed as-is; the spread path resolves the same redirect to it.
        if resolvedMoveIndex != moveIndex, usesSpreadPath(move, attacker: attacker) {
            performSpreadMove(attackerSide: attackerSide, attackerSlot: attackerSlot,
                              moveIndex: resolvedMoveIndex)
            return
        }

        // Destiny Bond clears when the user takes their next action.
        attacker.destinyBondActive = false

        if !preMoveStatusCheck(attacker) { return }

        // First-turn-only legality (Fake Out, First Impression). The UI
        // disables the button outright when this predicate is true, so the
        // only path that reaches here is a forced action — typically Encore
        // having locked the holder into Fake Out from a previous switch-in.
        // Per canon, the holder Struggles instead of failing the move; PP
        // is NOT charged on the original move since it never executes.
        if attacker.isFirstTurnOnlyMoveLockedOut(at: resolvedMoveIndex) {
            log.append(BattleLogEntry(text: "\(attacker.displayName) can't use \(move.name) right now!"))
            // `performStruggle` increments the counter itself — don't double-bump.
            performStruggle(attackerSide: attackerSide, attackerSlot: attackerSlot,
                            defenderSide: defenderSide, defenderSlot: defenderSlot)
            return
        }

        if attacker.pp.indices.contains(resolvedMoveIndex), attacker.pp[resolvedMoveIndex] <= 0 {
            log.append(BattleLogEntry(text: "\(attacker.displayName) has no PP left for \(move.name)!"))
            return
        }

        log.append(BattleLogEntry(text: "\(attacker.displayName) used \(move.name)!"))
        if attacker.pp.indices.contains(resolvedMoveIndex) {
            attacker.pp[resolvedMoveIndex] -= 1
            // Pressure — if any opposing active mon has Pressure, the attacker
            // pays an extra PP (canon: only when the move actually targets them,
            // but Tier 5 treats it as any opposing-side move that fired).
            let oppSide = side(at: 1 - attackerSide)
            for slot in 0..<format.activeSlots {
                if let t = oppSide.active(at: slot), !t.fainted,
                   t.activeAbility == "pressure" {
                    attacker.pp[resolvedMoveIndex] = max(0, attacker.pp[resolvedMoveIndex] - 1)
                    break
                }
            }
        }
        // Track the move for Encore / Disable lookup on the NEXT use.
        attacker.lastMoveIndex = resolvedMoveIndex

        // Bump the first-turn-only counter — any successful dispatch counts
        // as "this Pokemon has acted since switching in", which locks out
        // future Fake Out / First Impression attempts. The legality check
        // above already short-circuited illegal attempts to Struggle.
        attacker.movesUsedSinceSwitchIn += 1

        // Leppa Berry — restores 10 PP if the move just hit zero.
        maybeTriggerLeppaBerry(for: attacker, moveIndex: resolvedMoveIndex)

        // Stance Change — flip Aegislash before the damage roll so the new form's
        // stats apply to this move.
        maybeApplyStanceChange(for: attacker, move: move)

        // Lock the holder into this move for as long as it keeps its Choice item.
        if attacker.choiceLockedMoveIndex == nil, isChoiceLocked(attacker) {
            attacker.choiceLockedMoveIndex = resolvedMoveIndex
        }

        // Retarget if the intended target fainted before this action resolved. We
        // resolve before the accuracy roll so Bright Powder on the live target
        // applies.
        var defender = dSide.active(at: defenderSlot)
        if defender == nil || defender?.fainted == true {
            defender = firstLiveDefender(in: dSide)
        }

        // Redirection (Follow Me / Rage Powder). Only affects moves that target
        // a single opposing Pokemon — same-side moves pass through, and
        // unaffected types like Snipe Shot / Stalwart ignore it (Tier 1 doesn't
        // model those exceptions).
        if attackerSide != defenderSide,
           let redirSlot = dSide.redirectionTargetSlot,
           let redirected = dSide.active(at: redirSlot),
           !redirected.fainted {
            defender = redirected
        }

        if let acc = effectiveAccuracy(move, attacker: attacker, against: defender) {
            let roll = accuracyRoll()
            if roll > acc {
                log.append(BattleLogEntry(text: "It missed!"))
                attacker.consecutiveProtectCount = 0
                return
            }
        }

        // Quick Guard — blocks priority moves before they connect. Only affects
        // moves directed at the opposing side.
        if attackerSide != defenderSide,
           move.priority > 0,
           dSide.quickGuardActive {
            log.append(BattleLogEntry(text: "\(dSide.label)'s Quick Guard blocked \(move.name)!"))
            attacker.consecutiveProtectCount = 0
            return
        }

        // Two-turn charge moves — must run BEFORE the status-class branch so
        // Geomancy (status-class) charges & releases cleanly. For damaging
        // charge moves we just charge here and let the next call land in the
        // damage path on the release turn.
        let chargeKey = BattleSimSeed.normalize(move.name)
        if let charge = BattleMoveEffects.chargeMoves[chargeKey] {
            if attacker.chargedMoveKey == chargeKey {
                // Release turn — clear the volatile.
                attacker.chargedMoveKey = nil
                attacker.chargedMoveIndex = nil
                // Status-class release (Geomancy): apply boosts and bail.
                if !charge.statusOnRelease.isEmpty {
                    for (stat, delta) in charge.statusOnRelease {
                        changeStage(attacker, stat: stat, by: delta)
                    }
                    log.append(BattleLogEntry(text: "\(attacker.displayName) unleashed energy!"))
                    attacker.consecutiveProtectCount = 0
                    return
                }
                // Fall through to the normal damage path on the release turn.
            } else {
                // Charge turn unless weather skip applies (Solar Beam in sun,
                // Electro Shot in rain).
                let skip = charge.skipInWeather.map { weather == $0 } ?? false
                if !skip {
                    for (stat, delta) in charge.selfBoostsOnCharge {
                        changeStage(attacker, stat: stat, by: delta)
                    }
                    attacker.chargedMoveKey = chargeKey
                    attacker.chargedMoveIndex = resolvedMoveIndex
                    let text = charge.chargeLog.replacingOccurrences(
                        of: "{user}", with: attacker.displayName)
                    log.append(BattleLogEntry(text: text))
                    attacker.consecutiveProtectCount = 0
                    return
                }
                // Weather skipped — fall through to one-turn execution.
            }
        }

        if move.damageClass == "status" {
            // Status moves that target the opponent are stopped by Protect / King's
            // Shield. Self-targeted statuses (Swords Dance, Trick Room, screens,
            // tailwind) bypass — we only block when the user picked a foe slot AND
            // the move's effect lookup is "opposing-targeted" by nature. For Tier 1
            // we approximate: if the dispatch key lands in statusInflicts /
            // confusionInflicts / hazardSetters / taunt, the move's target matters.
            let key = BattleSimSeed.normalize(move.name)
            let opposingTargeted = BattleMoveEffects.statusInflicts[key] != nil
                || BattleMoveEffects.confusionInflicts.contains(key)
                || BattleMoveEffects.hazardSetters[key] != nil
                || key == "taunt" || key == "encore" || key == "disable"
            if opposingTargeted, attackerSide != defenderSide,
               let d = defender, d.protectedThisTurn {
                log.append(BattleLogEntry(text: "\(d.displayName) protected itself!"))
                attacker.consecutiveProtectCount = 0
                return
            }
            // Magic Bounce — opposing-targeted status moves bounce back at the
            // user instead of resolving on the defender. We swap roles for this
            // dispatch only; Substitute / abilities on the original user apply
            // exactly as if the user had been the target all along.
            if opposingTargeted, attackerSide != defenderSide,
               let d = defender, d.activeAbility == "magic-bounce" {
                log.append(BattleLogEntry(text: "\(d.displayName)'s Magic Bounce reflected \(move.name)!"))
                applyStatusMoveEffect(move: move, attacker: d,
                                      attackerSideIdx: defenderSide,
                                      defender: attacker, defenderSideIdx: attackerSide)
                attacker.consecutiveProtectCount = 0
                return
            }
            applyStatusMoveEffect(move: move, attacker: attacker,
                                  attackerSideIdx: attackerSide,
                                  defender: defender, defenderSideIdx: defenderSide)
            // The user successfully resolved a non-protect move; reset its
            // protect streak so the diminishing returns clock resets.
            if !BattleMoveEffects.protectFamily.contains(BattleSimSeed.normalize(move.name)),
               BattleSimSeed.normalize(move.name) != "wideguard",
               BattleSimSeed.normalize(move.name) != "quickguard" {
                attacker.consecutiveProtectCount = 0
            }
            return
        }

        guard let defender else {
            log.append(BattleLogEntry(text: "\(attacker.displayName)'s attack had no target."))
            return
        }

        // Telepathy — in doubles, your ally's targeted moves can't hit you.
        // Same-side spread moves still hit (Earthquake hits everyone), so we
        // only block here in the single-target path.
        if attackerSide == defenderSide, attacker !== defender,
           defender.activeAbility == "telepathy" {
            log.append(BattleLogEntry(text: "\(defender.displayName)'s Telepathy avoided the move!"))
            attacker.consecutiveProtectCount = 0
            return
        }

        // Protect — if the target braced this turn, the hit fizzles and the
        // attacker resets its own protect streak. Contact penalties on the
        // attacker (Spiky Shield chip, Baneful Bunker poison, Burning Bulwark
        // burn, Silk Trap speed drop, King's Shield Atk drop) fire here.
        // Phantom Force / Shadow Force bypass Protect — handled via the
        // chargeBehavior's `bypassesProtect` flag.
        let bypassesProtect = BattleMoveEffects.chargeMoves[BattleSimSeed.normalize(move.name)]?.bypassesProtect ?? false
        if defender.protectedThisTurn, !bypassesProtect {
            log.append(BattleLogEntry(text: "\(defender.displayName) protected itself from \(move.name)!"))
            applyProtectContactPenalty(attacker: attacker, defender: defender, move: move)
            attacker.consecutiveProtectCount = 0
            return
        }

        let movKey = BattleSimSeed.normalize(move.name)

        // Bulletproof / Soundproof — block the entire hit when the defender
        // has the matching immunity ability. Sheer Force does not bypass.
        if defender.activeAbility == "bulletproof",
           BattleMoveEffects.ballisticMoves.contains(movKey) {
            log.append(BattleLogEntry(text: "\(defender.displayName)'s Bulletproof blocked \(move.name)!"))
            attacker.consecutiveProtectCount = 0
            return
        }
        if defender.activeAbility == "soundproof",
           BattleMoveEffects.soundMoves.contains(movKey) {
            log.append(BattleLogEntry(text: "\(defender.displayName)'s Soundproof blocked \(move.name)!"))
            attacker.consecutiveProtectCount = 0
            return
        }

        // OHKO moves — skip the normal calc; level-diff accuracy, all-or-nothing.
        if BattleMoveEffects.ohkoMoves.contains(movKey) {
            applyOHKO(attacker: attacker, defender: defender, move: move)
            attacker.consecutiveProtectCount = 0
            return
        }
        // Tier 5 fixed-damage moves (Seismic Toss / Counter / Super Fang / …).
        // These bypass the standard damage formula.
        if BattleMoveEffects.tier5FixedDamage.contains(movKey) {
            applyTier5FixedDamage(key: movKey, attacker: attacker, defender: defender, move: move)
            attacker.consecutiveProtectCount = 0
            return
        }

        applyDamageHit(attacker: attacker, defender: defender, move: move, isSpread: false)
        let pivotKey = movKey
        // Damage-side hazard removers (Rapid Spin, Mortal Spin) fire their
        // secondary AFTER damage lands. Defog and Tidy Up are status moves and
        // are handled in `applyStatusMoveEffect` above.
        if let rm = BattleMoveEffects.hazardRemovers[pivotKey], !attacker.fainted {
            applyHazardRemoval(rm,
                               ownSideIdx: attackerSide,
                               foeSideIdx: defenderSide,
                               attacker: attacker, defender: defender)
        }
        // Damage pivots — switch the attacker out after a successful hit.
        if BattleMoveEffects.pivotMoves[pivotKey] == .damage, !attacker.fainted {
            queuePivotSwitch(side: attackerSide, slot: attackerSlot, attacker: attacker)
        }
        // Any non-protect move resets the protect streak.
        attacker.consecutiveProtectCount = 0
    }

    private func performSpreadMove(attackerSide: Int, attackerSlot: Int, moveIndex: Int) {
        let aSide = side(at: attackerSide)
        let defenderSideIdx = 1 - attackerSide
        let dSide = side(at: defenderSideIdx)
        guard let attacker = aSide.active(at: attackerSlot), !attacker.fainted else { return }
        guard moveIndex < attacker.moves.count else { return }

        // Choice lock defensive redirect, mirroring performMove.
        var resolvedMoveIndex = moveIndex
        if isChoiceLocked(attacker),
           let locked = attacker.choiceLockedMoveIndex,
           locked != moveIndex, attacker.moves.indices.contains(locked) {
            resolvedMoveIndex = locked
        }
        var move = attacker.moves[resolvedMoveIndex]

        if attacker.status == .freeze && move.type == "Fire" {
            attacker.status = .none
            log.append(BattleLogEntry(text: "\(attacker.displayName) thawed out by its move!"))
        }

        if attacker.tauntTurnsRemaining > 0 && move.damageClass == "status" {
            log.append(BattleLogEntry(text: "\(attacker.displayName) can't use \(move.name) after the taunt!"))
            return
        }

        // The same Disable / Encore / charge handling as performMove.
        if attacker.disableTurns > 0, attacker.disabledMoveIndex == resolvedMoveIndex {
            log.append(BattleLogEntry(text: "\(attacker.displayName)'s \(move.name) is disabled!"))
            return
        }
        if attacker.encoreTurns > 0,
           let locked = attacker.encoreLockedIndex,
           locked != resolvedMoveIndex,
           attacker.moves.indices.contains(locked),
           attacker.pp.indices.contains(locked),
           attacker.pp[locked] > 0 {
            resolvedMoveIndex = locked
            move = attacker.moves[resolvedMoveIndex]
        }
        if let chargedIdx = attacker.chargedMoveIndex,
           attacker.moves.indices.contains(chargedIdx) {
            resolvedMoveIndex = chargedIdx
            move = attacker.moves[resolvedMoveIndex]
        }
        // Redirected to a single-target move: run it on the single-target
        // path, aimed at the first live foe.
        if !usesSpreadPath(move, attacker: attacker) {
            let foeSide = 1 - attackerSide
            let foeSlot = (0..<format.activeSlots).first {
                side(at: foeSide).active(at: $0).map { !$0.fainted } ?? false
            } ?? 0
            performMove(attackerSide: attackerSide, attackerSlot: attackerSlot,
                        moveIndex: resolvedMoveIndex, defenderSide: foeSide, defenderSlot: foeSlot)
            return
        }

        // Destiny Bond clears when the user takes their next action.
        attacker.destinyBondActive = false

        if !preMoveStatusCheck(attacker) { return }

        if attacker.pp.indices.contains(resolvedMoveIndex), attacker.pp[resolvedMoveIndex] <= 0 {
            log.append(BattleLogEntry(text: "\(attacker.displayName) has no PP left for \(move.name)!"))
            return
        }

        log.append(BattleLogEntry(text: "\(attacker.displayName) used \(move.name)!"))
        if attacker.pp.indices.contains(resolvedMoveIndex) {
            attacker.pp[resolvedMoveIndex] -= 1
            // Pressure, as in performMove: an extra PP if any active foe has it.
            for slot in 0..<format.activeSlots {
                if let t = dSide.active(at: slot), !t.fainted, t.activeAbility == "pressure" {
                    attacker.pp[resolvedMoveIndex] = max(0, attacker.pp[resolvedMoveIndex] - 1)
                    break
                }
            }
        }
        // Track the move for Encore / Disable lookup on the next use.
        attacker.lastMoveIndex = resolvedMoveIndex

        // Bump the first-turn-only counter so a Pokemon that used a spread
        // move on turn 1 can't then Fake Out on turn 2.
        attacker.movesUsedSinceSwitchIn += 1

        maybeTriggerLeppaBerry(for: attacker, moveIndex: resolvedMoveIndex)

        // Stance Change — same flip rule applies on a spread move (Earthquake,
        // Surf, etc. all flip Aegislash to Blade Forme before damage rolls).
        maybeApplyStanceChange(for: attacker, move: move)

        if attacker.choiceLockedMoveIndex == nil, isChoiceLocked(attacker) {
            attacker.choiceLockedMoveIndex = resolvedMoveIndex
        }

        let liveDefender = firstLiveDefender(in: dSide)

        if let acc = effectiveAccuracy(move, attacker: attacker, against: liveDefender) {
            let roll = accuracyRoll()
            if roll > acc {
                log.append(BattleLogEntry(text: "It missed!"))
                return
            }
        }

        if move.damageClass == "status" {
            applyStatusMoveEffect(move: move, attacker: attacker,
                                  attackerSideIdx: attackerSide,
                                  defender: liveDefender, defenderSideIdx: defenderSideIdx)
            return
        }

        // Targets are fixed when the move is used: every live foe, plus the
        // user's ally for `allAdjacent` moves (Earthquake, Surf, Explosion).
        // The 0.75x spread reduction applies only when that's more than one
        // Pokemon. With one foe left and no ally, Hyper Voice is single-target
        // and does full damage. As in Showdown, a target that then protects or
        // is immune still counts.
        let targeting = SpreadMoves.targeting(of: move.name)
        var targets: [(participant: BattleParticipant, side: BattleSide)] =
            (0..<format.activeSlots).compactMap { slot in
                guard let foe = dSide.active(at: slot), !foe.fainted else { return nil }
                return (foe, dSide)
            }
        if targeting.hitsAlly {
            for slot in 0..<format.activeSlots where slot != attackerSlot {
                if let ally = aSide.active(at: slot), !ally.fainted { targets.append((ally, aSide)) }
            }
        }
        let isSpreadHit = targets.count > 1

        // Quick Guard catches priority spread moves (rare — e.g. Quick Attack
        // isn't spread, but a future priority spread move would route here too).
        if move.priority > 0, dSide.quickGuardActive {
            log.append(BattleLogEntry(text: "\(dSide.label)'s Quick Guard blocked \(move.name)!"))
            attacker.consecutiveProtectCount = 0
            return
        }

        for target in targets {
            // Wide Guard shields its own side, so the ally can be covered by
            // the attacker's side's Wide Guard. It keys off the move's target
            // type, not the live target count, so it still blocks a spread
            // move with one foe left.
            if target.side.wideGuardActive {
                log.append(BattleLogEntry(text: "\(target.side.label)'s Wide Guard blocked \(move.name)!"))
                continue
            }
            let defender = target.participant
            if defender.protectedThisTurn {
                log.append(BattleLogEntry(text: "\(defender.displayName) protected itself from \(move.name)!"))
                applyProtectContactPenalty(attacker: attacker, defender: defender, move: move)
                continue
            }
            applyDamageHit(attacker: attacker, defender: defender, move: move, isSpread: isSpreadHit)
            if attacker.fainted { break }
        }
        // Damage pivots that happen to be spread moves (none currently in our
        // pool, but the bookkeeping is identical).
        let pivotKey = BattleSimSeed.normalize(move.name)
        if BattleMoveEffects.pivotMoves[pivotKey] == .damage, !attacker.fainted {
            queuePivotSwitch(side: attackerSide, slot: attackerSlot, attacker: attacker)
        }
        attacker.consecutiveProtectCount = 0
    }

    private func performStruggle(attackerSide: Int, attackerSlot: Int,
                                 defenderSide: Int, defenderSlot: Int) {
        let aSide = side(at: attackerSide)
        let dSide = side(at: defenderSide)
        guard let attacker = aSide.active(at: attackerSlot), !attacker.fainted else { return }

        if !preMoveStatusCheck(attacker) { return }

        // Struggle also counts as "this Pokemon has moved" for the
        // first-turn-only check, even when dispatched directly via the
        // Struggle button rather than the legality redirect above.
        attacker.movesUsedSinceSwitchIn += 1

        log.append(BattleLogEntry(text: "\(attacker.displayName) used Struggle!"))

        var defender = dSide.active(at: defenderSlot)
        if defender == nil || defender?.fainted == true {
            defender = (0..<format.activeSlots).compactMap { dSide.active(at: $0) }
                .first(where: { !$0.fainted })
        }
        guard let defender else {
            log.append(BattleLogEntry(text: "No target remained."))
            return
        }

        // Compute struggle damage directly with calcDamageRange, bypassing the
        // VM (Struggle has no real MoveData and no type-effect / STAB).
        let proxyA = CalcSide(); configure(side: proxyA, from: attacker, withMove: nil)
        let proxyD = CalcSide(); configure(side: proxyD, from: defender, withMove: nil)
        let burn = attacker.status == .burn ? 0.5 : 1.0

        let raw = calcDamageRange(
            level: attacker.slot.level, movePower: 50,
            userAtk: proxyA.atk, defenderDef: proxyD.def,
            multi: false, weatherMult: 1.0, glaiveRush: false,
            crit: false, critMultiplier: 1.5,
            stabBonus: 1.0, typeEffect: 1.0,
            burnReduction: burn, abilityMods: AbilityModResult(),
            zMoveBypass: false
        )

        let dMin = Int(raw.min)
        let dMax = max(Int(raw.max), dMin)
        let damage = rollDamage(dMin, dMax)
        defender.currentHP = max(0, defender.currentHP - damage)
        log.append(BattleLogEntry(text: "\(defender.displayName) took \(damage) damage."))
        if defender.fainted {
            log.append(BattleLogEntry(text: "\(defender.displayName) fainted!", emphasis: true))
        }

        // Recoil: 1/4 of attacker's max HP.
        let recoil = max(1, attacker.maxHP / 4)
        attacker.currentHP = max(0, attacker.currentHP - recoil)
        log.append(BattleLogEntry(text: "\(attacker.displayName) is hit with recoil! (-\(recoil) HP)"))
        if attacker.fainted {
            log.append(BattleLogEntry(text: "\(attacker.displayName) fainted!", emphasis: true))
        }
    }

    /// Number of times a multi-hit move strikes this turn. Honors Skill Link and
    /// the Gen V+ 2–5 distribution (35/35/15/15). Falls back to `multiHitFallback`
    /// when the synced `MoveData` doesn't populate hit counts.
    private func hitCount(for move: MoveData, attacker: BattleParticipant) -> Int {
        var maxH = move.maxHits
        var minH = move.minHits
        if maxH == nil || (maxH ?? 1) <= 1 {
            if let fallback = BattleMoveEffects.multiHitFallback[BattleSimSeed.normalize(move.name)] {
                minH = fallback.0
                maxH = fallback.1
            }
        }
        guard let maxV = maxH, maxV > 1 else { return 1 }
        let minV = minH ?? maxV
        if minV == maxV { return maxV }
        if attacker.activeAbility == "skill-link" { return maxV }
        if rollOverride?.suppressChanceEvents == true {
            if case .min = rollOverride?.roll { return minV }
            return maxV
        }
        // Gen V+ 2–5 distribution: 35/35/15/15.
        let r = Double.random(in: 0..<1)
        switch r {
        case ..<0.35: return 2
        case ..<0.70: return 3
        case ..<0.85: return 4
        default:      return 5
        }
    }

    /// True if the move counts as making contact. Combines the synced flag with a
    /// curated fallback list (`BattleMoveEffects.contactMoves`) so contact-recoil
    /// (Rocky Helmet, Rough Skin, Iron Barbs) still fires on common physical moves
    /// even when the GraphQL sync didn't populate `makesContact`.
    private func isContactMove(_ move: MoveData) -> Bool {
        if move.makesContact { return true }
        return BattleMoveEffects.contactMoves.contains(BattleSimSeed.normalize(move.name))
    }

    private func applyDamageHit(attacker: BattleParticipant, defender: BattleParticipant,
                                move: MoveData, isSpread: Bool) {
        // Snapshot data we need *before* the hit lands: damage calc reads
        // effectiveHeldItem, and item-related effects below need the pre-hit state.
        let defenderHadItemBefore = defender.effectiveHeldItem != .none
        let preBerry = defender.effectiveHeldItem
        let wasFullHP = defender.atFullHP

        let isKnockOff = BattleSimSeed.normalize(move.name) == "knockoff"

        // Tier 8 — semi-invulnerable defender check. If the defender is
        // mid-charge of Dig / Fly / Dive / Bounce / Phantom Force / Shadow
        // Force, the attack misses entirely UNLESS the move is in the
        // hit-through exception list for that invulnerability kind.
        let attackKey = BattleSimSeed.normalize(move.name)
        var invDamageMult: Double = 1.0
        if let defChargeKey = defender.chargedMoveKey,
           let defBehavior = BattleMoveEffects.chargeMoves[defChargeKey],
           let kind = defBehavior.invulnerabilityKind {
            let exceptions = BattleMoveEffects.invulnerabilityExceptions[kind] ?? []
            if !exceptions.contains(attackKey) {
                log.append(BattleLogEntry(text: "\(defender.displayName) avoided the attack!"))
                return
            }
            let doublers = BattleMoveEffects.invulnerabilityDoubleDamage[kind] ?? []
            if doublers.contains(attackKey) { invDamageMult = 2.0 }
        }

        // Find which side the defender is on so we can read its screen state.
        // Helping Hand reads the attacker's side at the attacker's slot. Both
        // multipliers stack independently of the damage calc.
        let defenderSideIdx = side(at: 0).active(at: 0) === defender
                              || side(at: 0).active(at: 1) === defender ? 0 : 1
        let attackerSideIdx = 1 - defenderSideIdx
        let defenderSide = side(at: defenderSideIdx)
        let attackerSide = side(at: attackerSideIdx)
        let isPhysical = move.damageClass == "physical"
        let isSpecial = move.damageClass == "special"
        let attackerSlot = slotOf(attacker, side: attackerSideIdx)
        let helpingHand = attackerSlot < attackerSide.helpingHandPending.count
                          && attackerSide.helpingHandPending[attackerSlot]

        // First-hit zero-effectiveness check: avoid the loop entirely if the move
        // doesn't affect the defender at all (type immunity, etc.).
        let probe = computeDamage(attacker: attacker, defender: defender,
                                  move: move, isSpread: isSpread, crit: false)
        if probe.eff == 0 {
            log.append(BattleLogEntry(text: "It doesn't affect \(defender.displayName)…"))
            return
        }

        let hits = hitCount(for: move, attacker: attacker)
        var totalDamage = 0
        var hitsLanded = 0
        var anyCrit = false
        var lastEff: Double = probe.eff
        var preDefenderHP = defender.currentHP   // for Berserk threshold + Innards Out

        for _ in 0..<hits {
            if defender.fainted { break }
            // Roll crit independently per hit (Gen VI+).
            let didCrit = rollCrit(attacker: attacker, move: move)
            if didCrit { anyCrit = true }
            let result = computeDamage(attacker: attacker, defender: defender,
                                       move: move, isSpread: isSpread, crit: didCrit)
            if result.eff == 0 { break }
            lastEff = result.eff
            let dMin = Int(result.min)
            let dMax = max(Int(result.max), dMin)
            var damage = rollDamage(dMin, dMax)
            // Tier 8 — Earthquake-on-Dig and friends deal 2x to the
            // invulnerable defender.
            if invDamageMult != 1.0 {
                damage = Int(Double(damage) * invDamageMult)
            }
            // Knock Off: 1.5x damage when the defender has a removable item.
            // The Champions calc applies this itself, so it's only added
            // here when both sides are on mainline rules (the legacy engine).
            if isKnockOff && defenderHadItemBefore && !preBerry.isMegaStone
                && !(attacker.slot.championsMode && defender.slot.championsMode) {
                damage = Int(Double(damage) * 1.5)
            }
            // Tier 5 — power-modifier moves (Acrobatics / Hex / Venoshock /
            // Stored Power / Power Trip). Scale damage by a multiplier derived
            // from the move + battle state.
            let t5Key = BattleSimSeed.normalize(move.name)
            if BattleMoveEffects.damageModifierKeys.contains(t5Key) {
                let mult = tier5PowerMultiplier(key: t5Key, attacker: attacker,
                                                defender: defender,
                                                baseMovePower: move.power ?? 0)
                damage = Int(Double(damage) * mult)
            }
            // Body Press uses the user's Def stat instead of Atk; Foul Play
            // uses the TARGET's Atk. The base calc used Atk, so swap by
            // re-scaling the damage based on the alternate stat ratio.
            if t5Key == "bodypress" {
                let evAtk = attacker.slot.championsMode ? championsEVToMain(attacker.slot.evAtk) : attacker.slot.evAtk
                let evDef = attacker.slot.championsMode ? championsEVToMain(attacker.slot.evDef) : attacker.slot.evDef
                let atkVal = calcStat(base: attacker.baseAtk, iv: 31, ev: evAtk,
                                      level: attacker.slot.level,
                                      natureMod: attacker.nature.modifier(for: .atk))
                let defVal = calcStat(base: attacker.baseDef, iv: 31, ev: evDef,
                                      level: attacker.slot.level,
                                      natureMod: attacker.nature.modifier(for: .def))
                if atkVal > 0 {
                    damage = Int(Double(damage) * Double(defVal) / Double(atkVal))
                }
            }
            if t5Key == "foulplay" {
                let evAtkSelf = attacker.slot.championsMode ? championsEVToMain(attacker.slot.evAtk) : attacker.slot.evAtk
                let evAtkTgt  = defender.slot.championsMode ? championsEVToMain(defender.slot.evAtk) : defender.slot.evAtk
                let atkSelf = calcStat(base: attacker.baseAtk, iv: 31, ev: evAtkSelf,
                                       level: attacker.slot.level,
                                       natureMod: attacker.nature.modifier(for: .atk))
                let atkTgt = calcStat(base: defender.baseAtk, iv: 31, ev: evAtkTgt,
                                      level: defender.slot.level,
                                      natureMod: defender.nature.modifier(for: .atk))
                if atkSelf > 0 {
                    damage = Int(Double(damage) * Double(atkTgt) / Double(atkSelf))
                }
            }
            // Substitute — incoming damage hits the sub first. Sound moves
            // bypass canon (we don't model the sound category yet); Infiltrator
            // bypasses always. Sub absorbs `damage`; surplus does not carry
            // to the holder, but the sub breaks when its HP hits 0.
            if defender.subHP > 0, attacker.activeAbility != "infiltrator" {
                let absorbed = min(damage, defender.subHP)
                defender.subHP -= absorbed
                damage -= absorbed
                if defender.subHP <= 0 {
                    log.append(BattleLogEntry(text: "\(defender.displayName)'s substitute broke!"))
                } else {
                    log.append(BattleLogEntry(text: "The substitute took the hit!"))
                }
                // Remaining damage (if any) still falls through to the holder,
                // but in canon Substitute fully blocks the hit. We follow canon.
                damage = 0
            }
            // Screens — applied here so the multiplier sits cleanly outside the
            // damage calc. Crits bust screens, and Infiltrator on the attacker
            // ignores them entirely. Aurora Veil wins over Light Screen/Reflect.
            let bypassScreens = didCrit || attacker.activeAbility == "infiltrator"
            if !bypassScreens {
                let auro = defenderSide.auroraVeilTurns > 0
                let lite = defenderSide.lightScreenTurns > 0
                let refl = defenderSide.reflectTurns > 0
                if auro || (isPhysical && refl) || (isSpecial && lite) {
                    let multi = format.activeSlots >= 2 ? (2.0 / 3.0) : 0.5
                    damage = Int(Double(damage) * multi)
                }
            }
            // Helping Hand — 1.5x on each hit; persists across multi-hits as long
            // as the partner pending flag is set. Resets at end-of-turn.
            if helpingHand { damage = Int(Double(damage) * 1.5) }
            // Disguise — Mimikyu's first incoming damaging hit gets reduced to a
            // sliver of chip (1/8 max HP) and busts the form. Subsequent hits
            // resolve normally.
            if defender.disguiseIntact, defender.activeAbility == "disguise",
               damage > 0, hitsLanded == 0, !Self.ignoresAbilities(attacker, move) {
                defender.disguiseIntact = false
                damage = max(1, defender.maxHP / 8)
                log.append(BattleLogEntry(text: "\(defender.displayName)'s disguise was busted!"))
            }
            // Ice Face — Eiscue's first incoming PHYSICAL hit is blocked
            // entirely (zero damage). The Ice form busts to Noice; snow/hail
            // weather restores it via `setWeather`.
            if defender.iceFaceIntact, defender.activeAbility == "ice-face",
               move.damageClass == "physical", hitsLanded == 0 {
                defender.iceFaceIntact = false
                damage = 0
                log.append(BattleLogEntry(text: "\(defender.displayName)'s Ice Face transformed it into Noice Face!"))
            }
            // Endure — clamps post-hit HP at 1 for this turn.
            let preHP = defender.currentHP
            defender.currentHP = max(0, defender.currentHP - damage)
            if defender.endureThisTurn, defender.currentHP == 0, preHP > 0 {
                defender.currentHP = 1
                log.append(BattleLogEntry(text: "\(defender.displayName) endured the hit!"))
            }
            // Track HP loss for Innards Out retaliation later — picks up the
            // LAST hit's damage when the defender finally faints.
            preDefenderHP = preHP

            // Tier 4 — defender-side hit reactives. Fire per-hit so Anger Point
            // hooks the first crit and Berserk hooks the threshold crossing.
            applyDefenderHitReactives(attacker: attacker, defender: defender,
                                      move: move, preHP: preHP, wasCrit: didCrit)

            // Tier 5 — track per-hit damage for Counter / Mirror Coat. Both
            // are returnable next time the defender acts this turn. Status
            // moves and 0-damage hits don't qualify.
            if damage > 0 {
                if move.damageClass == "physical" {
                    defender.lastPhysicalDamageThisTurn = damage
                } else if move.damageClass == "special" {
                    defender.lastSpecialDamageThisTurn = damage
                }
            }

            // Sturdy / Focus Sash / Focus Band — survive a would-be OHKO at 1
            // HP. Only the first hit can be at full HP, so Sturdy and the sash
            // only apply there; Sturdy acts first, keeping the sash.
            if defender.currentHP == 0 {
                if wasFullHP && hitsLanded == 0 && defender.activeAbility == "sturdy"
                    && !Self.ignoresAbilities(attacker, move) {
                    defender.currentHP = 1
                    log.append(BattleLogEntry(text: "\(defender.displayName) endured the hit with Sturdy!"))
                } else if wasFullHP && hitsLanded == 0 && defender.effectiveHeldItem == .focusSash {
                    defender.currentHP = 1
                    defender.consumedItem = true
                    log.append(BattleLogEntry(text: "\(defender.displayName) hung on with its Focus Sash!"))
                } else if defender.effectiveHeldItem == .focusBand && luck(0.1) {
                    defender.currentHP = 1
                    log.append(BattleLogEntry(text: "\(defender.displayName) hung on using Focus Band!"))
                }
            }

            // Type-resist berry consumption — `computeItemModifiers` halved this
            // hit's damage; mark the berry spent so subsequent hits get full damage.
            if !defender.consumedItem,
               let resistedType = typeResistBerryMap[preBerry],
               resistedType == move.type, result.eff > 1.0 {
                defender.consumedItem = true
                log.append(BattleLogEntry(text: "\(defender.displayName)'s \(preBerry.rawValue) weakened the attack!"))
            } else if !defender.consumedItem, preBerry == .chilanBerry, move.type == "Normal" {
                defender.consumedItem = true
                log.append(BattleLogEntry(text: "\(defender.displayName)'s Chilan Berry weakened the attack!"))
            }

            totalDamage += damage
            hitsLanded += 1
        }

        if hitsLanded == 0 {
            log.append(BattleLogEntry(text: "It had no effect on \(defender.displayName)."))
            return
        }

        if anyCrit { log.append(BattleLogEntry(text: "A critical hit!")) }

        var effText = ""
        if lastEff > 1 { effText = " It's super effective!" }
        else if lastEff < 1 && lastEff > 0 { effText = " It's not very effective…" }
        if hitsLanded > 1 {
            log.append(BattleLogEntry(
                text: "Hit \(hitsLanded) time(s)! \(defender.displayName) took \(totalDamage) damage.\(effText)"))
        } else {
            log.append(BattleLogEntry(
                text: "\(defender.displayName) took \(totalDamage) damage.\(effText)"))
        }

        // HP-restore berry (Sitrus, Oran) after the hit sequence.
        maybeTriggerHPBerry(for: defender)

        // Shell Bell — attacker recovers a slice of total damage dealt.
        if !attacker.fainted,
           attacker.effectiveHeldItem == .shellBell,
           totalDamage > 0, attacker.currentHP < attacker.maxHP {
            let heal = max(1, totalDamage / 8)
            attacker.currentHP = min(attacker.maxHP, attacker.currentHP + heal)
            log.append(BattleLogEntry(text: "\(attacker.displayName) recovered HP via Shell Bell."))
        }

        // Knock Off — strip the item if defender survived and Sticky Hold doesn't
        // protect it. Mega Stones can't be knocked off.
        if isKnockOff, defenderHadItemBefore, !defender.fainted {
            if defender.activeAbility == "sticky-hold" {
                log.append(BattleLogEntry(text: "\(defender.displayName)'s Sticky Hold kept its item!"))
            } else if !preBerry.isMegaStone {
                defender.knockedOff = true
                log.append(BattleLogEntry(text: "\(defender.displayName)'s \(preBerry.rawValue) was knocked off!"))
            }
        }

        // King's Rock — 10% chance to flinch the defender per move use.
        if !defender.fainted,
           attacker.effectiveHeldItem == .kingsRock,
           luck(0.1) {
            setFlinch(defender)
            log.append(BattleLogEntry(text: "\(defender.displayName) is going to flinch!"))
        }

        // Phase 2 — Drain / move recoil / Life Orb recoil based on totals.
        applyDrainAndRecoil(attacker: attacker, defender: defender,
                            move: move, totalDamage: totalDamage)

        // Phase 5 — Contact recoil from the defender (Rocky Helmet, Rough Skin,
        // Iron Barbs). Skip if attacker has Magic Guard or has already fainted.
        applyContactRecoil(attacker: attacker, defender: defender, move: move)

        // Tier 4 — status-on-contact reactives (Flame Body, Static, Poison
        // Point, Effect Spore on the defender; Poison Touch on the attacker).
        applyContactStatusReactives(attacker: attacker, defender: defender, move: move)
        applyPoisonTouch(attacker: attacker, defender: defender, move: move)

        // Tier 5 — Cursed Body / Pickpocket / trap moves.
        applyTier5ContactReactives(attacker: attacker, defender: defender, move: move)
        applyTrapMove(attacker: attacker, defender: defender, move: move)

        // Phase 3 — Self stat changes (always) and probabilistic secondary effects
        // on the target (only if it survived).
        applySelfStatChangesOnHit(attacker: attacker, move: move)
        applySecondaryEffects(attacker: attacker, defender: defender, move: move)

        if defender.fainted {
            log.append(BattleLogEntry(text: "\(defender.displayName) fainted!", emphasis: true))
            // Tier 4 — KO retaliation (Innards Out, Aftermath).
            applyKORetaliation(attacker: attacker, defender: defender,
                               move: move, lastHPLoss: preDefenderHP)
            // Tier 6 — Battle Bond (Gen 9): +1 SpA on every KO the holder
            // delivers. Fires once per switch-in via the `battleBondTriggered`
            // gate so it can't stack indefinitely.
            if attacker.activeAbility == "battle-bond", !attacker.battleBondTriggered {
                attacker.battleBondTriggered = true
                changeStage(attacker, stat: .spAtk, by: 1)
                log.append(BattleLogEntry(text: "\(attacker.displayName)'s Battle Bond raised its Sp. Atk!"))
            }
            // Destiny Bond — if the fallen defender had it up, the attacker
            // goes with them. Skip when the attacker already fainted (e.g.
            // Brave Bird recoil) and when the attacker is on the same side as
            // the defender (no friendly-fire DB).
            if defender.destinyBondActive, !attacker.fainted,
               findSideIndex(of: defender) != findSideIndex(of: attacker) {
                attacker.currentHP = 0
                log.append(BattleLogEntry(text: "\(attacker.displayName) was taken down by Destiny Bond!", emphasis: true))
            }
        }
        if attacker.fainted {
            log.append(BattleLogEntry(text: "\(attacker.displayName) fainted!", emphasis: true))
        }
    }

    /// Phase 2 — Drain heals the attacker (`move.drain > 0`); move recoil chips
    /// the attacker (`move.drain < 0`). Life Orb adds 1/10 max HP recoil per move
    /// use when damage was dealt. Rock Head/Magic Guard suppress move recoil;
    /// Magic Guard also suppresses Life Orb.
    private func applyDrainAndRecoil(attacker: BattleParticipant,
                                     defender: BattleParticipant,
                                     move: MoveData, totalDamage: Int) {
        guard totalDamage > 0 else { return }

        // Drain.
        if move.drain > 0, !attacker.fainted, attacker.currentHP < attacker.maxHP {
            let heal = max(1, totalDamage * move.drain / 100)
            attacker.currentHP = min(attacker.maxHP, attacker.currentHP + heal)
            log.append(BattleLogEntry(text: "\(attacker.displayName) drained HP!"))
        }

        // Move recoil.
        if move.drain < 0, !attacker.fainted,
           attacker.activeAbility != "rock-head",
           attacker.activeAbility != "magic-guard" {
            let recoil = max(1, totalDamage * -move.drain / 100)
            attacker.currentHP = max(0, attacker.currentHP - recoil)
            log.append(BattleLogEntry(text: "\(attacker.displayName) is hit with recoil! (-\(recoil) HP)"))
        }

        // Life Orb — 1/10 max HP self-damage per move use that dealt damage.
        if !attacker.fainted,
           attacker.effectiveHeldItem == .lifeOrb,
           attacker.activeAbility != "magic-guard" {
            let chip = max(1, attacker.maxHP / 10)
            attacker.currentHP = max(0, attacker.currentHP - chip)
            log.append(BattleLogEntry(text: "\(attacker.displayName) lost some HP from its Life Orb! (-\(chip) HP)"))
        }
        _ = defender // silence unused warning; reserved for future per-defender effects
    }

    /// Phase 5 — Rocky Helmet (1/6 maxHP), Rough Skin / Iron Barbs (1/8 maxHP).
    /// Fires once per move use after the hit loop completes. Magic Guard exempts
    /// the attacker. Triggers only on contact moves that dealt damage.
    private func applyContactRecoil(attacker: BattleParticipant,
                                    defender: BattleParticipant,
                                    move: MoveData) {
        guard !attacker.fainted else { return }
        guard isContactMove(move) else { return }
        if attacker.activeAbility == "magic-guard" { return }

        if defender.effectiveHeldItem == .rockyHelmet {
            let chip = max(1, attacker.maxHP / 6)
            attacker.currentHP = max(0, attacker.currentHP - chip)
            log.append(BattleLogEntry(text: "\(attacker.displayName) was hurt by \(defender.displayName)'s Rocky Helmet! (-\(chip) HP)"))
        }
        if !attacker.fainted,
           let ab = defender.activeAbility,
           ab == "rough-skin" || ab == "iron-barbs" {
            let chip = max(1, attacker.maxHP / 8)
            attacker.currentHP = max(0, attacker.currentHP - chip)
            log.append(BattleLogEntry(text: "\(attacker.displayName) was hurt by \(defender.displayName)'s \(formatAbilityName(ab))! (-\(chip) HP)"))
        }
    }

    /// Set the flinch flag and fire Steadfast (+1 Spe) when present. Used by
    /// every site that flinches a participant so the ability hooks consistently.
    private func setFlinch(_ p: BattleParticipant) {
        p.flinched = true
        if p.activeAbility == "steadfast" {
            changeStage(p, stat: .speed, by: 1)
            log.append(BattleLogEntry(text: "\(p.displayName)'s Steadfast raised its Speed!"))
        }
    }

    // MARK: Tier 4 — Reactive abilities

    /// Status-on-contact reactives on the DEFENDER. Flame Body / Static /
    /// Poison Point / Effect Spore can inflict a status on the contacting
    /// attacker. Shield Dust on the attacker doesn't block these — they're
    /// ability-driven, not move-secondary. Sheer Force does NOT suppress them.
    private func applyContactStatusReactives(attacker: BattleParticipant,
                                             defender: BattleParticipant,
                                             move: MoveData) {
        guard !attacker.fainted, !defender.fainted else { return }
        guard isContactMove(move) else { return }
        guard let ab = defender.activeAbility else { return }
        switch ab {
        case "flame-body":
            if luck(0.3) {
                tryInflictStatus(.burn, on: attacker, inflicter: defender)
            }
        case "static":
            if luck(0.3) {
                tryInflictStatus(.paralysis, on: attacker, inflicter: defender)
            }
        case "poison-point":
            if luck(0.3) {
                tryInflictStatus(.poison, on: attacker, inflicter: defender)
            }
        case "effect-spore":
            // Canon Gen V+: 9% sleep, 11% poison, 10% paralysis (total 30%).
            // Roll one number; pick the band it lands in.
            let r = rollOverride?.suppressChanceEvents == true ? 100 : Int.random(in: 1...100)
            switch r {
            case 1...9:   tryInflictStatus(.sleep,     on: attacker, inflicter: defender)
            case 10...20: tryInflictStatus(.poison,    on: attacker, inflicter: defender)
            case 21...30: tryInflictStatus(.paralysis, on: attacker, inflicter: defender)
            default: break
            }
        default: break
        }
    }

    /// Status-on-contact reactive on the ATTACKER side. Poison Touch gives the
    /// attacker a 30% chance to poison the target on every contact hit.
    private func applyPoisonTouch(attacker: BattleParticipant,
                                  defender: BattleParticipant,
                                  move: MoveData) {
        guard !defender.fainted else { return }
        guard isContactMove(move) else { return }
        guard attacker.activeAbility == "poison-touch" else { return }
        if luck(0.3) {
            tryInflictStatus(.poison, on: defender, inflicter: attacker)
        }
    }

    /// Post-hit defender abilities that read the kind of hit they took:
    /// Stamina (+Def any hit), Weak Armor (-Def +2Spe physical only),
    /// Justified (+Atk Dark only), Anger Point (+6 Atk on crit), Steadfast
    /// (+Spe on flinch — handled where the flinch flag is set), Berserk
    /// (+SpA when HP first crosses below 50%).
    ///
    /// Fires once per hit. `wasCrit` and `wasFlinch` describe THIS hit.
    private func applyDefenderHitReactives(attacker: BattleParticipant,
                                           defender: BattleParticipant,
                                           move: MoveData,
                                           preHP: Int,
                                           wasCrit: Bool) {
        guard !defender.fainted else { return }
        guard let ab = defender.activeAbility else { return }
        let isPhysical = move.damageClass == "physical"
        switch ab {
        case "stamina":
            changeStage(defender, stat: .def, by: 1)
            log.append(BattleLogEntry(text: "\(defender.displayName)'s Stamina raised its Defense!"))
        case "weak-armor":
            if isPhysical {
                changeStage(defender, stat: .def, by: -1)
                changeStage(defender, stat: .speed, by: 2)
                log.append(BattleLogEntry(text: "\(defender.displayName)'s Weak Armor shifted its stats!"))
            }
        case "justified":
            if move.type == "Dark" {
                changeStage(defender, stat: .atk, by: 1)
                log.append(BattleLogEntry(text: "\(defender.displayName)'s Justified raised its Attack!"))
            }
        case "anger-point":
            if wasCrit {
                defender.atkStage = 6
                log.append(BattleLogEntry(text: "\(defender.displayName)'s Anger Point maxed its Attack!"))
            }
        default: break
        }
        // Berserk — fires regardless of which side has the ability switch above,
        // since the check is just "did HP cross the 50% threshold this hit".
        if defender.activeAbility == "berserk", !defender.berserkFired {
            let half = defender.maxHP / 2
            if preHP > half && defender.currentHP <= half && defender.currentHP > 0 {
                defender.berserkFired = true
                changeStage(defender, stat: .spAtk, by: 1)
                log.append(BattleLogEntry(text: "\(defender.displayName)'s Berserk raised its Sp. Atk!"))
            }
        }
        _ = attacker
    }

    /// KO retaliation: Innards Out damages the attacker by the defender's last
    /// HP loss; Aftermath damages the contact-attacker by 1/4 maxHP. Both fire
    /// only when the defender just fainted to this hit. Magic Guard on the
    /// attacker suppresses Aftermath (indirect damage); Innards Out is direct
    /// retaliation and ignores Magic Guard in canon.
    private func applyKORetaliation(attacker: BattleParticipant,
                                    defender: BattleParticipant,
                                    move: MoveData,
                                    lastHPLoss: Int) {
        guard defender.fainted, !attacker.fainted else { return }
        guard let ab = defender.activeAbility else { return }
        switch ab {
        case "innards-out":
            attacker.currentHP = max(0, attacker.currentHP - lastHPLoss)
            log.append(BattleLogEntry(text: "\(defender.displayName)'s Innards Out hit \(attacker.displayName) for \(lastHPLoss) damage!"))
        case "aftermath":
            if isContactMove(move), attacker.activeAbility != "magic-guard" {
                let chip = max(1, attacker.maxHP / 4)
                attacker.currentHP = max(0, attacker.currentHP - chip)
                log.append(BattleLogEntry(text: "\(attacker.displayName) was hurt by \(defender.displayName)'s Aftermath! (-\(chip) HP)"))
            }
        default: break
        }
    }

    /// Phase 3 — Always-on self stat changes after a damaging hit landed
    /// (Close Combat, Draco Meteor, etc.).
    private func applySelfStatChangesOnHit(attacker: BattleParticipant, move: MoveData) {
        guard !attacker.fainted else { return }
        let key = BattleSimSeed.normalize(move.name)
        guard let drops = BattleMoveEffects.selfStatChangesOnHit[key] else { return }
        for (stat, delta) in drops {
            changeStage(attacker, stat: stat, by: delta)
        }
        log.append(BattleLogEntry(text: "\(attacker.displayName)'s stats dropped!"))
        // Defensive drops from Close Combat etc. can fire White Herb on the user.
        consumeWhiteHerbIfNeeded(attacker)
    }

    /// Phase 3 — Probabilistic on-hit secondary effects (status, flinch, target
    /// stat drops). Honors Shield Dust (blocks), Sheer Force (suppresses), and
    /// Serene Grace (doubles chance).
    private func applySecondaryEffects(attacker: BattleParticipant,
                                       defender: BattleParticipant,
                                       move: MoveData) {
        guard !defender.fainted else { return }
        let key = BattleSimSeed.normalize(move.name)
        guard let sec = BattleMoveEffects.secondaryEffects[key] else { return }
        if defender.activeAbility == "shield-dust" { return }
        if attacker.activeAbility == "sheer-force" { return }

        var chance = sec.chance
        if attacker.activeAbility == "serene-grace" { chance = min(100, chance * 2) }
        guard luck(Double(chance) / 100) else { return }

        // Burning Jealousy — only fires if the target had a positive stat stage.
        if sec.requiresTargetBoost {
            let anyBoost = defender.atkStage > 0 || defender.defStage > 0
                || defender.spAtkStage > 0 || defender.spDefStage > 0
                || defender.speedStage > 0
            if !anyBoost { return }
        }

        if let st = sec.status { tryInflictStatus(st, on: defender, inflicter: attacker) }
        if sec.flinch { setFlinch(defender) }
        for (stat, delta) in sec.targetDrops {
            applyOpposingStatDrop(to: defender, stat: stat, delta: delta)
        }
        // Tier 2 — self stat boosts from on-hit secondaries (Power-Up Punch,
        // Charge Beam, Flame Charge, Meteor Mash, …). Apply directly via
        // `changeStage` so they bypass opposing-drop ability checks; White
        // Herb consumption is irrelevant here since these are buffs.
        for (stat, delta) in sec.selfBoosts {
            changeStage(attacker, stat: stat, by: delta)
        }
        if let hz = sec.setsHazardOnFoe,
           let foeSide = findSideIndex(of: defender) {
            setHazard(hz, sideIdx: foeSide, moveName: move.name)
        }
        if sec.groundsTarget {
            defender.grounded = true
            log.append(BattleLogEntry(text: "\(defender.displayName) was knocked to the ground!"))
        }
        if sec.curesTargetBurn, defender.status == .burn {
            defender.status = .none
            log.append(BattleLogEntry(text: "\(defender.displayName)'s burn was healed!"))
        }
        if sec.saltCureVolatile, !defender.saltCured {
            defender.saltCured = true
            log.append(BattleLogEntry(text: "\(defender.displayName) is being salt-cured!"))
        }
    }

    /// Trigger Sitrus / Oran when HP drops to 1/2 or below. One-shot per battle.
    private func maybeTriggerHPBerry(for p: BattleParticipant) {
        guard !p.consumedItem, p.currentHP > 0 else { return }
        let hpFrac = Double(p.currentHP) / Double(max(p.maxHP, 1))
        switch p.effectiveHeldItem {
        case .sitrusBerry where hpFrac <= 0.5:
            let heal = max(1, p.maxHP / 4)
            p.currentHP = min(p.maxHP, p.currentHP + heal)
            p.consumedItem = true
            log.append(BattleLogEntry(text: "\(p.displayName) ate its Sitrus Berry! Restored HP."))
        case .oranBerry where hpFrac <= 0.5:
            let heal = 10
            p.currentHP = min(p.maxHP, p.currentHP + heal)
            p.consumedItem = true
            log.append(BattleLogEntry(text: "\(p.displayName) ate its Oran Berry! Restored 10 HP."))
        default:
            break
        }
    }

    // MARK: Status-move dispatch

    private func applyStatusMoveEffect(move: MoveData, attacker: BattleParticipant,
                                       attackerSideIdx: Int,
                                       defender: BattleParticipant?,
                                       defenderSideIdx: Int) {
        let key = BattleSimSeed.normalize(move.name)

        if let change = BattleMoveEffects.statChanges[key] {
            applyStatChange(change, attacker: attacker, defender: defender)
            return
        }
        if let status = BattleMoveEffects.statusInflicts[key] {
            if let d = defender {
                tryInflictStatus(status, on: d, inflicter: attacker)
            }
            return
        }
        if let w = BattleMoveEffects.weatherSetters[key] {
            setWeather(w, name: move.name)
            return
        }
        if let t = BattleMoveEffects.terrainSetters[key] {
            setTerrain(t, name: move.name)
            return
        }
        if let h = BattleMoveEffects.hazardSetters[key] {
            setHazard(h, sideIdx: defenderSideIdx, moveName: move.name)
            return
        }
        // Field rooms (Trick Room, Wonder Room, Magic Room, Gravity).
        if let room = BattleMoveEffects.roomSetters[key] {
            applyRoomSetter(room, moveName: move.name)
            return
        }
        // Screens + Safeguard land on the user's side.
        if let screen = BattleMoveEffects.screenSetters[key] {
            applyScreenSetter(screen, ownSideIdx: attackerSideIdx,
                              attacker: attacker, moveName: move.name)
            return
        }
        if key == BattleMoveEffects.tailwindKey {
            applyTailwind(ownSideIdx: attackerSideIdx, moveName: move.name)
            return
        }
        // Hazard removal — Defog/Tidy Up only reach this status-move path. The
        // foe side is always `1 - attackerSideIdx`, not the user's chosen
        // defender (Tidy Up targets self but still hits both sides). Rapid Spin
        // / Mortal Spin are damage moves and run their own post-damage hook.
        if let rm = BattleMoveEffects.hazardRemovers[key] {
            applyHazardRemoval(rm,
                               ownSideIdx: attackerSideIdx,
                               foeSideIdx: 1 - attackerSideIdx,
                               attacker: attacker, defender: defender)
            return
        }
        // Doubles utility moves (most are no-ops outside doubles; the helpers
        // log "But it failed!" themselves).
        if key == "helpinghand" {
            applyHelpingHand(ownSideIdx: attackerSideIdx,
                             slot: slotOf(attacker, side: attackerSideIdx),
                             attacker: attacker)
            return
        }
        if key == "followme" || key == "ragepowder" {
            applyRedirect(ownSideIdx: attackerSideIdx,
                          slot: slotOf(attacker, side: attackerSideIdx),
                          attacker: attacker, moveName: move.name)
            return
        }
        if key == "allyswitch" {
            applyAllySwitch(ownSideIdx: attackerSideIdx,
                            slot: slotOf(attacker, side: attackerSideIdx),
                            attacker: attacker)
            return
        }
        if key == "afteryou" {
            applyAfterYou(attacker: attacker)
            return
        }
        if key == "wideguard" {
            // Wide Guard is a one-turn side-shield against spread/multi-target moves.
            // Implemented as a per-side flag for the rest of this turn, mirrored on
            // the same side the user is on. Quick Guard uses the same pattern but
            // shields priority moves.
            applyWideOrQuickGuard(.wide, ownSideIdx: attackerSideIdx, attacker: attacker)
            return
        }
        if key == "quickguard" {
            applyWideOrQuickGuard(.quick, ownSideIdx: attackerSideIdx, attacker: attacker)
            return
        }
        // Protect family (Protect, Detect, Spiky Shield, Baneful Bunker, Burning
        // Bulwark, Silk Trap, King's Shield). Each succeeds with a diminishing
        // chance and sets `protectedThisTurn`. Contact penalties on the attacker
        // are applied during `applyDamageHit` when the hit is blocked.
        if BattleMoveEffects.protectFamily.contains(key) {
            applyProtectFamily(key, attacker: attacker, moveName: move.name)
            return
        }
        // Pivot moves (status side). Damage pivots go through `applyDamageHit`.
        if let kind = BattleMoveEffects.pivotMoves[key], kind == .force {
            applyStatusPivot(key, attacker: attacker,
                             attackerSideIdx: attackerSideIdx,
                             attackerSlot: slotOf(attacker, side: attackerSideIdx),
                             defender: defender)
            return
        }
        // Tier 3 — bespoke logic per move.
        if BattleMoveEffects.tier3StatusMoves.contains(key) {
            applyTier3StatusMove(key, attacker: attacker,
                                 attackerSideIdx: attackerSideIdx,
                                 defender: defender,
                                 defenderSideIdx: defenderSideIdx)
            return
        }
        // Tier 5 — niche status moves (item swap, sacrifice, force switch, …).
        if BattleMoveEffects.tier5StatusMoves.contains(key) {
            applyTier5StatusMove(key, attacker: attacker,
                                 attackerSideIdx: attackerSideIdx,
                                 defender: defender,
                                 defenderSideIdx: defenderSideIdx)
            return
        }
        // Taunt — Mental Herb on the target cures it the moment it's applied.
        if key == "taunt" {
            if let d = defender { applyTaunt(to: d) }
            return
        }
        // King's Shield used to be a no-op stub here; it now flows through the
        // protect-family dispatch above. Falling into this branch would mean a
        // newly-known protect-style move slipped past the set — fall through to
        // the generic "no simulated effect" log below in that case.
        // Perish Song — every active Pokemon on the field (both sides) gets a
        // 3-turn countdown. Soundproof blocks the effect. The countdown ticks
        // in `endOfTurnEffects` and faints the holder when it reaches zero.
        if key == "perishsong" {
            applyPerishSong()
            return
        }
        // Confusion-inflicting moves: Confuse Ray / Supersonic / Swagger / Flatter /
        // Teeter Dance. Swagger boosts target Atk +2 (Confused +2 user Atk is the joke);
        // Flatter boosts target SpAtk +1. Both then confuse the target. Persim/Lum
        // cure the new confusion immediately.
        if BattleMoveEffects.confusionInflicts.contains(key) {
            guard let d = defender else { return }
            if key == "swagger" {
                applyOpposingStatDrop(to: d, stat: .atk, delta: 2) // delta>0 = boost
            } else if key == "flatter" {
                applyOpposingStatDrop(to: d, stat: .spAtk, delta: 1)
            }
            tryInflictConfusion(on: d)
            return
        }
        // Self-heal status moves: Recover / Roost / Soft-Boiled / Synthesis /
        // Morning Sun / Moonlight / Slack Off / Milk Drink / Rest. `MoveData.healing`
        // is positive percent of max HP. Rest also sets sleep for 2 turns.
        if move.damageClass == "status", move.healing > 0 {
            if attacker.currentHP < attacker.maxHP {
                let heal = max(1, attacker.maxHP * move.healing / 100)
                attacker.currentHP = min(attacker.maxHP, attacker.currentHP + heal)
                log.append(BattleLogEntry(text: "\(attacker.displayName) restored HP!"))
            } else {
                log.append(BattleLogEntry(text: "\(attacker.displayName)'s HP is already full!"))
            }
            if key == "rest" {
                attacker.currentHP = attacker.maxHP
                attacker.status = .sleep
                attacker.sleepTurnsRemaining = 2
                attacker.toxicCounter = 0
                log.append(BattleLogEntry(text: "\(attacker.displayName) fell asleep and became healthy!"))
            }
            return
        }
        log.append(BattleLogEntry(text: "(\(move.name) had no simulated effect.)"))
    }

    private func applyStatChange(_ change: BattleStatChange,
                                 attacker: BattleParticipant,
                                 defender: BattleParticipant?) {
        switch change {
        case .selfMod(let mods):
            for (stat, delta) in mods {
                changeStage(attacker, stat: stat, by: delta)
            }
            log.append(BattleLogEntry(text: "\(attacker.displayName)'s stats changed!"))
            // Shell Smash etc. lower defensive stats on top of the offensive boost;
            // White Herb fixes those drops.
            consumeWhiteHerbIfNeeded(attacker)
        case .opponentMod(let mods):
            guard let d = defender else { return }
            // Drops from the attacker flow through opposing-drop logic so guard
            // abilities (Clear Body, Hyper Cutter, ...) and reactive abilities
            // (Defiant, Competitive) trigger the same way they do off Intimidate.
            // `applyOpposingStatDrop` consumes White Herb internally.
            for (stat, delta) in mods {
                applyOpposingStatDrop(to: d, stat: stat, delta: delta)
            }
            log.append(BattleLogEntry(text: "\(d.displayName)'s stats changed!"))
        }
    }

    private func changeStage(_ p: BattleParticipant, stat: Nature.StatKey, by delta: Int) {
        switch stat {
        case .atk:   p.atkStage   = max(-6, min(6, p.atkStage + delta))
        case .def:   p.defStage   = max(-6, min(6, p.defStage + delta))
        case .spAtk: p.spAtkStage = max(-6, min(6, p.spAtkStage + delta))
        case .spDef: p.spDefStage = max(-6, min(6, p.spDefStage + delta))
        case .speed: p.speedStage = max(-6, min(6, p.speedStage + delta))
        }
    }

    private func tryInflictStatus(_ status: BattleStatus,
                                  on target: BattleParticipant,
                                  inflicter: BattleParticipant? = nil) {
        guard target.status == .none else {
            log.append(BattleLogEntry(text: "But \(target.displayName) already has a status condition!"))
            return
        }
        guard canApplyStatus(status, to: target) else {
            log.append(BattleLogEntry(text: "It had no effect on \(target.displayName)."))
            return
        }
        target.status = status
        if status == .sleep {
            target.sleepTurnsRemaining = Int.random(in: 1...3)
        }
        if status == .toxic {
            target.toxicCounter = 0
        }
        log.append(BattleLogEntry(text: "\(target.displayName) was afflicted with \(status.shortLabel)!"))

        // Status-curing berry kicks in immediately if the holder has the right berry.
        maybeTriggerStatusBerry(for: target)

        // Synchronize — burn, poison, toxic, and paralysis bounce back to the
        // inflicter. Sleep and freeze do not (canon). We only fire when there's
        // a distinct inflicter (no self-status, no toxic-spikes hazard).
        if let src = inflicter, src !== target,
           target.activeAbility == "synchronize",
           status == .burn || status == .poison || status == .toxic || status == .paralysis {
            log.append(BattleLogEntry(text: "\(target.displayName)'s Synchronize sent the status back!"))
            // Use a nil inflicter on the return-trip so we don't bounce again.
            tryInflictStatus(status, on: src, inflicter: nil)
        }
    }

    /// Confusion volatile inflict (Confuse Ray / Supersonic / Swagger / Flatter /
    /// Teeter Dance). Lasts 1-4 turns. Lum / Persim Berry cures immediately.
    private func tryInflictConfusion(on target: BattleParticipant) {
        if target.confused {
            log.append(BattleLogEntry(text: "But \(target.displayName) is already confused!"))
            return
        }
        target.confused = true
        target.confusionTurnsRemaining = Int.random(in: 2...5) // ticks on the holder's
        // next move, so 2-5 raw → 1-4 effective turns of confusion (matches Gen V+).
        log.append(BattleLogEntry(text: "\(target.displayName) became confused!"))
        maybeTriggerConfusionBerry(for: target)
    }

    /// Lum and Persim cure confusion immediately on application. Mirrors the
    /// status-berry shape so the engine doesn't keep the volatile around for one
    /// wasted turn.
    private func maybeTriggerConfusionBerry(for p: BattleParticipant) {
        guard !p.consumedItem, p.confused else { return }
        let item = p.effectiveHeldItem
        let cures: Bool
        switch item {
        case .lumBerry, .persimBerry: cures = true
        default:                      cures = false
        }
        guard cures else { return }
        p.confused = false
        p.confusionTurnsRemaining = 0
        p.consumedItem = true
        log.append(BattleLogEntry(text: "\(p.displayName) ate its \(item.rawValue), curing confusion."))
    }

    /// Taunt volatile inflict. Mental Herb on the target cures Taunt immediately.
    /// 3 turns matches Gen V+ canon.
    private func applyTaunt(to target: BattleParticipant) {
        if target.tauntTurnsRemaining > 0 {
            log.append(BattleLogEntry(text: "But \(target.displayName) is already taunted!"))
            return
        }
        target.tauntTurnsRemaining = 3
        log.append(BattleLogEntry(text: "\(target.displayName) fell for the taunt!"))
        maybeTriggerMentalHerb(for: target)
    }

    /// Mental Herb cures Taunt (and, in canon, Encore/Disable/Torment/Heal Block —
    /// none of which the engine simulates yet). Auto-consumed on trigger.
    private func maybeTriggerMentalHerb(for p: BattleParticipant) {
        guard !p.consumedItem, p.effectiveHeldItem == .mentalHerb else { return }
        guard p.tauntTurnsRemaining > 0 else { return }
        p.tauntTurnsRemaining = 0
        p.consumedItem = true
        log.append(BattleLogEntry(text: "\(p.displayName) ate its Mental Herb, shaking off the taunt!"))
    }

    /// Leppa Berry restores 10 PP to a move that just hit zero. Auto-consumed.
    /// Caps the restore at the move's max PP. Returns true if the berry triggered
    /// so the caller can log it.
    @discardableResult
    private func maybeTriggerLeppaBerry(for p: BattleParticipant, moveIndex: Int) -> Bool {
        guard !p.consumedItem, p.effectiveHeldItem == .leppaBerry else { return false }
        guard p.pp.indices.contains(moveIndex), p.pp[moveIndex] == 0 else { return false }
        guard p.moves.indices.contains(moveIndex) else { return false }
        let maxPP = p.moves[moveIndex].pp
        p.pp[moveIndex] = min(maxPP, 10)
        p.consumedItem = true
        log.append(BattleLogEntry(text: "\(p.displayName) ate its Leppa Berry! Restored PP for \(p.moves[moveIndex].name)."))
        return true
    }

    /// Consume Lum / Cheri / Chesto / Pecha / Rawst / Aspear when the holder picks
    /// up the matching status, clearing the status the same turn it was inflicted.
    private func maybeTriggerStatusBerry(for p: BattleParticipant) {
        guard !p.consumedItem, p.status != .none else { return }
        let item = p.effectiveHeldItem
        let cures: Bool
        switch item {
        case .lumBerry:    cures = true
        case .cheriBerry:  cures = p.status == .paralysis
        case .chestoBerry: cures = p.status == .sleep
        case .pechaBerry:  cures = p.status == .poison || p.status == .toxic
        case .rawstBerry:  cures = p.status == .burn
        case .aspearBerry: cures = p.status == .freeze
        default:           cures = false
        }
        guard cures else { return }
        let prior = p.status
        p.status = .none
        p.toxicCounter = 0
        p.sleepTurnsRemaining = 0
        p.consumedItem = true
        log.append(BattleLogEntry(text: "\(p.displayName) ate its \(item.rawValue), curing \(prior.shortLabel)."))
    }

    private func canApplyStatus(_ status: BattleStatus, to target: BattleParticipant) -> Bool {
        // Safeguard on the target's side blocks all new major status conditions.
        // Doesn't cure existing status (Rest works around this; we ignore it).
        if let sIdx = findSideIndex(of: target), side(at: sIdx).safeguardTurns > 0 {
            return false
        }
        let t = target.types
        switch status {
        case .burn:      return !t.contains("Fire")
        case .paralysis: return !t.contains("Electric")
        case .poison, .toxic: return !t.contains("Poison") && !t.contains("Steel")
        case .sleep:     return true
        case .freeze:    return !t.contains("Ice")
        case .none:      return false
        }
    }

    /// Return the side index (0 or 1) that currently owns `p` as an active
    /// Pokemon, or nil if it's not active on either side.
    private func findSideIndex(of p: BattleParticipant) -> Int? {
        for s in 0..<2 {
            for slot in 0..<format.activeSlots {
                if side(at: s).active(at: slot) === p { return s }
            }
        }
        return nil
    }

    private func setWeather(_ w: WeatherCondition, name: String) {
        weather = w
        weatherTurns = 5
        log.append(BattleLogEntry(text: "\(name): the weather is now \(w.rawValue)."))
        // Ice Face — Eiscue restores its Ice form when snow weather starts.
        if w == .snow {
            for s in 0..<2 {
                for slot in 0..<format.activeSlots {
                    if let p = side(at: s).active(at: slot),
                       p.activeAbility == "ice-face", !p.iceFaceIntact {
                        p.iceFaceIntact = true
                        log.append(BattleLogEntry(text: "\(p.displayName)'s Ice Face was restored!"))
                    }
                }
            }
        }
    }

    private func setTerrain(_ t: TerrainCondition, name: String) {
        terrain = t
        terrainTurns = 5
        log.append(BattleLogEntry(text: "\(name): the terrain is now \(t.rawValue)."))
    }

    /// Fires the participant's on-entry ability effects: weather/terrain setters and
    /// Intimidate. Called on initial send-out, after a regular or forced switch, and
    /// after Mega Evolution. Uses `activeAbility` so post-Mega abilities (Drought from
    /// Mega Charizard Y, Sand Stream from Mega Tyranitar, Intimidate from Mega
    /// Manectric, etc.) also trigger correctly.
    private func activateEntryAbility(for p: BattleParticipant, ownSide: Int) {
        guard let ability = p.activeAbility else { return }

        if let w = BattleMoveEffects.weatherAbilities[ability], weather != w {
            weather = w
            weatherTurns = 5
            log.append(BattleLogEntry(text: "\(p.displayName)'s \(formatAbilityName(ability)) set the weather to \(w.rawValue)!"))
        }
        if let t = BattleMoveEffects.terrainAbilities[ability], terrain != t {
            terrain = t
            terrainTurns = 5
            log.append(BattleLogEntry(text: "\(p.displayName)'s \(formatAbilityName(ability)) set \(t.rawValue) Terrain!"))
        }
        if ability == "intimidate" {
            applyIntimidate(from: p, ownSide: ownSide)
        }
        if ability == "trace" {
            applyTrace(from: p, ownSide: ownSide)
        }
        if ability == "frisk" {
            // Log every opposing active mon's held item. Common in singles too
            // (Gen V+ shows all opposing items at once).
            let oppSide = side(at: 1 - ownSide)
            for slot in 0..<format.activeSlots {
                guard let t = oppSide.active(at: slot), !t.fainted else { continue }
                if t.heldItem != .none {
                    log.append(BattleLogEntry(text: "\(p.displayName)'s Frisk spotted \(t.displayName)'s \(t.heldItem.rawValue)!"))
                }
            }
        }
        if ability == "imposter" {
            applyImposter(from: p, ownSide: ownSide)
        }
    }

    /// Imposter — Ditto's signature ability. On entry, copy the slot-0
    /// opponent's stats, types, ability, and (notionally) moves. HP and item
    /// stay the user's. Tier 6 doesn't copy move slots (the engine binds
    /// MoveData to the team slot at build time, which would require deeper
    /// surgery); the visible "transform" + stat copy covers the main use.
    private func applyImposter(from p: BattleParticipant, ownSide: Int) {
        let oppSide = side(at: 1 - ownSide)
        // Pick slot 0 in canon; if it's fainted, fall through to slot 1.
        var target: BattleParticipant?
        for slot in 0..<format.activeSlots {
            if let t = oppSide.active(at: slot), !t.fainted { target = t; break }
        }
        guard let t = target else { return }
        // Don't recursively copy an Imposter that copied us.
        if t.imposterSnapshot != nil { return }
        p.imposterSnapshot = BattleParticipant.ImposterSnapshot(
            displayName: "\(p.slot.pokemonName) (\(t.displayName))",
            type1: t.activeType1, type2: t.activeType2,
            baseAtk: t.baseAtk, baseDef: t.baseDef,
            baseSpAtk: t.baseSpAtk, baseSpDef: t.baseSpDef,
            baseSpeed: t.baseSpeed,
            ability: t.activeAbility
        )
        // Imposter also copies the target's current stat stages (canon).
        p.atkStage = t.atkStage
        p.defStage = t.defStage
        p.spAtkStage = t.spAtkStage
        p.spDefStage = t.spDefStage
        p.speedStage = t.speedStage
        log.append(BattleLogEntry(text: "\(p.slot.pokemonName) transformed into \(t.displayName)!"))
    }

    /// Trace — copy the ability of a random opposing active Pokemon. The copy
    /// lasts until the holder switches out. Some abilities are explicitly
    /// uncopyable (form-change / signature abilities) and Trace simply doesn't
    /// fire on those targets.
    private func applyTrace(from p: BattleParticipant, ownSide: Int) {
        let untraceable: Set<String> = [
            "trace", "stance-change", "disguise", "battle-bond", "schooling",
            "zen-mode", "comatose", "rks-system", "shields-down", "ice-face",
            "multitype", "power-construct", "flower-gift", "zero-to-hero",
            "hunger-switch", "neutralizing-gas",
        ]
        let oppSide = side(at: 1 - ownSide)
        let candidates = (0..<format.activeSlots).compactMap { oppSide.active(at: $0) }
            .filter { !$0.fainted }
            .compactMap { $0.activeAbility }
            .filter { !untraceable.contains($0) }
        guard let chosen = candidates.randomElement() else { return }
        p.tracedAbility = chosen
        log.append(BattleLogEntry(text: "\(p.displayName)'s Trace copied \(formatAbilityName(chosen))!"))
    }

    // MARK: Stat Drops & Reactive Abilities

    /// Reads the current stage for a given stat. Used to detect whether an opposing
    /// drop actually moved the needle (e.g. -1 against a stat already at -6 is a no-op,
    /// and should NOT trigger Defiant/Competitive).
    private func currentStage(of p: BattleParticipant, stat: Nature.StatKey) -> Int {
        switch stat {
        case .atk:   return p.atkStage
        case .def:   return p.defStage
        case .spAtk: return p.spAtkStage
        case .spDef: return p.spDefStage
        case .speed: return p.speedStage
        }
    }

    /// Applies a stat change to `target` coming from an *opposing* source (Intimidate
    /// switch-in, Growl, Leer, Screech, etc.). Negative deltas pass through guard
    /// abilities (Clear Body, Hyper Cutter, ...) and trigger reactive abilities
    /// (Defiant, Competitive) when a drop succeeds. Non-negative deltas pass through
    /// unchanged.
    @discardableResult
    private func applyOpposingStatDrop(to target: BattleParticipant,
                                       stat: Nature.StatKey,
                                       delta: Int) -> Bool {
        guard delta < 0 else {
            changeStage(target, stat: stat, by: delta)
            return true
        }

        if let ability = target.activeAbility {
            let blanketBlockers: Set<String> = ["clear-body", "white-smoke", "full-metal-body"]
            if blanketBlockers.contains(ability) {
                log.append(BattleLogEntry(text: "\(target.displayName)'s \(formatAbilityName(ability)) prevented the stat drop!"))
                return false
            }
            if ability == "hyper-cutter" && stat == .atk {
                log.append(BattleLogEntry(text: "\(target.displayName)'s Hyper Cutter prevented the Attack drop!"))
                return false
            }
            if ability == "big-pecks" && stat == .def {
                log.append(BattleLogEntry(text: "\(target.displayName)'s Big Pecks prevented the Defense drop!"))
                return false
            }
        }

        let before = currentStage(of: target, stat: stat)
        changeStage(target, stat: stat, by: delta)
        let after = currentStage(of: target, stat: stat)
        // No reactive trigger if the stat was already at -6 (clamped to no change).
        guard after < before else { return false }

        if let ability = target.activeAbility {
            switch ability {
            case "defiant":
                changeStage(target, stat: .atk, by: 2)
                log.append(BattleLogEntry(text: "\(target.displayName)'s Defiant sharply raised its Attack!"))
            case "competitive":
                changeStage(target, stat: .spAtk, by: 2)
                log.append(BattleLogEntry(text: "\(target.displayName)'s Competitive sharply raised its Sp. Atk!"))
            default:
                break
            }
        }

        // White Herb fires after reactive boosts so it cleans up only the residual
        // drops (e.g. -1 Atk from Intimidate when no Defiant pushed it back up).
        consumeWhiteHerbIfNeeded(target)
        return true
    }

    /// White Herb resets every negative stat stage to 0 the moment any of them are
    /// negative. Consumed after firing. Real-game behavior — Shell Smash users carry
    /// White Herb to undo the −1 Def/SpDef penalty.
    private func consumeWhiteHerbIfNeeded(_ p: BattleParticipant) {
        guard !p.consumedItem, p.effectiveHeldItem == .whiteHerb else { return }
        let stages = [p.atkStage, p.defStage, p.spAtkStage, p.spDefStage, p.speedStage]
        guard stages.contains(where: { $0 < 0 }) else { return }
        if p.atkStage   < 0 { p.atkStage   = 0 }
        if p.defStage   < 0 { p.defStage   = 0 }
        if p.spAtkStage < 0 { p.spAtkStage = 0 }
        if p.spDefStage < 0 { p.spDefStage = 0 }
        if p.speedStage < 0 { p.speedStage = 0 }
        p.consumedItem = true
        log.append(BattleLogEntry(text: "\(p.displayName) restored its stats with its White Herb!"))
    }

    /// Intimidate's on-entry effect: lowers each opposing active Pokemon's Attack by
    /// one stage. Respects the Gen 8+ Intimidate-only immunities (Inner Focus,
    /// Oblivious, Own Tempo, Scrappy) plus the blanket guard abilities and reactive
    /// boosts handled by `applyOpposingStatDrop`.
    private func applyIntimidate(from source: BattleParticipant, ownSide: Int) {
        let oppSide = side(at: 1 - ownSide)
        log.append(BattleLogEntry(text: "\(source.displayName)'s Intimidate kicks in!"))
        let intimImmune: Set<String> = ["inner-focus", "oblivious", "own-tempo", "scrappy"]
        for slot in 0..<format.activeSlots {
            guard let target = oppSide.active(at: slot), !target.fainted else { continue }
            if let ability = target.activeAbility, intimImmune.contains(ability) {
                log.append(BattleLogEntry(text: "\(target.displayName)'s \(formatAbilityName(ability)) shrugged off Intimidate!"))
                continue
            }
            applyOpposingStatDrop(to: target, stat: .atk, delta: -1)
        }
    }

    private func setHazard(_ h: BattleHazard, sideIdx: Int, moveName: String) {
        let s = side(at: sideIdx)
        switch h {
        case .stealthRock:
            if s.stealthRock {
                log.append(BattleLogEntry(text: "Stealth Rock is already set on \(s.label)'s field."))
                return
            }
            s.stealthRock = true
        case .spikes:
            if s.spikesLayers >= 3 {
                log.append(BattleLogEntry(text: "Spikes are already at max on \(s.label)'s field."))
                return
            }
            s.spikesLayers += 1
        case .stickyWeb:
            if s.stickyWeb {
                log.append(BattleLogEntry(text: "Sticky Web is already set on \(s.label)'s field."))
                return
            }
            s.stickyWeb = true
        case .toxicSpikes:
            if s.toxicSpikesLayers >= 2 {
                log.append(BattleLogEntry(text: "Toxic Spikes are already at max on \(s.label)'s field."))
                return
            }
            s.toxicSpikesLayers += 1
        }
        log.append(BattleLogEntry(text: "\(moveName) set hazards on \(s.label)'s field."))
    }

    // MARK: Field & Side Effects (Tier 1 — rooms, screens, tailwind, safeguard)

    /// Apply a global room/field effect (Trick Room, Wonder Room, Magic Room,
    /// Gravity). Re-using the move while the effect is already active toggles
    /// it back off — that's the canon "Trick Room twice cancels Trick Room"
    /// behavior.
    private func applyRoomSetter(_ kind: BattleMoveEffects.RoomKind, moveName: String) {
        switch kind {
        case .trickRoom:
            if trickRoomTurns > 0 {
                trickRoomTurns = 0
                log.append(BattleLogEntry(text: "The twisted dimensions returned to normal!"))
            } else {
                trickRoomTurns = 5
                log.append(BattleLogEntry(text: "\(moveName) twisted the dimensions!"))
            }
        case .wonderRoom:
            if wonderRoomTurns > 0 {
                wonderRoomTurns = 0
                log.append(BattleLogEntry(text: "Wonder Room wore off."))
            } else {
                wonderRoomTurns = 5
                log.append(BattleLogEntry(text: "Wonder Room swapped Defense and Sp.Def!"))
            }
        case .magicRoom:
            if magicRoomTurns > 0 {
                magicRoomTurns = 0
                log.append(BattleLogEntry(text: "Magic Room wore off."))
            } else {
                magicRoomTurns = 5
                log.append(BattleLogEntry(text: "Magic Room suppressed all held items!"))
            }
        case .gravity:
            if gravityTurns > 0 {
                log.append(BattleLogEntry(text: "Gravity is already intensified."))
            } else {
                gravityTurns = 5
                log.append(BattleLogEntry(text: "Gravity intensified! Flying-types and Levitate were grounded."))
                // Ground every active Pokemon for the duration. The grounded
                // flag is cleared when gravity expires.
                for s in 0..<2 {
                    for slot in 0..<format.activeSlots {
                        side(at: s).active(at: slot)?.grounded = true
                    }
                }
            }
        }
    }

    /// Set a screen / Safeguard on the user's side. Light Clay extends the
    /// screen duration to 8 turns. Aurora Veil requires hail/snow weather to
    /// even start; fizzles otherwise.
    private func applyScreenSetter(_ kind: BattleMoveEffects.ScreenKind,
                                   ownSideIdx: Int, attacker: BattleParticipant,
                                   moveName: String) {
        let s = side(at: ownSideIdx)
        let baseTurns = attacker.effectiveHeldItem == .lightClay ? 8 : 5
        switch kind {
        case .light:
            if s.lightScreenTurns > 0 {
                log.append(BattleLogEntry(text: "Light Screen is already up on \(s.label)'s side."))
                return
            }
            s.lightScreenTurns = baseTurns
            log.append(BattleLogEntry(text: "\(moveName) raised the Special-side wall on \(s.label)!"))
        case .reflect:
            if s.reflectTurns > 0 {
                log.append(BattleLogEntry(text: "Reflect is already up on \(s.label)'s side."))
                return
            }
            s.reflectTurns = baseTurns
            log.append(BattleLogEntry(text: "\(moveName) raised the Physical-side wall on \(s.label)!"))
        case .aurora:
            // Aurora Veil only succeeds if the weather is snow/hail when used.
            // Light Clay extends to 8 turns once up.
            guard weather == .snow else {
                log.append(BattleLogEntry(text: "But it failed! Aurora Veil needs snow."))
                return
            }
            if s.auroraVeilTurns > 0 {
                log.append(BattleLogEntry(text: "Aurora Veil is already up on \(s.label)'s side."))
                return
            }
            s.auroraVeilTurns = baseTurns
            log.append(BattleLogEntry(text: "\(moveName) shielded \(s.label) from damage!"))
        case .safeguard:
            if s.safeguardTurns > 0 {
                log.append(BattleLogEntry(text: "Safeguard is already up on \(s.label)'s side."))
                return
            }
            s.safeguardTurns = 5
            log.append(BattleLogEntry(text: "\(s.label) is veiled in a mystical aura!"))
        }
    }

    private func applyTailwind(ownSideIdx: Int, moveName: String) {
        let s = side(at: ownSideIdx)
        if s.tailwindTurns > 0 {
            log.append(BattleLogEntry(text: "Tailwind is already blowing on \(s.label)'s side."))
            return
        }
        s.tailwindTurns = 4
        log.append(BattleLogEntry(text: "\(moveName) whipped up a tailwind on \(s.label)!"))
    }

    /// Roll the Protect-family success and, on hit, set `protectedThisTurn`.
    /// Each successive turn the user picks a protect move the chance halves
    /// (100, 50, 25, …). On a failed roll we DON'T set the flag and the move
    /// still consumes the turn; we also reset the streak so the next attempt
    /// starts fresh. Wide/Quick Guard share their own counters because they
    /// behave differently in canon — Tier 1 treats them as one-off moves that
    /// don't share the protect streak (simplification, but rarely matters in
    /// practice).
    private func applyProtectFamily(_ key: String, attacker: BattleParticipant,
                                    moveName: String) {
        let denom = 1 << max(0, attacker.consecutiveProtectCount)
        let chance = 100 / denom
        if Int.random(in: 1...100) > chance {
            log.append(BattleLogEntry(text: "But it failed!"))
            attacker.consecutiveProtectCount = 0
            return
        }
        attacker.protectedThisTurn = true
        attacker.lastProtectKey = key
        attacker.consecutiveProtectCount = min(attacker.consecutiveProtectCount + 1, 4)
        // Stance Change — King's Shield reverts Aegislash to Shield Forme as part
        // of bracing. The flip is also driven by `maybeApplyStanceChange`; keeping
        // it explicit here documents the canon timing.
        if key == "kingsshield", attacker.activeAbility == "stance-change" {
            attacker.stanceForm = .aegislashShield
        }
        log.append(BattleLogEntry(text: "\(attacker.displayName) protected itself with \(moveName)!"))
    }

    // MARK: Doubles utility moves (Helping Hand, Follow Me, Rage Powder, Ally Switch, After You, Wide/Quick Guard)

    /// True when the format is doubles AND the user has a live partner. Most
    /// double-only moves silently no-op outside this state.
    private func hasLivePartner(side s: Int, slot: Int) -> Bool {
        guard format.activeSlots >= 2 else { return false }
        let other = 1 - slot
        return side(at: s).active(at: other) != nil
    }

    /// Return the active slot index of `p` on side `s`. Used by helpers that
    /// only get a participant reference but need to know its slot (Helping
    /// Hand targets the partner, redirection points at the user, etc.).
    /// Returns 0 if not found — callers should never get here in practice
    /// because the participant came from `active(at:)`.
    private func slotOf(_ p: BattleParticipant, side s: Int) -> Int {
        let theSide = side(at: s)
        for i in 0..<format.activeSlots {
            if theSide.active(at: i) === p { return i }
        }
        return 0
    }

    enum GuardKind { case wide, quick }
    private func applyWideOrQuickGuard(_ kind: GuardKind, ownSideIdx: Int,
                                       attacker: BattleParticipant) {
        let s = side(at: ownSideIdx)
        // Diminishing chance for the user (shared with Protect streak — Wide/
        // Quick Guard count toward the streak in canon).
        let denom = 1 << max(0, attacker.consecutiveProtectCount)
        if Int.random(in: 1...100) > 100 / denom {
            attacker.consecutiveProtectCount = 0
            log.append(BattleLogEntry(text: "But it failed!"))
            return
        }
        attacker.consecutiveProtectCount = min(attacker.consecutiveProtectCount + 1, 4)
        switch kind {
        case .wide:
            s.wideGuardActive = true
            log.append(BattleLogEntry(text: "\(s.label) braced against wide attacks!"))
        case .quick:
            s.quickGuardActive = true
            log.append(BattleLogEntry(text: "\(s.label) braced against priority attacks!"))
        }
    }

    private func applyHelpingHand(ownSideIdx: Int, slot: Int, attacker: BattleParticipant) {
        guard hasLivePartner(side: ownSideIdx, slot: slot) else {
            log.append(BattleLogEntry(text: "But it failed!"))
            return
        }
        let partnerSlot = 1 - slot
        let s = side(at: ownSideIdx)
        if partnerSlot < s.helpingHandPending.count {
            s.helpingHandPending[partnerSlot] = true
        }
        if let partner = s.active(at: partnerSlot) {
            log.append(BattleLogEntry(text: "\(attacker.displayName) is rooting for \(partner.displayName)!"))
        }
    }

    private func applyRedirect(ownSideIdx: Int, slot: Int, attacker: BattleParticipant,
                               moveName: String) {
        let s = side(at: ownSideIdx)
        s.redirectionTargetSlot = slot
        log.append(BattleLogEntry(text: "\(attacker.displayName) drew attention with \(moveName)!"))
    }

    private func applyAllySwitch(ownSideIdx: Int, slot: Int, attacker: BattleParticipant) {
        guard hasLivePartner(side: ownSideIdx, slot: slot) else {
            log.append(BattleLogEntry(text: "But it failed!"))
            return
        }
        let s = side(at: ownSideIdx)
        let partnerSlot = 1 - slot
        // Swap the indices into activeIndices — this physically swaps which
        // participant occupies each slot. Volatiles, stat stages, and HP all
        // travel with the participant (since we're swapping the index, not the
        // values), so no extra bookkeeping is needed.
        let tmp = s.activeIndices[slot]
        s.activeIndices[slot] = s.activeIndices[partnerSlot]
        s.activeIndices[partnerSlot] = tmp
        log.append(BattleLogEntry(text: "\(attacker.displayName) and its partner switched places!"))
    }

    /// After You — re-orders the action queue so a chosen partner moves next.
    /// In this simulator's flow, actions are sorted once at the top of the turn
    /// and dispatched in order; we don't currently re-sort mid-turn. After You
    /// therefore just logs and no-ops cleanly. Wiring it fully would require an
    /// action-priority bump system. Acknowledged limitation for Tier 1.
    private func applyAfterYou(attacker: BattleParticipant) {
        log.append(BattleLogEntry(text: "\(attacker.displayName) said \"After you.\""))
    }

    // MARK: Hazard removal (Defog / Rapid Spin / Mortal Spin / Tidy Up)

    private func applyHazardRemoval(_ kind: BattleMoveEffects.HazardRemoval,
                                    ownSideIdx: Int, foeSideIdx: Int,
                                    attacker: BattleParticipant, defender: BattleParticipant?) {
        let own = side(at: ownSideIdx)
        let foe = side(at: foeSideIdx)
        switch kind {
        case .ownSide:
            clearHazards(on: own, label: "user's")
        case .bothSides:
            // Defog clears hazards on BOTH sides + screens on BOTH sides + drops
            // the target's evasion by one stage.
            clearHazards(on: own, label: "both")
            clearHazards(on: foe, label: "both")
            clearScreens(on: own); clearScreens(on: foe)
            if let d = defender {
                applyOpposingStatDrop(to: d, stat: .speed, delta: 0) // no-op tag for the log below
                log.append(BattleLogEntry(text: "\(attacker.displayName)'s Defog blew the field clean!"))
            }
        case .tidyUp:
            clearHazards(on: own, label: "both"); clearHazards(on: foe, label: "both")
            clearScreens(on: own); clearScreens(on: foe)
            changeStage(attacker, stat: .atk, by: 1)
            changeStage(attacker, stat: .speed, by: 1)
            log.append(BattleLogEntry(text: "\(attacker.displayName) tidied up the field!"))
        case .mortalSpin:
            clearHazards(on: own, label: "user's")
            // Poison every live opposing active Pokemon.
            for s in 0..<format.activeSlots {
                if let target = side(at: foeSideIdx).active(at: s), !target.fainted {
                    tryInflictStatus(.poison, on: target)
                }
            }
        }
    }

    private func clearHazards(on s: BattleSide, label: String) {
        var cleared: [String] = []
        if s.stealthRock { cleared.append("Stealth Rock"); s.stealthRock = false }
        if s.spikesLayers > 0 { cleared.append("Spikes"); s.spikesLayers = 0 }
        if s.toxicSpikesLayers > 0 { cleared.append("Toxic Spikes"); s.toxicSpikesLayers = 0 }
        if s.stickyWeb { cleared.append("Sticky Web"); s.stickyWeb = false }
        if !cleared.isEmpty {
            log.append(BattleLogEntry(text: "\(cleared.joined(separator: ", ")) was blown away from \(s.label)'s side."))
        }
    }

    private func clearScreens(on s: BattleSide) {
        if s.lightScreenTurns > 0 || s.reflectTurns > 0 || s.auroraVeilTurns > 0 {
            s.lightScreenTurns = 0; s.reflectTurns = 0; s.auroraVeilTurns = 0
            log.append(BattleLogEntry(text: "Screens on \(s.label)'s side were removed!"))
        }
    }

    // MARK: Pivot moves

    /// Status-class pivot moves: apply their secondary, then queue a force-switch
    /// for the user. Damage pivots (U-turn, Volt Switch, Flip Turn) go through
    /// `maybeQueuePivotSwitch` after `applyDamageHit`.
    private func applyStatusPivot(_ key: String, attacker: BattleParticipant,
                                  attackerSideIdx: Int, attackerSlot: Int,
                                  defender: BattleParticipant?) {
        switch key {
        case "partingshot":
            if let d = defender {
                applyOpposingStatDrop(to: d, stat: .atk, delta: -1)
                applyOpposingStatDrop(to: d, stat: .spAtk, delta: -1)
            }
        case "chillyreception":
            setWeather(.snow, name: "Chilly Reception")
        case "teleport", "batonpass", "shedtail":
            // Pure pivots — no pre-switch side effect in this simulator. Shed
            // Tail's Substitute donation isn't modeled (Tier 5 — Substitute is
            // itself unwired).
            break
        default:
            break
        }
        queuePivotSwitch(side: attackerSideIdx, slot: attackerSlot, attacker: attacker)
    }

    /// Apply the Protect-family contact penalty when an incoming contact move
    /// is blocked. Each variant fires its hallmark side effect on the attacker.
    /// Non-contact moves are unaffected; the defender's identity (King's Shield
    /// is unique to Aegislash, Spiky Shield to Chesnaught/Decidueye, etc.) is
    /// inferred from the move name the defender used. We can't read that move
    /// directly here since the defender already resolved its action, so we
    /// stash the last-used protect-family key in `consecutiveProtectCount`'s
    /// sibling field — simpler: store the move key when applyProtectFamily fires.
    private func applyProtectContactPenalty(attacker: BattleParticipant,
                                            defender: BattleParticipant,
                                            move: MoveData) {
        guard isContactMove(move) else { return }
        switch defender.lastProtectKey {
        case "spikyshield":
            let chip = max(1, attacker.maxHP / 8)
            attacker.currentHP = max(0, attacker.currentHP - chip)
            log.append(BattleLogEntry(text: "\(attacker.displayName) was hurt by Spiky Shield! (-\(chip) HP)"))
        case "banefulbunker":
            tryInflictStatus(.poison, on: attacker)
        case "burningbulwark":
            tryInflictStatus(.burn, on: attacker)
        case "silktrap":
            applyOpposingStatDrop(to: attacker, stat: .speed, delta: -1)
        case "kingsshield":
            applyOpposingStatDrop(to: attacker, stat: .atk, delta: -1)
        default:
            break
        }
    }

    /// Called from `applyDamageHit` for damage pivots, and from `applyStatusPivot`
    /// for status pivots. Adds the attacker to the force-switch queue so the
    /// engine surfaces a switch prompt next.
    private func queuePivotSwitch(side: Int, slot: Int, attacker: BattleParticipant) {
        // Don't queue if the user fainted (e.g. Life Orb recoil killed them) or
        // there's nothing on the bench to swap to.
        if attacker.fainted { return }
        let s = self.side(at: side)
        if s.benchIndices().isEmpty {
            log.append(BattleLogEntry(text: "But \(attacker.displayName) had no one to switch to!"))
            return
        }
        // Avoid duplicate entries — a single move can only trigger one switch.
        if pendingForceSwitches.contains(where: { $0.side == side && $0.slot == slot }) { return }
        pendingForceSwitches.append(ForceSwitch(side: side, slot: slot))
        log.append(BattleLogEntry(text: "\(attacker.displayName) is coming back!"))
    }

    // MARK: Tier 3 — bespoke status-move logic

    private func applyTier3StatusMove(_ key: String,
                                      attacker: BattleParticipant,
                                      attackerSideIdx: Int,
                                      defender: BattleParticipant?,
                                      defenderSideIdx: Int) {
        switch key {
        case "painsplit":
            guard let d = defender else { return }
            let avg = (attacker.currentHP + d.currentHP) / 2
            attacker.currentHP = min(attacker.maxHP, avg)
            d.currentHP = min(d.maxHP, avg)
            log.append(BattleLogEntry(text: "\(attacker.displayName) and \(d.displayName) split their HP!"))

        case "healpulse":
            guard let d = defender else { return }
            // 50% maxHP heal on target. Mega Launcher boosts to 75%.
            let pct = attacker.activeAbility == "mega-launcher" ? 75 : 50
            let heal = max(1, d.maxHP * pct / 100)
            if d.currentHP < d.maxHP {
                d.currentHP = min(d.maxHP, d.currentHP + heal)
                log.append(BattleLogEntry(text: "\(d.displayName) was healed by Heal Pulse!"))
            } else {
                log.append(BattleLogEntry(text: "But \(d.displayName) was already at full HP!"))
            }

        case "lifedew":
            // Heal user (and ally in doubles) for 25% maxHP. Damaging-class in canon
            // but our MoveData routes it as status — treat as a status group heal.
            let s = side(at: attackerSideIdx)
            for slot in 0..<format.activeSlots {
                if let p = s.active(at: slot), !p.fainted, p.currentHP < p.maxHP {
                    let heal = max(1, p.maxHP / 4)
                    p.currentHP = min(p.maxHP, p.currentHP + heal)
                    log.append(BattleLogEntry(text: "\(p.displayName) was refreshed by Life Dew!"))
                }
            }

        case "healbell", "aromatherapy":
            let s = side(at: attackerSideIdx)
            var cured = 0
            for p in s.participants where p.status != .none && !p.fainted {
                p.status = .none
                p.toxicCounter = 0
                p.sleepTurnsRemaining = 0
                cured += 1
            }
            log.append(BattleLogEntry(text: cured > 0
                ? "\(attacker.displayName) rang the bell — \(cured) ally(s) cured of status!"
                : "But no one had a status condition."))

        case "strengthsap":
            guard let d = defender else { return }
            // Heal user by target's effective Atk stat (before the drop), then
            // drop target's Atk by 1. Failure if target's Atk stage is already -6.
            if d.atkStage <= -6 {
                log.append(BattleLogEntry(text: "But it failed!"))
                return
            }
            let evAtk = d.slot.championsMode ? championsEVToMain(d.slot.evAtk) : d.slot.evAtk
            let atk = calcStat(base: d.baseAtk, iv: 31, ev: evAtk,
                               level: d.slot.level,
                               natureMod: d.nature.modifier(for: .atk))
            let stageMod = statStageMultiplier(stage: d.atkStage)
            let healed = max(1, Int(Double(atk) * stageMod))
            attacker.currentHP = min(attacker.maxHP, attacker.currentHP + healed)
            log.append(BattleLogEntry(text: "\(attacker.displayName) sapped \(d.displayName)'s strength for \(healed) HP!"))
            applyOpposingStatDrop(to: d, stat: .atk, delta: -1)

        case "wish":
            // Wish lands at the END of the NEXT turn (1 turn from now). Heal
            // amount = 50% of the USER's max HP, captured at use time.
            let amount = max(1, attacker.maxHP / 2)
            let userSlot = slotOf(attacker, side: attackerSideIdx)
            side(at: attackerSideIdx).wishQueue.append(.init(slot: userSlot, turnsRemaining: 2, amount: amount))
            log.append(BattleLogEntry(text: "\(attacker.displayName) made a wish!"))

        case "yawn":
            guard let d = defender else { return }
            if d.yawnCounter > 0 || d.status != .none {
                log.append(BattleLogEntry(text: "But it failed!"))
                return
            }
            // Safeguard also blocks Yawn — `canApplyStatus` enforces this when
            // the effect lands at EOT; we still let it set the counter here.
            d.yawnCounter = 2  // ticks to 1 at this EOT, then 0 at next EOT → sleep
            log.append(BattleLogEntry(text: "\(d.displayName) grew drowsy!"))

        case "leechseed":
            guard let d = defender else { return }
            if d.types.contains("Grass") {
                log.append(BattleLogEntry(text: "But it failed! \(d.displayName) is Grass-type."))
                return
            }
            if d.leechSeededBy != nil {
                log.append(BattleLogEntry(text: "But \(d.displayName) is already seeded!"))
                return
            }
            d.leechSeededBy = (attackerSideIdx, slotOf(attacker, side: attackerSideIdx))
            log.append(BattleLogEntry(text: "\(d.displayName) was seeded!"))

        case "endure":
            // Same diminishing-chance pattern as Protect, sharing the streak.
            let denom = 1 << max(0, attacker.consecutiveProtectCount)
            if Int.random(in: 1...100) > 100 / denom {
                attacker.consecutiveProtectCount = 0
                log.append(BattleLogEntry(text: "But it failed!"))
                return
            }
            attacker.consecutiveProtectCount = min(attacker.consecutiveProtectCount + 1, 4)
            attacker.endureThisTurn = true
            log.append(BattleLogEntry(text: "\(attacker.displayName) braced itself!"))

        case "encore":
            guard let d = defender, let lastIdx = d.lastMoveIndex else {
                log.append(BattleLogEntry(text: "But it failed!"))
                return
            }
            d.encoreLockedIndex = lastIdx
            d.encoreTurns = 3
            log.append(BattleLogEntry(text: "\(d.displayName) got an encore!"))

        case "disable":
            guard let d = defender, let lastIdx = d.lastMoveIndex else {
                log.append(BattleLogEntry(text: "But it failed!"))
                return
            }
            d.disabledMoveIndex = lastIdx
            d.disableTurns = 4
            log.append(BattleLogEntry(text: "\(d.displayName)'s last move was disabled!"))

        case "destinybond":
            attacker.destinyBondActive = true
            log.append(BattleLogEntry(text: "\(attacker.displayName) is hoping to take its attacker down with it!"))

        case "substitute":
            // 25% maxHP cost to spawn the sub. Fails if HP < 25% or sub already up.
            let cost = max(1, attacker.maxHP / 4)
            if attacker.subHP > 0 {
                log.append(BattleLogEntry(text: "\(attacker.displayName) already has a substitute!"))
                return
            }
            if attacker.currentHP <= cost {
                log.append(BattleLogEntry(text: "But \(attacker.displayName) doesn't have enough HP!"))
                return
            }
            attacker.currentHP -= cost
            attacker.subHP = cost
            log.append(BattleLogEntry(text: "\(attacker.displayName) put up a substitute!"))

        case "roost":
            // Heal 50% maxHP. If at full HP, fail with the usual message. While
            // the user is "roosted", their Flying typing is suppressed for the
            // rest of the turn (Ground hits Flying-types neutral, etc.). Flag
            // clears at EOT.
            if attacker.currentHP >= attacker.maxHP {
                log.append(BattleLogEntry(text: "\(attacker.displayName)'s HP is already full!"))
                return
            }
            let heal = max(1, attacker.maxHP / 2)
            attacker.currentHP = min(attacker.maxHP, attacker.currentHP + heal)
            attacker.roostedThisTurn = true
            log.append(BattleLogEntry(text: "\(attacker.displayName) roosted to rest."))

        case "curse":
            // Ghost-type variant: half user HP cost, places a curse on the target
            // that chips 1/4 maxHP per EOT. Non-Ghost variant: +1 Atk, +1 Def,
            // -1 Speed on the user. We use the user's active type, not the slot's.
            if attacker.types.contains("Ghost") {
                guard let d = defender else { return }
                let cost = max(1, attacker.maxHP / 2)
                attacker.currentHP = max(0, attacker.currentHP - cost)
                // Stash the curse on the target via a simple status alias —
                // we don't have a dedicated cursed volatile so we reuse the
                // leechSeededBy slot, marking it with a sentinel side index.
                // (Tier 5 cleanup: dedicated `cursedBy` field.) For now we
                // log and apply 1/4 chip at next EOT manually via a new flag.
                d.subHP = max(d.subHP, 0)  // no-op; placeholder
                log.append(BattleLogEntry(text: "\(attacker.displayName) cursed \(d.displayName)!"))
                // The full Ghost-Curse EOT chip is a Tier 5 follow-up — Tier 3
                // ships the HP cost + the visible log entry.
            } else {
                changeStage(attacker, stat: .atk, by: 1)
                changeStage(attacker, stat: .def, by: 1)
                changeStage(attacker, stat: .speed, by: -1)
                log.append(BattleLogEntry(text: "\(attacker.displayName) raised Atk and Def, lowered Speed!"))
            }

        default:
            break
        }
    }

    // MARK: Tier 5 — Niche status moves

    private func applyTier5StatusMove(_ key: String,
                                      attacker: BattleParticipant,
                                      attackerSideIdx: Int,
                                      defender: BattleParticipant?,
                                      defenderSideIdx: Int) {
        switch key {
        case "trick", "switcheroo":
            guard let d = defender else { return }
            // Mega stones, Z-crystals (n/a here), and species-specific items
            // can't be swapped in canon. Tier 5 enforces only "no mega stones".
            if attacker.heldItem.isMegaStone || d.heldItem.isMegaStone {
                log.append(BattleLogEntry(text: "But it failed!"))
                return
            }
            let aItem = attacker.heldItem
            let dItem = d.heldItem
            // Swap raw items. consumedItem / knockedOff travel with the holder
            // since they describe what HAPPENED to them, not the item itself.
            attacker.heldItem = dItem
            d.heldItem = aItem
            // Trick is the one move that resets choice locks (canon).
            attacker.choiceLockedMoveIndex = nil
            d.choiceLockedMoveIndex = nil
            log.append(BattleLogEntry(text: "\(attacker.displayName) swapped items with \(d.displayName)!"))

        case "memento":
            guard let d = defender else { return }
            applyOpposingStatDrop(to: d, stat: .atk,   delta: -2)
            applyOpposingStatDrop(to: d, stat: .spAtk, delta: -2)
            attacker.currentHP = 0
            log.append(BattleLogEntry(text: "\(attacker.displayName) sacrificed itself with Memento!", emphasis: true))

        case "bellydrum":
            let cost = max(1, attacker.maxHP / 2)
            if attacker.currentHP <= cost {
                log.append(BattleLogEntry(text: "But it failed! HP too low for Belly Drum."))
                return
            }
            if attacker.atkStage >= 6 {
                log.append(BattleLogEntry(text: "But it failed! Attack is already maxed."))
                return
            }
            attacker.currentHP -= cost
            attacker.atkStage = 6
            log.append(BattleLogEntry(text: "\(attacker.displayName) belly-drummed for max Attack!"))

        case "clangoroussoul":
            let cost = max(1, attacker.maxHP / 3)
            if attacker.currentHP <= cost {
                log.append(BattleLogEntry(text: "But it failed!"))
                return
            }
            attacker.currentHP -= cost
            changeStage(attacker, stat: .atk,   by: 1)
            changeStage(attacker, stat: .def,   by: 1)
            changeStage(attacker, stat: .spAtk, by: 1)
            changeStage(attacker, stat: .spDef, by: 1)
            changeStage(attacker, stat: .speed, by: 1)
            log.append(BattleLogEntry(text: "\(attacker.displayName) raised all stats!"))

        case "healingwish", "lunardance":
            // User faints; the side's pending-heal flag fires when the
            // replacement walks in (handled in `performSwitch`).
            let slot = slotOf(attacker, side: attackerSideIdx)
            let s = side(at: attackerSideIdx)
            if slot < s.healingWishPending.count {
                s.healingWishPending[slot] = true
            }
            attacker.currentHP = 0
            log.append(BattleLogEntry(text: "\(attacker.displayName) sacrificed itself for an ally!", emphasis: true))

        case "roar", "whirlwind", "dragontail", "circlethrow":
            guard let d = defender else { return }
            // Force-switch a random benched mon in for the defender. Fails if
            // there's nothing on the bench. Roar/Whirlwind ignore Substitute;
            // Dragon Tail / Circle Throw deal damage too — that's already
            // handled in the damage path (these moves are damage-class).
            // Tier 5 handles the *status* path (no-damage Roar/Whirlwind).
            let dSide = side(at: defenderSideIdx)
            let bench = dSide.benchIndices()
            if bench.isEmpty {
                log.append(BattleLogEntry(text: "But it failed!"))
                return
            }
            let chosen = bench.randomElement()!
            let slot = slotOf(d, side: defenderSideIdx)
            d.resetVolatile()   // outgoing wipes its volatiles
            dSide.activeIndices[slot] = chosen
            let incoming = dSide.participants[chosen]
            log.append(BattleLogEntry(text: "\(d.displayName) was forced out! \(incoming.displayName) is dragged in!"))
            applyHazardsOnSwitchIn(p: incoming, side: dSide)
            if !incoming.fainted { activateEntryAbility(for: incoming, ownSide: defenderSideIdx) }

        case "endeavor":
            guard let d = defender else { return }
            // Only works if the target's HP is strictly greater than the user's.
            if d.currentHP > attacker.currentHP {
                d.currentHP = attacker.currentHP
                log.append(BattleLogEntry(text: "\(d.displayName)'s HP was sapped to match \(attacker.displayName)!"))
            } else {
                log.append(BattleLogEntry(text: "But it failed!"))
            }

        default: break
        }
    }

    // MARK: Tier 5 — Contact + trap reactives

    /// Cursed Body (30% disable on contact), Pickpocket (steal attacker's
    /// item on contact when holder has none), and Cute Charm (30% infatuate
    /// the contact attacker). All fire post-damage if the defender survived.
    private func applyTier5ContactReactives(attacker: BattleParticipant,
                                            defender: BattleParticipant,
                                            move: MoveData) {
        guard !attacker.fainted, !defender.fainted else { return }
        guard isContactMove(move) else { return }
        guard let ab = defender.activeAbility else { return }
        switch ab {
        case "cursed-body":
            if let last = attacker.lastMoveIndex,
               attacker.disableTurns == 0,
               luck(0.3) {
                attacker.disabledMoveIndex = last
                attacker.disableTurns = 4
                log.append(BattleLogEntry(text: "\(attacker.displayName)'s \(move.name) was disabled by Cursed Body!"))
            }
        case "pickpocket":
            if defender.heldItem == .none,
               attacker.heldItem != .none,
               !attacker.heldItem.isMegaStone,
               !attacker.consumedItem, !attacker.knockedOff {
                defender.heldItem = attacker.heldItem
                attacker.heldItem = .none
                log.append(BattleLogEntry(text: "\(defender.displayName) lifted \(attacker.displayName)'s item via Pickpocket!"))
            }
        case "cute-charm":
            // Canon: 30% chance; only fires on opposite-gender contact. We don't
            // track gender, so the gender check is skipped (always eligible).
            if !attacker.infatuated, luck(0.3) {
                attacker.infatuated = true
                log.append(BattleLogEntry(text: "\(attacker.displayName) became infatuated with \(defender.displayName)!"))
            }
        default: break
        }
    }

    /// Apply a trap volatile when the move belongs to the trap family. Lasts
    /// 4–5 turns; deals 1/8 maxHP at end-of-turn (handled in `endOfTurnEffects`).
    private func applyTrapMove(attacker: BattleParticipant,
                               defender: BattleParticipant,
                               move: MoveData) {
        guard !defender.fainted else { return }
        let key = BattleSimSeed.normalize(move.name)
        guard BattleMoveEffects.trapMoves.contains(key) else { return }
        if defender.trapTurnsRemaining > 0 { return }   // already trapped
        defender.trapTurnsRemaining = Int.random(in: 4...5)
        defender.trapMoveName = move.name
        log.append(BattleLogEntry(text: "\(defender.displayName) was trapped by \(move.name)!"))
    }

    // MARK: Tier 5 — OHKO + fixed-damage

    /// Mold Breaker and its kind, or a move that ignores abilities, get past
    /// the target's Sturdy and Disguise, as in `CalcEngine.getsPast`.
    private static func ignoresAbilities(_ attacker: BattleParticipant, _ move: MoveData) -> Bool {
        CalcEngine.abilityBreakers.contains(attacker.activeAbility ?? "")
            || CalcEngine.abilityIgnoringMoves.contains(BattleSimSeed.normalize(move.name))
    }

    /// One-hit KO moves. Accuracy uses the canon formula:
    ///   acc = 30 + (attackerLevel - defenderLevel)
    /// Type immunity: Sheer Cold doesn't affect Ice-types (Gen VII+);
    /// Fissure / Horn Drill / Guillotine don't affect immune types per move
    /// type (Ghost vs Normal, Flying vs Ground, etc.). The base damage calc's
    /// effectiveness probe captures this — we just need to bail when eff == 0.
    private func applyOHKO(attacker: BattleParticipant,
                           defender: BattleParticipant,
                           move: MoveData) {
        let probe = computeDamage(attacker: attacker, defender: defender,
                                  move: move, isSpread: false, crit: false)
        if probe.eff == 0 {
            log.append(BattleLogEntry(text: "It doesn't affect \(defender.displayName)…"))
            return
        }
        if attacker.slot.level < defender.slot.level {
            log.append(BattleLogEntry(text: "But it failed! Target's level is higher."))
            return
        }
        // Sheer Cold extra immunity check.
        if BattleSimSeed.normalize(move.name) == "sheercold",
           defender.types.contains("Ice") {
            log.append(BattleLogEntry(text: "It doesn't affect \(defender.displayName)…"))
            return
        }
        let acc = 30 + (attacker.slot.level - defender.slot.level)
        if accuracyRoll() > acc {
            log.append(BattleLogEntry(text: "\(attacker.displayName)'s \(move.name) missed!"))
            return
        }
        if defender.activeAbility == "sturdy", !Self.ignoresAbilities(attacker, move) {
            log.append(BattleLogEntry(text: "\(defender.displayName) is unaffected thanks to Sturdy!"))
            return
        }
        defender.currentHP = 0
        log.append(BattleLogEntry(text: "It's a one-hit KO!", emphasis: true))
        log.append(BattleLogEntry(text: "\(defender.displayName) fainted!", emphasis: true))
    }

    /// Fixed-damage moves (Seismic Toss / Night Shade / Dragon Rage / Sonic
    /// Boom / Super Fang / Final Gambit / Counter / Mirror Coat). Bypass the
    /// standard damage formula entirely.
    private func applyTier5FixedDamage(key: String,
                                       attacker: BattleParticipant,
                                       defender: BattleParticipant,
                                       move: MoveData) {
        // Type-immunity probe — Night Shade is Ghost (no effect on Normal),
        // Seismic Toss is Fighting (no effect on Ghost), Counter is Fighting,
        // Mirror Coat is Psychic. Sub-bypass is canon for these.
        let probe = computeDamage(attacker: attacker, defender: defender,
                                  move: move, isSpread: false, crit: false)
        if probe.eff == 0 {
            log.append(BattleLogEntry(text: "It doesn't affect \(defender.displayName)…"))
            return
        }
        let damage: Int
        switch key {
        case "seismictoss", "nightshade":
            damage = attacker.slot.level
        case "dragonrage":
            damage = 40
        case "sonicboom":
            damage = 20
        case "superfang":
            damage = max(1, defender.currentHP / 2)
        case "finalgambit":
            damage = attacker.currentHP
            attacker.currentHP = 0
        case "counter":
            if attacker.lastPhysicalDamageThisTurn <= 0 {
                log.append(BattleLogEntry(text: "But it failed!"))
                return
            }
            damage = attacker.lastPhysicalDamageThisTurn * 2
        case "mirrorcoat":
            if attacker.lastSpecialDamageThisTurn <= 0 {
                log.append(BattleLogEntry(text: "But it failed!"))
                return
            }
            damage = attacker.lastSpecialDamageThisTurn * 2
        default:
            return
        }
        let actual = min(damage, defender.currentHP)
        defender.currentHP = max(0, defender.currentHP - damage)
        log.append(BattleLogEntry(text: "\(defender.displayName) took \(actual) damage."))
        if defender.fainted {
            log.append(BattleLogEntry(text: "\(defender.displayName) fainted!", emphasis: true))
        }
        if attacker.fainted {
            log.append(BattleLogEntry(text: "\(attacker.displayName) fainted!", emphasis: true))
        }
    }

    /// Compute a damage multiplier for Tier 5 power-modifier moves so the
    /// normal calc result can be scaled cleanly. Returns 1.0 for moves with
    /// no Tier 5 power adjustment.
    func tier5PowerMultiplier(key: String,
                              attacker: BattleParticipant,
                              defender: BattleParticipant,
                              baseMovePower: Int) -> Double {
        switch key {
        case "acrobatics":
            return attacker.effectiveHeldItem == .none ? 2.0 : 1.0
        case "hex":
            return defender.status != .none ? 2.0 : 1.0
        case "venoshock":
            return (defender.status == .poison || defender.status == .toxic) ? 2.0 : 1.0
        case "storedpower", "powertrip":
            let stages = max(0, attacker.atkStage) + max(0, attacker.defStage)
                       + max(0, attacker.spAtkStage) + max(0, attacker.spDefStage)
                       + max(0, attacker.speedStage)
            // Canon power = 20 + 20 * stages. Scale relative to base.
            let target = 20 + 20 * stages
            let base = max(baseMovePower, 1)
            return Double(target) / Double(base)
        case "heatcrash", "heavyslam":
            let aW = BattleMoveEffects.weightForSpecies(attacker.displayName)
            let dW = BattleMoveEffects.weightForSpecies(defender.displayName)
            let target = BattleMoveEffects.heavySlamPower(attackerWeight: aW,
                                                         defenderWeight: dW)
            return Double(target) / Double(max(baseMovePower, 1))
        case "grassknot", "lowkick":
            let dW = BattleMoveEffects.weightForSpecies(defender.displayName)
            let target = BattleMoveEffects.weightPower(defenderWeight: dW)
            return Double(target) / Double(max(baseMovePower, 1))
        default:
            return 1.0
        }
    }

    // MARK: Damage Bridge

    /// Reuse the existing damage calculator end-to-end so STAB, ability, item, weather,
    /// terrain, type, and stat-stage logic stays the single source of truth.
    private func computeDamage(attacker: BattleParticipant, defender: BattleParticipant,
                               move: MoveData, isSpread: Bool,
                               crit: Bool = false) -> (min: Double, max: Double, eff: Double) {
        let vm = DamageCalcVM()
        configure(side: vm.side1, from: attacker, withMove: move)
        configure(side: vm.side2, from: defender, withMove: nil)
        vm.multi = isSpread
        vm.burn = attacker.status == .burn
        vm.weather = weather
        vm.terrain = terrain
        vm.crit = crit
        // Crits ignore the attacker's negative offensive stages and the defender's
        // positive defensive stages. Mutating the proxy sides is safe — they're
        // throwaway and the participants' real stages stay untouched.
        if crit {
            vm.side1.atkStage   = max(0, vm.side1.atkStage)
            vm.side1.spAtkStage = max(0, vm.side1.spAtkStage)
            vm.side2.defStage   = min(0, vm.side2.defStage)
            vm.side2.spDefStage = min(0, vm.side2.spDefStage)
        }
        // Unaware (Tier 6) — ignores opposing stat stages during the calc.
        // Attacker side ignores the defender's defensive stages; defender
        // side ignores the attacker's offensive stages. Mutating the proxy
        // is safe because it's throwaway.
        if attacker.activeAbility == "unaware" {
            vm.side2.defStage   = 0
            vm.side2.spDefStage = 0
        }
        if defender.activeAbility == "unaware" {
            vm.side1.atkStage   = 0
            vm.side1.spAtkStage = 0
        }
        guard let r = vm.side1Results.first else { return (0, 0, 1) }
        return (r.damageMin, r.damageMax, r.effectiveness)
    }

    /// Gen 7+ crit ratio table. Stage 0 → 1/24, Stage 1 → 1/8, Stage 2 → 1/2,
    /// Stage 3+ → always crit. Move's `critRate` field stacks with Scope Lens.
    private func rollCrit(attacker: BattleParticipant, move: MoveData) -> Bool {
        if let rollOverride { return rollOverride.crit }
        var stage = move.critRate
        if attacker.effectiveHeldItem == .scopeLens { stage += 1 }
        let chance: Double
        switch stage {
        case 0:  chance = 1.0 / 24.0
        case 1:  chance = 1.0 / 8.0
        case 2:  chance = 1.0 / 2.0
        default: chance = 1.0
        }
        return Double.random(in: 0..<1) < chance
    }

    /// Picks a damage value from a range: uniformly at random, or the pinned
    /// end when `rollOverride` is set.
    private func rollDamage(_ dMin: Int, _ dMax: Int) -> Int {
        guard dMin < dMax else { return dMin }
        guard let override = rollOverride else { return Int.random(in: dMin...dMax) }
        switch override.roll {
        case .min: return dMin
        case .max: return dMax
        case .fraction(let f):
            let clamped = Swift.max(0, Swift.min(1, f))
            return dMin + Int((Double(dMax - dMin) * clamped).rounded())
        }
    }

    /// Maps the sim's `BattleStatus` to the Showdown port's `ShowdownStatus`.
    private func showdownStatus(from status: BattleStatus) -> ShowdownStatus {
        switch status {
        case .none:       return .none
        case .burn:       return .brn
        case .paralysis:  return .par
        case .poison:     return .psn
        case .toxic:      return .tox
        case .sleep:      return .slp
        case .freeze:     return .frz
        }
    }

    private func configure(side: CalcSide, from p: BattleParticipant, withMove move: MoveData?) {
        if let mega = p.megaForm {
            // Feed the damage calc a transient PKMNStats representing the Mega form so
            // types, base stats, and ability all reflect post-evolution values.
            side.pokemon = PKMNStats(
                id: p.stats?.id ?? 0,
                speciesID: p.stats?.speciesID ?? 0,
                name: mega.displayName,
                formName: "mega",
                type1: mega.type1, type2: mega.type2,
                baseHP: p.stats?.baseHP ?? 1,
                baseAtk: mega.baseAtk, baseDef: mega.baseDef,
                baseSpAtk: mega.baseSpAtk, baseSpDef: mega.baseSpDef,
                baseSpeed: mega.baseSpeed,
                ability1: mega.ability, ability2: nil, hiddenAbility: nil,
                learnableMoveIDs: []
            )
            side.selectedAbility = mega.ability
        } else {
            side.pokemon = p.stats
            side.selectedAbility = p.slot.abilityName
        }
        side.level = p.slot.level
        side.nature = p.nature
        side.heldItem = p.effectiveHeldItem
        side.atFullHP = p.atFullHP
        // Feed the Showdown port real status + current HP so status-scaling moves
        // (Facade/Hex/Barb Barrage) and HP-scaling ones (Reversal/Eruption) and
        // abilities (Multiscale, Guts, Marvel Scale) resolve faithfully.
        side.status = showdownStatus(from: p.status)
        if p.maxHP > 0 {
            side.currentHPPercent = max(1, min(100, Int((Double(p.currentHP) / Double(p.maxHP)) * 100.0)))
        }
        side.championsMode = p.slot.championsMode
        side.evHP = p.slot.evHP
        side.evAtk = p.slot.evAtk
        side.evDef = p.slot.evDef
        side.evSpAtk = p.slot.evSpAtk
        side.evSpDef = p.slot.evSpDef
        side.evSpeed = p.slot.evSpeed
        side.ivHP = 31; side.ivAtk = 31; side.ivDef = 31
        side.ivSpAtk = 31; side.ivSpDef = 31; side.ivSpeed = 31
        side.atkStage = p.atkStage
        side.defStage = p.defStage
        side.spAtkStage = p.spAtkStage
        side.spDefStage = p.spDefStage
        side.speedStage = p.speedStage
        if let m = move { side.moves[0] = m }
    }

    // MARK: End-of-turn

    private func endOfTurnEffects() {
        for s in 0..<2 {
            for slot in 0..<format.activeSlots {
                guard let p = side(at: s).active(at: slot), !p.fainted else { continue }

                if weather == .sand, p.activeAbility != "magic-guard" {
                    let immune: Set<String> = ["Rock", "Ground", "Steel"]
                    if !p.types.contains(where: { immune.contains($0) }) {
                        let dmg = max(1, p.maxHP / 16)
                        p.currentHP = max(0, p.currentHP - dmg)
                        log.append(BattleLogEntry(text: "\(p.displayName) is buffeted by the sandstorm! (-\(dmg) HP)"))
                    }
                }

                // Magic Guard exempts the holder from all non-direct damage
                // (status DoT, weather chip, hazards). Hazards are applied on
                // switch-in and weather above; status DoT falls below.
                let magicGuard = p.activeAbility == "magic-guard"
                switch p.status {
                case .burn where !magicGuard:
                    let dmg = max(1, p.maxHP / 16)
                    p.currentHP = max(0, p.currentHP - dmg)
                    log.append(BattleLogEntry(text: "\(p.displayName) is hurt by its burn. (-\(dmg) HP)"))
                case .poison where !magicGuard:
                    let dmg = max(1, p.maxHP / 8)
                    p.currentHP = max(0, p.currentHP - dmg)
                    log.append(BattleLogEntry(text: "\(p.displayName) is hurt by poison. (-\(dmg) HP)"))
                case .toxic where !magicGuard:
                    p.toxicCounter = min(15, p.toxicCounter + 1)
                    let dmg = max(1, p.maxHP * p.toxicCounter / 16)
                    p.currentHP = max(0, p.currentHP - dmg)
                    log.append(BattleLogEntry(text: "\(p.displayName) is hurt by toxic poison. (-\(dmg) HP)"))
                case .toxic:
                    // Toxic counter still ticks under Magic Guard — the damage
                    // is suppressed but the badge counts the turns so a swap
                    // off-and-on doesn't reset it.
                    p.toxicCounter = min(15, p.toxicCounter + 1)
                default:
                    break
                }

                // Salt Cure — every-turn HP chip; doubles vs Water/Steel types.
                // Magic Guard suppresses (it's indirect damage).
                if p.saltCured, !p.fainted, p.activeAbility != "magic-guard" {
                    let bigType = p.types.contains("Water") || p.types.contains("Steel")
                    let denom = bigType ? 4 : 8
                    let dmg = max(1, p.maxHP / denom)
                    p.currentHP = max(0, p.currentHP - dmg)
                    log.append(BattleLogEntry(text: "\(p.displayName) is salt-cured! (-\(dmg) HP)"))
                }

                // Leftovers — recover 1/16 max HP at end of turn if not full and alive.
                if !p.fainted,
                   p.effectiveHeldItem == .leftovers,
                   p.currentHP < p.maxHP {
                    let heal = max(1, p.maxHP / 16)
                    p.currentHP = min(p.maxHP, p.currentHP + heal)
                    log.append(BattleLogEntry(text: "\(p.displayName) restored HP with Leftovers."))
                }

                // Status DoT may have dropped HP enough to trigger a pinch berry.
                if !p.fainted { maybeTriggerHPBerry(for: p) }

                // Harvest — chance to regrow a consumed berry. 100% in sun, 50% else.
                if !p.fainted,
                   p.activeAbility == "harvest",
                   p.consumedItem, p.heldItem.isBerry, !p.knockedOff {
                    let chance = weather == .sun ? 1.0 : 0.5
                    if luck(chance) {
                        p.consumedItem = false
                        log.append(BattleLogEntry(text: "\(p.displayName)'s Harvest restored its \(p.heldItem.rawValue)!"))
                    }
                }

                // Speed Boost — +1 Speed at end of turn while alive. `changeStage`
                // already clamps at +6.
                if !p.fainted, p.activeAbility == "speed-boost", p.speedStage < 6 {
                    changeStage(p, stat: .speed, by: 1)
                    log.append(BattleLogEntry(text: "\(p.displayName)'s Speed Boost raised its Speed!"))
                }

                if p.fainted {
                    log.append(BattleLogEntry(text: "\(p.displayName) fainted!", emphasis: true))
                }

                // Taunt — ticks down once per end-of-turn while alive.
                if !p.fainted && p.tauntTurnsRemaining > 0 {
                    p.tauntTurnsRemaining -= 1
                    if p.tauntTurnsRemaining == 0 {
                        log.append(BattleLogEntry(text: "\(p.displayName)'s taunt wore off."))
                    }
                }

                // Perish Song countdown — ticks down end-of-turn while alive.
                // When it reaches 0 the holder faints regardless of HP. Switch-out
                // (resetVolatile) is the only escape; switching wipes the counter.
                if !p.fainted && p.perishCounter > 0 {
                    p.perishCounter -= 1
                    if p.perishCounter == 0 {
                        p.currentHP = 0
                        log.append(BattleLogEntry(text: "\(p.displayName)'s perish count fell to 0!"))
                        log.append(BattleLogEntry(text: "\(p.displayName) fainted!", emphasis: true))
                    } else {
                        log.append(BattleLogEntry(text: "\(p.displayName)'s perish count is \(p.perishCounter)!"))
                    }
                }

                // Leech Seed — 1/8 maxHP transferred to the seeder per EOT.
                // Magic Guard exempts the seeded holder.
                if !p.fainted, let src = p.leechSeededBy,
                   p.activeAbility != "magic-guard" {
                    let amount = max(1, p.maxHP / 8)
                    let actual = min(amount, p.currentHP)
                    p.currentHP -= actual
                    if let seeder = side(at: src.side).active(at: src.slot), !seeder.fainted {
                        let heal = min(actual, seeder.maxHP - seeder.currentHP)
                        if heal > 0 {
                            seeder.currentHP += heal
                        }
                    }
                    log.append(BattleLogEntry(text: "\(p.displayName) was sapped by Leech Seed! (-\(actual) HP)"))
                }

                // Yawn — 2-step countdown. Ticks at end of every turn.
                //   2 (just applied)  → 1 (drowsy, no sleep yet)
                //   1                → 0 (sleep lands now)
                if !p.fainted, p.yawnCounter > 0 {
                    p.yawnCounter -= 1
                    if p.yawnCounter == 0 {
                        tryInflictStatus(.sleep, on: p)
                    }
                }

                // Trap move EOT chip (Bind / Wrap / Fire Spin / etc.). 1/8 max
                // HP per turn while the timer is active. Magic Guard exempts.
                if !p.fainted, p.trapTurnsRemaining > 0,
                   p.activeAbility != "magic-guard" {
                    let chip = max(1, p.maxHP / 8)
                    p.currentHP = max(0, p.currentHP - chip)
                    let name = p.trapMoveName ?? "the trap"
                    log.append(BattleLogEntry(text: "\(p.displayName) is hurt by \(name)! (-\(chip) HP)"))
                }
                if p.trapTurnsRemaining > 0 {
                    p.trapTurnsRemaining -= 1
                    if p.trapTurnsRemaining == 0 {
                        log.append(BattleLogEntry(text: "\(p.displayName) was freed from the trap."))
                        p.trapMoveName = nil
                    }
                }

                // Moody (Tier 6) — pick one stat to raise by 2 and a
                // different stat to lower by 1. Skip accuracy/evasion (not
                // tracked). Tier 6 ignores boost-cap edge cases.
                if !p.fainted, p.activeAbility == "moody" {
                    let stats: [Nature.StatKey] = [.atk, .def, .spAtk, .spDef, .speed]
                    let up = stats.randomElement()!
                    let downs = stats.filter { $0 != up }
                    let down = downs.randomElement()!
                    changeStage(p, stat: up, by: 2)
                    changeStage(p, stat: down, by: -1)
                    log.append(BattleLogEntry(text: "\(p.displayName)'s Moody shifted its stats!"))
                }

                // Encore / Disable — both tick at EOT. When the timer hits 0
                // the lock clears.
                if p.encoreTurns > 0 {
                    p.encoreTurns -= 1
                    if p.encoreTurns == 0 {
                        p.encoreLockedIndex = nil
                        log.append(BattleLogEntry(text: "\(p.displayName)'s encore wore off."))
                    }
                }
                if p.disableTurns > 0 {
                    p.disableTurns -= 1
                    if p.disableTurns == 0 {
                        p.disabledMoveIndex = nil
                        log.append(BattleLogEntry(text: "\(p.displayName)'s disable wore off."))
                    }
                }

                // Flinch resets at end of turn — never carries forward. Guarded so
                // the no-op write doesn't churn @Observable subscribers every turn.
                if p.flinched { p.flinched = false }
            }
        }

        if weatherTurns > 0 {
            weatherTurns -= 1
            if weatherTurns == 0 {
                log.append(BattleLogEntry(text: "The weather subsided."))
                weather = .none
            }
        }
        if terrainTurns > 0 {
            terrainTurns -= 1
            if terrainTurns == 0 {
                log.append(BattleLogEntry(text: "The terrain faded."))
                terrain = .none
            }
        }
        // Global field rooms.
        if trickRoomTurns > 0 {
            trickRoomTurns -= 1
            if trickRoomTurns == 0 {
                log.append(BattleLogEntry(text: "Trick Room ended."))
            }
        }
        if wonderRoomTurns > 0 {
            wonderRoomTurns -= 1
            if wonderRoomTurns == 0 {
                log.append(BattleLogEntry(text: "Wonder Room ended."))
            }
        }
        if magicRoomTurns > 0 {
            magicRoomTurns -= 1
            if magicRoomTurns == 0 {
                log.append(BattleLogEntry(text: "Magic Room ended."))
            }
        }
        if gravityTurns > 0 {
            gravityTurns -= 1
            if gravityTurns == 0 {
                log.append(BattleLogEntry(text: "Gravity returned to normal."))
                // Restore the grounded flag based on intrinsic typing only — we
                // don't track other ground sources at the moment, so clearing
                // the flag is sufficient.
                for s in 0..<2 {
                    for slot in 0..<format.activeSlots {
                        side(at: s).active(at: slot)?.grounded = false
                    }
                }
            }
        }
        // Per-side counters: tailwind, screens, safeguard.
        for sIdx in 0..<2 {
            let s = side(at: sIdx)
            if s.tailwindTurns > 0 {
                s.tailwindTurns -= 1
                if s.tailwindTurns == 0 {
                    log.append(BattleLogEntry(text: "Tailwind on \(s.label) faded."))
                }
            }
            if s.lightScreenTurns > 0 {
                s.lightScreenTurns -= 1
                if s.lightScreenTurns == 0 {
                    log.append(BattleLogEntry(text: "Light Screen on \(s.label) wore off."))
                }
            }
            if s.reflectTurns > 0 {
                s.reflectTurns -= 1
                if s.reflectTurns == 0 {
                    log.append(BattleLogEntry(text: "Reflect on \(s.label) wore off."))
                }
            }
            if s.auroraVeilTurns > 0 {
                s.auroraVeilTurns -= 1
                if s.auroraVeilTurns == 0 {
                    log.append(BattleLogEntry(text: "Aurora Veil on \(s.label) wore off."))
                }
            }
            if s.safeguardTurns > 0 {
                s.safeguardTurns -= 1
                if s.safeguardTurns == 0 {
                    log.append(BattleLogEntry(text: "Safeguard on \(s.label) wore off."))
                }
            }
            // Doubles per-turn flags: Helping Hand pending + redirection +
            // Wide/Quick Guard all live for one turn only.
            for i in 0..<s.helpingHandPending.count { s.helpingHandPending[i] = false }
            s.redirectionTargetSlot = nil
            s.wideGuardActive = false
            s.quickGuardActive = false
            // Per-Pokemon: protect this-turn flag clears so next turn starts fresh.
            for slot in 0..<format.activeSlots {
                if let p = s.active(at: slot) {
                    p.protectedThisTurn = false
                    p.lastProtectKey = nil
                    p.endureThisTurn = false
                    p.roostedThisTurn = false
                    p.lastPhysicalDamageThisTurn = 0
                    p.lastSpecialDamageThisTurn = 0
                }
            }
            // Wish queue: tick down each entry. When one hits 0, heal whoever
            // currently occupies the recorded slot — even if a different mon
            // is now there (canon: Wish heals "whatever is in that slot").
            var landedWishes = false
            for i in (0..<s.wishQueue.count).reversed() {
                s.wishQueue[i].turnsRemaining -= 1
                if s.wishQueue[i].turnsRemaining <= 0 {
                    let target = s.active(at: s.wishQueue[i].slot)
                    if let t = target, !t.fainted, t.currentHP < t.maxHP {
                        let amount = s.wishQueue[i].amount
                        t.currentHP = min(t.maxHP, t.currentHP + amount)
                        log.append(BattleLogEntry(text: "\(t.displayName)'s Wish came true!"))
                    }
                    s.wishQueue.remove(at: i)
                    landedWishes = true
                }
            }
            _ = landedWishes
        }
    }

    // MARK: KO / Force Switches

    private func checkForKOsAndEnd() {
        if !side1.hasUnfainted {
            winner = 2
            log.append(BattleLogEntry(text: "\(side2.label) wins!", emphasis: true))
            return
        }
        if !side2.hasUnfainted {
            winner = 1
            log.append(BattleLogEntry(text: "\(side1.label) wins!", emphasis: true))
        }
    }

    private func updateForceSwitchQueue() {
        // Don't wipe existing entries — damage-pivot moves (U-turn / Volt Switch
        // / Flip Turn) queue switches during action resolution and the queue
        // needs to survive EOT so the UI can prompt for the replacement. Add
        // fainted-mon entries on top, deduped.
        for s in 0..<2 {
            for slot in 0..<format.activeSlots {
                if let p = side(at: s).active(at: slot), p.fainted,
                   !side(at: s).benchIndices().isEmpty {
                    let entry = ForceSwitch(side: s, slot: slot)
                    if !pendingForceSwitches.contains(entry) {
                        pendingForceSwitches.append(entry)
                    }
                }
            }
        }
    }
}

// MARK: - Main View

struct BattleSimulatorView: View {
    @Query(sort: \SavedTeam.createdAt, order: .reverse) private var teams: [SavedTeam]
    @Query(sort: \SavedSpread.createdAt, order: .reverse) private var savedSpreads: [SavedSpread]
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]

    @AppStorage(AppSettings.defaultGeneration) private var defaultGeneration: String

    @State private var format: BattleFormat = .singles
    @State private var team1ID: PersistentIdentifier?
    @State private var team2ID: PersistentIdentifier?
    @State private var team1Order: [Int] = []
    @State private var team2Order: [Int] = []
    @State private var engine: BattleEngine?
    @State private var ai: PokiiBattleAI?
    /// Doubles-only AI toggles. Disabled (and visually hidden) in singles
    /// because the trained policy expects two active slots per side.
    @State private var side1AI: Bool = false
    @State private var side2AI: Bool = false
    @State private var championsFormat: Bool = false
    @State private var didApplyDefaultChampionsToggle: Bool = false

    /// Built lazily on first access — parsing ~600KB of JSON shouldn't block the
    /// view's initial layout. `nil` means the Champions JSON isn't bundled, in
    /// which case the toggle is disabled and a note is shown.
    @State private var championsValidator: ChampionsValidator? = nil
    @State private var validatorLoadAttempted: Bool = false
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        TabNavigationStack {
            Group {
                if let engine {
                    BattleView(engine: engine, ai: ai) {
                        self.engine = nil
                        self.ai = nil
                    }
                    .navigationTitle("Turn \(engine.turn)")
                } else {
                    setupView
                        .navigationTitle("Battle Simulator")
                }
            }
            .cardPage()
        }
        .leaveWarning(engine != nil && engine?.winner == nil ? "The battle in progress will end." : nil)
    }

    private var setupView: some View {
        ScrollView {
            Group {
                if allPokemon.isEmpty || allMoves.isEmpty {
                    syncingCard
                } else if teams.isEmpty {
                    emptyTeamsCard
                } else if hSize == .regular {
                    // Wide layout: the two sides sit next to each other, with
                    // the format picker on top and the AI / Start controls below.
                    CardStack {
                        formatCard
                        HStack(alignment: .top, spacing: 16) {
                            CardStack {
                                sideBlock("Side 1", selectedID: $team1ID, order: $team1Order)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            CardStack {
                                sideBlock("Side 2", selectedID: $team2ID, order: $team2Order)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                        if format == .doubles { aiControlCard }
                        startBattleButton
                    }
                } else {
                    // Compact layout: original single column, unchanged.
                    CardStack {
                        formatCard
                        sideBlock("Side 1", selectedID: $team1ID, order: $team1Order)
                        sideBlock("Side 2", selectedID: $team2ID, order: $team2Order)
                        if format == .doubles { aiControlCard }
                        startBattleButton
                    }
                }
            }
            .padding()
        }
        .onAppear { loadValidatorIfNeeded() }
        .onChange(of: team1ID) { _, _ in team1Order.removeAll() }
        .onChange(of: team2ID) { _, _ in team2Order.removeAll() }
        .onChange(of: format) { _, _ in
            team1Order.removeAll()
            team2Order.removeAll()
        }
    }

    /// One side's cards: team picker + (once a team is chosen) its lead-order
    /// editor. Shared by the compact single column and the wide two-column
    /// layout so the two stay in lockstep.
    @ViewBuilder
    private func sideBlock(_ label: String,
                           selectedID: Binding<PersistentIdentifier?>,
                           order: Binding<[Int]>) -> some View {
        TeamPickerCard(label: label, selectedID: selectedID,
                       teams: teams, savedSpreads: savedSpreads,
                       allPokemon: allPokemon, allMoves: allMoves,
                       format: format,
                       championsFormat: championsFormat,
                       validator: championsValidator)
        if let t = team(for: selectedID.wrappedValue) {
            LeadOrderCard(
                label: "\(label) — Lead Order",
                slots: t.resolvedSlots(allSpreads: savedSpreads,
                                       allPokemon: allPokemon,
                                       allMoves: allMoves),
                bringCount: format.bringCount,
                activeSlots: format.activeSlots,
                order: order
            )
        }
    }

    private var startBattleButton: some View {
        Button {
            startBattle()
        } label: {
            Label("Start Battle", systemImage: "play.fill")
        }
        .buttonStyle(.primaryAction)
        .disabled(!canStart)
    }

    /// Parses the bundled Champions JSON the first time we need it. If the JSON
    /// isn't shipped, the toggle gets disabled and a small note appears.
    private func loadValidatorIfNeeded() {
        guard !validatorLoadAttempted else { return }
        validatorLoadAttempted = true
        championsValidator = ChampionsValidator()
        if championsValidator == nil {
            // Force the toggle off if the data isn't available.
            championsFormat = false
        } else if !didApplyDefaultChampionsToggle {
            didApplyDefaultChampionsToggle = true
            if defaultGeneration == PokedexFilter.champions.rawValue {
                championsFormat = true
            }
        }
    }

    /// Doubles-only AI opt-in. Each side toggles independently so the user
    /// can play vs. AI, AI vs. AI (simulation mode), or two-human as before.
    private var aiControlCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI Opponent", systemImage: "brain")
                .font(.headline)
            Text("Let the Pokii doubles policy pick actions for one or both sides.")
                .font(.caption2).foregroundStyle(.secondary)
            Toggle(isOn: $side1AI) {
                Text("Side 1 controlled by AI").font(.subheadline)
            }
            Toggle(isOn: $side2AI) {
                Text("Side 2 controlled by AI").font(.subheadline)
            }
        }
        .card()
    }

    private var formatCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Format", systemImage: "rectangle.split.2x1").font(.headline)
            Picker("Format", selection: $format) {
                ForEach(BattleFormat.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle(isOn: $championsFormat) {
                Label("Champions Regulation", systemImage: "trophy")
                    .font(.subheadline)
            }
            .disabled(championsValidator == nil)
            if validatorLoadAttempted && championsValidator == nil {
                Text("Champions data unavailable — bundle is missing champions-\(ChampionsRegulation.current.rawValue).json.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if championsFormat {
                let rules = ChampionsRegulation.current.rules()
                Text("Lv 50, \(rules.statPointsMaxTotal) stat-point cap (\(rules.statPointsMaxPerStat) per stat), IVs \(rules.ivLockedAt). Illegal teams can't battle.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var syncingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Waiting for Pokemon & move data…")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 40)
    }

    private var emptyTeamsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3.fill")
                .font(.title).foregroundStyle(.secondary)
            Text("No saved teams").font(.headline)
            Text("Create teams in the Teams tab before starting a battle.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 24)
    }

    private var canStart: Bool {
        guard let t1 = team(for: team1ID), let t2 = team(for: team2ID) else { return false }
        let need = format.bringCount
        guard t1.slots.count >= need && t2.slots.count >= need else { return false }
        guard team1Order.count == need && team2Order.count == need else { return false }

        if championsFormat, let v = championsValidator {
            let t1Slots = t1.resolvedSlots(allSpreads: savedSpreads,
                                           allPokemon: allPokemon, allMoves: allMoves)
            let t2Slots = t2.resolvedSlots(allSpreads: savedSpreads,
                                           allPokemon: allPokemon, allMoves: allMoves)
            if ChampionsFormat.hasHardLegalityViolations(slots: t1Slots, validator: v) { return false }
            if ChampionsFormat.hasHardLegalityViolations(slots: t2Slots, validator: v) { return false }
        }
        return true
    }

    private func team(for id: PersistentIdentifier?) -> SavedTeam? {
        guard let id else { return nil }
        return teams.first(where: { $0.persistentModelID == id })
    }

    private func startBattle() {
        guard let t1 = team(for: team1ID), let t2 = team(for: team2ID) else { return }
        // Resolve through the live SavedSpread records so edits made in the Sets tab
        // (move swaps, EV tweaks, ability changes) propagate into the battle.
        let t1Resolved = t1.resolvedSlots(allSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
        let t2Resolved = t2.resolvedSlots(allSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
        // Apply the player's lead order — the first `activeSlots` are sent out,
        // the rest sit on the bench.
        var s1Slots = team1Order.compactMap { t1Resolved.indices.contains($0) ? t1Resolved[$0] : nil }
        var s2Slots = team2Order.compactMap { t2Resolved.indices.contains($0) ? t2Resolved[$0] : nil }
        if championsFormat {
            // Lv 50 + Champions stat scaling, regardless of how the spread was saved.
            s1Slots = s1Slots.map { ChampionsFormat.normalize($0) }
            s2Slots = s2Slots.map { ChampionsFormat.normalize($0) }
        }
        let s1 = BattleSide(label: "Side 1", slots: s1Slots, format: format,
                            allPokemon: allPokemon, allMoves: allMoves)
        let s2 = BattleSide(label: "Side 2", slots: s2Slots, format: format,
                            allPokemon: allPokemon, allMoves: allMoves)
        let newEngine = BattleEngine(format: format, side1: s1, side2: s2,
                                     allPokemon: allPokemon, allMoves: allMoves,
                                     championsRules: championsFormat
                                        ? ChampionsRegulation.current.rules() : nil)
        engine = newEngine
        // AI is only available in doubles — singles model lands later.
        if format == .doubles && (side1AI || side2AI) {
            ai = PokiiBattleAI(engine: newEngine, side1AI: side1AI, side2AI: side2AI)
        } else {
            ai = nil
        }
    }
}

// MARK: - Champions Format Helpers

/// Pure helpers for the enforced Champions battle format. Keeping them outside the
/// view makes them straightforward to unit-test without spinning up SwiftData.
enum ChampionsFormat {

    /// Forces level 50 and the 0-32 Champions stat-point scale, scaling main-series
    /// EVs proportionally when the slot wasn't already in Champions mode. Does NOT
    /// mutate persisted records — returns a copy.
    static func normalize(_ slot: TeamSlotInfo) -> TeamSlotInfo {
        var copy = slot
        copy.level = 50
        if !copy.championsMode {
            // Floor division (no rounding), so 252 EVs become 32 stat points
            // exactly, then the regulation's per-stat cap.
            let cap = championsMaxEVPerStat
            copy.evHP    = min(cap, mainEVToChampions(copy.evHP))
            copy.evAtk   = min(cap, mainEVToChampions(copy.evAtk))
            copy.evDef   = min(cap, mainEVToChampions(copy.evDef))
            copy.evSpAtk = min(cap, mainEVToChampions(copy.evSpAtk))
            copy.evSpDef = min(cap, mainEVToChampions(copy.evSpDef))
            copy.evSpeed = min(cap, mainEVToChampions(copy.evSpeed))
            copy.championsMode = true
        }
        return copy
    }

    /// Champions' species whitelist uses the canonical species name without form
    /// suffixes for several Pokemon. The local Pokedex stores those as
    /// form-specific rows (PokeAPI's dump pattern), so before sending a slot
    /// through the validator we need to collapse the form name back to the
    /// whitelist entry. Add new mappings here as additional ambiguous species
    /// surface.
    private static let pokedexToChampionsName: [String: String] = [
        "Floette-Eternal":     "Floette",
        "Aegislash-Shield":    "Aegislash",
        "Aegislash-Blade":     "Aegislash",
        "Basculegion-Male":    "Basculegion",
        "Basculegion-Female":  "Basculegion",
    ]

    /// Map a local Pokedex row name back to the Champions whitelist entry.
    /// Returns the input unchanged if no mapping exists.
    static func canonicalChampionsSpecies(_ pokedexName: String) -> String {
        pokedexToChampionsName[pokedexName] ?? pokedexName
    }

    /// Maps a live slot to the validator's `PokemonSet` representation. Ability ID
    /// (e.g. "snow-warning") is converted to its display form ("Snow Warning"),
    /// and form-specific species names are collapsed back to the Champions
    /// whitelist entry (e.g. "Floette-Eternal" → "Floette") so the legality
    /// whitelists match.
    static func pokemonSet(from slot: TeamSlotInfo) -> PokemonSet {
        let sp: PokemonSet.StatPoints
        if slot.championsMode {
            sp = .init(hp: slot.evHP, atk: slot.evAtk, def: slot.evDef,
                       spa: slot.evSpAtk, spd: slot.evSpDef, spe: slot.evSpeed)
        } else {
            sp = .init(hp: mainEVToChampions(slot.evHP),
                       atk: mainEVToChampions(slot.evAtk),
                       def: mainEVToChampions(slot.evDef),
                       spa: mainEVToChampions(slot.evSpAtk),
                       spd: mainEVToChampions(slot.evSpDef),
                       spe: mainEVToChampions(slot.evSpeed))
        }
        let abilityDisplay = slot.abilityName.map { formatAbilityName($0) } ?? ""
        let natureDisplay = allNatures.first(where: { $0.id == slot.natureID })?.name ?? ""
        return PokemonSet(
            species: canonicalChampionsSpecies(slot.pokemonName),
            ability: abilityDisplay,
            item: slot.itemRawValue.map(HeldItem.currentName),
            nature: natureDisplay,
            teraType: slot.teraType,
            moves: slot.moveSlots.map { $0.moveName },
            statPoints: sp,
            role: nil
        )
    }

    /// Validate the full team (all six slots — Champions enforces team size = 6).
    static func validate(slots: [TeamSlotInfo],
                         validator: ChampionsValidator) -> [Violation] {
        let team = slots.map { pokemonSet(from: $0) }
        return validator.validate(team: team)
    }

    static func hasHardLegalityViolations(slots: [TeamSlotInfo],
                                          validator: ChampionsValidator) -> Bool {
        validate(slots: slots, validator: validator).contains(where: { $0.category.isLegality })
    }
}

// MARK: - Engine Coverage

/// Catalog of moves and abilities the battle engine doesn't fully model.
/// Surfaced on the team-select screen so the user knows their pick will
/// behave differently from canon. Categories:
///   - `unimplementedMoves` / `unimplementedAbilities`: not simulated at all.
///     A move here falls through to either no effect (status) or generic
///     damage with no secondary (damaging).
///   - `partialMoves` / `partialAbilities`: works for the main case but with a
///     documented caveat (Sky Drop doesn't lift the target, etc.).
///
/// Keys are `BattleSimSeed.normalize`-form for moves and the PokeAPI slug for
/// abilities. Match the names the slots actually carry.
enum BattleEngineCoverage {
    static let unimplementedMoves: Set<String> = [
        "transform", "mimic", "sketch", "copycat", "imprison",
        "razorwind", "freezeshock", "iceburn", "bide",
        "skillswap", "roleplay", "instruct",
        "metalburst", "comeuppance",
    ]

    static let partialMoves: [String: String] = [
        "skydrop":     "Sky Drop: user goes airborne; the target isn't lifted.",
        "afteryou":    "After You: logs only — turn order isn't changed.",
        "curse":       "Curse (Ghost): HP cost applies; end-of-turn chip on the target isn't modeled.",
        "shedtail":    "Shed Tail: pivot works; the Substitute donation isn't modeled.",
        "substitute":  "Substitute: sound moves don't bypass it.",
        "throatchop":  "Throat Chop: damage lands; sound-move disable isn't modeled.",
        "stoneaxe":    "Stone Axe / Ceaseless Edge sets Spikes on the foe's side (Spikes, not Stealth Rock).",
    ]

    static let unimplementedAbilities: Set<String> = [
        "forecast", "schooling", "power-construct", "hunger-switch",
        "mimicry", "stench", "neutralizing-gas", "shields-down",
        "ball-fetch", "rks-system", "multitype", "zen-mode",
    ]

    static let partialAbilities: [String: String] = [
        "imposter": "Imposter: stats/types/ability/stages copy; move-slot copy isn't modeled.",
        "battle-bond": "Battle Bond: Gen 9 stat boost on KO; older form-change variant not modeled.",
        "zero-to-hero": "Zero to Hero: simplified stat boost (canon transform is more involved).",
        "cute-charm": "Cute Charm: 30% infatuation on contact (gender check skipped).",
    ]

    /// Return human-readable warnings for the given team slot. Empty if every
    /// move and the ability are fully modeled.
    static func warnings(for slot: TeamSlotInfo) -> [String] {
        var out: [String] = []
        if let ab = slot.abilityName?.lowercased() {
            if unimplementedAbilities.contains(ab) {
                out.append("Ability \(formatAbilityName(ab)): not yet simulated.")
            }
            if let partial = partialAbilities[ab] {
                out.append(partial)
            }
        }
        for moveSlot in slot.moveSlots {
            let key = BattleSimSeed.normalize(moveSlot.moveName)
            if unimplementedMoves.contains(key) {
                out.append("Move \(moveSlot.moveName): not yet simulated.")
            }
            if let partial = partialMoves[key] {
                out.append(partial)
            }
        }
        return out
    }
}

// MARK: - Team Picker

private struct TeamPickerCard: View {
    let label: String
    @Binding var selectedID: PersistentIdentifier?
    let teams: [SavedTeam]
    let savedSpreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    let format: BattleFormat
    let championsFormat: Bool
    let validator: ChampionsValidator?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static func title(for team: SavedTeam) -> String {
        "\(team.name) (\(team.slots.count))"
    }

    private var selectedTitle: String {
        teams.first { $0.persistentModelID == selectedID }.map { Self.title(for: $0) } ?? "Select a team…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.headline)
            // A Menu around the Picker, not a menu-style Picker: that one's
            // label doesn't grow taller when a long team name wraps at a
            // large text size, so the name is clipped.
            Menu {
                Picker("Team", selection: $selectedID) {
                    Text("Select a team…").tag(PersistentIdentifier?.none)
                    ForEach(teams) { t in
                        Text(Self.title(for: t)).tag(Optional(t.persistentModelID))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedTitle)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
            }
            .accessibilityLabel("Team")
            .accessibilityValue(selectedTitle)

            if let t = teams.first(where: { $0.persistentModelID == selectedID }) {
                let liveSlots = t.resolvedSlots(allSpreads: savedSpreads,
                                                allPokemon: allPokemon,
                                                allMoves: allMoves)
                let names = liveSlots.prefix(6).map { $0.pokemonName }.joined(separator: ", ")
                if !names.isEmpty {
                    Text(names).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                if t.slots.count < format.bringCount {
                    Label("Need at least \(format.bringCount) Pokemon for \(format.label).",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }

                if championsFormat, let v = validator {
                    let violations = ChampionsFormat.validate(slots: liveSlots, validator: v)
                    let hard = violations.filter { $0.category.isLegality }
                    let soft = violations.filter { !$0.category.isLegality }
                    if hard.isEmpty && soft.isEmpty {
                        Label("Champions-legal", systemImage: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                    ForEach(Array(hard.enumerated()), id: \.offset) { _, vio in
                        Label(vio.message, systemImage: "xmark.octagon.fill")
                            .font(.caption2).foregroundStyle(.red)
                    }
                    ForEach(Array(soft.enumerated()), id: \.offset) { _, vio in
                        Label(vio.message, systemImage: "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }

                // Engine-coverage warnings — surface anything the simulator
                // doesn't fully model so the user isn't surprised mid-battle.
                let coverageNotes: [(slot: String, lines: [String])] = liveSlots.compactMap { slot in
                    let lines = BattleEngineCoverage.warnings(for: slot)
                    return lines.isEmpty ? nil : (slot.pokemonName, lines)
                }
                if !coverageNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Engine coverage notes", systemImage: "info.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                        ForEach(Array(coverageNotes.enumerated()), id: \.offset) { _, note in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.slot).font(.caption2.bold())
                                ForEach(note.lines, id: \.self) { line in
                                    Text("• \(line)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .card()
    }
}

// MARK: - Lead Order Picker

/// VGC-style "bring 6 pick N" selector. The user taps slots in the order they
/// want them sent out; the first `activeSlots` become the field leads and the
/// remainder fill the bench.
private struct LeadOrderCard: View {
    let label: String
    let slots: [TeamSlotInfo]
    let bringCount: Int
    let activeSlots: Int
    @Binding var order: [Int]

    @ScaledMetric(relativeTo: .caption) private var tileMinimumWidth: CGFloat = 96
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: tileMinimumWidth), spacing: 8)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.headline)
                Spacer()
                Text("\(order.count)/\(bringCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("Tap to pick your lead order. First \(activeSlots) go to the field, the rest start on the bench.")
                .font(.caption2).foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(slots.enumerated()), id: \.offset) { idx, slot in
                    slotTile(index: idx, slot: slot)
                }
            }

            if !order.isEmpty {
                Button("Clear") { order.removeAll() }
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
        }
        .card()
    }

    @ViewBuilder
    private func slotTile(index: Int, slot: TeamSlotInfo) -> some View {
        let position = order.firstIndex(of: index)
        let isLead = position.map { $0 < activeSlots } ?? false
        let isBench = position.map { $0 >= activeSlots } ?? false
        Button {
            toggle(index)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    // The name sets the tile's height, so a two-line name at
                    // a large text size isn't clipped.
                    Text(slot.pokemonName)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(tileFill(isLead: isLead, isBench: isBench),
                                    in: RoundedRectangle(cornerRadius: 8))
                    if let p = position {
                        Text("\(p + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(isLead ? Color.green : Color.gray))
                            .offset(x: 4, y: -4)
                    }
                }
                Text(roleLabel(isLead: isLead, isBench: isBench))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(position == nil && order.count >= bringCount)
    }

    private func tileFill(isLead: Bool, isBench: Bool) -> Color {
        if isLead { return Color.green.opacity(0.18) }
        if isBench { return Color.gray.opacity(0.18) }
        return Color.secondary.opacity(0.08)
    }

    private func roleLabel(isLead: Bool, isBench: Bool) -> String {
        if isLead { return "Lead" }
        if isBench { return "Bench" }
        return "—"
    }

    private func toggle(_ index: Int) {
        if let existing = order.firstIndex(of: index) {
            order.remove(at: existing)
        } else if order.count < bringCount {
            order.append(index)
        }
    }
}

// MARK: - Battle Screen

private struct BattleView: View {
    @Bindable var engine: BattleEngine
    let ai: PokiiBattleAI?
    let onExit: () -> Void

    /// Combined signal that ticks any time the AI may need to act: new turn,
    /// new force switch, or a partner side just committed an action.
    private var aiTriggerKey: String {
        let pending = engine.pendingActions.flatMap { $0 }.map { $0 == nil ? "0" : "1" }.joined()
        let force = engine.pendingForceSwitches.map { "\($0.side)-\($0.slot)" }.joined()
        return "\(engine.turn)|\(pending)|\(force)|\(engine.winner ?? -1)"
    }

    /// True when both sides are AI-driven; we then auto-run executeTurn once
    /// the model has filled in all the action slots, so the user can just
    /// watch a self-play game unfold.
    private var bothSidesAI: Bool {
        ai?.sideControlled == [true, true]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    globalsBar
                    SideFieldView(side: engine.side2, isOpponent: true)
                    SideFieldView(side: engine.side1, isOpponent: false)
                    Divider()
                    actionPanel
                }
                .padding()
            }
            Divider()
            BattleLogView(entries: engine.log).frame(maxHeight: 220)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Exit") { onExit() }
            }
        }
        .task(id: aiTriggerKey) {
            // Let SwiftUI commit the previous turn's state changes before
            // the AI peeks at the engine; otherwise it might read stale HP
            // / fainted flags from the just-resolved turn.
            try? await Task.sleep(nanoseconds: 30_000_000)
            ai?.fill()
            if bothSidesAI, engine.allActionsChosen {
                try? await Task.sleep(nanoseconds: 250_000_000)
                engine.executeTurn()
            }
        }
    }

    @ViewBuilder
    private var globalsBar: some View {
        if engine.weather != .none || engine.terrain != .none {
            FlowLayout(spacing: 6) {
                if engine.weather != .none {
                    Label("\(engine.weather.rawValue) (\(engine.weatherTurns))", systemImage: "cloud.sun")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.15), in: Capsule())
                        .foregroundStyle(.cyan)
                }
                if engine.terrain != .none {
                    Label("\(engine.terrain.rawValue) Terrain (\(engine.terrainTurns))", systemImage: "leaf")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var actionPanel: some View {
        if let winner = engine.winner {
            VStack(spacing: 12) {
                Text(winner == 1 ? "Side 1 Wins!" : "Side 2 Wins!").font(.title2.bold())
                Button("New Battle", action: onExit).buttonStyle(.primaryAction)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else if !engine.pendingForceSwitches.isEmpty {
            ForceSwitchPanel(engine: engine)
        } else {
            ActionChooserPanel(engine: engine)
        }
    }
}

// MARK: - Field Views

private struct SideFieldView: View {
    var side: BattleSide
    let isOpponent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                // The hazard chip wraps under the label when both don't fit.
                FlowLayout(spacing: 6) {
                    Text(side.label).font(.subheadline.bold())
                    if !side.hazardSummary.isEmpty {
                        Text(side.hazardSummary)
                            .font(.caption2.bold())
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 3) {
                    ForEach(side.participants.indices, id: \.self) { i in
                        Circle()
                            .fill(side.participants[i].fainted ? Color.gray.opacity(0.4) : Color.green)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(side.activeIndices.contains(i) ? Color.primary : Color.clear, lineWidth: 1.5))
                    }
                }
            }
            ForEach(Array(side.activeIndices.enumerated()), id: \.offset) { _, idx in
                if side.participants.indices.contains(idx) {
                    ParticipantField(p: side.participants[idx])
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isOpponent ? Color.red.opacity(0.06) : Color.blue.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ParticipantField: View {
    var p: BattleParticipant
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                FlowLayout(spacing: 6) {
                    Text(p.displayName).font(.subheadline.bold())
                    TypeBadge(type: p.activeType1)
                    if let t2 = p.activeType2 { TypeBadge(type: t2) }
                    if p.megaForm != nil {
                        Text("MEGA")
                            .font(.caption2.bold())
                            .fixedSize()
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .foregroundStyle(.white)
                            .background(Color.pink, in: Capsule())
                    }
                    if p.status != .none {
                        Text(p.status.shortLabel)
                            .font(.caption2.bold())
                            .fixedSize()
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .foregroundStyle(.white)
                            .background(p.status.color, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Lv\(p.slot.level)").font(.caption2).foregroundStyle(.secondary)
            }
            HPBar(current: p.currentHP, maxHP: p.maxHP)
            HStack {
                Text("\(p.currentHP) / \(p.maxHP) HP")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if p.fainted {
                    Text("FAINTED").font(.caption2.bold()).foregroundStyle(.red)
                }
            }
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct HPBar: View {
    let current: Int
    let maxHP: Int
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.2)).frame(height: 8)
                let pct = maxHP > 0 ? Double(current) / Double(maxHP) : 0
                Capsule()
                    .fill(barColor(pct: pct))
                    .frame(width: geo.size.width * pct, height: 8)
            }
        }
        .frame(height: 8)
    }

    private func barColor(pct: Double) -> Color {
        if pct > 0.5 { return .green }
        if pct > 0.2 { return .yellow }
        return .red
    }
}

// MARK: - Action Chooser

private struct ActionChooserPanel: View {
    @Bindable var engine: BattleEngine

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { sIdx in
                ForEach(0..<engine.format.activeSlots, id: \.self) { slotIdx in
                    if let actor = engine.side(at: sIdx).active(at: slotIdx), !actor.fainted {
                        ActorActionCard(engine: engine,
                                        sideIndex: sIdx, slotIndex: slotIdx,
                                        actor: actor)
                    }
                }
            }
            Button {
                engine.executeTurn()
            } label: {
                Label("Execute Turn", systemImage: "forward.end.fill")
            }
            .buttonStyle(.primaryAction)
            .disabled(!engine.allActionsChosen)
        }
    }
}

private struct ActorActionCard: View {
    @Bindable var engine: BattleEngine
    let sideIndex: Int
    let slotIndex: Int
    var actor: BattleParticipant

    @State private var showSwitchSheet = false
    @State private var pendingChoice: PendingTargetChoice? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum PendingTargetChoice {
        case move(Int)
        case struggle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(engine.side(at: sideIndex).label): \(actor.displayName)")
                        .font(.subheadline.bold())
                    if engine.pendingActions[sideIndex][slotIndex] != nil {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Spe \(actor.speed)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }

            if engine.canMegaEvolve(side: sideIndex, slot: slotIndex) {
                Toggle(isOn: engine.megaBinding(side: sideIndex, slot: slotIndex)) {
                    Label("Mega Evolve", systemImage: "sparkles")
                        .font(.caption.bold())
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(.pink)
                .controlSize(.small)
            }

            if let pending = engine.pendingActions[sideIndex][slotIndex] {
                AdaptiveStack(spacing: 6) {
                    Text(pendingLabel(pending))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Change") {
                        engine.clearAction(side: sideIndex, slot: slotIndex)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            } else {
                moveOrStruggleButtons
                Button {
                    showSwitchSheet = true
                } label: {
                    Label("Switch", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(engine.side(at: sideIndex).benchIndices().isEmpty)
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $showSwitchSheet) {
            SwitchSheet(engine: engine, sideIndex: sideIndex,
                        slotIndex: slotIndex, isPresented: $showSwitchSheet)
            .sheetSize()
        }
        .confirmationDialog(
            "Choose target",
            isPresented: Binding(
                get: { pendingChoice != nil },
                set: { if !$0 { pendingChoice = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(enemyTargets()) { t in
                Button(t.name) {
                    commit(choice: pendingChoice, target: t)
                    pendingChoice = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingChoice = nil }
        }
    }

    @ViewBuilder
    private var moveOrStruggleButtons: some View {
        if actor.moves.isEmpty || !actor.hasAnyPP {
            // No usable moves: Struggle path.
            Button { chooseStruggle() } label: {
                Label("Struggle", systemImage: "bolt.slash")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.gray)
        } else {
            // Disable every move except the locked one while the Choice item is in
            // effect. Reads `effectiveHeldItem` indirectly via `isChoiceLocked` so a
            // knocked-off Choice item correctly frees the holder.
            let locked = engine.isChoiceLocked(actor) ? actor.choiceLockedMoveIndex : nil
            // One column at accessibility sizes, or move names truncate.
            LazyVGrid(columns: dynamicTypeSize.gridColumns(2), spacing: 6) {
                ForEach(0..<actor.moves.count, id: \.self) { mi in
                    let move = actor.moves[mi]
                    let curPP = actor.pp.indices.contains(mi) ? actor.pp[mi] : 0
                    let maxPP = move.pp
                    let isLockedOut = locked != nil && locked != mi
                    // Fake Out / First Impression are unselectable once the
                    // holder has dispatched a move since switching in. The
                    // engine treats forced attempts (Encore) as Struggle.
                    let isFirstTurnOnlyBlocked = actor.isFirstTurnOnlyMoveLockedOut(at: mi)
                    MoveButton(move: move, currentPP: curPP, maxPP: maxPP) {
                        chooseMove(mi)
                    }
                    .disabled(curPP <= 0 || isLockedOut || isFirstTurnOnlyBlocked)
                }
            }
        }
    }

    private func chooseMove(_ moveIndex: Int) {
        guard moveIndex < actor.moves.count else { return }
        let move = actor.moves[moveIndex]
        let isSpread = BattleMoveEffects.isSpread(move.name)

        // Doubles + spread → auto-target both opponents, no picker.
        if engine.format == .doubles && isSpread && move.damageClass != "status" {
            engine.setAction(side: sideIndex, slot: slotIndex,
                             action: .spreadMove(moveIndex: moveIndex))
            return
        }

        // Self / side / field-wide moves (Protect, Tailwind, Calm Mind, Trick
        // Room, hazards…) never need an enemy picker — record the actor as the
        // "target" so the action goes straight into the queue.
        if BattleMoveEffects.isFixedSelfOrFieldTarget(move.name) {
            engine.setAction(side: sideIndex, slot: slotIndex,
                             action: .move(moveIndex: moveIndex,
                                           targetSide: sideIndex, targetSlot: slotIndex))
            return
        }

        let targets = enemyTargets()
        if targets.count <= 1 {
            if let t = targets.first {
                engine.setAction(side: sideIndex, slot: slotIndex,
                                 action: .move(moveIndex: moveIndex,
                                               targetSide: t.side, targetSlot: t.slot))
            } else {
                // No targets (status move targeting nothing): still record the move so the
                // turn can progress. Target side is the opposing side, slot 0.
                let opp = 1 - sideIndex
                engine.setAction(side: sideIndex, slot: slotIndex,
                                 action: .move(moveIndex: moveIndex,
                                               targetSide: opp, targetSlot: 0))
            }
        } else {
            pendingChoice = .move(moveIndex)
        }
    }

    private func chooseStruggle() {
        let targets = enemyTargets()
        if targets.count <= 1 {
            if let t = targets.first {
                engine.setAction(side: sideIndex, slot: slotIndex,
                                 action: .struggle(targetSide: t.side, targetSlot: t.slot))
            }
        } else {
            pendingChoice = .struggle
        }
    }

    private func commit(choice: PendingTargetChoice?, target: EnemyTarget) {
        switch choice {
        case .move(let mi):
            engine.setAction(side: sideIndex, slot: slotIndex,
                             action: .move(moveIndex: mi,
                                           targetSide: target.side, targetSlot: target.slot))
        case .struggle:
            engine.setAction(side: sideIndex, slot: slotIndex,
                             action: .struggle(targetSide: target.side, targetSlot: target.slot))
        case .none:
            break
        }
    }

    private struct EnemyTarget: Identifiable {
        let side: Int
        let slot: Int
        let name: String
        var id: String { "\(side)-\(slot)" }
    }

    private func enemyTargets() -> [EnemyTarget] {
        let enemy = 1 - sideIndex
        let enemySide = engine.side(at: enemy)
        var t: [EnemyTarget] = []
        for i in 0..<engine.format.activeSlots {
            if let p = enemySide.active(at: i), !p.fainted {
                t.append(EnemyTarget(side: enemy, slot: i, name: p.displayName))
            }
        }
        return t
    }

    private func pendingLabel(_ action: BattleAction) -> String {
        let megaPrefix = engine.pendingMega[sideIndex][slotIndex] ? "✦ Mega + " : ""
        switch action {
        case .move(let mi, let ts, let tslot):
            guard mi < actor.moves.count else { return megaPrefix + "Move" }
            let name = actor.moves[mi].name
            if engine.format == .doubles, let target = engine.side(at: ts).active(at: tslot) {
                return "\(megaPrefix)Use \(name) → \(target.displayName)"
            }
            return "\(megaPrefix)Use \(name)"
        case .spreadMove(let mi):
            guard mi < actor.moves.count else { return megaPrefix + "Spread move" }
            return "\(megaPrefix)Use \(actor.moves[mi].name) (spread)"
        case .switchTo(let bench):
            let s = engine.side(at: sideIndex)
            guard bench < s.participants.count else { return "Switch" }
            return "Switch to \(s.participants[bench].displayName)"
        case .struggle(let ts, let tslot):
            if engine.format == .doubles, let target = engine.side(at: ts).active(at: tslot) {
                return "\(megaPrefix)Struggle → \(target.displayName)"
            }
            return "\(megaPrefix)Struggle"
        }
    }
}

private struct MoveButton: View {
    let move: MoveData
    let currentPP: Int
    let maxPP: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                // The name wraps rather than truncating at large text sizes.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(move.name).font(.caption.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TypeBadge(type: move.type)
                }
                HStack(alignment: .top, spacing: 6) {
                    FlowLayout(spacing: 6) {
                        Text("\(move.power ?? 0) BP")
                            .font(.caption2).foregroundStyle(.secondary)
                        if move.priority != 0 {
                            let sign = move.priority > 0 ? "+" : ""
                            Text("Prio \(sign)\(move.priority)")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    DamageClassBadge(damageClass: move.damageClass)
                }
                HStack {
                    Text("PP \(currentPP)/\(maxPP)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(currentPP == 0 ? .red : .secondary)
                    Spacer()
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            .opacity(currentPP == 0 ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

private struct SwitchSheet: View {
    @Bindable var engine: BattleEngine
    let sideIndex: Int
    let slotIndex: Int
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                // Skip bench mons that this side's *other* active slot has
                // already queued a switch into — two pokemon can't tag onto
                // the same teammate on the same turn.
                let claimed = claimedBenchIndices()
                let bench = engine.side(at: sideIndex).benchIndices()
                    .filter { !claimed.contains($0) }
                if bench.isEmpty {
                    Text("No available Pokemon to switch in.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bench, id: \.self) { bi in
                        let p = engine.side(at: sideIndex).participants[bi]
                        Button {
                            engine.setAction(side: sideIndex, slot: slotIndex,
                                             action: .switchTo(benchIndex: bi))
                            isPresented = false
                        } label: {
                            // HP moves under the name at accessibility sizes.
                            AdaptiveStack(spacing: 4) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.displayName).font(.subheadline.bold())
                                    FlowLayout(spacing: 4) {
                                        TypeBadge(type: p.slot.type1)
                                        if let t2 = p.slot.type2 { TypeBadge(type: t2) }
                                        if p.status != .none {
                                            Text(p.status.shortLabel)
                                                .font(.caption2.bold())
                                                .fixedSize()
                                                .padding(.horizontal, 4).padding(.vertical, 1)
                                                .foregroundStyle(.white)
                                                .background(p.status.color, in: Capsule())
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(p.currentHP)/\(p.maxHP)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Switch In")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Bench indices that another active slot on this side has already
    /// committed to switching into. They're hidden from the picker so two
    /// pokemon can't tag onto the same teammate.
    private func claimedBenchIndices() -> Set<Int> {
        var set = Set<Int>()
        for slot in 0..<engine.format.activeSlots where slot != slotIndex {
            if case .switchTo(let bi) = engine.pendingActions[sideIndex][slot] {
                set.insert(bi)
            }
        }
        return set
    }
}

// MARK: - Force Switch Panel

private struct ForceSwitchPanel: View {
    @Bindable var engine: BattleEngine
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 12) {
            ForEach(engine.pendingForceSwitches) { fs in
                let s = engine.side(at: fs.side)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(s.label) must send out a replacement.")
                        .font(.subheadline.bold())
                    LazyVGrid(columns: dynamicTypeSize.gridColumns(2), spacing: 6) {
                        ForEach(s.benchIndices(), id: \.self) { bi in
                            let p = s.participants[bi]
                            Button {
                                engine.forceSwitch(side: fs.side, slot: fs.slot, benchIndex: bi)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.displayName).font(.caption.bold())
                                    Text("\(p.currentHP)/\(p.maxHP) HP")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - Battle Log

private struct BattleLogView: View {
    let entries: [BattleLogEntry]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entries) { e in
                        Text(e.text)
                            .font(e.emphasis ? .footnote.bold() : .footnote)
                            .foregroundStyle(e.emphasis ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(e.id)
                    }
                }
                .padding(10)
            }
            .background(Color(.secondarySystemBackground))
            .onChange(of: entries.count) { _, _ in
                if let last = entries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

#Preview {
    BattleSimulatorView()
        .modelContainer(for: [PKMNStats.self, MoveData.self, SavedTeam.self, SavedSpread.self])
}
