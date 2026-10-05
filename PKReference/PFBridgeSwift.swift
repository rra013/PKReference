import Foundation

// MARK: - Method/Lead Mappings

enum PFMethod: UInt8 {
    case none = 0
    case method1 = 1
    case method1Reverse = 2
    case method2 = 3
    case method4 = 4
    case xdColo = 5
    case channel = 6
    case eBred = 7
    case eBredSplit = 8
    case eBredAlternate = 9
    case eBredPID = 10
    case rsFRLGBred = 11
    case rsFRLGBredSplit = 12
    case rsFRLGBredAlternate = 13
    case rsFRLGBredMixed = 14
    case cuteCharmDPPt = 15
    case cuteCharmHGSS = 16
    case methodJ = 17
    case methodK = 18
    case honeyTree = 19
    case pokeRadar = 20
    case wondercardIVs = 21
    case method5IVs = 22
    case method5CGear = 23
    case method5 = 24
}

/// PokéFinder's lead. Synchronize carries its nature: PokéFinder's
/// generators read leads 0–24 as Synchronize with that nature, and its
/// searchers read 0 as Synchronize with any nature.
nonisolated struct PFLead: RawRepresentable, Hashable, Sendable {
    let rawValue: UInt8
    init(rawValue: UInt8) { self.rawValue = rawValue }

    static let none = PFLead(rawValue: 255)
    /// For a searcher: Synchronize with any nature.
    static let synchronize = PFLead(rawValue: 0)
    /// For a generator: Synchronize with `nature`.
    static func synchronize(nature: UInt8) -> PFLead { PFLead(rawValue: min(nature, 24)) }
    static let cuteCharmF = PFLead(rawValue: 25)
    static let cuteCharmM = PFLead(rawValue: 26)
    static let magnetPull = PFLead(rawValue: 27)
    static let staticLead = PFLead(rawValue: 28)
    static let harvest = PFLead(rawValue: 29)
    static let flashFire = PFLead(rawValue: 30)
    static let stormDrain = PFLead(rawValue: 31)
    static let pressure = PFLead(rawValue: 32)
    static let suctionCups = PFLead(rawValue: 33)
    static let compoundEyes = PFLead(rawValue: 34)
    static let arenaTrap = PFLead(rawValue: 35)
}

enum PFGame: UInt32 {
    case none = 0
    case ruby = 1
    case sapphire = 2
    case emerald = 4
    case fireRed = 8
    case leafGreen = 16
    case gales = 32
    case colosseum = 64
    case diamond = 128
    case pearl = 256
    case platinum = 512
    case heartGold = 1024
    case soulSilver = 2048
    case black = 4096
    case white = 8192
    case black2 = 16384
    case white2 = 32768
    case sword = 16777216
    case shield = 33554432
    case bd = 67108864
    case sp = 134217728
}

enum PFEncounter: UInt8 {
    case grass = 0
    case grassDark = 1
    case grassRustling = 2
    case rockSmash = 3
    case surfing = 4
    case surfingRippling = 5
    case oldRod = 6
    case goodRod = 7
    case superRod = 8
    case superRodRippling = 9
    case staticEnc = 10
    case honeyTree = 11
    case bugCatchingContest = 12
    case headbutt = 13
    case headbuttAlt = 14
    case headbuttSpecial = 15
    case roamer = 16
    case gift = 17
    case entraLink = 18
    case giftEgg = 19
    case hiddenGrotto = 20

    var displayName: String {
        switch self {
        case .grass: return "Grass"
        case .grassDark: return "Dark Grass"
        case .grassRustling: return "Rustling Grass"
        case .rockSmash: return "Rock Smash"
        case .surfing: return "Surfing"
        case .surfingRippling: return "Rippling Water"
        case .oldRod: return "Old Rod"
        case .goodRod: return "Good Rod"
        case .superRod: return "Super Rod"
        case .superRodRippling: return "Rippling Super Rod"
        case .staticEnc: return "Static"
        case .honeyTree: return "Honey Tree"
        case .bugCatchingContest: return "Bug Catching Contest"
        case .headbutt: return "Headbutt"
        case .headbuttAlt: return "Headbutt (Alt)"
        case .headbuttSpecial: return "Headbutt (Special)"
        case .roamer: return "Roamer"
        case .gift: return "Gift"
        case .entraLink: return "Entralink"
        case .giftEgg: return "Gift Egg"
        case .hiddenGrotto: return "Hidden Grotto"
        }
    }
}

// MARK: - Encounter Types

struct PFSlotSwift: Identifiable {
    let id = UUID()
    let specie: UInt16
    let form: UInt8
    let minLevel: UInt8
    let maxLevel: UInt8
    var specieName: String { PFBridge.specieName(specie) }
}

struct PFEncounterAreaSwift: Identifiable {
    let id = UUID()
    let location: UInt8
    let rate: UInt8
    let encounter: PFEncounter
    let slots: [PFSlotSwift]
    var locationName: String = ""
}

/// What changes a Gen 4 area's slots, as PokéFinder's EncounterSettings4
/// (`PFEncounterSettings4`). Each game reads its own: Diamond, Pearl and
/// Platinum the dual slot, daily Pokémon, Feebas tile and radar;
/// HeartGold and SoulSilver the radio and the Safari Zone's blocks.
nonisolated struct Gen4EncounterSettings: Hashable, Sendable {
    /// 0 morning, 1 day, 2 night.
    var time: Int32 = 0
    var swarm = false
    /// The GBA game in Slot 2.
    var dual: PFGame = .none
    /// The Great Marsh's daily Pokémon, or the Trophy Garden's two.
    var replacement0: UInt16 = 0
    var replacement1: UInt16 = 0
    var feebasTile = false
    var radar = false
    /// 0 off, 1 Hoenn Sound, 2 Sinnoh Sound, 3 the Mysterious Transmission.
    var radio: Int32 = 0
    /// The Safari Zone's blocks: Plains, Forest, Peak, Water.
    var blocks: [UInt8] = [0, 0, 0, 0]

    var pf: PFEncounterSettings4 {
        let b = (0..<4).map { $0 < blocks.count ? blocks[$0] : 0 }
        return PFEncounterSettings4(time: time, swarm: swarm, dual: dual.rawValue,
                                    replacement: (replacement0, replacement1),
                                    feebasTile: feebasTile, radar: radar, radio: radio,
                                    blocks: (b[0], b[1], b[2], b[3]))
    }
}

struct PFStaticTemplateSwift: Identifiable {
    let id = UUID()
    let game: UInt32
    let specie: UInt16
    let form: UInt8
    /// PokéFinder's Shiny: 0 random, 1 never, 2 always.
    let shiny: UInt8
    let ability: UInt8
    let gender: UInt8
    let level: UInt8
    /// Gen 4's method (PFMethod's raw value); 0 elsewhere.
    var method: UInt8 = 0
    /// IVs fixed at 31.
    var ivCount: UInt8 = 0
    var specieName: String { PFBridge.specieName(specie) }
}

struct PFWildGeneratorStateSwift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let advances: UInt32
    let ivs: [UInt8]
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: UInt8
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8
    let encounterSlot: UInt8
    let level: UInt8
    let item: UInt16
    let specie: UInt16
    let form: UInt8
}

struct PFWildSearcherStateSwift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let ivs: [UInt8]
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: UInt8
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8
    let encounterSlot: UInt8
    let level: UInt8
    let item: UInt16
    let specie: UInt16
    let form: UInt8
}

struct PFWildGeneratorState4Swift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let advances: UInt32
    let ivs: [UInt8]
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: UInt8
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8
    let encounterSlot: UInt8
    let level: UInt8
    let item: UInt16
    let specie: UInt16
    let form: UInt8
    let call: UInt8
    let chatot: UInt8
}

struct PFWildSearcherState4Swift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let advances: UInt32
    let ivs: [UInt8]
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: UInt8
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8
    let encounterSlot: UInt8
    let level: UInt8
    let item: UInt16
    let specie: UInt16
    let form: UInt8
}

// MARK: - Swift Result Types

struct PFIVToPIDSwift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let sid: UInt16
    let method: UInt8
}

struct PFPIDToIVSwift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let ivs: [UInt8]
    let method: UInt8
}

struct PFDateTimeSwift: Identifiable, Hashable {
    let id = UUID()
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(year)
        hasher.combine(month)
        hasher.combine(day)
        hasher.combine(hour)
        hasher.combine(minute)
        hasher.combine(second)
    }

    static func == (lhs: PFDateTimeSwift, rhs: PFDateTimeSwift) -> Bool {
        lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day &&
        lhs.hour == rhs.hour && lhs.minute == rhs.minute && lhs.second == rhs.second
    }
}

struct PFSeedTime4Swift: Identifiable, Hashable {
    let id = UUID()
    let dateTime: PFDateTimeSwift
    let delay: UInt32

    func hash(into hasher: inout Hasher) {
        hasher.combine(dateTime)
        hasher.combine(delay)
    }

    static func == (lhs: PFSeedTime4Swift, rhs: PFSeedTime4Swift) -> Bool {
        lhs.dateTime == rhs.dateTime && lhs.delay == rhs.delay
    }
}

/// A Gen 3 static encounter's place in PokéFinder's tables.
nonisolated struct PFStaticTemplateRef: Hashable, Sendable {
    let type: Int32
    let index: Int32
}

struct PFGeneratorStateSwift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let advances: UInt32
    let ivs: [UInt8]
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: UInt8
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8
}

struct PFGeneratorState4Swift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let advances: UInt32
    let ivs: [UInt8]
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: UInt8
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8
    let call: UInt8
    let chatot: UInt8
}

nonisolated struct PFSearcherStateSwift: Identifiable, Sendable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let ivs: [UInt8]
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: UInt8
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8
}

struct PFSearcherState4Swift: Identifiable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let advances: UInt32
    let ivs: [UInt8]
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: UInt8
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8
}

// MARK: - Swift Bridge Functions

nonisolated enum PFBridge {

    // MARK: Tools

    static func ivToPID(hp: UInt8, atk: UInt8, def: UInt8,
                         spa: UInt8, spd: UInt8, spe: UInt8,
                         nature: UInt8, tid: UInt16) -> [PFIVToPIDSwift] {
        var count: Int32 = 0
        guard let ptr = pf_ivToPID(hp, atk, def, spa, spd, spe, nature, tid, &count) else {
            return []
        }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return PFIVToPIDSwift(seed: r.seed, pid: r.pid, sid: r.sid, method: r.method)
        }
    }

    static func pidToIV(pid: UInt32) -> [PFPIDToIVSwift] {
        var count: Int32 = 0
        guard let ptr = pf_pidToIV(pid, &count) else {
            return []
        }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = withUnsafePointer(to: ptr[i].ivs) { tuple in
                let bound = UnsafeRawPointer(tuple).assumingMemoryBound(to: UInt8.self)
                return Array(UnsafeBufferPointer(start: bound, count: 6))
            }
            return PFPIDToIVSwift(seed: r.seed, ivs: ivs, method: r.method)
        }
    }

    // MARK: Seed To Time

    static func seedToTimeOriginSeed3(seed: UInt32) -> (originSeed: UInt16, advances: UInt32) {
        let result = pf_seedToTimeOriginSeed3(seed)
        return (result.originSeed, result.advances)
    }

    static func seedToTime3(seed: UInt32, year: UInt16) -> [PFDateTimeSwift] {
        var count: Int32 = 0
        guard let ptr = pf_seedToTime3(seed, year, &count) else {
            return []
        }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return PFDateTimeSwift(year: Int(r.year), month: Int(r.month), day: Int(r.day),
                                    hour: Int(r.hour), minute: Int(r.minute), second: Int(r.second))
        }
    }

    static func seedToTime4(seed: UInt32, year: UInt16,
                             forceSecond: Bool = false, forcedSecond: UInt8 = 0) -> [PFSeedTime4Swift] {
        var count: Int32 = 0
        guard let ptr = pf_seedToTime4(seed, year, forceSecond, forcedSecond, &count) else {
            return []
        }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let dt = PFDateTimeSwift(year: Int(r.dateTime.year), month: Int(r.dateTime.month),
                                      day: Int(r.dateTime.day), hour: Int(r.dateTime.hour),
                                      minute: Int(r.dateTime.minute), second: Int(r.dateTime.second))
            return PFSeedTime4Swift(dateTime: dt, delay: r.delay)
        }
    }

    // MARK: Gen 3 Generator

    static func staticGenerate3(seed: UInt32,
                                 initialAdvances: UInt32,
                                 maxAdvances: UInt32,
                                 offset: UInt32 = 0,
                                 method: PFMethod,
                                 tid: UInt16, sid: UInt16,
                                 game: UInt8 = 0,
                                 deadBattery: Bool = false,
                                 filterGender: UInt8 = 255,
                                 filterAbility: UInt8 = 255,
                                 filterShiny: UInt8 = 255,
                                 ivMin: [UInt8] = [0,0,0,0,0,0],
                                 ivMax: [UInt8] = [31,31,31,31,31,31],
                                 natures: [Bool] = Array(repeating: false, count: 25),
                                 powers: [Bool] = Array(repeating: false, count: 16)) -> [PFGeneratorStateSwift] {
        var count: Int32 = 0
        let ptr = pf_staticGenerate3(seed, initialAdvances, maxAdvances, offset,
                                      method.rawValue, tid, sid, game, deadBattery,
                                      filterGender, filterAbility, filterShiny,
                                      ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFGeneratorStateSwift(seed: r.seed, pid: r.pid, advances: r.advances,
                                          ivs: ivs, nature: r.nature, ability: r.ability,
                                          gender: r.gender, shiny: r.shiny,
                                          hiddenPower: r.hiddenPower,
                                          hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }

    /// The static encounter of `species` in `game`, as its place in
    /// PokéFinder's tables (0 starters, 1 fossils, 2 gifts, 3 game corner,
    /// 4 stationary, 5 legends, 6 events, 7 roamers), looking in `type`
    /// first.
    static func staticTemplate3(species: UInt16, game: PFGame, preferring type: Int32? = nil) -> PFStaticTemplateRef? {
        let types = (type.map { [$0] } ?? []) + (0...7).filter { $0 != type }
        for type in types {
            if let index = getStaticEncounters3(type: type)
                .firstIndex(where: { $0.specie == species && $0.game & game.rawValue != 0 }) {
                return PFStaticTemplateRef(type: type, index: Int32(index))
            }
        }
        return nil
    }

    /// Ten Lines' static generator: like `staticGenerate3`, with the
    /// encounter's own template, so gender comes from its species.
    static func staticTemplateGenerate3(seed: UInt32, initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                                         method: PFMethod, template: PFStaticTemplateRef,
                                         tid: UInt16, sid: UInt16, game: PFGame,
                                         filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                         ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                         natures: [Bool] = Array(repeating: false, count: 25),
                                         powers: [Bool] = Array(repeating: false, count: 16)) -> [PFGeneratorStateSwift] {
        var count: Int32 = 0
        let ptr = pf_staticTemplateGenerate3(seed, initialAdvances, maxAdvances, offset, method.rawValue,
                                             template.type, template.index, tid, sid, game.rawValue,
                                             filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers,
                                             &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFGeneratorStateSwift(seed: r.seed, pid: r.pid, advances: r.advances,
                                          ivs: ivs, nature: r.nature, ability: r.ability,
                                          gender: r.gender, shiny: r.shiny,
                                          hiddenPower: r.hiddenPower,
                                          hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }

    /// Ten Lines' `calc_ivs_static`: the IVs a static encounter's stats
    /// allow, through PokéFinder's IV checker and the template's base stats.
    /// Each line is a level and its six stats; more lines (after levelling
    /// up) narrow it down. Per stat, the lowest and highest IV that fits, or
    /// nil when none does. Nil when the template isn't there.
    static func calcIVsStatic3(template: PFStaticTemplateRef, lines: [(level: UInt8, stats: [UInt16])],
                                nature: UInt8) -> [ClosedRange<UInt8>?]? {
        guard !lines.isEmpty, lines.allSatisfy({ $0.stats.count == 6 }) else { return nil }
        let levels = lines.map(\.level)
        let stats = lines.flatMap(\.stats)
        var min = [UInt8](repeating: 0, count: 6)
        var max = [UInt8](repeating: 0, count: 6)
        guard pf_calcIVsStatic3(template.type, template.index, levels, stats, Int32(lines.count),
                                nature, &min, &max) else { return nil }
        return (0..<6).map { min[$0] <= max[$0] && min[$0] < 32 ? min[$0]...max[$0] : nil }
    }

    // MARK: Gen 3 Searcher

    /// Starts PokéFinder's Gen 3 static searcher on its own thread: poll
    /// `staticSearch3Results` and `staticSearch3Progress` until
    /// `staticSearch3Done`, then `staticSearch3Free`. With the encounter's
    /// `template`, gender and bugged roamers' IVs follow it; without one,
    /// every result is genderless.
    static func staticSearch3Start(method: PFMethod, tid: UInt16, sid: UInt16, game: PFGame,
                                   template: PFStaticTemplateRef?,
                                   filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                   ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                   natures: [Bool] = Array(repeating: false, count: 25),
                                   powers: [Bool] = Array(repeating: false, count: 16)) -> UnsafeMutableRawPointer {
        pf_staticSearch3_start(method.rawValue, tid, sid, game.rawValue,
                               template?.type ?? -1, template?.index ?? -1,
                               filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers)
    }

    /// 0–100.
    static func staticSearch3Progress(_ handle: UnsafeMutableRawPointer) -> Int {
        min(100, max(0, Int(pf_staticSearch3_progress(handle))))
    }

    static func staticSearch3Done(_ handle: UnsafeMutableRawPointer) -> Bool {
        pf_staticSearch3_done(handle)
    }

    /// What the search has found since the last call.
    static func staticSearch3Results(_ handle: UnsafeMutableRawPointer) -> [PFSearcherStateSwift] {
        var count: Int32 = 0
        guard let ptr = pf_staticSearch3_getResults(handle, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFSearcherStateSwift(seed: r.seed, pid: r.pid, ivs: ivs,
                                         nature: r.nature, ability: r.ability,
                                         gender: r.gender, shiny: r.shiny,
                                         hiddenPower: r.hiddenPower,
                                         hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }

    static func staticSearch3Cancel(_ handle: UnsafeMutableRawPointer) {
        pf_staticSearch3_cancel(handle)
    }

    /// Waits for the search to end, so cancel first to stop it early.
    static func staticSearch3Free(_ handle: UnsafeMutableRawPointer) {
        pf_staticSearch3_free(handle)
    }

    static func staticSearch3(method: PFMethod,
                               tid: UInt16, sid: UInt16,
                               game: UInt8 = 0,
                               deadBattery: Bool = false,
                               filterGender: UInt8 = 255,
                               filterAbility: UInt8 = 255,
                               filterShiny: UInt8 = 255,
                               ivMin: [UInt8] = [0,0,0,0,0,0],
                               ivMax: [UInt8] = [31,31,31,31,31,31],
                               natures: [Bool] = Array(repeating: false, count: 25),
                               powers: [Bool] = Array(repeating: false, count: 16)) -> [PFSearcherStateSwift] {
        var count: Int32 = 0
        let ptr = pf_staticSearch3(method.rawValue, tid, sid, game, deadBattery,
                                    filterGender, filterAbility, filterShiny,
                                    ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFSearcherStateSwift(seed: r.seed, pid: r.pid, ivs: ivs,
                                         nature: r.nature, ability: r.ability,
                                         gender: r.gender, shiny: r.shiny,
                                         hiddenPower: r.hiddenPower,
                                         hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }

    // MARK: Gen 4 Generator

    static func staticGenerate4(seed: UInt32,
                                 initialAdvances: UInt32,
                                 maxAdvances: UInt32,
                                 offset: UInt32 = 0,
                                 method: PFMethod,
                                 lead: PFLead = .none,
                                 template: PFStaticTemplateRef? = nil,
                                 tid: UInt16, sid: UInt16,
                                 game: PFGame = .none,
                                 filterGender: UInt8 = 255,
                                 filterAbility: UInt8 = 255,
                                 filterShiny: UInt8 = 255,
                                 ivMin: [UInt8] = [0,0,0,0,0,0],
                                 ivMax: [UInt8] = [31,31,31,31,31,31],
                                 natures: [Bool] = Array(repeating: false, count: 25),
                                 powers: [Bool] = Array(repeating: false, count: 16)) -> [PFGeneratorState4Swift] {
        var count: Int32 = 0
        let ptr = pf_staticGenerate4(seed, initialAdvances, maxAdvances, offset,
                                      method.rawValue, lead.rawValue,
                                      template?.type ?? -1, template?.index ?? -1,
                                      tid, sid, game.rawValue,
                                      filterGender, filterAbility, filterShiny,
                                      ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFGeneratorState4Swift(seed: r.seed, pid: r.pid, advances: r.advances,
                                           ivs: ivs, nature: r.nature, ability: r.ability,
                                           gender: r.gender, shiny: r.shiny,
                                           hiddenPower: r.hiddenPower,
                                           hiddenPowerStrength: r.hiddenPowerStrength,
                                           call: r.call, chatot: r.chatot)
        }
    }

    // MARK: Gen 4 Searcher

    /// Starts PokéFinder's Gen 4 static searcher on its own thread: poll
    /// `staticSearch4Results` and `staticSearch4Progress` until
    /// `staticSearch4Done`, then `staticSearch4Free`. With the encounter's
    /// `template`, gender follows it; without one, every result is
    /// genderless.
    static func staticSearch4Start(minAdvance: UInt32, maxAdvance: UInt32, minDelay: UInt32, maxDelay: UInt32,
                                   method: PFMethod, lead: PFLead = .none, template: PFStaticTemplateRef?,
                                   tid: UInt16, sid: UInt16, game: PFGame,
                                   filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                   ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                   natures: [Bool] = Array(repeating: false, count: 25),
                                   powers: [Bool] = Array(repeating: false, count: 16)) -> UnsafeMutableRawPointer {
        pf_staticSearch4_start(minAdvance, maxAdvance, minDelay, maxDelay, method.rawValue, lead.rawValue,
                               template?.type ?? -1, template?.index ?? -1, tid, sid, game.rawValue,
                               filterGender, filterAbility, filterShiny, ivMin, ivMax, natures, powers)
    }

    /// 0–100.
    static func staticSearch4Progress(_ handle: UnsafeMutableRawPointer) -> Int {
        min(100, max(0, Int(pf_staticSearch4_progress(handle))))
    }

    static func staticSearch4Done(_ handle: UnsafeMutableRawPointer) -> Bool {
        pf_staticSearch4_done(handle)
    }

    /// What the search has found since the last call.
    static func staticSearch4Results(_ handle: UnsafeMutableRawPointer) -> [PFSearcherState4Swift] {
        var count: Int32 = 0
        guard let ptr = pf_staticSearch4_getResults(handle, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFSearcherState4Swift(seed: r.seed, pid: r.pid, advances: r.advances,
                                          ivs: ivs, nature: r.nature, ability: r.ability,
                                          gender: r.gender, shiny: r.shiny,
                                          hiddenPower: r.hiddenPower,
                                          hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }

    static func staticSearch4Cancel(_ handle: UnsafeMutableRawPointer) {
        pf_staticSearch4_cancel(handle)
    }

    /// Waits for the search to end, so cancel first to stop it early.
    static func staticSearch4Free(_ handle: UnsafeMutableRawPointer) {
        pf_staticSearch4_free(handle)
    }

    // MARK: Translator

    private static var translatorInitialized = false

    static func initTranslator(locale: String = "en") {
        guard !translatorInitialized else { return }
        pf_initTranslator(locale)
        translatorInitialized = true
    }

    static func specieName(_ specie: UInt16) -> String {
        initTranslator()
        guard specie > 0 else { return "???" }
        guard let cStr = pf_getSpecieName(specie) else { return "???" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    /// A form's name, such as Deoxys's "Attack"; empty when it has none.
    static func formName(specie: UInt16, form: UInt8) -> String {
        initTranslator()
        guard let cStr = pf_getFormName(specie, form) else { return "" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    static func abilityName(_ ability: UInt16) -> String {
        initTranslator()
        guard ability > 0 else { return "-" }
        guard let cStr = pf_getAbilityName(ability) else { return "-" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    static func natureName(_ nature: UInt8) -> String {
        initTranslator()
        guard let cStr = pf_getNatureName(nature) else { return "-" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    static func hiddenPowerName(_ power: UInt8) -> String {
        initTranslator()
        guard let cStr = pf_getHiddenPowerName(power) else { return "-" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    static func itemName(_ item: UInt16) -> String {
        initTranslator()
        guard let cStr = pf_getItemName(item) else { return "-" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    static func moveName(_ move: UInt16) -> String {
        initTranslator()
        guard let cStr = pf_getMoveName(move) else { return "-" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    static func allNatureNames() -> [String] {
        initTranslator()
        var count: Int32 = 0
        guard let arr = pf_getNatureNames(&count) else { return [] }
        defer { pf_freeStringArray(arr, count) }
        return (0..<Int(count)).map { String(cString: arr[$0]!) }
    }

    static func allHiddenPowerNames() -> [String] {
        initTranslator()
        var count: Int32 = 0
        guard let arr = pf_getHiddenPowerNames(&count) else { return [] }
        defer { pf_freeStringArray(arr, count) }
        return (0..<Int(count)).map { String(cString: arr[$0]!) }
    }

    static func locationNames(_ locationNums: [UInt16], game: PFGame) -> [String] {
        initTranslator()
        let count = Int32(locationNums.count)
        guard let arr = pf_getLocationNames(locationNums, count, game.rawValue) else { return [] }
        defer { pf_freeStringArray(arr, count) }
        return (0..<Int(count)).map { String(cString: arr[$0]!) }
    }

    // MARK: Encounter Data

    static func getEncounters3(encounter: PFEncounter, game: PFGame,
                                feebasTile: Bool = false) -> [PFEncounterAreaSwift] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getEncounters3(encounter.rawValue, game.rawValue,
                                           feebasTile, &count) else { return [] }
        defer { pf_freeResults(ptr) }

        var areas = (0..<Int(count)).map { i -> PFEncounterAreaSwift in
            let r = ptr[i]
            let enc = PFEncounter(rawValue: r.encounter) ?? .grass
            return PFEncounterAreaSwift(location: r.location, rate: r.rate,
                                         encounter: enc, slots: extractSlots(from: r))
        }

        let locationNums = areas.map { UInt16($0.location) }
        let uniqueNums = Array(Set(locationNums))
        let names = locationNames(uniqueNums, game: game)
        let nameMap = Dictionary(uniqueKeysWithValues: zip(uniqueNums, names))
        for i in areas.indices {
            areas[i].locationName = nameMap[UInt16(areas[i].location)] ?? "Unknown"
        }
        return areas
    }

    static func getEncounters4(encounter: PFEncounter, game: PFGame,
                                tid: UInt16 = 0, sid: UInt16 = 0,
                                settings: Gen4EncounterSettings = .init()) -> [PFEncounterAreaSwift] {
        initTranslator()
        var count: Int32 = 0
        var pfSettings = settings.pf
        guard let ptr = pf_getEncounters4(encounter.rawValue, game.rawValue,
                                           tid, sid, &pfSettings, &count) else { return [] }
        defer { pf_freeResults(ptr) }

        var areas = (0..<Int(count)).map { i -> PFEncounterAreaSwift in
            let r = ptr[i]
            let enc = PFEncounter(rawValue: r.encounter) ?? .grass
            return PFEncounterAreaSwift(location: r.location, rate: r.rate,
                                         encounter: enc, slots: extractSlots(from: r))
        }

        let locationNums = areas.map { UInt16($0.location) }
        let uniqueNums = Array(Set(locationNums))
        let names = locationNames(uniqueNums, game: game)
        let nameMap = Dictionary(uniqueKeysWithValues: zip(uniqueNums, names))
        for i in areas.indices {
            areas[i].locationName = nameMap[UInt16(areas[i].location)] ?? "Unknown"
        }
        return areas
    }

    static func getStaticEncounters3(type: Int32) -> [PFStaticTemplateSwift] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getStaticEncounters3(type, &count) else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return PFStaticTemplateSwift(game: r.game, specie: r.specie, form: r.form,
                                          shiny: r.shiny, ability: r.ability,
                                          gender: r.gender, level: r.level,
                                          method: r.method, ivCount: r.ivCount)
        }
    }

    static func getStaticEncounters4(type: Int32) -> [PFStaticTemplateSwift] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getStaticEncounters4(type, &count) else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return PFStaticTemplateSwift(game: r.game, specie: r.specie, form: r.form,
                                          shiny: r.shiny, ability: r.ability,
                                          gender: r.gender, level: r.level,
                                          method: r.method, ivCount: r.ivCount)
        }
    }

    // MARK: Wild Generators

    static func wildGenerate3(seed: UInt32,
                               initialAdvances: UInt32,
                               maxAdvances: UInt32,
                               offset: UInt32 = 0,
                               method: PFMethod,
                               lead: PFLead = .none,
                               tid: UInt16, sid: UInt16,
                               game: PFGame,
                               deadBattery: Bool = false,
                               feebasTile: Bool = false,
                               encounter: PFEncounter,
                               location: UInt8,
                               filterGender: UInt8 = 255,
                               filterAbility: UInt8 = 255,
                               filterShiny: UInt8 = 255,
                               ivMin: [UInt8] = [0,0,0,0,0,0],
                               ivMax: [UInt8] = [31,31,31,31,31,31],
                               natures: [Bool] = Array(repeating: true, count: 25),
                               powers: [Bool] = Array(repeating: true, count: 16),
                               encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> [PFWildGeneratorStateSwift] {
        var count: Int32 = 0
        let ptr = pf_wildGenerate3(seed, initialAdvances, maxAdvances, offset,
                                    method.rawValue, lead.rawValue, tid, sid,
                                    game.rawValue, deadBattery, feebasTile,
                                    encounter.rawValue, location,
                                    filterGender, filterAbility, filterShiny,
                                    ivMin, ivMax, natures, powers, encounterSlots, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFWildGeneratorStateSwift(seed: r.seed, pid: r.pid, advances: r.advances,
                                              ivs: ivs, nature: r.nature, ability: r.ability,
                                              gender: r.gender, shiny: r.shiny,
                                              hiddenPower: r.hiddenPower,
                                              hiddenPowerStrength: r.hiddenPowerStrength,
                                              encounterSlot: r.encounterSlot, level: r.level,
                                              item: r.item, specie: r.specie, form: r.form)
        }
    }

    static func wildGenerate4(seed: UInt32,
                               initialAdvances: UInt32,
                               maxAdvances: UInt32,
                               offset: UInt32 = 0,
                               method: PFMethod,
                               lead: PFLead = .none,
                               tid: UInt16, sid: UInt16,
                               game: PFGame,
                               encounter: PFEncounter,
                               location: UInt8,
                               settings: Gen4EncounterSettings = .init(),
                               radarShiny: Bool = false, happiness: UInt8 = 0, fixedSlot: UInt8 = 0,
                               filterGender: UInt8 = 255,
                               filterAbility: UInt8 = 255,
                               filterShiny: UInt8 = 255,
                               ivMin: [UInt8] = [0,0,0,0,0,0],
                               ivMax: [UInt8] = [31,31,31,31,31,31],
                               natures: [Bool] = Array(repeating: true, count: 25),
                               powers: [Bool] = Array(repeating: true, count: 16),
                               encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> [PFWildGeneratorState4Swift] {
        var count: Int32 = 0
        var pfSettings = settings.pf
        let ptr = pf_wildGenerate4(seed, initialAdvances, maxAdvances, offset,
                                    method.rawValue, lead.rawValue, tid, sid,
                                    game.rawValue,
                                    encounter.rawValue, location,
                                    &pfSettings, radarShiny, happiness, fixedSlot,
                                    filterGender, filterAbility, filterShiny,
                                    ivMin, ivMax, natures, powers, encounterSlots, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }

        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFWildGeneratorState4Swift(seed: r.seed, pid: r.pid, advances: r.advances,
                                               ivs: ivs, nature: r.nature, ability: r.ability,
                                               gender: r.gender, shiny: r.shiny,
                                               hiddenPower: r.hiddenPower,
                                               hiddenPowerStrength: r.hiddenPowerStrength,
                                               encounterSlot: r.encounterSlot, level: r.level,
                                               item: r.item, specie: r.specie, form: r.form,
                                               call: r.call, chatot: r.chatot)
        }
    }

    // MARK: Async Wild Search

    static func wildSearch3Async(method: PFMethod, lead: PFLead = .none,
                                  tid: UInt16, sid: UInt16, game: PFGame,
                                  deadBattery: Bool = false, feebasTile: Bool = false,
                                  encounter: PFEncounter, location: UInt8,
                                  filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                  ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                  natures: [Bool] = Array(repeating: true, count: 25),
                                  powers: [Bool] = Array(repeating: true, count: 16),
                                  encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> OpaquePointer? {
        let h = pf_wildSearch3_start(method.rawValue, lead.rawValue, tid, sid,
                                      game.rawValue, deadBattery, feebasTile,
                                      encounter.rawValue, location,
                                      filterGender, filterAbility, filterShiny,
                                      ivMin, ivMax, natures, powers, encounterSlots)
        return h.map(OpaquePointer.init)
    }

    static func wildSearch4Async(minAdvance: UInt32 = 0, maxAdvance: UInt32 = 10000,
                                  minDelay: UInt32 = 500, maxDelay: UInt32 = 10000,
                                  method: PFMethod, lead: PFLead = .none,
                                  tid: UInt16, sid: UInt16, game: PFGame,
                                  encounter: PFEncounter, location: UInt8,
                                  settings: Gen4EncounterSettings = .init(),
                                  radarShiny: Bool = false, happiness: UInt8 = 0, fixedSlot: UInt8 = 0,
                                  filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                  ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                  natures: [Bool] = Array(repeating: true, count: 25),
                                  powers: [Bool] = Array(repeating: true, count: 16),
                                  encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> OpaquePointer? {
        var pfSettings = settings.pf
        let h = pf_wildSearch4_start(minAdvance, maxAdvance, minDelay, maxDelay,
                                      method.rawValue, lead.rawValue, tid, sid,
                                      game.rawValue,
                                      encounter.rawValue, location,
                                      &pfSettings, radarShiny, happiness, fixedSlot,
                                      filterGender, filterAbility, filterShiny,
                                      ivMin, ivMax, natures, powers, encounterSlots)
        return h.map(OpaquePointer.init)
    }

    static func searchProgress(_ handle: OpaquePointer) -> Int {
        Int(pf_search_progress(UnsafeMutableRawPointer(handle)))
    }

    static func searchPollResults3(_ handle: OpaquePointer) -> [PFWildSearcherStateSwift] {
        var count: Int32 = 0
        guard let ptr = pf_search3_getResults(UnsafeMutableRawPointer(handle), &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFWildSearcherStateSwift(seed: r.seed, pid: r.pid,
                                             ivs: ivs, nature: r.nature, ability: r.ability,
                                             gender: r.gender, shiny: r.shiny,
                                             hiddenPower: r.hiddenPower,
                                             hiddenPowerStrength: r.hiddenPowerStrength,
                                             encounterSlot: r.encounterSlot, level: r.level,
                                             item: r.item, specie: r.specie, form: r.form)
        }
    }

    static func searchPollResults4(_ handle: OpaquePointer) -> [PFWildSearcherState4Swift] {
        var count: Int32 = 0
        guard let ptr = pf_search4_getResults(UnsafeMutableRawPointer(handle), &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFWildSearcherState4Swift(seed: r.seed, pid: r.pid, advances: r.advances,
                                              ivs: ivs, nature: r.nature, ability: r.ability,
                                              gender: r.gender, shiny: r.shiny,
                                              hiddenPower: r.hiddenPower,
                                              hiddenPowerStrength: r.hiddenPowerStrength,
                                              encounterSlot: r.encounterSlot, level: r.level,
                                              item: r.item, specie: r.specie, form: r.form)
        }
    }

    static func searchCancel(_ handle: OpaquePointer) {
        pf_search_cancel(UnsafeMutableRawPointer(handle))
    }

    static func searchFree(_ handle: OpaquePointer) {
        pf_search_free(UnsafeMutableRawPointer(handle))
    }

    // MARK: Egg Generator Gen 3

    struct EggResult3: Identifiable {
        let id = UUID()
        let pid: UInt32
        let advances: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let inheritance: [UInt8]
        let redraws: UInt8
        let pickupAdvances: UInt32
    }

    struct EggResult4: Identifiable {
        let id = UUID()
        let pid: UInt32
        let advances: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let inheritance: [UInt8]
        let pickupAdvances: UInt32
        let call: UInt8
        let chatot: UInt8
    }

    struct IDResult: Identifiable {
        let id = UUID()
        let advances: UInt32
        let tid: UInt16
        let sid: UInt16
        let tsv: UInt16
    }

    struct IDResult4: Identifiable {
        let id = UUID()
        let seed: UInt32
        let delay: UInt32
        let advances: UInt32
        let tid: UInt16
        let sid: UInt16
        let tsv: UInt16
        let seconds: UInt8
    }

    static func eggGenerate3(seedHeld: UInt32, seedPickup: UInt32,
                              initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                              initialAdvancesPickup: UInt32, maxAdvancesPickup: UInt32, offsetPickup: UInt32 = 0,
                              calibration: UInt8 = 0, minRedraw: UInt8 = 0, maxRedraw: UInt8 = 0,
                              method: PFMethod, compatibility: UInt8,
                              parentAIVs: [UInt8], parentBIVs: [UInt8],
                              parentAAbility: UInt8, parentBAbility: UInt8,
                              parentAGender: UInt8, parentBGender: UInt8,
                              parentAItem: UInt8, parentBItem: UInt8,
                              parentANature: UInt8, parentBNature: UInt8,
                              eggSpecie: UInt16, masuda: Bool,
                              tid: UInt16, sid: UInt16,
                              game: PFGame, deadBattery: Bool = false,
                              filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                              ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                              natures: [Bool] = Array(repeating: false, count: 25),
                              powers: [Bool] = Array(repeating: false, count: 16)) -> [EggResult3] {
        var count: Int32 = 0
        let ptr = pf_eggGenerate3(seedHeld, seedPickup,
                                   initialAdvances, maxAdvances, offset,
                                   initialAdvancesPickup, maxAdvancesPickup, offsetPickup,
                                   calibration, minRedraw, maxRedraw,
                                   method.rawValue, compatibility,
                                   parentAIVs, parentBIVs,
                                   parentAAbility, parentBAbility,
                                   parentAGender, parentBGender,
                                   parentAItem, parentBItem,
                                   parentANature, parentBNature,
                                   eggSpecie, masuda,
                                   tid, sid, game.rawValue, deadBattery,
                                   filterGender, filterAbility, filterShiny,
                                   ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            let inh = [r.inheritance.0, r.inheritance.1, r.inheritance.2,
                       r.inheritance.3, r.inheritance.4, r.inheritance.5]
            return EggResult3(pid: r.pid, advances: r.advances, ivs: ivs,
                              nature: r.nature, ability: r.ability, gender: r.gender,
                              shiny: r.shiny, inheritance: inh,
                              redraws: r.redraws, pickupAdvances: r.pickupAdvances)
        }
    }

    static func eggGenerate4(seedHeld: UInt32, seedPickup: UInt32,
                              initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                              initialAdvancesPickup: UInt32, maxAdvancesPickup: UInt32, offsetPickup: UInt32 = 0,
                              parentAIVs: [UInt8], parentBIVs: [UInt8],
                              parentAAbility: UInt8, parentBAbility: UInt8,
                              parentAGender: UInt8, parentBGender: UInt8,
                              parentAItem: UInt8, parentBItem: UInt8,
                              parentANature: UInt8, parentBNature: UInt8,
                              eggSpecie: UInt16, masuda: Bool,
                              tid: UInt16, sid: UInt16, game: PFGame,
                              filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                              ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                              natures: [Bool] = Array(repeating: false, count: 25),
                              powers: [Bool] = Array(repeating: false, count: 16)) -> [EggResult4] {
        var count: Int32 = 0
        let ptr = pf_eggGenerate4(seedHeld, seedPickup,
                                   initialAdvances, maxAdvances, offset,
                                   initialAdvancesPickup, maxAdvancesPickup, offsetPickup,
                                   parentAIVs, parentBIVs,
                                   parentAAbility, parentBAbility,
                                   parentAGender, parentBGender,
                                   parentAItem, parentBItem,
                                   parentANature, parentBNature,
                                   eggSpecie, masuda,
                                   tid, sid, game.rawValue,
                                   filterGender, filterAbility, filterShiny,
                                   ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            let inh = [r.inheritance.0, r.inheritance.1, r.inheritance.2,
                       r.inheritance.3, r.inheritance.4, r.inheritance.5]
            return EggResult4(pid: r.pid, advances: r.advances, ivs: ivs,
                              nature: r.nature, ability: r.ability, gender: r.gender,
                              shiny: r.shiny, inheritance: inh,
                              pickupAdvances: r.pickupAdvances,
                              call: r.call, chatot: r.chatot)
        }
    }

    // MARK: ID Generators

    static func idGenerate3RS(seed: UInt16, initialAdvances: UInt32, maxAdvances: UInt32) -> [IDResult] {
        var count: Int32 = 0
        guard let ptr = pf_idGenerate3_RS(seed, initialAdvances, maxAdvances, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return IDResult(advances: r.advances, tid: r.tid, sid: r.sid, tsv: r.tsv)
        }
    }

    static func idGenerate3FRLGE(tid: UInt16, initialAdvances: UInt32, maxAdvances: UInt32) -> [IDResult] {
        var count: Int32 = 0
        guard let ptr = pf_idGenerate3_FRLGE(tid, initialAdvances, maxAdvances, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return IDResult(advances: r.advances, tid: r.tid, sid: r.sid, tsv: r.tsv)
        }
    }

    static func idGenerate4(minDelay: UInt32, maxDelay: UInt32,
                             year: UInt16, month: UInt8, day: UInt8,
                             hour: UInt8, minute: UInt8,
                             targetTID: UInt16 = 0, filterTID: Bool = false,
                             targetSID: UInt16 = 0, filterSID: Bool = false,
                             targetTSV: UInt16 = 0, filterTSV: Bool = false) -> [IDResult4] {
        var count: Int32 = 0
        guard let ptr = pf_idGenerate4(minDelay, maxDelay, year, month, day, hour, minute,
                                        targetTID, filterTID, targetSID, filterSID,
                                        targetTSV, filterTSV, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return IDResult4(seed: r.seed, delay: r.delay, advances: r.advances,
                             tid: r.tid, sid: r.sid, tsv: r.tsv, seconds: r.seconds)
        }
    }

    // MARK: - ID Searcher Gen 4 (Async)

    static func idSearch4Start(infinite: Bool, year: UInt16,
                                minDelay: UInt32, maxDelay: UInt32,
                                targetTID: UInt16 = 0, filterTID: Bool = false,
                                targetSID: UInt16 = 0, filterSID: Bool = false,
                                targetTSV: UInt16 = 0, filterTSV: Bool = false) -> OpaquePointer {
        let h = pf_idSearch4_start(infinite, year, minDelay, maxDelay,
                                    targetTID, filterTID, targetSID, filterSID,
                                    targetTSV, filterTSV)!
        return OpaquePointer(h)
    }

    /// 0–100.
    static func idSearch4Progress(_ handle: OpaquePointer) -> Int {
        min(100, max(0, Int(pf_idSearch4_progress(UnsafeMutableRawPointer(handle)))))
    }

    static func idSearch4Done(_ handle: OpaquePointer) -> Bool {
        pf_idSearch4_done(UnsafeMutableRawPointer(handle))
    }

    static func idSearch4GetResults(_ handle: OpaquePointer) -> [IDResult4] {
        var count: Int32 = 0
        guard let ptr = pf_idSearch4_getResults(UnsafeMutableRawPointer(handle), &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return IDResult4(seed: r.seed, delay: r.delay, advances: r.advances,
                             tid: r.tid, sid: r.sid, tsv: r.tsv, seconds: r.seconds)
        }
    }

    static func idSearch4Cancel(_ handle: OpaquePointer) {
        pf_idSearch4_cancel(UnsafeMutableRawPointer(handle))
    }

    static func idSearch4Free(_ handle: OpaquePointer) {
        pf_idSearch4_free(UnsafeMutableRawPointer(handle))
    }

    // MARK: - GameCube

    struct ShadowTemplateInfo: Identifiable {
        let id: Int
        let specie: UInt16
        let level: UInt8
        let shadowType: UInt8
        let game: UInt32
        var specieName: String { PFBridge.specieName(specie) }
        var isColosseum: Bool { (game & PFGame.colosseum.rawValue) != 0 }
    }

    static func getShadowTemplates() -> [ShadowTemplateInfo] {
        var count: Int32 = 0
        guard let ptr = pf_getShadowTemplates(&count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return ShadowTemplateInfo(id: i, specie: r.specie, level: r.level,
                                       shadowType: r.shadowType, game: r.game)
        }
    }

    struct GameCubeResult: Identifiable {
        let id = UUID()
        let advances: UInt32
        let pid: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let hiddenPower: UInt8
        let hiddenPowerStrength: UInt8
    }

    static func gamecubeGenerateShadow(seed: UInt32,
                                        initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                                        shadowIndex: Int, unset: Bool,
                                        tid: UInt16, sid: UInt16, game: UInt32,
                                        filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                        ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                        natures: [Bool] = [Bool](repeating: false, count: 25),
                                        powers: [Bool] = [Bool](repeating: false, count: 16)) -> [GameCubeResult] {
        var count: Int32 = 0
        let ptr = pf_gamecubeGenerateShadow(seed, initialAdvances, maxAdvances, offset,
                                             Int32(shadowIndex), unset, tid, sid, game,
                                             filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return GameCubeResult(advances: r.advances, pid: r.pid, ivs: ivs,
                                   nature: r.nature, ability: r.ability, gender: r.gender,
                                   shiny: r.shiny, hiddenPower: r.hiddenPower,
                                   hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }

    static func gamecubeGenerateStatic(seed: UInt32,
                                        initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                                        method: PFMethod, staticType: Int, staticIndex: Int,
                                        tid: UInt16, sid: UInt16, game: UInt32,
                                        filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                        ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                        natures: [Bool] = [Bool](repeating: false, count: 25),
                                        powers: [Bool] = [Bool](repeating: false, count: 16)) -> [GameCubeResult] {
        var count: Int32 = 0
        let ptr = pf_gamecubeGenerateStatic(seed, initialAdvances, maxAdvances, offset,
                                             method.rawValue, Int32(staticType), Int32(staticIndex),
                                             tid, sid, game,
                                             filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return GameCubeResult(advances: r.advances, pid: r.pid, ivs: ivs,
                                   nature: r.nature, ability: r.ability, gender: r.gender,
                                   shiny: r.shiny, hiddenPower: r.hiddenPower,
                                   hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }

    // MARK: - GameCube Searcher

    /// Starts PokéFinder's shadow searcher on its own thread: poll
    /// `gamecubeSearchResults` and `gamecubeSearchProgress` until
    /// `gamecubeSearchDone`, then `gamecubeSearchFree`. Nil if `shadowIndex`
    /// isn't a shadow Pokémon.
    static func gamecubeSearchShadowStart(method: PFMethod = .xdColo, unset: Bool,
                                          tid: UInt16, sid: UInt16, game: UInt32,
                                          filterShiny: UInt8 = 255,
                                          ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                          natures: [Bool] = [Bool](repeating: false, count: 25),
                                          powers: [Bool] = [Bool](repeating: false, count: 16),
                                          shadowIndex: Int) -> UnsafeMutableRawPointer? {
        pf_gamecubeSearchShadow_start(method.rawValue, unset, tid, sid, game,
                                      255, 255, filterShiny,
                                      ivMin, ivMax, natures, powers,
                                      Int32(shadowIndex))
    }

    /// The same for a non-shadow (`staticType` 8) or Channel (9) template.
    static func gamecubeSearchStaticStart(method: PFMethod, unset: Bool = false,
                                          tid: UInt16, sid: UInt16, game: UInt32,
                                          filterShiny: UInt8 = 255,
                                          ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                          natures: [Bool] = [Bool](repeating: false, count: 25),
                                          powers: [Bool] = [Bool](repeating: false, count: 16),
                                          staticType: Int, staticIndex: Int) -> UnsafeMutableRawPointer? {
        pf_gamecubeSearchStatic_start(method.rawValue, unset, tid, sid, game,
                                      255, 255, filterShiny,
                                      ivMin, ivMax, natures, powers,
                                      Int32(staticType), Int32(staticIndex))
    }

    /// 0–100.
    static func gamecubeSearchProgress(_ handle: UnsafeMutableRawPointer) -> Int {
        min(100, max(0, Int(pf_gamecubeSearch_progress(handle))))
    }

    static func gamecubeSearchDone(_ handle: UnsafeMutableRawPointer) -> Bool {
        pf_gamecubeSearch_done(handle)
    }

    /// What the search has found since the last call.
    static func gamecubeSearchResults(_ handle: UnsafeMutableRawPointer) -> [PFSearcherStateSwift] {
        var count: Int32 = 0
        guard let ptr = pf_gamecubeSearch_getResults(handle, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PFSearcherStateSwift(seed: r.seed, pid: r.pid, ivs: ivs,
                                         nature: r.nature, ability: r.ability,
                                         gender: r.gender, shiny: r.shiny,
                                         hiddenPower: r.hiddenPower,
                                         hiddenPowerStrength: r.hiddenPowerStrength)
        }
    }

    static func gamecubeSearchCancel(_ handle: UnsafeMutableRawPointer) {
        pf_gamecubeSearch_cancel(handle)
    }

    /// Waits for the search to end, so cancel first to stop it early.
    static func gamecubeSearchFree(_ handle: UnsafeMutableRawPointer) {
        pf_gamecubeSearch_free(handle)
    }

    // MARK: - PokeSpot

    struct PokeSpotResult: Identifiable {
        let id = UUID()
        let advances: UInt32
        let encounterAdvances: UInt32
        let pid: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let hiddenPower: UInt8
        let hiddenPowerStrength: UInt8
        let encounterSlot: UInt8
        let level: UInt8
        let specie: UInt16
        var specieName: String { PFBridge.specieName(specie) }
    }

    struct PokeSpotArea: Identifiable {
        let id = UUID()
        let location: UInt8
        let rate: UInt8
        let encounter: PFEncounter
        let slots: [PFSlotSwift]
        var locationName: String = ""
    }

    static func getPokeSpotEncounters() -> [PokeSpotArea] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getPokeSpotEncounters(&count) else { return [] }
        defer { pf_freeResults(ptr) }

        let names = ["Rock", "Oasis", "Cave"]
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let enc = PFEncounter(rawValue: r.encounter) ?? .grass
            let slots = extractSlots(from: r)
            var area = PokeSpotArea(location: r.location, rate: r.rate, encounter: enc, slots: slots)
            area.locationName = i < names.count ? "Poké Spot \(names[i])" : "Poké Spot \(i)"
            return area
        }
    }

    static func pokeSpotGenerate(seedFood: UInt32, seedEncounter: UInt32,
                                   initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                                   initialAdvancesEncounter: UInt32, maxAdvancesEncounter: UInt32, offsetEncounter: UInt32 = 0,
                                   tid: UInt16, sid: UInt16, game: UInt32 = PFGame.gales.rawValue,
                                   pokeSpotIndex: Int,
                                   filterShiny: UInt8 = 255,
                                   natures: [Bool] = [Bool](repeating: false, count: 25)) -> [PokeSpotResult] {
        var count: Int32 = 0
        let ivMin: [UInt8] = [0,0,0,0,0,0]
        let ivMax: [UInt8] = [31,31,31,31,31,31]
        let powers = [Bool](repeating: true, count: 16)
        let slots = [Bool](repeating: true, count: 12)

        let ptr = pf_pokeSpotGenerate(seedFood, seedEncounter,
                                        initialAdvances, maxAdvances, offset,
                                        initialAdvancesEncounter, maxAdvancesEncounter, offsetEncounter,
                                        tid, sid, game,
                                        Int32(pokeSpotIndex),
                                        255, 255, filterShiny,
                                        ivMin, ivMax, natures, powers, slots, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return PokeSpotResult(advances: r.advances, encounterAdvances: r.encounterAdvances,
                                   pid: r.pid, ivs: ivs, nature: r.nature,
                                   ability: r.ability, gender: r.gender, shiny: r.shiny,
                                   hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                                   encounterSlot: r.encounterSlot, level: r.level, specie: r.specie)
        }
    }

    // MARK: - Seed Searchers (GameCube)

    static func coloSeedSearchStart(lead: UInt8, trainer: UInt8, threads: Int = 4) -> OpaquePointer {
        let h = pf_coloSeedSearch_start(lead, trainer, Int32(threads))!
        return OpaquePointer(h)
    }

    static func galesSeedSearchStart(enemyHP: (UInt16, UInt16), playerHP: (UInt16, UInt16),
                                       enemyIndex: UInt8, playerIndex: UInt8, threads: Int = 4) -> OpaquePointer {
        let h = pf_galesSeedSearch_start(enemyHP.0, enemyHP.1,
                                           playerHP.0, playerHP.1,
                                           enemyIndex, playerIndex, Int32(threads))!
        return OpaquePointer(h)
    }

    static func channelSeedSearchStart(pattern: [UInt8], threads: Int = 4) -> OpaquePointer {
        let h = pf_channelSeedSearch_start(pattern, Int32(pattern.count), Int32(threads))!
        return OpaquePointer(h)
    }

    /// 0–100.
    static func seedSearchProgress(_ handle: OpaquePointer) -> Int {
        min(100, max(0, Int(pf_seedSearch_progress(UnsafeMutableRawPointer(handle)))))
    }

    /// Read the results once this is true: they're sorted at the end.
    static func seedSearchDone(_ handle: OpaquePointer) -> Bool {
        pf_seedSearch_done(UnsafeMutableRawPointer(handle))
    }

    static func seedSearchGetResults(_ handle: OpaquePointer) -> [UInt32] {
        var count: Int32 = 0
        guard let ptr = pf_seedSearch_getResults(UnsafeMutableRawPointer(handle), &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { ptr[$0] }
    }

    static func seedSearchCancel(_ handle: OpaquePointer) {
        pf_seedSearch_cancel(UnsafeMutableRawPointer(handle))
    }

    static func seedSearchFree(_ handle: OpaquePointer) {
        pf_seedSearch_free(UnsafeMutableRawPointer(handle))
    }

    // MARK: - XD/Colo ID Generator

    static func idGenerate3XDColo(seed: UInt32, initialAdvances: UInt32, maxAdvances: UInt32) -> [IDResult] {
        var count: Int32 = 0
        guard let ptr = pf_idGenerate3_XDColo(seed, initialAdvances, maxAdvances, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return IDResult(advances: r.advances, tid: r.tid, sid: r.sid, tsv: r.tsv)
        }
    }

    // MARK: - Jirachi Pattern

    static func jirachiPattern(seed: UInt32, targetAdvance: UInt32, bruteForce: UInt32 = 50) -> [UInt8] {
        var count: Int32 = 0
        guard let ptr = pf_jirachiPattern(seed, targetAdvance, bruteForce, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { ptr[$0] }
    }

    static func computeJirachiSeed(_ seed: UInt32) -> UInt32 {
        pf_computeJirachiSeed(seed)
    }

    // MARK: - Gen 5 Result Types

    struct Gen5StaticResult: Identifiable {
        let id = UUID()
        let advances: UInt32
        let ivAdvances: UInt32
        let pid: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let hiddenPower: UInt8
        let hiddenPowerStrength: UInt8
        let chatot: UInt8
    }

    struct Gen5WildResult: Identifiable {
        let id = UUID()
        let advances: UInt32
        let ivAdvances: UInt32
        let pid: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let hiddenPower: UInt8
        let hiddenPowerStrength: UInt8
        let encounterSlot: UInt8
        let level: UInt8
        let item: UInt16
        let specie: UInt16
        let form: UInt8
        let chatot: UInt8
    }

    struct Gen5EggResult: Identifiable {
        let id = UUID()
        let advances: UInt32
        let pid: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let inheritance: [UInt8]
        let chatot: UInt8
    }

    struct Gen5IDResult: Identifiable {
        let id = UUID()
        let advances: UInt32
        let tid: UInt16
        let sid: UInt16
        let tsv: UInt16
    }

    // MARK: Gen 5 Static Generator

    static func staticGenerate5(seed: UInt64,
                                 initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                                 ivInitialAdvances: UInt32, ivMaxAdvances: UInt32,
                                 method: PFMethod, lead: PFLead = .none,
                                 tid: UInt16, sid: UInt16, game: PFGame,
                                 staticType: Int32 = 0, staticIndex: Int32 = 0,
                                 mac: UInt64, keypresses: [Bool],
                                 vcount: UInt8, gxstat: UInt8, vframe: UInt8,
                                 skipLR: Bool, timer0Min: UInt16, timer0Max: UInt16,
                                 memoryLink: Bool, shinyCharm: Bool,
                                 dsType: UInt8, language: UInt8,
                                 filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                 ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                 natures: [Bool] = Array(repeating: false, count: 25),
                                 powers: [Bool] = Array(repeating: false, count: 16)) -> [Gen5StaticResult] {
        var count: Int32 = 0
        let ptr = pf_staticGenerate5(seed, initialAdvances, maxAdvances, offset, ivInitialAdvances, ivMaxAdvances,
                                      method.rawValue, lead.rawValue, tid, sid, game.rawValue,
                                      staticType, staticIndex,
                                      mac, keypresses, vcount, gxstat, vframe,
                                      skipLR, timer0Min, timer0Max,
                                      memoryLink, shinyCharm, dsType, language,
                                      filterGender, filterAbility, filterShiny,
                                      ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return Gen5StaticResult(advances: r.advances, ivAdvances: r.ivAdvances,
                                     pid: r.pid, ivs: ivs, nature: r.nature,
                                     ability: r.ability, gender: r.gender, shiny: r.shiny,
                                     hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                                     chatot: r.chatot)
        }
    }

    // MARK: Gen 5 Wild Generator

    static func wildGenerate5(seed: UInt64,
                               initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                                 ivInitialAdvances: UInt32, ivMaxAdvances: UInt32,
                               method: PFMethod, lead: PFLead = .none,
                               tid: UInt16, sid: UInt16, game: PFGame,
                               encounter: PFEncounter, location: UInt8, season: UInt8 = 0,
                               mac: UInt64, keypresses: [Bool],
                               vcount: UInt8, gxstat: UInt8, vframe: UInt8,
                               skipLR: Bool, timer0Min: UInt16, timer0Max: UInt16,
                               memoryLink: Bool, shinyCharm: Bool,
                               dsType: UInt8, language: UInt8,
                               filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                               ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                               natures: [Bool] = Array(repeating: true, count: 25),
                               powers: [Bool] = Array(repeating: true, count: 16),
                               encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> [Gen5WildResult] {
        var count: Int32 = 0
        let ptr = pf_wildGenerate5(seed, initialAdvances, maxAdvances, offset, ivInitialAdvances, ivMaxAdvances,
                                    method.rawValue, lead.rawValue, tid, sid, game.rawValue,
                                    encounter.rawValue, location, season,
                                    mac, keypresses, vcount, gxstat, vframe,
                                    skipLR, timer0Min, timer0Max,
                                    memoryLink, shinyCharm, dsType, language,
                                    filterGender, filterAbility, filterShiny,
                                    ivMin, ivMax, natures, powers, encounterSlots, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return Gen5WildResult(advances: r.advances, ivAdvances: r.ivAdvances,
                                   pid: r.pid, ivs: ivs, nature: r.nature,
                                   ability: r.ability, gender: r.gender, shiny: r.shiny,
                                   hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                                   encounterSlot: r.encounterSlot, level: r.level,
                                   item: r.item, specie: r.specie, form: r.form,
                                   chatot: r.chatot)
        }
    }

    // MARK: Gen 5 Encounter Data

    static func getEncounters5(encounter: PFEncounter, game: PFGame,
                                season: UInt8 = 0,
                                tid: UInt16 = 0, sid: UInt16 = 0,
                                mac: UInt64 = 0, keypresses: [Bool] = Array(repeating: false, count: 9),
                                vcount: UInt8 = 0, gxstat: UInt8 = 0, vframe: UInt8 = 0,
                                skipLR: Bool = false, timer0Min: UInt16 = 0, timer0Max: UInt16 = 0,
                                memoryLink: Bool = false, shinyCharm: Bool = false,
                                dsType: UInt8 = 0, language: UInt8 = 0) -> [PFEncounterAreaSwift] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getEncounters5(encounter.rawValue, game.rawValue, season,
                                           tid, sid, mac, keypresses,
                                           vcount, gxstat, vframe,
                                           skipLR, timer0Min, timer0Max,
                                           memoryLink, shinyCharm, dsType, language,
                                           &count) else { return [] }
        defer { pf_freeResults(ptr) }

        var areas = (0..<Int(count)).map { i -> PFEncounterAreaSwift in
            let r = ptr[i]
            let enc = PFEncounter(rawValue: r.encounter) ?? .grass
            return PFEncounterAreaSwift(location: r.location, rate: r.rate,
                                         encounter: enc, slots: extractSlots(from: r))
        }

        let locationNums = areas.map { UInt16($0.location) }
        let uniqueNums = Array(Set(locationNums))
        let names = locationNames(uniqueNums, game: game)
        let nameMap = Dictionary(uniqueKeysWithValues: zip(uniqueNums, names))
        for i in areas.indices {
            areas[i].locationName = nameMap[UInt16(areas[i].location)] ?? "Unknown"
        }
        return areas
    }

    static func getStaticEncounters5(type: Int32) -> [PFStaticTemplateSwift] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getStaticEncounters5(type, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return PFStaticTemplateSwift(game: r.game, specie: r.specie, form: r.form,
                                          shiny: r.shiny, ability: r.ability,
                                          gender: r.gender, level: r.level,
                                          method: r.method, ivCount: r.ivCount)
        }
    }

    // MARK: Gen 5 Searcher Result Structs

    struct Gen5SearchResult: Identifiable {
        let id = UUID()
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let second: Int
        let initialSeed: UInt64
        let timer0: UInt16
        let buttons: UInt16
        let advances: UInt32
        let ivAdvances: UInt32
        let pid: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let hiddenPower: UInt8
        let hiddenPowerStrength: UInt8
        let chatot: UInt8
    }

    struct Gen5WildSearchResult: Identifiable {
        let id = UUID()
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let second: Int
        let initialSeed: UInt64
        let timer0: UInt16
        let buttons: UInt16
        let advances: UInt32
        let ivAdvances: UInt32
        let pid: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let hiddenPower: UInt8
        let hiddenPowerStrength: UInt8
        let encounterSlot: UInt8
        let level: UInt8
        let item: UInt16
        let specie: UInt16
        let form: UInt8
        let chatot: UInt8
    }

    // MARK: Gen 5 Async Searcher

    static func staticSearch5Start(initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                                    method: PFMethod, lead: PFLead = .none,
                                    tid: UInt16, sid: UInt16, game: PFGame,
                                    staticType: Int32 = 0, staticIndex: Int32 = 0,
                                    ivInitialAdvances: UInt32, ivMaxAdvances: UInt32,
                                    mac: UInt64, keypresses: [Bool],
                                    vcount: UInt8, gxstat: UInt8, vframe: UInt8,
                                    skipLR: Bool, timer0Min: UInt16, timer0Max: UInt16,
                                    memoryLink: Bool, shinyCharm: Bool,
                                    dsType: UInt8, language: UInt8,
                                    startYear: UInt16, startMonth: UInt8, startDay: UInt8,
                                    endYear: UInt16, endMonth: UInt8, endDay: UInt8,
                                    filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                    ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                    natures: [Bool] = Array(repeating: false, count: 25),
                                    powers: [Bool] = Array(repeating: false, count: 16)) -> OpaquePointer? {
        let handle = pf_staticSearch5_start(initialAdvances, maxAdvances, offset,
                                             method.rawValue, lead.rawValue, tid, sid, game.rawValue,
                                             staticType, staticIndex,
                                             ivInitialAdvances, ivMaxAdvances,
                                             mac, keypresses, vcount, gxstat, vframe,
                                             skipLR, timer0Min, timer0Max,
                                             memoryLink, shinyCharm, dsType, language,
                                             startYear, startMonth, startDay,
                                             endYear, endMonth, endDay,
                                             filterGender, filterAbility, filterShiny,
                                             ivMin, ivMax, natures, powers)
        return OpaquePointer(handle)
    }

    static func wildSearch5Start(initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                                  method: PFMethod, lead: PFLead = .none,
                                  tid: UInt16, sid: UInt16, game: PFGame,
                                  encounter: PFEncounter, location: UInt8, season: UInt8 = 0,
                                  ivInitialAdvances: UInt32, ivMaxAdvances: UInt32,
                                  mac: UInt64, keypresses: [Bool],
                                  vcount: UInt8, gxstat: UInt8, vframe: UInt8,
                                  skipLR: Bool, timer0Min: UInt16, timer0Max: UInt16,
                                  memoryLink: Bool, shinyCharm: Bool,
                                  dsType: UInt8, language: UInt8,
                                  startYear: UInt16, startMonth: UInt8, startDay: UInt8,
                                  endYear: UInt16, endMonth: UInt8, endDay: UInt8,
                                  filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                  ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                  natures: [Bool] = Array(repeating: false, count: 25),
                                  powers: [Bool] = Array(repeating: false, count: 16),
                                  encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> OpaquePointer? {
        let handle = pf_wildSearch5_start(initialAdvances, maxAdvances, offset,
                                           method.rawValue, lead.rawValue, tid, sid, game.rawValue,
                                           encounter.rawValue, location, season,
                                           ivInitialAdvances, ivMaxAdvances,
                                           mac, keypresses, vcount, gxstat, vframe,
                                           skipLR, timer0Min, timer0Max,
                                           memoryLink, shinyCharm, dsType, language,
                                           startYear, startMonth, startDay,
                                           endYear, endMonth, endDay,
                                           filterGender, filterAbility, filterShiny,
                                           ivMin, ivMax, natures, powers, encounterSlots)
        return OpaquePointer(handle)
    }

    static func search5Progress(_ handle: OpaquePointer) -> Int {
        Int(pf_search5_progress(UnsafeMutableRawPointer(handle)))
    }

    static func search5StaticResults(_ handle: OpaquePointer) -> [Gen5SearchResult] {
        var count: Int32 = 0
        guard let ptr = pf_search5_static_getResults(UnsafeMutableRawPointer(handle), &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return Gen5SearchResult(year: Int(r.dateTime.year), month: Int(r.dateTime.month),
                                     day: Int(r.dateTime.day), hour: Int(r.dateTime.hour),
                                     minute: Int(r.dateTime.minute), second: Int(r.dateTime.second),
                                     initialSeed: r.initialSeed, timer0: r.timer0, buttons: r.buttons,
                                     advances: r.advances, ivAdvances: r.ivAdvances,
                                     pid: r.pid, ivs: ivs, nature: r.nature,
                                     ability: r.ability, gender: r.gender, shiny: r.shiny,
                                     hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                                     chatot: r.chatot)
        }
    }

    static func search5WildResults(_ handle: OpaquePointer) -> [Gen5WildSearchResult] {
        var count: Int32 = 0
        guard let ptr = pf_search5_wild_getResults(UnsafeMutableRawPointer(handle), &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return Gen5WildSearchResult(year: Int(r.dateTime.year), month: Int(r.dateTime.month),
                                         day: Int(r.dateTime.day), hour: Int(r.dateTime.hour),
                                         minute: Int(r.dateTime.minute), second: Int(r.dateTime.second),
                                         initialSeed: r.initialSeed, timer0: r.timer0, buttons: r.buttons,
                                         advances: r.advances, ivAdvances: r.ivAdvances,
                                         pid: r.pid, ivs: ivs, nature: r.nature,
                                         ability: r.ability, gender: r.gender, shiny: r.shiny,
                                         hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                                         encounterSlot: r.encounterSlot, level: r.level,
                                         item: r.item, specie: r.specie, form: r.form,
                                         chatot: r.chatot)
        }
    }

    static func search5Cancel(_ handle: OpaquePointer) {
        pf_search5_cancel(UnsafeMutableRawPointer(handle))
    }

    static func search5Free(_ handle: OpaquePointer) {
        pf_search5_free(UnsafeMutableRawPointer(handle))
    }

    // MARK: - Seed Verification (Gen 4)

    static func coinFlips(_ seed: UInt32) -> String {
        let cStr = pf_coinFlips(seed)!
        let result = String(cString: cStr)
        free(cStr)
        return result
    }

    static func getCalls(_ seed: UInt32, skips: UInt8 = 0) -> String {
        let cStr = pf_getCalls(seed, skips)!
        let result = String(cString: cStr)
        free(cStr)
        return result
    }

    /// HeartGold/SoulSilver's roamers (Raikou, Entei, Latias/Latios) on
    /// loading from `seed`: the PRNG advances they take, which come before
    /// Elm and Irwin's calls, and each active one's new route (0 when
    /// inactive). `previousRoutes` are where they were (0 for unknown).
    static func hgssRoamers(seed: UInt32, active: [Bool], previousRoutes: [UInt8] = [0, 0, 0])
        -> (skips: UInt8, routes: [UInt8]) {
        var routes: [UInt8] = [0, 0, 0]
        let skips = pf_hgssRoamer(seed, active, previousRoutes, &routes)
        return (skips, routes)
    }

    /// Gen 3's PRNG: the advances from `from` to `to`.
    static func lcrngDistance(from: UInt32, to: UInt32) -> UInt32 {
        pf_lcrngDistance(from, to)
    }

    /// PokéFinder's IV checker with `game`'s base stats for `specie`: per
    /// stat, every IV its stats at each level allow (empty when none does).
    /// Nil when the species isn't in the game.
    static func calcIVs(game: PFGame, specie: UInt16, form: UInt8 = 0,
                        lines: [(level: UInt8, stats: [UInt16])], nature: UInt8,
                        characteristic: UInt8 = 255, hiddenPower: UInt8 = 255) -> [[UInt8]]? {
        guard !lines.isEmpty, lines.allSatisfy({ $0.stats.count == 6 }) else { return nil }
        var masks = [UInt32](repeating: 0, count: 6)
        guard pf_calcIVs(game.rawValue, specie, form, lines.map(\.level), lines.flatMap(\.stats), Int32(lines.count),
                         nature, characteristic, hiddenPower, &masks) else { return nil }
        return masks.map { mask in (0..<32).compactMap { mask & (1 << $0) != 0 ? UInt8($0) : nil } }
    }

    /// `game`'s base stats for `specie` (HP, Atk, Def, SpA, SpD, Spe).
    static func baseStats(game: PFGame, specie: UInt16, form: UInt8 = 0) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: 6)
        return pf_baseStats(game.rawValue, specie, form, &out) ? out : nil
    }

    /// The forms `specie` has in `game` (1 for just its base form, 0 when it
    /// isn't in the game).
    static func formCount(game: PFGame, specie: UInt16) -> Int {
        Int(pf_formCount(game.rawValue, specie))
    }

    /// The species `game`'s table marks present.
    static func presentSpecies(game: PFGame) -> [UInt16] {
        var count: Int32 = 0
        guard let ptr = pf_presentSpecies(game.rawValue, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return Array(UnsafeBufferPointer(start: ptr, count: Int(count)))
    }

    /// Per stat, the first level above `level` at which two of these IVs give
    /// different stats (`level` when the IV is known or no level up to 100
    /// does), PokéFinder's `IVChecker::nextLevel`. Any nature counts as Hardy.
    static func nextLevel(game: PFGame, specie: UInt16, form: UInt8 = 0, ivs: [[UInt8]],
                          level: UInt8, nature: UInt8) -> [UInt8]? {
        let masks = ivs.map { set in set.reduce(UInt32(0)) { $0 | (1 << UInt32($1)) } }
        var out = [UInt8](repeating: 0, count: 6)
        return pf_nextLevel(game.rawValue, specie, form, masks, level, nature, &out) ? out : nil
    }

    /// PokéFinder's 30 characteristics, in its order: index / 5 is the stat
    /// (HP, Atk, Def, Spe, SpA, SpD) with the highest IV, index % 5 that
    /// IV mod 5.
    static let characteristics: [String] = (0..<30).map { index in
        initTranslator()
        guard let cStr = pf_getCharacteristic(UInt8(index)) else { return "" }
        defer { pf_freeString(cStr) }
        return String(cString: cStr)
    }

    // MARK: - Gen 8 Result Types

    struct Gen8StaticResult: Identifiable {
        let id = UUID()
        let ec: UInt32
        let pid: UInt32
        let advances: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let hiddenPower: UInt8
        let hiddenPowerStrength: UInt8
        let height: UInt8
        let weight: UInt8
        let level: UInt8
    }

    struct Gen8WildResult: Identifiable {
        let id = UUID()
        let ec: UInt32
        let pid: UInt32
        let advances: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let hiddenPower: UInt8
        let hiddenPowerStrength: UInt8
        let height: UInt8
        let weight: UInt8
        let encounterSlot: UInt8
        let level: UInt8
        let item: UInt16
        let specie: UInt16
        let form: UInt8
    }

    struct Gen8EggResult: Identifiable {
        let id = UUID()
        let ec: UInt32
        let pid: UInt32
        let advances: UInt32
        let seed: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let inheritance: [UInt8]
    }

    struct Gen8IDResult: Identifiable {
        let id = UUID()
        let advances: UInt32
        let tid: UInt16
        let sid: UInt16
        let tsv: UInt16
        let displayTID: UInt32
    }

    struct Gen8UndergroundResult: Identifiable {
        let id = UUID()
        let ec: UInt32
        let pid: UInt32
        let advances: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let hiddenPower: UInt8
        let hiddenPowerStrength: UInt8
        let height: UInt8
        let weight: UInt8
        let eggMove: UInt16
        let item: UInt16
        let specie: UInt16
        let level: UInt8
    }

    // MARK: Gen 8 Static Generator

    static func staticGenerate8(seed0: UInt64, seed1: UInt64,
                                 initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                                 lead: PFLead = .none,
                                 tid: UInt16, sid: UInt16, game: PFGame,
                                 nationalDex: Bool = true, shinyCharm: Bool = false, ovalCharm: Bool = false,
                                 staticType: Int32 = 0, staticIndex: Int32 = 0,
                                 filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                 ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                 natures: [Bool] = Array(repeating: false, count: 25),
                                 powers: [Bool] = Array(repeating: false, count: 16)) -> [Gen8StaticResult] {
        var count: Int32 = 0
        let ptr = pf_staticGenerate8(seed0, seed1, initialAdvances, maxAdvances, offset,
                                      lead.rawValue, tid, sid, game.rawValue,
                                      nationalDex, shinyCharm, ovalCharm,
                                      staticType, staticIndex,
                                      filterGender, filterAbility, filterShiny,
                                      ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return Gen8StaticResult(ec: r.ec, pid: r.pid, advances: r.advances,
                                     ivs: ivs, nature: r.nature, ability: r.ability,
                                     gender: r.gender, shiny: r.shiny,
                                     hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                                     height: r.height, weight: r.weight, level: r.level)
        }
    }

    // MARK: Gen 8 Wild Generator

    static func wildGenerate8(seed0: UInt64, seed1: UInt64,
                               initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                               lead: PFLead = .none,
                               tid: UInt16, sid: UInt16, game: PFGame,
                               nationalDex: Bool = true, shinyCharm: Bool = false, ovalCharm: Bool = false,
                               encounter: PFEncounter, location: UInt8,
                               time: Int32 = 0, swarm: Bool = false, radar: Bool = false,
                               replacement0: UInt16 = 0, replacement1: UInt16 = 0,
                               filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                               ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                               natures: [Bool] = Array(repeating: true, count: 25),
                               powers: [Bool] = Array(repeating: true, count: 16),
                               encounterSlots: [Bool] = Array(repeating: true, count: 12)) -> [Gen8WildResult] {
        var count: Int32 = 0
        let ptr = pf_wildGenerate8(seed0, seed1, initialAdvances, maxAdvances, offset,
                                    lead.rawValue, tid, sid, game.rawValue,
                                    nationalDex, shinyCharm, ovalCharm,
                                    encounter.rawValue, location,
                                    time, swarm, radar, replacement0, replacement1,
                                    filterGender, filterAbility, filterShiny,
                                    ivMin, ivMax, natures, powers, encounterSlots, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return Gen8WildResult(ec: r.ec, pid: r.pid, advances: r.advances,
                                   ivs: ivs, nature: r.nature, ability: r.ability,
                                   gender: r.gender, shiny: r.shiny,
                                   hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                                   height: r.height, weight: r.weight,
                                   encounterSlot: r.encounterSlot, level: r.level,
                                   item: r.item, specie: r.specie, form: r.form)
        }
    }

    // MARK: Gen 8 Egg Generator

    static func eggGenerate8(seed0: UInt64, seed1: UInt64,
                              initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                              compatibility: UInt8,
                              parentAIVs: [UInt8], parentBIVs: [UInt8],
                              parentAAbility: UInt8, parentBAbility: UInt8,
                              parentAGender: UInt8, parentBGender: UInt8,
                              parentAItem: UInt8, parentBItem: UInt8,
                              parentANature: UInt8, parentBNature: UInt8,
                              eggSpecie: UInt16, masuda: Bool,
                              tid: UInt16, sid: UInt16, game: PFGame,
                              nationalDex: Bool = true, shinyCharm: Bool = false, ovalCharm: Bool = false,
                              filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                              ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                              natures: [Bool] = Array(repeating: false, count: 25),
                              powers: [Bool] = Array(repeating: false, count: 16)) -> [Gen8EggResult] {
        var count: Int32 = 0
        let ptr = pf_eggGenerate8(seed0, seed1, initialAdvances, maxAdvances, offset,
                                   compatibility,
                                   parentAIVs, parentBIVs,
                                   parentAAbility, parentBAbility,
                                   parentAGender, parentBGender,
                                   parentAItem, parentBItem,
                                   parentANature, parentBNature,
                                   eggSpecie, masuda,
                                   tid, sid, game.rawValue,
                                   nationalDex, shinyCharm, ovalCharm,
                                   filterGender, filterAbility, filterShiny,
                                   ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            let inh = [r.inheritance.0, r.inheritance.1, r.inheritance.2,
                       r.inheritance.3, r.inheritance.4, r.inheritance.5]
            return Gen8EggResult(ec: r.ec, pid: r.pid, advances: r.advances,
                                  seed: r.seed, ivs: ivs, nature: r.nature,
                                  ability: r.ability, gender: r.gender, shiny: r.shiny,
                                  inheritance: inh)
        }
    }

    // MARK: Gen 8 ID Generator

    static func idGenerate8(seed0: UInt64, seed1: UInt64,
                              initialAdvances: UInt32, maxAdvances: UInt32,
                              filterTID: UInt16 = 0, hasTIDFilter: Bool = false,
                              filterSID: UInt16 = 0, hasSIDFilter: Bool = false,
                              filterDisplayTID: UInt32 = 0, hasDisplayFilter: Bool = false) -> [Gen8IDResult] {
        var count: Int32 = 0
        guard let ptr = pf_idGenerate8(seed0, seed1, initialAdvances, maxAdvances,
                                        filterTID, hasTIDFilter,
                                        filterSID, hasSIDFilter,
                                        filterDisplayTID, hasDisplayFilter, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return Gen8IDResult(advances: r.advances, tid: r.tid, sid: r.sid,
                                 tsv: r.tsv, displayTID: r.displayTID)
        }
    }

    // MARK: Gen 8 Raid Generator

    static func raidGenerate8(seed: UInt64,
                               initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                               tid: UInt16, sid: UInt16, game: PFGame,
                               nationalDex: Bool = true, shinyCharm: Bool = false, ovalCharm: Bool = false,
                               denIndex: UInt16, rarity: UInt8,
                               raidIndex: UInt8, level: UInt8,
                               filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                               ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                               natures: [Bool] = Array(repeating: false, count: 25),
                               powers: [Bool] = Array(repeating: false, count: 16)) -> [Gen8StaticResult] {
        var count: Int32 = 0
        let ptr = pf_raidGenerate8(seed, initialAdvances, maxAdvances, offset,
                                    tid, sid, game.rawValue,
                                    nationalDex, shinyCharm, ovalCharm,
                                    denIndex, rarity, raidIndex, level,
                                    filterGender, filterAbility, filterShiny,
                                    ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return Gen8StaticResult(ec: r.ec, pid: r.pid, advances: r.advances,
                                     ivs: ivs, nature: r.nature, ability: r.ability,
                                     gender: r.gender, shiny: r.shiny,
                                     hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                                     height: r.height, weight: r.weight, level: r.level)
        }
    }

    // MARK: Gen 8 Underground Generator

    static func undergroundGenerate8(seed0: UInt64, seed1: UInt64,
                                      initialAdvances: UInt32, maxAdvances: UInt32, offset: UInt32 = 0,
                                      lead: PFLead = .none,
                                      diglett: Bool = false, levelFlag: UInt8 = 0,
                                      tid: UInt16, sid: UInt16, game: PFGame,
                                      nationalDex: Bool = true, shinyCharm: Bool = false, ovalCharm: Bool = false,
                                      storyFlag: Int32 = 1, location: UInt8,
                                      species: [UInt16] = [],
                                      filterGender: UInt8 = 255, filterAbility: UInt8 = 255, filterShiny: UInt8 = 255,
                                      ivMin: [UInt8] = [0,0,0,0,0,0], ivMax: [UInt8] = [31,31,31,31,31,31],
                                      natures: [Bool] = Array(repeating: false, count: 25),
                                      powers: [Bool] = Array(repeating: false, count: 16)) -> [Gen8UndergroundResult] {
        var count: Int32 = 0
        let ptr = pf_undergroundGenerate8(seed0, seed1, initialAdvances, maxAdvances, offset,
                                           lead.rawValue, diglett, levelFlag,
                                           tid, sid, game.rawValue,
                                           nationalDex, shinyCharm, ovalCharm,
                                           storyFlag, location, species, Int32(species.count),
                                           filterGender, filterAbility, filterShiny,
                                           ivMin, ivMax, natures, powers, &count)
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            let ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            return Gen8UndergroundResult(ec: r.ec, pid: r.pid, advances: r.advances,
                                          ivs: ivs, nature: r.nature, ability: r.ability,
                                          gender: r.gender, shiny: r.shiny,
                                          hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                                          height: r.height, weight: r.weight,
                                          eggMove: r.eggMove, item: r.item,
                                          specie: r.specie, level: r.level)
        }
    }

    /// A Grand Underground area at a story stage: its location, name and
    /// the species it can give.
    struct UndergroundArea: Hashable, Sendable {
        let location: UInt8
        let name: String
        let species: [UInt16]
    }

    /// The Grand Underground's areas, as PokéFinder's Underground screen
    /// lists them (named as location + 181).
    static func undergroundAreas8(storyFlag: Int32, diglett: Bool = false, game: PFGame) -> [UndergroundArea] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getUndergroundAreas8(storyFlag, diglett, game.rawValue, true, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        let areas = (0..<Int(count)).map { ptr[$0] }
        let names = locationNames(areas.map { UInt16($0.location) + 181 }, game: game)
        return areas.enumerated().map { i, a in
            let species = withUnsafeBytes(of: a.species) { Array($0.bindMemory(to: UInt16.self).prefix(Int(a.speciesCount))) }
            return UndergroundArea(location: a.location, name: i < names.count ? names[i] : "Location \(a.location)",
                                   species: species)
        }
    }

    /// Every Pokémon the Great Marsh (or, with `trophyGarden`, the Trophy
    /// Garden) can show as its daily Pokémon in `game`, Gen 4 or BDSP, with
    /// the National Pokédex or without.
    static func dailyPokemon(game: PFGame, trophyGarden: Bool) -> [UInt16] {
        var out = [UInt16](repeating: 0, count: 32)
        let count = pf_getDailyPokemon(game.rawValue, trophyGarden, &out)
        return Array(out.prefix(Int(count)))
    }

    // MARK: Gen 8 Encounter Data

    static func getEncounters8(encounter: PFEncounter, game: PFGame,
                                tid: UInt16 = 0, sid: UInt16 = 0,
                                nationalDex: Bool = true, shinyCharm: Bool = false, ovalCharm: Bool = false,
                                time: Int32 = 0, swarm: Bool = false, radar: Bool = false,
                                replacement0: UInt16 = 0, replacement1: UInt16 = 0) -> [PFEncounterAreaSwift] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getEncounters8(encounter.rawValue, game.rawValue,
                                           tid, sid, nationalDex, shinyCharm, ovalCharm,
                                           time, swarm, radar,
                                           replacement0, replacement1, &count) else { return [] }
        defer { pf_freeResults(ptr) }

        var areas = (0..<Int(count)).map { i -> PFEncounterAreaSwift in
            let r = ptr[i]
            let enc = PFEncounter(rawValue: r.encounter) ?? .grass
            return PFEncounterAreaSwift(location: r.location, rate: r.rate,
                                         encounter: enc, slots: extractSlots(from: r))
        }

        let locationNums = areas.map { UInt16($0.location) }
        let uniqueNums = Array(Set(locationNums))
        let names = locationNames(uniqueNums, game: game)
        let nameMap = Dictionary(uniqueKeysWithValues: zip(uniqueNums, names))
        for i in areas.indices {
            areas[i].locationName = nameMap[UInt16(areas[i].location)] ?? "Unknown"
        }
        return areas
    }

    static func getStaticEncounters8(type: Int32) -> [PFStaticTemplateSwift] {
        initTranslator()
        var count: Int32 = 0
        guard let ptr = pf_getStaticEncounters8(type, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return PFStaticTemplateSwift(game: r.game, specie: r.specie, form: r.form,
                                          shiny: r.shiny, ability: r.ability,
                                          gender: r.gender, level: r.level,
                                          method: r.method, ivCount: r.ivCount)
        }
    }

    // MARK: Slot Extraction Helper

    private static func extractSlots(from area: PFEncounterArea) -> [PFSlotSwift] {
        let count = Int(area.slotCount)
        let mirror = Mirror(reflecting: area.slots)
        var slots: [PFSlotSwift] = []
        slots.reserveCapacity(count)
        for (i, child) in mirror.children.enumerated() {
            guard i < count else { break }
            let slot = child.value as! PFSlot
            slots.append(PFSlotSwift(specie: slot.specie, form: slot.form,
                                      minLevel: slot.minLevel, maxLevel: slot.maxLevel))
        }
        return slots
    }
}
