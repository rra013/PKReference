import Foundation

// ============================================================================
// MARK: - Encounter Data Models
// ============================================================================

enum FinderGameVersion: String, CaseIterable, Identifiable, Hashable {
    case ruby = "Ruby"
    case sapphire = "Sapphire"
    case emerald = "Emerald"
    case fireRed = "FireRed"
    case leafGreen = "LeafGreen"
    case diamond = "Diamond"
    case pearl = "Pearl"
    case platinum = "Platinum"
    case heartGold = "HeartGold"
    case soulSilver = "SoulSilver"
    case black = "Black"
    case white = "White"
    case black2 = "Black 2"
    case white2 = "White 2"
    case sword = "Sword"
    case shield = "Shield"
    case brilliantDiamond = "Brilliant Diamond"
    case shiningPearl = "Shining Pearl"

    var id: String { rawValue }

    var generation: FinderGeneration {
        switch self {
        case .ruby, .sapphire, .emerald, .fireRed, .leafGreen: return .gen3
        case .diamond, .pearl, .platinum, .heartGold, .soulSilver: return .gen4
        case .black, .white, .black2, .white2: return .gen5
        case .sword, .shield, .brilliantDiamond, .shiningPearl: return .gen8
        }
    }

    static func games(for gen: FinderGeneration) -> [FinderGameVersion] {
        allCases.filter { $0.generation == gen }
    }

    var pfGame: PFGame {
        switch self {
        case .ruby: return .ruby
        case .sapphire: return .sapphire
        case .emerald: return .emerald
        case .fireRed: return .fireRed
        case .leafGreen: return .leafGreen
        case .diamond: return .diamond
        case .pearl: return .pearl
        case .platinum: return .platinum
        case .heartGold: return .heartGold
        case .soulSilver: return .soulSilver
        case .black: return .black
        case .white: return .white
        case .black2: return .black2
        case .white2: return .white2
        case .sword: return .sword
        case .shield: return .shield
        case .brilliantDiamond: return .bd
        case .shiningPearl: return .sp
        }
    }

    var isBDSP: Bool {
        self == .brilliantDiamond || self == .shiningPearl
    }

    var isSwSh: Bool {
        self == .sword || self == .shield
    }
}

/// A kind of static encounter: one of PokéFinder's tables. Each generation
/// has some of them, in its own order (`pfType`).
enum StaticEncounterCategory: String, CaseIterable, Identifiable, Hashable {
    case starters = "Starters"
    case fossils = "Fossils"
    case gifts = "Gifts"
    case gameCorner = "Game Corner"
    case stationary = "Stationary"
    case legends = "Legends"
    case events = "Events"
    case mythics = "Mythics"
    case roamers = "Roamers"
    case curtis = "Curtis"
    case yancy = "Yancy"
    case ramanasParkPureSpace = "Ramanas Park (Pure Space)"
    case ramanasParkStrangeSpace = "Ramanas Park (Strange Space)"

    var id: String { rawValue }

    /// The category's table in PokéFinder's `Encounters3/4/5/8`
    /// (`getStaticEncounters` type), nil where the generation has none.
    /// Gen 3's GameCube tables (8 and 9) are the GameCube tool's.
    func pfType(_ generation: FinderGeneration) -> Int32? {
        switch generation {
        case .gen3, .gen4:
            switch self {
            case .starters: 0
            case .fossils: 1
            case .gifts: 2
            case .gameCorner: 3
            case .stationary: 4
            case .legends: 5
            case .events: 6
            case .roamers: 7
            default: nil
            }
        case .gen5:
            switch self {
            case .starters: 0
            case .fossils: 1
            case .gifts: 2
            case .stationary: 3
            case .legends: 4
            case .mythics: 5
            case .roamers: 6
            case .curtis: 7
            case .yancy: 8
            default: nil
            }
        case .gen8:
            switch self {
            case .starters: 0
            case .gifts: 1
            case .fossils: 2
            case .stationary: 3
            case .roamers: 4
            case .legends: 5
            case .ramanasParkPureSpace: 6
            case .ramanasParkStrangeSpace: 7
            case .mythics: 8
            default: nil
            }
        }
    }
}

/// A static encounter in PokéFinder's tables. Its searches and generators
/// take it as a template, which gives its gender ratio, shiny lock, fixed
/// IVs and, in Gen 4, its method.
struct StaticEncounter: Identifiable, Hashable {
    let generation: FinderGeneration
    let category: StaticEncounterCategory
    /// The table (PokéFinder's `getStaticEncounters` type) and the index in it.
    let type: Int32
    let index: Int32
    /// PokéFinder's game mask.
    let games: UInt32
    let species: UInt16
    let form: UInt8
    let level: UInt8
    /// PokéFinder's Shiny: 0 random, 1 never, 2 always.
    let shiny: UInt8
    /// IVs fixed at 31 (BDSP legends' three).
    let fixedIVs: UInt8
    /// The method its RNG uses: Method 1 in Gen 3 and 8, the template's in
    /// Gen 4 (Method J or K for most). Nil in Gen 5, where it's the DS's.
    let method: FinderMethod?
    /// The species, and its form when it has one ("Deoxys (Attack)").
    let speciesName: String

    var id: String { "\(generation.rawValue) \(type) \(index) \(games)" }
    var template: PFStaticTemplateRef { PFStaticTemplateRef(type: type, index: index) }
    var shinyLocked: Bool { shiny == 1 }

    func isIn(_ game: FinderGameVersion) -> Bool { games & game.pfGame.rawValue != 0 }
}

enum EncounterType: String, CaseIterable, Identifiable, Hashable {
    case grass = "Grass"
    case surf = "Surf"
    case oldRod = "Old Rod"
    case goodRod = "Good Rod"
    case superRod = "Super Rod"
    case rockSmash = "Rock Smash"
    case darkGrass = "Dark Grass"
    case rustlingGrass = "Rustling Grass"
    case ripplingWater = "Rippling Water"
    case superRodRippling = "Rippling Super Rod"

    var id: String { rawValue }

    var pfEncounter: PFEncounter {
        switch self {
        case .grass: return .grass
        case .surf: return .surfing
        case .oldRod: return .oldRod
        case .goodRod: return .goodRod
        case .superRod: return .superRod
        case .rockSmash: return .rockSmash
        case .darkGrass: return .grassDark
        case .rustlingGrass: return .grassRustling
        case .ripplingWater: return .surfingRippling
        case .superRodRippling: return .superRodRippling
        }
    }

    init?(from pf: PFEncounter) {
        switch pf {
        case .grass: self = .grass
        case .surfing: self = .surf
        case .oldRod: self = .oldRod
        case .goodRod: self = .goodRod
        case .superRod: self = .superRod
        case .rockSmash: self = .rockSmash
        case .grassDark: self = .darkGrass
        case .grassRustling: self = .rustlingGrass
        case .surfingRippling: self = .ripplingWater
        case .superRodRippling: self = .superRodRippling
        default: return nil
        }
    }

    static func types(for gen: FinderGeneration) -> [EncounterType] {
        switch gen {
        case .gen3, .gen4:
            return [.grass, .surf, .oldRod, .goodRod, .superRod, .rockSmash]
        case .gen5:
            return [.grass, .darkGrass, .rustlingGrass, .surf, .ripplingWater, .superRod, .superRodRippling]
        case .gen8:
            return [.grass, .surf, .oldRod, .goodRod, .superRod]
        }
    }
}

// ============================================================================
// MARK: - Static Encounter Data
// ============================================================================

/// Every static encounter, from PokéFinder's tables.
enum StaticEncounterData {
    /// PokéFinder's tables, by generation: its getStaticEncounters for each
    /// category's type.
    private static func templates(_ generation: FinderGeneration, type: Int32) -> [PFStaticTemplateSwift] {
        switch generation {
        case .gen3: PFBridge.getStaticEncounters3(type: type)
        case .gen4: PFBridge.getStaticEncounters4(type: type)
        case .gen5: PFBridge.getStaticEncounters5(type: type)
        case .gen8: PFBridge.getStaticEncounters8(type: type)
        }
    }

    static let all: [StaticEncounter] = {
        var encounters: [StaticEncounter] = []
        for generation in FinderGeneration.allCases {
            for category in StaticEncounterCategory.allCases {
                guard let type = category.pfType(generation) else { continue }
                for (index, template) in templates(generation, type: type).enumerated() {
                    encounters.append(encounter(template, generation: generation, category: category,
                                                type: type, index: Int32(index)))
                }
            }
        }
        // FireRed and LeafGreen's Mew event, which PokéFinder has only on
        // Emerald's Faraway Island: the same Mew, level 30 and able to be
        // shiny, so it's generated from that template.
        if let mew = encounters.first(where: { $0.generation == .gen3 && $0.species == 151
                                                 && $0.games == PFGame.emerald.rawValue }) {
            encounters.append(StaticEncounter(
                generation: .gen3, category: .events, type: mew.type, index: mew.index,
                games: PFGame.fireRed.rawValue | PFGame.leafGreen.rawValue, species: mew.species, form: mew.form,
                level: mew.level, shiny: mew.shiny, fixedIVs: mew.fixedIVs, method: mew.method,
                speciesName: mew.speciesName))
        }
        return encounters
    }()

    private static func encounter(_ template: PFStaticTemplateSwift, generation: FinderGeneration,
                                  category: StaticEncounterCategory, type: Int32, index: Int32) -> StaticEncounter {
        let form = template.form == 0 ? "" : PFBridge.formName(specie: template.specie, form: template.form)
        let method: FinderMethod? = switch generation {
        case .gen3: .method1
        case .gen4:
            switch PFMethod(rawValue: template.method) {
            case .methodJ: .methodJ
            case .methodK: .methodK
            default: .method1
            }
        // Gen 5 has its own methods, and BDSP's Xorshift has none.
        case .gen5, .gen8: nil
        }
        return StaticEncounter(generation: generation, category: category, type: type, index: index,
                               games: template.game, species: template.specie, form: template.form,
                               level: template.level, shiny: template.shiny, fixedIVs: template.ivCount,
                               method: method,
                               speciesName: form.isEmpty ? template.specieName : "\(template.specieName) (\(form))")
    }

    static func encounters(for game: FinderGameVersion, category: StaticEncounterCategory) -> [StaticEncounter] {
        all.filter { $0.generation == game.generation && $0.category == category && $0.isIn(game) }
    }

    static func categories(for game: FinderGameVersion) -> [StaticEncounterCategory] {
        StaticEncounterCategory.allCases.filter { !encounters(for: game, category: $0).isEmpty }
    }
}

// ============================================================================
// MARK: - Wild Areas
// ============================================================================

/// One slot of a wild area: its Pokémon, levels and the chance of it.
struct WildSlot: Identifiable, Hashable {
    /// Its slot number in PokéFinder's area, which the encounter-slot filter
    /// and the Poké Radar take.
    let index: Int
    let species: UInt16
    let speciesName: String
    let minLevel: UInt8
    let maxLevel: UInt8
    /// The chance of this slot, as "20%"; slots with the same Pokémon each
    /// keep their own.
    let slotRate: String
    var id: Int { index }
}

/// A wild area: a reference into PokéFinder's tables (game, encounter type
/// and location ID) and what it holds under the settings it was listed
/// with, as PR 3 made statics references.
struct WildArea: Identifiable, Hashable {
    let game: FinderGameVersion
    /// PokéFinder's encounter: the Finder's types (`type`), and Headbutt and
    /// the like, which the Routes browser lists.
    let encounter: PFEncounter
    let location: UInt8
    /// PokéFinder's name for the location, told apart where two share one
    /// ("National Park (2)").
    let name: String
    /// The area's encounter rate, as PokéFinder's tables give it.
    let rate: UInt8
    let slots: [WildSlot]

    var id: String { "\(game.rawValue)/\(encounter.rawValue)/\(location)" }
    var type: EncounterType? { EncounterType(from: encounter) }

    /// Each Pokémon once, in slot order.
    var uniqueSpecies: [(species: UInt16, name: String)] {
        var seen = Set<UInt16>()
        return slots.compactMap { seen.insert($0.species).inserted ? ($0.species, $0.speciesName) : nil }
    }

    /// The encounter-slot filter for `species` (all slots for 0): the slots
    /// that hold it, as PokéFinder's filter takes them.
    func encounterSlots(for species: UInt16) -> [Bool] {
        (0..<12).map { i in
            species == 0 || slots.contains { $0.index == i && $0.species == species }
        }
    }

    /// HeartGold and SoulSilver's Safari Zone, whose slots are each 10% and
    /// whose Pokémon reroll for a 31 IV.
    var isSafariZone: Bool { WildAreaData.isSafariZone(game: game, location: location) }
    /// The Great Marsh, whose daily Pokémon take two grass slots.
    var isGreatMarsh: Bool { (game.isDPPt || game.isBDSP) && (23...28).contains(location) }
    /// The Trophy Garden, whose two daily Pokémon take two grass slots.
    var isTrophyGarden: Bool { (game.isDPPt || game.isBDSP) && location == 117 }
    /// Route 119 (Ruby, Sapphire and Emerald) or Mt. Coronet B1F (Diamond,
    /// Pearl and Platinum), where a Feebas tile can be fished.
    var isFeebasLocation: Bool {
        switch game {
        case .ruby, .sapphire: return location == 73
        case .emerald: return location == 33
        case .diamond, .pearl, .platinum: return location == 22
        default: return false
        }
    }
}

extension FinderGameVersion {
    var isDPPt: Bool { self == .diamond || self == .pearl || self == .platinum }
    var isHGSS: Bool { self == .heartGold || self == .soulSilver }
}

/// What changes a wild area's slots, beyond its game and type. Each game
/// reads the settings it has (`WildAreaData.settingsShown`).
struct WildSettings: Hashable {
    /// Gen 4 and BDSP: 0 morning, 1 day, 2 night.
    var time: Int32 = 0
    var swarm = false
    /// Diamond, Pearl and Platinum: the GBA game in Slot 2.
    var dual: FinderGameVersion?
    /// The Great Marsh's daily Pokémon, or the Trophy Garden's two.
    var replacement0: UInt16 = 0
    var replacement1: UInt16 = 0
    /// Ruby, Sapphire, Emerald and Diamond, Pearl, Platinum: a Feebas tile.
    var feebasTile = false
    /// Diamond, Pearl, Platinum and BDSP: the Poké Radar's slots.
    var radar = false
    /// HeartGold and SoulSilver: 0 off, 1 Hoenn Sound, 2 Sinnoh Sound,
    /// 3 the Mysterious Transmission.
    var radio: Int32 = 0
    /// HeartGold and SoulSilver's Safari Zone: blocks placed, by type
    /// (Plains, Forest, Peak, Water).
    var blocks: [UInt8] = [0, 0, 0, 0]
    /// Gen 5: 0 spring, 1 summer, 2 autumn, 3 winter.
    var season: UInt8 = 0

    /// Gen 4's, for PokéFinder.
    var gen4: Gen4EncounterSettings {
        Gen4EncounterSettings(time: time, swarm: swarm, dual: dual?.pfGame ?? .none,
                              replacement0: replacement0, replacement1: replacement1,
                              feebasTile: feebasTile, radar: radar, radio: radio, blocks: blocks)
    }
}

/// The wild areas of each game, from PokéFinder's tables (`PFBridge`), with
/// each slot's chance from the thresholds of PokéFinder's slot code
/// (`Core/Util/EncounterSlot.cpp`).
enum WildAreaData {
    private struct Key: Hashable {
        let game: FinderGameVersion
        let encounter: PFEncounter
        let settings: WildSettings
    }
    private static var cache: [Key: [WildArea]] = [:]

    /// The areas of `type` in `game`, as PokéFinder lists them.
    static func areas(for game: FinderGameVersion, type: EncounterType,
                      settings: WildSettings = .init()) -> [WildArea] {
        areas(for: game, encounter: type.pfEncounter, settings: settings)
    }

    /// The areas of any of PokéFinder's wild encounters in `game`; settings
    /// apply to the Finder's types.
    static func areas(for game: FinderGameVersion, encounter: PFEncounter,
                      settings: WildSettings = .init()) -> [WildArea] {
        let settings = EncounterType(from: encounter).map { relevant(settings, game: game, type: $0) } ?? WildSettings()
        let key = Key(game: game, encounter: encounter, settings: settings)
        if let cached = cache[key] { return cached }
        let raw = rawAreas(game: game, encounter: encounter, settings: settings)
        let names = locationNames(for: game)
        let areas = raw.map { area -> WildArea in
            // PokéFinder rolls one of the Safari Zone's ten slots for the
            // Finder's encounters; Headbutt keeps its own rates here.
            let safari = isSafariZone(game: game, location: area.location) && EncounterType(from: encounter) != nil
            let feebas = settings.feebasTile && isFeebasRod(game: game, encounter: encounter, location: area.location)
            let rates = slotRates(game: game, encounter: encounter, slotCount: area.slots.count,
                                  safari: safari, feebas: feebas)
            let slots = area.slots.enumerated().map { i, slot in
                WildSlot(index: i, species: slot.specie, speciesName: slot.specieName,
                         minLevel: slot.minLevel, maxLevel: slot.maxLevel,
                         slotRate: i < rates.count ? percent(rates[i]) : "–")
            }
            return WildArea(game: game, encounter: encounter, location: area.location,
                            name: names[area.location] ?? "Location \(area.location)",
                            rate: area.rate, slots: slots)
        }
        if cache.count > 500 { cache.removeAll() }
        cache[key] = areas
        return areas
    }

    /// The area at `location`, or nil when the game has none there (for
    /// this type and these settings): no fall back to another location.
    static func area(for game: FinderGameVersion, type: EncounterType, location: UInt8,
                     settings: WildSettings = .init()) -> WildArea? {
        areas(for: game, type: type, settings: settings).first { $0.location == location }
    }

    /// Every location with wild Pokémon in `game`, once each, by ID: the
    /// game's map order, as PokéFinder's tables keep it.
    static func locations(for game: FinderGameVersion, settings: WildSettings = .init()) -> [(id: UInt8, name: String)] {
        var names: [UInt8: String] = [:]
        for type in EncounterType.types(for: game.generation) {
            for area in areas(for: game, type: type, settings: settings) { names[area.location] = area.name }
        }
        return names.keys.sorted().map { ($0, names[$0]!) }
    }

    /// The encounter types `location` has in `game`.
    static func types(for game: FinderGameVersion, location: UInt8, settings: WildSettings = .init()) -> [EncounterType] {
        EncounterType.types(for: game.generation).filter {
            area(for: game, type: $0, location: location, settings: settings) != nil
        }
    }

    /// PokéFinder's names for `game`'s locations. Where two locations share
    /// a name (HeartGold and SoulSilver's National Parks, BDSP's Turnback
    /// Cave), each gets its number among them: "National Park (2)".
    static func locationNames(for game: FinderGameVersion) -> [UInt8: String] {
        if let cached = nameCache[game] { return cached }
        var ids = Set<UInt8>()
        var encounters = EncounterType.types(for: game.generation).map(\.pfEncounter)
        if game.generation == .gen4 || game.generation == .gen8 {
            encounters += [.honeyTree, .bugCatchingContest, .headbutt, .headbuttAlt, .headbuttSpecial]
        }
        for encounter in encounters {
            for area in rawAreas(game: game, encounter: encounter, settings: .init()) { ids.insert(area.location) }
        }
        let sorted = ids.sorted()
        let names = PFBridge.locationNames(sorted.map(UInt16.init), game: game.pfGame)
        var byID: [UInt8: String] = [:]
        for (i, id) in sorted.enumerated() {
            let name = i < names.count ? names[i] : ""
            byID[id] = name.isEmpty ? "Location \(id)" : name
        }
        let shared = Dictionary(grouping: sorted, by: { byID[$0]! }).filter { $0.value.count > 1 }
        for (name, sharing) in shared {
            for (n, id) in sharing.enumerated() { byID[id] = "\(name) (\(n + 1))" }
        }
        nameCache[game] = byID
        return byID
    }
    private static var nameCache: [FinderGameVersion: [UInt8: String]] = [:]

    /// Which settings change `game`'s areas of `type`, as PokéFinder's
    /// screens show them (Wild3, Wild4, Wild5, Wild8). The others are left at
    /// their defaults, so they neither change the list nor split the cache.
    struct Shown: OptionSet {
        let rawValue: Int
        static let time = Shown(rawValue: 1 << 0)
        static let swarm = Shown(rawValue: 1 << 1)
        static let dual = Shown(rawValue: 1 << 2)
        static let radar = Shown(rawValue: 1 << 3)
        static let radio = Shown(rawValue: 1 << 4)
        static let dailyPokemon = Shown(rawValue: 1 << 5)
        static let feebasTile = Shown(rawValue: 1 << 6)
        static let blocks = Shown(rawValue: 1 << 7)
        static let season = Shown(rawValue: 1 << 8)
        static let happiness = Shown(rawValue: 1 << 9)
    }

    static func settingsShown(game: FinderGameVersion, type: EncounterType, location: UInt8?) -> Shown {
        let fishing = type == .oldRod || type == .goodRod || type == .superRod
        let safari = location.map { isSafariZone(game: game, location: $0) } == true
        let marsh = location.map { (23...28).contains($0) || $0 == 117 } == true
        let feebas = location.map { isFeebasRod(game: game, encounter: type.pfEncounter, location: $0) } == true
        var shown: Shown = []
        switch game.generation {
        case .gen3:
            if feebas { shown.insert(.feebasTile) }
        case .gen4 where game.isDPPt:
            if type == .grass {
                shown.formUnion([.time, .swarm, .dual, .radar])
                if marsh { shown.insert(.dailyPokemon) }
            }
            if feebas { shown.insert(.feebasTile) }
        case .gen4:
            // HeartGold and SoulSilver: time for grass and the Good and
            // Super Rods (and anything in the Safari Zone), swarms for
            // grass, surfing and fishing, the radio for grass.
            if type == .grass || type == .goodRod || type == .superRod || safari { shown.insert(.time) }
            if type == .grass || type == .surf || fishing { shown.insert(.swarm) }
            if type == .grass { shown.insert(.radio) }
            if safari { shown.insert(.blocks) }
            if fishing { shown.insert(.happiness) }
        case .gen5:
            shown.insert(.season)
        case .gen8:
            if game.isBDSP && type == .grass {
                shown.formUnion([.time, .swarm, .radar])
                if marsh { shown.insert(.dailyPokemon) }
            }
        }
        return shown
    }

    /// `settings` with what `game`'s areas of `type` don't read put back to
    /// the defaults. Location-specific ones (daily Pokémon, Feebas tile,
    /// Safari blocks) are kept: they change only their own area.
    private static func relevant(_ settings: WildSettings, game: FinderGameVersion, type: EncounterType) -> WildSettings {
        var shown = settingsShown(game: game, type: type, location: nil)
        switch game.generation {
        case .gen3: shown.insert(.feebasTile)
        case .gen4 where game.isDPPt:
            shown.insert(.feebasTile)
            if type == .grass { shown.insert(.dailyPokemon) }
        case .gen4: shown.formUnion([.time, .blocks])
        case .gen8: if type == .grass { shown.insert(.dailyPokemon) }
        default: break
        }
        var out = WildSettings()
        if shown.contains(.time) { out.time = settings.time }
        if shown.contains(.swarm) { out.swarm = settings.swarm }
        if shown.contains(.dual) { out.dual = settings.dual }
        if shown.contains(.radar) { out.radar = settings.radar }
        if shown.contains(.radio) { out.radio = settings.radio }
        if shown.contains(.dailyPokemon) {
            out.replacement0 = settings.replacement0
            out.replacement1 = settings.replacement1
        }
        if shown.contains(.feebasTile) { out.feebasTile = settings.feebasTile }
        if shown.contains(.blocks) { out.blocks = settings.blocks }
        if shown.contains(.season) { out.season = settings.season }
        return out
    }

    /// The Safari Zone Gate and its twelve areas (PokéFinder's
    /// `EncounterArea4::safariZone`).
    static func isSafariZone(game: FinderGameVersion, location: UInt8) -> Bool {
        game.isHGSS && (148...160).contains(location)
    }

    private static func isFeebasRod(game: FinderGameVersion, encounter: PFEncounter, location: UInt8) -> Bool {
        guard encounter == .oldRod || encounter == .goodRod || encounter == .superRod else { return false }
        switch game {
        case .ruby, .sapphire: return location == 73
        case .emerald: return location == 33
        case .diamond, .pearl, .platinum: return location == 22
        default: return false
        }
    }

    private static func rawAreas(game: FinderGameVersion, encounter: PFEncounter,
                                 settings: WildSettings) -> [PFEncounterAreaSwift] {
        switch game.generation {
        case .gen3:
            return PFBridge.getEncounters3(encounter: encounter, game: game.pfGame, feebasTile: settings.feebasTile)
        case .gen4:
            return PFBridge.getEncounters4(encounter: encounter, game: game.pfGame, settings: settings.gen4)
        case .gen5:
            return PFBridge.getEncounters5(encounter: encounter, game: game.pfGame, season: settings.season)
        case .gen8:
            return PFBridge.getEncounters8(encounter: encounter, game: game.pfGame,
                                           time: settings.time, swarm: settings.swarm, radar: settings.radar,
                                           replacement0: settings.replacement0, replacement1: settings.replacement1)
        }
    }

    // MARK: Slot rates

    /// Each slot's chance in percent, from the thresholds PokéFinder's slot
    /// code rolls against (hSlot, jSlot, kSlot, bwSlot without Lucky Power,
    /// bdspSlot). A Feebas tile gives Feebas, the slot after the others,
    /// half the time, and the others the other half; the Safari Zone picks
    /// one of its ten slots evenly. Honey trees have no slot roll here (none).
    static func slotRates(game: FinderGameVersion, encounter: PFEncounter, slotCount: Int,
                          safari: Bool = false, feebas: Bool = false) -> [Double] {
        if safari { return Array(repeating: 10, count: slotCount) }
        let grass: [Double] = [20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1]
        let water0: [Double] = [70, 30]
        let water1: [Double] = [60, 20, 20]
        let water2: [Double] = [40, 40, 15, 4, 1]
        let water3: [Double] = [40, 30, 15, 10, 5]
        let water4: [Double] = [60, 30, 5, 4, 1]
        let gen3 = game.generation == .gen3
        let rates: [Double]
        switch encounter {
        case .grass, .grassDark, .grassRustling: rates = grass
        case .surfing, .surfingRippling: rates = water4
        case .rockSmash: rates = game.isHGSS ? [80, 20] : water4
        case .oldRod: rates = gen3 ? water0 : game.isHGSS ? water3 : water4
        case .goodRod: rates = gen3 ? water1 : game.isHGSS ? water3 : water2
        case .superRod, .superRodRippling: rates = game.isHGSS ? water3 : water2
        case .headbutt, .headbuttAlt, .headbuttSpecial: rates = [50, 15, 15, 10, 5, 5]
        case .bugCatchingContest: rates = [20, 20, 10, 10, 10, 10, 5, 5, 5, 5]
        default: return []
        }
        guard feebas else { return rates }
        return rates.map { $0 / 2 } + [50]
    }

    private static func percent(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))%" : "\(value.formatted(.number.precision(.fractionLength(0...1))))%"
    }
}
