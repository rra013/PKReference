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

enum CustomTimerUnit: String, CaseIterable, Identifiable, Codable {
    case milliseconds = "ms"
    case advances = "Advances"
    case hex = "Seed (Hex)"
    var id: String { rawValue }
}

struct CustomPhase: Codable, Equatable {
    var unit: CustomTimerUnit
    var target: Int
    var calibration: Int

    static let defaults = [CustomPhase(unit: .milliseconds, target: 5000, calibration: 0)]

    /// The Custom timer's phases as saved; the default for none.
    static func decoded(_ data: Data) -> [CustomPhase] {
        guard let phases = try? JSONDecoder().decode([CustomPhase].self, from: data), !phases.isEmpty else {
            return defaults
        }
        return phases
    }

    static func encoded(_ phases: [CustomPhase]) -> Data {
        (try? JSONEncoder().encode(phases)) ?? Data()
    }
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

    /// PokéFinder's Gen 3 static generator has no Method 2 (it gives Method
    /// 1), so statics offer the two it has in both modes.
    static func methods(for gen: FinderGeneration, staticEncounter: Bool = false) -> [FinderMethod] {
        switch gen {
        case .gen3: return staticEncounter ? [.method1, .method4] : [.method1, .method2, .method4]
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

    /// What the picker shows: the abilities whose encounter effect is the
    /// same share a lead.
    var name: String {
        switch self {
        case .pressure: return "Pressure / Hustle / Vital Spirit"
        case .suctionCups: return "Suction Cups / Sticky Hold"
        default: return rawValue
        }
    }

    /// The leads PokéFinder's generator for this encounter reads; it ignores
    /// the rest.
    static func leads(for gen: FinderGeneration, mode: FinderRootView.EncounterMode,
                      game: FinderGameVersion) -> [FinderLead] {
        switch mode {
        case .static_:
            // Gen 3's static generator and searcher take no lead.
            return gen == .gen3 ? [.none] : [.none, .synchronize, .cuteCharmF, .cuteCharmM]
        case .underground:
            return [.none, .synchronize, .cuteCharmF, .cuteCharmM, .pressure, .compoundEyes]
        case .egg, .raid, .id:
            return [.none]
        case .wild:
            switch gen {
            case .gen3:
                // Of Gen 3, only Emerald has leads' encounter effects.
                return game == .emerald
                    ? [.none, .synchronize, .cuteCharmF, .cuteCharmM, .magnetPull, .staticLead, .pressure]
                    : [.none]
            case .gen4:
                return [.none, .synchronize, .cuteCharmF, .cuteCharmM, .magnetPull, .staticLead, .pressure,
                        .suctionCups, .compoundEyes, .arenaTrap]
            case .gen5:
                return [.none, .synchronize, .cuteCharmF, .cuteCharmM, .magnetPull, .staticLead, .pressure,
                        .suctionCups, .compoundEyes]
            case .gen8:
                return [.none, .synchronize, .cuteCharmF, .cuteCharmM, .magnetPull, .staticLead, .harvest,
                        .flashFire, .stormDrain, .pressure, .compoundEyes]
            }
        }
    }
}

/// BDSP's Grand Underground: what PokéFinder's Underground screen offers.
/// The story stage (1–6) sets which Pokémon appear and how often; the level
/// flag (0–8) sets their levels.
enum UndergroundProgress {
    static let stories = ["Underground Unlocked", "Strength Obtained", "Defog Obtained",
                          "7 Badges", "Waterfall Obtained", "National Dex"]
    static let levels = ["0/1 Badges", "2 Badges", "3 Badges", "4 Badges", "5 Badges",
                         "6 Badges", "7 Badges", "8 Badges", "National Dex"]
}

/// PokéFinder's shiny filter for a Shiny Only switch: star or square (1 | 2).
/// The games show both the same way.
nonisolated func pfShinyFilter(_ shinyOnly: Bool) -> UInt8 { shinyOnly ? 3 : 255 }

/// The most results a search keeps before it stops. One with every IV can
/// find millions: an XD shadow Pokémon with no locks finds about 270,000 a
/// second, at about 170 bytes each: the app grew by about 110 MB a second,
/// past 1.5 GB in under a minute. The lists show the first 500.
nonisolated let searchResultLimit = 100_000

/// Adds what fits under `searchResultLimit`; true once the list is full.
nonisolated func appendUpToLimit<T>(_ batch: some Collection<T>, to results: inout [T],
                                    limit: Int = searchResultLimit) -> Bool {
    results.append(contentsOf: batch.prefix(max(0, limit - results.count)))
    return results.count >= limit
}

/// Said under the Search button when a search stopped at the limit.
let searchResultLimitNote = "Stopped at \(searchResultLimit.formatted()) results. Narrow the search to find the rest."

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
    /// The game's day count: Day 1 is 1 January 2000.
    let day: Int
    let hour: Int
    let minute: Int
    /// The same day in 2000, for an emulator's clock.
    let month: Int
    let dayOfMonth: Int

    var displayTime: String { String(format: "Day %d  %02d:%02d", day, hour, minute) }

    var dateText: String {
        let components = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2000,
                                        month: month, day: dayOfMonth)
        return components.date?.formatted(.dateTime.day().month(.wide).year()) ?? ""
    }
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
                          day: RSClock.dayNumber(month: dt.month, day: dt.day), hour: dt.hour, minute: dt.minute,
                          month: dt.month, dayOfMonth: dt.day)
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
    syncNature: UInt8 = 0,
    game: PFGame = .none,
    template: PFStaticTemplateRef? = nil
) -> [StaticSearchResult] {
    var results: [StaticSearchResult] = []
    staticGenerateGen4Streaming(
        seed: seed, initialAdvance: initialAdvance, maxAdvance: maxAdvance,
        natures: natures, tid: tid, sid: sid, shinyOnly: shinyOnly,
        method: method, lead: lead, syncNature: syncNature, game: game, template: template
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
    game: PFGame = .none,
    template: PFStaticTemplateRef? = nil,
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

    // The encounter's template gives its gender; without one, every result
    // is genderless.
    let results = PFBridge.staticGenerate4(
        seed: seed, initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        method: pfMethod, lead: pfLead, template: template, tid: tid, sid: sid, game: game,
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

/// Streams PokéFinder's searcher, read every tenth of a second, as Gen 3's
/// does. `template` is the static encounter's, for its gender; without one,
/// every result is genderless. `lead` is the searcher's (Synchronize with
/// any nature).
nonisolated func staticSearchGen4Streaming(
    minIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    maxIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
    natures: Set<UInt8>,
    tid: UInt16,
    sid: UInt16,
    shinyOnly: Bool,
    method: FinderMethod,
    lead: FinderLead = .none,
    game: PFGame = .none,
    template: PFStaticTemplateRef? = nil,
    minAdvance: UInt32 = 0,
    maxAdvance: UInt32 = 0,
    minDelay: UInt16,
    maxDelay: UInt16,
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

    let handle = PFBridge.staticSearch4Start(
        minAdvance: minAdvance, maxAdvance: maxAdvance,
        minDelay: UInt32(minDelay), maxDelay: UInt32(maxDelay),
        method: pfMethod, lead: lead.pfLead, template: template, tid: tid, sid: sid, game: game,
        filterGender: filterGender, filterAbility: filterAbility,
        filterShiny: shinyFilter, ivMin: ivMin, ivMax: ivMax,
        natures: natArr, powers: hiddenPowers)
    defer { PFBridge.staticSearch4Free(handle) }

    func send(_ results: [PFSearcherState4Swift]) {
        for r in results {
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

    while !PFBridge.staticSearch4Done(handle) {
        if Task.isCancelled {
            PFBridge.staticSearch4Cancel(handle)
            return
        }
        send(PFBridge.staticSearch4Results(handle))
        onProgress(Double(PFBridge.staticSearch4Progress(handle)))
        Thread.sleep(forTimeInterval: 0.1)
    }
    send(PFBridge.staticSearch4Results(handle))
    onProgress(100)
}

// ============================================================================
// MARK: - PokeFinder Port: Static Generator (Gen 5)
// ============================================================================

nonisolated func staticGenerateGen5Streaming(
    seed: UInt64,
    initialAdvance: UInt32,
    maxAdvance: UInt32,
    ivInitialAdvance: UInt32 = 0,
    ivMaxAdvance: UInt32 = 0,
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
    staticType: Int32 = 0, staticIndex: Int32 = 0,
    onResult: (StaticSearchResult) -> Void
) {
    let pfMethod = finderMethodToPF(method)
    let pfLead = lead.pfGeneratorLead(syncNature: syncNature)
    var natArr = [Bool](repeating: natures.isEmpty, count: 25)
    for n in natures { natArr[Int(n)] = true }
    let shinyFilter: UInt8 = pfShinyFilter(shinyOnly)

    let results = PFBridge.staticGenerate5(
        seed: seed, initialAdvances: initialAdvance, maxAdvances: maxAdvance,
        ivInitialAdvances: ivInitialAdvance, ivMaxAdvances: ivMaxAdvance,
        method: pfMethod, lead: pfLead, tid: tid, sid: sid, game: game,
        staticType: staticType, staticIndex: staticIndex,
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
    ivInitialAdvance: UInt32 = 0,
    ivMaxAdvance: UInt32 = 0,
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
        ivInitialAdvances: ivInitialAdvance, ivMaxAdvances: ivMaxAdvance,
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
    diglett: Bool, storyFlag: Int32, levelFlag: UInt8 = 0,
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
        diglett: diglett, levelFlag: levelFlag,
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
    speciesFilter: UInt16, lead: FinderLead, syncNature: UInt8 = 0, deadBattery: Bool,
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
    /// Gen 3: Standard for a target counted from boot.
    var pendingGen3Mode: Gen3TimerMode?
    var pendingTargetDelay: Int?
    var pendingTargetSecond: Int?
    var shouldSwitchToTimer: Bool = false
    var selectedTime: String?
    var selectedSeed: String?
    /// Gen 4: the target's whole clock time, and whether it's
    /// HeartGold/SoulSilver (calls) or Diamond/Pearl/Platinum (coin flips).
    var pendingSeedTime: Gen4SeedTime?
    var pendingHGSS: Bool?
    /// What you hit, from checking your seed or catch, for the Timer's
    /// calibration. It doesn't replace the target.
    var pendingHit: TimerHit?

    func clear() {
        pendingGen = nil
        pendingTargetFrame = nil
        pendingPreTimer = nil
        pendingCalibration = nil
        pendingConsole = nil
        pendingGen3Mode = nil
        pendingTargetDelay = nil
        pendingTargetSecond = nil
        shouldSwitchToTimer = false
        selectedTime = nil
        selectedSeed = nil
        pendingSeedTime = nil
        pendingHGSS = nil
        pendingHit = nil
    }

    /// A Ruby, Sapphire or Emerald target: its frames, on the GBA's frame
    /// rate, and Standard mode when they count from boot.
    func sendGen3(_ start: Gen3TargetStart, time: String, seed: String) {
        pendingGen = .gen3
        pendingTargetFrame = start.frame
        pendingConsole = .gba
        pendingGen3Mode = start.fromBoot ? .standard : nil
        selectedTime = time
        selectedSeed = seed
        shouldSwitchToTimer = true
    }
}

/// What you hit, for the Timer's calibration.
struct TimerHit {
    var generation: TimerGeneration
    /// Gen 4: the delay you hit.
    var delay: Int?
    /// Gen 3: the frames you were off by (late is positive); the Timer adds
    /// it to its target frame, as the targets may count from different
    /// presses.
    var frameOffset: Int?
    /// Shown above the Timer.
    var note: String
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
/// The stat formula from Gen 3 on; EVs count a quarter (PokéFinder's
/// leaves them out: RNG catches have none).
private func pfComputeStat(baseStat: UInt16, iv: UInt8, nature: UInt8, level: UInt8, index: UInt8, ev: Int = 0) -> UInt16 {
    let stat = ((2 * UInt16(baseStat) + UInt16(iv) + UInt16(clamping: max(0, ev) / 4)) * UInt16(level)) / 100
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

/// Full IV range calculator matching PokeFinder's IVChecker::calculateIVRange,
/// with EVs for today's games (`evs` per stat, 0–252).
func pfCalculateIVRange(baseStats: [UInt8], stats: [[UInt16]], levels: [UInt8],
                         nature: UInt8, characteristic: UInt8 = 255, hiddenPower: UInt8 = 255,
                         evs: [Int] = Array(repeating: 0, count: 6)) -> [IVCalcResult] {
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
                                              nature: nature, level: levels[si], index: UInt8(i), ev: evs[i])
                    if calc == statSet[i] {
                        minIVs[i] = min(iv, minIVs[i])
                        maxIVs[i] = max(iv, maxIVs[i])
                    }
                } else {
                    // Unknown nature: check with Hardy (neutral) and also +/- 10%
                    let calc = pfComputeStat(baseStat: UInt16(baseStats[i]), iv: iv,
                                              nature: 0, level: levels[si], index: UInt8(i), ev: evs[i])
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

            // When no IV fits the stat, its range is empty: min above max.
            if minIVs[charIndex] <= maxIVs[charIndex] {
                for iv in minIVs[charIndex]...maxIVs[charIndex] {
                    if (iv % 5) == charResult {
                        if minIVs.allSatisfy({ iv >= $0 }) {
                            current[charIndex].append(iv)
                            characteristicHigh = iv
                        }
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

/// Runs the timer's phases as EonTimer does: from one start on a monotonic
/// clock, each phase ending at the start plus the phases before it, so a
/// late tick (or none, while scrolling) can't add up. Each phase ends with
/// a run of beeps, scheduled ahead on the audio engine.
@Observable
final class RNGTimerEngine {
    /// The app's timer. It outlives the Timer screen (RNG Tools rebuilds the
    /// selected tool), so it keeps running while you use the Finder, as
    /// Variable Target needs; Stop is the only way to end it.
    static let shared = RNGTimerEngine()

    private(set) var phases: [Int] = []
    private(set) var currentPhaseIndex: Int = 0
    /// What's left of the phase (ms); for an open phase (Variable Target),
    /// how long it has run.
    private(set) var remainingMs: Int = 0
    private(set) var isRunning: Bool = false

    /// EonTimer's actions: this many beeps, this far apart (ms), the last
    /// on each phase's end.
    var beepCount = 6
    var beepInterval = 500

    @ObservationIgnored private let now: () -> Double
    @ObservationIgnored private let beeper: TimerBeeper?
    @ObservationIgnored private var startTime = 0.0
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var activity: NSObjectProtocol?

    /// `now` is in seconds; tests pass a fake clock and beeper.
    init(now: @escaping () -> Double = RNGTimerClock.now, beeper: TimerBeeper? = RNGTimerSound.shared) {
        self.now = now
        self.beeper = beeper
    }

    /// Variable Target's open phase, waiting for its frame.
    var isWaitingForTarget: Bool {
        isRunning && phases.indices.contains(currentPhaseIndex) && phases[currentPhaseIndex] == Int.max
    }

    func start(phases: [Int]) {
        // Variable Target with no pre-timer ([0, open]) starts on the A
        // press that sets the seed, so an open phase is enough.
        guard phases.contains(where: { $0 == Int.max || $0 > 0 }) else { return }
        stop()
        self.phases = phases
        startTime = now()
        isRunning = true
        beeper?.prepare()
        scheduleBeeps(from: 0)
        keepAwake(true)
        let ticker = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // The common modes keep it firing while a scroll view tracks.
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
        tick()
    }

    func stop() {
        beeper?.cancelAll()
        finish()
    }

    /// Variable Target's Set Target Frame: the open phase ends `ms` after it
    /// began.
    func resolveOpenPhase(_ ms: Int) {
        guard isWaitingForTarget else { return }
        phases[currentPhaseIndex] = ms
        scheduleBeeps(from: currentPhaseIndex)
        tick()
    }

    /// Works out the phase and what's left of it from the clock alone.
    func tick() {
        guard isRunning else { return }
        let t = now()
        var phaseStart = startTime
        for (i, phase) in phases.enumerated() {
            // Only a new phase is reported, so views reading the phase (not
            // the time) don't redraw on every tick.
            if phase == Int.max {
                if currentPhaseIndex != i { currentPhaseIndex = i }
                remainingMs = Int(((t - phaseStart) * 1000).rounded())
                return
            }
            let end = phaseStart + Double(max(0, phase)) / 1000
            if t < end {
                if currentPhaseIndex != i { currentPhaseIndex = i }
                remainingMs = Int(((end - t) * 1000).rounded())
                return
            }
            phaseStart = end
        }
        // Done; the last beep is already on its way.
        finish()
    }

    var totalPhases: Int { phases.count }
    var displaySeconds: Double { Double(remainingMs) / 1000.0 }

    /// Each phase's beeps, from `index` up to an open phase: `beepCount` of
    /// them ending on its end, those after its start (as EonTimer's).
    private func scheduleBeeps(from index: Int) {
        var phaseStart = startTime
        for phase in phases[..<index] { phaseStart += Double(max(0, phase)) / 1000 }
        var times: [Double] = []
        for phase in phases[index...] {
            if phase == Int.max { break }
            let end = phaseStart + Double(max(0, phase)) / 1000
            let earliest = max(phaseStart, now())
            for j in (0..<max(0, beepCount)).reversed() {
                let time = end - Double(j * beepInterval) / 1000
                if time > earliest { times.append(time) }
            }
            phaseStart = end
        }
        if !times.isEmpty { beeper?.schedule(times) }
    }

    private func finish() {
        ticker?.invalidate()
        ticker = nil
        isRunning = false
        currentPhaseIndex = 0
        remainingMs = 0
        keepAwake(false)
    }

    /// A locked iPhone suspends the app, and App Nap slows a hidden Mac
    /// window's timers.
    private func keepAwake(_ on: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
        if on, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                             reason: "The RNG Timer is running")
        } else if !on, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
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

                if selectedTool != RNGToolTab.timer.rawValue {
                    RunningTimerBar(engine: .shared) { selectedTool = RNGToolTab.timer.rawValue }
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
            // `-debugOpenSheet gameCubeSearch`: the GameCube tab, then a search.
            .task { await DebugSnapshot.openSheet("gameCubeSearch") { selectedTool = RNGToolTab.gamecube.rawValue } }
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

/// The running timer's time and phase. Its own view, so ticking redraws
/// only this.
struct RNGTimerReadout: View {
    let engine: RNGTimerEngine

    var body: some View {
        VStack(spacing: 8) {
            Text(String(format: "%.3f", engine.displaySeconds))
                .scaledFont(size: 64, weight: .bold, design: .monospaced, relativeTo: .largeTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(engine.isRunning ? .primary : .secondary)
                .contentTransition(.numericText())

            if engine.isWaitingForTarget {
                Text("Time since the seed was set. Once you know which seed you hit, enter its target frame and set it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if engine.isRunning && engine.totalPhases > 1 {
                Text("Phase \(engine.currentPhaseIndex + 1) of \(engine.totalPhases)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Shown above the other RNG tools while the timer runs: its time, and a way
/// back to it (Variable Target is set in the Timer once the Finder has found
/// the frame).
struct RunningTimerBar: View {
    let engine: RNGTimerEngine
    let open: () -> Void

    var body: some View {
        if engine.isRunning {
            Button(action: open) {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                    Text(String(format: "%.3f", engine.displaySeconds))
                        .font(.system(.body, design: .monospaced).bold())
                    Text(engine.isWaitingForTarget ? "since the seed" :
                            "phase \(engine.currentPhaseIndex + 1) of \(engine.totalPhases)")
                        .font(.caption)
                    Spacer()
                    Text("Timer").font(.caption.bold())
                    Image(systemName: "chevron.right").font(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 6)
        }
    }
}

// ============================================================================
// MARK: - RNG Timer View
// ============================================================================

struct RNGTimerView: View {
    private let engine = RNGTimerEngine.shared
    // Saved, as EonTimer saves them: RNG Tools rebuilds the selected tool,
    // so going to the Finder and back reset everything.
    @AppStorage("timer_generation") private var generation: TimerGeneration = .gen5
    @AppStorage("timer_console") private var consoleType: RNGConsole = .ndsSlot1
    @AppStorage("timer_customFramerate") private var customFramerate: Double = 60.0
    @AppStorage("timer_precisionCalibration") private var precisionCalibration = false
    /// EonTimer's action count and interval (ms).
    @AppStorage("timer_beepCount") private var beepCount = 6
    @AppStorage("timer_beepInterval") private var beepInterval = 500

    // Gen 3
    @AppStorage("timer_gen3Mode") private var gen3Mode: Gen3TimerMode = .standard
    @AppStorage("timer_gen3PreTimer") private var gen3PreTimer = 5000
    @AppStorage("timer_gen3TargetFrame") private var gen3TargetFrame = 1000
    @AppStorage("timer_gen3Calibration") private var gen3Calibration = 0
    @State private var gen3FrameHit = 0

    // Gen 4 (defaults from EonTimer store)
    @AppStorage("timer_gen4TargetDelay") private var gen4TargetDelay = 600
    @AppStorage("timer_gen4TargetSecond") private var gen4TargetSecond = 50
    @AppStorage("timer_gen4CalibratedDelay") private var gen4CalibratedDelay = 500
    @AppStorage("timer_gen4CalibratedSecond") private var gen4CalibratedSecond = 14
    @State private var gen4DelayHit = 0
    /// The last Gen 4 target's whole clock time, from the Finder, for
    /// checking the seed you hit.
    @AppStorage("timer_gen4SeedTime") private var gen4SeedTimeData = Data()
    @AppStorage("timer_gen4HGSS") private var gen4HGSS = false
    @State private var checkingSeed = false

    // Gen 5 (defaults from EonTimer store)
    @AppStorage("timer_gen5Mode") private var gen5Mode: Gen5TimerMode = .standard
    @AppStorage("timer_gen5TargetDelay") private var gen5TargetDelay = 1200
    @AppStorage("timer_gen5TargetSecond") private var gen5TargetSecond = 50
    @AppStorage("timer_gen5TargetAdvances") private var gen5TargetAdvances = 100
    @AppStorage("timer_gen5Calibration") private var gen5Calibration = -95
    @AppStorage("timer_gen5EntralinkCalibration") private var gen5EntralinkCalibration = 256
    @AppStorage("timer_gen5FrameCalibration") private var gen5FrameCalibration = 0
    @State private var gen5DelayHit: Int?
    @State private var gen5SecondHit: Int?
    @State private var gen5AdvancesHit: Int?

    /// The target last handed off from the Finder; empty for none.
    @AppStorage("timer_reminder") private var reminderText = ""

    /// Variable Target's frame, as typed. Text, so Set Target Frame reads
    /// what's in the field: a number field commits only when it loses focus,
    /// which tapping a button doesn't do, so it used the old frame.
    @State private var variableTargetText = ""
    @State private var variableTargetNote: String?
    @FocusState private var variableTargetFocused: Bool

    // Custom
    @AppStorage("timer_customPhases") private var customPhasesData = Data()
    private var customPhases: [CustomPhase] {
        get { CustomPhase.decoded(customPhasesData) }
        nonmutating set { customPhasesData = CustomPhase.encoded(newValue) }
    }

    private var settings: CalibratorSettings {
        CalibratorSettings(console: consoleType, customFramerate: customFramerate,
                           precisionCalibration: precisionCalibration, minimumLength: EONTIMER_MINIMUM_LENGTH)
    }

    var body: some View {
        ScrollView {
            CardStack {
                // While running, it's pinned above (`runningPanel`).
                if !engine.isRunning {
                    timerDisplay
                }

                if !reminderText.isEmpty {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text(reminderText)
                            .font(.callout)
                        Spacer()
                        Button {
                            reminderText = ""
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

                // As EonTimer, the settings hold still while it runs; the
                // running timer has its phases already.
                Group {
                    Picker("Generation", selection: $generation) {
                        ForEach(TimerGeneration.allCases) { gen in
                            Text(gen.rawValue).tag(gen)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

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

                    beepSettings
                }
                .disabled(engine.isRunning)

                if !engine.isRunning {
                    Button {
                        startTimer()
                    } label: {
                        Label("Start Timer", systemImage: "play.fill")
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(computePhases().isEmpty)
                }

                // Phase preview
                let phases = computePhases()
                if !phases.isEmpty && !engine.isRunning {
                    SectionCard(title: "Phase Preview", icon: "list.number") {
                        ForEach(Array(phases.enumerated()), id: \.offset) { i, ms in
                            HStack {
                                Text("Phase \(i + 1)")
                                Spacer()
                                if ms == Int.max {
                                    Text("From the seed until you set the frame")
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
        .dismissesKeyboard()
        // The countdown and Stop stay in view while it runs; Start is at the
        // bottom, below the settings.
        .safeAreaInset(edge: .top, spacing: 0) {
            if engine.isRunning { runningPanel }
        }
        .sheet(isPresented: $checkingSeed) {
            NavigationStack {
                Gen4SeedCheckView(target: seedCheckTarget, heartGoldSoulSilver: gen4HGSS) { candidate in
                    gen4DelayHit = candidate.delay
                    reminderText = "You hit delay \(candidate.delay)" + hitOffsetText(candidate.delayOffset)
                        + ". Tap Update Calibration."
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { checkingSeed = false }
                    }
                }
            }
            .sheetSize()
        }
        #if DEBUG && os(macOS)
        // `-debugOpenSheet timerRunning` starts it, for a snapshot of the
        // running panel (pass `-timer_beepCount 0` to keep it quiet).
        .task { await DebugSnapshot.openSheet("timerRunning") { startTimer() } }
        #endif
        .onAppear {
            let bridge = FinderTimerBridge.shared
            if let hit = bridge.pendingHit {
                takeHit(hit)
                bridge.clear()
            }
            if let gen = bridge.pendingGen {
                // A new target replaces the running timer, whose phases are
                // the old target's.
                engine.stop()
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
                if gen == .gen3, let mode = bridge.pendingGen3Mode {
                    gen3Mode = mode
                }
                if let console = bridge.pendingConsole {
                    consoleType = console
                } else if gen != .gen3 && consoleType == .gba {
                    // Left over from a GBA target: DS games don't run on one.
                    consoleType = .ndsSlot1
                }
                if gen == .gen4 {
                    if let delay = bridge.pendingTargetDelay {
                        gen4TargetDelay = delay
                    }
                    if let second = bridge.pendingTargetSecond {
                        gen4TargetSecond = second
                    }
                    gen4SeedTimeData = bridge.pendingSeedTime?.encoded ?? Data()
                    if let hgss = bridge.pendingHGSS { gen4HGSS = hgss }
                }
                if let time = bridge.selectedTime {
                    let seed = bridge.selectedSeed ?? "?"
                    reminderText = "Seed \(seed) — \(time)"
                } else {
                    reminderText = ""
                }
                bridge.clear()
            }
        }
    }

    /// The Gen 4 target to check around: the clock time the Finder handed
    /// over, with the target delay and second as they are now.
    private var seedCheckTarget: Gen4SeedTime {
        var target = Gen4SeedTime.decoded(gen4SeedTimeData) ?? Gen4SeedTime()
        target.delay = gen4TargetDelay
        target.second = gen4TargetSecond
        return target
    }

    /// What you hit, from the Finder: Gen 4's delay, Gen 3's frames off.
    private func takeHit(_ hit: TimerHit) {
        generation = hit.generation
        if let delay = hit.delay { gen4DelayHit = delay }
        if let offset = hit.frameOffset { gen3FrameHit = gen3TargetFrame + offset }
        reminderText = hit.note
    }

    private func hitOffsetText(_ offset: Int) -> String {
        offset == 0 ? ", the target" : offset > 0 ? ", \(offset) late" : ", \(-offset) early"
    }

    private func startTimer() {
        engine.beepCount = beepCount
        engine.beepInterval = beepInterval
        variableTargetText = ""
        variableTargetNote = nil
        engine.start(phases: computePhases())
    }

    /// Ends the open phase on the typed frame, measured from the seed. A
    /// frame already passed is refused, not run (the timer would just end).
    private func setVariableTarget() {
        guard let frame = Int(variableTargetText.filter(\.isNumber)) else { return }
        let ms = createFramePhase(settings, targetFrame: frame, calibration: gen3Calibration)
        guard ms > engine.remainingMs else {
            variableTargetNote = "Frame \(frame.formatted()) is \(String(format: "%.3f", Double(ms) / 1000)) s from the seed, which has passed."
            return
        }
        variableTargetFocused = false
        variableTargetNote = nil
        gen3TargetFrame = frame
        engine.resolveOpenPhase(ms)
    }

    /// Pinned above the settings while running.
    private var runningPanel: some View {
        VStack(spacing: 10) {
            timerReadout
            // EonTimer's Variable Target: the open phase runs until you've
            // seen the frame and set it.
            if engine.isWaitingForTarget && generation == .gen3 {
                HStack {
                    Text("Target Frame")
                    Spacer()
                    TextField("Frame", text: $variableTargetText)
                        .textFieldStyle(.roundedBorder).scaledWidth(120)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .focused($variableTargetFocused)
                        .onSubmit(setVariableTarget)
                }
                Button("Set Target Frame", action: setVariableTarget)
                    .buttonStyle(.bordered)
                    .disabled(Int(variableTargetText.filter(\.isNumber)) == nil)
                if let variableTargetNote {
                    Text(variableTargetNote)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                engine.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.primaryAction)
            .tint(.red)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var beepSettings: some View {
        SectionCard(title: "Beeps", icon: "speaker.wave.2") {
            Text("A run of beeps ends on each target: press on the last one.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            RNGIntField(label: "Beeps", value: $beepCount, range: 0...20)
            RNGIntField(label: "Interval (ms)", value: $beepInterval, range: 100...2000)
            Button {
                RNGTimerSound.shared.beepNow()
            } label: {
                Label("Test Beep", systemImage: "speaker.wave.2")
            }
        }
    }

    private var timerDisplay: some View {
        timerReadout
            .padding(.vertical, 8)
            .card()
    }

    private var timerReadout: some View {
        RNGTimerReadout(engine: engine)
    }

    // MARK: Gen Settings

    private var gen3Settings: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $gen3Mode) {
                ForEach(Gen3TimerMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            Text(gen3Mode == .standard
                 ? "For a seed you know in advance: the pre-timer, then the target frame."
                 : "For a seed you only learn in game, from your Trainer ID or a Pokémon's IVs. The pre-timer ends on the A press that sets the seed (0 if you start the timer on that press); the timer then counts from it until you set the target frame.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                    LiveIntField("Value", value: Binding(
                        get: { customPhases[i].target },
                        set: { customPhases[i].target = $0 }
                    ))
                    .textFieldStyle(.roundedBorder).scaledWidth(80)

                    Picker("", selection: Binding(
                        get: { customPhases[i].unit },
                        set: { customPhases[i].unit = $0 }
                    )) {
                        ForEach(CustomTimerUnit.allCases) { u in Text(u.rawValue).tag(u) }
                    }.scaledWidth(100)

                    LiveIntField("Cal", value: Binding(
                        get: { customPhases[i].calibration },
                        set: { customPhases[i].calibration = $0 }
                    ))
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
                Text("Enter the delay you hit. To find it, check your seed right after loading: the Pokétch's coin flips, or the roamers and Elm's or Irwin's calls.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    checkingSeed = true
                } label: {
                    Label("Check Your Seed", systemImage: "checkmark.seal")
                }
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
    @State private var searched = false

    var body: some View {
        ScrollView {
            CardStack {
                SectionCard(title: "IVs", icon: "number.square") {
                    IVField(label: "HP", value: $hp)
                    IVField(label: "Attack", value: $atk)
                    IVField(label: "Defense", value: $def)
                    IVField(label: "Sp. Atk", value: $spa)
                    IVField(label: "Sp. Def", value: $spd)
                    IVField(label: "Speed", value: $spe)
                }

                SectionCard(title: "Trainer Info", icon: "person") {
                    LabeledContent("Nature") {
                        Picker("Nature", selection: $nature) {
                            ForEach(0..<25, id: \.self) { Text(pfNatureNames[$0]).tag(UInt8($0)) }
                        }
                        .labelsHidden()
                    }
                    HStack {
                        Text("Trainer ID")
                        Spacer()
                        LiveIntField(value: $tid, grouping: false)
                            .textFieldStyle(.roundedBorder).scaledWidth(80)
                    }
                }

                Button {
                    results = LCRNGReverse.calculatePIDs(hp: hp, atk: atk, def: def,
                                                          spa: spa, spd: spd, spe: spe,
                                                          nature: nature, tid: tid)
                    searched = true
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
                } else if searched {
                    Text("No PIDs give these IVs with this nature.").foregroundStyle(.secondary)
                }
            }.padding()
        }
        .dismissesKeyboard()
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
                    IVField(label: "HP", value: $ivHP)
                    IVField(label: "Attack", value: $ivAtk)
                    IVField(label: "Defense", value: $ivDef)
                    IVField(label: "Sp. Atk", value: $ivSpAtk)
                    IVField(label: "Sp. Def", value: $ivSpDef)
                    IVField(label: "Speed", value: $ivSpeed)
                }

                SectionCard(title: "Hidden Power", icon: "questionmark.diamond") {
                    HStack {
                        Text("Type"); Spacer()
                        Text(hpType).bold().padding(.horizontal, 12).padding(.vertical, 4)
                            .background(TypePalette.fill(for: hpType).opacity(0.2)).clipShape(Capsule())
                    }
                    HStack {
                        Text("Base Power (Gen 3–5)"); Spacer()
                        Text("\(hpPower)").bold().font(.system(.body, design: .monospaced))
                    }
                    Text("From Gen 6 on, Hidden Power always has 60 base power.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                SectionCard(title: "Common Hidden Power IVs", icon: "table") {
                    VStack(spacing: 6) {
                        ForEach(Self.presets, id: \.type) { preset in
                            hpPreset(preset.type, ivs: preset.ivs.map(String.init).joined(separator: "/"))
                        }
                    }
                }
            }.padding()
        }
        .dismissesKeyboard()
    }

    /// HP/Atk/Def/SpA/SpD/Spe.
    static let presets: [(type: String, ivs: [Int])] = [
        ("Fire", [31, 30, 31, 30, 31, 30]),
        ("Ice", [31, 30, 30, 31, 31, 31]),
        ("Grass", [31, 30, 31, 30, 31, 31]),
        ("Electric", [31, 31, 31, 30, 31, 31]),
        ("Ground", [31, 31, 31, 30, 30, 31]),
        ("Fighting", [31, 31, 30, 30, 30, 30]),
        ("Flying", [30, 30, 30, 30, 30, 31]),
    ]

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
                // PokéFinder's Gen 8 static, wild, egg and ID generators are
                // BDSP's, and its Sword/Shield areas are BDSP's under other
                // names: only raids are Sword/Shield's own.
                return game.isSwSh ? [.raid] : [.static_, .wild, .egg, .underground, .id]
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
    @AppStorage("finder_deadBattery") private var deadBattery: Bool = false

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
    /// PokéFinder's story stage, 1–6 (`UndergroundProgress.stories`).
    @AppStorage("finder_gen8storyStage") private var gen8StoryStage: Int = 1
    /// PokéFinder's level flag, 0–8 (`UndergroundProgress.levels`).
    @AppStorage("finder_gen8levelFlag") private var gen8LevelFlag: Int = 0

    // Gen 8 ID filter parameters
    @AppStorage("finder_gen8filterTID") private var gen8FilterTIDText: String = ""
    @AppStorage("finder_gen8filterSID") private var gen8FilterSIDText: String = ""
    @AppStorage("finder_gen8filterDisplayTID") private var gen8FilterDisplayTIDText: String = ""

    /// Gen 4: checking which seed near the Generator's you hit.
    @State private var checkingSeed = false
    /// Gen 3: the Generator's seed from a Trainer ID, or a caught Pokémon.
    @State private var seedTrainerIDText = ""
    @State private var findingSeedFromPokemon = false

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
    /// The last search stopped at `searchResultLimit`.
    @State private var stoppedAtLimit = false
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
                                // Its method is the template's (Method J
                                // for Diamond, Pearl and Platinum's legends).
                                .onChange(of: selectedEncounter) {
                                    if let encounterMethod = selectedEncounter?.method,
                                       availableMethods.contains(encounterMethod) {
                                        method = encounterMethod
                                    }
                                }
                            }
                        }

                        if let enc = selectedEncounter {
                            encounterInfoCard(enc)
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

                // Method and lead, where there's a choice (not Gen 8's one
                // method, nor its eggs, raids and TID/SID)
                if encounterMode != .id && (availableMethods.count > 1 || leadApplies) {
                    SectionCard(title: availableMethods.count > 1 ? "Method" : "Lead", icon: "cpu") {
                    if availableMethods.count > 1 {
                        Picker("Method", selection: $method) {
                            ForEach(availableMethods) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                    }

                    // Only where PokéFinder reads one: not Gen 3 statics, nor
                    // Ruby, Sapphire, FireRed and LeafGreen.
                    if leadApplies {
                        Picker("Lead Ability", selection: $lead) {
                            ForEach(availableLeads) { l in
                                Text(l.name).tag(l)
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

                    // Emerald boots on seed 0000 either way.
                    if generation == .gen3 && (selectedGame == .ruby || selectedGame == .sapphire) {
                        Toggle("Dead Battery", isOn: $deadBattery)
                            .font(.subheadline)
                            .onChange(of: deadBattery) {
                                // Every boot starts on 05A0, as PokéFinder's Generators take it.
                                if deadBattery { genSeedText = "05A0" }
                            }
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
                    .disabled(needsStaticEncounter)
                    if stoppedAtLimit {
                        Text(searchResultLimitNote)
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if needsStaticEncounter {
                        Text("Choose the Pokémon under Encounter: Gen 5 and 8 searches need its template.")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                           tid: tid, sid: sid, method: method, game: selectedGame,
                           fromGenerator: mode == .generator, deadBattery: deadBattery,
                           staticTarget: encounterMode == .static_, onUseInGenerator: { seed in
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
        .onAppear { fixStoredSelections() }
        .sheet(isPresented: $findingSeedFromPokemon) {
            NavigationStack {
                Gen3SeedFromPokemonView(method: method, tid: tid,
                                        template: encounterMode == .static_ ? selectedEncounter?.template : nil,
                                        level: encounterMode == .static_ ? selectedEncounter.map { Int($0.level) } : nil) { origin in
                    genSeedText = String(format: "%04X", origin.seed)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { findingSeedFromPokemon = false }
                    }
                }
            }
            .sheetSize()
        }
        .sheet(isPresented: $checkingSeed) {
            NavigationStack {
                Gen4SeedCheckView(target: Gen4SeedTime(), bareSeed: UInt32(genSeedText, radix: 16) ?? 0,
                                  heartGoldSoulSilver: selectedGame == .heartGold || selectedGame == .soulSilver) { candidate in
                    let bridge = FinderTimerBridge.shared
                    bridge.pendingHit = TimerHit(generation: .gen4, delay: candidate.delay,
                                                 note: "You hit delay \(candidate.delay) (seed \(String(format: "%08X", candidate.seed))). Tap Update Calibration.")
                    bridge.shouldSwitchToTimer = true
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { checkingSeed = false }
                    }
                }
            }
            .sheetSize()
        }
        .onChange(of: generation) { fixLead() }
        .onChange(of: encounterMode) { fixLead() }
        .onChange(of: selectedGame) { fixLead() }
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

    private var availableLeads: [FinderLead] {
        FinderLead.leads(for: generation, mode: encounterMode, game: selectedGame)
    }

    private var leadApplies: Bool { availableLeads.count > 1 }

    private var availableMethods: [FinderMethod] {
        FinderMethod.methods(for: generation, staticEncounter: encounterMode == .static_)
    }

    private func fixLead() {
        if !availableLeads.contains(lead) { lead = .none }
    }

    /// Stored choices the current game no longer offers (Sword/Shield's
    /// Static, or Method 2 for a Gen 3 static), as changing the game would.
    private func fixStoredSelections() {
        let modes = EncounterMode.modes(for: generation, game: selectedGame)
        if !modes.contains(encounterMode) { encounterMode = modes[0] }
        if !availableMethods.contains(method) { autoSelectMethod() }
        fixLead()
        // The story picker offered 0 ("Pre-National Dex") and 1 ("Post-
        // National Dex"); PokéFinder's stages are 1–6.
        let defaults = UserDefaults.standard
        if let oldFlag = defaults.object(forKey: "finder_gen8storyFlag") as? Int {
            gen8StoryStage = oldFlag == 1 ? UndergroundProgress.stories.count : 1
            defaults.removeObject(forKey: "finder_gen8storyFlag")
        }
    }

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

    /// What the chosen encounter's template sets: its method, shiny lock and
    /// fixed IVs.
    private func encounterInfoCard(_ encounter: StaticEncounter) -> some View {
        let notes = [selectedGame.rawValue, encounter.method?.rawValue,
                     encounter.shinyLocked ? "shiny-locked" : nil,
                     encounter.fixedIVs > 0 ? "\(encounter.fixedIVs) IVs of 31" : nil].compactMap { $0 }
        return HStack(spacing: 8) {
            Image(systemName: "target")
                .foregroundStyle(.orange)
            Text("\(encounter.speciesName) Lv\(encounter.level)")
                .font(.callout).bold()
            Text("(\(notes.joined(separator: ", ")))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Gen 5 and 8's static searches need the Pokémon's template.
    private var needsStaticEncounter: Bool {
        encounterMode == .static_ && (generation == .gen5 || generation == .gen8) && selectedEncounter == nil
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
                IVField(label: statNames[i], value: Binding(
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
                IVField(label: statNames[i], value: Binding(
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
                LiveIntField("0", value: $gen8RaidDen)
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
                LiveIntField("0", value: $gen8RaidIndex)
                    .textFieldStyle(.roundedBorder)
                    .scaledWidth(80)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Level")
                Spacer()
                LiveIntField("60", value: $gen8RaidLevel)
                    .textFieldStyle(.roundedBorder)
                    .scaledWidth(80)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var gen8UndergroundParametersView: some View {
        VStack(spacing: 8) {
            Toggle("Diglett Bonus", isOn: $gen8Diglett)
            // Labelled: on iOS a menu shows only its value.
            LabeledContent("Story Progress") {
                Picker("Story Progress", selection: $gen8StoryStage) {
                    ForEach(Array(UndergroundProgress.stories.enumerated()), id: \.offset) { i, name in
                        Text(name).tag(i + 1)
                    }
                }
                .labelsHidden()
            }
            LabeledContent("Levels") {
                Picker("Levels", selection: $gen8LevelFlag) {
                    ForEach(Array(UndergroundProgress.levels.enumerated()), id: \.offset) { i, name in
                        Text(name).tag(i)
                    }
                }
                .labelsHidden()
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

    /// Gen 3 seeds only learnt in game (Variable Target): a new game's is
    /// its Trainer ID, and a caught Pokémon leads back to one.
    @ViewBuilder
    private var gen3SeedSources: some View {
        HStack {
            Text("From Trainer ID")
            Spacer()
            TextField("New game", text: $seedTrainerIDText)
                .textFieldStyle(.roundedBorder).scaledWidth(110)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Use") {
                if let id = UInt16(seedTrainerIDText.filter(\.isNumber)) { genSeedText = Gen3SeedFinder.seed(trainerID: id) }
            }
            .disabled(UInt16(seedTrainerIDText.filter(\.isNumber)) == nil)
        }
        Button {
            findingSeedFromPokemon = true
        } label: {
            Label("From a Pokémon You Caught", systemImage: "magnifyingglass")
        }
        Text("A new game seeds the RNG with the Trainer ID it makes; a Pokémon's nature and IVs lead back to its seed.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

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
                if generation == .gen3 {
                    gen3SeedSources
                }
            }
            if generation == .gen5 {
                // Gen 5 draws IVs and the PID from separate RNGs; PokéFinder
                // pairs each PID advance with each IV one.
                RNGIntField(label: "Initial PID Advance", value: $genInitAdvance, range: RNGFieldRange.advances)
                RNGIntField(label: "Max PID Advance", value: $genMaxAdvance, range: RNGFieldRange.advances)
                RNGIntField(label: "Min IV Advance", value: $gen5IVMinAdvance, range: RNGFieldRange.advances)
                RNGIntField(label: "Max IV Advance", value: $gen5IVMaxAdvance, range: RNGFieldRange.advances)
            } else {
                RNGIntField(label: "Initial Advance", value: $genInitAdvance, range: RNGFieldRange.advances)
                RNGIntField(label: "Max Advance", value: $genMaxAdvance, range: RNGFieldRange.advances)
            }
        }
    }

    private var seedVerificationSection: some View {
        let seed = UInt32(genSeedText, radix: 16) ?? 0
        return SectionCard(title: "Seed Verification", icon: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    checkingSeed = true
                } label: {
                    Label("Check Which Seed You Hit", systemImage: "checkmark.seal")
                }
                Text("Near this seed, from the coin flips, roamers or calls after loading. A target from the Searcher's Seed to Time checks its own clock time in the Timer.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
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
        stoppedAtLimit = false

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
        let isDeadBattery = deadBattery && (selectedGame == .ruby || selectedGame == .sapphire)

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
        let g8StoryFlag = Int32(gen8StoryStage.clamped(to: 1...UndergroundProgress.stories.count))
        let g8LevelFlag = UInt8(gen8LevelFlag.clamped(to: 0...(UndergroundProgress.levels.count - 1)))

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
        // The static encounter's place in PokéFinder's tables, for its
        // template: gender, shiny lock, fixed IVs.
        let staticTemplate: PFStaticTemplateRef? = encMode == .static_
            ? selectedEncounter.flatMap { $0.generation == gen ? $0.template : nil } : nil
        let gen3Template = gen == .gen3 ? staticTemplate : nil
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
                    diglett: g8Diglett, storyFlag: g8StoryFlag, levelFlag: g8LevelFlag,
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
                        ivInitialAdvance: g5IVMinAdv, ivMaxAdvance: g5IVMaxAdv,
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
                                  lead: ld, syncNature: sNat, deadBattery: isDeadBattery,
                                  filterGender: genderFilter, filterAbility: abilityFilter,
                                  hiddenPowers: hpFilter,
                                  onResult: { continuation.yield(.result($0)) },
                                  onProgress: { continuation.yield(.progress($0)) })
                }
            } else if m == .searcher {
                if gen == .gen5 {
                    // Gen 5 needs the Pokémon: the Finder doesn't search
                    // without one.
                    if let staticTemplate {
                        staticSearchGen5Streaming(
                            initialAdvance: srcMinAdv, maxAdvance: srcMaxAdv,
                            ivInitialAdvance: g5IVMinAdv, ivMaxAdvance: g5IVMaxAdv,
                            natures: natFilter, tid: tID, sid: sID, shinyOnly: shiny,
                            method: meth, lead: ld, syncNature: sNat, game: pfGameVal,
                            staticType: staticTemplate.type, staticIndex: staticTemplate.index,
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
                    }
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
                        lead: ld, game: pfGameVal, template: staticTemplate,
                        minAdvance: srcMinAdv, maxAdvance: srcMaxAdv,
                        minDelay: delMin, maxDelay: delMax,
                        filterGender: genderFilter, filterAbility: abilityFilter,
                        hiddenPowers: hpFilter,
                        onProgress: { continuation.yield(.progress($0)) }
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
                    // Gen 5 and 8 need the Pokémon: the Finder doesn't
                    // generate without one.
                    if let staticTemplate {
                        staticGenerateGen5Streaming(
                            seed: seedVal64, initialAdvance: initAdv, maxAdvance: maxAdv,
                            ivInitialAdvance: g5IVMinAdv, ivMaxAdvance: g5IVMaxAdv,
                            natures: natFilter, tid: tID, sid: sID, shinyOnly: shiny,
                            method: meth, lead: ld, syncNature: sNat, game: pfGameVal,
                            mac: g5Mac, keypresses: g5Keys,
                            vcount: g5VCount, gxstat: g5GxStat, vframe: g5VFrame,
                            skipLR: g5SkipLR, timer0Min: g5Timer0Min, timer0Max: g5Timer0Max,
                            memoryLink: g5MemoryLink, shinyCharm: g5ShinyCharm,
                            dsType: g5DSType, language: g5Language,
                            filterGender: genderFilter, filterAbility: abilityFilter,
                            hiddenPowers: hpFilter,
                            staticType: staticTemplate.type, staticIndex: staticTemplate.index
                        ) { continuation.yield(.result($0)) }
                    }
                } else if gen == .gen8 {
                    if let staticTemplate {
                        staticGenerateGen8Streaming(
                            seed0: g8Seed0, seed1: g8Seed1,
                            initialAdvance: initAdv, maxAdvance: maxAdv,
                            natures: natFilter, tid: tID, sid: sID,
                            shinyOnly: shiny, lead: ld, syncNature: sNat, game: pfGameVal,
                            shinyCharm: g8ShinyCharm,
                            staticType: staticTemplate.type, staticIndex: staticTemplate.index,
                            filterGender: genderFilter, filterAbility: abilityFilter,
                            hiddenPowers: hpFilter
                        ) { continuation.yield(.result($0)) }
                    }
                } else {
                    staticGenerateGen4Streaming(
                        seed: seedVal, initialAdvance: initAdv,
                        maxAdvance: maxAdv,
                        natures: natFilter, tid: tID, sid: sID,
                        shinyOnly: shiny, method: meth,
                        lead: ld, syncNature: sNat, game: pfGameVal, template: staticTemplate,
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
                    guard buffer.count >= 100 else { continue }
                case .progress(let pct):
                    searchProgressValue = pct
                }
                let full = keep(buffer, searcher: isSearcherMode)
                buffer.removeAll(keepingCapacity: true)
                if full {
                    stopSearch()
                    stoppedAtLimit = true
                    return
                }
            }
            // Stopping already cleared these, maybe for the next search,
            // whose list the rest of this one's would land in.
            guard !Task.isCancelled else { return }
            stoppedAtLimit = keep(buffer, searcher: isSearcherMode)
            searchWorkTask = nil
            searchTask = nil
        }
    }

    /// Adds a batch to the list being filled; true once it's full.
    private func keep(_ batch: [StaticSearchResult], searcher: Bool) -> Bool {
        searcher ? appendUpToLimit(batch, to: &searcherResults) : appendUpToLimit(batch, to: &generatorResults)
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
    /// The game searched, for what's checked after hitting the target.
    var game: FinderGameVersion? = nil
    /// The Generator's result, whose frames count from its seed.
    var fromGenerator = false
    var deadBattery = false
    /// A static encounter (wild ones generate differently).
    var staticTarget = false
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
    /// Gen 3 (not FireRed and LeafGreen's seed list): where the target's
    /// frames count from.
    @State private var gen3Start: Gen3TargetStart?
    @State private var isComputing = false

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
                    afterHittingSection
                }
            }
            .padding()
        }
        .dismissesKeyboard()
        .navigationTitle(frlg != nil ? "Initial Seeds" : generation == .gen3 && gen3Start?.kind != .clock ? "Target" : "Seed to Time")
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

            if generation == .gen3, let gen3Start {
                gen3StartCard(gen3Start)
            }
        }
    }

    @ViewBuilder
    private var timeResultsSection: some View {
        if isComputing {
            ProgressView("Computing times...").padding()
        }

        if generation == .gen3 && gen3Start?.kind == .clock && !timeResults3.isEmpty {
            gen3TimeSection
        }

        if generation == .gen4 && !timeResults4.isEmpty {
            gen4TimeSection
        }

        if generation == .gen5 {
            Text("Seed-to-time is not applicable for Gen 5.")
                .foregroundStyle(.secondary)
        } else if !isComputing && (
            (generation == .gen3 && gen3Start?.kind == .clock && timeResults3.isEmpty) ||
            (generation == .gen4 && timeResults4.isEmpty)
        ) {
            Text("No date/time combos found for this seed.")
                .foregroundStyle(.secondary)
        }
    }

    /// What tells you what you hit: Gen 3 from the catch, Gen 4 from the
    /// seed check in the Timer.
    @ViewBuilder
    private var afterHittingSection: some View {
        if generation == .gen3 && staticTarget {
            Gen3WhatYouHitCard(target: result, fromGenerator: fromGenerator, suggestedInitialSeed: gen3InitialSeed,
                               method: method, template: encounter?.template, level: encounter.map { Int($0.level) },
                               game: game?.pfGame ?? .none, tid: tid, sid: sid) { hit in
                let bridge = FinderTimerBridge.shared
                bridge.pendingHit = hit
                bridge.shouldSwitchToTimer = true
                close()
            }
        } else if generation == .gen4 {
            SectionCard(title: "After You Hit It", icon: "checkmark.seal") {
                Text("Load your game and check your seed before going on: the Timer's Check Your Seed lists the seeds near this one with their coin flips, or roamers and Elm's or Irwin's calls, and gives the delay you hit for its calibration.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The seed a Gen 3 game starts on: Emerald's is always 0, a dead
    /// battery's 0x5A0; otherwise the 16-bit seed before the target's.
    private var gen3InitialSeed: UInt32 {
        gen3Start?.seed ?? UInt32(PFBridge.seedToTimeOriginSeed3(seed: result.seed).originSeed)
    }

    private var gen3TimeSection: some View {
        SeedToTimeListGen3(
            times: timeResults3,
            totalCount: timeResults3.count,
            onSelect: { timeText in
                if let gen3Start { sendToTimerGen3(gen3Start, timeText: timeText) }
            }
        )
    }

    /// The seed the target's frames count from, the frames, and how long
    /// they take; the clock's times follow in their own list.
    private func gen3StartCard(_ start: Gen3TargetStart) -> some View {
        let seedText = String(format: "%04X", start.seed)
        let title = switch start.kind {
        case .boot: "From Boot"
        case .clock, .origin: "Origin Seed"
        case .generatorSeed: "From the Generator's Seed"
        }
        let note: String? = switch start.kind {
        case .boot where game == .emerald:
            "Emerald starts on seed 0000 every time, so the target is a frame count from boot, not a clock time."
        case .boot:
            "With a dead battery, Ruby and Sapphire start on seed 05A0 every time, so the target is a frame count from boot, not a clock time."
        case .clock:
            "Ruby and Sapphire's clock makes the seed: load the game at one of the times below."
        case .generatorSeed:
            "Counted from the Generator's seed, which the game doesn't boot on. For a seed learnt in game, such as a new game's Trainer ID, use the Timer's Variable Target."
        case .origin:
            "FireRed and LeafGreen's seed depends on when you load the game. Turn on Only targets I can reach to find the seeds you can hit."
        }
        let minutes = Double(start.frame) / GBA_FRAMERATE / 60
        return SectionCard(title: title, icon: "arrow.uturn.backward") {
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent(start.kind == .clock || start.kind == .origin ? "16-bit Seed" : "Seed", value: seedText)
                .font(.system(.body, design: .monospaced))
            LabeledContent("Frames", value: start.frame.formatted())
            LabeledContent("Wait", value: Self.waitText(frames: start.frame))
            if start.kind != .clock && start.kind != .origin {
                if minutes > 60 {
                    Text("That's a long wait. The Generator from \(seedText) lists the targets within the frames you can wait for.")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    sendToTimerGen3(start, timeText: "frame \(start.frame.formatted()) from seed \(seedText)")
                } label: {
                    Label("Send to Timer", systemImage: "timer")
                }
            }
        }
    }

    /// How long `frames` take on a GBA: "41.9 s", "12 min 5 s", "3 h 20 min".
    static func waitText(frames: Int) -> String {
        let seconds = Double(frames) / GBA_FRAMERATE
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        let whole = Int(seconds.rounded())
        if whole < 3600 { return "\(whole / 60) min \(whole % 60) s" }
        if whole < 86400 { return "\(whole / 3600) h \(whole % 3600 / 60) min" }
        return "\((whole / 86400).formatted()) days"
    }

    private var gen4TimeSection: some View {
        SeedToTimeListGen4(
            times: timeResults4,
            totalCount: timeResults4.count,
            onSelect: { time in sendToTimerGen4(time) }
        )
    }

    private func computeTimes() async {
        isComputing = true
        let gen = generation
        let seedVal = result.seed
        if gen == .gen3 {
            let start = Gen3TargetStart.of(seed: seedVal, advances: result.advances, fromGenerator: fromGenerator,
                                           game: game, deadBattery: deadBattery)
            gen3Start = start
            if start.kind == .clock {
                let clockSeed = start.seed
                timeResults3 = await Task.detached {
                    seedToTimeGen3(seed: clockSeed).times
                }.value
            }
        } else {
            let r = await Task.detached {
                return seedToTimeGen4(seed: seedVal)
            }.value
            timeResults4 = r
        }
        isComputing = false
    }

    private func sendToTimerGen3(_ start: Gen3TargetStart, timeText: String) {
        FinderTimerBridge.shared.sendGen3(start, time: timeText, seed: result.seedHex)
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

    /// The Timer also keeps the whole clock time, for checking the seed you
    /// hit (`Gen4SeedCheckView`).
    private func sendToTimerGen4(_ time: SeedToTimeResult4) {
        let bridge = FinderTimerBridge.shared
        bridge.pendingGen = .gen4
        bridge.pendingTargetDelay = Int(time.delay)
        bridge.pendingTargetSecond = time.second
        bridge.pendingSeedTime = Gen4SeedTime(month: time.month, day: time.day, hour: Int(time.hour),
                                              minute: time.minute, second: time.second, delay: Int(time.delay))
        bridge.pendingHGSS = game == .heartGold || game == .soulSilver
        bridge.selectedTime = time.displayTime
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(time.displayTime)
                        .font(.system(.body, design: .monospaced))
                    // For an emulator's clock.
                    Text(time.dateText)
                        .font(.caption).foregroundStyle(.secondary)
                }
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
    let onSelect: (SeedToTimeResult4) -> Void

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
    let onSelect: (SeedToTimeResult4) -> Void
    var body: some View {
        Button { onSelect(time) } label: {
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
            LiveIntField("Min", value: $min, range: 0...31)
                .textFieldStyle(.roundedBorder).scaledWidth(50)
                .multilineTextAlignment(.trailing)
            Text("–")
            LiveIntField("Max", value: $max, range: 0...31)
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

/// A whole-number field that takes its number as you type.
/// `TextField(value:format:)` only takes it when the field loses focus, so a
/// button tapped straight after typing (Find IVs, Start, Update Calibration)
/// used the number from before.
struct LiveIntField: View {
    private let title: String
    @Binding private var value: Int?
    private let range: ClosedRange<Int>?
    private let prompt: Text?
    private let grouping: Bool

    @State private var text = ""
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool

    /// An entry outside `range` is clamped, and the field shows the clamped
    /// number once it loses focus. `grouping` is for quantities, not IDs or
    /// years.
    init(_ title: String = "", value: Binding<Int?>, range: ClosedRange<Int>? = nil,
         prompt: Text? = nil, grouping: Bool = true) {
        self.title = title
        _value = value
        self.range = range
        self.prompt = prompt
        self.grouping = grouping
    }

    /// For a number that's always there: emptying the field keeps the last
    /// one, and an entry is clamped to what `T` holds.
    init<T: FixedWidthInteger>(_ title: String = "", value: Binding<T>, range: ClosedRange<Int>? = nil,
                               prompt: Text? = nil, grouping: Bool = true) {
        let fits = Int(clamping: T.min)...Int(clamping: T.max)
        self.init(title,
                  value: Binding<Int?>(get: { Int(value.wrappedValue) },
                                         set: { if let number = $0 { value.wrappedValue = T(clamping: number) } }),
                  range: range?.clamped(to: fits) ?? fits, prompt: prompt, grouping: grouping)
    }

    private var allowsNegative: Bool { (range?.lowerBound ?? -1) < 0 }

    var body: some View {
        TextField(title, text: $text, selection: $selection, prompt: prompt)
            .focused($focused)
            .autocorrectionDisabled()
            #if os(iOS)
            // The number pad has no minus sign.
            .keyboardType(allowsNegative ? .numbersAndPunctuation : .numberPad)
            #endif
            .onChange(of: text) { typed() }
            // Set from elsewhere: a button, or a saved value.
            .onChange(of: value, initial: true) { if number(in: text) != value { show() } }
            .onChange(of: focused) {
                show()
                // Typing replaces the number, as a 31 is usually retyped,
                // not added to.
                if focused { selectAll() }
            }
    }

    private func selectAll() {
        // After the tap that focused it has placed the caret.
        Task { @MainActor in
            selection = TextSelection(range: text.startIndex..<text.endIndex)
        }
    }

    private func typed() {
        // Showing the number isn't typing it.
        guard focused else { return }
        let cleaned = Self.cleaned(text, allowsNegative: allowsNegative)
        guard cleaned == text else { text = cleaned; return }
        let entry = number(in: text)
        if entry != value, entry != nil || text.isEmpty { value = entry }
    }

    private func number(in text: String) -> Int? {
        guard let number = Int(text) else { return nil }
        return range.map { number.clamped(to: $0) } ?? number
    }

    /// Plain digits while editing; grouped, if wanted, otherwise.
    private func show() {
        guard let value else { text = ""; return }
        text = focused || !grouping ? String(value) : value.formatted()
    }

    /// Digits only, with a leading minus where it's allowed, and few enough
    /// to fit an `Int`.
    nonisolated static func cleaned(_ text: String, allowsNegative: Bool) -> String {
        var result = ""
        for character in text where character.isASCII {
            if character.isNumber {
                result.append(character)
            } else if character == "-", allowsNegative, result.isEmpty {
                result.append(character)
            }
        }
        return String(result.prefix(result.hasPrefix("-") ? 11 : 10))
    }
}

struct RNGIntField: View {
    let label: String
    @Binding var value: Int
    /// What the field allows; an entry outside it is clamped, and the field
    /// shows what's used once it loses focus.
    var range: ClosedRange<Int>? = nil
    var body: some View {
        // At accessibility sizes the field moves under its label.
        AdaptiveStack(spacing: 6) {
            Text(label).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            LiveIntField(value: $value, range: range)
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
    /// Clamps a number field's value to `range`, as when it's set from
    /// elsewhere.
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
            LiveIntField(value: $value, range: 0...Int.max, prompt: Text("—"))
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
            LiveIntField("Stat", value: $stat)
                .textFieldStyle(.roundedBorder).scaledWidth(70)
            Text("EV:").font(.caption).foregroundStyle(.secondary)
            LiveIntField("EV", value: $ev, range: 0...255)
                .textFieldStyle(.roundedBorder).scaledWidth(60)
        }
    }
}

/// An IV, 0–31, as a number field: exact, and narrow enough for a grid (a
/// slider there had no room for its track, and drew as an empty capsule).
struct IVField: View {
    let label: String
    @Binding var value: UInt8

    init(label: String, value: Binding<UInt8>) {
        self.label = label
        _value = value
    }

    init(label: String, value: Binding<Int>) {
        self.label = label
        _value = Binding(get: { UInt8(clamping: value.wrappedValue) }, set: { value.wrappedValue = Int($0) })
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            LiveIntField(label, value: $value, range: 0...31)
                .textFieldStyle(.roundedBorder).scaledWidth(52)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .monospaced))
        }
    }
}

extension View {
    /// Scrolling or tapping off a field puts the keyboard away, as the
    /// number pad has no Return key.
    func dismissesKeyboard() -> some View {
        #if os(iOS)
        scrollDismissesKeyboard(.interactively)
            .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        #else
        self
        #endif
    }
}
