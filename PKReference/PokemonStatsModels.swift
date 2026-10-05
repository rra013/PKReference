//
//  PokemonStatsModels.swift
//  PKReference
//

import Foundation
import SwiftData

// MARK: - Pokemon with Base Stats, Types, Abilities & Learnset

@Model
final class PKMNStats {
    @Attribute(.unique) var id: Int
    var speciesID: Int
    var name: String
    var formName: String?
    var type1: String
    var type2: String?
    var baseHP: Int
    var baseAtk: Int
    var baseDef: Int
    var baseSpAtk: Int
    var baseSpDef: Int
    var baseSpeed: Int
    var ability1: String?
    var ability2: String?
    var hiddenAbility: String?
    var learnableMoveIDs: [Int]

    init(id: Int, speciesID: Int, name: String, formName: String? = nil,
         type1: String, type2: String? = nil,
         baseHP: Int, baseAtk: Int, baseDef: Int,
         baseSpAtk: Int, baseSpDef: Int, baseSpeed: Int,
         ability1: String? = nil, ability2: String? = nil,
         hiddenAbility: String? = nil, learnableMoveIDs: [Int] = []) {
        self.id = id
        self.speciesID = speciesID
        self.name = name
        self.formName = formName
        self.type1 = type1
        self.type2 = type2
        self.baseHP = baseHP
        self.baseAtk = baseAtk
        self.baseDef = baseDef
        self.baseSpAtk = baseSpAtk
        self.baseSpDef = baseSpDef
        self.baseSpeed = baseSpeed
        self.ability1 = ability1
        self.ability2 = ability2
        self.hiddenAbility = hiddenAbility
        self.learnableMoveIDs = learnableMoveIDs
    }

    var allAbilities: [String] {
        [ability1, ability2, hiddenAbility].compactMap { $0 }
    }

    var isForm: Bool {
        formName != nil && !(formName?.isEmpty ?? true)
    }

    /// The National Dex number to show, as "#445". A form's `id` is
    /// PokeAPI's form ID (Mega Garchomp is 10058), so forms show their
    /// species' number instead.
    var dexLabel: String { PKReference.dexLabel(for: speciesID) }
}

/// A National Dex number as players write it: "#1000", never "#1,000".
/// A plain String, because `Text("#\(number)")` localizes the number and
/// adds a thousands separator.
func dexLabel(for number: Int) -> String {
    "#\(number)"
}

// MARK: - Move Data

@Model
final class MoveData {
    @Attribute(.unique) var id: Int
    var name: String
    var type: String
    var damageClass: String // "physical", "special"
    var power: Int?
    var accuracy: Int?
    var pp: Int
    var priority: Int
    var minHits: Int?
    var maxHits: Int?
    var drain: Int
    var healing: Int
    var critRate: Int
    var makesContact: Bool
    var generationId: Int

    init(id: Int, name: String, type: String, damageClass: String,
         power: Int? = nil, accuracy: Int? = nil, pp: Int = 0, priority: Int = 0,
         minHits: Int? = nil, maxHits: Int? = nil,
         drain: Int = 0, healing: Int = 0, critRate: Int = 0, makesContact: Bool = false,
         generationId: Int = 0) {
        self.id = id
        self.name = name
        self.type = type
        self.damageClass = damageClass
        self.power = power
        self.accuracy = accuracy
        self.pp = pp
        self.priority = priority
        self.minHits = minHits
        self.maxHits = maxHits
        self.drain = drain
        self.healing = healing
        self.critRate = critRate
        self.makesContact = makesContact
        self.generationId = generationId
    }
}

// MARK: - Nature

nonisolated struct Nature: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let boosted: StatKey?
    let lowered: StatKey?

    nonisolated enum StatKey: String, CaseIterable, Sendable {
        case atk, def, spAtk, spDef, speed

        var label: String {
            switch self {
            case .atk:   return "Atk"
            case .def:   return "Def"
            case .spAtk: return "Sp.Atk"
            case .spDef: return "Sp.Def"
            case .speed: return "Speed"
            }
        }
    }

    func modifier(for stat: StatKey) -> Double {
        if let b = boosted, b == stat { return 1.1 }
        if let l = lowered, l == stat { return 0.9 }
        return 1.0
    }

    var summary: String {
        guard let b = boosted, let l = lowered else { return "Neutral" }
        return "+\(b.label) / -\(l.label)"
    }
}

nonisolated let allNatures: [Nature] = [
    Nature(id: "hardy",   name: "Hardy",   boosted: nil,    lowered: nil),
    Nature(id: "docile",  name: "Docile",  boosted: nil,    lowered: nil),
    Nature(id: "serious", name: "Serious", boosted: nil,    lowered: nil),
    Nature(id: "bashful", name: "Bashful", boosted: nil,    lowered: nil),
    Nature(id: "quirky",  name: "Quirky",  boosted: nil,    lowered: nil),
    Nature(id: "lonely",  name: "Lonely",  boosted: .atk,   lowered: .def),
    Nature(id: "brave",   name: "Brave",   boosted: .atk,   lowered: .speed),
    Nature(id: "adamant", name: "Adamant", boosted: .atk,   lowered: .spAtk),
    Nature(id: "naughty", name: "Naughty", boosted: .atk,   lowered: .spDef),
    Nature(id: "bold",    name: "Bold",    boosted: .def,   lowered: .atk),
    Nature(id: "relaxed", name: "Relaxed", boosted: .def,   lowered: .speed),
    Nature(id: "impish",  name: "Impish",  boosted: .def,   lowered: .spAtk),
    Nature(id: "lax",     name: "Lax",     boosted: .def,   lowered: .spDef),
    Nature(id: "modest",  name: "Modest",  boosted: .spAtk, lowered: .atk),
    Nature(id: "mild",    name: "Mild",    boosted: .spAtk, lowered: .def),
    Nature(id: "quiet",   name: "Quiet",   boosted: .spAtk, lowered: .speed),
    Nature(id: "rash",    name: "Rash",    boosted: .spAtk, lowered: .spDef),
    Nature(id: "calm",    name: "Calm",    boosted: .spDef, lowered: .atk),
    Nature(id: "gentle",  name: "Gentle",  boosted: .spDef, lowered: .def),
    Nature(id: "sassy",   name: "Sassy",   boosted: .spDef, lowered: .speed),
    Nature(id: "careful", name: "Careful", boosted: .spDef, lowered: .spAtk),
    Nature(id: "timid",   name: "Timid",   boosted: .speed, lowered: .atk),
    Nature(id: "hasty",   name: "Hasty",   boosted: .speed, lowered: .def),
    Nature(id: "jolly",   name: "Jolly",   boosted: .speed, lowered: .spAtk),
    Nature(id: "naive",   name: "Naive",   boosted: .speed, lowered: .spDef),
]

// MARK: - Saved Spread

@Model
final class SavedSpread {
    var name: String
    var pokemonID: Int?
    var pokemonName: String?
    var abilityName: String?
    var itemRawValue: String?
    var championsMode: Bool
    var natureID: String
    var level: Int
    var evHP: Int; var evAtk: Int; var evDef: Int
    var evSpAtk: Int; var evSpDef: Int; var evSpeed: Int
    var ivHP: Int; var ivAtk: Int; var ivDef: Int
    var ivSpAtk: Int; var ivSpDef: Int; var ivSpeed: Int
    var moveID1: Int?
    var moveID2: Int?
    var moveID3: Int?
    var moveID4: Int?
    var createdAt: Date
    /// The set's Tera type, as a type name ("Fairy"), or nil. Kept with the
    /// set and in its paste; nothing Terastallizes yet, since no Champions
    /// regulation allows it. Optional, so stores from before it existed
    /// migrate automatically.
    var teraType: String?

    init(name: String, pokemonID: Int? = nil, pokemonName: String? = nil,
         abilityName: String? = nil, itemRawValue: String? = nil,
         championsMode: Bool = false, natureID: String = "adamant", level: Int = 50,
         evHP: Int = 0, evAtk: Int = 0, evDef: Int = 0,
         evSpAtk: Int = 0, evSpDef: Int = 0, evSpeed: Int = 0,
         ivHP: Int = 31, ivAtk: Int = 31, ivDef: Int = 31,
         ivSpAtk: Int = 31, ivSpDef: Int = 31, ivSpeed: Int = 31,
         moveID1: Int? = nil, moveID2: Int? = nil,
         moveID3: Int? = nil, moveID4: Int? = nil,
         teraType: String? = nil) {
        self.name = name
        self.pokemonID = pokemonID
        self.pokemonName = pokemonName
        self.abilityName = abilityName
        self.itemRawValue = itemRawValue
        self.championsMode = championsMode
        self.natureID = natureID
        self.level = level
        self.evHP = evHP; self.evAtk = evAtk; self.evDef = evDef
        self.evSpAtk = evSpAtk; self.evSpDef = evSpDef; self.evSpeed = evSpeed
        self.ivHP = ivHP; self.ivAtk = ivAtk; self.ivDef = ivDef
        self.ivSpAtk = ivSpAtk; self.ivSpDef = ivSpDef; self.ivSpeed = ivSpeed
        self.moveID1 = moveID1; self.moveID2 = moveID2
        self.moveID3 = moveID3; self.moveID4 = moveID4
        self.createdAt = Date()
        self.teraType = teraType
    }
}

// MARK: - Saved Team

@Model
final class SavedTeam {
    var name: String
    var createdAt: Date

    /// JSON-encoded array of `TeamSlotInfo` (up to 6 slots).
    var slotsJSON: Data

    init(name: String, slots: [TeamSlotInfo] = []) {
        self.name = name
        self.createdAt = Date()
        self.slotsJSON = (try? JSONEncoder().encode(slots)) ?? Data()
    }

    var slots: [TeamSlotInfo] {
        get { (try? JSONDecoder().decode([TeamSlotInfo].self, from: slotsJSON)) ?? [] }
        set { slotsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Returns the team's slots resolved against the live `SavedSpread` records by
    /// name. Each slot stores a JSON snapshot when added (so the team survives spread
    /// deletion), but display and battle code should call this so subsequent edits to
    /// the underlying spread — new moves, EVs, ability, etc. — propagate automatically.
    /// If a slot's `spreadName` no longer matches any saved spread, the cached
    /// snapshot is returned as a fallback.
    func resolvedSlots(allSpreads: [SavedSpread],
                       allPokemon: [PKMNStats],
                       allMoves: [MoveData]) -> [TeamSlotInfo] {
        slots.map { stored -> TeamSlotInfo in
            guard let live = allSpreads.first(where: { $0.name == stored.spreadName }) else {
                return stored
            }
            let pkmn = allPokemon.first(where: { $0.id == live.pokemonID })
            return TeamSlotInfo.from(spread: live, pokemon: pkmn, moves: allMoves) ?? stored
        }
    }
}

struct TeamSlotInfo: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var spreadName: String
    var pokemonID: Int
    var pokemonName: String
    var type1: String
    var type2: String?
    var abilityName: String?
    var itemRawValue: String?
    var championsMode: Bool = false
    var natureID: String = "adamant"
    var level: Int = 50
    var evHP: Int = 0; var evAtk: Int = 0; var evDef: Int = 0
    var evSpAtk: Int = 0; var evSpDef: Int = 0; var evSpeed: Int = 0
    var moveSlots: [TeamMoveInfo]
    /// The set's Tera type; see `SavedSpread.teraType`. Teams saved before
    /// it existed decode it as nil.
    var teraType: String? = nil

    static func from(spread: SavedSpread, pokemon: PKMNStats?, moves: [MoveData]) -> TeamSlotInfo? {
        guard let pokemon else { return nil }
        let moveIDs = [spread.moveID1, spread.moveID2, spread.moveID3, spread.moveID4]
        let resolvedMoves = moveIDs.compactMap { mid -> TeamMoveInfo? in
            guard let mid, let move = moves.first(where: { $0.id == mid }) else { return nil }
            let pokemonTypes = [pokemon.type1] + [pokemon.type2].compactMap { $0 }
            let isAttacking = move.damageClass != "status"
            return TeamMoveInfo(moveID: move.id, moveName: move.name, moveType: move.type,
                                damageClass: move.damageClass, power: move.power,
                                isSTAB: isAttacking && pokemonTypes.contains(move.type))
        }
        return TeamSlotInfo(
            spreadName: spread.name,
            pokemonID: pokemon.id,
            pokemonName: pokemon.name,
            type1: pokemon.type1, type2: pokemon.type2,
            abilityName: spread.abilityName,
            itemRawValue: spread.itemRawValue,
            championsMode: spread.championsMode,
            natureID: spread.natureID,
            level: spread.level,
            evHP: spread.evHP, evAtk: spread.evAtk, evDef: spread.evDef,
            evSpAtk: spread.evSpAtk, evSpDef: spread.evSpDef, evSpeed: spread.evSpeed,
            moveSlots: resolvedMoves,
            teraType: spread.teraType
        )
    }
}

struct TeamMoveInfo: Codable, Identifiable, Equatable {
    var id: Int { moveID }
    var moveID: Int
    var moveName: String
    var moveType: String
    var damageClass: String
    var power: Int?
    var isSTAB: Bool
}

// MARK: - EV System

// Main-series scale
nonisolated let maxEVPerStat = 252
nonisolated let maxTotalEVs = 510

// Champions scale: stat points, where 32 buy what 252 EVs do in the main
// formula. That exchange rate is a game mechanic; the caps are regulation
// rules, read from the current regulation's JSON.
nonisolated let championsStatPointsPer252EVs = 32

/// The current regulation's per-stat stat-point cap (32 so far).
nonisolated var championsMaxEVPerStat: Int {
    ChampionsRegulation.current.rules().statPointsMaxPerStat
}

/// The current regulation's total stat-point cap (66 so far).
nonisolated var championsMaxTotalEVs: Int {
    ChampionsRegulation.current.rules().statPointsMaxTotal
}

/// The IV every stat is locked at in the current regulation (31 so far).
nonisolated var championsLockedIV: Int {
    ChampionsRegulation.current.rules().ivLockedAt
}

/// Convert a Champions-scale EV (stat points) to the main-series value used in stat formulas.
nonisolated func championsEVToMain(_ cev: Int) -> Int {
    return cev * maxEVPerStat / championsStatPointsPer252EVs
}

/// Convert main-series EVs to Champions stat points, rounding down, so 252
/// is 32. Callers cap the result themselves.
nonisolated func mainEVToChampions(_ ev: Int) -> Int {
    ev * championsStatPointsPer252EVs / maxEVPerStat
}

// MARK: - Stat Calculation (Gen III+ formula)

nonisolated func calcHP(base: Int, iv: Int, ev: Int, level: Int) -> Int {
    if base == 1 { return 1 } // Shedinja
    return ((2 * base + iv + ev / 4) * level / 100) + level + 10
}

nonisolated func calcStat(base: Int, iv: Int, ev: Int, level: Int, natureMod: Double) -> Int {
    let raw = ((2 * base + iv + ev / 4) * level / 100) + 5
    return Int(Double(raw) * natureMod)
}

nonisolated func statStageMultiplier(stage: Int) -> Double {
    let clamped = max(-6, min(6, stage))
    if clamped >= 0 {
        return Double(2 + clamped) / 2.0
    } else {
        return 2.0 / Double(2 - clamped)
    }
}

// MARK: - Weather

// MARK: - Held Items

/// A held item, identified by its name ("Leftovers"), which is also how
/// saved sets store it (`itemRawValue`).
///
/// Items with an effect are declared below, since their effects are code;
/// `case .choiceBand:` and `== .leftovers` work as they did when this was
/// an enum. Mega stones aren't declared: each stone-triggered form in
/// `mega_forms.json` names its stone, and that makes it an item. Adding a
/// Mega is a line there.
nonisolated struct HeldItem: RawRepresentable, Hashable, CaseIterable, Identifiable,
                             CustomStringConvertible, Sendable {
    let rawValue: String

    /// A known item: a built-in one, or a Mega stone from `mega_forms.json`.
    /// An item's old name (`renamed`) gives the item under its current name.
    init?(rawValue: String) {
        let name = Self.currentName(rawValue)
        guard Self.knownNames.contains(name) else { return nil }
        self.rawValue = name
    }

    /// Items whose names were corrected, old name to current. Saved sets and
    /// teams keep the name they were saved with, so lookups go through
    /// `currentName`. Golisopite and Baxcalibrite were guessed as
    /// "Golisopodite" and "Baxcaliburite" before Serebii listed them.
    static let renamed: [String: String] = [
        "Golisopodite": "Golisopite",
        "Baxcaliburite": "Baxcalibrite",
    ]

    /// `name`, or its current name if the item was renamed.
    static func currentName(_ name: String) -> String {
        renamed[name] ?? name
    }

    private init(_ name: String) { rawValue = name }

    var id: String { rawValue }
    var description: String { rawValue }

    static let none = HeldItem("None")

    // Offensive
    static let choiceBand = HeldItem("Choice Band")
    static let choiceSpecs = HeldItem("Choice Specs")
    static let lifeOrb = HeldItem("Life Orb")
    static let expertBelt = HeldItem("Expert Belt")
    static let metronome = HeldItem("Metronome")

    // Type-boosting plates / gems
    static let typeBoost = HeldItem("Type-Boost (1.2x)")

    // Defensive
    static let assaultVest = HeldItem("Assault Vest")
    static let eviolite = HeldItem("Eviolite")

    // Species-specific
    static let lightBall = HeldItem("Light Ball")
    static let thickClub = HeldItem("Thick Club")

    // Type-boosting items (1.2x to moves of the listed type).
    static let silkScarf       = HeldItem("Silk Scarf")        // Normal
    static let charcoal        = HeldItem("Charcoal")          // Fire
    static let mysticWater     = HeldItem("Mystic Water")      // Water
    static let magnet          = HeldItem("Magnet")            // Electric
    static let miracleSeed     = HeldItem("Miracle Seed")      // Grass
    static let neverMeltIce    = HeldItem("Never-Melt Ice")    // Ice
    static let blackBelt       = HeldItem("Black Belt")        // Fighting
    static let poisonBarb      = HeldItem("Poison Barb")       // Poison
    static let softSand        = HeldItem("Soft Sand")         // Ground
    static let sharpBeak       = HeldItem("Sharp Beak")        // Flying
    static let twistedSpoon    = HeldItem("Twisted Spoon")     // Psychic
    static let silverPowder    = HeldItem("Silver Powder")     // Bug
    static let hardStone       = HeldItem("Hard Stone")        // Rock
    static let spellTag        = HeldItem("Spell Tag")         // Ghost
    static let dragonFang      = HeldItem("Dragon Fang")       // Dragon
    static let blackGlasses    = HeldItem("Black Glasses")     // Dark
    static let metalCoat       = HeldItem("Metal Coat")        // Steel
    static let fairyFeather    = HeldItem("Fairy Feather")     // Fairy

    // Other competitive items
    static let choiceScarf     = HeldItem("Choice Scarf")
    static let focusSash       = HeldItem("Focus Sash")
    static let focusBand       = HeldItem("Focus Band")
    static let leftovers       = HeldItem("Leftovers")
    static let scopeLens       = HeldItem("Scope Lens")
    static let shellBell       = HeldItem("Shell Bell")
    static let quickClaw       = HeldItem("Quick Claw")
    static let kingsRock       = HeldItem("King's Rock")
    static let brightPowder    = HeldItem("Bright Powder")
    static let mentalHerb      = HeldItem("Mental Herb")
    static let whiteHerb       = HeldItem("White Herb")
    static let rockyHelmet     = HeldItem("Rocky Helmet")
    static let lightClay       = HeldItem("Light Clay")   // extends screens from 5 → 8 turns

    // Healing & status berries
    static let aspearBerry     = HeldItem("Aspear Berry")
    static let cheriBerry      = HeldItem("Cheri Berry")
    static let chestoBerry     = HeldItem("Chesto Berry")
    static let leppaBerry      = HeldItem("Leppa Berry")
    static let lumBerry        = HeldItem("Lum Berry")
    static let oranBerry       = HeldItem("Oran Berry")
    static let pechaBerry      = HeldItem("Pecha Berry")
    static let persimBerry     = HeldItem("Persim Berry")
    static let rawstBerry      = HeldItem("Rawst Berry")
    static let sitrusBerry     = HeldItem("Sitrus Berry")

    // Type-resist berries (halve a supereffective hit of the matching type, once).
    static let occaBerry       = HeldItem("Occa Berry")        // Fire
    static let passhoBerry     = HeldItem("Passho Berry")      // Water
    static let wacanBerry      = HeldItem("Wacan Berry")       // Electric
    static let rindoBerry      = HeldItem("Rindo Berry")       // Grass
    static let yacheBerry      = HeldItem("Yache Berry")       // Ice
    static let chopleBerry     = HeldItem("Chople Berry")      // Fighting
    static let kebiaBerry      = HeldItem("Kebia Berry")       // Poison
    static let shucaBerry      = HeldItem("Shuca Berry")       // Ground
    static let cobaBerry       = HeldItem("Coba Berry")        // Flying
    static let payapaBerry     = HeldItem("Payapa Berry")      // Psychic
    static let tangaBerry      = HeldItem("Tanga Berry")       // Bug
    static let chartiBerry     = HeldItem("Charti Berry")      // Rock
    static let kasibBerry      = HeldItem("Kasib Berry")       // Ghost
    static let habanBerry      = HeldItem("Haban Berry")       // Dragon
    static let colburBerry     = HeldItem("Colbur Berry")      // Dark
    static let babiriBerry     = HeldItem("Babiri Berry")      // Steel
    static let roseliBerry     = HeldItem("Roseli Berry")      // Fairy
    static let chilanBerry     = HeldItem("Chilan Berry")      // Normal (triggers regardless of effectiveness)

    /// Every built-in item, in picker order. A new built-in item needs an
    /// entry here as well as its declaration above.
    static let builtIns: [HeldItem] = [
        .none, .choiceBand, .choiceSpecs, .lifeOrb, .expertBelt,
        .metronome, .typeBoost, .assaultVest, .eviolite, .lightBall,
        .thickClub, .silkScarf, .charcoal, .mysticWater, .magnet,
        .miracleSeed, .neverMeltIce, .blackBelt, .poisonBarb, .softSand,
        .sharpBeak, .twistedSpoon, .silverPowder, .hardStone, .spellTag,
        .dragonFang, .blackGlasses, .metalCoat, .fairyFeather, .choiceScarf,
        .focusSash, .focusBand, .leftovers, .scopeLens, .shellBell,
        .quickClaw, .kingsRock, .brightPowder, .mentalHerb, .whiteHerb,
        .rockyHelmet, .lightClay, .aspearBerry, .cheriBerry, .chestoBerry,
        .leppaBerry, .lumBerry, .oranBerry, .pechaBerry, .persimBerry,
        .rawstBerry, .sitrusBerry, .occaBerry, .passhoBerry, .wacanBerry,
        .rindoBerry, .yacheBerry, .chopleBerry, .kebiaBerry, .shucaBerry,
        .cobaBerry, .payapaBerry, .tangaBerry, .chartiBerry, .kasibBerry,
        .habanBerry, .colburBerry, .babiriBerry, .roseliBerry, .chilanBerry,
    ]

    /// Every item: the built-in ones, then the Mega stones in
    /// `mega_forms.json` order.
    static let allCases: [HeldItem] = builtIns + MegaForms.all.compactMap(\.stone)

    private static let knownNames = Set(allCases.map(\.rawValue))

    /// The stone a stone-triggered form in `mega_forms.json` names. Called
    /// while that file loads, so it can't consult `allCases`; it only
    /// refuses a name that's already a built-in item.
    static func megaStone(named name: String) -> HeldItem? {
        builtInNames.contains(name) ? nil : HeldItem(name)
    }

    private static let builtInNames = Set(builtIns.map(\.rawValue))

    /// True for any item that exists as a Mega Stone in `MegaForms.all`. Used by
    /// Knock Off (can't remove a Mega Stone) and similar item-removal effects.
    var isMegaStone: Bool {
        MegaForms.all.contains { $0.stone == self }
    }

    /// True for any held item whose display name ends in "Berry" (Oran, Sitrus, Lum,
    /// Occa, ...). Used by Harvest to know which consumed items can be regrown.
    var isBerry: Bool {
        rawValue.hasSuffix("Berry")
    }

    /// Items that don't exist in the Champions format and that the vendored
    /// `champions.ts` damage pipeline doesn't model. Champions-mode pickers
    /// leave them out; the mainline engine does model them.
    static let nonChampionsItems: Set<HeldItem> = [
        .choiceBand, .choiceSpecs, .assaultVest, .eviolite, .thickClub,
    ]

    /// The items to offer in a set's item picker.
    ///
    /// - With a species, its own Mega stones come first and every other
    ///   stone is left out, so the list isn't 86 irrelevant stones. Rayquaza,
    ///   which Mega Evolves by Dragon Ascent, gets none. With no species,
    ///   every stone is listed.
    /// - In Champions mode, `nonChampionsItems` are left out.
    /// - `current`, the item the set holds, is always listed, even if the
    ///   rules above would leave it out (a set pasted or saved in another
    ///   mode), so a picker never shows a blank selection.
    static func pickerOptions(forSpeciesNamed speciesName: String?, championsMode: Bool,
                              keeping current: HeldItem = .none) -> [HeldItem] {
        func offered(_ item: HeldItem) -> Bool {
            !(championsMode && nonChampionsItems.contains(item))
        }
        guard let name = speciesName else {
            return allCases.filter { offered($0) || $0 == current }
        }
        let key = BattleSimSeed.normalize(name)
        let ownStones = MegaForms.all
            .filter { $0.speciesKey == key }
            .compactMap { $0.stone }
        var result = ownStones
        for item in allCases where !ownStones.contains(item) {
            if item == current || (!item.isMegaStone && offered(item)) {
                result.append(item)
            }
        }
        return result
    }

    /// The item's name in a picker. In Champions mode, an item the calc
    /// ignores says so, since a set can still hold one.
    func pickerLabel(championsMode: Bool) -> String {
        championsMode && Self.nonChampionsItems.contains(self) ? "\(rawValue) (not in Champions)" : rawValue
    }
}

/// Maps a damage-affecting held item to the type it boosts. Used by the damage calc
/// to apply 1.2x to moves of that type without bloating the main switch statement.
nonisolated let typeBoostingItemMap: [HeldItem: String] = [
    .silkScarf: "Normal", .charcoal: "Fire", .mysticWater: "Water",
    .magnet: "Electric", .miracleSeed: "Grass", .neverMeltIce: "Ice",
    .blackBelt: "Fighting", .poisonBarb: "Poison", .softSand: "Ground",
    .sharpBeak: "Flying", .twistedSpoon: "Psychic", .silverPowder: "Bug",
    .hardStone: "Rock", .spellTag: "Ghost", .dragonFang: "Dragon",
    .blackGlasses: "Dark", .metalCoat: "Steel", .fairyFeather: "Fairy",
]

/// Maps a type-resist berry to the move type it resists. Triggers in the damage calc
/// (halves damage) and is consumed by the engine after the hit.
nonisolated let typeResistBerryMap: [HeldItem: String] = [
    .occaBerry: "Fire", .passhoBerry: "Water", .wacanBerry: "Electric",
    .rindoBerry: "Grass", .yacheBerry: "Ice", .chopleBerry: "Fighting",
    .kebiaBerry: "Poison", .shucaBerry: "Ground", .cobaBerry: "Flying",
    .payapaBerry: "Psychic", .tangaBerry: "Bug", .chartiBerry: "Rock",
    .kasibBerry: "Ghost", .habanBerry: "Dragon", .colburBerry: "Dark",
    .babiriBerry: "Steel", .roseliBerry: "Fairy",
]

nonisolated struct ItemModResult: Sendable {
    var atkMultiplier: Double = 1.0
    var spAtkMultiplier: Double = 1.0
    var defMultiplier: Double = 1.0
    var spDefMultiplier: Double = 1.0
    var damageMult: Double = 1.0
}

nonisolated func computeItemModifiers(
    attackerItem: HeldItem,
    defenderItem: HeldItem,
    isPhysical: Bool,
    typeEffectiveness: Double,
    moveType: String
) -> ItemModResult {
    var r = ItemModResult()

    // Attacker items
    switch attackerItem {
    case .choiceBand:
        if isPhysical { r.atkMultiplier = 1.5 }
    case .choiceSpecs:
        if !isPhysical { r.spAtkMultiplier = 1.5 }
    case .lifeOrb:
        r.damageMult = 5324.0 / 4096.0 // ~1.3, exact game value
    case .expertBelt:
        if typeEffectiveness > 1.0 { r.damageMult = 1.2 }
    case .metronome:
        break // user adjusts via misc multiplier
    case .typeBoost:
        r.damageMult = 1.2
    case .lightBall:
        r.atkMultiplier = 2.0; r.spAtkMultiplier = 2.0
    case .thickClub:
        if isPhysical { r.atkMultiplier = 2.0 }
    default:
        break
    }

    // Attacker: type-specific 1.2x boosters (Charcoal, Magnet, Silk Scarf, ...)
    if let boostedType = typeBoostingItemMap[attackerItem], boostedType == moveType {
        r.damageMult *= 1.2
    }

    // Defender items
    switch defenderItem {
    case .assaultVest:
        r.spDefMultiplier = 1.5
    case .eviolite:
        r.defMultiplier = 1.5; r.spDefMultiplier = 1.5
    default:
        break
    }

    // Defender: type-resist berries (halve a supereffective hit of that type).
    // Chilan Berry is special — halves any Normal-type hit regardless of effectiveness.
    if let resistedType = typeResistBerryMap[defenderItem],
       resistedType == moveType,
       typeEffectiveness > 1.0 {
        r.damageMult *= 0.5
    }
    if defenderItem == .chilanBerry && moveType == "Normal" {
        r.damageMult *= 0.5
    }

    return r
}

// MARK: - Weather

nonisolated enum WeatherCondition: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case sun = "Sun"
    case rain = "Rain"
    case sand = "Sand"
    case snow = "Snow"

    var id: String { rawValue }

    /// Multiplier applied to the move's damage based on its type.
    func moveDamageMultiplier(moveType: String) -> Double {
        switch self {
        case .sun:
            if moveType == "Fire"  { return 1.5 }
            if moveType == "Water" { return 0.5 }
        case .rain:
            if moveType == "Water" { return 1.5 }
            if moveType == "Fire"  { return 0.5 }
        default:
            break
        }
        return 1.0
    }

    /// Sandstorm: Rock types get 1.5x SpDef.
    func sandSpDefMultiplier(defenderTypes: [String]) -> Double {
        if self == .sand && defenderTypes.contains("Rock") { return 1.5 }
        return 1.0
    }

    /// Snow: Ice types get 1.5x Def.
    func snowDefMultiplier(defenderTypes: [String]) -> Double {
        if self == .snow && defenderTypes.contains("Ice") { return 1.5 }
        return 1.0
    }
}

// MARK: - Terrain

nonisolated enum TerrainCondition: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case electric = "Electric"
    case grassy = "Grassy"
    case misty = "Misty"
    case psychic = "Psychic"

    var id: String { rawValue }

    /// Multiplier applied to the move's damage based on its type.
    func moveDamageMultiplier(moveType: String) -> Double {
        switch self {
        case .electric:
            if moveType == "Electric" { return 1.3 }
        case .grassy:
            if moveType == "Grass" { return 1.3 }
        case .misty:
            if moveType == "Dragon" { return 0.5 }
        case .psychic:
            if moveType == "Psychic" { return 1.3 }
        case .none:
            break
        }
        return 1.0
    }
}

// MARK: - Ability Damage Modifiers

/// All competitively relevant abilities that modify damage calculation.
nonisolated enum DamageAbility: String, CaseIterable, Identifiable, Sendable {
    // Attacker — stat / power multipliers
    case adaptability = "adaptability"
    case aerilate = "aerilate"
    case analytic = "analytic"
    case blaze = "blaze"
    case darkAura = "dark-aura"
    case dragonsMaw = "dragons-maw"
    case fairyAura = "fairy-aura"
    case galvanize = "galvanize"
    case gorillaTactics = "gorilla-tactics"
    case hugePower = "huge-power"
    case hustle = "hustle"
    case ironFist = "iron-fist"
    case megaLauncher = "mega-launcher"
    case normalize = "normalize"
    case overgrow = "overgrow"
    case pixilate = "pixilate"
    case protean = "protean"
    case libero = "libero"
    case purePower = "pure-power"
    case punkRock = "punk-rock"
    case reckless = "reckless"
    case refrigerate = "refrigerate"
    case sandForce = "sand-force"
    case sheerForce = "sheer-force"
    case sniperAbility = "sniper"
    case solarPower = "solar-power"
    case stakeout = "stakeout"
    case steelworker = "steelworker"
    case strongJaw = "strong-jaw"
    case supremeOverlord = "supreme-overlord"
    case swarm = "swarm"
    case technician = "technician"
    case tintedLens = "tinted-lens"
    case torrent = "torrent"
    case toughClaws = "tough-claws"
    case transistor = "transistor"
    case waterBubble = "water-bubble"
    // Defender — damage reduction / immunities
    case drySkin = "dry-skin"
    case filter = "filter"
    case flashFire = "flash-fire"
    case fluffy = "fluffy"
    case furCoat = "fur-coat"
    case heatproof = "heatproof"
    case iceScales = "ice-scales"
    case levitate = "levitate"
    case lightningRod = "lightning-rod"
    case marvelScale = "marvel-scale"
    case motorDrive = "motor-drive"
    case multiscale = "multiscale"
    case prismArmor = "prism-armor"
    case punkRockDefense = "punk-rock-def" // same ability, defender side
    case sapSipper = "sap-sipper"
    case shadowShield = "shadow-shield"
    case solidRock = "solid-rock"
    case stormDrain = "storm-drain"
    case thickFat = "thick-fat"
    case voltAbsorb = "volt-absorb"
    case waterAbsorb = "water-absorb"
    case waterBubbleDefense = "water-bubble-def" // same ability, defender side
    case wonderGuard = "wonder-guard"

    // Gen IX+ attacker abilities
    case scrappy = "scrappy"
    case mindsEye = "minds-eye"
    case guts = "guts"
    case toxicBoost = "toxic-boost"
    case flareBoost = "flare-boost"
    case defeatist = "defeatist"
    case slowStart = "slow-start"
    case rockyPayload = "rocky-payload"
    case sharpness = "sharpness"
    case neuroforce = "neuroforce"
    case orichalcumPulse = "orichalcum-pulse"
    case hadronEngine = "hadron-engine"
    case steelySpirit = "steely-spirit"
    case battery = "battery"
    case powerSpot = "power-spot"
    case parentalBond = "parental-bond"
    case swordOfRuin = "sword-of-ruin"
    case beadsOfRuin = "beads-of-ruin"

    // Gen IX+ defender abilities
    case purifyingSalt = "purifying-salt"
    case wellBakedBody = "well-baked-body"
    case earthEater = "earth-eater"
    case teraShell = "tera-shell"
    case tabletsOfRuin = "tablets-of-ruin"
    case vesselOfRuin = "vessel-of-ruin"
    case friendGuard = "friend-guard"

    // Pokemon Champions Regulation M-B abilities
    case fireMane = "fire-mane"    // Mega Pyroar — +50% Fire move power
    case eelevate = "eelevate"     // Mega Eelektross — Ground/hazard immunity

    var id: String { rawValue }

    var displayName: String {
        rawValue.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }
}

nonisolated struct AbilityModResult: Sendable {
    var atkMultiplier: Double = 1.0
    var defMultiplier: Double = 1.0
    var powerMultiplier: Double = 1.0
    var stabOverride: Double?       // e.g. Adaptability makes STAB 2.0
    var critMultiplierOverride: Double?  // Sniper makes crit 2.25x
    var typeEffOverride: Double?    // Immunities
    var finalMultiplier: Double = 1.0
}

nonisolated func computeAbilityModifiers(
    attackerAbility: String?,
    defenderAbility: String?,
    moveType: String,
    movePower: Int,
    isPhysical: Bool,
    isContact: Bool,
    isSTAB: Bool,
    typeEffectiveness: Double,
    weather: WeatherCondition,
    attackerAtFullHP: Bool,
    defenderAtFullHP: Bool,
    defenderTypes: [String] = [],
    terrain: TerrainCondition = .none,
    isSpread: Bool = false,
    moldBreaker: Bool = false
) -> AbilityModResult {
    var r = AbilityModResult()
    let atk = attackerAbility ?? ""
    // Mold Breaker suppresses the defender's ability for ALL damage-calc
    // purposes — type immunities (Levitate, Volt Absorb, …) and damage
    // reducers (Multiscale, Thick Fat, …) both no-op when the attacker has it.
    let def = moldBreaker ? "" : (defenderAbility ?? "")

    // --- Attacker abilities ---

    switch atk {
    case "adaptability":
        if isSTAB { r.stabOverride = 2.0 }

    case "protean", "libero":
        // Grants STAB on every move (type changes to match move)
        if !isSTAB { r.stabOverride = 1.5 }

    case "huge-power", "pure-power":
        if isPhysical { r.atkMultiplier *= 2.0 }

    case "hustle":
        if isPhysical { r.atkMultiplier *= 1.5 }

    case "gorilla-tactics":
        if isPhysical { r.atkMultiplier *= 1.5 }

    case "solar-power":
        if weather == .sun && !isPhysical { r.atkMultiplier *= 1.5 }

    case "water-bubble":
        // 2x Water move power + halves incoming Fire damage (defender handled below)
        if moveType == "Water" { r.powerMultiplier *= 2.0 }

    case "transistor":
        if moveType == "Electric" { r.powerMultiplier *= 1.3 }

    case "dragons-maw":
        if moveType == "Dragon" { r.powerMultiplier *= 1.5 }

    case "fire-mane":
        // Pokemon Champions ability (Mega Pyroar): +50% to the holder's
        // Fire-type moves.
        if moveType == "Fire" { r.powerMultiplier *= 1.5 }

    case "steelworker":
        if moveType == "Steel" { r.powerMultiplier *= 1.5 }

    case "dark-aura":
        if moveType == "Dark" { r.powerMultiplier *= 1.33 }

    case "fairy-aura":
        if moveType == "Fairy" { r.powerMultiplier *= 1.33 }

    case "blaze":
        if moveType == "Fire" && !attackerAtFullHP { r.powerMultiplier *= 1.5 }

    case "torrent":
        if moveType == "Water" && !attackerAtFullHP { r.powerMultiplier *= 1.5 }

    case "overgrow":
        if moveType == "Grass" && !attackerAtFullHP { r.powerMultiplier *= 1.5 }

    case "swarm":
        if moveType == "Bug" && !attackerAtFullHP { r.powerMultiplier *= 1.5 }

    case "technician":
        if movePower <= 60 { r.powerMultiplier *= 1.5 }

    case "tough-claws":
        if isContact { r.powerMultiplier *= 1.3 }

    case "iron-fist":
        r.powerMultiplier *= 1.2 // applies to punching moves; simplified

    case "strong-jaw":
        r.powerMultiplier *= 1.5 // applies to biting moves; simplified

    case "mega-launcher":
        r.powerMultiplier *= 1.5 // applies to pulse/aura moves; simplified

    case "punk-rock":
        r.powerMultiplier *= 1.3 // applies to sound moves; simplified

    case "reckless":
        r.powerMultiplier *= 1.2 // applies to recoil moves; simplified

    case "sheer-force":
        r.powerMultiplier *= 1.3 // applies to moves with secondary effects; simplified

    case "sand-force":
        // 1.3x to Rock/Ground/Steel in sand
        if weather == .sand && (moveType == "Rock" || moveType == "Ground" || moveType == "Steel") {
            r.powerMultiplier *= 1.3
        }

    case "analytic":
        r.powerMultiplier *= 1.3 // if moving last; user toggled

    case "stakeout":
        r.powerMultiplier *= 2.0 // if target switched in; simplified

    case "supreme-overlord":
        r.powerMultiplier *= 1.1 // 1.1x per fainted ally, simplified to 1 fainted

    case "tinted-lens":
        // Doubles damage of "not very effective" moves
        if typeEffectiveness < 1.0 && typeEffectiveness > 0 {
            r.finalMultiplier *= 2.0
        }

    case "sniper":
        r.critMultiplierOverride = 2.25

    case "normalize":
        // All moves become Normal type; 1.2x power boost (Gen VII+)
        r.powerMultiplier *= 1.2

    case "aerilate":
        if moveType == "Normal" { r.powerMultiplier *= 1.2 }
    case "pixilate":
        if moveType == "Normal" { r.powerMultiplier *= 1.2 }
    case "refrigerate":
        if moveType == "Normal" { r.powerMultiplier *= 1.2 }
    case "galvanize":
        if moveType == "Normal" { r.powerMultiplier *= 1.2 }

    case "scrappy", "minds-eye":
        // Normal and Fighting moves can hit Ghost types
        if (moveType == "Normal" || moveType == "Fighting") && typeEffectiveness == 0 {
            var recalc = 1.0
            let chart = typeEffectivenessChart[moveType] ?? [:]
            for dt in defenderTypes {
                if dt == "Ghost" { continue }
                recalc *= chart[dt] ?? 1.0
            }
            r.typeEffOverride = recalc
        }

    case "guts":
        if isPhysical { r.atkMultiplier *= 1.5 }

    case "toxic-boost":
        if isPhysical { r.atkMultiplier *= 1.5 }

    case "flare-boost":
        if !isPhysical { r.atkMultiplier *= 1.5 }

    case "defeatist":
        if !attackerAtFullHP { r.atkMultiplier *= 0.5 }

    case "slow-start":
        if isPhysical { r.atkMultiplier *= 0.5 }

    case "rocky-payload":
        if moveType == "Rock" { r.powerMultiplier *= 1.5 }

    case "sharpness":
        r.powerMultiplier *= 1.5 // applies to slicing moves; simplified

    case "neuroforce":
        if typeEffectiveness > 1.0 { r.finalMultiplier *= 1.25 }

    case "orichalcum-pulse":
        if weather == .sun && isPhysical { r.atkMultiplier *= (4.0 / 3.0) }

    case "hadron-engine":
        if !isPhysical && terrain == .electric { r.atkMultiplier *= (4.0 / 3.0) }

    case "steely-spirit":
        if moveType == "Steel" { r.powerMultiplier *= 1.5 }

    case "battery":
        if !isPhysical { r.finalMultiplier *= 1.3 }

    case "power-spot":
        r.finalMultiplier *= 1.3

    case "parental-bond":
        // Parental Bond does not activate on spread (multi-target) moves in doubles.
        if !isSpread { r.powerMultiplier *= 1.25 }

    case "sword-of-ruin":
        if isPhysical { r.defMultiplier *= 0.75 }

    case "beads-of-ruin":
        if !isPhysical { r.defMultiplier *= 0.75 }

    default: break
    }

    // --- Defender abilities ---

    switch def {
    case "multiscale", "shadow-shield":
        if defenderAtFullHP { r.finalMultiplier *= 0.5 }

    case "marvel-scale":
        // 1.5x Def when statused; simplified as always active when selected
        if isPhysical { r.defMultiplier *= 1.5 }

    case "thick-fat":
        if moveType == "Fire" || moveType == "Ice" { r.atkMultiplier *= 0.5 }

    case "ice-scales":
        if !isPhysical { r.defMultiplier *= 2.0 }

    case "fur-coat":
        if isPhysical { r.defMultiplier *= 2.0 }

    case "punk-rock":
        // Defender side: halves incoming sound move damage; simplified
        r.finalMultiplier *= 0.5

    case "water-bubble":
        // Defender side: halves incoming Fire damage
        if moveType == "Fire" { r.finalMultiplier *= 0.5 }

    case "fluffy":
        if isContact { r.finalMultiplier *= 0.5 }
        if moveType == "Fire" { r.finalMultiplier *= 2.0 }

    case "filter", "solid-rock", "prism-armor":
        if typeEffectiveness > 1.0 { r.finalMultiplier *= 0.75 }

    case "heatproof":
        if moveType == "Fire" { r.finalMultiplier *= 0.5 }

    case "dry-skin":
        if moveType == "Water" { r.typeEffOverride = 0.0 }
        if moveType == "Fire"  { r.finalMultiplier *= 1.25 }

    case "levitate":
        if moveType == "Ground" { r.typeEffOverride = 0.0 }

    case "eelevate":
        // Pokemon Champions ability (Mega Eelektross): identical Ground
        // immunity to Levitate. The "boost highest stat on KO" half of the
        // ability runs in the battle engine, not the damage calc — not
        // yet implemented (no Moxie/Beast Boost infrastructure exists).
        // Spikes / Toxic Spikes / Sticky Web immunity is handled in
        // `applyHazardsOnSwitchIn` via the grounded check.
        if moveType == "Ground" { r.typeEffOverride = 0.0 }

    case "flash-fire":
        if moveType == "Fire" { r.typeEffOverride = 0.0 }

    case "water-absorb", "storm-drain":
        if moveType == "Water" { r.typeEffOverride = 0.0 }

    case "volt-absorb", "lightning-rod", "motor-drive":
        if moveType == "Electric" { r.typeEffOverride = 0.0 }

    case "sap-sipper":
        if moveType == "Grass" { r.typeEffOverride = 0.0 }

    case "wonder-guard":
        if typeEffectiveness <= 1.0 { r.typeEffOverride = 0.0 }

    case "purifying-salt":
        if moveType == "Ghost" { r.finalMultiplier *= 0.5 }

    case "well-baked-body":
        if moveType == "Fire" { r.typeEffOverride = 0.0 }

    case "earth-eater":
        if moveType == "Ground" { r.typeEffOverride = 0.0 }

    case "tera-shell":
        if defenderAtFullHP && typeEffectiveness > 1.0 { r.typeEffOverride = 0.5 }

    case "tablets-of-ruin":
        if isPhysical { r.atkMultiplier *= 0.75 }

    case "vessel-of-ruin":
        if !isPhysical { r.atkMultiplier *= 0.75 }

    case "friend-guard":
        r.finalMultiplier *= 0.75

    default: break
    }

    return r
}
