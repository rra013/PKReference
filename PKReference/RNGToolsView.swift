//
//  RNGToolsView.swift
//  PKReference
//
//  RNG manipulation tools ported from:
//  - PokeFinder by Admiral_Fish, bumba, and EzPzStreamz
//    (https://github.com/Admiral-Fish/PokeFinder) — GPL-3.0-or-later
//  - EonTimer by DasAmpharos
//    (https://github.com/DasAmpharos/EonTimer) — MIT
//
//  The PokeFinder parts (marked "PokeFinder Port") were ported to Swift and
//  modified for PK Reference by rra013 from April 2026. Like the rest of the
//  app, this file is licensed under GPL-3.0-or-later.
//

import SwiftUI
import SwiftData
import AVFoundation

extension UInt8: @retroactive RawRepresentable {
    public init?(rawValue: Int) { self.init(exactly: rawValue) }
    public var rawValue: Int { Int(self) }
}

extension UInt16: @retroactive RawRepresentable {
    public init?(rawValue: Int) { self.init(exactly: rawValue) }
    public var rawValue: Int { Int(self) }
}

extension Set<UInt8>: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        if rawValue.isEmpty { self = [] }
        else { self = Set(rawValue.split(separator: ",").compactMap { UInt8($0) }) }
    }
    public var rawValue: String { sorted().map(String.init).joined(separator: ",") }
}

// ============================================================================
// MARK: - EonTimer Port: Constants (from utils/constants.ts)
// ============================================================================

/// Default minimum length in milliseconds (EonTimer default: 14 seconds)
let EONTIMER_MINIMUM_LENGTH = 14000

/// When a phase is below minimum, add 60s repeatedly (from toMinimumLength)
func eonToMinimumLength(_ value: Int, minimumLength: Int = EONTIMER_MINIMUM_LENGTH) -> Int {
    var v = value
    while v < minimumLength {
        v += 60000
    }
    return v
}

func eonGetMinutesBeforeTarget(_ phases: [Int]) -> Int {
    var total = 0
    for phase in phases {
        if phase == Int.max { continue } // INFINITY
        total += phase
    }
    return total / 60000
}

// Console framerates (from utils/constants.ts)
let GBA_FRAMERATE: Double = 16777216.0 / 280896.0
let NDS_SLOT1_FRAMERATE: Double = 59.8261
let NDS_SLOT2_FRAMERATE: Double = 59.6555

let GBA_MS_PER_FRAME: Double = 1000.0 / GBA_FRAMERATE
let NDS_SLOT1_MS_PER_FRAME: Double = 1000.0 / NDS_SLOT1_FRAMERATE
let NDS_SLOT2_MS_PER_FRAME: Double = 1000.0 / NDS_SLOT2_FRAMERATE

// ============================================================================
// MARK: - EonTimer Port: Console + Calibrator (from timers/calibrator.ts)
// ============================================================================

enum RNGConsole: String, CaseIterable, Identifiable {
    case gba = "GBA"
    case ndsSlot1 = "NDS - Slot 1"
    case ndsSlot2 = "NDS - Slot 2"
    case dsi = "DSi"
    case threeds = "3DS"
    case custom = "Custom"
    var id: String { rawValue }
}

struct CalibratorSettings {
    var console: RNGConsole
    var customFramerate: Double
    var precisionCalibration: Bool
    var minimumLength: Int // in milliseconds
}

let defaultCalibratorSettings = CalibratorSettings(
    console: .ndsSlot1,
    customFramerate: 60.0,
    precisionCalibration: false,
    minimumLength: EONTIMER_MINIMUM_LENGTH
)

/// Banker's rounding to match C# Math.Round behavior (from calibrator.ts)
func roundHalfToEven(_ value: Double) -> Int {
    guard value.isFinite else { return Int(value.rounded()) }
    let lower = floor(value)
    let upper = ceil(value)
    if lower == upper { return Int(lower) }
    let lowerDist = value - lower
    let upperDist = upper - value
    let epsilon = Double.ulpOfOne * max(1, abs(value))
    if abs(lowerDist - upperDist) <= epsilon {
        return Int(lower).isMultiple(of: 2) ? Int(lower) : Int(upper)
    }
    return lowerDist < upperDist ? Int(lower) : Int(upper)
}

func getMsPerFrame(_ settings: CalibratorSettings) -> Double {
    switch settings.console {
    case .gba: return GBA_MS_PER_FRAME
    case .ndsSlot2: return NDS_SLOT2_MS_PER_FRAME
    case .ndsSlot1, .dsi, .threeds: return NDS_SLOT1_MS_PER_FRAME
    case .custom:
        guard settings.customFramerate > 0 else { return NDS_SLOT1_MS_PER_FRAME }
        return 1000.0 / settings.customFramerate
    }
}

func eonToDelays(_ settings: CalibratorSettings, milliseconds: Double) -> Int {
    return roundHalfToEven(milliseconds / getMsPerFrame(settings))
}

func eonToMilliseconds(_ settings: CalibratorSettings, delays: Int) -> Int {
    return roundHalfToEven(getMsPerFrame(settings) * Double(delays))
}

func calibrateToDelays(_ settings: CalibratorSettings, milliseconds: Double) -> Int {
    return settings.precisionCalibration
        ? roundHalfToEven(milliseconds)
        : eonToDelays(settings, milliseconds: milliseconds)
}

func calibrateToMilliseconds(_ settings: CalibratorSettings, delays: Int) -> Int {
    return settings.precisionCalibration ? delays : eonToMilliseconds(settings, delays: delays)
}

func createCalibration(_ settings: CalibratorSettings, delays: Int, seconds: Int) -> Int {
    return eonToMilliseconds(settings, delays: delays - eonToDelays(settings, milliseconds: Double(seconds) * 1000.0))
}

// ============================================================================
// MARK: - EonTimer Port: Second Timer (from timers/secondTimer.ts)
// ============================================================================

func createSecondPhases(targetSecond: Int, calibration: Int, minimumLength: Int = EONTIMER_MINIMUM_LENGTH) -> [Int] {
    return [eonToMinimumLength(targetSecond * 1000 + calibration + 200, minimumLength: minimumLength)]
}

func calibrateSecond(targetSecond: Int, secondHit: Int) -> Double {
    if secondHit < targetSecond {
        return Double((targetSecond - secondHit) * 1000 - 500)
    } else if secondHit > targetSecond {
        return Double((targetSecond - secondHit) * 1000 + 500)
    }
    return 0
}

// ============================================================================
// MARK: - EonTimer Port: Delay Timer (from timers/delayTimer.ts)
// ============================================================================

private let CLOSE_THRESHOLD: Double = 167
private let CLOSE_UPDATE_FACTOR: Double = 0.75

func createDelayPhases(_ settings: CalibratorSettings, targetDelay: Int, targetSecond: Int, calibration: Int) -> [Int] {
    let secondPhases = createSecondPhases(targetSecond: targetSecond, calibration: calibration, minimumLength: settings.minimumLength)
    let delayMs = eonToMilliseconds(settings, delays: targetDelay)
    let phase1 = eonToMinimumLength(secondPhases[0] - delayMs, minimumLength: settings.minimumLength)
    let phase2 = delayMs - calibration
    return [phase1, phase2]
}

func calibrateDelay(_ settings: CalibratorSettings, targetDelay: Int, delayHit: Int) -> Double {
    let delta = Double(eonToMilliseconds(settings, delays: delayHit) - eonToMilliseconds(settings, delays: targetDelay))
    if abs(delta) <= CLOSE_THRESHOLD {
        return CLOSE_UPDATE_FACTOR * delta
    }
    return delta
}

// ============================================================================
// MARK: - EonTimer Port: Frame Timer (from timers/frameTimer.ts)
// ============================================================================

func createFramePhases(_ settings: CalibratorSettings, preTimer: Int, targetFrame: Int, calibration: Int) -> [Int] {
    return [preTimer, createFramePhase(settings, targetFrame: targetFrame, calibration: calibration)]
}

func createFramePhase(_ settings: CalibratorSettings, targetFrame: Int, calibration: Int) -> Int {
    return eonToMilliseconds(settings, delays: targetFrame) + calibration
}

func calibrateFrame(_ settings: CalibratorSettings, targetFrame: Int, frameHit: Int) -> Int {
    return eonToMilliseconds(settings, delays: targetFrame - frameHit)
}

func createVariableFramePhases(preTimer: Int) -> [Int] {
    return [preTimer, Int.max]
}

// ============================================================================
// MARK: - EonTimer Port: Entralink Timer (from timers/entralinkTimer.ts)
// ============================================================================

private let ENTRALINK_FRAME_RATE: Double = 0.837148929

func createEntralinkPhases(_ settings: CalibratorSettings, targetDelay: Int, targetSecond: Int,
                            calibration: Int, entralinkCalibration: Int) -> [Int] {
    var durations = createDelayPhases(settings, targetDelay: targetDelay, targetSecond: targetSecond, calibration: calibration)
    durations[0] += 250
    durations[1] -= entralinkCalibration
    return durations
}

func createEnhancedEntralinkPhases(_ settings: CalibratorSettings, targetDelay: Int, targetSecond: Int,
                                    targetAdvances: Int, calibration: Int,
                                    entralinkCalibration: Int, frameCalibration: Int) -> [Int] {
    var phases = createEntralinkPhases(settings, targetDelay: targetDelay, targetSecond: targetSecond,
                                        calibration: calibration, entralinkCalibration: entralinkCalibration)
    phases.append(Int((Double(targetAdvances) / ENTRALINK_FRAME_RATE) * 1000) + frameCalibration)
    return phases
}

func calibrateEntralinkAdvances(targetAdvances: Int, advancesHit: Int) -> Double {
    return (Double(targetAdvances - advancesHit) / ENTRALINK_FRAME_RATE) * 1000
}

// ============================================================================
// MARK: - EonTimer Port: Gen 3 Timer (from timers/gen3Timer.ts)
// ============================================================================

enum Gen3TimerMode: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case variableTarget = "Variable Target"
    var id: String { rawValue }
}

func createGen3Phases(_ settings: CalibratorSettings, mode: Gen3TimerMode,
                       preTimer: Int, targetFrame: Int, calibration: Int) -> [Int] {
    switch mode {
    case .standard:
        return createFramePhases(settings, preTimer: preTimer, targetFrame: targetFrame, calibration: calibration)
    case .variableTarget:
        return createVariableFramePhases(preTimer: preTimer)
    }
}

func calibrateGen3(_ settings: CalibratorSettings, targetFrame: Int, frameHit: Int) -> Int {
    return calibrateFrame(settings, targetFrame: targetFrame, frameHit: frameHit)
}

// ============================================================================
// MARK: - EonTimer Port: Gen 4 Timer (from timers/gen4Timer.ts)
// ============================================================================

func getGen4Calibration(_ settings: CalibratorSettings, calibratedDelay: Int, calibratedSecond: Int) -> Int {
    return createCalibration(settings, delays: calibratedDelay, seconds: calibratedSecond)
}

func createGen4Phases(_ settings: CalibratorSettings, targetDelay: Int, targetSecond: Int,
                       calibratedDelay: Int, calibratedSecond: Int) -> [Int] {
    let cal = getGen4Calibration(settings, calibratedDelay: calibratedDelay, calibratedSecond: calibratedSecond)
    return createDelayPhases(settings, targetDelay: targetDelay, targetSecond: targetSecond, calibration: cal)
}

func calibrateGen4(_ settings: CalibratorSettings, targetDelay: Int, delayHit: Int) -> Int {
    guard delayHit > 0 else { return 0 }
    return eonToDelays(settings, milliseconds: calibrateDelay(settings, targetDelay: targetDelay, delayHit: delayHit))
}

// ============================================================================
// MARK: - EonTimer Port: Gen 5 Timer (from timers/gen5Timer.ts)
// ============================================================================

enum Gen5TimerMode: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case cGear = "C-Gear"
    case entralink = "Entralink"
    case entralinkPlus = "Entralink+"
    var id: String { rawValue }
}

func createGen5Phases(_ settings: CalibratorSettings, mode: Gen5TimerMode,
                       targetDelay: Int, targetSecond: Int, targetAdvances: Int,
                       calibration: Int, entralinkCalibration: Int, frameCalibration: Int) -> [Int] {
    let calMs = calibrateToMilliseconds(settings, delays: calibration)
    let entCalMs = calibrateToMilliseconds(settings, delays: entralinkCalibration)

    switch mode {
    case .standard:
        return createSecondPhases(targetSecond: targetSecond, calibration: calMs, minimumLength: settings.minimumLength)
    case .cGear:
        return createDelayPhases(settings, targetDelay: targetDelay, targetSecond: targetSecond, calibration: calMs)
    case .entralink:
        return createEntralinkPhases(settings, targetDelay: targetDelay, targetSecond: targetSecond,
                                      calibration: calMs, entralinkCalibration: entCalMs)
    case .entralinkPlus:
        return createEnhancedEntralinkPhases(settings, targetDelay: targetDelay, targetSecond: targetSecond,
                                              targetAdvances: targetAdvances, calibration: calMs,
                                              entralinkCalibration: entCalMs, frameCalibration: frameCalibration)
    }
}

struct Gen5CalibrationResult {
    var calibrationDelta: Int
    var entralinkCalibrationDelta: Int
    var frameCalibrationDelta: Double
}

func calibrateGen5(_ settings: CalibratorSettings, mode: Gen5TimerMode,
                    targetDelay: Int, targetSecond: Int, targetAdvances: Int,
                    delayHit: Int?, secondHit: Int?, advancesHit: Int?) -> Gen5CalibrationResult {
    var result = Gen5CalibrationResult(calibrationDelta: 0, entralinkCalibrationDelta: 0, frameCalibrationDelta: 0)

    switch mode {
    case .standard:
        if let sh = secondHit {
            result.calibrationDelta = calibrateToDelays(settings, milliseconds: calibrateSecond(targetSecond: targetSecond, secondHit: sh))
        }
    case .cGear:
        if let dh = delayHit {
            result.calibrationDelta = calibrateToDelays(settings, milliseconds: calibrateDelay(settings, targetDelay: targetDelay, delayHit: dh))
        }
    case .entralink, .entralinkPlus:
        if let sh = secondHit, sh != targetSecond {
            result.calibrationDelta = calibrateToDelays(settings, milliseconds: calibrateSecond(targetSecond: targetSecond, secondHit: sh))
        }
        if let dh = delayHit, dh != targetDelay {
            result.entralinkCalibrationDelta = calibrateToDelays(settings,
                milliseconds: calibrateDelay(settings, targetDelay: targetDelay, delayHit: dh))
        }
        if mode == .entralinkPlus, let ah = advancesHit, ah != targetAdvances {
            result.frameCalibrationDelta = calibrateEntralinkAdvances(targetAdvances: targetAdvances, advancesHit: ah)
        }
    }

    return result
}

// ============================================================================
// MARK: - EonTimer Port: Custom Timer (from timers/customTimer.ts)
// ============================================================================

enum CustomTimerUnit: String, CaseIterable, Identifiable {
    case milliseconds = "ms"
    case advances = "Advances"
    case hex = "Seed (Hex)"
    var id: String { rawValue }
}

struct CustomPhase {
    var unit: CustomTimerUnit
    var target: Int
    var calibration: Int
}

func createCustomPhases(_ settings: CalibratorSettings, phases: [CustomPhase]) -> [Int] {
    return phases.map { phase in
        var value = phase.target
        if phase.unit == .advances || phase.unit == .hex {
            value = eonToMilliseconds(settings, delays: value)
        }
        return value + phase.calibration
    }
}

// ============================================================================
// MARK: - PokeFinder Port: LCRNG (from Core/RNG/LCRNG.hpp + LCRNG.cpp)
// ============================================================================

/// Linear Congruential RNG used in Pokemon Gen 3/4 games.
/// Ported from PokeFinder by Admiral_Fish, bumba, and EzPzStreamz (GPLv3)nonisolated .
nonisolated struct LCRNG {
    let mult: UInt32
    let add: UInt32
    var seed: UInt32

    init(mult: UInt32, add: UInt32, seed: UInt32) {
        self.mult = mult
        self.add = add
        self.seed = seed
    }

    @discardableResult
    mutating func next() -> UInt32 {
        seed = seed &* mult &+ add
        return seed
    }

    func nextUShort() -> UInt16 {
        return UInt16((seed &* mult &+ add) >> 16)
    }

    @discardableResult
    mutating func advance(_ count: Int) -> UInt32 {
        for _ in 0..<count { next() }
        return seed
    }
}

// Standard Pokemon RNG constants
nonisolated let pokeRNGMult: UInt32 = 0x41C64E6D
nonisolated let pokeRNGAdd: UInt32 = 0x6073
nonisolated let pokeRNGRMult: UInt32 = 0xEEB9EB65
nonisolated let pokeRNGRAdd: UInt32 = 0x0A3561A1

nonisolated let xdRNGMult: UInt32 = 0x343FD
nonisolated let xdRNGAdd: UInt32 = 0x269EC3
nonisolated let xdRNGRMult: UInt32 = 0xB9B33155
nonisolated let xdRNGRAdd: UInt32 = 0xA170F641

nonisolated func makePokeRNG(_ seed: UInt32) -> LCRNG { LCRNG(mult: pokeRNGMult, add: pokeRNGAdd, seed: seed) }
nonisolated func makePokeRNGR(_ seed: UInt32) -> LCRNG { LCRNG(mult: pokeRNGRMult, add: pokeRNGRAdd, seed: seed) }
nonisolated func makeXDRNG(_ seed: UInt32) -> LCRNG { LCRNG(mult: xdRNGMult, add: xdRNGAdd, seed: seed) }
nonisolated func makeXDRNGR(_ seed: UInt32) -> LCRNG { LCRNG(mult: xdRNGRMult, add: xdRNGRAdd, seed: seed) }

// ============================================================================
// MARK: - PokeFinder Port: LCRNGReverse (from Core/RNG/LCRNGReverse.cpp)
// ============================================================================

/// Recovers origin seeds from IVs using meet-in-the-middle attacks.
/// Ported from PokeFinder (GPLv3).
nonisolated enum LCRNGReverse {
    enum RNGMethod {
        case method1, method1Reverse, method2, method4
        case xdColo, channel
        case cuteCharmDPPt, cuteCharmHGSS
    }

    struct IVToPIDResult: Identifiable {
        let id = UUID()
        let seed: UInt32
        let pid: UInt32
        let sid: UInt16
        let method: RNGMethod
        var methodName: String {
            switch method {
            case .method1: return "Method 1"
            case .method1Reverse: return "Method 1 (R)"
            case .method2: return "Method 2"
            case .method4: return "Method 4"
            case .xdColo: return "XD/Colo"
            case .channel: return "Channel"
            case .cuteCharmDPPt: return "Cute Charm (DPPt)"
            case .cuteCharmHGSS: return "Cute Charm (HGSS)"
            }
        }
    }

    // Method 1/2 seed recovery (no gap between IV calls)
    static func recoverPokeRNGIVMethod12(hp: UInt8, atk: UInt8, def: UInt8,
                                          spa: UInt8, spd: UInt8, spe: UInt8) -> [(UInt32)] {
        let mult: UInt32 = 0x41c64e6d
        let add: UInt32 = 0x6073
        let mod: UInt32 = 0x67d3
        let pat: UInt32 = 0xd3e
        let inc: UInt32 = 0x4034

        var seeds: [UInt32] = []
        let firstIVs: UInt32 = UInt32(hp) | (UInt32(atk) << 5) | (UInt32(def) << 10)
        let first: UInt32 = firstIVs << 16
        let secondIVs: UInt32 = UInt32(spe) | (UInt32(spa) << 5) | (UInt32(spd) << 10)
        let second: UInt32 = secondIVs << 16

        let diff = UInt16(truncatingIfNeeded: (second &- first &* mult) >> 16)
        let s1a: UInt32 = (UInt32(diff) &* mod &+ inc) >> 16
        let start1 = UInt16(truncatingIfNeeded: (s1a &* pat) % mod)
        let s2a: UInt32 = (UInt32(diff ^ 0x8000) &* mod &+ inc) >> 16
        let start2 = UInt16(truncatingIfNeeded: (s2a &* pat) % mod)

        var low = UInt32(start1)
        while low < 0x10000 {
            let seed = first | low
            if (seed &* mult &+ add) & 0x7fff0000 == second {
                seeds.append(seed)
                seeds.append(seed ^ 0x80000000)
            }
            low += UInt32(mod)
        }

        low = UInt32(start2)
        while low < 0x10000 {
            let seed = first | low
            if (seed &* mult &+ add) & 0x7fff0000 == second {
                seeds.append(seed)
                seeds.append(seed ^ 0x80000000)
            }
            low += UInt32(mod)
        }

        return seeds
    }

    // Method 4 seed recovery (gap between IV calls)
    static func recoverPokeRNGIVMethod4(hp: UInt8, atk: UInt8, def: UInt8,
                                         spa: UInt8, spd: UInt8, spe: UInt8) -> [UInt32] {
        let mult: UInt32 = 0xc2a29a69
        let add: UInt32 = 0xe97e7b6a
        let mod: UInt32 = 0x3a89
        let pat: UInt32 = 0x2e4c
        let inc: UInt32 = 0x5831

        var seeds: [UInt32] = []
        let firstIVs: UInt32 = UInt32(hp) | (UInt32(atk) << 5) | (UInt32(def) << 10)
        let first: UInt32 = firstIVs << 16
        let secondIVs: UInt32 = UInt32(spe) | (UInt32(spa) << 5) | (UInt32(spd) << 10)
        let second: UInt32 = secondIVs << 16

        let diff = UInt16(truncatingIfNeeded: (second &- (first &* mult &+ add)) >> 16)
        let s1a: UInt32 = (UInt32(diff) &* mod &+ inc) >> 16
        let start1 = UInt16(truncatingIfNeeded: (s1a &* pat) % mod)
        let s2a: UInt32 = (UInt32(diff ^ 0x8000) &* mod &+ inc) >> 16
        let start2 = UInt16(truncatingIfNeeded: (s2a &* pat) % mod)

        var low = UInt32(start1)
        while low < 0x10000 {
            let seed = first | low
            if (seed &* mult &+ add) & 0x7fff0000 == second {
                seeds.append(seed)
                seeds.append(seed ^ 0x80000000)
            }
            low += UInt32(mod)
        }

        low = UInt32(start2)
        while low < 0x10000 {
            let seed = first | low
            if (seed &* mult &+ add) & 0x7fff0000 == second {
                seeds.append(seed)
                seeds.append(seed ^ 0x80000000)
            }
            low += UInt32(mod)
        }

        return seeds
    }

    // XDRNG IV seed recovery
    static func recoverXDRNGIV(hp: UInt8, atk: UInt8, def: UInt8,
                                spa: UInt8, spd: UInt8, spe: UInt8) -> [UInt32] {
        let mult: UInt32 = 0x343fd
        let sub: UInt32 = 0x259ec4
        let base: UInt64 = 0x343fabc02

        var seeds: [UInt32] = []
        let firstIVs: UInt32 = UInt32(hp) | (UInt32(atk) << 5) | (UInt32(def) << 10)
        let first: UInt32 = firstIVs << 16
        let secondIVs: UInt32 = UInt32(spe) | (UInt32(spa) << 5) | (UInt32(spd) << 10)
        let second: UInt32 = secondIVs << 16

        let rawT: UInt32 = (second &- mult &* first) &- sub
        var t = UInt64(rawT) & 0x7FFFFFFF
        let kmax = (base &- t) >> 31

        for _ in 0...kmax {
            if t % UInt64(mult) < 0x10000 {
                let seed = first | UInt32(t / UInt64(mult))
                seeds.append(seed)
                seeds.append(seed ^ 0x80000000)
            }
            t &+= 0x80000000
        }

        return seeds
    }

    /// Full IV-to-PID calculation (from IVToPIDCalculator.cpp)
    static func calculatePIDs(hp: UInt8, atk: UInt8, def: UInt8,
                               spa: UInt8, spd: UInt8, spe: UInt8,
                               nature: UInt8, tid: UInt16) -> [IVToPIDResult] {
        let bridgeResults = PFBridge.ivToPID(hp: hp, atk: atk, def: def,
                                              spa: spa, spd: spd, spe: spe,
                                              nature: nature, tid: tid)
        return bridgeResults.map { r in
            let method: RNGMethod = switch PFMethod(rawValue: r.method) {
            case .method1: .method1
            case .method1Reverse: .method1Reverse
            case .method2: .method2
            case .method4: .method4
            case .xdColo: .xdColo
            case .channel: .channel
            case .cuteCharmDPPt: .cuteCharmDPPt
            case .cuteCharmHGSS: .cuteCharmHGSS
            default: .method1
            }
            return IVToPIDResult(seed: r.seed, pid: r.pid, sid: r.sid, method: method)
        }
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Finder Types & Models
// ============================================================================

/// Nature names in game-engine index order (pid % 25), PokéFinder's order.
/// Matches pfNatureModifiers. As a 5×5 grid, rows raise Attack, Defense,
/// Speed, Sp. Atk, Sp. Def and columns lower them, in that order.
let pfNatureNames: [String] = [
    "Hardy", "Lonely", "Brave", "Adamant", "Naughty",
    "Bold", "Docile", "Relaxed", "Impish", "Lax",
    "Timid", "Hasty", "Serious", "Jolly", "Naive",
    "Modest", "Mild", "Quiet", "Bashful", "Rash",
    "Calm", "Gentle", "Sassy", "Careful", "Quirky"
]

enum FinderGeneration: String, CaseIterable, Identifiable {
    case gen3 = "Gen 3"
    case gen4 = "Gen 4"
    case gen5 = "Gen 5"
    case gen8 = "Gen 8"
    var id: String { rawValue }
}

enum FinderMethod: String, CaseIterable, Identifiable, Sendable {
    case method1 = "Method 1"
    case method2 = "Method 2"
    case method4 = "Method 4"
    case methodJ = "Method J"
    case methodK = "Method K"
    case method5 = "Method 5"
    case method5IVs = "Method 5 IVs"
    case method5CGear = "Method 5 C-Gear"
    var id: String { rawValue }

    static func methods(for gen: FinderGeneration) -> [FinderMethod] {
        switch gen {
        case .gen3: return [.method1, .method2, .method4]
        case .gen4: return [.method1, .methodJ, .methodK]
        case .gen5: return [.method5, .method5IVs, .method5CGear]
        case .gen8: return [.method1]
        }
    }
}

enum FinderLead: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case synchronize = "Synchronize"
    case cuteCharmF = "Cute Charm ♀"
    case cuteCharmM = "Cute Charm ♂"
    case magnetPull = "Magnet Pull"
    case staticLead = "Static"
    case pressure = "Pressure"
    case compoundEyes = "Compound Eyes"
    case suctionCups = "Suction Cups"
    case flashFire = "Flash Fire"
    case harvest = "Harvest"
    case stormDrain = "Storm Drain"
    case arenaTrap = "Arena Trap"
    var id: String { rawValue }

    /// The lead as PokéFinder's generators take it: Synchronize with
    /// `syncNature`. (Searchers take `pfLead`, where it means any nature.)
    nonisolated func pfGeneratorLead(syncNature: UInt8) -> PFLead {
        self == .synchronize ? .synchronize(nature: syncNature) : pfLead
    }

    /// The lead as PokéFinder's searchers take it.
    nonisolated var pfLead: PFLead {
        switch self {
        case .none: return .none
        case .synchronize: return .synchronize
        case .cuteCharmF: return .cuteCharmF
        case .cuteCharmM: return .cuteCharmM
        case .magnetPull: return .magnetPull
        case .staticLead: return .staticLead
        case .pressure: return .pressure
        case .compoundEyes: return .compoundEyes
        case .suctionCups: return .suctionCups
        case .flashFire: return .flashFire
        case .harvest: return .harvest
        case .stormDrain: return .stormDrain
        case .arenaTrap: return .arenaTrap
        }
    }

    static func leads(for gen: FinderGeneration, encounterMode: Bool) -> [FinderLead] {
        if !encounterMode { return [.none, .synchronize] }
        switch gen {
        case .gen3:
            return [.none, .synchronize, .magnetPull, .staticLead, .pressure, .compoundEyes, .suctionCups, .arenaTrap]
        case .gen4:
            return [.none, .synchronize, .cuteCharmF, .cuteCharmM, .magnetPull, .staticLead, .pressure, .compoundEyes, .suctionCups, .flashFire, .harvest, .stormDrain, .arenaTrap]
        case .gen5:
            return [.none, .synchronize, .cuteCharmF, .cuteCharmM, .magnetPull, .staticLead, .pressure, .compoundEyes, .suctionCups, .flashFire, .harvest, .stormDrain, .arenaTrap]
        case .gen8:
            return [.none, .synchronize, .cuteCharmF, .cuteCharmM, .magnetPull, .staticLead, .pressure, .compoundEyes, .suctionCups, .flashFire, .harvest, .stormDrain, .arenaTrap]
        }
    }
}

/// PokéFinder's shiny filter for a Shiny Only switch: star or square (1 | 2).
/// The games show both the same way.
nonisolated func pfShinyFilter(_ shinyOnly: Bool) -> UInt8 { shinyOnly ? 3 : 255 }

nonisolated func finderMethodToPF(_ method: FinderMethod) -> PFMethod {
    switch method {
    case .method1: return .method1
    case .method2: return .method2
    case .method4: return .method4
    case .methodJ: return .methodJ
    case .methodK: return .methodK
    case .method5: return .method5
    case .method5IVs: return .method5IVs
    case .method5CGear: return .method5CGear
    }
}

struct StaticSearchResult: Identifiable, Sendable {
    let id = UUID()
    let seed: UInt32
    let pid: UInt32
    let ivHP: UInt8
    let ivAtk: UInt8
    let ivDef: UInt8
    let ivSpA: UInt8
    let ivSpD: UInt8
    let ivSpe: UInt8
    let nature: UInt8
    let ability: UInt8
    let gender: UInt8
    let shiny: Bool
    let advances: UInt32
    let method: FinderMethod
    let hiddenPower: UInt8
    let hiddenPowerStrength: UInt8

    // Wild encounter data
    let encounterSlot: UInt8?
    let level: UInt8?
    let item: UInt16?
    let specie: UInt16?
    let form: UInt8?

    // Gen 4/5 extras
    let call: UInt8?
    let chatot: UInt8?
    let ivAdvances: UInt32?

    // Gen 5 searcher metadata
    let dateTimeString: String?
    let initialSeed64: UInt64?
    let timer0: UInt16?
    let buttons: UInt16?

    // Gen 8 ID results
    let resultTID: UInt16?
    let resultSID: UInt16?
    let resultTSV: UInt16?
    let resultDisplayTID: UInt32?

    // Gen 8 Egg results
    let inheritance: [UInt8]?
    let eggSeed: UInt32?

    // Gen 8 Underground extras
    let eggMove: UInt16?

    nonisolated init(seed: UInt32, pid: UInt32,
         ivHP: UInt8, ivAtk: UInt8, ivDef: UInt8, ivSpA: UInt8, ivSpD: UInt8, ivSpe: UInt8,
         nature: UInt8, ability: UInt8, gender: UInt8, shiny: Bool, advances: UInt32, method: FinderMethod,
         hiddenPower: UInt8 = 0, hiddenPowerStrength: UInt8 = 0,
         encounterSlot: UInt8? = nil, level: UInt8? = nil, item: UInt16? = nil,
         specie: UInt16? = nil, form: UInt8? = nil,
         call: UInt8? = nil, chatot: UInt8? = nil,
         ivAdvances: UInt32? = nil,
         dateTimeString: String? = nil, initialSeed64: UInt64? = nil,
         timer0: UInt16? = nil, buttons: UInt16? = nil,
         resultTID: UInt16? = nil, resultSID: UInt16? = nil,
         resultTSV: UInt16? = nil, resultDisplayTID: UInt32? = nil,
         inheritance: [UInt8]? = nil, eggSeed: UInt32? = nil,
         eggMove: UInt16? = nil) {
        self.seed = seed; self.pid = pid
        self.ivHP = ivHP; self.ivAtk = ivAtk; self.ivDef = ivDef
        self.ivSpA = ivSpA; self.ivSpD = ivSpD; self.ivSpe = ivSpe
        self.nature = nature; self.ability = ability; self.gender = gender
        self.shiny = shiny; self.advances = advances; self.method = method
        self.hiddenPower = hiddenPower; self.hiddenPowerStrength = hiddenPowerStrength
        self.encounterSlot = encounterSlot; self.level = level
        self.item = item; self.specie = specie; self.form = form
        self.call = call; self.chatot = chatot
        self.ivAdvances = ivAdvances
        self.dateTimeString = dateTimeString; self.initialSeed64 = initialSeed64
        self.timer0 = timer0; self.buttons = buttons
        self.resultTID = resultTID; self.resultSID = resultSID
        self.resultTSV = resultTSV; self.resultDisplayTID = resultDisplayTID
        self.inheritance = inheritance; self.eggSeed = eggSeed
        self.eggMove = eggMove
    }

    var natureName: String { pfNatureNames[Int(nature)] }
    var pidHex: String { String(format: "%08X", pid) }
    var seedHex: String { String(format: "%08X", seed) }
    var seedHex64: String? { initialSeed64.map { String(format: "%016llX", $0) } }
    var buttonPressName: String? {
        guard let b = buttons else { return nil }
        if b == 0 { return "None" }
        var names: [String] = []
        if b & 1 != 0 { names.append("R") }
        if b & 2 != 0 { names.append("L") }
        if b & 4 != 0 { names.append("X") }
        if b & 8 != 0 { names.append("Y") }
        if b & 16 != 0 { names.append("A") }
        if b & 32 != 0 { names.append("B") }
        if b & 64 != 0 { names.append("Select") }
        if b & 128 != 0 { names.append("Start") }
        if b & 256 != 0 { names.append("Right") }
        if b & 512 != 0 { names.append("Left") }
        if b & 1024 != 0 { names.append("Up") }
        if b & 2048 != 0 { names.append("Down") }
        return names.joined(separator: "+")
    }
    var ivSummary: String { "\(ivHP)/\(ivAtk)/\(ivDef)/\(ivSpA)/\(ivSpD)/\(ivSpe)" }
    var specieName: String? { specie.flatMap { $0 > 0 ? PFBridge.specieName($0) : nil } }
    var abilityDisplayName: String { PFBridge.abilityName(UInt16(ability)) }
    var hiddenPowerName: String { hiddenPowerTypes[Int(hiddenPower) % hiddenPowerTypes.count] }
    var itemName: String? { item.flatMap { $0 > 0 ? PFBridge.itemName($0) : nil } }
    var genderSymbol: String {
        switch gender {
        case 0: return "♂"
        case 1: return "♀"
        case 2: return "-"
        default: return "?"
        }
    }
    var chatotPitch: String? {
        guard let c = chatot else { return nil }
        let label: String
        switch c {
        case 0..<20: label = "L"
        case 20..<40: label = "ML"
        case 40..<60: label = "M"
        case 60..<80: label = "MH"
        default: label = "H"
        }
        return "\(label) \(c)"
    }
    var callName: String? {
        guard let c = call else { return nil }
        switch c {
        case 0: return "E"
        case 1: return "K"
        case 2: return "P"
        default: return "?"
        }
    }
}

struct SeedToTimeResult3: Identifiable, Hashable {
    let id = UUID()
    let originSeed: UInt16
    let advances: UInt32
    let day: Int
    let hour: Int
    let minute: Int

    var displayTime: String { String(format: "Day %d  %02d:%02d", day + 1, hour, minute) }
}

struct SeedToTimeResult4: Identifiable, Hashable {
    let id = UUID()
    let seed: UInt32
    let delay: UInt32
    let hour: UInt8
    let month: Int
    let day: Int
    let minute: Int
    let second: Int

    var displayTime: String {
        String(format: "%02d/%02d %02d:%02d:%02d  (delay %d)", month, day, hour, minute, second, delay)
    }
}

struct SeedVerificationResult {
    let actualSeed: UInt32
    let targetSeed: UInt32
    let delayDelta: Int
}

// ============================================================================
// MARK: - PokeFinder Port: Finder Profiles
// ============================================================================

struct FinderProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var tid: UInt16
    var sid: UInt16
    var gameVersion: String?
    var deadBattery: Bool = false
    var nationalDex: Bool = false

    // Gen 5 DS parameters
    var mac: UInt64 = 0
    var timer0Min: UInt16 = 0
    var timer0Max: UInt16 = 0
    var vcount: UInt8 = 0
    var gxstat: UInt8 = 0
    var vframe: UInt8 = 0
    var keypresses: [Bool] = Array(repeating: false, count: 9)
    var skipLR: Bool = false
    var dsType: UInt8 = 0       // 0=DS, 1=DSi, 2=3DS
    var language: UInt8 = 0     // 0=ENG, 1=FRE, 2=DEU, 3=ITA, 4=JPN, 5=KOR, 6=SPA
    var memoryLink: Bool = false
    var shinyCharm: Bool = false

    var isGen5: Bool {
        guard let g = gameVersion else { return false }
        return ["Black", "White", "Black 2", "White 2"].contains(g)
    }

    var gen5Game: PFGame? {
        switch gameVersion {
        case "Black":   return .black
        case "White":   return .white
        case "Black 2": return .black2
        case "White 2": return .white2
        default:        return nil
        }
    }

    var macString: String {
        get { String(format: "%012llX", mac) }
        set { mac = UInt64(newValue.replacingOccurrences(of: ":", with: ""), radix: 16) ?? 0 }
    }

    var displayName: String {
        if let g = gameVersion, !g.isEmpty {
            return "\(name) (\(g) \(tid)/\(sid))"
        }
        return "\(name) (\(tid)/\(sid))"
    }
}

/// Manages saved TID/SID profiles via UserDefaults.
enum FinderProfileStore {
    private static let key = "finderProfiles"
    private static let lastKey = "finderLastProfileID"

    static func load() -> [FinderProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profiles = try? JSONDecoder().decode([FinderProfile].self, from: data)
        else { return [] }
        return profiles
    }

    static func save(_ profiles: [FinderProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static var lastProfileID: UUID? {
        get {
            guard let str = UserDefaults.standard.string(forKey: lastKey) else { return nil }
            return UUID(uuidString: str)
        }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: lastKey) }
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Gen 3 Origin Seed Recovery
// ============================================================================

/// Walk backward from a 32-bit seed to find the 16-bit origin seed (Gen 3).
/// Returns (originSeed, advanceCount).
nonisolated func findGen3OriginSeed(_ seed: UInt32) -> (UInt16, UInt32) {
    if seed <= 0xFFFF { return (UInt16(seed), 0) }
    var rng = makePokeRNGR(seed)
    var count: UInt32 = 0
    var current = seed
    while current > 0xFFFF {
        current = rng.next()
        count += 1
    }
    return (UInt16(current), count)
}

// ============================================================================
// MARK: - PokeFinder Port: Static Generator (Gen 3)
// ============================================================================

/// Generate Pokemon at each advance from a known seed using Gen 3 methods.
nonisolated func staticGenerateGen3(
    seed: UInt32,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod
) -> [StaticSearchResult] {
    var results: [StaticSearchResult] = []
    staticGenerateGen3Streaming(
        seed: seed, initialAdvance: initialAdvance, maxAdvance: maxAdvance,
        natures: natures, tid: tid, sid: sid, shinyOnly: shinyOnly, method: method
    ) { results.append($0) }
    return results
}

nonisolated func staticGenerateGen3Streaming(
    seed: UInt32,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    game: PFGame = .none,
    template: PFStaticTemplateRef? = nil,
    filterGender: UInt8 = 255,
    filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    onResult: (StaticSearchResult) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    // The encounter's template gives its gender; without one, every result
    // is genderless.
    let results = if let template {
        PFBridge.staticTemplateGenerate3(
            seed: seed, initialAdvances: initialAdvance, maxAdvances: maxAdvance,
            method: pfMethod, template: template, tid: tid, sid: sid, game: game,
            filterGender: filterGender, filterAbility: filterAbility,
            filterShiny: shinyFilter, natures: natArr, powers: hiddenPowers)
    } else {
        PFBridge.staticGenerate3(
            seed: seed, initialAdvances: initialAdvance, maxAdvances: maxAdvance,
            method: pfMethod, tid: tid, sid: sid,
            filterGender: filterGender, filterAbility: filterAbility,
            filterShiny: shinyFilter, natures: natArr, powers: hiddenPowers)
    }

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: seed, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: method,
            hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength
        ))
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Static Searcher (Gen 3)
// ============================================================================

/// Search for seeds producing Pokemon matching the given IV/nature/shiny filters.
/// CPU-intensive — call from a background task.
nonisolated func staticSearchGen3(
    minIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    maxIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod
) -> [StaticSearchResult] {
    var results: [StaticSearchResult] = []
    staticSearchGen3Streaming(
        minIVs: minIVs, maxIVs: maxIVs, natures: natures,
        tid: tid, sid: sid, shinyOnly: shinyOnly, method: method
    ) { results.append($0) }
    return results
}

/// The search runs on its own thread and is read every tenth of a second,
/// so results and progress come in as it goes. `template` is the static
/// encounter's, for its gender and bugged roamers' IVs; without one, every
/// result is genderless.
nonisolated func staticSearchGen3Streaming(
    minIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    maxIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    game: PFGame = .none,
    template: PFStaticTemplateRef? = nil,
    filterGender: UInt8 = 255,
    filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    onProgress: (Double) -> Void = { _ in },
    onResult: (StaticSearchResult) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)
    let ivMin = [minIVs.0, minIVs.1, minIVs.2, minIVs.3, minIVs.4, minIVs.5]
    let ivMax = [maxIVs.0, maxIVs.1, maxIVs.2, maxIVs.3, maxIVs.4, maxIVs.5]

    let handle = PFBridge.staticSearch3Start(
        method: pfMethod, tid: tid, sid: sid, game: game, template: template,
        filterGender: filterGender, filterAbility: filterAbility,
        filterShiny: shinyFilter, ivMin: ivMin, ivMax: ivMax,
        natures: natArr, powers: hiddenPowers)
    defer { PFBridge.staticSearch3Free(handle) }

    func send(_ results: [PFSearcherStateSwift]) {
        for r in results {
            onResult(StaticSearchResult(
                seed: r.seed, pid: r.pid,
                ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
                ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
                nature: r.nature, ability: r.ability,
                gender: r.gender, shiny: r.shiny > 0,
                advances: 0, method: method,
                hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength
            ))
        }
    }

    while !PFBridge.staticSearch3Done(handle) {
        if Task.isCancelled {
            PFBridge.staticSearch3Cancel(handle)
            return
        }
        send(PFBridge.staticSearch3Results(handle))
        onProgress(Double(PFBridge.staticSearch3Progress(handle)))
        Thread.sleep(forTimeInterval: 0.1)
    }
    send(PFBridge.staticSearch3Results(handle))
    onProgress(100)
}

// ============================================================================
// MARK: - PokeFinder Port: Seed to Time (Gen 3)
// ============================================================================

/// Convert a 32-bit seed to date/time combinations (Gen 3).
/// Ported from PokeFinder's SeedToTimeCalculator3.
nonisolated func seedToTimeGen3(seed: UInt32) -> (originSeed: UInt16, advances: UInt32, times: [SeedToTimeResult3]) {
    let origin = PFBridge.seedToTimeOriginSeed3(seed: seed)
    let dateTimes = PFBridge.seedToTime3(seed: UInt32(origin.originSeed), year: 2000)
    let times = dateTimes.prefix(200).map { dt in
        SeedToTimeResult3(originSeed: origin.originSeed, advances: origin.advances,
                          day: (dt.month - 1) * 31 + dt.day - 1, hour: dt.hour, minute: dt.minute)
    }
    return (origin.originSeed, origin.advances, times)
}

// ============================================================================
// MARK: - PokeFinder Port: Seed to Time (Gen 4)
// ============================================================================

/// Convert a 32-bit seed to date/time combinations (Gen 4).
/// Seed format: ab|cd|efgh where ab = hash, cd = hour, efgh = delay.
/// Ported from PokeFinder's SeedToTimeCalculator4.
nonisolated func seedToTimeGen4(seed: UInt32) -> [SeedToTimeResult4] {
    let bridgeResults = PFBridge.seedToTime4(seed: seed, year: 2000)
    return bridgeResults.prefix(300).map { r in
        SeedToTimeResult4(seed: seed, delay: UInt32(r.delay),
                          hour: UInt8(r.dateTime.hour),
                          month: r.dateTime.month, day: r.dateTime.day,
                          minute: r.dateTime.minute, second: r.dateTime.second)
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Static Generator (Gen 4)
// ============================================================================

/// Generate Pokemon at each advance from a known seed using Gen 4 methods.
/// Method 1 is identical to Gen 3 Method 1.
/// Method J (DPPt) and Method K (HGSS) use nature-locked PID loops.
nonisolated func staticGenerateGen4(
    seed: UInt32,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    lead: FinderLead,
    syncNature: UInt8 = 0
) -> [StaticSearchResult] {
    var results: [StaticSearchResult] = []
    staticGenerateGen4Streaming(
        seed: seed, initialAdvance: initialAdvance, maxAdvance: maxAdvance,
        natures: natures, tid: tid, sid: sid, shinyOnly: shinyOnly,
        method: method, lead: lead, syncNature: syncNature
    ) { results.append($0) }
    return results
}

nonisolated func staticGenerateGen4Streaming(
    seed: UInt32,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    lead: FinderLead,
    syncNature: UInt8 = 0,
    filterGender: UInt8 = 255,
    filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    onResult: (StaticSearchResult) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    let pfLead = lead.pfGeneratorLead(syncNature: syncNature)
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    let results = PFBridge.staticGenerate4(
        seed: seed, initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        method: pfMethod, lead: pfLead, tid: tid, sid: sid,
        filterGender: filterGender, filterAbility: filterAbility,
        filterShiny: shinyFilter, natures: natArr, powers: hiddenPowers)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: seed, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: method,
            hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
            call: r.call, chatot: r.chatot
        ))
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Static Searcher (Gen 4)
// ============================================================================

/// Search for Gen 4 seeds matching the given filters.
/// Validates initial seeds against hour < 24 and delay range.
nonisolated func staticSearchGen4(
    minIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    maxIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    minDelay: UInt16,
    maxDelay: UInt16
) -> [StaticSearchResult] {
    var results: [StaticSearchResult] = []
    staticSearchGen4Streaming(
        minIVs: minIVs, maxIVs: maxIVs, natures: natures,
        tid: tid, sid: sid, shinyOnly: shinyOnly, method: method,
        minDelay: minDelay, maxDelay: maxDelay
    ) { results.append($0) }
    return results
}

nonisolated func staticSearchGen4Streaming(
    minIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    maxIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    minAdvance: UInt32 = 0,
    maxAdvance: UInt32 = 0,
    minDelay: UInt16,
    maxDelay: UInt16,
    filterGender: UInt8 = 255,
    filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    onResult: (StaticSearchResult) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)
    let ivMin = [minIVs.0, minIVs.1, minIVs.2, minIVs.3, minIVs.4, minIVs.5]
    let ivMax = [maxIVs.0, maxIVs.1, maxIVs.2, maxIVs.3, maxIVs.4, maxIVs.5]

    let results = PFBridge.staticSearch4(
        minAdvance: minAdvance, maxAdvance: maxAdvance,
        minDelay: UInt32(minDelay), maxDelay: UInt32(maxDelay),
        method: pfMethod, tid: tid, sid: sid,
        filterGender: filterGender, filterAbility: filterAbility,
        filterShiny: shinyFilter, ivMin: ivMin, ivMax: ivMax,
        natures: natArr, powers: hiddenPowers)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: r.seed, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: method,
            hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength
        ))
    }
}

// ============================================================================
// MARK: - PokeFinder Port: Static Generator (Gen 5)
// ============================================================================

nonisolated func staticGenerateGen5Streaming(
    seed: UInt64,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    lead: FinderLead,
    syncNature: UInt8 = 0,
    game: PFGame,
    mac: UInt64, keypresses: [Bool],
    vcount: UInt8, gxstat: UInt8, vframe: UInt8,
    skipLR: Bool, timer0Min: UInt16, timer0Max: UInt16,
    memoryLink: Bool, shinyCharm: Bool,
    dsType: UInt8, language: UInt8,
    filterGender: UInt8 = 255,
    filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    onResult: (StaticSearchResult) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    let pfLead = lead.pfGeneratorLead(syncNature: syncNature)
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    let results = PFBridge.staticGenerate5(
        seed: seed, initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        method: pfMethod, lead: pfLead, tid: tid, sid: sid, game: game,
        mac: mac, keypresses: keypresses,
        vcount: vcount, gxstat: gxstat, vframe: vframe,
        skipLR: skipLR, timer0Min: timer0Min, timer0Max: timer0Max,
        memoryLink: memoryLink, shinyCharm: shinyCharm,
        dsType: dsType, language: language,
        filterGender: filterGender, filterAbility: filterAbility,
        filterShiny: shinyFilter, natures: natArr, powers: hiddenPowers)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: 0, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: method,
            hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
            chatot: r.chatot, ivAdvances: r.ivAdvances
        ))
    }
}

nonisolated func wildGenerateGen5Streaming(
    seed: UInt64,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    lead: FinderLead,
    syncNature: UInt8 = 0,
    game: PFGame,
    encounter: PFEncounter, location: UInt8, season: UInt8,
    mac: UInt64, keypresses: [Bool],
    vcount: UInt8, gxstat: UInt8, vframe: UInt8,
    skipLR: Bool, timer0Min: UInt16, timer0Max: UInt16,
    memoryLink: Bool, shinyCharm: Bool,
    dsType: UInt8, language: UInt8,
    filterGender: UInt8 = 255,
    filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    encounterSlots: [Bool] = Array(repeating: true, count: 12),
    onResult: (StaticSearchResult) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    let pfLead = lead.pfGeneratorLead(syncNature: syncNature)
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    let results = PFBridge.wildGenerate5(
        seed: seed, initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        method: pfMethod, lead: pfLead, tid: tid, sid: sid, game: game,
        encounter: encounter, location: location, season: season,
        mac: mac, keypresses: keypresses,
        vcount: vcount, gxstat: gxstat, vframe: vframe,
        skipLR: skipLR, timer0Min: timer0Min, timer0Max: timer0Max,
        memoryLink: memoryLink, shinyCharm: shinyCharm,
        dsType: dsType, language: language,
        filterGender: filterGender, filterAbility: filterAbility,
        filterShiny: shinyFilter, natures: natArr, powers: hiddenPowers,
        encounterSlots: encounterSlots)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: 0, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: method,
            hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
            encounterSlot: r.encounterSlot, level: r.level,
            item: r.item, specie: r.specie, form: r.form,
            chatot: r.chatot, ivAdvances: r.ivAdvances
        ))
    }
}

// ============================================================================
// MARK: - Gen 8 Generator Streaming
// ============================================================================

nonisolated func staticGenerateGen8Streaming(
    seed0: UInt64, seed1: UInt64,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    lead: FinderLead,
    syncNature: UInt8 = 0,
    game: PFGame,
    shinyCharm: Bool,
    staticType: Int32 = 0, staticIndex: Int32 = 0,
    filterGender: UInt8 = 255,
    filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    onResult: (StaticSearchResult) -> Void
) {
    let pfLead = lead.pfGeneratorLead(syncNature: syncNature)
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    let results = PFBridge.staticGenerate8(
        seed0: seed0, seed1: seed1,
        initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        lead: pfLead, tid: tid, sid: sid, game: game,
        shinyCharm: shinyCharm,
        staticType: staticType, staticIndex: staticIndex,
        filterGender: filterGender, filterAbility: filterAbility,
        filterShiny: shinyFilter, natures: natArr, powers: hiddenPowers)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: r.ec, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: .method1,
            hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength
        ))
    }
}

nonisolated func wildGenerateGen8Streaming(
    seed0: UInt64, seed1: UInt64,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    lead: FinderLead,
    syncNature: UInt8 = 0,
    game: PFGame,
    shinyCharm: Bool,
    encounter: PFEncounter, location: UInt8,
    filterGender: UInt8 = 255,
    filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    encounterSlots: [Bool] = Array(repeating: true, count: 12),
    onResult: (StaticSearchResult) -> Void
) {
    let pfLead = lead.pfGeneratorLead(syncNature: syncNature)
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    let results = PFBridge.wildGenerate8(
        seed0: seed0, seed1: seed1,
        initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        lead: pfLead, tid: tid, sid: sid, game: game,
        shinyCharm: shinyCharm,
        encounter: encounter, location: location,
        filterGender: filterGender, filterAbility: filterAbility,
        filterShiny: shinyFilter, natures: natArr, powers: hiddenPowers,
        encounterSlots: encounterSlots)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: r.ec, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: .method1,
            hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
            encounterSlot: r.encounterSlot, level: r.level,
            item: r.item, specie: r.specie, form: r.form
        ))
    }
}

// ============================================================================
// MARK: - Gen 8 Egg Generator Streaming
// ============================================================================

nonisolated func eggGenerateGen8Streaming(
    seed0: UInt64, seed1: UInt64,
    initialAdvance: UInt32, maxAdvance: UInt32,
    compatibility: UInt8,
    parentAIVs: [UInt8], parentBIVs: [UInt8],
    parentAAbility: UInt8, parentBAbility: UInt8,
    parentAGender: UInt8, parentBGender: UInt8,
    parentAItem: UInt8, parentBItem: UInt8,
    parentANature: UInt8, parentBNature: UInt8,
    eggSpecie: UInt16, masuda: Bool,
    natures: Set<UInt8>,
    tid: UInt16, sid: UInt16,
    shinyOnly: Bool,
    game: PFGame,
    shinyCharm: Bool, ovalCharm: Bool,
    filterGender: UInt8 = 255, filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    onResult: (StaticSearchResult) -> Void
) {
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    let results = PFBridge.eggGenerate8(
        seed0: seed0, seed1: seed1,
        initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        compatibility: compatibility,
        parentAIVs: parentAIVs, parentBIVs: parentBIVs,
        parentAAbility: parentAAbility, parentBAbility: parentBAbility,
        parentAGender: parentAGender, parentBGender: parentBGender,
        parentAItem: parentAItem, parentBItem: parentBItem,
        parentANature: parentANature, parentBNature: parentBNature,
        eggSpecie: eggSpecie, masuda: masuda,
        tid: tid, sid: sid, game: game,
        shinyCharm: shinyCharm, ovalCharm: ovalCharm,
        filterGender: filterGender, filterAbility: filterAbility,
        filterShiny: shinyFilter, natures: natArr, powers: hiddenPowers)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: r.ec, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: .method1,
            inheritance: r.inheritance, eggSeed: r.seed
        ))
    }
}

// ============================================================================
// MARK: - Gen 8 ID Generator Streaming
// ============================================================================

nonisolated func idGenerateGen8Streaming(
    seed0: UInt64, seed1: UInt64,
    initialAdvance: UInt32, maxAdvance: UInt32,
    filterTID: UInt16, hasTIDFilter: Bool,
    filterSID: UInt16, hasSIDFilter: Bool,
    filterDisplayTID: UInt32, hasDisplayFilter: Bool,
    onResult: (StaticSearchResult) -> Void
) {
    let results = PFBridge.idGenerate8(
        seed0: seed0, seed1: seed1,
        initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        filterTID: filterTID, hasTIDFilter: hasTIDFilter,
        filterSID: filterSID, hasSIDFilter: hasSIDFilter,
        filterDisplayTID: filterDisplayTID, hasDisplayFilter: hasDisplayFilter)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: 0, pid: 0,
            ivHP: 0, ivAtk: 0, ivDef: 0, ivSpA: 0, ivSpD: 0, ivSpe: 0,
            nature: 0, ability: 0, gender: 0, shiny: false,
            advances: r.advances, method: .method1,
            resultTID: r.tid, resultSID: r.sid,
            resultTSV: r.tsv, resultDisplayTID: r.displayTID
        ))
    }
}

// ============================================================================
// MARK: - Gen 8 Raid Generator Streaming
// ============================================================================

nonisolated func raidGenerateGen8Streaming(
    seed: UInt64,
    initialAdvance: UInt32, maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16, sid: UInt16,
    shinyOnly: Bool,
    game: PFGame,
    shinyCharm: Bool,
    denIndex: UInt16, rarity: UInt8,
    raidIndex: UInt8, level: UInt8,
    filterGender: UInt8 = 255, filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    onResult: (StaticSearchResult) -> Void
) {
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    let results = PFBridge.raidGenerate8(
        seed: seed,
        initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        tid: tid, sid: sid, game: game,
        shinyCharm: shinyCharm,
        denIndex: denIndex, rarity: rarity,
        raidIndex: raidIndex, level: level,
        filterGender: filterGender, filterAbility: filterAbility,
        filterShiny: shinyFilter, natures: natArr, powers: hiddenPowers)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: r.ec, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: .method1,
            hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
            level: r.level
        ))
    }
}

// ============================================================================
// MARK: - Gen 8 Underground Generator Streaming
// ============================================================================

nonisolated func undergroundGenerateGen8Streaming(
    seed0: UInt64, seed1: UInt64,
    initialAdvance: UInt32, maxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16, sid: UInt16,
    shinyOnly: Bool,
    lead: FinderLead,
    syncNature: UInt8 = 0,
    game: PFGame,
    shinyCharm: Bool,
    diglett: Bool, storyFlag: Int32,
    filterGender: UInt8 = 255, filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    onResult: (StaticSearchResult) -> Void
) {
    let pfLead = lead.pfGeneratorLead(syncNature: syncNature)
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    let results = PFBridge.undergroundGenerate8(
        seed0: seed0, seed1: seed1,
        initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        lead: pfLead,
        diglett: diglett, levelFlag: 0,
        tid: tid, sid: sid, game: game,
        shinyCharm: shinyCharm,
        storyFlag: storyFlag,
        filterGender: filterGender, filterAbility: filterAbility,
        filterShiny: shinyFilter, natures: natArr, powers: hiddenPowers)

    for r in results {
        if Task.isCancelled { return }
        onResult(StaticSearchResult(
            seed: r.ec, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: .method1,
            hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
            item: r.item, specie: r.specie,
            eggMove: r.eggMove
        ))
    }
}

// ============================================================================
// MARK: - Gen 5 Async Searcher Streaming
// ============================================================================

nonisolated func staticSearchGen5Streaming(
    initialAdvance: UInt32, maxAdvance: UInt32,
    ivInitialAdvance: UInt32, ivMaxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16, sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    lead: FinderLead,
    syncNature: UInt8 = 0,
    game: PFGame,
    staticType: Int32 = 0, staticIndex: Int32 = 0,
    mac: UInt64, keypresses: [Bool],
    vcount: UInt8, gxstat: UInt8, vframe: UInt8,
    skipLR: Bool, timer0Min: UInt16, timer0Max: UInt16,
    memoryLink: Bool, shinyCharm: Bool,
    dsType: UInt8, language: UInt8,
    startYear: UInt16, startMonth: UInt8, startDay: UInt8,
    endYear: UInt16, endMonth: UInt8, endDay: UInt8,
    filterGender: UInt8 = 255, filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    onResult: (StaticSearchResult) -> Void,
    onProgress: (Double) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    let pfLead = lead.pfGeneratorLead(syncNature: syncNature)
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    guard let handle = PFBridge.staticSearch5Start(
        initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        method: pfMethod, lead: pfLead, tid: tid, sid: sid, game: game,
        staticType: staticType, staticIndex: staticIndex,
        ivInitialAdvances: ivInitialAdvance, ivMaxAdvances: ivMaxAdvance,
        mac: mac, keypresses: keypresses,
        vcount: vcount, gxstat: gxstat, vframe: vframe,
        skipLR: skipLR, timer0Min: timer0Min, timer0Max: timer0Max,
        memoryLink: memoryLink, shinyCharm: shinyCharm,
        dsType: dsType, language: language,
        startYear: startYear, startMonth: startMonth, startDay: startDay,
        endYear: endYear, endMonth: endMonth, endDay: endDay,
        filterGender: filterGender, filterAbility: filterAbility, filterShiny: shinyFilter,
        ivMin: [0,0,0,0,0,0], ivMax: [31,31,31,31,31,31],
        natures: natArr, powers: hiddenPowers
    ) else { return }
    defer { PFBridge.search5Free(handle) }

    while !Task.isCancelled {
        let progress = PFBridge.search5Progress(handle)
        onProgress(Double(progress))

        let results = PFBridge.search5StaticResults(handle)
        for r in results {
            let dtStr = String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                               r.year, r.month, r.day, r.hour, r.minute, r.second)
            onResult(StaticSearchResult(
                seed: 0, pid: r.pid,
                ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
                ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
                nature: r.nature, ability: r.ability,
                gender: r.gender, shiny: r.shiny > 0,
                advances: r.advances, method: method,
                hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                chatot: r.chatot, ivAdvances: r.ivAdvances,
                dateTimeString: dtStr, initialSeed64: r.initialSeed,
                timer0: r.timer0, buttons: r.buttons
            ))
        }

        if progress >= 100 { break }
        Thread.sleep(forTimeInterval: 0.25)
    }

    if Task.isCancelled {
        PFBridge.search5Cancel(handle)
    }

    let finalResults = PFBridge.search5StaticResults(handle)
    for r in finalResults {
        let dtStr = String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                           r.year, r.month, r.day, r.hour, r.minute, r.second)
        onResult(StaticSearchResult(
            seed: 0, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: method,
            hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
            chatot: r.chatot, ivAdvances: r.ivAdvances,
            dateTimeString: dtStr, initialSeed64: r.initialSeed,
            timer0: r.timer0, buttons: r.buttons
        ))
    }
}

nonisolated func wildSearchGen5Streaming(
    initialAdvance: UInt32, maxAdvance: UInt32,
    ivInitialAdvance: UInt32, ivMaxAdvance: UInt32,
    natures: Set<UInt8>,
    tid: UInt16, sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    lead: FinderLead,
    syncNature: UInt8 = 0,
    game: PFGame,
    encounter: PFEncounter, location: UInt8, season: UInt8,
    mac: UInt64, keypresses: [Bool],
    vcount: UInt8, gxstat: UInt8, vframe: UInt8,
    skipLR: Bool, timer0Min: UInt16, timer0Max: UInt16,
    memoryLink: Bool, shinyCharm: Bool,
    dsType: UInt8, language: UInt8,
    startYear: UInt16, startMonth: UInt8, startDay: UInt8,
    endYear: UInt16, endMonth: UInt8, endDay: UInt8,
    filterGender: UInt8 = 255, filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    encounterSlots: [Bool] = Array(repeating: true, count: 12),
    onResult: (StaticSearchResult) -> Void,
    onProgress: (Double) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    let pfLead = lead.pfGeneratorLead(syncNature: syncNature)
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    guard let handle = PFBridge.wildSearch5Start(
        initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        method: pfMethod, lead: pfLead, tid: tid, sid: sid, game: game,
        encounter: encounter, location: location, season: season,
        ivInitialAdvances: ivInitialAdvance, ivMaxAdvances: ivMaxAdvance,
        mac: mac, keypresses: keypresses,
        vcount: vcount, gxstat: gxstat, vframe: vframe,
        skipLR: skipLR, timer0Min: timer0Min, timer0Max: timer0Max,
        memoryLink: memoryLink, shinyCharm: shinyCharm,
        dsType: dsType, language: language,
        startYear: startYear, startMonth: startMonth, startDay: startDay,
        endYear: endYear, endMonth: endMonth, endDay: endDay,
        filterGender: filterGender, filterAbility: filterAbility, filterShiny: shinyFilter,
        ivMin: [0,0,0,0,0,0], ivMax: [31,31,31,31,31,31],
        natures: natArr, powers: hiddenPowers, encounterSlots: encounterSlots
    ) else { return }
    defer { PFBridge.search5Free(handle) }

    while !Task.isCancelled {
        let progress = PFBridge.search5Progress(handle)
        onProgress(Double(progress))

        let results = PFBridge.search5WildResults(handle)
        for r in results {
            let dtStr = String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                               r.year, r.month, r.day, r.hour, r.minute, r.second)
            onResult(StaticSearchResult(
                seed: 0, pid: r.pid,
                ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
                ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
                nature: r.nature, ability: r.ability,
                gender: r.gender, shiny: r.shiny > 0,
                advances: r.advances, method: method,
                hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                encounterSlot: r.encounterSlot, level: r.level,
                item: r.item, specie: r.specie, form: r.form,
                chatot: r.chatot, ivAdvances: r.ivAdvances,
                dateTimeString: dtStr, initialSeed64: r.initialSeed,
                timer0: r.timer0, buttons: r.buttons
            ))
        }

        if progress >= 100 { break }
        Thread.sleep(forTimeInterval: 0.25)
    }

    if Task.isCancelled {
        PFBridge.search5Cancel(handle)
    }

    let finalResults = PFBridge.search5WildResults(handle)
    for r in finalResults {
        let dtStr = String(format: "%04d-%02d-%02d %02d:%02d:%02d",
                           r.year, r.month, r.day, r.hour, r.minute, r.second)
        onResult(StaticSearchResult(
            seed: 0, pid: r.pid,
            ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
            ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
            nature: r.nature, ability: r.ability,
            gender: r.gender, shiny: r.shiny > 0,
            advances: r.advances, method: method,
            hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
            encounterSlot: r.encounterSlot, level: r.level,
            item: r.item, specie: r.specie, form: r.form,
            chatot: r.chatot, ivAdvances: r.ivAdvances,
            dateTimeString: dtStr, initialSeed64: r.initialSeed,
            timer0: r.timer0, buttons: r.buttons
        ))
    }
}

// ============================================================================
// MARK: - Wild Encounter Search/Generate
// ============================================================================

nonisolated func runWildSearch(
    gen: FinderGeneration, mode: FinderRootView.FinderMode, method: FinderMethod,
    natures: Set<UInt8>, tid: UInt16, sid: UInt16, shinyOnly: Bool,
    minIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    maxIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    seed: UInt32, initAdv: UInt32, maxAdv: UInt32,
    searcherMinAdv: UInt32 = 0, searcherMaxAdv: UInt32 = 100,
    minDelay: UInt32, maxDelay: UInt32,
    pfGame: PFGame, pfEnc: PFEncounter, locationID: UInt8,
    slotSpecies: [UInt16],
    speciesFilter: UInt16, lead: FinderLead, syncNature: UInt8 = 0, isEmerald: Bool,
    filterGender: UInt8 = 255, filterAbility: UInt8 = 255,
    hiddenPowers: [Bool] = Array(repeating: false, count: 16),
    onResult: @Sendable (StaticSearchResult) -> Void,
    onProgress: @Sendable (Double) -> Void = { _ in }
) {

    var natArr: [Bool]
    if natures.isEmpty {
        natArr = [Bool](repeating: true, count: 25)
    } else {
        natArr = [Bool](repeating: false, count: 25)
        for n in natures { natArr[Int(n)] = true }
    }
    let ivMin: [UInt8] = [minIVs.0, minIVs.1, minIVs.2, minIVs.3, minIVs.4, minIVs.5]
    let ivMax: [UInt8] = [maxIVs.0, maxIVs.1, maxIVs.2, maxIVs.3, maxIVs.4, maxIVs.5]
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    var encounterSlots = [Bool](repeating: true, count: 12)
    if speciesFilter != 0 {
        for i in 0..<12 {
            encounterSlots[i] = i < slotSpecies.count && slotSpecies[i] == speciesFilter
        }
    }

    let pfMethod = finderMethodToPF(method)

    // Generators take Synchronize's nature; searchers take any.
    let pfLead = mode == .generator ? lead.pfGeneratorLead(syncNature: syncNature) : lead.pfLead
    let deadBattery = isEmerald

    if mode == .generator {
        onProgress(0)
        let results: [StaticSearchResult]
        if gen == .gen3 {
            results = PFBridge.wildGenerate3(
                seed: seed, initialAdvances: initAdv, maxAdvances: maxAdv,
                method: pfMethod, lead: pfLead,
                tid: tid, sid: sid, game: pfGame,
                deadBattery: deadBattery,
                encounter: pfEnc, location: locationID,
                filterGender: filterGender, filterAbility: filterAbility,
                filterShiny: shinyFilter,
                ivMin: ivMin, ivMax: ivMax, natures: natArr,
                powers: hiddenPowers,
                encounterSlots: encounterSlots
            ).map { r in
                StaticSearchResult(
                    seed: seed, pid: r.pid,
                    ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
                    ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
                    nature: r.nature, ability: r.ability,
                    gender: r.gender, shiny: r.shiny > 0,
                    advances: r.advances, method: method,
                    hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                    encounterSlot: r.encounterSlot, level: r.level,
                    item: r.item, specie: r.specie, form: r.form)
            }
        } else {
            results = PFBridge.wildGenerate4(
                seed: seed, initialAdvances: initAdv, maxAdvances: maxAdv,
                method: pfMethod, lead: pfLead,
                tid: tid, sid: sid, game: pfGame,
                encounter: pfEnc, location: locationID,
                filterGender: filterGender, filterAbility: filterAbility,
                filterShiny: shinyFilter,
                ivMin: ivMin, ivMax: ivMax, natures: natArr,
                powers: hiddenPowers,
                encounterSlots: encounterSlots
            ).map { r in
                StaticSearchResult(
                    seed: seed, pid: r.pid,
                    ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
                    ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
                    nature: r.nature, ability: r.ability,
                    gender: r.gender, shiny: r.shiny > 0,
                    advances: r.advances, method: method,
                    hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                    encounterSlot: r.encounterSlot, level: r.level,
                    item: r.item, specie: r.specie, form: r.form,
                    call: r.call, chatot: r.chatot)
            }
        }
        let total = max(results.count, 1)
        for (i, r) in results.enumerated() {
            if Task.isCancelled { return }
            onResult(r)
            if i % 500 == 0 { onProgress(Double(i) / Double(total) * 100) }
        }
        onProgress(100)
    } else {
        let handle: OpaquePointer
        if gen == .gen3 {
            handle = PFBridge.wildSearch3Async(
                method: pfMethod, lead: pfLead,
                tid: tid, sid: sid, game: pfGame,
                deadBattery: deadBattery,
                encounter: pfEnc, location: locationID,
                filterGender: filterGender, filterAbility: filterAbility,
                filterShiny: shinyFilter,
                ivMin: ivMin, ivMax: ivMax, natures: natArr,
                powers: hiddenPowers,
                encounterSlots: encounterSlots)
        } else {
            handle = PFBridge.wildSearch4Async(
                minAdvance: searcherMinAdv, maxAdvance: searcherMaxAdv,
                minDelay: minDelay, maxDelay: maxDelay,
                method: pfMethod, lead: pfLead,
                tid: tid, sid: sid, game: pfGame,
                encounter: pfEnc, location: locationID,
                filterGender: filterGender, filterAbility: filterAbility,
                filterShiny: shinyFilter,
                ivMin: ivMin, ivMax: ivMax, natures: natArr,
                powers: hiddenPowers,
                encounterSlots: encounterSlots)
        }
        defer { PFBridge.searchFree(handle) }

        while PFBridge.searchProgress(handle) < 100 {
            if Task.isCancelled {
                PFBridge.searchCancel(handle)
                return
            }
            onProgress(Double(PFBridge.searchProgress(handle)))
            let batch: [StaticSearchResult]
            if gen == .gen3 {
                batch = PFBridge.searchPollResults3(handle).map { r in
                    StaticSearchResult(
                        seed: r.seed, pid: r.pid,
                        ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
                        ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
                        nature: r.nature, ability: r.ability,
                        gender: r.gender, shiny: r.shiny > 0,
                        advances: 0, method: method,
                        hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                        encounterSlot: r.encounterSlot, level: r.level,
                        item: r.item, specie: r.specie, form: r.form)
                }
            } else {
                batch = PFBridge.searchPollResults4(handle).map { r in
                    StaticSearchResult(
                        seed: r.seed, pid: r.pid,
                        ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
                        ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
                        nature: r.nature, ability: r.ability,
                        gender: r.gender, shiny: r.shiny > 0,
                        advances: r.advances, method: method,
                        hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                        encounterSlot: r.encounterSlot, level: r.level,
                        item: r.item, specie: r.specie, form: r.form)
                }
            }
            for r in batch { onResult(r) }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let final3 = gen == .gen3 ? PFBridge.searchPollResults3(handle) : []
        let final4 = gen == .gen4 ? PFBridge.searchPollResults4(handle) : []
        for r in final3 {
            onResult(StaticSearchResult(
                seed: r.seed, pid: r.pid,
                ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
                ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
                nature: r.nature, ability: r.ability,
                gender: r.gender, shiny: r.shiny > 0,
                advances: 0, method: method,
                hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                encounterSlot: r.encounterSlot, level: r.level,
                item: r.item, specie: r.specie, form: r.form))
        }
        for r in final4 {
            onResult(StaticSearchResult(
                seed: r.seed, pid: r.pid,
                ivHP: r.ivs[0], ivAtk: r.ivs[1], ivDef: r.ivs[2],
                ivSpA: r.ivs[3], ivSpD: r.ivs[4], ivSpe: r.ivs[5],
                nature: r.nature, ability: r.ability,
                gender: r.gender, shiny: r.shiny > 0,
                advances: r.advances, method: method,
                hiddenPower: r.hiddenPower, hiddenPowerStrength: r.hiddenPowerStrength,
                encounterSlot: r.encounterSlot, level: r.level,
                item: r.item, specie: r.specie, form: r.form))
        }
        onProgress(100)
    }
}

nonisolated func findLocationID(pfGame: PFGame, pfEnc: PFEncounter, isGen3: Bool, locationName: String) -> UInt8 {
    let areas: [PFEncounterAreaSwift]
    if isGen3 {
        areas = PFBridge.getEncounters3(encounter: pfEnc, game: pfGame)
    } else {
        areas = PFBridge.getEncounters4(encounter: pfEnc, game: pfGame, tid: 0, sid: 0)
    }
    return areas.first { $0.locationName == locationName }?.location ?? 0
}

nonisolated func findLocationID5(pfGame: PFGame, pfEnc: PFEncounter, locationName: String, season: UInt8 = 0) -> UInt8 {
    let areas = PFBridge.getEncounters5(encounter: pfEnc, game: pfGame, season: season)
    return areas.first { $0.locationName == locationName }?.location ?? 0
}

nonisolated func findLocationID8(pfGame: PFGame, pfEnc: PFEncounter, locationName: String) -> UInt8 {
    let areas = PFBridge.getEncounters8(encounter: pfEnc, game: pfGame)
    return areas.first { $0.locationName == locationName }?.location ?? 0
}

// ============================================================================
// MARK: - Coin Flip Matching (Gen 4 Mersenne Twister)
// ============================================================================

nonisolated func matchesCoinFlips(seed: UInt32, observed: [Bool]) -> Bool {
    var mt = [UInt32](repeating: 0, count: 624)
    mt[0] = seed
    for i in 1..<624 {
        mt[i] = 1812433253 &* (mt[i - 1] ^ (mt[i - 1] >> 30)) &+ UInt32(i)
    }

    var idx = 624
    func nextMT() -> UInt32 {
        if idx >= 624 {
            for i in 0..<624 {
                let y = (mt[i] & 0x80000000) | (mt[(i + 1) % 624] & 0x7fffffff)
                mt[i] = mt[(i + 397) % 624] ^ (y >> 1)
                if y & 1 != 0 { mt[i] ^= 0x9908b0df }
            }
            idx = 0
        }
        var y = mt[idx]
        y ^= (y >> 11)
        y ^= (y << 7) & 0x9d2c5680
        y ^= (y << 15) & 0xefc60000
        y ^= (y >> 18)
        idx += 1
        return y
    }

    for isHeads in observed {
        let isH = (nextMT() & 1) != 0
        if isH != isHeads { return false }
    }
    return true
}

nonisolated func matchesCalls(seed: UInt32, observed: [UInt8], skips: UInt8) -> Bool {
    var rngState = seed
    func nextRNG() -> UInt16 {
        rngState = rngState &* 0x41C64E6D &+ 0x6073
        return UInt16(rngState >> 16)
    }

    // Skip roamer advances
    for _ in 0..<skips {
        _ = nextRNG()
    }

    for expected in observed {
        let call = nextRNG() % 3
        if call != UInt16(expected) { return false }
    }
    return true
}

// ============================================================================
// MARK: - PokeFinder Port: Seed Verification
// ============================================================================

/// Verify what seed was actually hit by reverse-calculating from caught Pokemon's IVs.
/// Returns the delta between actual and target seeds.
nonisolated func verifySeedFromIVs(
    caughtHP: UInt8, caughtAtk: UInt8, caughtDef: UInt8,
    caughtSpA: UInt8, caughtSpD: UInt8, caughtSpe: UInt8,
    caughtNature: UInt8,
    tid: UInt16,
    targetSeed: UInt32,
    method: FinderMethod
) -> SeedVerificationResult? {
    let pidResults = LCRNGReverse.calculatePIDs(
        hp: caughtHP, atk: caughtAtk, def: caughtDef,
        spa: caughtSpA, spd: caughtSpD, spe: caughtSpe,
        nature: caughtNature, tid: tid
    )

    // Find the result whose method matches
    let targetMethod: LCRNGReverse.RNGMethod
    switch method {
    case .method1, .methodJ, .methodK, .method5, .method5IVs, .method5CGear: targetMethod = .method1
    case .method2: targetMethod = .method2
    case .method4: targetMethod = .method4
    }

    let matching = pidResults.filter { $0.method == targetMethod }
    guard let closest = matching.first else { return nil }

    // Compute delay delta for Gen 4 seeds
    let actualDelay = Int(closest.seed & 0xFFFF)
    let targetDelay = Int(targetSeed & 0xFFFF)

    return SeedVerificationResult(
        actualSeed: closest.seed,
        targetSeed: targetSeed,
        delayDelta: actualDelay - targetDelay
    )
}

// ============================================================================
// MARK: - Finder Timer Bridge
// ============================================================================

/// Shared bridge for passing Finder results to the Timer view.
@Observable
final class FinderTimerBridge {
    static let shared = FinderTimerBridge()
    var pendingGen: TimerGeneration?
    var pendingTargetFrame: Int?
    /// FireRed and LeafGreen: the seed time, as the Gen 3 pre-timer.
    var pendingPreTimer: Int?
    /// FireRed and LeafGreen: the final press's calibration, in ms.
    var pendingCalibration: Int?
    var pendingConsole: RNGConsole?
    var pendingTargetDelay: Int?
    var pendingTargetSecond: Int?
    var shouldSwitchToTimer: Bool = false
    var selectedTime: String?
    var selectedSeed: String?

    func clear() {
        pendingGen = nil
        pendingTargetFrame = nil
        pendingPreTimer = nil
        pendingCalibration = nil
        pendingConsole = nil
        pendingTargetDelay = nil
        pendingTargetSecond = nil
        shouldSwitchToTimer = false
        selectedTime = nil
        selectedSeed = nil
    }
}

// ============================================================================
// MARK: - PokeFinder Port: IVChecker (from Core/Util/IVChecker.cpp)
// ============================================================================

/// Nature modifiers table matching PokeFinder's Nature.hpp
private let pfNatureModifiers: [[Float]] = [
    // [Atk, Def, SpA, SpD, Spe]  — nature index 0-24
    [1.0, 1.0, 1.0, 1.0, 1.0], // Hardy
    [1.1, 0.9, 1.0, 1.0, 1.0], // Lonely
    [1.1, 1.0, 1.0, 1.0, 0.9], // Brave
    [1.1, 1.0, 0.9, 1.0, 1.0], // Adamant
    [1.1, 1.0, 1.0, 0.9, 1.0], // Naughty
    [0.9, 1.1, 1.0, 1.0, 1.0], // Bold
    [1.0, 1.0, 1.0, 1.0, 1.0], // Docile
    [1.0, 1.1, 1.0, 1.0, 0.9], // Relaxed
    [1.0, 1.1, 0.9, 1.0, 1.0], // Impish
    [1.0, 1.1, 1.0, 0.9, 1.0], // Lax
    [0.9, 1.0, 1.0, 1.0, 1.1], // Timid
    [1.0, 0.9, 1.0, 1.0, 1.1], // Hasty
    [1.0, 1.0, 1.0, 1.0, 1.0], // Serious
    [1.0, 1.0, 0.9, 1.0, 1.1], // Jolly
    [1.0, 1.0, 1.0, 0.9, 1.1], // Naive
    [0.9, 1.0, 1.1, 1.0, 1.0], // Modest
    [1.0, 0.9, 1.1, 1.0, 1.0], // Mild
    [1.0, 1.0, 1.1, 1.0, 0.9], // Quiet
    [1.0, 1.0, 1.0, 1.0, 1.0], // Bashful
    [1.0, 1.0, 1.1, 0.9, 1.0], // Rash
    [0.9, 1.0, 1.0, 1.1, 1.0], // Calm
    [1.0, 0.9, 1.0, 1.1, 1.0], // Gentle
    [1.0, 1.0, 1.0, 1.1, 0.9], // Sassy
    [1.0, 1.0, 0.9, 1.1, 1.0], // Careful
    [1.0, 1.0, 1.0, 1.0, 1.0], // Quirky
]

/// Compute stat matching PokeFinder's Nature::computeStat
private func pfComputeStat(baseStat: UInt16, iv: UInt8, nature: UInt8, level: UInt8, index: UInt8) -> UInt16 {
    let stat = ((2 * UInt16(baseStat) + UInt16(iv)) * UInt16(level)) / 100
    if index == 0 { // HP
        return stat + UInt16(level) + 10
    } else {
        return UInt16(Float(stat + 5) * pfNatureModifiers[Int(nature)][Int(index) - 1])
    }
}

struct IVCalcResult: Identifiable {
    let id = UUID()
    let statName: String
    let possibleIVs: [UInt8]

    var displayRange: String {
        guard let first = possibleIVs.first, let last = possibleIVs.last else { return "?" }
        if first == last { return "\(first)" }
        return "\(first)-\(last)"
    }
}

/// Full IV range calculator matching PokeFinder's IVChecker::calculateIVRange
func pfCalculateIVRange(baseStats: [UInt8], stats: [[UInt16]], levels: [UInt8],
                         nature: UInt8, characteristic: UInt8 = 255, hiddenPower: UInt8 = 255) -> [IVCalcResult] {
    let statNames = ["HP", "Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed"]
    let ivOrder: [UInt8] = [0, 1, 2, 5, 3, 4]

    // Calculate IVs for each set of stats, then intersect
    var ivs: [[UInt8]] = Array(repeating: [], count: 6)

    for (si, statSet) in stats.enumerated() {
        var minIVs: [UInt8] = Array(repeating: 31, count: 6)
        var maxIVs: [UInt8] = Array(repeating: 0, count: 6)

        for i in 0..<6 {
            for iv: UInt8 in 0...31 {
                if nature != 255 {
                    let calc = pfComputeStat(baseStat: UInt16(baseStats[i]), iv: iv,
                                              nature: nature, level: levels[si], index: UInt8(i))
                    if calc == statSet[i] {
                        minIVs[i] = min(iv, minIVs[i])
                        maxIVs[i] = max(iv, maxIVs[i])
                    }
                } else {
                    // Unknown nature: check with Hardy (neutral) and also +/- 10%
                    let calc = pfComputeStat(baseStat: UInt16(baseStats[i]), iv: iv,
                                              nature: 0, level: levels[si], index: UInt8(i))
                    if calc == statSet[i] ||
                        (i != 0 && (UInt16(Float(calc) * 0.9) == statSet[i] || UInt16(Float(calc) * 1.1) == statSet[i])) {
                        minIVs[i] = min(iv, minIVs[i])
                        maxIVs[i] = max(iv, maxIVs[i])
                    }
                }
            }
        }

        // Build possible arrays with characteristic filtering
        var current: [[UInt8]] = Array(repeating: [], count: 6)
        var characteristicHigh: UInt8 = 31
        var charIndex: Int = -1

        if characteristic != 255 {
            charIndex = Int(ivOrder[Int(characteristic) / 5])
            let charResult = characteristic % 5

            for iv in minIVs[charIndex]...maxIVs[charIndex] {
                if (iv % 5) == charResult {
                    if minIVs.allSatisfy({ iv >= $0 }) {
                        current[charIndex].append(iv)
                        characteristicHigh = iv
                    }
                }
            }
        }

        for i in 0..<6 {
            if i == charIndex { continue }
            if minIVs[i] <= maxIVs[i] {
                for iv in minIVs[i]...min(maxIVs[i], characteristicHigh) {
                    current[i].append(iv)
                }
            }
        }

        if si == 0 {
            ivs = current
        } else {
            // Intersect
            for j in 0..<6 {
                let intersection = ivs[j].filter { current[j].contains($0) }
                ivs[j] = intersection
            }
        }
    }

    // Hidden power filtering
    if hiddenPower != 255 {
        var possible: [[UInt8]] = Array(repeating: [], count: 6)
        for i in 0..<6 {
            if ivs[i].contains(where: { $0 % 2 == 0 }) { possible[i].append(0) }
            if ivs[i].contains(where: { $0 % 2 == 1 }) { possible[i].append(1) }
        }

        var temp: [[UInt8]] = Array(repeating: [], count: 6)
        for hp in possible[0] {
            for atk in possible[1] {
                for def in possible[2] {
                    for spa in possible[3] {
                        for spd in possible[4] {
                            for spe in possible[5] {
                                let typeVal = (UInt8(hp) + 2 * atk + 4 * def + 16 * spa + 32 * spd + 8 * spe) * 15 / 63
                                if typeVal == hiddenPower {
                                    temp[0].append(contentsOf: ivs[0].filter { $0 % 2 == hp })
                                    temp[1].append(contentsOf: ivs[1].filter { $0 % 2 == atk })
                                    temp[2].append(contentsOf: ivs[2].filter { $0 % 2 == def })
                                    temp[3].append(contentsOf: ivs[3].filter { $0 % 2 == spa })
                                    temp[4].append(contentsOf: ivs[4].filter { $0 % 2 == spd })
                                    temp[5].append(contentsOf: ivs[5].filter { $0 % 2 == spe })
                                }
                            }
                        }
                    }
                }
            }
        }
        for i in 0..<6 {
            ivs[i] = Array(Set(temp[i])).sorted()
        }
    }

    return (0..<6).map { IVCalcResult(statName: statNames[$0], possibleIVs: ivs[$0]) }
}

// ============================================================================
// MARK: - Hidden Power Calculator
// ============================================================================

let hiddenPowerTypes = [
    "Fighting", "Flying", "Poison", "Ground", "Rock", "Bug",
    "Ghost", "Steel", "Fire", "Water", "Grass", "Electric",
    "Psychic", "Ice", "Dragon", "Dark"
]

func calculateHiddenPowerType(ivHP: Int, ivAtk: Int, ivDef: Int,
                               ivSpeed: Int, ivSpAtk: Int, ivSpDef: Int) -> String {
    let a = ivHP % 2
    let b = ivAtk % 2
    let c = ivDef % 2
    let d = ivSpeed % 2
    let e = ivSpAtk % 2
    let f = ivSpDef % 2
    let index = ((a + 2*b + 4*c + 8*d + 16*e + 32*f) * 15) / 63
    return hiddenPowerTypes[min(index, hiddenPowerTypes.count - 1)]
}

func calculateHiddenPowerBasePower(ivHP: Int, ivAtk: Int, ivDef: Int,
                                    ivSpeed: Int, ivSpAtk: Int, ivSpDef: Int) -> Int {
    let a = (ivHP / 2) % 2
    let b = (ivAtk / 2) % 2
    let c = (ivDef / 2) % 2
    let d = (ivSpeed / 2) % 2
    let e = (ivSpAtk / 2) % 2
    let f = (ivSpDef / 2) % 2
    return ((a + 2*b + 4*c + 8*d + 16*e + 32*f) * 40) / 63 + 30
}

// ============================================================================
// MARK: - Timer Engine
// ============================================================================

@Observable
final class RNGTimerEngine {
    var phases: [Int] = []
    var currentPhaseIndex: Int = 0
    var remainingMs: Int = 0
    var isRunning: Bool = false

    private var timer: Timer?
    private var phaseStartDate: Date?
    private var phaseTargetMs: Int = 0

    func start(phases: [Int]) {
        let finite = phases.filter { $0 != Int.max && $0 > 0 }
        guard !finite.isEmpty else { return }
        self.phases = phases
        currentPhaseIndex = 0
        isRunning = true
        beginPhase(index: 0)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        currentPhaseIndex = 0
        remainingMs = 0
    }

    private func beginPhase(index: Int) {
        guard index < phases.count else {
            playBeep(count: 3)
            stop()
            return
        }
        if phases[index] == Int.max {
            // Variable target: just stay on this phase, user stops manually
            currentPhaseIndex = index
            remainingMs = 0
            return
        }
        currentPhaseIndex = index
        phaseTargetMs = phases[index]
        remainingMs = phaseTargetMs
        phaseStartDate = Date()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let start = phaseStartDate else { return }
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        remainingMs = max(0, phaseTargetMs - elapsed)

        if remainingMs <= 0 {
            timer?.invalidate()
            playBeep(count: 1)
            beginPhase(index: currentPhaseIndex + 1)
        }
    }

    var totalPhases: Int { phases.count }
    var displaySeconds: Double { Double(remainingMs) / 1000.0 }
}

private func playBeep(count: Int) {
    for i in 0..<count {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
            AudioServicesPlaySystemSound(1057)
        }
    }
}

// ============================================================================
// MARK: - Root RNG Tools View
// ============================================================================

enum TimerGeneration: String, CaseIterable, Identifiable {
    case gen3 = "Gen 3"
    case gen4 = "Gen 4"
    case gen5 = "Gen 5"
    case custom = "Custom"
    var id: String { rawValue }
}

enum RNGToolTab: Int, CaseIterable, Identifiable {
    case timer = 0
    case finder = 5
    case encounters = 6
    case statics = 7
    case eggs = 8
    case ids = 9
    case gamecube = 10
    case ivCalc = 1
    case ivToPID = 2
    case hp = 3
    case credits = 4
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .timer: return "Timer"
        case .finder: return "Finder"
        case .encounters: return "Routes"
        case .statics: return "Statics"
        case .eggs: return "Eggs"
        case .ids: return "TID/SID"
        case .gamecube: return "GameCube"
        case .ivCalc: return "IV Calc"
        case .ivToPID: return "IV\u{2192}PID"
        case .hp: return "HP"
        case .credits: return "Credits"
        }
    }
}

struct RNGToolsView: View {
    @State private var selectedTool = 0

    var body: some View {
        TabNavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RNGToolTab.allCases) { tab in
                            Button {
                                selectedTool = tab.rawValue
                            } label: {
                                Text(tab.label)
                                    .font(.subheadline.weight(selectedTool == tab.rawValue ? .semibold : .regular))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedTool == tab.rawValue ? Color.accentColor : Color.clear,
                                                in: Capsule())
                                    .foregroundStyle(selectedTool == tab.rawValue ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.trailing, 20)
                    .padding(.top, 8)
                }
                .scrollIndicatorsFlash(onAppear: true)
                .mask {
                    HStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 28)
                    }
                }

                switch selectedTool {
                case 0: RNGTimerView()
                case 1: IVCalculatorView()
                case 2: IVToPIDView()
                case 3: HiddenPowerCalcView()
                case 5: FinderRootView(switchToTimer: { selectedTool = 0 })
                case 6: EncounterBrowserView()
                case 7: StaticEncounterBrowserView()
                case 8: EggRNGView()
                case 9: IDRNGView()
                case 10: GameCubeRNGView()
                default: RNGCreditsView()
                }
            }
            .cardPage()
            .navigationTitle("RNG Tools")
            #if DEBUG && os(macOS)
            // `-debugOpenSheet frlgCalibration`: the Finder, then a FireRed
            // Eevee target, then its first seed's Calibrate.
            .task { await DebugSnapshot.openSheet("frlgCalibration") { selectedTool = RNGToolTab.finder.rawValue } }
            #endif
            .onChange(of: FinderTimerBridge.shared.shouldSwitchToTimer) {
                if FinderTimerBridge.shared.shouldSwitchToTimer {
                    selectedTool = 0
                    FinderTimerBridge.shared.shouldSwitchToTimer = false
                }
            }
        }
    }
}

// ============================================================================
// MARK: - RNG Timer View
// ============================================================================

struct RNGTimerView: View {
    @State private var engine = RNGTimerEngine()
    @State private var generation: TimerGeneration = .gen5
    @State private var consoleType: RNGConsole = .ndsSlot1
    @State private var customFramerate: Double = 60.0
    @State private var precisionCalibration = false

    // Gen 3
    @State private var gen3Mode: Gen3TimerMode = .standard
    @State private var gen3PreTimer = 5000
    @State private var gen3TargetFrame = 1000
    @State private var gen3Calibration = 0
    @State private var gen3FrameHit = 0

    // Gen 4 (defaults from EonTimer store)
    @State private var gen4TargetDelay = 600
    @State private var gen4TargetSecond = 50
    @State private var gen4CalibratedDelay = 500
    @State private var gen4CalibratedSecond = 14
    @State private var gen4DelayHit = 0

    // Gen 5 (defaults from EonTimer store)
    @State private var gen5Mode: Gen5TimerMode = .standard
    @State private var gen5TargetDelay = 1200
    @State private var gen5TargetSecond = 50
    @State private var gen5TargetAdvances = 100
    @State private var gen5Calibration = -95
    @State private var gen5EntralinkCalibration = 256
    @State private var gen5FrameCalibration = 0
    @State private var gen5DelayHit: Int?
    @State private var gen5SecondHit: Int?
    @State private var gen5AdvancesHit: Int?

    // Finder reminder
    @State private var reminderText: String?

    // Custom
    @State private var customPhases: [CustomPhase] = [
        CustomPhase(unit: .milliseconds, target: 5000, calibration: 0)
    ]

    private var settings: CalibratorSettings {
        CalibratorSettings(console: consoleType, customFramerate: customFramerate,
                           precisionCalibration: precisionCalibration, minimumLength: EONTIMER_MINIMUM_LENGTH)
    }

    var body: some View {
        ScrollView {
            CardStack {
                timerDisplay

                if let reminderText {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text(reminderText)
                            .font(.callout)
                        Spacer()
                        Button {
                            self.reminderText = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Picker("Generation", selection: $generation) {
                    ForEach(TimerGeneration.allCases) { gen in
                        Text(gen.rawValue).tag(gen)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(engine.isRunning)

                // Console picker
                SectionCard(title: "Console", icon: "gamecontroller") {
                    Picker("Console", selection: $consoleType) {
                        ForEach(RNGConsole.allCases) { c in Text(c.rawValue).tag(c) }
                    }
                    if consoleType == .custom {
                        RNGDoubleField(label: "Framerate", value: $customFramerate)
                    }
                    Toggle("Precision Calibration", isOn: $precisionCalibration)
                }

                SectionCard(title: "Settings", icon: "gearshape") {
                    switch generation {
                    case .gen3: gen3Settings
                    case .gen4: gen4Settings
                    case .gen5: gen5Settings
                    case .custom: customSettings
                    }
                }

                if generation != .custom {
                    SectionCard(title: "Calibration", icon: "tuningfork") {
                        calibrationSection
                    }
                }

                Button {
                    if engine.isRunning {
                        engine.stop()
                    } else {
                        engine.start(phases: computePhases())
                    }
                } label: {
                    Label(engine.isRunning ? "Stop" : "Start Timer",
                          systemImage: engine.isRunning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.primaryAction)
                .tint(engine.isRunning ? .red : nil)
                .disabled(!engine.isRunning && computePhases().isEmpty)

                // Phase preview
                let phases = computePhases()
                if !phases.isEmpty && !engine.isRunning {
                    SectionCard(title: "Phase Preview", icon: "list.number") {
                        ForEach(Array(phases.enumerated()), id: \.offset) { i, ms in
                            HStack {
                                Text("Phase \(i + 1)")
                                Spacer()
                                if ms == Int.max {
                                    Text("Variable (manual stop)")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(String(format: "%.3fs", Double(ms) / 1000.0))
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            let bridge = FinderTimerBridge.shared
            if let gen = bridge.pendingGen {
                generation = gen
                if gen == .gen3, let frame = bridge.pendingTargetFrame {
                    gen3TargetFrame = frame
                }
                if gen == .gen3, let preTimer = bridge.pendingPreTimer {
                    gen3Mode = .standard
                    gen3PreTimer = preTimer
                }
                if gen == .gen3, let calibration = bridge.pendingCalibration {
                    gen3Calibration = calibration
                }
                if let console = bridge.pendingConsole {
                    consoleType = console
                }
                if gen == .gen4 {
                    if let delay = bridge.pendingTargetDelay {
                        gen4TargetDelay = delay
                    }
                    if let second = bridge.pendingTargetSecond {
                        gen4TargetSecond = second
                    }
                }
                if let time = bridge.selectedTime {
                    let seed = bridge.selectedSeed ?? "?"
                    reminderText = "Seed \(seed) — \(time)"
                }
                bridge.clear()
            }
        }
        .leaveWarning(engine.isRunning ? "The running timer will stop." : nil)
    }

    private var timerDisplay: some View {
        VStack(spacing: 8) {
            Text(String(format: "%.3f", engine.displaySeconds))
                .scaledFont(size: 64, weight: .bold, design: .monospaced, relativeTo: .largeTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(engine.isRunning ? .primary : .secondary)
                .contentTransition(.numericText())

            if engine.isRunning && engine.totalPhases > 1 {
                Text("Phase \(engine.currentPhaseIndex + 1) of \(engine.totalPhases)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .card()
    }

    // MARK: Gen Settings

    private var gen3Settings: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $gen3Mode) {
                ForEach(Gen3TimerMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            RNGIntField(label: "Pre-Timer (ms)", value: $gen3PreTimer)
            RNGIntField(label: "Target Frame", value: $gen3TargetFrame)
            RNGIntField(label: "Calibration (ms)", value: $gen3Calibration)
        }
    }

    private var gen4Settings: some View {
        VStack(spacing: 12) {
            RNGIntField(label: "Calibrated Delay", value: $gen4CalibratedDelay)
            RNGIntField(label: "Calibrated Second", value: $gen4CalibratedSecond)
            RNGIntField(label: "Target Delay", value: $gen4TargetDelay)
            RNGIntField(label: "Target Second", value: $gen4TargetSecond)
        }
    }

    private var gen5Settings: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $gen5Mode) {
                ForEach(Gen5TimerMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            RNGIntField(label: "Calibration", value: $gen5Calibration)
            if gen5Mode == .entralink || gen5Mode == .entralinkPlus {
                RNGIntField(label: "Entralink Cal.", value: $gen5EntralinkCalibration)
            }
            if gen5Mode == .entralinkPlus {
                RNGIntField(label: "Frame Cal.", value: $gen5FrameCalibration)
            }
            RNGIntField(label: "Target Delay", value: $gen5TargetDelay)
            RNGIntField(label: "Target Second", value: $gen5TargetSecond)
            if gen5Mode == .entralink || gen5Mode == .entralinkPlus {
                RNGIntField(label: "Target Advances", value: $gen5TargetAdvances)
            }
        }
    }

    private var customSettings: some View {
        VStack(spacing: 12) {
            ForEach(customPhases.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Text("Phase \(i + 1)").font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .scaledWidth(56, relativeTo: .caption, alignment: .leading)
                    TextField("Value", value: Binding(
                        get: { customPhases[i].target },
                        set: { customPhases[i].target = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder).scaledWidth(80)

                    Picker("", selection: Binding(
                        get: { customPhases[i].unit },
                        set: { customPhases[i].unit = $0 }
                    )) {
                        ForEach(CustomTimerUnit.allCases) { u in Text(u.rawValue).tag(u) }
                    }.scaledWidth(100)

                    TextField("Cal", value: Binding(
                        get: { customPhases[i].calibration },
                        set: { customPhases[i].calibration = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder).scaledWidth(60)

                    if customPhases.count > 1 {
                        Button { customPhases.remove(at: i) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button { customPhases.append(CustomPhase(unit: .milliseconds, target: 5000, calibration: 0)) }
                label: { Label("Add Phase", systemImage: "plus.circle") }
        }
    }

    // MARK: Calibration

    private var calibrationSection: some View {
        VStack(spacing: 12) {
            switch generation {
            case .gen3:
                Text("Enter the frame you hit to adjust calibration.")
                    .font(.caption).foregroundStyle(.secondary)
                RNGIntField(label: "Frame Hit", value: $gen3FrameHit)
                Button("Update Calibration") {
                    gen3Calibration += calibrateGen3(settings, targetFrame: gen3TargetFrame, frameHit: gen3FrameHit)
                }
            case .gen4:
                Text("Enter the delay you hit.")
                    .font(.caption).foregroundStyle(.secondary)
                RNGIntField(label: "Delay Hit", value: $gen4DelayHit)
                Button("Update Calibration") {
                    let delta = calibrateGen4(settings, targetDelay: gen4TargetDelay, delayHit: gen4DelayHit)
                    gen4CalibratedDelay += delta
                }
            case .gen5:
                Text("Enter what you hit to refine calibration.")
                    .font(.caption).foregroundStyle(.secondary)
                RNGOptIntField(label: "Delay Hit", value: $gen5DelayHit)
                RNGOptIntField(label: "Second Hit", value: $gen5SecondHit)
                if gen5Mode == .entralinkPlus {
                    RNGOptIntField(label: "Advances Hit", value: $gen5AdvancesHit)
                }
                Button("Update Calibration") {
                    let result = calibrateGen5(settings, mode: gen5Mode,
                        targetDelay: gen5TargetDelay, targetSecond: gen5TargetSecond,
                        targetAdvances: gen5TargetAdvances,
                        delayHit: gen5DelayHit, secondHit: gen5SecondHit, advancesHit: gen5AdvancesHit)
                    gen5Calibration += result.calibrationDelta
                    gen5EntralinkCalibration += result.entralinkCalibrationDelta
                    gen5FrameCalibration += Int(result.frameCalibrationDelta)
                    gen5DelayHit = nil
                    gen5SecondHit = nil
                    gen5AdvancesHit = nil
                }
            case .custom:
                EmptyView()
            }
        }
    }

    private func computePhases() -> [Int] {
        switch generation {
        case .gen3:
            return createGen3Phases(settings, mode: gen3Mode, preTimer: gen3PreTimer,
                                     targetFrame: gen3TargetFrame, calibration: gen3Calibration)
        case .gen4:
            return createGen4Phases(settings, targetDelay: gen4TargetDelay, targetSecond: gen4TargetSecond,
                                     calibratedDelay: gen4CalibratedDelay, calibratedSecond: gen4CalibratedSecond)
        case .gen5:
            return createGen5Phases(settings, mode: gen5Mode,
                                     targetDelay: gen5TargetDelay, targetSecond: gen5TargetSecond,
                                     targetAdvances: gen5TargetAdvances, calibration: gen5Calibration,
                                     entralinkCalibration: gen5EntralinkCalibration, frameCalibration: gen5FrameCalibration)
        case .custom:
            return createCustomPhases(settings, phases: customPhases)
        }
    }
}

// ============================================================================
// MARK: - IV Calculator View
// ============================================================================

struct IVCalculatorView: View {
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @State private var searchText = ""
    @State private var selectedPokemon: PKMNStats?
    @State private var level: UInt8 = 50
    @State private var natureIndex: UInt8 = 3 // Adamant

    @State private var evHP = 0; @State private var evAtk = 0; @State private var evDef = 0
    @State private var evSpAtk = 0; @State private var evSpDef = 0; @State private var evSpeed = 0

    @State private var statHP: UInt16 = 0; @State private var statAtk: UInt16 = 0
    @State private var statDef: UInt16 = 0; @State private var statSpAtk: UInt16 = 0
    @State private var statSpDef: UInt16 = 0; @State private var statSpeed: UInt16 = 0

    @State private var results: [IVCalcResult] = []

    private var filteredPokemon: [PKMNStats] {
        let t = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return [] }
        return Array(allPokemon.filter { $0.name.lowercased().contains(t) }.prefix(20))
    }

    var body: some View {
        ScrollView {
            CardStack {
                if allPokemon.isEmpty {
                    ContentUnavailableView("Syncing Data", systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Waiting for Pokemon data to sync..."))
                } else {
                    pokemonSelector
                    if selectedPokemon != nil {
                        configSection
                        statEntrySection
                        calculateButton
                        resultsSection
                    }
                }
            }.padding()
        }
    }

    private var pokemonSelector: some View {
        SectionCard(title: "Pokemon", icon: "sparkles") {
            VStack(spacing: 8) {
                TextField("Search Pokemon...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { selectedPokemon = nil; results = [] }

                if !filteredPokemon.isEmpty && selectedPokemon == nil {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredPokemon, id: \.id) { pkmn in
                                Button {
                                    selectedPokemon = pkmn
                                    searchText = pkmn.name
                                    results = []
                                } label: {
                                    Text(pkmn.name).frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4).padding(.horizontal, 8)
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(maxHeight: 200)
                }

                if let pkmn = selectedPokemon {
                    HStack(spacing: 12) {
                        baseStatPill("HP", pkmn.baseHP)
                        baseStatPill("Atk", pkmn.baseAtk)
                        baseStatPill("Def", pkmn.baseDef)
                        baseStatPill("SpA", pkmn.baseSpAtk)
                        baseStatPill("SpD", pkmn.baseSpDef)
                        baseStatPill("Spe", pkmn.baseSpeed)
                    }.font(.caption)

                    Button("Clear") { selectedPokemon = nil; searchText = ""; results = [] }.font(.caption)
                }
            }
        }
    }

    private func baseStatPill(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text("\(value)").bold()
        }.frame(maxWidth: .infinity)
    }

    private var configSection: some View {
        SectionCard(title: "Config", icon: "slider.horizontal.3") {
            HStack {
                Text("Level")
                Spacer()
                TextField("Lv", value: $level, format: .number)
                    .textFieldStyle(.roundedBorder).scaledWidth(60)
            }
            Picker("Nature", selection: $natureIndex) {
                ForEach(Array(allNatures.enumerated()), id: \.element.id) { i, n in
                    Text("\(n.name) \(n.summary)").tag(UInt8(i))
                }
            }
        }
    }

    private var statEntrySection: some View {
        SectionCard(title: "Stats (from in-game summary)", icon: "number") {
            VStack(spacing: 8) {
                IVCalcRow16(label: "HP", stat: $statHP, ev: $evHP)
                IVCalcRow16(label: "Attack", stat: $statAtk, ev: $evAtk)
                IVCalcRow16(label: "Defense", stat: $statDef, ev: $evDef)
                IVCalcRow16(label: "Sp. Atk", stat: $statSpAtk, ev: $evSpAtk)
                IVCalcRow16(label: "Sp. Def", stat: $statSpDef, ev: $evSpDef)
                IVCalcRow16(label: "Speed", stat: $statSpeed, ev: $evSpeed)
            }
        }
    }

    private var calculateButton: some View {
        Button {
            guard let pkmn = selectedPokemon else { return }
            // PokeFinder's formula uses base stats without EVs in the stat formula
            // Our stats already include EVs from in-game, so pass them as-is
            let baseStats: [UInt8] = [UInt8(pkmn.baseHP), UInt8(pkmn.baseAtk), UInt8(pkmn.baseDef),
                                       UInt8(pkmn.baseSpAtk), UInt8(pkmn.baseSpDef), UInt8(pkmn.baseSpeed)]
            let stats: [[UInt16]] = [[statHP, statAtk, statDef, statSpAtk, statSpDef, statSpeed]]
            results = pfCalculateIVRange(baseStats: baseStats, stats: stats, levels: [level], nature: natureIndex)
        } label: {
            Label("Calculate IVs", systemImage: "function")
        }
        .buttonStyle(.primaryAction)
    }

    private var resultsSection: some View {
        Group {
            if !results.isEmpty {
                SectionCard(title: "Results", icon: "checkmark.circle") {
                    ForEach(results) { r in
                        HStack {
                            Text(r.statName).lineLimit(1).scaledWidth(80, alignment: .leading)
                            Spacer()
                            if r.possibleIVs.isEmpty {
                                Text("Invalid").foregroundStyle(.red).bold()
                            } else {
                                Text(r.displayRange)
                                    .font(.system(.body, design: .monospaced)).bold()
                                    .foregroundStyle(ivColor(r.possibleIVs))
                            }
                        }
                    }
                }
            }
        }
    }

    private func ivColor(_ ivs: [UInt8]) -> Color {
        guard let best = ivs.last else { return .primary }
        if best == 31 { return .green }
        if best == 0 { return .red }
        if best >= 28 { return .blue }
        return .primary
    }
}

// ============================================================================
// MARK: - IV to PID View (PokeFinder feature)
// ============================================================================

struct IVToPIDView: View {
    @State private var hp: UInt8 = 31
    @State private var atk: UInt8 = 31
    @State private var def: UInt8 = 31
    @State private var spa: UInt8 = 31
    @State private var spd: UInt8 = 31
    @State private var spe: UInt8 = 31
    @State private var nature: UInt8 = 0
    @State private var tid: UInt16 = 0
    @State private var results: [LCRNGReverse.IVToPIDResult] = []

    var body: some View {
        ScrollView {
            CardStack {
                SectionCard(title: "IVs", icon: "number.square") {
                    IVSliderRow8(label: "HP", value: $hp)
                    IVSliderRow8(label: "Attack", value: $atk)
                    IVSliderRow8(label: "Defense", value: $def)
                    IVSliderRow8(label: "Sp. Atk", value: $spa)
                    IVSliderRow8(label: "Sp. Def", value: $spd)
                    IVSliderRow8(label: "Speed", value: $spe)
                }

                SectionCard(title: "Trainer Info", icon: "person") {
                    HStack {
                        Text("Nature (0-24)")
                        Spacer()
                        TextField("", value: $nature, format: .number)
                            .textFieldStyle(.roundedBorder).scaledWidth(60)
                    }
                    HStack {
                        Text("Trainer ID")
                        Spacer()
                        TextField("", value: $tid, format: .number)
                            .textFieldStyle(.roundedBorder).scaledWidth(80)
                    }
                }

                Button {
                    results = LCRNGReverse.calculatePIDs(hp: hp, atk: atk, def: def,
                                                          spa: spa, spd: spd, spe: spe,
                                                          nature: nature, tid: tid)
                } label: {
                    Label("Find PIDs", systemImage: "magnifyingglass")
                }
                .buttonStyle(.primaryAction)

                if !results.isEmpty {
                    SectionCard(title: "Results (\(results.count))", icon: "list.bullet") {
                        ForEach(results) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(r.methodName).font(.caption).bold()
                                    Spacer()
                                    Text("PID: \(String(format: "%08X", r.pid))")
                                        .font(.system(.caption, design: .monospaced))
                                }
                                HStack {
                                    Text("Seed: \(String(format: "%08X", r.seed))")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(verbatim: "SID: \(r.sid)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Divider()
                        }
                    }
                } else if !results.isEmpty {
                    Text("No results found").foregroundStyle(.secondary)
                }
            }.padding()
        }
    }
}

// ============================================================================
// MARK: - Hidden Power Calculator View
// ============================================================================

struct HiddenPowerCalcView: View {
    @State private var ivHP = 31; @State private var ivAtk = 31; @State private var ivDef = 31
    @State private var ivSpAtk = 31; @State private var ivSpDef = 31; @State private var ivSpeed = 31

    private var hpType: String {
        calculateHiddenPowerType(ivHP: ivHP, ivAtk: ivAtk, ivDef: ivDef,
                                  ivSpeed: ivSpeed, ivSpAtk: ivSpAtk, ivSpDef: ivSpDef)
    }
    private var hpPower: Int {
        calculateHiddenPowerBasePower(ivHP: ivHP, ivAtk: ivAtk, ivDef: ivDef,
                                      ivSpeed: ivSpeed, ivSpAtk: ivSpAtk, ivSpDef: ivSpDef)
    }

    var body: some View {
        ScrollView {
            CardStack {
                SectionCard(title: "IVs", icon: "number.square") {
                    IVSliderRow(label: "HP", value: $ivHP)
                    IVSliderRow(label: "Attack", value: $ivAtk)
                    IVSliderRow(label: "Defense", value: $ivDef)
                    IVSliderRow(label: "Sp. Atk", value: $ivSpAtk)
                    IVSliderRow(label: "Sp. Def", value: $ivSpDef)
                    IVSliderRow(label: "Speed", value: $ivSpeed)
                }

                SectionCard(title: "Hidden Power", icon: "questionmark.diamond") {
                    HStack {
                        Text("Type"); Spacer()
                        Text(hpType).bold().padding(.horizontal, 12).padding(.vertical, 4)
                            .background(TypePalette.fill(for: hpType).opacity(0.2)).clipShape(Capsule())
                    }
                    HStack {
                        Text("Base Power (Gen V-VI)"); Spacer()
                        Text("\(hpPower)").bold().font(.system(.body, design: .monospaced))
                    }
                    Text("Note: In Gen VII+, Hidden Power always has 60 base power.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                SectionCard(title: "Common Hidden Power IVs", icon: "table") {
                    VStack(spacing: 6) {
                        hpPreset("Fire", ivs: "31/30/31/30/31/30")
                        hpPreset("Ice", ivs: "31/30/30/31/31/31")
                        hpPreset("Grass", ivs: "31/30/31/30/31/30")
                        hpPreset("Electric", ivs: "31/31/31/30/31/31")
                        hpPreset("Ground", ivs: "31/31/31/30/30/31")
                        hpPreset("Fighting", ivs: "31/31/30/30/30/30")
                        hpPreset("Flying", ivs: "30/30/30/30/30/31")
                    }
                }
            }.padding()
        }
    }

    private func hpPreset(_ type: String, ivs: String) -> some View {
        HStack {
            TypeBadge(type: type).scaledWidth(80, relativeTo: .caption2, alignment: .leading)
            Spacer()
            Text(ivs).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}

// ============================================================================
// MARK: - Finder Root View
// ============================================================================

struct FinderRootView: View {
    var switchToTimer: () -> Void

    @AppStorage("finder_generation") private var generation: FinderGeneration = .gen3
    @AppStorage("finder_mode") private var mode: FinderMode = .searcher
    @AppStorage("finder_method") private var method: FinderMethod = .method1
    @AppStorage("finder_lead") private var lead: FinderLead = .none
    @State private var syncNature: UInt8 = 0

    // Profile
    @AppStorage("finder_tid") private var tid: UInt16 = 0
    @AppStorage("finder_sid") private var sid: UInt16 = 0
    @State private var savedProfiles: [FinderProfile] = FinderProfileStore.load()
    @State private var selectedProfileID: UUID? = FinderProfileStore.lastProfileID
    @State private var showSaveAlert = false
    @State private var newProfileName = ""

    // Encounter
    @AppStorage("finder_game") private var selectedGame: FinderGameVersion = .emerald
    @AppStorage("finder_encounterMode") private var encounterMode: EncounterMode = .static_
    @AppStorage("finder_encounterCategory") private var encounterCategory: StaticEncounterCategory = .legends
    @State private var selectedEncounter: StaticEncounter?
    @AppStorage("finder_selectedLocation") private var selectedLocation: String = ""
    @AppStorage("finder_encounterType") private var selectedEncounterType: EncounterType = .grass
    @AppStorage("finder_speciesFilter") private var selectedSpeciesFilter: UInt16 = 0

    enum EncounterMode: String, CaseIterable, Identifiable {
        case static_ = "Static"
        case wild = "Wild"
        case egg = "Egg"
        case raid = "Raid"
        case underground = "Underground"
        case id = "TID/SID"
        var id: String { rawValue }

        static func modes(for generation: FinderGeneration, game: FinderGameVersion) -> [EncounterMode] {
            switch generation {
            case .gen3, .gen4, .gen5:
                return [.static_, .wild]
            case .gen8:
                var modes: [EncounterMode] = [.static_, .wild, .egg, .id]
                if game.isSwSh { modes.insert(.raid, at: 3) }
                if game.isBDSP { modes.insert(.underground, at: 3) }
                return modes
            }
        }
    }

    // Searcher IV ranges
    @AppStorage("finder_minHP") private var minHP: UInt8 = 0
    @AppStorage("finder_maxHP") private var maxHP: UInt8 = 31
    @AppStorage("finder_minAtk") private var minAtk: UInt8 = 0
    @AppStorage("finder_maxAtk") private var maxAtk: UInt8 = 31
    @AppStorage("finder_minDef") private var minDef: UInt8 = 0
    @AppStorage("finder_maxDef") private var maxDef: UInt8 = 31
    @AppStorage("finder_minSpA") private var minSpA: UInt8 = 0
    @AppStorage("finder_maxSpA") private var maxSpA: UInt8 = 31
    @AppStorage("finder_minSpD") private var minSpD: UInt8 = 0
    @AppStorage("finder_maxSpD") private var maxSpD: UInt8 = 31
    @AppStorage("finder_minSpe") private var minSpe: UInt8 = 0
    @AppStorage("finder_maxSpe") private var maxSpe: UInt8 = 31

    // Gen 4 delay/advance range (searcher)
    @AppStorage("finder_minDelay") private var minDelay: UInt16 = 500
    @AppStorage("finder_maxDelay") private var maxDelay: UInt16 = 10000
    @AppStorage("finder_searcherMinAdvance") private var searcherMinAdvance: Int = 0
    @AppStorage("finder_searcherMaxAdvance") private var searcherMaxAdvance: Int = 100

    // Generator inputs
    @AppStorage("finder_genSeed") private var genSeedText: String = ""
    @AppStorage("finder_genInitAdvance") private var genInitAdvance: Int = 0
    @AppStorage("finder_genMaxAdvance") private var genMaxAdvance: Int = 10000

    // Filters
    @AppStorage("finder_natures") private var selectedNatures: Set<UInt8> = []
    @AppStorage("finder_shinyOnly") private var shinyOnly: Bool = false
    @AppStorage("finder_filterGender") private var filterGender: UInt8 = 255
    @AppStorage("finder_filterAbility") private var filterAbility: UInt8 = 255
    @AppStorage("finder_hiddenPowers") private var selectedHiddenPowers: Set<UInt8> = []
    @AppStorage("finder_deadBattery") private var deadBattery: Bool = true

    // Gen 5 DS parameters
    @AppStorage("finder_gen5mac") private var gen5MacText: String = ""
    @AppStorage("finder_gen5timer0Min") private var gen5Timer0Min: Int = 0
    @AppStorage("finder_gen5timer0Max") private var gen5Timer0Max: Int = 0
    @AppStorage("finder_gen5vcount") private var gen5VCount: Int = 0
    @AppStorage("finder_gen5gxstat") private var gen5GxStat: Int = 0
    @AppStorage("finder_gen5vframe") private var gen5VFrame: Int = 0
    @AppStorage("finder_gen5skipLR") private var gen5SkipLR: Bool = false
    @AppStorage("finder_gen5dsType") private var gen5DSType: UInt8 = 0
    @AppStorage("finder_gen5language") private var gen5Language: UInt8 = 0
    @AppStorage("finder_gen5memoryLink") private var gen5MemoryLink: Bool = false
    @AppStorage("finder_gen5shinyCharm") private var gen5ShinyCharm: Bool = false
    @AppStorage("finder_gen5season") private var gen5Season: UInt8 = 0
    @State private var gen5Keypresses: [Bool] = [true, false, false, false, false, false, false, false, false]

    // Gen 5 searcher date range
    @State private var gen5StartDate: Date = {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1
        return Calendar.current.date(from: c) ?? Date()
    }()
    @State private var gen5EndDate: Date = {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 2
        return Calendar.current.date(from: c) ?? Date()
    }()
    @State private var gen5IVMinAdvance: Int = 0
    @State private var gen5IVMaxAdvance: Int = 30
    @State private var gen5SearchHandle: OpaquePointer? = nil

    // Gen 8 parameters
    @AppStorage("finder_gen8seed1") private var gen8Seed1Text: String = ""
    @AppStorage("finder_gen8shinyCharm") private var gen8ShinyCharm: Bool = false
    @AppStorage("finder_gen8ovalCharm") private var gen8OvalCharm: Bool = false

    // Gen 8 Egg parameters
    @State private var gen8EggParentAIVs: [UInt8] = [31, 31, 31, 31, 31, 31]
    @State private var gen8EggParentBIVs: [UInt8] = [31, 31, 31, 31, 31, 31]
    @AppStorage("finder_gen8parentAAbility") private var gen8ParentAAbility: UInt8 = 0
    @AppStorage("finder_gen8parentBAbility") private var gen8ParentBAbility: UInt8 = 0
    @AppStorage("finder_gen8parentAGender") private var gen8ParentAGender: UInt8 = 0
    @AppStorage("finder_gen8parentBGender") private var gen8ParentBGender: UInt8 = 1
    @AppStorage("finder_gen8parentAItem") private var gen8ParentAItem: UInt8 = 0
    @AppStorage("finder_gen8parentBItem") private var gen8ParentBItem: UInt8 = 0
    @AppStorage("finder_gen8parentANature") private var gen8ParentANature: UInt8 = 0
    @AppStorage("finder_gen8parentBNature") private var gen8ParentBNature: UInt8 = 0
    @AppStorage("finder_gen8compatibility") private var gen8Compatibility: UInt8 = 20
    @AppStorage("finder_gen8masuda") private var gen8Masuda: Bool = false
    @AppStorage("finder_gen8eggSpecie") private var gen8EggSpecie: UInt16 = 1

    // Gen 8 Raid parameters
    @AppStorage("finder_gen8raidDen") private var gen8RaidDen: UInt16 = 0
    @AppStorage("finder_gen8raidRarity") private var gen8RaidRarity: UInt8 = 0
    @AppStorage("finder_gen8raidIndex") private var gen8RaidIndex: UInt8 = 0
    @AppStorage("finder_gen8raidLevel") private var gen8RaidLevel: UInt8 = 60

    // Gen 8 Underground parameters (BDSP)
    @AppStorage("finder_gen8diglett") private var gen8Diglett: Bool = false
    @AppStorage("finder_gen8storyFlag") private var gen8StoryFlag: Int = 0

    // Gen 8 ID filter parameters
    @AppStorage("finder_gen8filterTID") private var gen8FilterTIDText: String = ""
    @AppStorage("finder_gen8filterSID") private var gen8FilterSIDText: String = ""
    @AppStorage("finder_gen8filterDisplayTID") private var gen8FilterDisplayTIDText: String = ""

    // Coin flip search (Gen 4)
    @State private var flipInput: [Bool] = []
    @State private var flipSearchResults: [(seed: UInt32, flips: String)] = []
    @State private var flipSearching = false
    @State private var flipSearchRange: Int = 200

    // Call search (Elm/Irwin, Gen 4)
    @State private var callInput: [UInt8] = []
    @State private var callSearchResults: [(seed: UInt32, calls: String)] = []
    @State private var callSearching = false
    @State private var callSearchRange: Int = 200
    @State private var roamerCount: UInt8 = 0

    /// FireRed and LeafGreen initial seeds.
    @State private var frlg = FRLGSeedSearch()
    @State private var frlgMatches = FRLGMatchCache()

    // State — separate results for searcher and generator
    @State private var searcherResults: [StaticSearchResult] = []
    @State private var generatorResults: [StaticSearchResult] = []
    private var activeResults: [StaticSearchResult] {
        mode == .searcher ? searcherResults : generatorResults
    }
    @State private var searchTask: Task<Void, Never>?
    @State private var searchWorkTask: Task<Void, Never>?
    @State private var searchProgressValue: Double = -1
    private var isSearching: Bool { searchTask != nil }
    @State private var selectedResult: StaticSearchResult?

    enum FinderMode: String, CaseIterable, Identifiable {
        case searcher = "Searcher"
        case generator = "Generator"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            CardStack {
                // Generation picker
                Picker("Generation", selection: $generation) {
                    ForEach(FinderGeneration.allCases) { g in Text(g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: generation) {
                    let games = FinderGameVersion.games(for: generation)
                    if !games.contains(selectedGame) { selectedGame = games[0] }
                    let cats = StaticEncounterData.categories(for: selectedGame)
                    if !cats.contains(encounterCategory) { encounterCategory = cats.first ?? .legends }
                    selectedEncounter = nil
                    autoSelectMethod()
                    if generation == .gen8 { mode = .generator }
                }

                if generation != .gen8 {
                    Picker("Mode", selection: $mode) {
                        ForEach(FinderMode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Encounter
                SectionCard(title: "Encounter", icon: "sparkles") {
                    Picker("Game", selection: $selectedGame) {
                        ForEach(FinderGameVersion.games(for: generation)) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                    .onChange(of: selectedGame) {
                        let cats = StaticEncounterData.categories(for: selectedGame)
                        if !cats.contains(encounterCategory) {
                            encounterCategory = cats.first ?? .legends
                        }
                        selectedEncounter = nil
                        let locs = PFEncounterDataProvider.locationNames(for: selectedGame)
                        if !locs.contains(selectedLocation) {
                            selectedLocation = locs.first ?? ""
                        }
                        autoSelectMethod()
                    }

                    let availableModes = EncounterMode.modes(for: generation, game: selectedGame)
                    Picker("Type", selection: $encounterMode) {
                        ForEach(availableModes) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: encounterMode) { autoSelectMethod() }
                    .onChange(of: generation) {
                        let modes = EncounterMode.modes(for: generation, game: selectedGame)
                        if !modes.contains(encounterMode) { encounterMode = modes[0] }
                    }
                    .onChange(of: selectedGame) {
                        let modes = EncounterMode.modes(for: generation, game: selectedGame)
                        if !modes.contains(encounterMode) { encounterMode = modes[0] }
                    }

                    if encounterMode == .static_ {
                        let categories = StaticEncounterData.categories(for: selectedGame)
                        if !categories.isEmpty {
                            Picker("Category", selection: $encounterCategory) {
                                ForEach(categories) { cat in
                                    Text(cat.rawValue).tag(cat)
                                }
                            }
                            .onChange(of: encounterCategory) {
                                selectedEncounter = nil
                            }

                            let encounters = StaticEncounterData.encounters(for: selectedGame, category: encounterCategory)
                            if !encounters.isEmpty {
                                Picker("Pokemon", selection: $selectedEncounter) {
                                    Text("None").tag(StaticEncounter?.none)
                                    ForEach(encounters) { e in
                                        Text("\(e.speciesName) Lv\(e.level)").tag(StaticEncounter?.some(e))
                                    }
                                }
                            }
                        }

                        if let enc = selectedEncounter {
                            encounterInfoCard(name: enc.speciesName, level: enc.level,
                                              game: selectedGame.rawValue, method: enc.method.rawValue)
                        }
                    } else if encounterMode == .wild {
                        let locations = PFEncounterDataProvider.locationNames(for: selectedGame)
                        if !locations.isEmpty {
                            Picker("Location", selection: $selectedLocation) {
                                ForEach(locations, id: \.self) { loc in
                                    Text(loc).tag(loc)
                                }
                            }
                            .onAppear {
                                if selectedLocation.isEmpty {
                                    selectedLocation = locations.first ?? ""
                                }
                            }

                            let types = PFEncounterDataProvider.encounterTypes(for: selectedGame, location: selectedLocation)
                            if !types.isEmpty {
                                Picker("Encounter", selection: $selectedEncounterType) {
                                    ForEach(types) { t in
                                        Text(t.rawValue).tag(t)
                                    }
                                }
                                .onChange(of: selectedLocation) {
                                    let available = PFEncounterDataProvider.encounterTypes(for: selectedGame, location: selectedLocation)
                                    if !available.contains(selectedEncounterType) {
                                        selectedEncounterType = available.first ?? .grass
                                    }
                                }
                            }

                            if let route = PFEncounterDataProvider.wildEncounter(for: selectedGame, location: selectedLocation, type: selectedEncounterType) {
                                let uniqueSpecies = route.slots.reduce(into: [(UInt16, String)]()) { result, slot in
                                    if !result.contains(where: { $0.0 == slot.species }) {
                                        result.append((slot.species, slot.speciesName))
                                    }
                                }

                                Picker("Pokemon", selection: $selectedSpeciesFilter) {
                                    Text("Any").tag(UInt16(0))
                                    ForEach(uniqueSpecies, id: \.0) { species, name in
                                        Text(name).tag(species)
                                    }
                                }
                                .onChange(of: selectedLocation) { selectedSpeciesFilter = 0 }
                                .onChange(of: selectedEncounterType) { selectedSpeciesFilter = 0 }

                                wildSlotTable(route: route)
                            }
                        } else {
                            Text("No wild data for \(selectedGame.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if encounterMode == .egg {
                        gen8EggParametersView
                    } else if encounterMode == .raid {
                        gen8RaidParametersView
                    } else if encounterMode == .underground {
                        gen8UndergroundParametersView
                    } else if encounterMode == .id {
                        gen8IDParametersView
                    }
                }

                // Profile
                SectionCard(title: "Trainer", icon: "person") {
                    if !savedProfiles.isEmpty {
                        Picker("Profile", selection: $selectedProfileID) {
                            Text("None").tag(UUID?.none)
                            ForEach(savedProfiles) { p in
                                Text(p.displayName).tag(UUID?.some(p.id))
                            }
                        }
                        .onChange(of: selectedProfileID) {
                            if let pid = selectedProfileID,
                               let profile = savedProfiles.first(where: { $0.id == pid }) {
                                tid = profile.tid
                                sid = profile.sid
                                deadBattery = profile.deadBattery
                                if let gv = profile.gameVersion,
                                   let game = FinderGameVersion(rawValue: gv) {
                                    selectedGame = game
                                }
                            }
                            FinderProfileStore.lastProfileID = selectedProfileID
                        }
                    }

                    FinderUInt16Field(label: "TID", value: $tid)
                    FinderUInt16Field(label: "SID", value: $sid)

                    HStack {
                        Button {
                            newProfileName = ""
                            showSaveAlert = true
                        } label: {
                            Label("Save Profile", systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderless)

                        Spacer()

                        if let pid = selectedProfileID,
                           savedProfiles.contains(where: { $0.id == pid }) {
                            Button(role: .destructive) {
                                savedProfiles.removeAll { $0.id == pid }
                                selectedProfileID = nil
                                FinderProfileStore.save(savedProfiles)
                                FinderProfileStore.lastProfileID = nil
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                // Gen 5 DS Parameters
                if generation == .gen5 {
                    SectionCard(title: "DS Parameters", icon: "wifi") {
                        HStack {
                            Text("MAC Address")
                            Spacer()
                            TextField("e.g. 0009BF123456", text: $gen5MacText)
                                .textFieldStyle(.roundedBorder)
                                .scaledWidth(160)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.characters)
                                #endif
                        }
                        RNGIntField(label: "Timer0 Min", value: $gen5Timer0Min, range: RNGFieldRange.word)
                        RNGIntField(label: "Timer0 Max", value: $gen5Timer0Max, range: RNGFieldRange.word)
                        RNGIntField(label: "VCount", value: $gen5VCount, range: RNGFieldRange.byte)
                        RNGIntField(label: "GxStat", value: $gen5GxStat, range: RNGFieldRange.byte)
                        RNGIntField(label: "VFrame", value: $gen5VFrame, range: RNGFieldRange.byte)

                        Picker("DS Type", selection: $gen5DSType) {
                            Text("DS Lite").tag(UInt8(0))
                            Text("DSi").tag(UInt8(1))
                            Text("3DS").tag(UInt8(2))
                        }

                        Picker("Language", selection: $gen5Language) {
                            Text("English").tag(UInt8(0))
                            Text("French").tag(UInt8(1))
                            Text("German").tag(UInt8(2))
                            Text("Italian").tag(UInt8(3))
                            Text("Japanese").tag(UInt8(4))
                            Text("Korean").tag(UInt8(5))
                            Text("Spanish").tag(UInt8(6))
                        }

                        Picker("Season", selection: $gen5Season) {
                            Text("Spring").tag(UInt8(0))
                            Text("Summer").tag(UInt8(1))
                            Text("Autumn").tag(UInt8(2))
                            Text("Winter").tag(UInt8(3))
                        }

                        Toggle("Skip L/R", isOn: $gen5SkipLR)
                        Toggle("Memory Link", isOn: $gen5MemoryLink)
                        if selectedGame == .black2 || selectedGame == .white2 {
                            Toggle("Shiny Charm", isOn: $gen5ShinyCharm)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Keypresses").font(.subheadline).foregroundStyle(.secondary)
                            let labels = ["None", "1 Button", "2 Buttons", "3 Buttons",
                                          "4 Buttons", "5 Buttons", "6 Buttons", "7 Buttons", "8 Buttons"]
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 4) {
                                ForEach(0..<9, id: \.self) { i in
                                    Toggle(labels[i], isOn: $gen5Keypresses[i])
                                        .toggleStyle(.button)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }

                // Gen 8 Parameters
                if generation == .gen8 {
                    SectionCard(title: "Gen 8 Options", icon: "sparkles") {
                        Toggle("Shiny Charm", isOn: $gen8ShinyCharm)
                        if encounterMode == .egg {
                            Toggle("Oval Charm", isOn: $gen8OvalCharm)
                        }
                    }
                }

                // Method (hidden for ID mode)
                if encounterMode != .id {
                    SectionCard(title: "Method", icon: "cpu") {
                    Picker("Method", selection: $method) {
                        ForEach(FinderMethod.methods(for: generation)) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .onChange(of: generation) {
                        let available = FinderLead.leads(for: generation, encounterMode: encounterMode == .wild)
                        if !available.contains(lead) { lead = .none }
                    }
                    .onChange(of: encounterMode) {
                        let available = FinderLead.leads(for: generation, encounterMode: encounterMode == .wild)
                        if !available.contains(lead) { lead = .none }
                    }

                    // PokéFinder's Gen 3 static generator and searcher take no
                    // lead.
                    if leadApplies {
                        Picker("Lead Ability", selection: $lead) {
                            ForEach(FinderLead.leads(for: generation, encounterMode: encounterMode == .wild)) { l in
                                Text(l.rawValue).tag(l)
                            }
                        }
                    }

                    if leadApplies, lead == .synchronize {
                        if searchesAnySyncNature {
                            Text("Searches every Synchronize nature: choose the natures you want under Nature Filter.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Picker("Sync Nature", selection: $syncNature) {
                                ForEach(0..<25, id: \.self) { i in
                                    Text(pfNatureNames[i]).tag(UInt8(i))
                                }
                            }
                        }
                    }

                    if generation == .gen3 && (selectedGame == .emerald || selectedGame == .ruby || selectedGame == .sapphire) {
                        Toggle("Dead Battery", isOn: $deadBattery)
                            .font(.subheadline)
                    }
                    }
                }

                if mode == .searcher {
                    searcherInputs
                } else {
                    generatorInputs
                }

                if generation == .gen4 && mode == .generator {
                    seedVerificationSection
                    coinFlipSearchSection
                    callSearchSection
                }

                if encounterMode != .id {
                    // Nature filter
                    FinderNatureGrid(selected: $selectedNatures)

                    // Additional filters
                    SectionCard(title: "Filters", icon: "line.3.horizontal.decrease.circle") {
                        Toggle("Shiny Only", isOn: $shinyOnly)

                        Picker("Gender", selection: $filterGender) {
                            Text("Any").tag(UInt8(255))
                            Text("Male").tag(UInt8(0))
                            Text("Female").tag(UInt8(1))
                            Text("Genderless").tag(UInt8(2))
                        }
                        if generation == .gen3, encounterMode == .static_, selectedEncounter == nil,
                           filterGender == 0 || filterGender == 1 {
                            Text("Gender comes from the Pokémon: choose it under Encounter, or every result is genderless.")
                                .font(.caption).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Picker("Ability", selection: $filterAbility) {
                            Text("Any").tag(UInt8(255))
                            Text("Ability 0").tag(UInt8(0))
                            Text("Ability 1").tag(UInt8(1))
                        }

                        FinderHiddenPowerGrid(selected: $selectedHiddenPowers)
                    }
                }

                if frlgApplies {
                    FRLGInitialSeedSection(search: frlg, fireRed: selectedGame == .fireRed)
                }

                // Search / Stop button
                if isSearching {
                    VStack(spacing: 8) {
                        if searchProgressValue < 0 {
                            ProgressView()
                                .padding(.vertical, 4)
                        } else {
                            ProgressView(value: searchProgressValue, total: 100)
                                .progressViewStyle(.linear)
                                .padding(.horizontal)
                            Text("\(Int(searchProgressValue))% — \(activeResults.count) found")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button {
                            stopSearch()
                        } label: {
                            Label("Stop",
                                  systemImage: "stop.fill")
                        }
                        .buttonStyle(.primaryAction)
                        .tint(.red)
                    }
                } else {
                    Button {
                        startSearch()
                    } label: {
                        Label(mode == .searcher ? "Search" : "Generate",
                              systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.primaryAction)
                }

                if frlgFiltering {
                    if !searcherResults.isEmpty { frlgResultsSection }
                } else if !activeResults.isEmpty {
                    SectionCard(title: "Results (\(activeResults.count))", icon: "list.bullet") {
                        ForEach(activeResults.prefix(500)) { r in
                            Button { selectedResult = r } label: {
                                resultRowView(r)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        #if os(iOS)
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        #endif
        .navigationDestination(item: $selectedResult) { result in
            SeedToTimeView(result: result, generation: generation,
                           tid: tid, sid: sid, method: method, onUseInGenerator: { seed in
                genSeedText = String(format: "%08X", seed)
                mode = .generator
            }, frlg: frlgFiltering ? frlg : nil,
               encounter: encounterMode == .static_ ? selectedEncounter : nil,
               calibrates: frlgFiltering && encounterMode == .static_,
               close: { selectedResult = nil })
        }
        .alert("Save Profile", isPresented: $showSaveAlert) {
            TextField("Profile name", text: $newProfileName)
            Button("Save") {
                let name = newProfileName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let profile = FinderProfile(name: name, tid: tid, sid: sid,
                                            gameVersion: selectedGame.rawValue,
                                            deadBattery: deadBattery,
                                            nationalDex: false)
                savedProfiles.append(profile)
                selectedProfileID = profile.id
                FinderProfileStore.save(savedProfiles)
                FinderProfileStore.lastProfileID = profile.id
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(verbatim: "Save profile for \(selectedGame.rawValue) TID \(tid) / SID \(sid)")
        }
        .leaveWarning(isSearching ? "The search in progress will stop." : nil)
        #if DEBUG && os(macOS)
        // With `-finder_game FireRed -finder_encounterCategory Gifts`: opens
        // a reachable Eevee target.
        .task {
            await DebugSnapshot.openSheet("frlgCalibration") {
                guard let eevee = StaticEncounterData.encounters(for: selectedGame, category: encounterCategory)
                    .first(where: { $0.species == 133 }) else { return }
                selectedEncounter = eevee
                let targets = staticSearchGen3(minIVs: (31, 31, 31, 31, 25, 0), maxIVs: (31, 31, 31, 31, 31, 31),
                                               natures: [], tid: tid, sid: sid, shinyOnly: false, method: .method1)
                selectedResult = targets.first { frlg.nearest(reaching: $0.seed) != nil }
            }
        }
        #endif
    }

    // MARK: Encounter Helpers

    private var leadApplies: Bool { !(generation == .gen3 && encounterMode == .static_) }

    /// Gen 3 and 4's searchers take Synchronize with any nature; everything
    /// else runs PokéFinder's generators (Gen 5's searches too), which take
    /// the Synchronize nature.
    private var searchesAnySyncNature: Bool {
        mode == .searcher && (generation == .gen3 || generation == .gen4)
    }

    private func autoSelectMethod() {
        switch generation {
        case .gen3:
            method = .method1
        case .gen4:
            if encounterMode == .wild {
                switch selectedGame {
                case .diamond, .pearl, .platinum:
                    method = .methodJ
                case .heartGold, .soulSilver:
                    method = .methodK
                default:
                    method = .methodJ
                }
            } else {
                method = .method1
            }
        case .gen5:
            method = .method5
        case .gen8:
            method = .method1
        }
    }

    private func encounterInfoCard(name: String, level: UInt8, game: String, method: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "target")
                .foregroundStyle(.orange)
            Text("\(name) Lv\(level)")
                .font(.callout).bold()
            Text("(\(game), \(method))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func wildSlotTable(route: WildEncounterRoute) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(route.slots) { slot in
                HStack {
                    Text(slot.slotRate)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .scaledWidth(36, relativeTo: .caption2, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Text(slot.speciesName)
                        .font(.caption)
                    Spacer()
                    if slot.minLevel == slot.maxLevel {
                        Text("Lv\(slot.minLevel)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Lv\(slot.minLevel)-\(slot.maxLevel)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Result Row View

    @ViewBuilder
    /// FireRed and LeafGreen searches can be narrowed to targets reachable
    /// from a seed the player can hit.
    private var frlgApplies: Bool {
        generation == .gen3 && (selectedGame == .fireRed || selectedGame == .leafGreen)
            && mode == .searcher && encounterMode != .id
    }

    private var frlgFiltering: Bool { frlgApplies && frlg.enabled }

    /// The search's targets that a seed the player can hit reaches in range,
    /// fewest advances first.
    private var frlgResults: [FRLGMatch] { frlgMatches.matches(for: searcherResults, search: frlg) }

    @ViewBuilder
    private var frlgResultsSection: some View {
        let matches = frlgResults
        SectionCard(title: "Reachable (\(matches.count.formatted()) of \(searcherResults.count.formatted()))", icon: "list.bullet") {
            if frlg.index == nil {
                ProgressView("Loading the seed list…")
            } else if matches.isEmpty, isSearching {
                Text("None of the targets found so far is \(frlg.minimumAdvances.formatted())–\(frlg.maximumAdvances.formatted()) advances from a seed you can hit. Still searching.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if matches.isEmpty {
                Text("None of these targets is \(frlg.minimumAdvances.formatted())–\(frlg.maximumAdvances.formatted()) advances from a seed you can hit with these settings. Widen the range, loosen the settings, or relax the filters.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(matches.prefix(500), id: \.result.id) { match in
                Button { selectedResult = match.result } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        resultRowView(match.result, showAdvances: false)
                        FRLGMatchLine(seed: match.seed, search: frlg)
                    }
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    /// `showAdvances` is off for a FireRed or LeafGreen target, whose
    /// advances come from its initial seed instead.
    private func resultRowView(_ r: StaticSearchResult, showAdvances: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if r.resultTID != nil {
                idResultRow(r)
            } else {
                standardResultRow(r, showAdvances: showAdvances)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func idResultRow(_ r: StaticSearchResult) -> some View {
        HStack {
            Text("Adv: \(r.advances)")
                .font(.system(.caption, design: .monospaced))
            Spacer()
        }
        HStack {
            Text("TID: \(r.resultTID ?? 0)")
                .font(.system(.caption2, design: .monospaced))
            Text("SID: \(r.resultSID ?? 0)")
                .font(.system(.caption2, design: .monospaced))
            Spacer()
            Text("TSV: \(r.resultTSV ?? 0)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        HStack {
            Text("Display TID: \(r.resultDisplayTID ?? 0)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func standardResultRow(_ r: StaticSearchResult, showAdvances: Bool = true) -> some View {
        HStack {
            if let name = r.specieName {
                Text(name).font(.caption).bold()
                if let lv = r.level {
                    Text("Lv\(lv)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !showAdvances {
                EmptyView()
            } else if let ivAdv = r.ivAdvances {
                Text("Adv: \(r.advances)/\(ivAdv)")
                    .font(.system(.caption, design: .monospaced))
            } else {
                Text("Adv: \(r.advances)")
                    .font(.system(.caption, design: .monospaced))
            }
        }
        HStack {
            if let dtStr = r.dateTimeString {
                Text(dtStr)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if generation != .gen5 {
                Text("Seed: \(r.seedHex)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(r.natureName).font(.caption2).bold()
            Text(r.genderSymbol).font(.caption2)
            if r.shiny {
                Image(systemName: "star.fill")
                    .font(.caption2).foregroundStyle(.yellow)
            }
        }
        if let seedHex64 = r.seedHex64 {
            HStack {
                Text("Seed: \(seedHex64)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if let t0 = r.timer0 {
                    Spacer()
                    Text("T0: \(t0)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if let bp = r.buttonPressName {
                    Spacer()
                    Text("Keys: \(bp)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        HStack {
            Text("IVs: \(r.ivSummary)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text("HP: \(r.hiddenPowerName) \(r.hiddenPowerStrength)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        HStack {
            Text("PID: \(r.pidHex)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("Ability: \(r.ability)")
                .font(.caption2).foregroundStyle(.tertiary)
            if let item = r.itemName {
                Text(item).font(.caption2).foregroundStyle(ColorRole.item.color)
            }
        }
        if let inh = r.inheritance {
            let inhLabels = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
            HStack {
                ForEach(0..<6, id: \.self) { i in
                    let label = inhLabels[i]
                    let val = inh[i]
                    Text("\(label):\(val == 1 ? "A" : val == 2 ? "B" : "-")")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(val > 0 ? Color.blue : Color.gray)
                }
                Spacer()
            }
        }
        if let em = r.eggMove, em > 0 {
            HStack {
                Text("Egg Move: \(PFBridge.moveName(em))")
                    .font(.caption2).foregroundStyle(.purple)
                Spacer()
            }
        }
        if r.chatot != nil || r.call != nil {
            HStack {
                if let pitch = r.chatotPitch {
                    Text("Chatot: \(pitch)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.cyan)
                }
                if let call = r.callName {
                    Text("Call: \(call)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.mint)
                }
                Spacer()
            }
        }
    }

    // MARK: Gen 8 Encounter Mode Views

    private var gen8EggParametersView: some View {
        VStack(spacing: 8) {
            Text("Parent A").font(.subheadline).bold().frame(maxWidth: .infinity, alignment: .leading)
            ForEach(0..<6) { i in
                let statNames = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
                IVSliderRow8(label: statNames[i], value: Binding(
                    get: { gen8EggParentAIVs[i] },
                    set: { gen8EggParentAIVs[i] = $0 }
                ))
            }
            Picker("Ability", selection: $gen8ParentAAbility) {
                Text("1").tag(UInt8(0)); Text("2").tag(UInt8(1)); Text("H").tag(UInt8(2))
            }.pickerStyle(.segmented).labelsHidden()
            Picker("Gender", selection: $gen8ParentAGender) {
                Text("Male").tag(UInt8(0)); Text("Female").tag(UInt8(1))
            }.pickerStyle(.segmented).labelsHidden()
            Picker("Item", selection: $gen8ParentAItem) {
                Text("None").tag(UInt8(0)); Text("Everstone").tag(UInt8(1))
                Text("Destiny Knot").tag(UInt8(2)); Text("Power Weight").tag(UInt8(3))
                Text("Power Bracer").tag(UInt8(4)); Text("Power Belt").tag(UInt8(5))
                Text("Power Lens").tag(UInt8(6)); Text("Power Band").tag(UInt8(7))
                Text("Power Anklet").tag(UInt8(8))
            }
            Picker("Nature", selection: $gen8ParentANature) {
                ForEach(0..<25, id: \.self) { i in Text(pfNatureNames[i]).tag(UInt8(i)) }
            }

            Divider().padding(.vertical, 4)
            Text("Parent B").font(.subheadline).bold().frame(maxWidth: .infinity, alignment: .leading)
            ForEach(0..<6) { i in
                let statNames = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
                IVSliderRow8(label: statNames[i], value: Binding(
                    get: { gen8EggParentBIVs[i] },
                    set: { gen8EggParentBIVs[i] = $0 }
                ))
            }
            Picker("Ability", selection: $gen8ParentBAbility) {
                Text("1").tag(UInt8(0)); Text("2").tag(UInt8(1)); Text("H").tag(UInt8(2))
            }.pickerStyle(.segmented).labelsHidden()
            Picker("Gender", selection: $gen8ParentBGender) {
                Text("Male").tag(UInt8(0)); Text("Female").tag(UInt8(1))
            }.pickerStyle(.segmented).labelsHidden()
            Picker("Item", selection: $gen8ParentBItem) {
                Text("None").tag(UInt8(0)); Text("Everstone").tag(UInt8(1))
                Text("Destiny Knot").tag(UInt8(2)); Text("Power Weight").tag(UInt8(3))
                Text("Power Bracer").tag(UInt8(4)); Text("Power Belt").tag(UInt8(5))
                Text("Power Lens").tag(UInt8(6)); Text("Power Band").tag(UInt8(7))
                Text("Power Anklet").tag(UInt8(8))
            }
            Picker("Nature", selection: $gen8ParentBNature) {
                ForEach(0..<25, id: \.self) { i in Text(pfNatureNames[i]).tag(UInt8(i)) }
            }

            Divider().padding(.vertical, 4)
            Picker("Compatibility", selection: $gen8Compatibility) {
                Text("The two don't like each other (20%)").tag(UInt8(20))
                Text("The two seem to get along (50%)").tag(UInt8(50))
                Text("The two get along very well (70%)").tag(UInt8(70))
            }
            Toggle("Masuda Method", isOn: $gen8Masuda)
        }
    }

    private var gen8RaidParametersView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Den Index")
                Spacer()
                TextField("0", value: $gen8RaidDen, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .scaledWidth(80)
                    .multilineTextAlignment(.trailing)
            }
            Picker("Rarity", selection: $gen8RaidRarity) {
                Text("Normal").tag(UInt8(0))
                Text("Rare").tag(UInt8(1))
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Text("Raid Index")
                Spacer()
                TextField("0", value: $gen8RaidIndex, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .scaledWidth(80)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Level")
                Spacer()
                TextField("60", value: $gen8RaidLevel, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .scaledWidth(80)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var gen8UndergroundParametersView: some View {
        VStack(spacing: 8) {
            Toggle("Diglett Bonus", isOn: $gen8Diglett)
            Picker("Story Progress", selection: $gen8StoryFlag) {
                Text("Pre-National Dex").tag(0)
                Text("Post-National Dex").tag(1)
            }
        }
    }

    private var gen8IDParametersView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Target TID")
                Spacer()
                TextField("Optional", text: $gen8FilterTIDText)
                    .textFieldStyle(.roundedBorder)
                    .scaledWidth(120)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            HStack {
                Text("Target SID")
                Spacer()
                TextField("Optional", text: $gen8FilterSIDText)
                    .textFieldStyle(.roundedBorder)
                    .scaledWidth(120)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            HStack {
                Text("Display TID")
                Spacer()
                TextField("Optional", text: $gen8FilterDisplayTIDText)
                    .textFieldStyle(.roundedBorder)
                    .scaledWidth(120)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
        }
    }

    // MARK: Searcher Inputs

    private var searcherInputs: some View {
        Group {
            SectionCard(title: "IV Ranges", icon: "number.square") {
                FinderIVRangeRow(label: "HP", min: $minHP, max: $maxHP)
                FinderIVRangeRow(label: "Attack", min: $minAtk, max: $maxAtk)
                FinderIVRangeRow(label: "Defense", min: $minDef, max: $maxDef)
                FinderIVRangeRow(label: "Sp. Atk", min: $minSpA, max: $maxSpA)
                FinderIVRangeRow(label: "Sp. Def", min: $minSpD, max: $maxSpD)
                FinderIVRangeRow(label: "Speed", min: $minSpe, max: $maxSpe)
            }

            if generation == .gen4 {
                SectionCard(title: "Delay & Advance Range", icon: "clock") {
                    FinderUInt16Field(label: "Min Delay", value: $minDelay)
                    FinderUInt16Field(label: "Max Delay", value: $maxDelay)
                    RNGIntField(label: "Min Advance", value: $searcherMinAdvance, range: RNGFieldRange.advances)
                    RNGIntField(label: "Max Advance", value: $searcherMaxAdvance, range: RNGFieldRange.advances)
                }
            }

            if generation == .gen5 {
                SectionCard(title: "Date Range", icon: "calendar") {
                    DatePicker("Start Date", selection: $gen5StartDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $gen5EndDate, displayedComponents: .date)
                }
                SectionCard(title: "IV Advance Range", icon: "number") {
                    RNGIntField(label: "Min IV Advance", value: $gen5IVMinAdvance, range: RNGFieldRange.advances)
                    RNGIntField(label: "Max IV Advance", value: $gen5IVMaxAdvance, range: RNGFieldRange.advances)
                    RNGIntField(label: "Min PID Advance", value: $searcherMinAdvance, range: RNGFieldRange.advances)
                    RNGIntField(label: "Max PID Advance", value: $searcherMaxAdvance, range: RNGFieldRange.advances)
                }
            }
        }
    }

    // MARK: Generator Inputs

    private var generatorInputs: some View {
        SectionCard(title: "Seed & Advances", icon: "number") {
            if generation == .gen8 {
                HStack {
                    Text("Seed 0 (hex)")
                    Spacer()
                    TextField("e.g. 1A2B3C4D5E6F7890", text: $genSeedText)
                        .textFieldStyle(.roundedBorder)
                        .scaledWidth(190)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                }
                HStack {
                    Text("Seed 1 (hex)")
                    Spacer()
                    TextField("e.g. 1A2B3C4D5E6F7890", text: $gen8Seed1Text)
                        .textFieldStyle(.roundedBorder)
                        .scaledWidth(190)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                }
            } else {
                HStack {
                    Text("Seed (hex)")
                    Spacer()
                    TextField(generation == .gen5 ? "e.g. 1A2B3C4D5E6F7890" : "e.g. 1A2B3C4D", text: $genSeedText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: generation == .gen5 ? 190 : 140)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                }
            }
            RNGIntField(label: "Initial Advance", value: $genInitAdvance, range: RNGFieldRange.advances)
            RNGIntField(label: "Max Advance", value: $genMaxAdvance, range: RNGFieldRange.advances)
        }
    }

    private var seedVerificationSection: some View {
        let seed = UInt32(genSeedText, radix: 16) ?? 0
        return SectionCard(title: "Seed Verification", icon: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Coin Flips (Poketch)")
                    .font(.caption).foregroundStyle(.secondary)
                let flips = PFBridge.coinFlips(seed).split(separator: ", ").map(String.init)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 10), spacing: 4) {
                    ForEach(Array(flips.enumerated()), id: \.offset) { _, flip in
                        Text(flip)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(flip == "H" ? .orange : .cyan)
                    }
                }

                Divider()

                Text("Elm/Irwin Calls")
                    .font(.caption).foregroundStyle(.secondary)
                Text(PFBridge.getCalls(seed))
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text("Chatot Pitches")
                    .font(.caption).foregroundStyle(.secondary)
                chatotPitchGrid(seed: seed)
            }
        }
    }

    private func chatotPitchGrid(seed: UInt32) -> some View {
        let pitches: [(Int, String)] = {
            var rngState = seed
            var result: [(Int, String)] = []
            for i in 0..<20 {
                rngState = rngState &* 0x41C64E6D &+ 0x6073
                let high = UInt16(rngState >> 16)
                let value = UInt8((UInt32(high % 8192) * 100) >> 13)
                let label: String
                switch value {
                case 0..<20: label = "L"
                case 20..<40: label = "ML"
                case 40..<60: label = "M"
                case 60..<80: label = "MH"
                default: label = "H"
                }
                result.append((i, label))
            }
            return result
        }()

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 10), spacing: 4) {
            ForEach(pitches, id: \.0) { _, label in
                Text(label)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(label == "H" ? .red : label == "L" ? .blue : .primary)
            }
        }
    }

    // MARK: - Coin Flip Finder

    private var coinFlipSearchSection: some View {
        SectionCard(title: "Coin Flip Finder", icon: "circle.lefthalf.filled") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tap to record observed Poketch coin flips")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(Array(flipInput.enumerated()), id: \.offset) { idx, isHeads in
                        Button {
                            flipInput[idx].toggle()
                        } label: {
                            Text(isHeads ? "H" : "T")
                                .font(.system(.caption, design: .monospaced)).bold()
                                .foregroundStyle(isHeads ? .orange : .cyan)
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isHeads ? Color.orange.opacity(0.15) : Color.cyan.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if flipInput.count < 15 {
                        Button { flipInput.append(false) } label: {
                            Image(systemName: "plus.circle").foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Text("Range: \u{00B1}")
                        .font(.caption)
                    TextField("200", value: $flipSearchRange, format: .number)
                        .clamping($flipSearchRange, to: RNGFieldRange.word)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .textFieldStyle(.roundedBorder)
                        .scaledWidth(80)
                        .font(.caption)
                }

                HStack {
                    if !flipInput.isEmpty {
                        Button("Clear") {
                            flipInput.removeAll()
                            flipSearchResults.removeAll()
                        }
                        .font(.caption)
                    }
                    Spacer()
                    Button { searchCoinFlips() } label: {
                        Label("Search", systemImage: "magnifyingglass").font(.caption)
                    }
                    .disabled(flipInput.count < 5 || flipSearching)
                }

                if flipSearching {
                    ProgressView().padding(.vertical, 4)
                }

                if !flipSearchResults.isEmpty {
                    Divider()
                    Text("Matching Seeds (\(flipSearchResults.count))")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(flipSearchResults.prefix(50).enumerated()), id: \.offset) { _, match in
                        HStack {
                            Text(String(format: "%08X", match.seed))
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text(match.flips)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func searchCoinFlips() {
        guard flipInput.count >= 5 else { return }
        flipSearching = true
        flipSearchResults = []

        let observed = flipInput
        let targetSeed = UInt32(genSeedText, radix: 16) ?? 0
        let range = UInt32(clamping: flipSearchRange)
        let lo = targetSeed &- range
        let hi = targetSeed &+ range

        Task.detached {
            var found: [(seed: UInt32, flips: String)] = []

            if lo <= hi {
                for seed in lo...hi {
                    if matchesCoinFlips(seed: seed, observed: observed) {
                        found.append((seed: seed, flips: PFBridge.coinFlips(seed)))
                    }
                }
            } else {
                for seed in lo...UInt32.max {
                    if matchesCoinFlips(seed: seed, observed: observed) {
                        found.append((seed: seed, flips: PFBridge.coinFlips(seed)))
                    }
                }
                for seed: UInt32 in 0...hi {
                    if matchesCoinFlips(seed: seed, observed: observed) {
                        found.append((seed: seed, flips: PFBridge.coinFlips(seed)))
                    }
                }
            }

            let results = found
            await MainActor.run {
                flipSearchResults = results
                flipSearching = false
            }
        }
    }

    // MARK: - Elm/Irwin Call Finder

    private var callSearchSection: some View {
        SectionCard(title: "Elm/Irwin Call Finder", icon: "phone.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tap to record observed Elm/Irwin calls")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(Array(callInput.enumerated()), id: \.offset) { idx, call in
                        Button {
                            callInput[idx] = (call + 1) % 3
                        } label: {
                            Text(callLabel(call))
                                .font(.system(.caption, design: .monospaced)).bold()
                                .foregroundStyle(callColor(call))
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(callColor(call).opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if callInput.count < 15 {
                        Button { callInput.append(0) } label: {
                            Image(systemName: "plus.circle").foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("E = Elm, K = Irwin, P = Pokemon (tap to cycle)")
                    .font(.caption2).foregroundStyle(.tertiary)

                HStack {
                    Text("Range: \u{00B1}")
                        .font(.caption)
                    TextField("200", value: $callSearchRange, format: .number)
                        .clamping($callSearchRange, to: RNGFieldRange.word)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .textFieldStyle(.roundedBorder)
                        .scaledWidth(80)
                        .font(.caption)
                }

                Stepper("Roamers: \(roamerCount)", value: $roamerCount, in: 0...3)
                    .font(.caption)

                HStack {
                    if !callInput.isEmpty {
                        Button("Clear") {
                            callInput.removeAll()
                            callSearchResults.removeAll()
                        }
                        .font(.caption)
                    }
                    Spacer()
                    Button { searchCalls() } label: {
                        Label("Search", systemImage: "magnifyingglass").font(.caption)
                    }
                    .disabled(callInput.count < 3 || callSearching)
                }

                if callSearching {
                    ProgressView().padding(.vertical, 4)
                }

                if !callSearchResults.isEmpty {
                    Divider()
                    Text("Matching Seeds (\(callSearchResults.count))")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(callSearchResults.prefix(50).enumerated()), id: \.offset) { _, match in
                        HStack {
                            Text(String(format: "%08X", match.seed))
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text(match.calls)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func callLabel(_ call: UInt8) -> String {
        switch call {
        case 0: return "E"
        case 1: return "K"
        default: return "P"
        }
    }

    private func callColor(_ call: UInt8) -> Color {
        switch call {
        case 0: return .green
        case 1: return .orange
        default: return .purple
        }
    }

    private func searchCalls() {
        guard callInput.count >= 3 else { return }
        callSearching = true
        callSearchResults = []

        let observed = callInput
        let targetSeed = UInt32(genSeedText, radix: 16) ?? 0
        let range = UInt32(clamping: callSearchRange)
        let skips = roamerCount
        let lo = targetSeed &- range
        let hi = targetSeed &+ range

        Task.detached {
            var found: [(seed: UInt32, calls: String)] = []

            func check(_ seed: UInt32) {
                if matchesCalls(seed: seed, observed: observed, skips: skips) {
                    found.append((seed: seed, calls: PFBridge.getCalls(seed, skips: skips)))
                }
            }

            if lo <= hi {
                for seed in lo...hi { check(seed) }
            } else {
                for seed in lo...UInt32.max { check(seed) }
                for seed: UInt32 in 0...hi { check(seed) }
            }

            let results = found
            await MainActor.run {
                callSearchResults = results
                callSearching = false
            }
        }
    }

    // MARK: Search Logic

    private func stopSearch() {
        searchWorkTask?.cancel()
        searchWorkTask = nil
        searchTask?.cancel()
        searchTask = nil
    }

    private func startSearch() {
        stopSearch()
        if mode == .searcher { searcherResults = [] } else { generatorResults = [] }
        searchProgressValue = -1

        // Capture all @State values before entering task
        let gen = generation
        let m = mode
        let meth = method
        let natFilter = selectedNatures
        let tID = tid, sID = sid
        let shiny = shinyOnly
        let hpMin = minHP, hpMax = maxHP
        let atkMin = minAtk, atkMax = maxAtk
        let defMin = minDef, defMax = maxDef
        let spaMin = minSpA, spaMax = maxSpA
        let spdMin = minSpD, spdMax = maxSpD
        let speMin = minSpe, speMax = maxSpe
        let delMin = minDelay, delMax = maxDelay
        let srcMinAdv = UInt32(clamping: searcherMinAdvance), srcMaxAdv = UInt32(clamping: searcherMaxAdvance)
        let ld = lead, sNat = syncNature
        let seedVal = UInt32(genSeedText, radix: 16) ?? 0
        let seedVal64 = UInt64(genSeedText, radix: 16) ?? 0
        let initAdv = UInt32(clamping: genInitAdvance)
        let maxAdv = UInt32(clamping: genMaxAdvance)
        let genderFilter = filterGender
        let abilityFilter = filterAbility
        let hpFilter: [Bool] = {
            if selectedHiddenPowers.isEmpty { return [Bool](repeating: true, count: 16) }
            var arr = [Bool](repeating: false, count: 16)
            for p in selectedHiddenPowers { arr[Int(p)] = true }
            return arr
        }()
        let isDeadBattery = deadBattery && (selectedGame == .emerald)

        // Gen 5 profile params
        let g5Mac = UInt64(gen5MacText.replacingOccurrences(of: ":", with: ""), radix: 16) ?? 0
        let g5Keys = gen5Keypresses
        let g5VCount = UInt8(clamping: gen5VCount)
        let g5GxStat = UInt8(clamping: gen5GxStat)
        let g5VFrame = UInt8(clamping: gen5VFrame)
        let g5SkipLR = gen5SkipLR
        let g5Timer0Min = UInt16(clamping: gen5Timer0Min)
        let g5Timer0Max = UInt16(clamping: gen5Timer0Max)
        let g5MemoryLink = gen5MemoryLink
        let g5ShinyCharm = gen5ShinyCharm
        let g5DSType = gen5DSType
        let g5Language = gen5Language
        let g5Season = gen5Season

        // Gen 8 params
        let g8Seed0 = UInt64(genSeedText, radix: 16) ?? 0
        let g8Seed1 = UInt64(gen8Seed1Text, radix: 16) ?? 0
        let g8ShinyCharm = gen8ShinyCharm
        let g8OvalCharm = gen8OvalCharm

        // Gen 8 Egg params
        let g8ParentAIVs = gen8EggParentAIVs
        let g8ParentBIVs = gen8EggParentBIVs
        let g8ParentAAbility = gen8ParentAAbility
        let g8ParentBAbility = gen8ParentBAbility
        let g8ParentAGender = gen8ParentAGender
        let g8ParentBGender = gen8ParentBGender
        let g8ParentAItem = gen8ParentAItem
        let g8ParentBItem = gen8ParentBItem
        let g8ParentANature = gen8ParentANature
        let g8ParentBNature = gen8ParentBNature
        let g8Compatibility = gen8Compatibility
        let g8Masuda = gen8Masuda
        let g8EggSpecie = gen8EggSpecie

        // Gen 8 Raid params
        let g8RaidDen = gen8RaidDen
        let g8RaidRarity = gen8RaidRarity
        let g8RaidIndex = gen8RaidIndex
        let g8RaidLevel = gen8RaidLevel

        // Gen 8 Underground params
        let g8Diglett = gen8Diglett
        let g8StoryFlag = Int32(gen8StoryFlag)

        // Gen 8 ID filter params
        let g8FilterTID = UInt16(gen8FilterTIDText) ?? 0
        let g8HasTIDFilter = !gen8FilterTIDText.isEmpty
        let g8FilterSID = UInt16(gen8FilterSIDText) ?? 0
        let g8HasSIDFilter = !gen8FilterSIDText.isEmpty
        let g8FilterDisplayTID = UInt32(gen8FilterDisplayTIDText) ?? 0
        let g8HasDisplayFilter = !gen8FilterDisplayTIDText.isEmpty

        // Gen 5 searcher date range
        let g5StartComponents = Calendar.current.dateComponents([.year, .month, .day], from: gen5StartDate)
        let g5EndComponents = Calendar.current.dateComponents([.year, .month, .day], from: gen5EndDate)
        let g5StartYear = UInt16(g5StartComponents.year ?? 2000)
        let g5StartMonth = UInt8(g5StartComponents.month ?? 1)
        let g5StartDay = UInt8(g5StartComponents.day ?? 1)
        let g5EndYear = UInt16(g5EndComponents.year ?? 2000)
        let g5EndMonth = UInt8(g5EndComponents.month ?? 1)
        let g5EndDay = UInt8(g5EndComponents.day ?? 2)
        let g5IVMinAdv = UInt32(clamping: gen5IVMinAdvance)
        let g5IVMaxAdv = UInt32(clamping: gen5IVMaxAdvance)

        // Wild encounter context (pre-compute on main actor)
        let encMode = encounterMode
        let encLocation = selectedLocation
        let speciesFilter = selectedSpeciesFilter
        let pfGameVal = selectedGame.pfGame
        let pfEncVal = selectedEncounterType.pfEncounter
        let isGen3 = generation == .gen3
        let locationIDVal: UInt8 = {
            if generation == .gen5 {
                return findLocationID5(pfGame: pfGameVal, pfEnc: pfEncVal, locationName: encLocation, season: g5Season)
            } else if generation == .gen8 {
                return findLocationID8(pfGame: pfGameVal, pfEnc: pfEncVal, locationName: encLocation)
            }
            return findLocationID(pfGame: pfGameVal, pfEnc: pfEncVal,
                                  isGen3: isGen3, locationName: encLocation)
        }()
        // A Gen 3 static encounter's template, for its gender.
        let gen3Template: PFStaticTemplateRef? = gen == .gen3 && encMode == .static_
            ? selectedEncounter.flatMap {
                PFBridge.staticTemplate3(species: $0.species, game: pfGameVal, preferring: $0.category.pfStaticType3)
            } : nil
        let slotSpecies: [UInt16]
        if let route = PFEncounterDataProvider.wildEncounter(for: selectedGame,
                                                              location: encLocation,
                                                              type: selectedEncounterType) {
            slotSpecies = route.slots.map { $0.species }
        } else {
            slotSpecies = []
        }

        enum SearchEvent: Sendable {
            case result(StaticSearchResult)
            case progress(Double)
        }

        var _continuation: AsyncStream<SearchEvent>.Continuation!
        let stream = AsyncStream<SearchEvent> { _continuation = $0 }
        let continuation = _continuation!

        searchWorkTask = Task.detached {
            if encMode == .egg && gen == .gen8 {
                eggGenerateGen8Streaming(
                    seed0: g8Seed0, seed1: g8Seed1,
                    initialAdvance: initAdv, maxAdvance: maxAdv,
                    compatibility: g8Compatibility,
                    parentAIVs: g8ParentAIVs, parentBIVs: g8ParentBIVs,
                    parentAAbility: g8ParentAAbility, parentBAbility: g8ParentBAbility,
                    parentAGender: g8ParentAGender, parentBGender: g8ParentBGender,
                    parentAItem: g8ParentAItem, parentBItem: g8ParentBItem,
                    parentANature: g8ParentANature, parentBNature: g8ParentBNature,
                    eggSpecie: g8EggSpecie, masuda: g8Masuda,
                    natures: natFilter, tid: tID, sid: sID,
                    shinyOnly: shiny, game: pfGameVal,
                    shinyCharm: g8ShinyCharm, ovalCharm: g8OvalCharm,
                    filterGender: genderFilter, filterAbility: abilityFilter,
                    hiddenPowers: hpFilter
                ) { continuation.yield(.result($0)) }
                continuation.yield(.progress(100))
            } else if encMode == .id && gen == .gen8 {
                idGenerateGen8Streaming(
                    seed0: g8Seed0, seed1: g8Seed1,
                    initialAdvance: initAdv, maxAdvance: maxAdv,
                    filterTID: g8FilterTID, hasTIDFilter: g8HasTIDFilter,
                    filterSID: g8FilterSID, hasSIDFilter: g8HasSIDFilter,
                    filterDisplayTID: g8FilterDisplayTID, hasDisplayFilter: g8HasDisplayFilter
                ) { continuation.yield(.result($0)) }
                continuation.yield(.progress(100))
            } else if encMode == .raid && gen == .gen8 {
                raidGenerateGen8Streaming(
                    seed: g8Seed0,
                    initialAdvance: initAdv, maxAdvance: maxAdv,
                    natures: natFilter, tid: tID, sid: sID,
                    shinyOnly: shiny, game: pfGameVal,
                    shinyCharm: g8ShinyCharm,
                    denIndex: g8RaidDen, rarity: g8RaidRarity,
                    raidIndex: g8RaidIndex, level: g8RaidLevel,
                    filterGender: genderFilter, filterAbility: abilityFilter,
                    hiddenPowers: hpFilter
                ) { continuation.yield(.result($0)) }
                continuation.yield(.progress(100))
            } else if encMode == .underground && gen == .gen8 {
                undergroundGenerateGen8Streaming(
                    seed0: g8Seed0, seed1: g8Seed1,
                    initialAdvance: initAdv, maxAdvance: maxAdv,
                    natures: natFilter, tid: tID, sid: sID,
                    shinyOnly: shiny, lead: ld, syncNature: sNat, game: pfGameVal,
                    shinyCharm: g8ShinyCharm,
                    diglett: g8Diglett, storyFlag: g8StoryFlag,
                    filterGender: genderFilter, filterAbility: abilityFilter,
                    hiddenPowers: hpFilter
                ) { continuation.yield(.result($0)) }
                continuation.yield(.progress(100))
            } else if encMode == .wild {
                if gen == .gen5 && m == .searcher {
                    wildSearchGen5Streaming(
                        initialAdvance: srcMinAdv, maxAdvance: srcMaxAdv,
                        ivInitialAdvance: g5IVMinAdv, ivMaxAdvance: g5IVMaxAdv,
                        natures: natFilter, tid: tID, sid: sID, shinyOnly: shiny,
                        method: meth, lead: ld, syncNature: sNat, game: pfGameVal,
                        encounter: pfEncVal, location: locationIDVal, season: g5Season,
                        mac: g5Mac, keypresses: g5Keys,
                        vcount: g5VCount, gxstat: g5GxStat, vframe: g5VFrame,
                        skipLR: g5SkipLR, timer0Min: g5Timer0Min, timer0Max: g5Timer0Max,
                        memoryLink: g5MemoryLink, shinyCharm: g5ShinyCharm,
                        dsType: g5DSType, language: g5Language,
                        startYear: g5StartYear, startMonth: g5StartMonth, startDay: g5StartDay,
                        endYear: g5EndYear, endMonth: g5EndMonth, endDay: g5EndDay,
                        filterGender: genderFilter, filterAbility: abilityFilter,
                        hiddenPowers: hpFilter,
                        onResult: { continuation.yield(.result($0)) },
                        onProgress: { continuation.yield(.progress($0)) })
                } else if gen == .gen5 {
                    wildGenerateGen5Streaming(
                        seed: seedVal64, initialAdvance: initAdv, maxAdvance: maxAdv,
                        natures: natFilter, tid: tID, sid: sID, shinyOnly: shiny,
                        method: meth, lead: ld, syncNature: sNat, game: pfGameVal,
                        encounter: pfEncVal, location: locationIDVal, season: g5Season,
                        mac: g5Mac, keypresses: g5Keys,
                        vcount: g5VCount, gxstat: g5GxStat, vframe: g5VFrame,
                        skipLR: g5SkipLR, timer0Min: g5Timer0Min, timer0Max: g5Timer0Max,
                        memoryLink: g5MemoryLink, shinyCharm: g5ShinyCharm,
                        dsType: g5DSType, language: g5Language,
                        filterGender: genderFilter, filterAbility: abilityFilter,
                        hiddenPowers: hpFilter
                    ) { continuation.yield(.result($0)) }
                    continuation.yield(.progress(100))
                } else if gen == .gen8 {
                    wildGenerateGen8Streaming(
                        seed0: g8Seed0, seed1: g8Seed1,
                        initialAdvance: initAdv, maxAdvance: maxAdv,
                        natures: natFilter, tid: tID, sid: sID,
                        shinyOnly: shiny, lead: ld, syncNature: sNat, game: pfGameVal,
                        shinyCharm: g8ShinyCharm,
                        encounter: pfEncVal, location: locationIDVal,
                        filterGender: genderFilter, filterAbility: abilityFilter,
                        hiddenPowers: hpFilter
                    ) { continuation.yield(.result($0)) }
                    continuation.yield(.progress(100))
                } else {
                    runWildSearch(gen: gen, mode: m, method: meth,
                                  natures: natFilter, tid: tID, sid: sID,
                                  shinyOnly: shiny,
                                  minIVs: (hpMin, atkMin, defMin, spaMin, spdMin, speMin),
                                  maxIVs: (hpMax, atkMax, defMax, spaMax, spdMax, speMax),
                                  seed: seedVal, initAdv: initAdv, maxAdv: maxAdv,
                                  searcherMinAdv: srcMinAdv, searcherMaxAdv: srcMaxAdv,
                                  minDelay: UInt32(delMin), maxDelay: UInt32(delMax),
                                  pfGame: pfGameVal, pfEnc: pfEncVal,
                                  locationID: locationIDVal,
                                  slotSpecies: slotSpecies,
                                  speciesFilter: speciesFilter,
                                  lead: ld, syncNature: sNat, isEmerald: isDeadBattery,
                                  filterGender: genderFilter, filterAbility: abilityFilter,
                                  hiddenPowers: hpFilter,
                                  onResult: { continuation.yield(.result($0)) },
                                  onProgress: { continuation.yield(.progress($0)) })
                }
            } else if m == .searcher {
                if gen == .gen5 {
                    staticSearchGen5Streaming(
                        initialAdvance: srcMinAdv, maxAdvance: srcMaxAdv,
                        ivInitialAdvance: g5IVMinAdv, ivMaxAdvance: g5IVMaxAdv,
                        natures: natFilter, tid: tID, sid: sID, shinyOnly: shiny,
                        method: meth, lead: ld, syncNature: sNat, game: pfGameVal,
                        mac: g5Mac, keypresses: g5Keys,
                        vcount: g5VCount, gxstat: g5GxStat, vframe: g5VFrame,
                        skipLR: g5SkipLR, timer0Min: g5Timer0Min, timer0Max: g5Timer0Max,
                        memoryLink: g5MemoryLink, shinyCharm: g5ShinyCharm,
                        dsType: g5DSType, language: g5Language,
                        startYear: g5StartYear, startMonth: g5StartMonth, startDay: g5StartDay,
                        endYear: g5EndYear, endMonth: g5EndMonth, endDay: g5EndDay,
                        filterGender: genderFilter, filterAbility: abilityFilter,
                        hiddenPowers: hpFilter,
                        onResult: { continuation.yield(.result($0)) },
                        onProgress: { continuation.yield(.progress($0)) })
                } else if gen == .gen3 {
                    staticSearchGen3Streaming(
                        minIVs: (hpMin, atkMin, defMin, spaMin, spdMin, speMin),
                        maxIVs: (hpMax, atkMax, defMax, spaMax, spdMax, speMax),
                        natures: natFilter, tid: tID, sid: sID,
                        shinyOnly: shiny, method: meth,
                        game: pfGameVal, template: gen3Template,
                        filterGender: genderFilter, filterAbility: abilityFilter,
                        hiddenPowers: hpFilter,
                        onProgress: { continuation.yield(.progress($0)) }
                    ) { continuation.yield(.result($0)) }
                } else {
                    staticSearchGen4Streaming(
                        minIVs: (hpMin, atkMin, defMin, spaMin, spdMin, speMin),
                        maxIVs: (hpMax, atkMax, defMax, spaMax, spdMax, speMax),
                        natures: natFilter, tid: tID, sid: sID,
                        shinyOnly: shiny, method: meth,
                        minAdvance: srcMinAdv, maxAdvance: srcMaxAdv,
                        minDelay: delMin, maxDelay: delMax,
                        filterGender: genderFilter, filterAbility: abilityFilter,
                        hiddenPowers: hpFilter
                    ) { continuation.yield(.result($0)) }
                }
                continuation.yield(.progress(100))
            } else {
                if gen == .gen3 {
                    staticGenerateGen3Streaming(
                        seed: seedVal, initialAdvance: initAdv,
                        maxAdvance: maxAdv,
                        natures: natFilter, tid: tID, sid: sID,
                        shinyOnly: shiny, method: meth,
                        game: pfGameVal, template: gen3Template,
                        filterGender: genderFilter, filterAbility: abilityFilter,
                        hiddenPowers: hpFilter
                    ) { continuation.yield(.result($0)) }
                } else if gen == .gen5 {
                    staticGenerateGen5Streaming(
                        seed: seedVal64, initialAdvance: initAdv, maxAdvance: maxAdv,
                        natures: natFilter, tid: tID, sid: sID, shinyOnly: shiny,
                        method: meth, lead: ld, syncNature: sNat, game: pfGameVal,
                        mac: g5Mac, keypresses: g5Keys,
                        vcount: g5VCount, gxstat: g5GxStat, vframe: g5VFrame,
                        skipLR: g5SkipLR, timer0Min: g5Timer0Min, timer0Max: g5Timer0Max,
                        memoryLink: g5MemoryLink, shinyCharm: g5ShinyCharm,
                        dsType: g5DSType, language: g5Language,
                        filterGender: genderFilter, filterAbility: abilityFilter,
                        hiddenPowers: hpFilter
                    ) { continuation.yield(.result($0)) }
                } else if gen == .gen8 {
                    staticGenerateGen8Streaming(
                        seed0: g8Seed0, seed1: g8Seed1,
                        initialAdvance: initAdv, maxAdvance: maxAdv,
                        natures: natFilter, tid: tID, sid: sID,
                        shinyOnly: shiny, lead: ld, syncNature: sNat, game: pfGameVal,
                        shinyCharm: g8ShinyCharm,
                        filterGender: genderFilter, filterAbility: abilityFilter,
                        hiddenPowers: hpFilter
                    ) { continuation.yield(.result($0)) }
                } else {
                    staticGenerateGen4Streaming(
                        seed: seedVal, initialAdvance: initAdv,
                        maxAdvance: maxAdv,
                        natures: natFilter, tid: tID, sid: sID,
                        shinyOnly: shiny, method: meth,
                        lead: ld, syncNature: sNat,
                        filterGender: genderFilter, filterAbility: abilityFilter,
                        hiddenPowers: hpFilter
                    ) { continuation.yield(.result($0)) }
                }
                continuation.yield(.progress(100))
            }
            continuation.finish()
        }

        let isSearcherMode = m == .searcher
        searchTask = Task {
            var buffer: [StaticSearchResult] = []
            for await event in stream {
                if Task.isCancelled { break }
                switch event {
                case .result(let result):
                    buffer.append(result)
                    if buffer.count >= 100 {
                        if isSearcherMode { searcherResults.append(contentsOf: buffer) }
                        else { generatorResults.append(contentsOf: buffer) }
                        buffer.removeAll(keepingCapacity: true)
                    }
                case .progress(let pct):
                    if !buffer.isEmpty {
                        if isSearcherMode { searcherResults.append(contentsOf: buffer) }
                        else { generatorResults.append(contentsOf: buffer) }
                        buffer.removeAll(keepingCapacity: true)
                    }
                    searchProgressValue = pct
                }
            }
            if !buffer.isEmpty {
                if isSearcherMode { searcherResults.append(contentsOf: buffer) }
                else { generatorResults.append(contentsOf: buffer) }
            }
            searchWorkTask = nil
            searchTask = nil
        }
    }
}

// ============================================================================
// MARK: - Seed to Time View
// ============================================================================

struct SeedToTimeView: View {
    let result: StaticSearchResult
    let generation: FinderGeneration
    let tid: UInt16
    let sid: UInt16
    let method: FinderMethod
    var onUseInGenerator: ((UInt32) -> Void)?
    /// FireRed and LeafGreen: the seeds the player can hit, in place of
    /// Ruby and Sapphire's clock times.
    var frlg: FRLGSeedSearch? = nil
    /// The static encounter searched for, so its catch can calibrate the
    /// timer; nil for wild ones.
    var encounter: StaticEncounter? = nil
    var calibrates = false
    /// Goes back to the Finder. Not the environment's dismiss: on the Mac,
    /// with a screen pushed on top of this one, it changed on every update,
    /// and the page redrew until the window gave up and crashed.
    var close: () -> Void = {}

    @State private var timeResults3: [SeedToTimeResult3] = []
    @State private var timeResults4: [SeedToTimeResult4] = []
    @State private var originSeed: UInt16 = 0
    @State private var advances: UInt32 = 0
    @State private var isComputing = false

    // Verification
    @State private var showVerify = false
    @State private var verifyHP: UInt8 = 0
    @State private var verifyAtk: UInt8 = 0
    @State private var verifyDef: UInt8 = 0
    @State private var verifySpA: UInt8 = 0
    @State private var verifySpD: UInt8 = 0
    @State private var verifySpe: UInt8 = 0
    @State private var verifyNature: UInt8 = 0
    @State private var verificationResult: SeedVerificationResult?

    /// The FireRed or LeafGreen seed being calibrated.
    @State private var calibrating: FRLGInitialSeed?

    private var calibration: FRLGCalibrationContext? {
        calibrates ? FRLGCalibrationContext(method: method, tid: tid, sid: sid, encounter: encounter) : nil
    }

    var body: some View {
        ScrollView {
            CardStack {
                targetSummary
                if let frlg {
                    FRLGInitialSeedList(target: result, search: frlg, calibration: calibration,
                                        calibrating: $calibrating) { seed, preTimer, frame in
                        sendToTimerFRLG(seed, preTimer: preTimer, frame: frame)
                    }
                } else {
                    timeResultsSection
                    // FireRed and LeafGreen calibrate from each seed instead.
                    verifySection
                }
            }
            .padding()
        }
        .navigationTitle(frlg == nil ? "Seed to Time" : "Initial Seeds")
        .navigationDestination(item: $calibrating) { seed in
            if let frlg, let calibration {
                FRLGCalibrationView(target: result, attempted: seed, search: frlg, context: calibration) {
                    seed, preTimer, frame in
                    // Back past this page too, to the Timer.
                    calibrating = nil
                    sendToTimerFRLG(seed, preTimer: preTimer, frame: frame)
                }
            }
        }
        .task { if frlg == nil { await computeTimes() } }
    }

    private var targetSummary: some View {
        Group {
            SectionCard(title: "Target", icon: "target") {
                if let dtStr = result.dateTimeString {
                    LabeledContent("Date/Time", value: dtStr)
                        .font(.system(.body, design: .monospaced))
                }
                if let seedHex64 = result.seedHex64 {
                    LabeledContent("Seed", value: seedHex64)
                        .font(.system(.body, design: .monospaced))
                } else {
                    LabeledContent("Seed", value: result.seedHex)
                        .font(.system(.body, design: .monospaced))
                }
                if let t0 = result.timer0 {
                    LabeledContent("Timer0", value: "\(t0)")
                }
                if let bp = result.buttonPressName {
                    LabeledContent("Keypresses", value: bp)
                }
                LabeledContent("PID", value: result.pidHex)
                    .font(.system(.body, design: .monospaced))
                LabeledContent("IVs", value: result.ivSummary)
                    .font(.system(.body, design: .monospaced))
                LabeledContent("Nature", value: result.natureName)
                if frlg == nil {
                    LabeledContent("Advances", value: "\(result.advances)")
                }
                if result.shiny {
                    HStack {
                        Text("Shiny")
                        Spacer()
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                }

                if onUseInGenerator != nil {
                    Button {
                        onUseInGenerator?(result.seed)
                        close()
                    } label: {
                        Label("Use in Generator", systemImage: "arrow.right.circle")
                            .frame(maxWidth: .infinity).padding(8)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            if generation == .gen3 && frlg == nil {
                SectionCard(title: "Origin Seed", icon: "arrow.uturn.backward") {
                    LabeledContent("16-bit Seed", value: String(format: "%04X", originSeed))
                        .font(.system(.body, design: .monospaced))
                    LabeledContent("Advances", value: "\(advances)")
                }
            }
        }
    }

    @ViewBuilder
    private var timeResultsSection: some View {
        if isComputing {
            ProgressView("Computing times...").padding()
        }

        if generation == .gen3 && !timeResults3.isEmpty {
            gen3TimeSection
        }

        if generation == .gen4 && !timeResults4.isEmpty {
            gen4TimeSection
        }

        if generation == .gen5 {
            Text("Seed-to-time is not applicable for Gen 5.")
                .foregroundStyle(.secondary)
        } else if !isComputing && (
            (generation == .gen3 && timeResults3.isEmpty) ||
            (generation == .gen4 && timeResults4.isEmpty)
        ) {
            Text("No date/time combos found for this seed.")
                .foregroundStyle(.secondary)
        }
    }

    private var verifySection: some View {
        SectionCard(title: "Verify Catch", icon: "checkmark.shield") {
            DisclosureGroup("Enter Caught Pokemon IVs", isExpanded: $showVerify) {
                VStack(spacing: 8) {
                    IVSliderRow8(label: "HP", value: $verifyHP)
                    IVSliderRow8(label: "Attack", value: $verifyAtk)
                    IVSliderRow8(label: "Defense", value: $verifyDef)
                    IVSliderRow8(label: "Sp. Atk", value: $verifySpA)
                    IVSliderRow8(label: "Sp. Def", value: $verifySpD)
                    IVSliderRow8(label: "Speed", value: $verifySpe)

                    Picker("Nature", selection: $verifyNature) {
                        ForEach(0..<25, id: \.self) { i in
                            Text(pfNatureNames[i]).tag(UInt8(i))
                        }
                    }

                    Button {
                        verificationResult = verifySeedFromIVs(
                            caughtHP: verifyHP, caughtAtk: verifyAtk,
                            caughtDef: verifyDef, caughtSpA: verifySpA,
                            caughtSpD: verifySpD, caughtSpe: verifySpe,
                            caughtNature: verifyNature,
                            tid: tid, targetSeed: result.seed,
                            method: method
                        )
                    } label: {
                        Label("Verify", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.primaryAction)

                    if let vr = verificationResult {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Actual Seed", value: String(format: "%08X", vr.actualSeed))
                                .font(.system(.body, design: .monospaced))
                            LabeledContent("Target Seed", value: String(format: "%08X", vr.targetSeed))
                                .font(.system(.body, design: .monospaced))
                            HStack {
                                Text("Delay Delta")
                                Spacer()
                                Text("\(vr.delayDelta > 0 ? "+" : "")\(vr.delayDelta)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(vr.delayDelta == 0 ? .green : .red)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private var gen3TimeSection: some View {
        SeedToTimeListGen3(
            times: timeResults3,
            totalCount: timeResults3.count,
            onSelect: { timeText in sendToTimerGen3(advances: advances, timeText: timeText) }
        )
    }

    private var gen4TimeSection: some View {
        SeedToTimeListGen4(
            times: timeResults4,
            totalCount: timeResults4.count,
            onSelect: { delay, second, timeText in sendToTimerGen4(delay: delay, second: second, timeText: timeText) }
        )
    }

    private func computeTimes() async {
        isComputing = true
        let gen = generation
        let seedVal = result.seed
        if gen == .gen3 {
            let r = await Task.detached {
                return seedToTimeGen3(seed: seedVal)
            }.value
            originSeed = r.originSeed
            advances = r.advances
            timeResults3 = r.times
        } else {
            let r = await Task.detached {
                return seedToTimeGen4(seed: seedVal)
            }.value
            timeResults4 = r
        }
        isComputing = false
    }

    private func sendToTimerGen3(advances: UInt32, timeText: String) {
        let bridge = FinderTimerBridge.shared
        bridge.pendingGen = .gen3
        bridge.pendingTargetFrame = Int(advances)
        bridge.selectedTime = timeText
        bridge.selectedSeed = result.seedHex
        bridge.shouldSwitchToTimer = true
        close()
    }

    /// Two phases on the Gen 3 timer: the seed time, then the target frame.
    private func sendToTimerFRLG(_ seed: FRLGInitialSeed, preTimer: Int, frame: UInt32) {
        let bridge = FinderTimerBridge.shared
        bridge.pendingGen = .gen3
        bridge.pendingPreTimer = preTimer
        bridge.pendingTargetFrame = Int(frame)
        bridge.pendingCalibration = frlg?.frameCalibrationMS
        // Switch FireRed and LeafGreen run at the GBA's frame rate.
        bridge.pendingConsole = .gba
        bridge.selectedTime = "initial seed \(String(format: "%04X", seed.seed)), \(seed.settingsName)"
        bridge.selectedSeed = result.seedHex
        bridge.shouldSwitchToTimer = true
        close()
    }

    private func sendToTimerGen4(delay: Int, second: Int, timeText: String) {
        let bridge = FinderTimerBridge.shared
        bridge.pendingGen = .gen4
        bridge.pendingTargetDelay = delay
        bridge.pendingTargetSecond = second
        bridge.selectedTime = timeText
        bridge.selectedSeed = result.seedHex
        bridge.shouldSwitchToTimer = true
        close()
    }
}

// Make StaticSearchResult Hashable for navigationDestination
extension StaticSearchResult: Hashable {
    static func == (lhs: StaticSearchResult, rhs: StaticSearchResult) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// ============================================================================
// MARK: - Seed to Time List Views (extracted for type checker)
// ============================================================================

struct SeedToTimeListGen3: View {
    let times: [SeedToTimeResult3]
    let totalCount: Int
    let onSelect: (String) -> Void

    private var limited: ArraySlice<SeedToTimeResult3> {
        times.prefix(100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Date/Time Combos (\(totalCount))", systemImage: "calendar")
                .font(.headline)
            Divider()
            ForEach(limited) { t in
                SeedToTimeRow3(time: t, onSelect: onSelect)
            }
        }
        .card()
    }
}

private struct SeedToTimeRow3: View {
    let time: SeedToTimeResult3
    let onSelect: (String) -> Void
    var body: some View {
        Button { onSelect(time.displayTime) } label: {
            HStack {
                Text(time.displayTime)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Image(systemName: "timer")
                    .foregroundColor(.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SeedToTimeListGen4: View {
    let times: [SeedToTimeResult4]
    let totalCount: Int
    let onSelect: (Int, Int, String) -> Void

    private var limited: ArraySlice<SeedToTimeResult4> {
        times.prefix(100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Date/Time Combos (\(totalCount))", systemImage: "calendar")
                .font(.headline)
            Divider()
            ForEach(limited) { t in
                SeedToTimeRow4(time: t, onSelect: onSelect)
            }
        }
        .card()
    }
}

private struct SeedToTimeRow4: View {
    let time: SeedToTimeResult4
    let onSelect: (Int, Int, String) -> Void
    var body: some View {
        Button { onSelect(Int(time.delay), time.second, time.displayTime) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(time.displayTime)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .buttonStyle(.plain)
        Divider()
    }
}

// ============================================================================
// MARK: - Finder Reusable Components
// ============================================================================

struct FinderIVRangeRow: View {
    let label: String
    @Binding var min: UInt8
    @Binding var max: UInt8

    var body: some View {
        HStack(spacing: 8) {
            Text(label).lineLimit(1).scaledWidth(70, alignment: .leading)
            TextField("Min", value: $min, format: .number)
                .textFieldStyle(.roundedBorder).scaledWidth(50)
                .multilineTextAlignment(.trailing)
            Text("–")
            TextField("Max", value: $max, format: .number)
                .textFieldStyle(.roundedBorder).scaledWidth(50)
                .multilineTextAlignment(.trailing)
            Spacer()
        }
    }
}

struct FinderUInt16Field: View {
    let label: String
    @Binding var value: UInt16
    @State private var text: String = ""
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("00000", text: $text)
                .textFieldStyle(.roundedBorder).scaledWidth(100).multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onAppear { text = String(value) }
                .onChange(of: text) {
                    let filtered = String(text.prefix(5).filter { $0.isNumber })
                    if filtered != text { text = filtered }
                    if let n = UInt16(filtered), n <= 65535 {
                        value = n
                    }
                }
                .onChange(of: value) {
                    let s = String(value)
                    if text != s { text = s }
                }
        }
    }
}

struct FinderNatureGrid: View {
    @Binding var selected: Set<UInt8>

    var body: some View {
        SectionCard(title: "Nature Filter", icon: "leaf") {
            Text("Tap natures to filter (none = all)")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 6) {
                ForEach(0..<25, id: \.self) { i in
                    let idx = UInt8(i)
                    Button {
                        if selected.contains(idx) { selected.remove(idx) }
                        else { selected.insert(idx) }
                    } label: {
                        Text(pfNatureNames[i])
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 4).padding(.vertical, 3)
                            .frame(maxWidth: .infinity)
                            .background(selected.contains(idx) ? Color.accentColor : Color.gray.opacity(0.2))
                            .foregroundStyle(selected.contains(idx) ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !selected.isEmpty {
                Button("Clear All") { selected.removeAll() }
                    .font(.caption)
            }
        }
    }
}

// ============================================================================
// MARK: - Hidden Power Grid
// ============================================================================

struct FinderHiddenPowerGrid: View {
    @Binding var selected: Set<UInt8>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hidden Power (none = any)")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 6) {
                ForEach(0..<16, id: \.self) { i in
                    let idx = UInt8(i)
                    Button {
                        if selected.contains(idx) { selected.remove(idx) }
                        else { selected.insert(idx) }
                    } label: {
                        Text(hiddenPowerTypes[i])
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 4).padding(.vertical, 3)
                            .frame(maxWidth: .infinity)
                            .background(selected.contains(idx) ? hpColor(i) : Color.gray.opacity(0.2))
                            .foregroundStyle(selected.contains(idx) ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !selected.isEmpty {
                Button("Clear") { selected.removeAll() }
                    .font(.caption)
            }
        }
    }

    private func hpColor(_ index: Int) -> Color {
        switch index {
        case 0: return .orange       // Fighting
        case 1: return .cyan         // Flying
        case 2: return .purple       // Poison
        case 3: return .brown        // Ground
        case 4: return .gray         // Rock
        case 5: return .green        // Bug
        case 6: return .indigo       // Ghost
        case 7: return Color(.systemGray) // Steel
        case 8: return .red          // Fire
        case 9: return .blue         // Water
        case 10: return Color(.systemGreen) // Grass
        case 11: return .yellow      // Electric
        case 12: return .pink        // Psychic
        case 13: return .teal        // Ice
        case 14: return Color(.systemIndigo) // Dragon
        case 15: return Color(.darkGray) // Dark
        default: return .accentColor
        }
    }
}

// ============================================================================
// MARK: - Credits View
// ============================================================================

struct RNGCreditsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "dice").scaledFont(size: 48, relativeTo: .largeTitle).foregroundColor(.accentColor)
                    Text("RNG Tools").font(.title2.bold())
                    Text("Pokemon RNG manipulation utilities").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 24)

                SectionCard(title: "Timer", icon: "timer") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ported from EonTimer").font(.headline)
                        Text("by DasAmpharos (MIT License)").foregroundStyle(.secondary)
                        Text("Precision timer for Pokemon RNG manipulation. Supports Gen 3/4/5 and custom multi-phase timers with calibration. Timer phase calculations, calibration logic, console-specific framerates, and banker's rounding are faithfully ported from the TypeScript source.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("github.com/DasAmpharos/EonTimer",
                             destination: URL(string: "https://github.com/DasAmpharos/EonTimer")!)
                            .font(.caption)
                    }
                }

                SectionCard(title: "RNG Calculator", icon: "function") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ported from PokeFinder").font(.headline)
                        Text("by Admiral_Fish, bumba, and EzPzStreamz (GPLv3)").foregroundStyle(.secondary)
                        Text("IV Calculator with characteristic/hidden power filtering, IV-to-PID reverse calculator using LCRNG meet-in-the-middle attacks, and seed recovery for Method 1/2/4, XD/Colo, and Cute Charm. All algorithms are faithfully ported from the C++ source.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("github.com/Admiral-Fish/PokeFinder",
                             destination: URL(string: "https://github.com/Admiral-Fish/PokeFinder")!)
                            .font(.caption)
                    }
                }

                SectionCard(title: "FireRed and LeafGreen Initial Seeds", icon: "power") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ported from Ten Lines").font(.headline)
                        Text("by Lincoln-LM (GPLv3)").foregroundStyle(.secondary)
                        Text("The Finder's initial seeds for FireRed and LeafGreen: how each farmed seed list is laid out, the held-button offsets, seed times per console, Teachy TV, and finding the seeds that reach a target by advances. Calibration too: which seed and frame an attempt hit, from the Pokémon's nature, gender and stats, with the IV calculator. The seed lists are the RNG community's, farmed on each version and shared as public sheets.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("github.com/Lincoln-LM/ten-lines",
                             destination: URL(string: "https://github.com/Lincoln-LM/ten-lines")!)
                            .font(.caption)
                    }
                }

                SectionCard(title: "Acknowledgments", icon: "heart") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Built on research from the Pokemon RNG community, including insights from RNG Reporter, PPRNG, and 3DSRNG Tool.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("LCRNG reverse algorithms are based on meet-in-the-middle attacks and Euclidean divisor methods as described on crypto.stackexchange.com.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding()
        }
    }
}

// ============================================================================
// MARK: - Reusable Components
// ============================================================================

struct RNGIntField: View {
    let label: String
    @Binding var value: Int
    /// What the field allows; an entry outside it is clamped when it
    /// commits, so the screen shows what's used.
    var range: ClosedRange<Int>? = nil
    var body: some View {
        // At accessibility sizes the field moves under its label.
        AdaptiveStack(spacing: 6) {
            Text(label).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder).scaledWidth(100).multilineTextAlignment(.trailing)
        }
    .clamping($value, to: range)
    }
}

/// What the RNG tools' number fields allow, so an entry can't overflow the
/// search's integer types.
enum RNGFieldRange {
    static let advances = 0...Int(UInt32.max)
    static let byte = 0...Int(UInt8.max)
    static let word = 0...Int(UInt16.max)
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

extension View {
    /// Clamps a number field's value to `range` when it commits.
    func clamping(_ value: Binding<Int>, to range: ClosedRange<Int>?) -> some View {
        onChange(of: value.wrappedValue, initial: true) {
            guard let range else { return }
            let clamped = value.wrappedValue.clamped(to: range)
            if clamped != value.wrappedValue { value.wrappedValue = clamped }
        }
    }
}

struct RNGDoubleField: View {
    let label: String
    @Binding var value: Double
    var body: some View {
        // At accessibility sizes the field moves under its label.
        AdaptiveStack(spacing: 6) {
            Text(label).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder).scaledWidth(100).multilineTextAlignment(.trailing)
        }
    }
}

struct RNGOptIntField: View {
    let label: String
    @Binding var value: Int?
    var body: some View {
        // At accessibility sizes the field moves under its label.
        AdaptiveStack(spacing: 6) {
            Text(label).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("", value: $value, format: .number, prompt: Text("—"))
                .textFieldStyle(.roundedBorder).scaledWidth(100).multilineTextAlignment(.trailing)
        }
    }
}

struct IVCalcRow16: View {
    let label: String
    @Binding var stat: UInt16
    @Binding var ev: Int
    var body: some View {
        HStack(spacing: 8) {
            Text(label).lineLimit(1).scaledWidth(70, alignment: .leading)
            TextField("Stat", value: $stat, format: .number)
                .textFieldStyle(.roundedBorder).scaledWidth(70)
            Text("EV:").font(.caption).foregroundStyle(.secondary)
            TextField("EV", value: $ev, format: .number)
                .textFieldStyle(.roundedBorder).scaledWidth(60)
        }
    }
}

struct IVSliderRow: View {
    let label: String
    @Binding var value: Int
    var body: some View {
        HStack {
            Text(label).lineLimit(1).scaledWidth(70, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0) }), in: 0...31, step: 1)
            Text("\(value)").font(.system(.body, design: .monospaced)).lineLimit(1).scaledWidth(30, alignment: .trailing)
        }
    }
}

struct IVSliderRow8: View {
    let label: String
    @Binding var value: UInt8
    var body: some View {
        HStack {
            Text(label).lineLimit(1).scaledWidth(70, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { value = UInt8($0) }), in: 0...31, step: 1)
            Text("\(value)").font(.system(.body, design: .monospaced)).lineLimit(1).scaledWidth(30, alignment: .trailing)
        }
    }
}
