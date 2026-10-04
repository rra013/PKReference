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

struct WildSlot: Identifiable, Hashable {
    let id = UUID()
    let species: UInt16
    let speciesName: String
    let minLevel: UInt8
    let maxLevel: UInt8
    let slotRate: String
}

struct WildEncounterRoute: Identifiable, Hashable {
    let id = UUID()
    let gameVersions: [FinderGameVersion]
    let locationName: String
    let encounterType: EncounterType
    let slots: [WildSlot]
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
// MARK: - PokeFinder-backed Encounter Data Provider
// ============================================================================

private let grassRates = ["20%", "20%", "10%", "10%", "10%", "10%", "5%", "5%", "4%", "4%", "1%", "1%"]
private let surfRates = ["60%", "30%", "5%", "4%", "1%"]
private let oldRodRates = ["70%", "30%"]
private let goodRodRates = ["60%", "20%", "20%"]
private let superRodRates = ["40%", "40%", "15%", "4%", "1%"]
private let rockSmashRates = ["60%", "30%", "5%", "4%", "1%"]

private func slotRates(for type: EncounterType) -> [String] {
    switch type {
    case .grass: return grassRates
    case .surf: return surfRates
    case .oldRod: return oldRodRates
    case .goodRod: return goodRodRates
    case .superRod: return superRodRates
    case .rockSmash: return rockSmashRates
    case .darkGrass: return grassRates
    case .rustlingGrass: return grassRates
    case .ripplingWater: return surfRates
    case .superRodRippling: return superRodRates
    }
}

enum PFEncounterDataProvider {

    static func wildRoutes(for game: FinderGameVersion, encounterType: EncounterType) -> [WildEncounterRoute] {
        let pfEnc = encounterType.pfEncounter
        let pfGame = game.pfGame

        let areas: [PFEncounterAreaSwift]
        switch game.generation {
        case .gen3:
            areas = PFBridge.getEncounters3(encounter: pfEnc, game: pfGame)
        case .gen4:
            areas = PFBridge.getEncounters4(encounter: pfEnc, game: pfGame, tid: 0, sid: 0)
        case .gen5:
            areas = PFBridge.getEncounters5(encounter: pfEnc, game: pfGame, season: 0, tid: 0, sid: 0)
        case .gen8:
            areas = PFBridge.getEncounters8(encounter: pfEnc, game: pfGame, tid: 0, sid: 0)
        }

        let rates = slotRates(for: encounterType)
        return areas.map { area in
            let slots = area.slots.enumerated().map { i, slot in
                WildSlot(species: slot.specie, speciesName: slot.specieName,
                         minLevel: slot.minLevel, maxLevel: slot.maxLevel,
                         slotRate: i < rates.count ? rates[i] : "?")
            }
            let name = area.locationName.isEmpty ? "Location \(area.location)" : area.locationName
            return WildEncounterRoute(gameVersions: [game], locationName: name,
                                       encounterType: encounterType, slots: slots)
        }
    }

    static func locationNames(for game: FinderGameVersion) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        let encounterTypes = EncounterType.types(for: game.generation)
        for enc in encounterTypes {
            let routes = wildRoutes(for: game, encounterType: enc)
            for route in routes {
                if !seen.contains(route.locationName) {
                    seen.insert(route.locationName)
                    names.append(route.locationName)
                }
            }
        }
        return names
    }

    static func encounterTypes(for game: FinderGameVersion, location: String) -> [EncounterType] {
        return EncounterType.types(for: game.generation).filter { type in
            wildRoutes(for: game, encounterType: type).contains { $0.locationName == location }
        }
    }

    static func wildEncounter(for game: FinderGameVersion, location: String, type: EncounterType) -> WildEncounterRoute? {
        wildRoutes(for: game, encounterType: type).first { $0.locationName == location }
    }
}
