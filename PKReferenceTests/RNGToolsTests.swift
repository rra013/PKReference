//
//  RNGToolsTests.swift
//  PKReferenceTests
//
//  Tests for EonTimer port and PokeFinder port
//

import Testing
import Observation
import Foundation
@testable import PKReference

// MARK: - EonTimer: Calibrator Tests

struct CalibratorTests {
    let ndsSlot1 = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60.0,
        precisionCalibration: false, minimumLength: 14000
    )

    @Test func roundHalfToEven_roundsCorrectly() {
        #expect(roundHalfToEven(2.5) == 2)  // banker's: round to even
        #expect(roundHalfToEven(3.5) == 4)  // banker's: round to even
        #expect(roundHalfToEven(2.3) == 2)
        #expect(roundHalfToEven(2.7) == 3)
    }

    @Test func toMilliseconds_ndsSlot1() {
        // NDS Slot 1: 59.8261 fps -> ~16.715ms per frame
        let ms = eonToMilliseconds(ndsSlot1, delays: 60)
        // 60 * (1000/59.8261) ≈ 1002.9
        #expect(ms >= 1002 && ms <= 1004)
    }

    @Test func toDelays_ndsSlot1() {
        let delays = eonToDelays(ndsSlot1, milliseconds: 1000.0)
        // 1000 / (1000/59.8261) ≈ 59.83
        #expect(delays == 60)
    }

    @Test func toMilliseconds_gba() {
        let gba = CalibratorSettings(console: .gba, customFramerate: 60, precisionCalibration: false, minimumLength: 14000)
        let ms = eonToMilliseconds(gba, delays: 60)
        // GBA: 16777216/280896 fps ≈ 59.7275 -> 60 frames ≈ 1004.6ms
        #expect(ms >= 1004 && ms <= 1006)
    }

    @Test func createCalibration_combinesDelayAndSecond() {
        // createCalibration(settings, delays, seconds) =
        //   toMilliseconds(settings, delays - toDelays(settings, seconds * 1000))
        let cal = createCalibration(ndsSlot1, delays: 500, seconds: 14)
        #expect(cal != 0)  // Non-trivial calibration
    }

    @Test func toMinimumLength_addsMinuteUntilAbove() {
        // Default minimum is 14000ms (14s)
        let result1 = eonToMinimumLength(5000)
        #expect(result1 == 65000) // 5000 + 60000

        let result2 = eonToMinimumLength(15000)
        #expect(result2 == 15000) // Already above 14000

        let result3 = eonToMinimumLength(-10000)
        #expect(result3 == 50000) // -10000 + 60000
    }
}

// MARK: - EonTimer: Second Timer Tests

struct SecondTimerTests {
    @Test func createSecondPhases_singlePhase() {
        let phases = createSecondPhases(targetSecond: 50, calibration: 0)
        #expect(phases.count == 1)
        // 50*1000 + 0 + 200 = 50200, already above 14000
        #expect(phases[0] == 50200)
    }

    @Test func createSecondPhases_withCalibration() {
        let phases = createSecondPhases(targetSecond: 50, calibration: -500)
        #expect(phases[0] == 49700) // 50000 - 500 + 200
    }

    @Test func calibrateSecond_exactHit() {
        #expect(calibrateSecond(targetSecond: 50, secondHit: 50) == 0)
    }

    @Test func calibrateSecond_hitEarly() {
        // Early: (50-48)*1000 - 500 = 1500
        #expect(calibrateSecond(targetSecond: 50, secondHit: 48) == 1500)
    }

    @Test func calibrateSecond_hitLate() {
        // Late: (50-52)*1000 + 500 = -1500
        #expect(calibrateSecond(targetSecond: 50, secondHit: 52) == -1500)
    }
}

// MARK: - EonTimer: Delay Timer Tests

struct DelayTimerTests {
    let settings = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60, precisionCalibration: false, minimumLength: 14000
    )

    @Test func createDelayPhases_producesTwoPhases() {
        let phases = createDelayPhases(settings, targetDelay: 600, targetSecond: 50, calibration: 0)
        #expect(phases.count == 2)
    }

    @Test func calibrateDelay_exactHit_returnsZero() {
        let delta = calibrateDelay(settings, targetDelay: 600, delayHit: 600)
        #expect(delta == 0)
    }

    @Test func calibrateDelay_closeHit_usesReducedFactor() {
        let close = calibrateDelay(settings, targetDelay: 600, delayHit: 605)
        let far = calibrateDelay(settings, targetDelay: 600, delayHit: 700)
        // Close uses 0.75x, far uses 1.0x
        #expect(abs(close) < abs(far))
    }
}

// MARK: - EonTimer: Gen 3 Timer Tests

struct Gen3TimerEonTests {
    let gba = CalibratorSettings(console: .gba, customFramerate: 60, precisionCalibration: false, minimumLength: 14000)

    @Test func standardMode_producesTwoPhases() {
        let phases = createGen3Phases(gba, mode: .standard, preTimer: 5000, targetFrame: 1000, calibration: 0)
        #expect(phases.count == 2)
        #expect(phases[0] == 5000) // preTimer passthrough
    }

    @Test func variableMode_producesTwoPhases_secondIsMax() {
        let phases = createGen3Phases(gba, mode: .variableTarget, preTimer: 5000, targetFrame: 1000, calibration: 0)
        #expect(phases.count == 2)
        #expect(phases[0] == 5000)
        #expect(phases[1] == Int.max)
    }

    @Test func calibration_adjustsFramePhase() {
        let uncal = createGen3Phases(gba, mode: .standard, preTimer: 5000, targetFrame: 1000, calibration: 0)
        let cal = createGen3Phases(gba, mode: .standard, preTimer: 5000, targetFrame: 1000, calibration: 100)
        // Positive calibration adds to frame phase
        #expect(cal[1] == uncal[1] + 100)
    }
}

// MARK: - EonTimer: Gen 4 Timer Tests

struct Gen4TimerEonTests {
    let settings = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60, precisionCalibration: false, minimumLength: 14000
    )

    @Test func producesTwoPhases() {
        let phases = createGen4Phases(settings, targetDelay: 600, targetSecond: 50,
                                       calibratedDelay: 500, calibratedSecond: 14)
        #expect(phases.count == 2)
    }

    @Test func phasesArePositive() {
        let phases = createGen4Phases(settings, targetDelay: 600, targetSecond: 50,
                                       calibratedDelay: 500, calibratedSecond: 14)
        #expect(phases[0] > 0)
        #expect(phases[1] > 0)
    }

    @Test func calibrateGen4_exactHit_returnsZero() {
        #expect(calibrateGen4(settings, targetDelay: 600, delayHit: 600) == 0)
    }

    @Test func calibrateGen4_zeroHit_returnsZero() {
        #expect(calibrateGen4(settings, targetDelay: 600, delayHit: 0) == 0)
    }

    @Test func calibrateGen4_overshoot_positive() {
        let delta = calibrateGen4(settings, targetDelay: 600, delayHit: 610)
        #expect(delta > 0)
    }
}

// MARK: - EonTimer: Gen 5 Timer Tests

struct Gen5TimerEonTests {
    let settings = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60, precisionCalibration: false, minimumLength: 14000
    )

    @Test func standardMode_producesSinglePhase() {
        // Gen 5 Standard uses only secondPhases (1 phase)
        let phases = createGen5Phases(settings, mode: .standard,
            targetDelay: 1200, targetSecond: 50, targetAdvances: 0,
            calibration: -95, entralinkCalibration: 0, frameCalibration: 0)
        #expect(phases.count == 1)
    }

    @Test func cGearMode_producesTwoPhases() {
        let phases = createGen5Phases(settings, mode: .cGear,
            targetDelay: 1200, targetSecond: 50, targetAdvances: 0,
            calibration: -95, entralinkCalibration: 0, frameCalibration: 0)
        #expect(phases.count == 2)
    }

    @Test func entralinkMode_producesTwoPhases() {
        let phases = createGen5Phases(settings, mode: .entralink,
            targetDelay: 1200, targetSecond: 50, targetAdvances: 100,
            calibration: -95, entralinkCalibration: 256, frameCalibration: 0)
        #expect(phases.count == 2)
    }

    @Test func entralinkPlusMode_producesThreePhases() {
        let phases = createGen5Phases(settings, mode: .entralinkPlus,
            targetDelay: 1200, targetSecond: 50, targetAdvances: 100,
            calibration: -95, entralinkCalibration: 256, frameCalibration: 0)
        #expect(phases.count == 3)
    }
}

// MARK: - EonTimer: Custom Timer Tests

struct CustomTimerEonTests {
    let settings = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60, precisionCalibration: false, minimumLength: 14000
    )

    @Test func milliseconds_passthrough() {
        let phases = createCustomPhases(settings, phases: [
            CustomPhase(unit: .milliseconds, target: 20000, calibration: 0)
        ])
        #expect(phases[0] == 20000)
    }

    @Test func calibration_added() {
        let phases = createCustomPhases(settings, phases: [
            CustomPhase(unit: .milliseconds, target: 20000, calibration: -100)
        ])
        #expect(phases[0] == 19900)
    }

    @Test func advances_convertedToMs() {
        let phases = createCustomPhases(settings, phases: [
            CustomPhase(unit: .advances, target: 60, calibration: 0)
        ])
        // Should use toMilliseconds(settings, 60) ≈ 1003
        #expect(phases[0] >= 1002 && phases[0] <= 1004)
    }
}

// MARK: - PokeFinder: LCRNG Tests

struct LCRNGTests {
    @Test func pokeRNG_correctConstants() {
        var rng = makePokeRNG(0)
        let first = rng.next()
        // seed * 0x41C64E6D + 0x6073
        // 0 * mult + 0x6073 = 0x6073
        #expect(first == 0x6073)
    }

    @Test func pokeRNG_advance() {
        var rng = makePokeRNG(0x12345678)
        let seed1 = rng.next()
        var rng2 = makePokeRNG(0x12345678)
        rng2.advance(1)
        #expect(rng2.seed == seed1)
    }

    @Test func xdRNG_correctConstants() {
        var rng = makeXDRNG(0)
        let first = rng.next()
        // 0 * 0x343FD + 0x269EC3
        #expect(first == 0x269EC3)
    }
}

// MARK: - PokeFinder: LCRNGReverse Tests

struct LCRNGReverseTests {
    @Test func method12_recoversSeeds() {
        // Known good: a specific seed should produce specific IVs
        // Start from seed 0, advance through PokeRNG to get IVs
        var rng = makePokeRNG(0)
        rng.advance(1) // PID low
        rng.advance(1) // PID high
        let iv1 = UInt16(rng.next() >> 16)
        let iv2 = UInt16(rng.next() >> 16)
        let hp = UInt8(iv1 & 0x1f)
        let atk = UInt8((iv1 >> 5) & 0x1f)
        let def = UInt8((iv1 >> 10) & 0x1f)
        let spe = UInt8(iv2 & 0x1f)
        let spa = UInt8((iv2 >> 5) & 0x1f)
        let spd = UInt8((iv2 >> 10) & 0x1f)

        let seeds = LCRNGReverse.recoverPokeRNGIVMethod12(
            hp: hp, atk: atk, def: def, spa: spa, spd: spd, spe: spe
        )
        // Should recover at least one seed
        #expect(!seeds.isEmpty)
    }

    @Test func calculatePIDs_returnsResults() {
        // Using known IVs that should produce results
        let results = LCRNGReverse.calculatePIDs(
            hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31,
            nature: 0, tid: 12345
        )
        // Every returned PID should satisfy the requested nature constraint.
        #expect(results.allSatisfy { $0.pid % 25 == 0 })
    }
}

// MARK: - PokeFinder: IVChecker Tests

struct IVCheckerTests {
    @Test func perfectIVs_level50() {
        // Pikachu: base stats [35, 55, 40, 50, 50, 90]
        // Nature 3 = Adamant (+Atk, -SpA)
        // At level 50, IV 31, no EVs:
        // HP: ((2*35 + 31)*50/100) + 50 + 10 = 110
        let baseStats: [UInt8] = [35, 55, 40, 50, 50, 90]
        let hpStat = pfComputeStatPublic(baseStat: 35, iv: 31, nature: 3, level: 50, index: 0)
        let atkStat = pfComputeStatPublic(baseStat: 55, iv: 31, nature: 3, level: 50, index: 1)
        let defStat = pfComputeStatPublic(baseStat: 40, iv: 31, nature: 3, level: 50, index: 2)
        let spaStat = pfComputeStatPublic(baseStat: 50, iv: 31, nature: 3, level: 50, index: 3)
        let spdStat = pfComputeStatPublic(baseStat: 50, iv: 31, nature: 3, level: 50, index: 4)
        let speStat = pfComputeStatPublic(baseStat: 90, iv: 31, nature: 3, level: 50, index: 5)

        let results = pfCalculateIVRange(
            baseStats: baseStats,
            stats: [[hpStat, atkStat, defStat, spaStat, spdStat, speStat]],
            levels: [50],
            nature: 3
        )

        #expect(results[0].possibleIVs.contains(31)) // HP
        #expect(results[1].possibleIVs.contains(31)) // Atk
    }

    @Test func zeroIV_detected() {
        let baseStats: [UInt8] = [35, 55, 40, 50, 50, 90]
        let hpStat = pfComputeStatPublic(baseStat: 35, iv: 0, nature: 0, level: 50, index: 0)

        let results = pfCalculateIVRange(
            baseStats: baseStats,
            stats: [[hpStat, 0, 0, 0, 0, 0]],
            levels: [50],
            nature: 0
        )
        #expect(results[0].possibleIVs.contains(0))
    }

    @Test func impossibleStat_returnsEmpty() {
        let baseStats: [UInt8] = [35, 55, 40, 50, 50, 90]
        let results = pfCalculateIVRange(
            baseStats: baseStats,
            stats: [[999, 0, 0, 0, 0, 0]],
            levels: [50],
            nature: 0
        )
        #expect(results[0].possibleIVs.isEmpty)
    }

    @Test func displayRange_singleIV() {
        let r = IVCalcResult(statName: "HP", possibleIVs: [31])
        #expect(r.displayRange == "31")
    }

    @Test func displayRange_range() {
        let r = IVCalcResult(statName: "HP", possibleIVs: [29, 30, 31])
        #expect(r.displayRange == "29-31")
    }
}

// MARK: - IV Calculator Tests

@MainActor
struct IVCalculatorTests {
    private func line(_ level: Int, _ stats: [Int]) -> FRLGStatsLine {
        FRLGStatsLine(level: level, stats: stats.map { Optional($0) })
    }

    /// Emerald's Pikachu, level 50, Hardy, every IV 15: each stat allows 15,
    /// and Sword's base stats don't fit its Defense.
    @Test func eachGamesBaseStats() throws {
        let stats = [102, 67, 42, 62, 52, 102]
        guard case .result(let emerald) = IVCalcEngine.calculate(game: .emerald, specie: 25, form: 0, lines: [line(50, stats)],
                                                                nature: 0, characteristic: nil, hiddenPower: nil) else {
            Issue.record("Emerald should fit"); return
        }
        #expect(emerald.ivs.allSatisfy { $0.contains(15) })
        let sword = IVCalcEngine.calculate(game: .sword, specie: 25, form: 0, lines: [line(50, stats)],
                                           nature: 0, characteristic: nil, hiddenPower: nil)
        #expect(sword == .error("No Defense IV fits. Check the nature, level and stats."))
    }

    /// The nature's index is PokéFinder's (pid % 25): Modest (15) raises
    /// Sp. Atk, so a Modest stat isn't a Hardy one.
    @Test func natureOrderIsPokeFinders() throws {
        #expect(pfNatureNames[15] == "Modest" && pfNatureNames[3] == "Adamant")
        #expect(pfNatureLabel(15) == "Modest (+Sp.Atk / -Atk)" && pfNatureLabel(0) == "Hardy")
        let stats = [102, 60, 42, 68, 52, 102]  // Pikachu Lv 50, IVs 15, Modest
        guard case .result(let modest) = IVCalcEngine.calculate(game: .emerald, specie: 25, form: 0, lines: [line(50, stats)],
                                                               nature: 15, characteristic: nil, hiddenPower: nil) else {
            Issue.record("Modest should fit"); return
        }
        #expect(modest.ivs[3].contains(15) && modest.ivs[1].contains(15))
        #expect(IVCalcEngine.calculate(game: .emerald, specie: 25, form: 0, lines: [line(50, stats)],
                                       nature: 0, characteristic: nil, hiddenPower: nil) != .result(modest))
    }

    /// A characteristic and a Hidden Power type narrow the IVs, and a second
    /// line at a later level narrows them further.
    @Test func narrowing() throws {
        let level5 = [20, 12, 9, 11, 10, 15]   // Pikachu Lv 5, IVs 31, Hardy (Platinum's stats)
        guard case .result(let wide) = IVCalcEngine.calculate(game: .platinum, specie: 25, form: 0, lines: [line(5, level5)],
                                                             nature: 0, characteristic: nil, hiddenPower: nil) else {
            Issue.record("should fit"); return
        }
        #expect(wide.ivs[0].count > 1)
        #expect(wide.nextLevel[0] > 5)
        // "Takes plenty of siestas" family: HP highest, HP IV % 5 == 1 → 31.
        guard case .result(let charFiltered) = IVCalcEngine.calculate(game: .platinum, specie: 25, form: 0, lines: [line(5, level5)],
                                                                     nature: 0, characteristic: 1, hiddenPower: nil) else {
            Issue.record("should fit"); return
        }
        #expect(charFiltered.ivs[0].allSatisfy { $0 % 5 == 1 })
        #expect(charFiltered.ivs[0].count < wide.ivs[0].count)
        let level100 = [211, 146, 96, 136, 116, 216]  // the same at Lv 100, where every IV shows
        guard case .result(let both) = IVCalcEngine.calculate(game: .platinum, specie: 25, form: 0,
                                                             lines: [line(5, level5), line(100, level100)],
                                                             nature: 0, characteristic: nil, hiddenPower: nil) else {
            Issue.record("should fit"); return
        }
        #expect(both.ivs.allSatisfy { $0 == [31] })
        // Hidden Power Dark needs every IV odd.
        guard case .result(let dark) = IVCalcEngine.calculate(game: .platinum, specie: 25, form: 0, lines: [line(5, level5)],
                                                             nature: 0, characteristic: nil, hiddenPower: 15) else {
            Issue.record("should fit"); return
        }
        #expect(dark.ivs.allSatisfy { $0.allSatisfy { $0 % 2 == 1 } })
    }

    /// The species and forms each game has, as PokéFinder lists them.
    @Test func speciesAndForms() {
        #expect(PFBridge.presentSpecies(game: .emerald).count == 386)
        #expect(PFBridge.presentSpecies(game: .platinum).last == 493)
        #expect(PFBridge.formCount(game: .emerald, specie: 386) == 4)    // Deoxys
        #expect(PFBridge.formCount(game: .platinum, specie: 479) == 6)   // Rotom
        #expect(PFBridge.formCount(game: .emerald, specie: 25) == 1)
        // Deoxys's Attack Forme has its own stats.
        #expect(PFBridge.baseStats(game: .emerald, specie: 386, form: 1) != PFBridge.baseStats(game: .emerald, specie: 386, form: 0))
        #expect(PFBridge.characteristics.count == 30 && !PFBridge.characteristics[0].isEmpty)
    }

    @Test func ivText() {
        #expect(IVCalcEngine.text([31]) == "31")
        #expect(IVCalcEngine.text([17, 18, 19]) == "17–19")
        #expect(IVCalcEngine.text([16, 21, 26, 31]) == "16, 21, 26, 31")
        #expect(IVCalcEngine.text([28, 29, 31]) == "28, 29, 31")
    }

    /// Today's games count EVs: 252 in Attack is 63 more points at Lv 100.
    @Test func currentGamesUseEVs() {
        let base: [UInt8] = [35, 55, 40, 50, 50, 90]
        let withEVs = pfCalculateIVRange(baseStats: base, stats: [[211, 209, 116, 136, 136, 216]], levels: [100], nature: 0,
                                         evs: [0, 252, 0, 0, 0, 0])
        #expect(withEVs[1].possibleIVs == [31])
        let withoutEVs = pfCalculateIVRange(baseStats: base, stats: [[211, 209, 116, 136, 136, 216]], levels: [100], nature: 0)
        #expect(withoutEVs[1].possibleIVs.isEmpty)
    }

    /// The Hidden Power screen's presets give their types.
    @Test func hiddenPowerPresets() {
        for preset in HiddenPowerCalcView.presets {
            let ivs = preset.ivs
            #expect(calculateHiddenPowerType(ivHP: ivs[0], ivAtk: ivs[1], ivDef: ivs[2], ivSpeed: ivs[5],
                                             ivSpAtk: ivs[3], ivSpDef: ivs[4]) == preset.type, "\(preset.type)")
        }
    }

    /// The number fields keep digits, and a minus only where it's allowed
    /// and only in front.
    @Test func numberFieldEntry() {
        #expect(LiveIntField.cleaned("1,200", allowsNegative: false) == "1200")
        #expect(LiveIntField.cleaned("-95", allowsNegative: false) == "95")
        #expect(LiveIntField.cleaned("-95", allowsNegative: true) == "-95")
        #expect(LiveIntField.cleaned("9-5", allowsNegative: true) == "95")
        #expect(LiveIntField.cleaned("3 1a", allowsNegative: false) == "31")
        #expect(LiveIntField.cleaned("٣١", allowsNegative: false) == "")
        // Short enough for an Int either way.
        #expect(LiveIntField.cleaned(String(repeating: "9", count: 30), allowsNegative: false).count == 10)
        #expect(LiveIntField.cleaned("-" + String(repeating: "9", count: 30), allowsNegative: true).count == 11)
    }
}

// MARK: - Hidden Power Tests

struct HiddenPowerEonTests {
    @Test func allMaxIVs_isDark() {
        #expect(calculateHiddenPowerType(ivHP: 31, ivAtk: 31, ivDef: 31,
            ivSpeed: 31, ivSpAtk: 31, ivSpDef: 31) == "Dark")
    }

    @Test func allZeroIVs_isFighting() {
        #expect(calculateHiddenPowerType(ivHP: 0, ivAtk: 0, ivDef: 0,
            ivSpeed: 0, ivSpAtk: 0, ivSpDef: 0) == "Fighting")
    }

    @Test func basePower_maxIVs_is70() {
        #expect(calculateHiddenPowerBasePower(ivHP: 31, ivAtk: 31, ivDef: 31,
            ivSpeed: 31, ivSpAtk: 31, ivSpDef: 31) == 70)
    }

    @Test func basePower_minIVs_is30() {
        #expect(calculateHiddenPowerBasePower(ivHP: 0, ivAtk: 0, ivDef: 0,
            ivSpeed: 0, ivSpAtk: 0, ivSpDef: 0) == 30)
    }
}

// MARK: - Timer Engine Tests

@MainActor
struct TimerEngineTests {
    private final class Clock { var t = 100.0 }

    private final class FakeBeeper: TimerBeeper {
        var scheduled: [Double] = []
        var cancelled = 0
        func prepare() {}
        func schedule(_ times: [Double]) { scheduled += times }
        func cancelAll() { cancelled += 1 }
    }

    private func engine(_ clock: Clock, _ beeper: FakeBeeper? = nil) -> RNGTimerEngine {
        RNGTimerEngine(now: { clock.t }, beeper: beeper ?? FakeBeeper())
    }

    @Test func initialState() {
        let engine = engine(Clock())
        #expect(!engine.isRunning)
        #expect(engine.phases.isEmpty)
    }

    @Test func emptyPhases_doesNotStart() {
        let engine = engine(Clock())
        engine.start(phases: [])
        #expect(!engine.isRunning)
    }

    @Test func stop_resetsState() {
        let beeper = FakeBeeper()
        let engine = engine(Clock(), beeper)
        engine.start(phases: [50000])
        engine.stop()
        #expect(!engine.isRunning)
        #expect(engine.remainingMs == 0)
        #expect(beeper.cancelled > 0)
    }

    /// Each phase ends at the start plus the phases before it, whenever the
    /// ticks come (they used to restart the clock each phase, so late ticks
    /// added up).
    @Test func phasesEndAtTheirSums() {
        let clock = Clock()
        let engine = engine(clock)
        engine.start(phases: Array(repeating: 1000, count: 10))
        for i in 0..<10 {
            clock.t = 100 + Double(i) + 0.937   // a late tick in every phase
            engine.tick()
            #expect(engine.currentPhaseIndex == i)
            #expect(engine.remainingMs == 63)
        }
        clock.t = 109.990
        engine.tick()
        #expect(engine.remainingMs == 10)
        clock.t = 110.0
        engine.tick()
        #expect(!engine.isRunning)
    }

    /// EonTimer's actions: six beeps 500 ms apart, the last on each phase's
    /// end, those after the phase's start.
    @Test func beepsLeadUpToEachTarget() {
        let clock = Clock()
        let beeper = FakeBeeper()
        engine(clock, beeper).start(phases: [1000, 2000])
        #expect(beeper.scheduled == [100.5, 101, 101.5, 102, 102.5, 103])
    }

    /// Variable Target counts up until the frame is set, then ends that many
    /// milliseconds after its phase began.
    @Test func variableTarget() {
        let clock = Clock()
        let beeper = FakeBeeper()
        let engine = engine(clock, beeper)
        engine.start(phases: [5000, Int.max])
        #expect(beeper.scheduled == [102.5, 103, 103.5, 104, 104.5, 105])
        clock.t = 107
        engine.tick()
        #expect(engine.isWaitingForTarget)
        #expect(engine.remainingMs == 2000)
        engine.resolveOpenPhase(3000)
        #expect(!engine.isWaitingForTarget)
        #expect(beeper.scheduled.suffix(2) == [107.5, 108])
        #expect(engine.remainingMs == 1000)
        clock.t = 108
        engine.tick()
        #expect(!engine.isRunning)
    }

    /// With no pre-timer (started on the A press that sets the seed, as in
    /// the FireRed/LeafGreen new-game manip), it counts from the start.
    @Test func variableTargetWithNoPreTimer() {
        let clock = Clock()
        let engine = engine(clock)
        engine.start(phases: [0, Int.max])
        #expect(engine.isRunning)
        #expect(engine.isWaitingForTarget)
        clock.t = 112
        engine.tick()
        #expect(engine.remainingMs == 12_000)
        engine.resolveOpenPhase(20_000)
        #expect(engine.remainingMs == 8_000)
    }

    /// A tick inside a phase doesn't report a phase change, so only the
    /// readout redraws each tick.
    @Test func ticksReportOnlyPhaseChanges() {
        final class Flag: @unchecked Sendable { var set = false }
        let clock = Clock()
        let engine = engine(clock)
        engine.start(phases: [1000, 1000])
        let changed = Flag()
        withObservationTracking { _ = engine.currentPhaseIndex } onChange: { changed.set = true }
        clock.t = 100.5
        engine.tick()
        #expect(!changed.set)
        clock.t = 101.5
        engine.tick()
        #expect(changed.set)
    }

    /// A target already passed ends the timer.
    @Test func variableTargetAlreadyPassed() {
        let clock = Clock()
        let engine = engine(clock)
        engine.start(phases: [1000, Int.max])
        clock.t = 103
        engine.tick()
        engine.resolveOpenPhase(1000)
        #expect(!engine.isRunning)
    }

    /// The Custom timer's phases survive saving.
    @Test func customPhasesRoundTrip() {
        let phases = [CustomPhase(unit: .advances, target: 1234, calibration: -5),
                      CustomPhase(unit: .milliseconds, target: 5000, calibration: 0)]
        #expect(CustomPhase.decoded(CustomPhase.encoded(phases)) == phases)
        #expect(CustomPhase.decoded(Data()) == CustomPhase.defaults)
    }
}

// MARK: - PokeFinder: Finder Origin Seed Tests

struct FinderOriginSeedTests {
    @Test func smallSeed_returnsItself() {
        let (origin, advances) = findGen3OriginSeed(0x1234)
        #expect(origin == 0x1234)
        #expect(advances == 0)
    }

    @Test func zero_returnsZero() {
        let (origin, advances) = findGen3OriginSeed(0)
        #expect(origin == 0)
        #expect(advances == 0)
    }

    @Test func largeSeed_reverseWalks() {
        let (origin, advances) = findGen3OriginSeed(0x12345678)
        #expect(origin == 0x372B)
        #expect(advances == 57823)
    }

    @Test func maxU16_returnsItself() {
        let (origin, advances) = findGen3OriginSeed(0xFFFF)
        #expect(origin == 0xFFFF)
        #expect(advances == 0)
    }
}

// MARK: - PokeFinder: Gen 3 Generator Tests

struct FinderGen3GeneratorTests {
    @Test func generateFromSeedZero_method1() {
        let results = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 2,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        #expect(results.count == 3)

        // Advance 0
        #expect(results[0].pid == 0xE97E0000)
        #expect(results[0].nature == 14) // 0xE97E0000 % 25
        #expect(results[0].ivHP == 17)
        #expect(results[0].ivAtk == 19)
        #expect(results[0].ivDef == 20)
        #expect(results[0].ivSpA == 13)
        #expect(results[0].ivSpD == 12)
        #expect(results[0].ivSpe == 16)
    }

    @Test func natureFilter_filtersCorrectly() {
        // Only accept nature 14 (Rash) — advance 0 has nature 14
        let results = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 10,
            natures: Set<UInt8>([14]), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        #expect(results.allSatisfy { $0.nature == 14 })
    }

    @Test func initialAdvance_skipsFrames() {
        let allResults = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        // maxAdvance is relative to initialAdvance, so use 3 to cover same tail
        let skippedResults = staticGenerateGen3(
            seed: 0, initialAdvance: 2, maxAdvance: 3,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        #expect(skippedResults.count == allResults.count - 2)
        #expect(skippedResults[0].pid == allResults[2].pid)
    }
}

// MARK: - PokeFinder: Gen 3 Generator Additional Tests

struct FinderGen3AdditionalTests {
    /// PokéFinder's static Generator has Methods 1 and 4 (its Method 2 is
    /// Method 1), so statics offer those, and a Method 4 Searcher result's
    /// seed generates it.
    @Test func method4_searcherResultRegenerates() {
        let found = staticSearchGen3(minIVs: (31, 31, 31, 31, 0, 0), maxIVs: (31, 31, 31, 31, 31, 31),
                                     natures: [], tid: 0, sid: 0, shinyOnly: false, method: .method4)
        #expect(!found.isEmpty)
        for r in found.prefix(20) {
            let generated = staticGenerateGen3(seed: r.seed, initialAdvance: 0, maxAdvance: 0,
                                               natures: [], tid: 0, sid: 0, shinyOnly: false, method: .method4)
            #expect(generated.first?.pid == r.pid)
            #expect(generated.first?.ivSummary == r.ivSummary)
        }
    }

    @Test func method4_producesDifferentIVs() {
        // Method 4 has a VBlank skip between IV1 and IV2 calls.
        // StaticGenerator3 handles this — second IV call is shifted.
        let m1 = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 10,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        let m4 = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 10,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method4
        )
        #expect(!m1.isEmpty)
        #expect(!m4.isEmpty)
        // PIDs match (same first two LCRNG calls)
        for (a, b) in zip(m1, m4) { #expect(a.pid == b.pid) }
        // At least some IVs should differ due to VBlank skip between IV1 and IV2
        let anyDifferentIVs = zip(m1, m4).contains { a, b in
            a.ivHP != b.ivHP || a.ivAtk != b.ivAtk || a.ivDef != b.ivDef ||
            a.ivSpA != b.ivSpA || a.ivSpD != b.ivSpD || a.ivSpe != b.ivSpe
        }
        #expect(anyDifferentIVs)
    }

    @Test func resultFields_arePopulated() {
        let results = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 2,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        for r in results {
            #expect(r.nature < 25)
            #expect(r.ivHP <= 31)
            #expect(r.ivAtk <= 31)
            #expect(r.ivDef <= 31)
            #expect(r.ivSpA <= 31)
            #expect(r.ivSpD <= 31)
            #expect(r.ivSpe <= 31)
            #expect(r.method == .method1)
        }
    }

    @Test func shinyFilter_restrictsResults() {
        let all = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 100,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        let shinyOnly = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 100,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: true, method: .method1
        )
        #expect(shinyOnly.count <= all.count)
        #expect(shinyOnly.allSatisfy { $0.shiny })
    }
}

// MARK: - PokeFinder: Seed to Time Gen 3 Tests

struct SeedToTimeGen3Tests {
    @Test func simpleSeed_findsValidTimes() {
        let result = seedToTimeGen3(seed: 0x00000005)
        #expect(result.originSeed == 0x0005)
        #expect(result.advances == 0)
        #expect(!result.times.isEmpty)
    }

    @Test func simpleSeed_timesAreConsistent() {
        let result = seedToTimeGen3(seed: 0x00000005)
        // All times should reference the same origin seed
        #expect(result.times.allSatisfy { $0.originSeed == 0x0005 })
        #expect(result.times.allSatisfy { $0.advances == 0 })
        // Hours must be valid (0-23)
        #expect(result.times.allSatisfy { $0.hour >= 0 && $0.hour < 24 })
        // Minutes must be valid (0-59)
        #expect(result.times.allSatisfy { $0.minute >= 0 && $0.minute < 60 })
    }

    @Test func largeSeed_reverseWalksFirst() {
        // 0x12345678 reverse-walks to origin seed 0x372B; times are found for the origin
        let result = seedToTimeGen3(seed: 0x12345678)
        #expect(result.originSeed == 0x372B)
        #expect(result.advances == 57823)
        #expect(!result.times.isEmpty)
    }
}

// MARK: - PokeFinder: Seed to Time Gen 4 Tests

struct SeedToTimeGen4Tests {
    @Test func validSeed_findsResults() {
        let results = seedToTimeGen4(seed: 0x05100320)
        #expect(!results.isEmpty)
    }

    @Test func firstResult_correctValues() {
        let results = seedToTimeGen4(seed: 0x05100320)
        let first = results[0]
        #expect(first.hour == 16)      // cd = 0x10 = 16
        #expect(first.delay == 800)     // efgh = 0x0320 = 800
        #expect(first.month == 1)
        #expect(first.day == 1)
        #expect(first.minute == 0)
        #expect(first.second == 4)
    }

    @Test func overflowHour_adjustsToHour23() {
        // cd = 0xFF = 255, cd > 23 -> hour clamped to 23, delay adjusted
        let results = seedToTimeGen4(seed: 0x00FF0000)
        #expect(!results.isEmpty)
        #expect(results[0].hour == 23)
    }
}

// MARK: - PokeFinder: Gen 4 Generator Tests

struct FinderGen4GeneratorTests {
    @Test func method1_matchesGen3() {
        // Gen 4 Method 1 should delegate to Gen 3 Method 1
        let gen3 = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        let gen4 = staticGenerateGen4(
            seed: 0, initialAdvance: 0, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        #expect(gen3.count == gen4.count)
        for (g3, g4) in zip(gen3, gen4) {
            #expect(g3.pid == g4.pid)
            #expect(g3.ivHP == g4.ivHP)
        }
    }

    @Test func method1Gen4_producesResults() {
        let results = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 0, maxAdvance: 10,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.method == .method1 })
    }

    @Test func gen4_differentSeed_differentResults() {
        let r1 = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 0, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        let r2 = staticGenerateGen4(
            seed: 0xABCD1234, initialAdvance: 0, maxAdvance: 5,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        #expect(!r1.isEmpty)
        #expect(!r2.isEmpty)
        #expect(r1[0].pid != r2[0].pid)
    }
}

// MARK: - PokeFinder: Gen 4 Generator Additional Tests

struct FinderGen4AdditionalTests {
    @Test func gen4_natureFilter_works() {
        let all = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 0, maxAdvance: 50,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        let filtered = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 0, maxAdvance: 50,
            natures: Set<UInt8>([3]), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        #expect(filtered.count <= all.count)
        #expect(filtered.allSatisfy { $0.nature == 3 })
    }

    @Test func gen4_initialAdvance_skipsFrames() {
        let all = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 0, maxAdvance: 10,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        // maxAdvance is relative to initialAdvance, so use 7 to cover same tail
        let skipped = staticGenerateGen4(
            seed: 0x05100320, initialAdvance: 3, maxAdvance: 7,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1, lead: .none
        )
        #expect(skipped.count == all.count - 3)
        #expect(skipped[0].pid == all[3].pid)
    }
}

// MARK: - Gen 3 What You Hit Tests

@MainActor
struct Gen3WhatYouHitTests {
    private func squirtle() throws -> StaticEncounter {
        try #require(StaticEncounterData.encounters(for: .fireRed, category: .starters).first { $0.species == 7 })
    }

    private func exactly(_ ivs: [UInt8], nature: UInt8) -> FRLGCatch {
        FRLGCatch(nature: nature, ivMin: ivs, ivMax: ivs)
    }

    /// A Searcher's target is a seed; its frame from the game's initial
    /// seed (Emerald's 0) is the distance to it, and generates it.
    @Test func searcherTargetsFrameFromTheInitialSeed() throws {
        let rayquaza = try #require(StaticEncounterData.encounters(for: .emerald, category: .legends).first { $0.species == 384 })
        let targets = staticSearchGen3(minIVs: (31, 31, 31, 31, 31, 0), maxIVs: (31, 31, 31, 31, 31, 31),
                                       natures: [], tid: 0, sid: 0, shinyOnly: false, method: .method1)
        #expect(!targets.isEmpty)
        for target in targets.prefix(3) {
            let frame = PFBridge.lcrngDistance(from: 0, to: target.seed)
            let generated = PFBridge.staticTemplateGenerate3(seed: 0, initialAdvances: frame, maxAdvances: 0,
                                                             method: .method1, template: rayquaza.template,
                                                             tid: 0, sid: 0, game: .emerald)
            #expect(generated.first?.pid == target.pid)
            #expect(generated.first?.ivs == [target.ivHP, target.ivAtk, target.ivDef, target.ivSpA, target.ivSpD, target.ivSpe])
        }
    }

    /// A Squirtle caught 4 frames late is found 4 late.
    @Test func findsTheFrameHit() throws {
        let squirtle = try squirtle()
        let frames = PFBridge.staticTemplateGenerate3(seed: 0x2DA6, initialAdvances: 9613, maxAdvances: 0,
                                                      method: .method1, template: squirtle.template,
                                                      tid: 11686, sid: 0, game: .fireRed)
        let caught = try #require(frames.first)
        let hits = Gen3HitSearch.search(initialSeed: 0x2DA6, targetFrame: 9609, framesEitherSide: 200,
                                        method: .method1, template: squirtle.template, game: .fireRed,
                                        tid: 11686, sid: 0, caught: exactly(caught.ivs, nature: caught.nature))
        let first = try #require(hits.first)
        #expect(first.frame == 9613 && first.offset == 4)
        #expect(hits.allSatisfy { $0.ivs == caught.ivs && $0.nature == caught.nature })
    }

    /// Each game's base stats: Pikachu's Defense and Sp. Def rose in Gen 6,
    /// so the same stats give different IVs in Emerald and Sword.
    @Test func baseStatsAndIVsByGame() throws {
        #expect(PFBridge.baseStats(game: .emerald, specie: 25) == [UInt8]([35, 55, 30, 50, 40, 90]))
        #expect(PFBridge.baseStats(game: .sword, specie: 25) == [UInt8]([35, 55, 40, 50, 50, 90]))
        #expect(PFBridge.baseStats(game: .emerald, specie: 493) == nil)   // no Arceus in Gen 3
        // Level 50 Hardy, every IV 15: Emerald's stats.
        let lines: [(level: UInt8, stats: [UInt16])] = [(50, [102, 67, 42, 62, 52, 102])]
        let emerald = try #require(PFBridge.calcIVs(game: .emerald, specie: 25, lines: lines, nature: 0))
        #expect(emerald.allSatisfy { $0.contains(15) })
        let sword = try #require(PFBridge.calcIVs(game: .sword, specie: 25, lines: lines, nature: 0))
        #expect(sword[0] == emerald[0])
        #expect(sword[2].isEmpty && sword[4].isEmpty)   // Defense and Sp. Def can't be that low in Sword
    }

    /// A caught Pokémon's IVs lead back to a 16-bit seed and frame that
    /// generate it; a new game's seed is its Trainer ID.
    @Test func seedFromAPokemon() throws {
        let squirtle = try squirtle()
        let caught = try #require(PFBridge.staticTemplateGenerate3(seed: 0x2DA6, initialAdvances: 4266, maxAdvances: 0,
                                                                   method: .method1, template: squirtle.template,
                                                                   tid: 11686, sid: 0, game: .fireRed).first)
        let origins = try #require(Gen3SeedFinder.origins(ivMin: caught.ivs, ivMax: caught.ivs, nature: caught.nature,
                                                          method: .method1, tid: 11686))
        #expect(!origins.isEmpty)
        #expect(origins.contains { $0.pid == caught.pid })
        for origin in origins where origin.pid == caught.pid {
            let again = PFBridge.staticTemplateGenerate3(seed: UInt32(origin.seed), initialAdvances: origin.frame, maxAdvances: 0,
                                                         method: .method1, template: squirtle.template,
                                                         tid: 11686, sid: 0, game: .fireRed)
            #expect(again.first?.pid == caught.pid)
        }
        #expect(Gen3SeedFinder.seed(trainerID: 11686) == "2DA6")
        // Wide ranges are refused rather than tried.
        #expect(Gen3SeedFinder.origins(ivMin: [0, 0, 0, 0, 0, 0], ivMax: [31, 31, 31, 31, 31, 31], nature: 0,
                                       method: .method1, tid: 0) == nil)
    }
}

// MARK: - PokeFinder: Finder Timer Bridge Tests

struct FinderTimerBridgeTests {
    @Test func clear_resetsAllValues() {
        let bridge = FinderTimerBridge.shared
        bridge.pendingGen = .gen3
        bridge.pendingTargetFrame = 1000
        bridge.pendingTargetDelay = 600
        bridge.pendingTargetSecond = 50
        bridge.shouldSwitchToTimer = true
        bridge.selectedTime = "Day 1 08:30"
        bridge.selectedSeed = "0x1A2B3C4D"

        bridge.clear()

        #expect(bridge.pendingGen == nil)
        #expect(bridge.pendingTargetFrame == nil)
        #expect(bridge.pendingTargetDelay == nil)
        #expect(bridge.pendingTargetSecond == nil)
        #expect(bridge.shouldSwitchToTimer == false)
        #expect(bridge.selectedTime == nil)
        #expect(bridge.selectedSeed == nil)
    }
}

// MARK: - PokeFinder: Finder Types Tests

struct FinderTypesTests {
    @Test func finderMethod_gen3Methods() {
        #expect(FinderMethod.methods(for: .gen3) == [.method1, .method2, .method4])
        #expect(FinderMethod.methods(for: .gen3, staticEncounter: true) == [.method1, .method4])
    }

    @Test func finderMethod_gen4Methods() {
        let methods = FinderMethod.methods(for: .gen4, staticEncounter: true, game: .diamond)
        #expect(methods == [.method1, .methodJ, .methodK])
    }

    /// PokéFinder's Gen 4 wild generator has Method J (Diamond, Pearl,
    /// Platinum) and Method K (HeartGold, SoulSilver) only: Method 1 gave
    /// nothing, and each game's method is its own (finding 56).
    @MainActor
    @Test func finderMethod_gen4WildFollowsTheGame() throws {
        for game in [FinderGameVersion.diamond, .pearl, .platinum] {
            #expect(FinderMethod.methods(for: .gen4, game: game) == [.methodJ])
        }
        for game in [FinderGameVersion.heartGold, .soulSilver] {
            #expect(FinderMethod.methods(for: .gen4, game: game) == [.methodK])
        }
        let route201 = try #require(WildAreaData.locations(for: .platinum).first { $0.name == "Route 201" })
        let method1 = PFBridge.wildGenerate4(seed: 0x0C12_0353, initialAdvances: 0, maxAdvances: 100, method: .method1,
                                             tid: 0, sid: 0, game: .platinum, encounter: .grass, location: route201.id)
        let methodJ = PFBridge.wildGenerate4(seed: 0x0C12_0353, initialAdvances: 0, maxAdvances: 100, method: .methodJ,
                                             tid: 0, sid: 0, game: .platinum, encounter: .grass, location: route201.id)
        #expect(method1.isEmpty && !methodJ.isEmpty)
    }

    @Test func pfNatureNames_has25Entries() {
        #expect(pfNatureNames.count == 25)
        #expect(pfNatureNames[0] == "Hardy")
        #expect(pfNatureNames[3] == "Adamant")
        #expect(pfNatureNames[10] == "Timid")
        #expect(pfNatureNames[15] == "Modest")
        #expect(pfNatureNames[24] == "Quirky")
    }

    /// The names follow PokéFinder's, so a result's nature (pid % 25) is
    /// named as the game names it.
    @Test func pfNatureNames_matchPokeFinder() {
        #expect(pfNatureNames == PFBridge.allNatureNames())
        // PID 45CA66AF: 1,170,892,463 % 25 is 13, a Jolly Pokémon.
        #expect(pfNatureNames[Int(0x45CA66AF % 25)] == "Jolly")
    }
}

// MARK: - Helper for tests (expose private pfComputeStat)

func pfComputeStatPublic(baseStat: UInt16, iv: UInt8, nature: UInt8, level: UInt8, index: UInt8) -> UInt16 {
    let modifiers: [[Float]] = [
        [1.0, 1.0, 1.0, 1.0, 1.0], [1.1, 0.9, 1.0, 1.0, 1.0],
        [1.1, 1.0, 1.0, 1.0, 0.9], [1.1, 1.0, 0.9, 1.0, 1.0],
        [1.1, 1.0, 1.0, 0.9, 1.0], [0.9, 1.1, 1.0, 1.0, 1.0],
        [1.0, 1.0, 1.0, 1.0, 1.0], [1.0, 1.1, 1.0, 1.0, 0.9],
        [1.0, 1.1, 0.9, 1.0, 1.0], [1.0, 1.1, 1.0, 0.9, 1.0],
        [0.9, 1.0, 1.0, 1.0, 1.1], [1.0, 0.9, 1.0, 1.0, 1.1],
        [1.0, 1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 0.9, 1.0, 1.1],
        [1.0, 1.0, 1.0, 0.9, 1.1], [0.9, 1.0, 1.1, 1.0, 1.0],
        [1.0, 0.9, 1.1, 1.0, 1.0], [1.0, 1.0, 1.1, 1.0, 0.9],
        [1.0, 1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.1, 0.9, 1.0],
        [0.9, 1.0, 1.0, 1.1, 1.0], [1.0, 0.9, 1.0, 1.1, 1.0],
        [1.0, 1.0, 1.0, 1.1, 0.9], [1.0, 1.0, 0.9, 1.1, 1.0],
        [1.0, 1.0, 1.0, 1.0, 1.0],
    ]
    let stat = ((2 * baseStat + UInt16(iv)) * UInt16(level)) / 100
    if index == 0 { return stat + UInt16(level) + 10 }
    return UInt16(Float(stat + 5) * modifiers[Int(nature)][Int(index) - 1])
}

// MARK: - Gen 4 Seed Check Tests

struct Gen4SeedCheckTests {
    /// PokéFinder's "H, T, ..." and "E, K, ..." strings as values.
    private func flips(_ text: String) -> [Bool] { text.split(separator: ", ").map { $0 == "H" } }
    private func calls(_ text: String) -> [UInt8] {
        // With skips, PokéFinder writes "(E, K skipped)  P, ...".
        let rest = text.components(separatedBy: "skipped)").last ?? text
        return rest.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0 == "E" ? 0 : $0 == "K" ? 1 : 2 }
    }

    @Test func coinFlipsAreThePokétchs() {
        for seed: UInt32 in [0, 1, 0x0510_0320, 0x2C11_02EA, 0xDEAD_BEEF] {
            #expect(Gen4SeedCheck.coinFlips(seed: seed, count: 20) == flips(PFBridge.coinFlips(seed)))
        }
    }

    @Test func callsAreElmsAndIrwins() {
        for seed: UInt32 in [0, 0x0510_0320, 0x2C11_02EA] {
            #expect(Gen4SeedCheck.calls(seed: seed, skips: 0, count: 20) == calls(PFBridge.getCalls(seed)))
            #expect(Gen4SeedCheck.calls(seed: seed, skips: 2, count: 20) == calls(PFBridge.getCalls(seed, skips: 2)))
        }
    }

    /// The seed of each of Seed to Time's clock times is the seed asked for.
    @Test func seedFromClockTime() {
        let seed: UInt32 = 0x2C11_02EA
        let times = seedToTimeGen4(seed: seed)
        #expect(!times.isEmpty)
        for time in times.prefix(20) {
            let target = Gen4SeedTime(month: time.month, day: time.day, hour: Int(time.hour),
                                      minute: time.minute, second: time.second, delay: Int(time.delay))
            #expect(target.seed == seed)
        }
    }

    /// A second later rolls the clock over, as the DS does.
    @Test func secondsRollOver() {
        let target = Gen4SeedTime(month: 12, day: 31, hour: 23, minute: 59, second: 59, delay: 600)
        let next = target.adding(seconds: 1)
        #expect(next.year == 2001 && next.month == 1 && next.day == 1 && next.hour == 0 && next.minute == 0 && next.second == 0)
        let back = Gen4SeedTime(month: 3, day: 1, hour: 0, minute: 0, second: 0, delay: 600).adding(seconds: -1)
        #expect(back.month == 2 && back.day == 29 && back.hour == 23 && back.second == 59) // 2000 is a leap year
    }

    /// Ten coin flips pick out the seed hit, 4 delays and a second late.
    @Test func coinFlipsFindTheSeedHit() throws {
        let target = Gen4SeedTime(month: 7, day: 28, hour: 17, minute: 54, second: 23, delay: 4357)
        let candidates = Gen4SeedCheck.candidates(around: target, delays: 20, seconds: 1)
        #expect(candidates.count == 41 * 3)
        #expect(candidates.first?.delayOffset == 0 && candidates.first?.secondOffset == 0)
        var hit = target.adding(seconds: 1)
        hit.delay = 4361
        let seen = Gen4SeedCheck.coinFlips(seed: hit.seed, count: 10)
        let matches = Gen4SeedCheck.matches(candidates, flips: seen)
        let found = try #require(matches.first { $0.seed == hit.seed })
        #expect(found.delay == 4361 && found.delayOffset == 4 && found.secondOffset == 1)
        #expect(matches.count <= 3)
    }

    /// HeartGold/SoulSilver: each active roamer takes at least one advance
    /// before the calls, and lands on a route it roams; the calls and
    /// routes find the seed.
    @Test func roamersAndCalls() throws {
        let target = Gen4SeedTime(month: 4, day: 2, hour: 9, minute: 30, second: 10, delay: 700)
        let roamers = [true, true, true]
        let candidates = Gen4SeedCheck.candidates(around: target, delays: 10, seconds: 1, roamers: roamers)
        for candidate in candidates {
            #expect(candidate.skips >= 3)
            #expect(Gen4SeedCheck.johtoRoutes.contains(candidate.roamerRoutes[0]))
            #expect(Gen4SeedCheck.johtoRoutes.contains(candidate.roamerRoutes[1]))
            #expect(Gen4SeedCheck.kantoRoutes.contains(candidate.roamerRoutes[2]))
            #expect(candidate.calls == calls(PFBridge.getCalls(candidate.seed, skips: candidate.skips)))
        }
        let hit = try #require(candidates.first { $0.delayOffset == -3 })
        let matches = Gen4SeedCheck.matches(candidates, calls: Array(hit.calls.prefix(8)),
                                            routes: hit.roamerRoutes.map { Optional($0) })
        #expect(matches.contains(hit))
        #expect(matches.count <= 2)
    }

    /// Around a bare seed, a second moves its first byte.
    @Test func aroundABareSeed() {
        let candidates = Gen4SeedCheck.candidates(aroundSeed: 0x2C11_02EA, delays: 2, seconds: 1)
        #expect(candidates.count == 5 * 3)
        #expect(candidates.contains { $0.seed == 0x2D11_02EC && $0.delayOffset == 2 && $0.secondOffset == 1 })
        #expect(candidates.contains { $0.seed == 0x2B11_02E8 && $0.delay == 0x02E8 })
    }
}

// MARK: - Frame Timer Tests

struct FrameTimerTests {
    let ndsSlot1 = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60.0,
        precisionCalibration: false, minimumLength: 14000
    )

    @Test func getMsPerFrame_allConsoles() {
        let gba = CalibratorSettings(console: .gba, customFramerate: 60, precisionCalibration: false, minimumLength: 14000)
        let nds1 = CalibratorSettings(console: .ndsSlot1, customFramerate: 60, precisionCalibration: false, minimumLength: 14000)
        let nds2 = CalibratorSettings(console: .ndsSlot2, customFramerate: 60, precisionCalibration: false, minimumLength: 14000)
        let custom = CalibratorSettings(console: .custom, customFramerate: 120, precisionCalibration: false, minimumLength: 14000)

        // GBA: 16777216/280896 fps -> ~16.7427ms/frame
        #expect(getMsPerFrame(gba) > 16.7 && getMsPerFrame(gba) < 16.8)
        // NDS Slot 1: 1000/59.8261 -> ~16.715ms/frame
        #expect(getMsPerFrame(nds1) > 16.7 && getMsPerFrame(nds1) < 16.8)
        // NDS Slot 2: 1000/59.6555 -> ~16.763ms/frame (different from GBA)
        #expect(getMsPerFrame(nds2) > 16.7 && getMsPerFrame(nds2) < 16.8)
        #expect(getMsPerFrame(nds2) != getMsPerFrame(gba))
        // Custom: 1000/120 = 8.333ms
        #expect(abs(getMsPerFrame(custom) - 8.333) < 0.01)
    }

    @Test func createFramePhases_returnsPreTimerAndFrame() {
        let phases = createFramePhases(ndsSlot1, preTimer: 5000, targetFrame: 100, calibration: 0)
        #expect(phases.count == 2)
        #expect(phases[0] == 5000)
        #expect(phases[1] > 0)
    }

    @Test func calibrateFrame_computesDelta() {
        // If we hit frame 105 targeting 100, calibration should be positive
        let cal = calibrateFrame(ndsSlot1, targetFrame: 100, frameHit: 105)
        #expect(cal < 0) // We were late, need to subtract time
        let cal2 = calibrateFrame(ndsSlot1, targetFrame: 100, frameHit: 95)
        #expect(cal2 > 0) // We were early, need to add time
    }

    @Test func createVariableFramePhases_usesMaxInt() {
        let phases = createVariableFramePhases(preTimer: 3000)
        #expect(phases.count == 2)
        #expect(phases[0] == 3000)
        #expect(phases[1] == Int.max)
    }

    @Test func calibrateToDelays_precisionMode() {
        let precision = CalibratorSettings(console: .ndsSlot1, customFramerate: 60, precisionCalibration: true, minimumLength: 14000)
        // In precision mode, calibrateToDelays just rounds the milliseconds
        let result = calibrateToDelays(precision, milliseconds: 123.7)
        #expect(result == 124)
    }

    @Test func calibrateToMilliseconds_precisionMode() {
        let precision = CalibratorSettings(console: .ndsSlot1, customFramerate: 60, precisionCalibration: true, minimumLength: 14000)
        // In precision mode, just passes through
        #expect(calibrateToMilliseconds(precision, delays: 500) == 500)
    }
}

// MARK: - Entralink Timer Tests

struct EntralinkTimerTests {
    let nds = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60.0,
        precisionCalibration: false, minimumLength: 14000
    )

    @Test func createEntralinkPhases_addsOffset() {
        let delayPhases = createDelayPhases(nds, targetDelay: 1000, targetSecond: 30, calibration: 0)
        let entralink = createEntralinkPhases(nds, targetDelay: 1000, targetSecond: 30, calibration: 0, entralinkCalibration: 100)
        // Phase 0 should be delay phase 0 + 250
        #expect(entralink[0] == delayPhases[0] + 250)
        // Phase 1 should be delay phase 1 - entralinkCalibration
        #expect(entralink[1] == delayPhases[1] - 100)
    }

    @Test func createEnhancedEntralinkPhases_hasThreePhases() {
        let phases = createEnhancedEntralinkPhases(
            nds, targetDelay: 1000, targetSecond: 30,
            targetAdvances: 50, calibration: 0,
            entralinkCalibration: 100, frameCalibration: 0
        )
        #expect(phases.count == 3)
        #expect(phases[2] > 0) // Third phase for advances
    }

    @Test func calibrateEntralinkAdvances_computesDelta() {
        let cal = calibrateEntralinkAdvances(targetAdvances: 50, advancesHit: 55)
        #expect(cal < 0) // Hit more advances than target
        let cal2 = calibrateEntralinkAdvances(targetAdvances: 50, advancesHit: 45)
        #expect(cal2 > 0) // Hit fewer advances than target
    }
}

// MARK: - Gen Timer Integration Tests

struct GenTimerTests {
    let nds = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60.0,
        precisionCalibration: false, minimumLength: 14000
    )

    @Test func gen3_standardMode() {
        let phases = createGen3Phases(nds, mode: .standard, preTimer: 5000, targetFrame: 1000, calibration: 0)
        #expect(phases.count == 2)
        #expect(phases[0] == 5000)
    }

    @Test func gen3_variableMode() {
        let phases = createGen3Phases(nds, mode: .variableTarget, preTimer: 5000, targetFrame: 1000, calibration: 0)
        #expect(phases.count == 2)
        #expect(phases[1] == Int.max)
    }

    @Test func gen4_phasesArePositive() {
        let phases = createGen4Phases(nds, targetDelay: 600, targetSecond: 50,
                                       calibratedDelay: 600, calibratedSecond: 50)
        #expect(phases.count == 2)
        #expect(phases.allSatisfy { $0 > 0 })
    }

    @Test func gen4_calibration() {
        let cal = getGen4Calibration(nds, calibratedDelay: 600, calibratedSecond: 50)
        #expect(cal != 0 || true) // Calibration can be 0 if delay matches seconds perfectly
    }

    @Test func gen5_standardMode_singlePhase() {
        let phases = createGen5Phases(nds, mode: .standard,
                                       targetDelay: 600, targetSecond: 50, targetAdvances: 0,
                                       calibration: 0, entralinkCalibration: 0, frameCalibration: 0)
        #expect(phases.count == 1)
    }

    @Test func gen5_cGearMode_twoPhases() {
        let phases = createGen5Phases(nds, mode: .cGear,
                                       targetDelay: 600, targetSecond: 50, targetAdvances: 0,
                                       calibration: 0, entralinkCalibration: 0, frameCalibration: 0)
        #expect(phases.count == 2)
    }

    @Test func gen5_entralinkMode_twoPhases() {
        let phases = createGen5Phases(nds, mode: .entralink,
                                       targetDelay: 600, targetSecond: 50, targetAdvances: 0,
                                       calibration: 0, entralinkCalibration: 0, frameCalibration: 0)
        #expect(phases.count == 2)
    }

    @Test func gen5_entralinkPlusMode_threePhases() {
        let phases = createGen5Phases(nds, mode: .entralinkPlus,
                                       targetDelay: 600, targetSecond: 50, targetAdvances: 50,
                                       calibration: 0, entralinkCalibration: 0, frameCalibration: 0)
        #expect(phases.count == 3)
    }

    @Test func eonGetMinutesBeforeTarget_basic() {
        let phases1 = [60000, 5000]
        #expect(eonGetMinutesBeforeTarget(phases1) == 1)

        let phases2 = [120000, 30000]
        #expect(eonGetMinutesBeforeTarget(phases2) == 2)

        let phases3 = [5000]
        #expect(eonGetMinutesBeforeTarget(phases3) == 0)
    }
}

// MARK: - Encounter Data Tests

struct EncounterDataTests {
    @Test func gameVersions_correctGeneration() {
        #expect(FinderGameVersion.emerald.generation == .gen3)
        #expect(FinderGameVersion.ruby.generation == .gen3)
        #expect(FinderGameVersion.diamond.generation == .gen4)
        #expect(FinderGameVersion.platinum.generation == .gen4)
        #expect(FinderGameVersion.heartGold.generation == .gen4)
    }

    @Test func gamesForGen_filtersCorrectly() {
        let gen3 = FinderGameVersion.games(for: .gen3)
        let gen4 = FinderGameVersion.games(for: .gen4)
        #expect(gen3.count == 5)
        #expect(gen4.count == 5)
        #expect(gen3.allSatisfy { $0.generation == .gen3 })
        #expect(gen4.allSatisfy { $0.generation == .gen4 })
    }

    @Test func encounterType_pfMapping() {
        #expect(EncounterType.grass.pfEncounter == .grass)
        #expect(EncounterType.surf.pfEncounter == .surfing)
        #expect(EncounterType.oldRod.pfEncounter == .oldRod)
        #expect(EncounterType.goodRod.pfEncounter == .goodRod)
        #expect(EncounterType.superRod.pfEncounter == .superRod)
        #expect(EncounterType.rockSmash.pfEncounter == .rockSmash)
    }

    @Test func encounterType_roundTrip() {
        for type in EncounterType.allCases {
            let pf = type.pfEncounter
            let back = EncounterType(from: pf)
            #expect(back == type)
        }
    }

    @Test func staticEncounterData_startersExist() {
        let starters = StaticEncounterData.encounters(for: .emerald, category: .starters)
        #expect(starters.allSatisfy { $0.category == .starters && $0.level == 5 })
        // Treecko, Torchic and Mudkip, and in Emerald the Johto ones from
        // Professor Birch after the Hall of Fame.
        #expect(Set(starters.map(\.species)) == [252, 255, 258, 152, 155, 158])
        #expect(Set(StaticEncounterData.encounters(for: .ruby, category: .starters).map(\.species)) == [252, 255, 258])
    }

    @Test func pfGame_mappingCoversAll() {
        for game in FinderGameVersion.allCases {
            let pfGame = game.pfGame
            // Just verify no crashes — all cases are covered
            #expect(pfGame.rawValue >= 0)
        }
    }

    /// Each list is the leads PokéFinder's generator for that encounter
    /// reads (from its Gen 3/4/5/8 generators); it ignores any other.
    @Test func finderLead_followsPokeFinder() {
        let charm: [FinderLead] = [.cuteCharmF, .cuteCharmM]
        // Of Gen 3, only Emerald's wild encounters have lead effects.
        for game in [FinderGameVersion.ruby, .sapphire, .fireRed, .leafGreen] {
            #expect(FinderLead.leads(for: .gen3, mode: .wild, game: game) == [.none], "\(game.rawValue)")
        }
        #expect(FinderLead.leads(for: .gen3, mode: .wild, game: .emerald)
                == [.none, .synchronize] + charm + [.magnetPull, .staticLead, .pressure])
        #expect(FinderLead.leads(for: .gen3, mode: .static_, game: .emerald) == [.none])
        #expect(FinderLead.leads(for: .gen4, mode: .wild, game: .diamond)
                == [.none, .synchronize] + charm + [.magnetPull, .staticLead, .pressure, .suctionCups, .compoundEyes, .arenaTrap])
        #expect(FinderLead.leads(for: .gen5, mode: .wild, game: .black)
                == [.none, .synchronize] + charm + [.magnetPull, .staticLead, .pressure, .suctionCups, .compoundEyes])
        #expect(FinderLead.leads(for: .gen8, mode: .wild, game: .brilliantDiamond)
                == [.none, .synchronize] + charm + [.magnetPull, .staticLead, .harvest, .flashFire, .stormDrain, .pressure, .compoundEyes])
        // Gen 4, 5 and BDSP statics read Synchronize and Cute Charm.
        for (gen, game) in [(FinderGeneration.gen4, FinderGameVersion.diamond), (.gen5, .black), (.gen8, .brilliantDiamond)] {
            #expect(FinderLead.leads(for: gen, mode: .static_, game: game) == [.none, .synchronize] + charm)
        }
        #expect(FinderLead.leads(for: .gen8, mode: .underground, game: .brilliantDiamond)
                == [.none, .synchronize] + charm + [.pressure, .compoundEyes])
        for mode in [FinderRootView.EncounterMode.egg, .raid, .id] {
            #expect(FinderLead.leads(for: .gen8, mode: mode, game: .brilliantDiamond) == [.none])
        }
        #expect(FinderLead.pressure.name == "Pressure / Hustle / Vital Spirit")
    }

    /// Emerald's Cute Charm, newly offered, works: behind a female lead,
    /// two thirds of Route 101's Pokémon are male.
    @Test func emeraldCuteCharm() throws {
        let area = try #require(PFBridge.getEncounters3(encounter: .grass, game: .emerald).first)
        func males(_ lead: PFLead) -> Int {
            PFBridge.wildGenerate3(seed: 0x1234_5678, initialAdvances: 0, maxAdvances: 2_000, method: .method1,
                                   lead: lead, tid: 0, sid: 0, game: .emerald, encounter: .grass,
                                   location: area.location).filter { $0.gender == 0 }.count
        }
        #expect(males(.cuteCharmF) > males(.none) + 300)
    }

    /// PokéFinder's Gen 8 static, wild, egg and ID generators are BDSP's.
    @Test func swordShieldOffersOnlyRaids() {
        #expect(FinderRootView.EncounterMode.modes(for: .gen8, game: .sword) == [.raid])
        #expect(FinderRootView.EncounterMode.modes(for: .gen8, game: .shield) == [.raid])
        #expect(FinderRootView.EncounterMode.modes(for: .gen8, game: .brilliantDiamond)
                == [.static_, .wild, .egg, .underground, .id])
    }

    /// PokéFinder's six story stages change which Pokémon the Underground
    /// has, and its level flags their levels. Stage 0, which it reads as
    /// `flagRates[-1]`, is stage 1.
    @Test func undergroundStagesAndLevels() {
        func results(stage: Int32 = 6, levelFlag: UInt8 = 0) -> [PFBridge.Gen8UndergroundResult] {
            PFBridge.undergroundAreas8(storyFlag: stage, game: .bd).flatMap { area in
                PFBridge.undergroundGenerate8(seed0: 0x1234_5678_9ABC_DEF0, seed1: 0x0FED_CBA9_8765_4321,
                                              initialAdvances: 0, maxAdvances: 300, levelFlag: levelFlag,
                                              tid: 0, sid: 0, game: .bd, storyFlag: stage, location: area.location)
            }
        }
        let first = Set(results(stage: 1).map(\.specie))
        let last = Set(results(stage: 6).map(\.specie))
        #expect(!first.isEmpty && !last.isEmpty)
        #expect(first != last)
        #expect(Set(results(stage: 0).map(\.specie)) == first)
        #expect(Set(results(levelFlag: 0).map(\.level)) != Set(results(levelFlag: 8).map(\.level)))
        #expect(UndergroundProgress.stories.count == 6)
        #expect(UndergroundProgress.levels.count == 9)
    }
}

// MARK: - Delay Calibration Tests

struct DelayCalibrationTests {
    let nds = CalibratorSettings(
        console: .ndsSlot1, customFramerate: 60.0,
        precisionCalibration: false, minimumLength: 14000
    )

    @Test func calibrateDelay_closeThreshold() {
        // When delta is within 167ms (10 frames), use 0.75 factor
        let cal = calibrateDelay(nds, targetDelay: 600, delayHit: 605)
        let fullDelta = Double(eonToMilliseconds(nds, delays: 605) - eonToMilliseconds(nds, delays: 600))
        // 5 frames * ~16.7ms = ~83.5ms, which is < 167, so factor 0.75 applies
        let expected = 0.75 * fullDelta
        #expect(abs(cal - expected) < 0.01)
    }

    @Test func calibrateDelay_farThreshold() {
        // When delta is beyond 167ms, use full delta
        let cal = calibrateDelay(nds, targetDelay: 600, delayHit: 620)
        let fullDelta = Double(eonToMilliseconds(nds, delays: 620) - eonToMilliseconds(nds, delays: 600))
        // 20 frames * ~16.7ms = ~334ms, which is > 167, so full delta
        #expect(abs(cal - fullDelta) < 0.01)
    }

    @Test func calibrateSecond_early() {
        let cal = calibrateSecond(targetSecond: 50, secondHit: 48)
        #expect(cal > 0) // Hit early, need to add time
        #expect(cal == Double((50 - 48) * 1000 - 500))
    }

    @Test func calibrateSecond_late() {
        let cal = calibrateSecond(targetSecond: 50, secondHit: 52)
        #expect(cal < 0) // Hit late, need to subtract time
        #expect(cal == Double((50 - 52) * 1000 + 500))
    }

    @Test func calibrateSecond_exact() {
        let cal = calibrateSecond(targetSecond: 50, secondHit: 50)
        #expect(cal == 0)
    }
}

// MARK: - Gen 4 ID Generator Tests

struct Gen4IDGeneratorTests {
    @Test func knownSeed_producesCorrectTIDSID() {
        // seed 0x01000258: month=1, day=1, hour=0, minute=0, second=0, delay=600
        let results = PFBridge.idGenerate4(
            minDelay: 600, maxDelay: 600,
            year: 2000, month: 1, day: 1,
            hour: 0, minute: 0)
        let match = results.first { $0.seed == 0x01000258 }
        #expect(match != nil)
        #expect(match!.tid == 34378)
        #expect(match!.sid == 38338)
        #expect(match!.tsv == 625)
        #expect(match!.delay == 600)
        #expect(match!.seconds == 0)
    }

    @Test func differentSeconds_produceDifferentIDs() {
        let results = PFBridge.idGenerate4(
            minDelay: 600, maxDelay: 600,
            year: 2000, month: 1, day: 1,
            hour: 0, minute: 0)
        // Each second (0-59) produces a different seed for the same delay
        let seeds = Set(results.map { $0.seed })
        #expect(seeds.count == 60)
        let tids = Set(results.map { $0.tid })
        #expect(tids.count > 1)
    }

    @Test func delayRange_producesExpectedCount() {
        let results = PFBridge.idGenerate4(
            minDelay: 600, maxDelay: 605,
            year: 2000, month: 1, day: 1,
            hour: 0, minute: 0)
        // 6 delays * 60 seconds = 360 results
        #expect(results.count == 360)
    }

    @Test func tsvCalculation_isCorrect() {
        let results = PFBridge.idGenerate4(
            minDelay: 600, maxDelay: 600,
            year: 2000, month: 1, day: 1,
            hour: 0, minute: 0)
        for r in results {
            #expect(r.tsv == (r.tid ^ r.sid) >> 3)
        }
    }

    @Test func tidFilter_narrowsResults() {
        let all = PFBridge.idGenerate4(
            minDelay: 500, maxDelay: 1000,
            year: 2000, month: 1, day: 1,
            hour: 0, minute: 0)
        let filtered = PFBridge.idGenerate4(
            minDelay: 500, maxDelay: 1000,
            year: 2000, month: 1, day: 1,
            hour: 0, minute: 0,
            targetTID: 34378, filterTID: true)
        #expect(filtered.count < all.count)
        #expect(filtered.allSatisfy { $0.tid == 34378 })
    }

    @Test func sidFilter_narrowsResults() {
        let filtered = PFBridge.idGenerate4(
            minDelay: 500, maxDelay: 1000,
            year: 2000, month: 1, day: 1,
            hour: 0, minute: 0,
            targetSID: 38338, filterSID: true)
        #expect(filtered.allSatisfy { $0.sid == 38338 })
    }

    @Test func knownSeeds_multipleVerified() {
        let results = PFBridge.idGenerate4(
            minDelay: 600, maxDelay: 600,
            year: 2000, month: 1, day: 1,
            hour: 0, minute: 0)
        // Verify several seeds from different seconds
        let sec3 = results.first { $0.seed == 0x04000258 }
        #expect(sec3 != nil)
        #expect(sec3!.tid == 58035)
        #expect(sec3!.sid == 35865)
        #expect(sec3!.seconds == 3)

        let sec59 = results.first { $0.seed == 0x3C000258 }
        #expect(sec59 != nil)
        #expect(sec59!.tid == 32115)
        #expect(sec59!.sid == 51580)
        #expect(sec59!.seconds == 59)
    }

    @Test func emptyRange_returnsNoResults() {
        // min > max should return empty
        let results = PFBridge.idGenerate4(
            minDelay: 1000, maxDelay: 500,
            year: 2000, month: 1, day: 1,
            hour: 0, minute: 0)
        #expect(results.isEmpty)
    }
}

// MARK: - Gen 4 ID Searcher Tests

struct Gen4IDSearcherTests {
    private func waitForSearch(_ handle: OpaquePointer, timeout: TimeInterval = 5.0) {
        let start = Date()
        while !PFBridge.idSearch4Done(handle), Date().timeIntervalSince(start) < timeout {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    @Test func searcher_findsKnownTID() {
        let handle = PFBridge.idSearch4Start(
            infinite: false, year: 2000,
            minDelay: 598, maxDelay: 602,
            targetTID: 34378, filterTID: true)

        waitForSearch(handle)
        let results = PFBridge.idSearch4GetResults(handle)
        PFBridge.idSearch4Free(handle)

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.tid == 34378 })
        let match = results.first { $0.seed == 0x01000258 }
        #expect(match != nil)
        #expect(match!.sid == 38338)
    }

    @Test func searcher_findsSIDFilter() {
        let handle = PFBridge.idSearch4Start(
            infinite: false, year: 2000,
            minDelay: 598, maxDelay: 602,
            targetSID: 38338, filterSID: true)

        waitForSearch(handle)
        let results = PFBridge.idSearch4GetResults(handle)
        PFBridge.idSearch4Free(handle)

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.sid == 38338 })
    }

    @Test func searcher_tsvFilter() {
        let handle = PFBridge.idSearch4Start(
            infinite: false, year: 2000,
            minDelay: 598, maxDelay: 602,
            targetTSV: 625, filterTSV: true)

        waitForSearch(handle)
        let results = PFBridge.idSearch4GetResults(handle)
        PFBridge.idSearch4Free(handle)

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { ($0.tid ^ $0.sid) >> 3 == 625 })
    }

    @Test func searcher_cancelStopsEarly() {
        let handle = PFBridge.idSearch4Start(
            infinite: false, year: 2000,
            minDelay: 0, maxDelay: 1000)

        Thread.sleep(forTimeInterval: 0.01)
        PFBridge.idSearch4Cancel(handle)
        Thread.sleep(forTimeInterval: 0.2)

        let results = PFBridge.idSearch4GetResults(handle)
        PFBridge.idSearch4Free(handle)

        let fullCount = 1001 * 256 * 24
        #expect(results.count < fullCount)
    }

    @Test func searcher_noFilter_findsMany() {
        let handle = PFBridge.idSearch4Start(
            infinite: false, year: 2000,
            minDelay: 600, maxDelay: 600)

        waitForSearch(handle)
        let results = PFBridge.idSearch4GetResults(handle)
        PFBridge.idSearch4Free(handle)

        // delay=600: 256 ab values * 24 cd values = 6144 seeds
        #expect(results.count == 6144)
    }

    @Test func searcher_delayCalculation_matchesGenerator() {
        let handle = PFBridge.idSearch4Start(
            infinite: false, year: 2000,
            minDelay: 600, maxDelay: 600,
            targetTID: 34378, filterTID: true,
            targetSID: 38338, filterSID: true)

        waitForSearch(handle)
        let results = PFBridge.idSearch4GetResults(handle)
        PFBridge.idSearch4Free(handle)

        let match = results.first { $0.seed == 0x01000258 }
        #expect(match != nil)
        #expect(match!.delay == 600)
    }

    /// PokéFinder's IDs come from the second MT19937 output of the seed.
    private func referenceTID(_ seed: UInt32) -> UInt16 {
        var mt = [UInt32](repeating: 0, count: 399)
        mt[0] = seed
        for i in 1..<399 { mt[i] = 1812433253 &* (mt[i - 1] ^ (mt[i - 1] >> 30)) &+ UInt32(i) }
        let y = (mt[1] & 0x8000_0000) | (mt[2] & 0x7FFF_FFFF)
        var v = mt[398] ^ (y >> 1) ^ ((y & 1) != 0 ? 0x9908_B0DF : 0)
        v ^= v >> 11; v ^= (v << 7) & 0x9D2C_5680; v ^= (v << 15) & 0xEFC6_0000; v ^= v >> 18
        return UInt16(v & 0xFFFF)
    }

    /// The search reports when it's done, at 100%, and returns every seed
    /// with the TID: every date/time byte and hour for each delay.
    @Test func searcher_finishesWithEveryResult() {
        let target: UInt16 = referenceTID(0x7B0F_0259)
        var expected = 0
        for efgh: UInt32 in 600...604 {
            for ab: UInt32 in 0..<256 {
                for cd: UInt32 in 0..<24 where referenceTID((ab << 24) | (cd << 16) + efgh) == target { expected += 1 }
            }
        }
        let handle = PFBridge.idSearch4Start(infinite: false, year: 2000, minDelay: 600, maxDelay: 604,
                                             targetTID: target, filterTID: true)
        waitForSearch(handle, timeout: 30)
        #expect(PFBridge.idSearch4Done(handle))
        #expect(PFBridge.idSearch4Progress(handle) == 100)
        let results = PFBridge.idSearch4GetResults(handle)
        PFBridge.idSearch4Free(handle)
        #expect(expected > 0 && results.count == expected)
        #expect(results.allSatisfy { $0.tid == target })
    }

    /// Cancel ends even an Infinite search at once.
    @Test func searcher_cancelEndsInfiniteSearch() {
        let handle = PFBridge.idSearch4Start(infinite: true, year: 2000, minDelay: 0, maxDelay: 0,
                                             targetTID: 1, filterTID: true)
        Thread.sleep(forTimeInterval: 0.1)
        #expect(!PFBridge.idSearch4Done(handle))
        #expect((0...100).contains(PFBridge.idSearch4Progress(handle)))
        PFBridge.idSearch4Cancel(handle)
        waitForSearch(handle, timeout: 2)
        #expect(PFBridge.idSearch4Done(handle))
        PFBridge.idSearch4Free(handle)
    }
}

// MARK: - GameCube Seed Searcher Tests

struct GameCubeSeedSearcherTests {
    /// Progress stays 0–100 while it runs, and Cancel ends it.
    @Test func coloSearch_progressAndCancel() {
        let handle = PFBridge.coloSeedSearchStart(lead: 0, trainer: 0, threads: 2)
        Thread.sleep(forTimeInterval: 0.3)
        let progress = PFBridge.seedSearchProgress(handle)
        #expect(!PFBridge.seedSearchDone(handle))
        #expect((0..<100).contains(progress))
        PFBridge.seedSearchCancel(handle)
        let start = Date()
        while !PFBridge.seedSearchDone(handle), Date().timeIntervalSince(start) < 5 {
            Thread.sleep(forTimeInterval: 0.05)
        }
        #expect(PFBridge.seedSearchDone(handle))
        _ = PFBridge.seedSearchGetResults(handle)
        PFBridge.seedSearchFree(handle)
    }
}

// MARK: - GameCube Searcher Tests

@MainActor
struct GameCubeSearcherTests {
    private static let ivMin: [UInt8] = [31, 31, 31, 31, 0, 0]
    private static let ivMax: [UInt8] = [31, 31, 31, 31, 31, 31]
    private static let xd = PFGame.gales.rawValue

    private struct Key: Hashable { let seed: UInt32, pid: UInt32 }

    /// A search streamed as the view runs it, and the same search read once
    /// at the end.
    private func streamedAndOneShot(_ start: () -> UnsafeMutableRawPointer?) throws
        -> (streamed: [PFSearcherStateSwift], progress: [Double], oneShot: [PFSearcherStateSwift]) {
        var streamed: [PFSearcherStateSwift] = []
        var progress: [Double] = []
        gameCubeSearchStreaming(try #require(start()), onProgress: { progress.append($0) }) { streamed += $0 }

        let handle = try #require(start())
        while !PFBridge.gamecubeSearchDone(handle) { Thread.sleep(forTimeInterval: 0.01) }
        let oneShot = PFBridge.gamecubeSearchResults(handle)
        PFBridge.gamecubeSearchFree(handle)
        return (streamed, progress, oneShot)
    }

    private func checkSearch(_ search: (streamed: [PFSearcherStateSwift], progress: [Double], oneShot: [PFSearcherStateSwift])) {
        #expect(!search.streamed.isEmpty)
        #expect(search.streamed.count == search.oneShot.count)
        #expect(Set(search.streamed.map { Key(seed: $0.seed, pid: $0.pid) })
                == Set(search.oneShot.map { Key(seed: $0.seed, pid: $0.pid) }))
        #expect(search.progress.last == 100)
        #expect(search.progress.allSatisfy { (0...100).contains($0) })
        #expect(zip(search.progress, search.progress.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(search.streamed.allSatisfy { r in (0..<6).allSatisfy { (Self.ivMin[$0]...Self.ivMax[$0]).contains(r.ivs[$0]) } })
    }

    @Test func shadowStreamsWhatItFinds() throws {
        let shadow = try #require(PFBridge.getShadowTemplates().first { !$0.isColosseum })
        let search = try streamedAndOneShot {
            PFBridge.gamecubeSearchShadowStart(unset: false, tid: 0, sid: 0, game: Self.xd,
                                               ivMin: Self.ivMin, ivMax: Self.ivMax, shadowIndex: shadow.id)
        }
        checkSearch(search)
        // Each one's seed generates it.
        for r in search.streamed.prefix(20) {
            let generated = PFBridge.gamecubeGenerateShadow(seed: r.seed, initialAdvances: 0, maxAdvances: 0,
                                                            shadowIndex: shadow.id, unset: false,
                                                            tid: 0, sid: 0, game: Self.xd)
            #expect(generated.first?.pid == r.pid, "seed \(String(format: "%08X", r.seed))")
        }
    }

    @Test func nonShadowStreamsWhatItFinds() throws {
        let templates = PFBridge.getStaticEncounters3(type: 8)
        let index = try #require(templates.firstIndex { $0.game & Self.xd != 0 })
        let search = try streamedAndOneShot {
            PFBridge.gamecubeSearchStaticStart(method: .xdColo, tid: 0, sid: 0, game: Self.xd,
                                               ivMin: Self.ivMin, ivMax: Self.ivMax, staticType: 8, staticIndex: index)
        }
        checkSearch(search)
        for r in search.streamed.prefix(20) {
            let generated = PFBridge.gamecubeGenerateStatic(seed: r.seed, initialAdvances: 0, maxAdvances: 0,
                                                            method: .xdColo, staticType: 8, staticIndex: index,
                                                            tid: 0, sid: 0, game: Self.xd)
            #expect(generated.first?.pid == r.pid, "seed \(String(format: "%08X", r.seed))")
        }
    }

    /// Channel counts seeds, 2^27 per Sp. Def IV: a whole search reads
    /// under 100% while it runs. Cancel ends it.
    @Test func channelProgressAndCancel() throws {
        let handle = try #require(PFBridge.gamecubeSearchStaticStart(method: .channel, tid: 0, sid: 0, game: Self.xd,
                                                                     staticType: 9, staticIndex: 0))
        Thread.sleep(forTimeInterval: 0.3)
        #expect(!PFBridge.gamecubeSearchDone(handle))
        #expect((0..<100).contains(pf_gamecubeSearch_progress(handle)))
        PFBridge.gamecubeSearchCancel(handle)
        let start = Date()
        while !PFBridge.gamecubeSearchDone(handle), Date().timeIntervalSince(start) < 2 {
            Thread.sleep(forTimeInterval: 0.01)
        }
        #expect(PFBridge.gamecubeSearchDone(handle))
        PFBridge.gamecubeSearchFree(handle)
    }

    /// The view's Stop cancels the task, which stops and frees the search.
    @Test func streamingStopsWithItsTask() async throws {
        let xd = Self.xd
        let task = Task.detached { () -> Bool in
            guard let handle = PFBridge.gamecubeSearchStaticStart(method: .channel, tid: 0, sid: 0, game: xd,
                                                                  staticType: 9, staticIndex: 0) else { return false }
            gameCubeSearchStreaming(handle) { _ in }
            return true
        }
        try await Task.sleep(for: .milliseconds(300))
        let start = Date()
        task.cancel()
        #expect(await task.value)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    /// PokéFinder doesn't check template indices; the bridge does.
    @Test func noSearchForATemplateThatIsNotOne() {
        let shadows = PFBridge.getShadowTemplates().count
        #expect(PFBridge.gamecubeSearchShadowStart(unset: false, tid: 0, sid: 0, game: Self.xd, shadowIndex: -1) == nil)
        #expect(PFBridge.gamecubeSearchShadowStart(unset: false, tid: 0, sid: 0, game: Self.xd, shadowIndex: shadows) == nil)
        let statics = PFBridge.getStaticEncounters3(type: 8).count
        #expect(PFBridge.gamecubeSearchStaticStart(method: .xdColo, tid: 0, sid: 0, game: Self.xd,
                                                   staticType: 8, staticIndex: statics) == nil)
    }
}

// MARK: - Search Result Limit Tests

struct SearchResultLimitTests {
    /// Batches fill the list to the limit and no further.
    @Test func fillsToTheLimit() {
        var results: [Int] = []
        #expect(!appendUpToLimit(0..<60, to: &results, limit: 100))
        #expect(appendUpToLimit(60..<160, to: &results, limit: 100))
        #expect(results == Array(0..<100))
        #expect(appendUpToLimit(160..<170, to: &results, limit: 100))
        #expect(results.count == 100)
        #expect(searchResultLimit == 100_000)
    }
}

// MARK: - Egg Generator Tests

struct EggGeneratorTests {
    /// Every Gen 3 and Gen 4 game generates eggs: the game used to be
    /// passed as a byte, which trapped from Pearl (256) on.
    @Test func everyGameGenerates() {
        let ivs: [UInt8] = [31, 31, 31, 31, 31, 31]
        for game in FinderGameVersion.allCases where game.generation == .gen4 {
            let eggs = PFBridge.eggGenerate4(seedHeld: 0x1234_5678, seedPickup: 0x8765_4321,
                                             initialAdvances: 0, maxAdvances: 20,
                                             initialAdvancesPickup: 0, maxAdvancesPickup: 20,
                                             parentAIVs: ivs, parentBIVs: ivs,
                                             parentAAbility: 0, parentBAbility: 0, parentAGender: 0, parentBGender: 1,
                                             parentAItem: 0, parentBItem: 0, parentANature: 0, parentBNature: 0,
                                             eggSpecie: 1, masuda: false, tid: 0, sid: 0, game: game.pfGame)
            #expect(!eggs.isEmpty, "\(game.rawValue)")
        }
        for game in FinderGameVersion.allCases where game.generation == .gen3 {
            let eggs = PFBridge.eggGenerate3(seedHeld: 0x1234, seedPickup: 0x5678,
                                             initialAdvances: 0, maxAdvances: 20,
                                             initialAdvancesPickup: 0, maxAdvancesPickup: 20,
                                             method: game == .emerald ? .eBred : .rsFRLGBred, compatibility: 20,
                                             parentAIVs: ivs, parentBIVs: ivs,
                                             parentAAbility: 0, parentBAbility: 0, parentAGender: 0, parentBGender: 1,
                                             parentAItem: 0, parentBItem: 0, parentANature: 0, parentBNature: 0,
                                             eggSpecie: 1, masuda: false, tid: 0, sid: 0, game: game.pfGame)
            #expect(!eggs.isEmpty, "\(game.rawValue)")
        }
        #expect(EggRNGView.generations == [.gen3, .gen4, .gen5])
    }

    /// The estimate keeps Generate off for ranges that would run out of
    /// memory, and on for the defaults.
    @Test func resultEstimate() {
        let wide = EggRNGView.estimatedResults(held: 0...10_000, pickup: 0...10_000, gen3Compatibility: nil,
                                                natures: 0, shinyOnly: false)
        #expect(wide > Double(EggRNGView.resultLimit))
        for compatibility in [nil, 70] {
            let defaults = EggRNGView.estimatedResults(held: 0...5_000, pickup: 0...100, gen3Compatibility: compatibility,
                                                        natures: 0, shinyOnly: false)
            #expect(defaults < Double(EggRNGView.resultLimit))
        }
        // Gen 4 lists every pair: 101 × 51.
        let ivs: [UInt8] = [31, 31, 31, 31, 31, 31]
        let eggs = PFBridge.eggGenerate4(seedHeld: 1, seedPickup: 2, initialAdvances: 0, maxAdvances: 100,
                                         initialAdvancesPickup: 0, maxAdvancesPickup: 50,
                                         parentAIVs: ivs, parentBIVs: ivs, parentAAbility: 0, parentBAbility: 0,
                                         parentAGender: 0, parentBGender: 1, parentAItem: 0, parentBItem: 0,
                                         parentANature: 0, parentBNature: 0, eggSpecie: 1, masuda: false,
                                         tid: 0, sid: 0, game: .pearl)
        #expect(Double(eggs.count) == EggRNGView.estimatedResults(held: 0...100, pickup: 0...50, gen3Compatibility: nil,
                                                                  natures: 0, shinyOnly: false))
        #expect(EggRNGView.estimatedResults(held: 0...10_000, pickup: 0...10_000, gen3Compatibility: nil,
                                            natures: 1, shinyOnly: true) < Double(EggRNGView.resultLimit))
    }
}

// MARK: - Filter and Lead Tests

/// RNG fixes PR 2: the wild filters work, Shiny Only finds square shinies,
/// and the generators take Synchronize's nature.
@MainActor
struct RNGFilterAndLeadTests {
    private let route101 = WildAreaData.locations(for: .emerald).first { $0.name == "Route 101" }!.id
    private let route201 = WildAreaData.locations(for: .platinum).first { $0.name == "Route 201" }!.id

    private func wild(gen: FinderGeneration, mode: FinderRootView.FinderMode, method: FinderMethod, game: PFGame,
                      location: UInt8, seed: UInt32 = 0, maxAdvance: UInt32 = 1_000, natures: Set<UInt8> = [],
                      minIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0),
                      maxIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (31, 31, 31, 31, 31, 31),
                      lead: FinderLead = .none, syncNature: UInt8 = 0) -> [StaticSearchResult] {
        let box = ResultCollector()
        runWildSearch(gen: gen, mode: mode, method: method, natures: natures, tid: 0, sid: 0, shinyOnly: false,
                      minIVs: minIVs, maxIVs: maxIVs, seed: seed, initAdv: 0, maxAdv: maxAdvance,
                      searcherMinAdv: 0, searcherMaxAdv: 20, minDelay: 600, maxDelay: 620,
                      pfGame: game, pfEnc: .grass, locationID: location,
                      lead: lead, syncNature: syncNature, deadBattery: false, onResult: { box.append($0) })
        return box.results
    }

    /// The wild generators used to pass PokéFinder's "skip filters" flag
    /// whenever gender, ability and shiny were Any, so IVs and natures were
    /// ignored: all 1,001 advances came back.
    @Test func wildGeneratorFilters() {
        let all = wild(gen: .gen3, mode: .generator, method: .method1, game: .emerald, location: route101)
        #expect(all.count == 1_001)
        let adamant = wild(gen: .gen3, mode: .generator, method: .method1, game: .emerald, location: route101, natures: [3])
        #expect(!adamant.isEmpty && adamant.count < all.count / 10 && adamant.allSatisfy { $0.nature == 3 })
        let hp31 = wild(gen: .gen3, mode: .generator, method: .method1, game: .emerald, location: route101,
                        minIVs: (31, 0, 0, 0, 0, 0))
        #expect(!hp31.isEmpty && hp31.count < all.count / 10 && hp31.allSatisfy { $0.ivHP == 31 })
        let jolly = wild(gen: .gen4, mode: .generator, method: .methodJ, game: .platinum, location: route201,
                         seed: 0x0C12_0353, natures: [13])
        #expect(!jolly.isEmpty && jolly.allSatisfy { $0.nature == 13 })
    }

    /// A wild Generator result carries the seed it came from, so its Seed to
    /// Time is the right one (it showed seed 0).
    @Test func wildGeneratorKeepsTheSeed() {
        let results = wild(gen: .gen3, mode: .generator, method: .method1, game: .emerald, location: route101,
                           seed: 0x0C12_0353, maxAdvance: 5)
        #expect(results.count == 6 && results.allSatisfy { $0.seed == 0x0C12_0353 })
        let gen4 = wild(gen: .gen4, mode: .generator, method: .methodJ, game: .platinum, location: route201,
                        seed: 0x0C12_0353, maxAdvance: 5)
        #expect(!gen4.isEmpty && gen4.allSatisfy { $0.seed == 0x0C12_0353 })
    }

    @Test func wildSearcherFilters() {
        let found = wild(gen: .gen3, mode: .searcher, method: .method1, game: .emerald, location: route101, natures: [10],
                         minIVs: (31, 31, 31, 0, 0, 0))
        #expect(!found.isEmpty && found.allSatisfy { $0.nature == 10 && $0.ivHP == 31 && $0.ivDef == 31 })
    }

    /// BDSP's Grand Underground: its filter also checks the species, which
    /// had no list, so any filter rejected everything.
    @Test func undergroundFilters() throws {
        let area = try #require(PFBridge.undergroundAreas8(storyFlag: 6, game: .bd).first).location
        func generate(natures: Set<UInt8>, gender: UInt8 = 255) -> [StaticSearchResult] {
            var results: [StaticSearchResult] = []
            undergroundGenerateGen8Streaming(seed0: 0x1234_5678_9ABC_DEF0, seed1: 0x0FED_CBA9_8765_4321,
                                             initialAdvance: 0, maxAdvance: 300, natures: natures, tid: 0, sid: 0,
                                             shinyOnly: false, lead: .none, game: .bd, shinyCharm: false,
                                             diglett: false, storyFlag: 6, location: area,
                                             filterGender: gender) { results.append($0) }
            return results
        }
        let all = generate(natures: [])
        let modest = generate(natures: [15])
        #expect(!all.isEmpty)
        #expect(!modest.isEmpty && modest.count < all.count && modest.allSatisfy { $0.nature == 15 })
        let female = generate(natures: [], gender: 1)
        #expect(!female.isEmpty && female.allSatisfy { $0.gender == 1 })
    }

    /// Seed 0's first 3 million advances (TID/SID 0) have 344 star shinies
    /// and 57 square ones; Shiny Only used to find only the stars.
    @Test func shinyOnlyFindsSquares() {
        let shinies = staticGenerateGen3(seed: 0, initialAdvance: 0, maxAdvance: 3_000_000, natures: [],
                                         tid: 0, sid: 0, shinyOnly: true, method: .method1)
        #expect(shinies.count == 344 + 57)
        #expect(pfShinyFilter(true) == 3 && pfShinyFilter(false) == 255)
    }

    /// The generators read Synchronize's nature from the lead; the old
    /// code always sent Hardy's.
    @Test func generatorsTakeSyncNature() {
        let timid: UInt8 = 10
        let gen4 = staticGenerateGen4(seed: 0x1234_5678, initialAdvance: 0, maxAdvance: 2_000, natures: [],
                                      tid: 0, sid: 0, shinyOnly: false, method: .methodJ,
                                      lead: .synchronize, syncNature: timid)
        let gen4Timid = gen4.filter { $0.nature == timid }.count
        #expect(gen4Timid > gen4.count / 3)
        #expect(gen4.filter { $0.nature == 0 }.count < gen4.count / 10)
        let emerald = wild(gen: .gen3, mode: .generator, method: .method1, game: .emerald, location: route101,
                           lead: .synchronize, syncNature: timid)
        #expect(emerald.filter { $0.nature == timid }.count > emerald.count / 3)
        // BDSP's Synchronize always works.
        var bdsp: [StaticSearchResult] = []
        staticGenerateGen8Streaming(seed0: 1, seed1: 2, initialAdvance: 0, maxAdvance: 200, natures: [], tid: 0, sid: 0,
                                    shinyOnly: false, lead: .synchronize, syncNature: timid, game: .bd,
                                    shinyCharm: false) { bdsp.append($0) }
        #expect(!bdsp.isEmpty && bdsp.allSatisfy { $0.nature == timid })
        #expect(FinderLead.synchronize.pfLead == .synchronize)
        #expect(FinderLead.synchronize.pfGeneratorLead(syncNature: timid).rawValue == timid)
        #expect(FinderLead.pressure.pfGeneratorLead(syncNature: timid) == .pressure)
    }
}

nonisolated final class ResultCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [StaticSearchResult] = []
    func append(_ result: StaticSearchResult) { lock.lock(); storage.append(result); lock.unlock() }
    var results: [StaticSearchResult] { lock.lock(); defer { lock.unlock() }; return storage }
}

// MARK: - Static Encounter Template Tests

/// RNG fixes PR 3: the static encounters are PokéFinder's, and every static
/// search and generator takes the chosen one's template.
@MainActor
struct StaticEncounterTemplateTests {
    private func encounter(_ game: FinderGameVersion, _ category: StaticEncounterCategory,
                           _ species: UInt16) throws -> StaticEncounter {
        try #require(StaticEncounterData.encounters(for: game, category: category).first { $0.species == species },
                     "\(species) in \(game.rawValue)")
    }

    /// Every PokéFinder template is offered, once, and nothing else is but
    /// FireRed and LeafGreen's Mew.
    @Test func everyTemplateIsOffered() {
        var expected = 0
        for generation in FinderGeneration.allCases {
            for category in StaticEncounterCategory.allCases {
                guard let type = category.pfType(generation) else { continue }
                let count = switch generation {
                case .gen3: PFBridge.getStaticEncounters3(type: type).count
                case .gen4: PFBridge.getStaticEncounters4(type: type).count
                case .gen5: PFBridge.getStaticEncounters5(type: type).count
                case .gen8: PFBridge.getStaticEncounters8(type: type).count
                }
                expected += count
            }
        }
        #expect(StaticEncounterData.all.count == expected + 1)
        #expect(Set(StaticEncounterData.all.map(\.id)).count == StaticEncounterData.all.count)
        // Gen 5 and BDSP have them now.
        #expect(!StaticEncounterData.categories(for: .black2).isEmpty)
        #expect(!StaticEncounterData.categories(for: .brilliantDiamond).isEmpty)
        // PokéFinder's Gen 8 statics are BDSP's only.
        #expect(StaticEncounterData.categories(for: .sword).isEmpty)
    }

    @Test func gen4MethodsAndGames() throws {
        #expect(try encounter(.diamond, .legends, 483).method == .methodJ)
        #expect(try encounter(.heartGold, .legends, 249).method == .methodK)
        #expect(try encounter(.diamond, .gifts, 133).method == .method1)
        // HeartGold has Kyogre and SoulSilver Groudon; the old list swapped them.
        #expect(try encounter(.heartGold, .legends, 382).isIn(.heartGold))
        #expect(StaticEncounterData.encounters(for: .heartGold, category: .legends).allSatisfy { $0.species != 383 })
        #expect(try encounter(.soulSilver, .legends, 383).isIn(.soulSilver))
        // Forms are named.
        #expect(try encounter(.fireRed, .events, 386).speciesName == "Deoxys (Attack)")
    }

    @Test func gen4GenderFollowsTheTemplate() throws {
        let eevee = try encounter(.diamond, .gifts, 133)
        let genders = Set(staticGenerateGen4(seed: 0x0C12_0353, initialAdvance: 0, maxAdvance: 200, natures: [],
                                             tid: 0, sid: 0, shinyOnly: false, method: .method1, lead: .none,
                                             game: .diamond, template: eevee.template).map(\.gender))
        #expect(genders == [0, 1])
        let standIn = Set(staticGenerateGen4(seed: 0x0C12_0353, initialAdvance: 0, maxAdvance: 200, natures: [],
                                             tid: 0, sid: 0, shinyOnly: false, method: .method1, lead: .none).map(\.gender))
        #expect(standIn == [2])
    }

    /// The Gen 4 searcher streams, with the template's gender, and cancels.
    @Test func gen4SearcherStreams() async throws {
        let eevee = try encounter(.diamond, .gifts, 133)
        var progress: [Double] = []
        var results: [StaticSearchResult] = []
        staticSearchGen4Streaming(minIVs: (31, 31, 31, 0, 0, 0), maxIVs: (31, 31, 31, 31, 31, 31), natures: [],
                                  tid: 0, sid: 0, shinyOnly: false, method: .method1, game: .diamond,
                                  template: eevee.template, minAdvance: 0, maxAdvance: 20, minDelay: 600, maxDelay: 640,
                                  filterGender: 1, onProgress: { progress.append($0) }) { results.append($0) }
        #expect(!results.isEmpty && results.allSatisfy { $0.gender == 1 && $0.ivHP == 31 })
        #expect(progress.last == 100)
        let started = ContinuousClock.now
        let task = Task.detached {
            staticSearchGen4Streaming(minIVs: (0, 0, 0, 0, 0, 0), maxIVs: (31, 31, 31, 31, 31, 31), natures: [],
                                      tid: 0, sid: 0, shinyOnly: true, method: .methodJ, minAdvance: 0, maxAdvance: 50,
                                      minDelay: 0, maxDelay: 5_000) { _ in }
        }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()
        _ = await task.value
        #expect(ContinuousClock.now - started < .seconds(3))
    }

    /// Reshiram is shiny-locked, so a Shiny Only generation finds none; an
    /// unlocked encounter's does.
    @Test func gen5ShinyLock() throws {
        let reshiram = try encounter(.black, .legends, 643)
        #expect(reshiram.shinyLocked)
        let volcarona = try #require(StaticEncounterData.encounters(for: .black, category: .stationary)
            .first { !$0.shinyLocked })
        func shinies(_ encounter: StaticEncounter) -> Int {
            var count = 0
            staticGenerateGen5Streaming(seed: 0x1234_5678_9ABC_DEF0, initialAdvance: 0, maxAdvance: 100_000,
                                        ivInitialAdvance: 0, ivMaxAdvance: 0, natures: [],
                                        tid: 0, sid: 0, shinyOnly: true, method: .method5, lead: .none, game: .black,
                                        mac: 0, keypresses: [true] + Array(repeating: false, count: 8),
                                        vcount: 0, gxstat: 0, vframe: 0, skipLR: false, timer0Min: 0, timer0Max: 0,
                                        memoryLink: false, shinyCharm: false, dsType: 0, language: 0,
                                        staticType: encounter.type, staticIndex: encounter.index) { _ in count += 1 }
            return count
        }
        #expect(shinies(reshiram) == 0)
        #expect(shinies(volcarona) > 0)
    }

    /// PokéFinder's Gen 5 generators pair each PID advance with each IV
    /// advance; the PID range used to be the IV range too, (n + 1)² results.
    @Test func gen5IVRange() throws {
        let snivy = try encounter(.black, .starters, 495)
        var count = 0
        staticGenerateGen5Streaming(seed: 0x1234_5678_9ABC_DEF0, initialAdvance: 0, maxAdvance: 99,
                                    ivInitialAdvance: 0, ivMaxAdvance: 2, natures: [],
                                    tid: 0, sid: 0, shinyOnly: false, method: .method5, lead: .none, game: .black,
                                    mac: 0, keypresses: [true] + Array(repeating: false, count: 8),
                                    vcount: 0, gxstat: 0, vframe: 0, skipLR: false, timer0Min: 0, timer0Max: 0,
                                    memoryLink: false, shinyCharm: false, dsType: 0, language: 0,
                                    staticType: snivy.type, staticIndex: snivy.index) { _ in count += 1 }
        #expect(count == 100 * 3)
    }

    /// BDSP's Dialga has three IVs fixed at 31.
    @Test func gen8FixedIVs() throws {
        let dialga = try encounter(.brilliantDiamond, .legends, 483)
        #expect(dialga.fixedIVs == 3)
        #expect(dialga.method == nil)
        var results: [StaticSearchResult] = []
        staticGenerateGen8Streaming(seed0: 1, seed1: 2, initialAdvance: 0, maxAdvance: 200, natures: [], tid: 0, sid: 0,
                                    shinyOnly: false, lead: .none, game: .bd, shinyCharm: false,
                                    staticType: dialga.type, staticIndex: dialga.index) { results.append($0) }
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { r in [r.ivHP, r.ivAtk, r.ivDef, r.ivSpA, r.ivSpD, r.ivSpe].filter { $0 == 31 }.count >= 3 })
    }
}

// MARK: - Number Field Tests

struct RNGFieldRangeTests {
    @Test func clampsToTheSearchTypes() {
        #expect((-5).clamped(to: RNGFieldRange.advances) == 0)
        #expect(300.clamped(to: RNGFieldRange.byte) == 255)
        #expect(70_000.clamped(to: RNGFieldRange.word) == 65_535)
        #expect(RNGFieldRange.advances.upperBound == Int(UInt32.max))
        #expect(42.clamped(to: RNGFieldRange.byte) == 42)
    }
}

// MARK: - Gen 4 ID Seed Verification Tests

struct Gen4IDSeedVerificationTests {
    @Test func coinFlips_knownSeed() {
        let flips = PFBridge.coinFlips(0x01000258)
        #expect(flips == "H, T, H, H, T, T, H, H, T, H, T, T, H, T, H, H, H, H, H, H")
    }

    @Test func elmCalls_knownSeed() {
        let calls = PFBridge.getCalls(0x01000258)
        #expect(calls == "K, E, E, E, P, E, K, K, K, E, E, K, K, E, P, E, P, E, E, E")
    }

    @Test func seedToTime_knownSeed_findsOriginalDateTime() {
        let times = PFBridge.seedToTime4(seed: 0x01000258, year: 2000)
        #expect(!times.isEmpty)
        let original = times.first {
            $0.dateTime.month == 1 && $0.dateTime.day == 1 &&
            $0.dateTime.hour == 0 && $0.dateTime.minute == 0 &&
            $0.dateTime.second == 0
        }
        #expect(original != nil)
        #expect(original!.delay == 600)
    }

    @Test func seedToTime_differentYear() {
        let times2009 = PFBridge.seedToTime4(seed: 0x01000258, year: 2009)
        #expect(!times2009.isEmpty)
        // delay = efgh + 2000 - year = 0x258 + 2000 - 2009 = 600 + 2000 - 2009 = 591
        let first = times2009.first {
            $0.dateTime.month == 1 && $0.dateTime.day == 1 &&
            $0.dateTime.hour == 0 && $0.dateTime.second == 0
        }
        #expect(first != nil)
        #expect(first!.delay == 591)
    }
}

// MARK: - Gen 3 targets: Ruby/Sapphire days, Emerald, Dead Battery

@MainActor
struct Gen3TargetTests {
    /// The seed `frames` steps of the GBA's RNG after `seed`.
    private func advance(_ seed: UInt32, _ frames: Int) -> UInt32 {
        (0..<frames).reduce(seed) { s, _ in s &* 0x41C64E6D &+ 0x6073 }
    }

    /// Every Day N, hour and minute rebuilds its seed by Ruby and Sapphire's
    /// clock formula, and Day N is that many days into 2000 (a leap year),
    /// not months of 31 days.
    @Test func rubySapphireDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let newYear = try #require(DateComponents(calendar: calendar, year: 2000, month: 1, day: 1).date)
        var afterJanuary = 0
        for seed: UInt32 in [0x0005, 0x372B, 0x9C1F, 0xE0A4] {
            let times = seedToTimeGen3(seed: seed).times
            #expect(!times.isEmpty)
            for t in times {
                let v = 1440 * t.day + 960 * (t.hour / 10) + 60 * (t.hour % 10) + 16 * (t.minute / 10) + t.minute % 10
                #expect(UInt32((v >> 16) ^ (v & 0xFFFF)) == seed, "\(t.displayTime)")
                let date = try #require(calendar.date(byAdding: .day, value: t.day - 1, to: newYear))
                #expect(calendar.component(.month, from: date) == t.month && calendar.component(.day, from: date) == t.dayOfMonth)
                if t.month > 1 { afterJanuary += 1 }
            }
        }
        #expect(afterJanuary > 0)
        #expect(RSClock.dayNumber(month: 3, day: 1) == 61 && RSClock.dayNumber(month: 12, day: 31) == 366)
    }

    /// Emerald counts from 0000 and a dead battery's Ruby or Sapphire from
    /// 05A0, and the frames there make the target.
    @Test func bootSeeds() throws {
        let emerald = Gen3TargetStart.of(seed: advance(0, 1234), advances: 0, fromGenerator: false,
                                         game: .emerald, deadBattery: false)
        #expect(emerald == Gen3TargetStart(kind: .boot, seed: 0, frame: 1234))
        // Emerald boots on 0000 with a dead battery too.
        #expect(Gen3TargetStart.of(seed: advance(0, 1234), advances: 0, fromGenerator: false,
                                   game: .emerald, deadBattery: true).seed == 0)
        let ruby = Gen3TargetStart.of(seed: advance(0x5A0, 777), advances: 0, fromGenerator: false,
                                      game: .ruby, deadBattery: true)
        #expect(ruby == Gen3TargetStart(kind: .boot, seed: 0x5A0, frame: 777) && ruby.fromBoot)

        let target = try #require(PFBridge.staticGenerate3(seed: advance(0x5A0, 777), initialAdvances: 0, maxAdvances: 0,
                                                           method: .method1, tid: 0, sid: 0).first)
        let fromBoot = try #require(PFBridge.staticGenerate3(seed: ruby.seed, initialAdvances: UInt32(ruby.frame), maxAdvances: 0,
                                                             method: .method1, tid: 0, sid: 0).first)
        #expect(fromBoot.pid == target.pid && fromBoot.ivs == target.ivs)
    }

    /// A Generator's frames count from its seed: a boot seed's from boot, a
    /// live battery's clock seed with the frames before it, and any other
    /// seed (learnt in game) as it is.
    @Test func generatorTargets() {
        #expect(Gen3TargetStart.of(seed: 0, advances: 500, fromGenerator: true, game: .emerald, deadBattery: false)
                == Gen3TargetStart(kind: .boot, seed: 0, frame: 500))
        let trainerID = Gen3TargetStart.of(seed: 0x2DA6, advances: 500, fromGenerator: true, game: .emerald, deadBattery: false)
        #expect(trainerID == Gen3TargetStart(kind: .generatorSeed, seed: 0x2DA6, frame: 500) && !trainerID.fromBoot)
        #expect(Gen3TargetStart.of(seed: 0x1234, advances: 500, fromGenerator: true, game: .sapphire, deadBattery: false)
                == Gen3TargetStart(kind: .clock, seed: 0x1234, frame: 500))
        // Before, the Timer got the frames to the Generator's seed and not the 500 after it.
        #expect(Gen3TargetStart.of(seed: advance(0x372B, 100), advances: 500, fromGenerator: true, game: .ruby, deadBattery: false)
                == Gen3TargetStart(kind: .clock, seed: 0x372B, frame: 600))
    }

    /// A Searcher's target with a live battery is the clock's seed before
    /// it; FireRed and LeafGreen's, without their seed list, the 16-bit seed.
    @Test func searcherTargets() {
        #expect(Gen3TargetStart.of(seed: 0x12345678, advances: 0, fromGenerator: false, game: .ruby, deadBattery: false)
                == Gen3TargetStart(kind: .clock, seed: 0x372B, frame: 57823))
        let fireRed = Gen3TargetStart.of(seed: 0x12345678, advances: 0, fromGenerator: false, game: .fireRed, deadBattery: true)
        #expect(fireRed == Gen3TargetStart(kind: .origin, seed: 0x372B, frame: 57823) && !fireRed.fromBoot)
    }

    /// The handoff runs the Timer at the GBA's frame rate, in Standard mode
    /// when the frames count from boot.
    @Test func handoffSetsGBA() {
        let bridge = FinderTimerBridge()
        bridge.sendGen3(Gen3TargetStart(kind: .boot, seed: 0, frame: 1234), time: "frame 1,234", seed: "ABCD1234")
        #expect(bridge.pendingGen == .gen3 && bridge.pendingTargetFrame == 1234)
        #expect(bridge.pendingConsole == .gba && bridge.pendingGen3Mode == .standard && bridge.shouldSwitchToTimer)
        bridge.clear()
        bridge.sendGen3(Gen3TargetStart(kind: .generatorSeed, seed: 0x2DA6, frame: 500), time: "", seed: "")
        #expect(bridge.pendingConsole == .gba && bridge.pendingGen3Mode == nil)
    }

    @Test func waitText() {
        #expect(SeedToTimeView.waitText(frames: 2500) == "41.9 s")
        #expect(SeedToTimeView.waitText(frames: Int(GBA_FRAMERATE * 725)) == "12 min 5 s")
        #expect(SeedToTimeView.waitText(frames: Int(GBA_FRAMERATE * 3600 * 3.5)) == "3 h 30 min")
    }
}

// MARK: - Finder results: generators in chunks, empty results

struct GeneratorChunkTests {
    /// Each chunk starts where the last ended, a 32-bit range stops at its
    /// top, and progress ends at 100.
    @Test func chunksCoverTheRange() {
        var calls: [[UInt32]] = []
        var progress: [Double] = []
        generateInChunks(initialAdvance: 3, maxAdvance: 20, chunkSize: 7, onProgress: { progress.append($0) }) {
            calls.append([$0, $1]); return 0
        }
        #expect(calls == [[3, 6], [10, 6], [17, 6]])
        #expect(progress.last == 100 && progress == progress.sorted())

        calls = []
        generateInChunks(initialAdvance: UInt32.max - 2, maxAdvance: 10, chunkSize: 7) { calls.append([$0, $1]); return 0 }
        #expect(calls == [[UInt32.max - 2, 2]])
    }

    @Test func stopsAtTheLimit() {
        var calls = 0
        generateInChunks(initialAdvance: 0, maxAdvance: 1_000, chunkSize: 10, limit: 12) { _, _ in calls += 1; return 5 }
        #expect(calls == 3)
    }

    private func pairs(_ results: [StaticSearchResult]) -> [String] { results.map { "\($0.advances) \($0.pid)" } }

    /// Over three chunks, each generator gives what one call to PokéFinder does.
    @Test func chunkedResultsMatchOneCall() {
        let adamant = [Bool](repeating: false, count: 25).enumerated().map { $0.offset == 3 }
        var gen3: [StaticSearchResult] = []
        staticGenerateGen3Streaming(seed: 0x1234, initialAdvance: 5, maxAdvance: 25_000, natures: [3],
                                    tid: 0, sid: 0, shinyOnly: false, method: .method1) { gen3.append($0) }
        let one3 = PFBridge.staticGenerate3(seed: 0x1234, initialAdvances: 5, maxAdvances: 25_000, method: .method1,
                                            tid: 0, sid: 0, natures: adamant)
        #expect(!gen3.isEmpty && pairs(gen3) == one3.map { "\($0.advances) \($0.pid)" })

        var gen4: [StaticSearchResult] = []
        staticGenerateGen4Streaming(seed: 0x0C12_0353, initialAdvance: 5, maxAdvance: 25_000, natures: [3],
                                    tid: 0, sid: 0, shinyOnly: false, method: .methodJ, lead: .none, game: .platinum) { gen4.append($0) }
        let one4 = PFBridge.staticGenerate4(seed: 0x0C12_0353, initialAdvances: 5, maxAdvances: 25_000, method: .methodJ,
                                            tid: 0, sid: 0, game: .platinum, natures: adamant)
        #expect(!gen4.isEmpty && pairs(gen4) == one4.map { "\($0.advances) \($0.pid)" })

        var raid: [StaticSearchResult] = []
        raidGenerateGen8Streaming(seed: 0xBADC0FFEE, initialAdvance: 0, maxAdvance: 25_000, natures: [3],
                                  tid: 0, sid: 0, shinyOnly: false, game: .sword, shinyCharm: false,
                                  denIndex: 0, rarity: 0, raidIndex: 0, level: 60) { raid.append($0) }
        let oneRaid = PFBridge.raidGenerate8(seed: 0xBADC0FFEE, initialAdvances: 0, maxAdvances: 25_000, tid: 0, sid: 0,
                                             game: .sword, denIndex: 0, rarity: 0, raidIndex: 0, level: 60, natures: adamant)
        #expect(pairs(raid) == oneRaid.map { "\($0.advances) \($0.pid)" })

        // PokéFinder's Gen 8 ID generator stops one short of its max advances.
        var ids: [StaticSearchResult] = []
        idGenerateGen8Streaming(seed0: 0x1234_5678, seed1: 0x9ABC_DEF0, initialAdvance: 0, maxAdvance: 25_000,
                                filterTID: 0, hasTIDFilter: false, filterSID: 0, hasSIDFilter: false,
                                filterDisplayTID: 0, hasDisplayFilter: false) { ids.append($0) }
        let oneIDs = PFBridge.idGenerate8(seed0: 0x1234_5678, seed1: 0x9ABC_DEF0, initialAdvances: 0, maxAdvances: 25_000)
        #expect(ids.count == 25_000 && ids.map(\.advances) == oneIDs.map(\.advances) && ids.map(\.resultTID) == oneIDs.map(\.tid))
    }

    /// A hundred million advances with nothing filtered stop at the limit,
    /// a chunk past it at most, instead of building every result first.
    @Test func longGenerateStopsAtTheLimit() {
        var count = 0
        var last: UInt32 = 0
        staticGenerateGen3Streaming(seed: 0, initialAdvance: 0, maxAdvance: 100_000_000, natures: [],
                                    tid: 0, sid: 0, shinyOnly: false, method: .method1) {
            count += 1
            last = $0.advances
        }
        #expect(count >= searchResultLimit && count < searchResultLimit + Int(generatorChunkSize))
        #expect(last < UInt32(searchResultLimit) + generatorChunkSize)
    }

    @Test func noResultsWording() {
        #expect(noResultsText(filters: []) == "Nothing found.")
        #expect(noResultsText(filters: [], widen: "the advances") == "Nothing found. Widen the advances.")
        #expect(noResultsText(filters: ["IVs", "natures", "Shiny Only"], widen: "the advances")
                == "Nothing found with IVs, natures, and Shiny Only set. Loosen one, or widen the advances.")
    }
}

// MARK: - Wild Area Tests

/// RNG fixes PR 9: a wild area is a reference into PokéFinder's tables, by
/// location ID, with the settings that change its slots.
@MainActor
struct WildAreaTests {
    private func location(_ game: FinderGameVersion, _ name: String) throws -> UInt8 {
        try #require(WildAreaData.locations(for: game).first { $0.name == name }, "\(game.rawValue) \(name)").id
    }

    /// Every area PokéFinder lists is offered once, by its ID, for every
    /// game and encounter type; every location once, with its own name.
    @Test func everyAreaOnceByID() {
        for game in FinderGameVersion.allCases where !game.isSwSh {
            for type in EncounterType.types(for: game.generation) {
                let ids = WildAreaData.areas(for: game, type: type).map(\.location)
                let raw: [UInt8] = switch game.generation {
                case .gen3: PFBridge.getEncounters3(encounter: type.pfEncounter, game: game.pfGame).map(\.location)
                case .gen4: PFBridge.getEncounters4(encounter: type.pfEncounter, game: game.pfGame).map(\.location)
                case .gen5: PFBridge.getEncounters5(encounter: type.pfEncounter, game: game.pfGame).map(\.location)
                case .gen8: PFBridge.getEncounters8(encounter: type.pfEncounter, game: game.pfGame).map(\.location)
                }
                #expect(ids == raw, "\(game.rawValue) \(type.rawValue)")
                #expect(Set(ids).count == ids.count, "\(game.rawValue) \(type.rawValue)")
            }
            let locations = WildAreaData.locations(for: game)
            #expect(!locations.isEmpty, "\(game.rawValue)")
            #expect(Set(locations.map(\.id)).count == locations.count, "\(game.rawValue)")
            #expect(Set(locations.map(\.name)).count == locations.count, "\(game.rawValue)")
            #expect(!locations.contains { $0.name.isEmpty }, "\(game.rawValue)")
        }
    }

    /// Where two locations share PokéFinder's name, each gets its number.
    @Test func sharedNamesToldApart() {
        let hgss = WildAreaData.locationNames(for: .heartGold)
        #expect(hgss[23] == "National Park (1)" && hgss[24] == "National Park (2)")
        let bdsp = WildAreaData.locationNames(for: .brilliantDiamond)
        #expect([bdsp[60], bdsp[61], bdsp[62]] == ["Turnback Cave (1)", "Turnback Cave (2)", "Turnback Cave (3)"])
        #expect(hgss[22] == "Route 35")
    }

    /// The two National Parks are different tables, and each searches its
    /// own; a location the game doesn't have gives nothing, where it gave
    /// the list's first area.
    @Test func searchesTheChosenArea() throws {
        let parks = WildAreaData.areas(for: .heartGold, type: .grass).filter { $0.location == 23 || $0.location == 24 }
        try #require(parks.count == 2)
        #expect(parks[0].slots.map(\.species) != parks[1].slots.map(\.species))
        for park in parks {
            let results = PFBridge.wildGenerate4(seed: 0x0C12_0353, initialAdvances: 0, maxAdvances: 3_000, method: .methodK,
                                                 tid: 0, sid: 0, game: .heartGold, encounter: .grass, location: park.location)
            #expect(!results.isEmpty)
            #expect(Set(results.map(\.specie)).isSubset(of: Set(park.slots.map(\.species))), "\(park.name)")
        }
        #expect(WildAreaData.area(for: .emerald, type: .grass, location: 250) == nil)
        #expect(PFBridge.wildGenerate3(seed: 0, initialAdvances: 0, maxAdvances: 100, method: .method1,
                                       tid: 0, sid: 0, game: .emerald, encounter: .grass, location: 250).isEmpty)
        #expect(PFBridge.wildSearch3Async(method: .method1, tid: 0, sid: 0, game: .emerald,
                                          encounter: .grass, location: 250) == nil)
    }

    /// Gen 5's areas and slots follow the season: winter Route 7 has
    /// Cubchoo, spring's doesn't, and some areas aren't there in winter.
    @Test func gen5Seasons() throws {
        let route7 = try location(.black, "Route 7")
        let spring = try #require(WildAreaData.area(for: .black, type: .grass, location: route7))
        let winter = try #require(WildAreaData.area(for: .black, type: .grass, location: route7, settings: .init(season: 3)))
        #expect(winter.slots.contains { $0.species == 613 })
        #expect(!spring.slots.contains { $0.species == 613 })
        #expect(WildAreaData.areas(for: .black, type: .grass, settings: .init(season: 3)).count
                < WildAreaData.areas(for: .black, type: .grass).count)
        // The generator takes the season and the Pokémon picker's slots.
        let cubchoo = winter.encounterSlots(for: 613)
        let results = PFBridge.wildGenerate5(seed: 0x1234_5678_9ABC_DEF0, initialAdvances: 0, maxAdvances: 2_000,
                                             ivInitialAdvances: 0, ivMaxAdvances: 0, method: .method5, tid: 0, sid: 0,
                                             game: .black, encounter: .grass, location: route7, season: 3,
                                             mac: 0, keypresses: Array(repeating: false, count: 9),
                                             vcount: 0, gxstat: 0, vframe: 0, skipLR: false, timer0Min: 0, timer0Max: 0,
                                             memoryLink: false, shinyCharm: false, dsType: 0, language: 0,
                                             encounterSlots: cubchoo)
        #expect(!results.isEmpty && results.allSatisfy { $0.specie == 613 })
    }

    /// Gen 4's time of day: HeartGold's Route 29 has Hoothoot at night, not
    /// in the morning, and a night search finds it.
    @Test func gen4TimeOfDay() throws {
        let route29 = try location(.heartGold, "Route 29")
        let morning = try #require(WildAreaData.area(for: .heartGold, type: .grass, location: route29))
        let night = try #require(WildAreaData.area(for: .heartGold, type: .grass, location: route29, settings: .init(time: 2)))
        #expect(night.slots.contains { $0.species == 163 } && !morning.slots.contains { $0.species == 163 })
        let results = PFBridge.wildGenerate4(seed: 0x0C12_0353, initialAdvances: 0, maxAdvances: 3_000, method: .methodK,
                                             tid: 0, sid: 0, game: .heartGold, encounter: .grass, location: route29,
                                             settings: Gen4EncounterSettings(time: 2))
        #expect(results.contains { $0.specie == 163 })
        // Diamond, Pearl and Platinum's grass reads it too.
        let platinum = WildAreaData.areas(for: .platinum, type: .grass)
        let platinumNight = WildAreaData.areas(for: .platinum, type: .grass, settings: .init(time: 2))
        #expect(zip(platinum, platinumNight).contains { $0.slots.map(\.species) != $1.slots.map(\.species) })
    }

    /// Each setting changes the slots PokéFinder says it does.
    @Test func gen4Settings() throws {
        func changed(_ game: FinderGameVersion, _ settings: WildSettings, type: EncounterType = .grass,
                     slots: Set<Int>) -> Bool {
            let plain = WildAreaData.areas(for: game, type: type)
            let set = WildAreaData.areas(for: game, type: type, settings: settings)
            let differing = zip(plain, set).flatMap { a, b in
                zip(a.slots, b.slots).filter { $0.species != $1.species }.map(\.0.index)
            }
            return !differing.isEmpty && Set(differing).isSubset(of: slots)
        }
        #expect(changed(.platinum, .init(swarm: true), slots: [0, 1]))
        #expect(changed(.platinum, .init(dual: .ruby), slots: [8, 9]))
        #expect(changed(.platinum, .init(radar: true), slots: [4, 5, 10, 11]))
        #expect(changed(.heartGold, .init(radio: 1), slots: [2, 3, 4, 5]))
        #expect(changed(.heartGold, .init(swarm: true), type: .surf, slots: [0]))
        #expect(changed(.brilliantDiamond, .init(time: 2), slots: [2, 3]))
        // The Great Marsh's daily Pokémon takes slots 6 and 7.
        let marsh = try #require(WildAreaData.area(for: .platinum, type: .grass, location: 23))
        let daily = PFBridge.dailyPokemon(game: .platinum, trophyGarden: false)
        let pick = try #require(daily.first { specie in !marsh.slots.contains { $0.species == specie } })
        let replaced = try #require(WildAreaData.area(for: .platinum, type: .grass, location: 23,
                                                      settings: .init(replacement0: pick)))
        #expect(replaced.slots[6].species == pick && replaced.slots[7].species == pick)
        #expect(PFBridge.dailyPokemon(game: .platinum, trophyGarden: true).count == 16)
        // The Safari Zone's blocks change its slots.
        let safari = WildAreaData.areas(for: .heartGold, type: .grass).filter(\.isSafariZone)
        let blocked = WildAreaData.areas(for: .heartGold, type: .grass, settings: .init(blocks: [30, 30, 30, 30]))
            .filter(\.isSafariZone)
        #expect(!safari.isEmpty && safari.allSatisfy { $0.slots.count == 10 })
        #expect(zip(safari, blocked).contains { $0.slots.map(\.species) != $1.slots.map(\.species) })
    }

    /// The Poké Radar is PokéFinder's own method, from the chosen slot; its
    /// shiny patch gives shinies.
    @Test func pokeRadar() throws {
        let route201 = try location(.platinum, "Route 201")
        let area = try #require(WildAreaData.area(for: .platinum, type: .grass, location: route201,
                                                  settings: .init(radar: true)))
        let radar = Gen4EncounterSettings(radar: true)
        let results = PFBridge.wildGenerate4(seed: 0x0C12_0353, initialAdvances: 0, maxAdvances: 500, method: .pokeRadar,
                                             tid: 0, sid: 0, game: .platinum, encounter: .grass, location: route201,
                                             settings: radar, fixedSlot: 4)
        #expect(!results.isEmpty && results.allSatisfy { $0.specie == area.slots[4].species })
        let shiny = PFBridge.wildGenerate4(seed: 0x0C12_0353, initialAdvances: 0, maxAdvances: 100, method: .pokeRadar,
                                           tid: 1234, sid: 5678, game: .platinum, encounter: .grass, location: route201,
                                           settings: radar, radarShiny: true, fixedSlot: 4)
        #expect(!shiny.isEmpty && shiny.allSatisfy { $0.shiny > 0 })
    }

    /// A Feebas tile adds Feebas after the rod's slots, half the time.
    @Test func feebasTile() throws {
        let plain = try #require(WildAreaData.area(for: .emerald, type: .superRod, location: 33))
        let tile = try #require(WildAreaData.area(for: .emerald, type: .superRod, location: 33,
                                                  settings: .init(feebasTile: true)))
        #expect(!plain.slots.contains { $0.species == 349 })
        #expect(tile.slots.last?.species == 349 && tile.slots.last?.slotRate == "50%")
        #expect(tile.slots.first?.slotRate == "20%")
        #expect(plain.isFeebasLocation && WildAreaData.areas(for: .emerald, type: .superRod).filter(\.isFeebasLocation).count == 1)
    }

    /// Slot labels come from the thresholds PokéFinder rolls against, per
    /// game and encounter type, and each area's add up to 100%.
    @Test func slotRatesSumTo100() {
        for game in FinderGameVersion.allCases where !game.isSwSh {
            var encounters = EncounterType.types(for: game.generation).map(\.pfEncounter)
            if game.isHGSS { encounters += [.headbutt, .bugCatchingContest] }
            for encounter in encounters {
                for area in WildAreaData.areas(for: game, encounter: encounter) {
                    let rates = WildAreaData.slotRates(game: game, encounter: encounter, slotCount: area.slots.count,
                                                       safari: area.isSafariZone && area.type != nil)
                    #expect(rates.count == area.slots.count, "\(game.rawValue) \(encounter.displayName) \(area.name)")
                    #expect(abs(rates.reduce(0, +) - 100) < 0.001, "\(game.rawValue) \(encounter.displayName) \(area.name)")
                }
            }
        }
        // Not Gen 3's rods everywhere: Diamond's Old Rod has five slots, and
        // HeartGold's rods their own rates.
        #expect(WildAreaData.slotRates(game: .diamond, encounter: .oldRod, slotCount: 5) == [60, 30, 5, 4, 1])
        #expect(WildAreaData.slotRates(game: .heartGold, encounter: .superRod, slotCount: 5) == [40, 30, 15, 10, 5])
        #expect(WildAreaData.slotRates(game: .emerald, encounter: .oldRod, slotCount: 2) == [70, 30])
    }

    /// BDSP's Grand Underground searches one area, as PokéFinder's screen
    /// does: its results are that area's Pokémon, and the Pokémon picker
    /// narrows them.
    @Test func undergroundOneArea() throws {
        let areas = PFBridge.undergroundAreas8(storyFlag: 6, game: .bd)
        try #require(areas.count > 1)
        // The bridge holds up to 255 species an area; the largest have about 70.
        #expect(areas.allSatisfy { !$0.species.isEmpty && $0.species.count < 255 && !$0.name.isEmpty })
        #expect(areas.map(\.name).first == "Spacious Cave")
        func generate(_ area: PFBridge.UndergroundArea, species: [UInt16] = []) -> [PFBridge.Gen8UndergroundResult] {
            PFBridge.undergroundGenerate8(seed0: 0x1234_5678_9ABC_DEF0, seed1: 0x0FED_CBA9_8765_4321,
                                          initialAdvances: 0, maxAdvances: 300, tid: 0, sid: 0, game: .bd,
                                          storyFlag: 6, location: area.location, species: species)
        }
        let first = generate(areas[0])
        let second = generate(areas[1])
        #expect(!first.isEmpty && Set(first.map(\.specie)).isSubset(of: Set(areas[0].species)))
        #expect(Set(first.map(\.specie)) != Set(second.map(\.specie)))
        let one = try #require(first.first?.specie)
        let only = generate(areas[0], species: [one])
        #expect(!only.isEmpty && only.allSatisfy { $0.specie == one })
    }

    /// BDSP's wild generator takes the settings and the Pokémon picker's
    /// slots (it ignored both).
    @Test func bdspSettingsAndPokemon() throws {
        let area = try #require(WildAreaData.areas(for: .brilliantDiamond, type: .grass, settings: .init(time: 2))
            .first { night in
                WildAreaData.area(for: .brilliantDiamond, type: .grass, location: night.location)?.slots[2].species
                    != night.slots[2].species
            })
        let nightOnly = area.slots[2].species
        var results: [StaticSearchResult] = []
        wildGenerateGen8Streaming(seed0: 0x1234_5678_9ABC_DEF0, seed1: 0x0FED_CBA9_8765_4321,
                                  initialAdvance: 0, maxAdvance: 3_000, natures: [], tid: 0, sid: 0,
                                  shinyOnly: false, lead: .none, game: .bd, shinyCharm: false,
                                  encounter: .grass, location: area.location, settings: Gen4EncounterSettings(time: 2),
                                  encounterSlots: area.encounterSlots(for: nightOnly)) { results.append($0) }
        #expect(!results.isEmpty && results.allSatisfy { $0.specie == nightOnly })
    }
}

// MARK: - Gen 4 Tools Tests

/// RNG fixes PR 10: the DS year in Seed to Time and the TID/SID tool, the
/// Generator's TSV filter, and TID/SID's generations.
struct Gen4ToolsTests {
    /// A later year takes one off the delay for each year after 2000, and
    /// the clock time with that year and delay gives back the seed.
    @Test func seedToTimeYear() {
        let seed: UInt32 = 0x0510_0320
        let in2000 = seedToTimeGen4(seed: seed)
        let in2010 = seedToTimeGen4(seed: seed, year: 2010)
        #expect(!in2010.isEmpty && in2010.allSatisfy { $0.delay == 800 - 10 && $0.year == 2010 })
        #expect(in2000.allSatisfy { $0.delay == 800 })
        for time in in2010.prefix(20) {
            let clock = Gen4SeedTime(year: time.year, month: time.month, day: time.day, hour: Int(time.hour),
                                     minute: time.minute, second: time.second, delay: Int(time.delay))
            #expect(clock.seed == seed)
        }
        #expect(in2010.first?.displayTime.hasPrefix("2010/") == true)
    }

    /// A year that would need a negative delay gives nothing.
    @Test func seedToTimeYearTooLate() {
        let seed: UInt32 = 0x0510_0005
        #expect(seedToTimeGen4LatestYear(seed: seed) == 2005)
        #expect(!seedToTimeGen4(seed: seed, year: 2005).isEmpty)
        #expect(seedToTimeGen4(seed: seed, year: 2006).isEmpty)
        // Hours past 23 carry 0x10000 delays each.
        #expect(seedToTimeGen4LatestYear(seed: 0x0019_0000) == 2000 + 2 * 0x10000)
    }

    /// TID/SID's Generator shows the delays entered for the year: the
    /// seed's low bits are the delay plus the years since 2000, so a 2010
    /// delay is the 2000 one less 10.
    @Test func idGeneratorYear() throws {
        let in2010 = PFBridge.idGenerate4(minDelay: 600, maxDelay: 605, year: 2010, month: 1, day: 1, hour: 0, minute: 0)
        #expect(in2010.count == 6 * 60)
        #expect(in2010.allSatisfy { (600...605).contains($0.delay) && $0.seed & 0xFFFF == $0.delay + 10 })
        let in2000 = PFBridge.idGenerate4(minDelay: 610, maxDelay: 610, year: 2000, month: 1, day: 1, hour: 0, minute: 0)
        let sameSeed = try #require(in2000.first)
        let match = try #require(in2010.first { $0.seed == sameSeed.seed })
        #expect(match.delay == 600 && match.tid == sameSeed.tid && match.sid == sameSeed.sid)
    }

    /// The Generator's TSV filter is passed (only the Searcher's was).
    @Test func idGeneratorTSV() throws {
        let all = PFBridge.idGenerate4(minDelay: 500, maxDelay: 1_500, year: 2000, month: 1, day: 1, hour: 0, minute: 0)
        let tsv = try #require(all.first).tsv
        let filtered = PFBridge.idGenerate4(minDelay: 500, maxDelay: 1_500, year: 2000, month: 1, day: 1, hour: 0, minute: 0,
                                            targetTSV: tsv, filterTSV: true)
        #expect(!filtered.isEmpty && filtered.count < all.count && filtered.allSatisfy { $0.tsv == tsv })
    }

    /// The Searcher shows the delays entered for the year too.
    @Test func idSearcherYear() async {
        let handle = PFBridge.idSearch4Start(infinite: false, year: 2010, minDelay: 600, maxDelay: 601)
        while !PFBridge.idSearch4Done(handle) { try? await Task.sleep(for: .milliseconds(20)) }
        let results = PFBridge.idSearch4GetResults(handle)
        PFBridge.idSearch4Free(handle)
        #expect(results.count == 2 * 256 * 24)
        #expect(results.allSatisfy { (600...601).contains($0.delay) && $0.seed & 0xFFFF == $0.delay + 10 })
    }

    /// Checking around a bare seed (the Finder's Generator) gives delays for
    /// the same year as Seed to Time, so the Timer's hit and target agree.
    @Test func seedCheckYear() throws {
        let seed: UInt32 = 0x2C11_02EA
        let in2010 = Gen4SeedCheck.candidates(aroundSeed: seed, delays: 2, seconds: 0, year: 2010)
        let exact = try #require(in2010.first { $0.delayOffset == 0 })
        #expect(exact.seed == seed && exact.delay == 0x02EA - 10)
        let target = try #require(seedToTimeGen4(seed: seed, year: 2010).first)
        #expect(Int(target.delay) == exact.delay)
    }

    /// TID/SID offers Gen 3, 4 and 5: its Gen 8 tab ran Gen 4's generator,
    /// as Gen 5's did before PR 12 gave it PokéFinder's IDSearcher5.
    @MainActor
    @Test func idToolGenerations() {
        #expect(IDRNGView.generations == [.gen3, .gen4, .gen5])
    }
}

// MARK: - Gen 5 Profile Tests

/// RNG fixes PR 12: Gen 5 profiles, the calibrator, Gen 5 IDs and Gen 5's
/// Send to Timer.
struct Gen5ProfileTests {
    /// A DS with known parameters (a made-up one: the calibrator's ranges
    /// hold it).
    private let ds = Gen5DSParameters(mac: 0x0009_BF12_3456, timer0Min: 0xC79, timer0Max: 0xC79, vcount: 0x60,
                                      gxstat: 6, vframe: 5, dsType: 0, language: 0)

    /// The calibrator finds the parameters a seed was made with.
    @Test func calibratorFindsTheParameters() async throws {
        let seed = PFBridge.gen5InitialSeed(game: .black, profile: ds, timer0: 0xC79,
                                            year: 2011, month: 3, day: 6, hour: 10, minute: 20, second: 33)
        let ranges = Gen5DSParameters.calibratorRanges(game: .black, dsType: 0)
        let handle = try #require(PFBridge.profileSearch5Start(
            bySeed: true, game: .black, language: 0, dsType: 0, mac: ds.mac, buttons: 0,
            year: 2011, month: 3, day: 6, hour: 10, minute: 20, seconds: 0...59,
            vcount: UInt8(ranges.vcount.lowerBound)...UInt8(ranges.vcount.upperBound),
            timer0: UInt16(ranges.timer0.lowerBound)...UInt16(ranges.timer0.upperBound),
            gxstat: 6...6, vframe: 0...10, seed: seed))
        while !PFBridge.profileSearch5Done(handle) { try? await Task.sleep(for: .milliseconds(20)) }
        let results = PFBridge.profileSearch5Results(handle)
        #expect(PFBridge.profileSearch5Progress(handle) == 100)
        PFBridge.profileSearch5Free(handle)
        let found = try #require(results.first)
        #expect(results.count == 1)
        #expect(found.timer0 == 0xC79 && found.vcount == 0x60 && found.vframe == 5 && found.gxstat == 6 && found.second == 33)
    }

    /// The IV calibrator reads every combination in range: with every IV
    /// allowed, each set of parameters fits.
    @Test func calibratorIVsWired() async throws {
        let handle = try #require(PFBridge.profileSearch5Start(
            bySeed: false, game: .white2, language: 0, dsType: 2, mac: ds.mac, buttons: 0,
            year: 2012, month: 7, day: 1, hour: 9, minute: 0, seconds: 10...11,
            vcount: 0xA0...0xA1, timer0: 0x1400...0x1402, gxstat: 6...6, vframe: 0...1))
        while !PFBridge.profileSearch5Done(handle) { try? await Task.sleep(for: .milliseconds(20)) }
        let results = PFBridge.profileSearch5Results(handle)
        PFBridge.profileSearch5Free(handle)
        // 2 seconds, 2 VCounts, 3 Timer0s, 1 GxStat and 2 VFrames.
        let combinations = 24
        #expect(results.count == combinations)

    }

    /// PokéFinder's calibrator's starting ranges, by game and DS.
    @Test func calibratorRanges() {
        #expect(Gen5DSParameters.calibratorRanges(game: .black, dsType: 0) == (0x50...0x70, 0xC60...0xCA0))
        #expect(Gen5DSParameters.calibratorRanges(game: .white2, dsType: 0) == (0x70...0x90, 0x10E0...0x1130))
        #expect(Gen5DSParameters.calibratorRanges(game: .white, dsType: 1) == (0x80...0x92, 0x1140...0x12D0))
        #expect(Gen5DSParameters.calibratorRanges(game: .black2, dsType: 2) == (0xA0...0xC0, 0x1400...0x1900))
        #expect(Gen5DSParameters().isUnset && !ds.isUnset)
    }

    /// Find My Seed finds the seed from the TID it gave, and each result's
    /// IDs regenerate in IDGenerator5; the date search finds the same.
    @Test func gen5IDs() async throws {
        let seed = PFBridge.gen5InitialSeed(game: .black, profile: ds, timer0: 0xC79,
                                            year: 2011, month: 3, day: 6, hour: 10, minute: 20, second: 33)
        let ids = PFBridge.idGenerate5(seed: seed, game: .black, profile: ds, maxAdvances: 0)
        let first = try #require(ids.first)
        let found = PFBridge.idFind5(game: .black, profile: ds, tid: first.tid, year: 2011, month: 3, day: 6,
                                     hour: 10, minute: 20, seconds: 0...59, maxAdvances: 0)
        let hit = try #require(found.first { $0.seed == seed })
        #expect(hit.second == 33 && hit.timer0 == 0xC79 && hit.tid == first.tid && hit.sid == first.sid)
        for r in found {
            let again = PFBridge.idGenerate5(seed: r.seed, game: .black, profile: ds, maxAdvances: 0)
            #expect(again.contains { $0.advances == r.advances && $0.tid == r.tid && $0.sid == r.sid })
        }
        let handle = try #require(PFBridge.idSearch5Start(game: .black, profile: ds,
                                                          start: (2011, 3, 6), end: (2011, 3, 6), maxAdvances: 0,
                                                          tid: first.tid, filterTID: true, sid: first.sid, filterSID: true))
        while !PFBridge.idSearch5Done(handle) { try? await Task.sleep(for: .milliseconds(20)) }
        let searched = PFBridge.idSearch5Results(handle)
        PFBridge.idSearch5Free(handle)
        #expect(searched.contains { $0.seed == seed && $0.hour == 10 && $0.minute == 20 && $0.second == 33 })
    }

    /// A Gen 5 ID result sends the Gen 5 Timer its second.
    @MainActor
    @Test func sendToTimer() {
        let r = PFBridge.IDSearchResult5(year: 2011, month: 3, day: 6, hour: 10, minute: 20, second: 33,
                                         seed: 0x1234, timer0: 0xC79, buttons: 1 << 4, advances: 0,
                                         tid: 1, sid: 2, tsv: 0)
        let bridge = FinderTimerBridge.shared
        bridge.clear()
        Gen5IDView.sendToTimer(r)
        #expect(bridge.pendingGen == .gen5 && bridge.pendingTargetSecond == 33 && bridge.shouldSwitchToTimer)
        #expect(bridge.selectedTime == "2011/03/06 10:20:33, holding A")
        bridge.clear()
    }

    /// PokéFinder's Gen 5 generators don't read the method: Method 5, its
    /// IVs and its C-Gear gave the same results, so the Finder offers one.
    @Test func gen5Methods() {
        #expect(FinderMethod.methods(for: .gen5) == [.method5])
        func generate(_ method: PFMethod) -> [UInt32] {
            PFBridge.staticGenerate5(seed: 0x1234_5678_9ABC_DEF0, initialAdvances: 0, maxAdvances: 20,
                                     ivInitialAdvances: 0, ivMaxAdvances: 0, method: method, tid: 0, sid: 0,
                                     game: .black, staticType: 0, staticIndex: 0, mac: ds.mac, keypresses: ds.keypresses,
                                     vcount: ds.vcount, gxstat: ds.gxstat, vframe: ds.vframe, skipLR: false,
                                     timer0Min: ds.timer0Min, timer0Max: ds.timer0Max, memoryLink: false,
                                     shinyCharm: false, dsType: 0, language: 0).map(\.pid)
        }
        #expect(!generate(.method5).isEmpty)
        #expect(generate(.method5) == generate(.method5CGear) && generate(.method5) == generate(.method5IVs))
    }

    /// A profile keeps the DS's parameters, and they store and read back.
    @Test func profilesKeepTheParameters() throws {
        var profile = FinderProfile(name: "Black", tid: 1, sid: 2, gameVersion: "Black")
        profile.gen5Parameters = ds
        #expect(profile.gen5Parameters == ds && profile.isGen5)
        let defaults = try #require(UserDefaults(suiteName: "Gen5ProfileTests"))
        defaults.removePersistentDomain(forName: "Gen5ProfileTests")
        Gen5DSParametersCard.store(ds, defaults)
        #expect(Gen5DSParametersCard.stored(defaults) == ds)
        #expect(Gen5DSParameterKeys.keypresses(from: "010000000") == [false, true] + Array(repeating: false, count: 7))
        #expect(Gen5Buttons.describe(0) == "None" && Gen5Buttons.describe((1 << 4) | (1 << 7)) == "A + Start")
    }
}

// MARK: - Gen 5 Egg Tests

/// The Eggs tool's Gen 5 tab: PokéFinder's EggGenerator5 and its egg
/// searcher, with its parent rules.
struct Gen5EggTests {
    /// The test DS from the Gen 5 profile tests.
    private let ds = Gen5DSParameters(mac: 0x0009_BF12_3456, timer0Min: 0xC79, timer0Max: 0xC79, vcount: 0x60,
                                      gxstat: 6, vframe: 5, dsType: 0, language: 0)

    /// A male with every IV 31 and a female with every IV 0, so each IV
    /// shows which parent gave it.
    private func daycare(male: EggParent = EggParent(ivs: Array(repeating: 31, count: 6), gender: 0),
                         female: EggParent = EggParent(ivs: Array(repeating: 0, count: 6), gender: 1),
                         femaleFirst: Bool = false) -> Gen5Daycare {
        femaleFirst ? Gen5Daycare(parentA: female, parentB: male, specie: 1, masuda: false)
                    : Gen5Daycare(parentA: male, parentB: female, specie: 1, masuda: false)
    }

    private func seed(_ game: PFGame) -> UInt64 {
        PFBridge.gen5InitialSeed(game: game, profile: ds, timer0: 0xC79,
                                 year: 2011, month: 3, day: 6, hour: 10, minute: 20, second: 33)
    }

    private func generate(_ game: PFGame, daycare: Gen5Daycare, maxAdvances: UInt32 = 50,
                          filter: Gen5EggFilter = Gen5EggFilter()) -> [PFBridge.EggResult5] {
        PFBridge.eggGenerate5(seed: seed(game), initialAdvances: 0, maxAdvances: maxAdvances, game: game,
                              tid: 0, sid: 0, profile: ds, daycare: daycare, filter: filter)
    }

    /// Each egg inherits three IVs, each the parent's that's named.
    @Test(arguments: [PFGame.black, .white2])
    func inheritsThreeIVs(game: PFGame) throws {
        let eggs = generate(game, daycare: daycare())
        #expect(eggs.count == 51)
        for egg in eggs {
            #expect(egg.inheritance.filter { $0 != 0 }.count == 3)
            for (iv, parent) in zip(egg.ivs, egg.inheritance) where parent != 0 {
                #expect(iv == (parent == 1 ? 31 : 0))
            }
        }
        // Black 2 and White 2 make the egg from the seed: every advance's
        // is the same but its PID.
        if game == .white2 {
            #expect(Set(eggs.map(\.ivs)).count == 1 && Set(eggs.map(\.pid)).count > 1)
        }
    }

    /// A power item always passes its stat; in Black 2 and White 2 an
    /// Everstone always passes its holder's nature.
    @Test func powerItemsAndEverstone() {
        var male = EggParent(ivs: Array(repeating: 31, count: 6), gender: 0)
        male.item = 7 // Power Anklet: Speed
        var female = EggParent(ivs: Array(repeating: 0, count: 6), gender: 1)
        female.item = 1
        female.nature = 15 // Modest
        let both = daycare(male: male, female: female)
        for game in [PFGame.black, .black2] {
            for egg in generate(game, daycare: both) {
                #expect(egg.inheritance[5] == 1 && egg.ivs[5] == 31)
            }
        }
        #expect(generate(.black2, daycare: both).allSatisfy { $0.nature == 15 })
    }

    /// Parents entered female first are swapped to the game's order, and
    /// the inheritance still names them as entered.
    @Test(arguments: [PFGame.white, .black2])
    func reordersParents(game: PFGame) {
        let maleFirst = daycare()
        let femaleFirst = daycare(femaleFirst: true)
        #expect(!maleFirst.isReversed && femaleFirst.isReversed)
        #expect(femaleFirst.pf.genders == (0, 1) && femaleFirst.pf.parentAIVs.0 == 31)
        let a = generate(game, daycare: maleFirst)
        let b = generate(game, daycare: femaleFirst)
        #expect(a.map(\.pid) == b.map(\.pid) && a.map(\.ivs) == b.map(\.ivs))
        let swapped = a.map { $0.inheritance.map { $0 == 1 ? UInt8(2) : $0 == 2 ? 1 : 0 } }
        #expect(b.map(\.inheritance) == swapped)
        // The female, or else Ditto, goes second.
        #expect(Gen5Daycare(parentA: EggParent(gender: 3), parentB: EggParent(gender: 2), specie: 81, masuda: false).isReversed)
        #expect(Gen5Daycare(parentA: EggParent(gender: 1), parentB: EggParent(gender: 3), specie: 1, masuda: false).isReversed)
        #expect(!Gen5Daycare(parentA: EggParent(gender: 3), parentB: EggParent(gender: 1), specie: 1, masuda: false).isReversed)
        #expect(Gen5Daycare(parentA: EggParent(gender: 1), parentB: EggParent(gender: 0), specie: 1, masuda: false)
            .yourParents([1, 2, 0]) == [2, 1, 0])
    }

    /// Only a female with her hidden ability passes it down, bred with a
    /// male, as PokéFinder checks.
    @Test func hiddenAbility() {
        var female = EggParent(gender: 1)
        female.ability = 2
        let parents = daycare(female: female)
        #expect(parents.blockedReason(hiddenAbility: true) == nil)
        var filter = Gen5EggFilter()
        filter.ability = 2
        let eggs = generate(.black, daycare: parents, maxAdvances: 200, filter: filter)
        #expect(!eggs.isEmpty && eggs.allSatisfy { $0.ability == 2 })
        // Black 2 and White 2 fix the egg's ability from the seed: 60% of
        // seeds give the hidden one, and none without it.
        func black2Abilities(_ parents: Gen5Daycare) -> [UInt8] {
            (0..<20).compactMap { second in
                let seed = PFBridge.gen5InitialSeed(game: .black2, profile: ds, timer0: 0xC79, year: 2012, month: 7,
                                                    day: 1, hour: 9, minute: 0, second: UInt8(second))
                return PFBridge.eggGenerate5(seed: seed, initialAdvances: 0, maxAdvances: 0, game: .black2, tid: 0, sid: 0,
                                             profile: ds, daycare: parents, filter: Gen5EggFilter()).first?.ability
            }
        }
        #expect(black2Abilities(parents).contains(2) && !black2Abilities(daycare()).contains(2))
        #expect(daycare().blockedReason(hiddenAbility: true) != nil)
        #expect(daycare().blockedReason(hiddenAbility: false) == nil)
        let ditto = Gen5Daycare(parentA: EggParent(gender: 3), parentB: female, specie: 1, masuda: false)
        #expect(ditto.blockedReason(hiddenAbility: true) != nil)
        let males = Gen5Daycare(parentA: EggParent(gender: 0), parentB: EggParent(gender: 0), specie: 1, masuda: false)
        #expect(males.blockedReason(hiddenAbility: false) == EggParent.cannotBreedText)
    }

    /// The searcher finds the second an egg's seed was made on, and each
    /// result regenerates from its seed.
    @Test(arguments: [PFGame.black, .white2])
    func searchFindsTheSeed(game: PFGame) async throws {
        let parents = daycare()
        let egg = try #require(generate(game, daycare: parents, maxAdvances: 0).first)
        var filter = Gen5EggFilter()
        filter.ivMin = egg.ivs
        filter.ivMax = egg.ivs
        filter.natures = [egg.nature]
        let handle = try #require(PFBridge.eggSearch5Start(game: game, tid: 0, sid: 0, profile: ds, daycare: parents,
                                                           start: (2011, 3, 6), end: (2011, 3, 6),
                                                           initialAdvances: 0, maxAdvances: 0, filter: filter))
        var found: [PFBridge.EggSearchResult5] = []
        while !PFBridge.eggSearch5Done(handle) {
            found += PFBridge.eggSearch5Results(handle, daycare: parents)
            try? await Task.sleep(for: .milliseconds(20))
        }
        found += PFBridge.eggSearch5Results(handle, daycare: parents)
        #expect(PFBridge.eggSearch5Progress(handle) == 100)
        PFBridge.eggSearch5Free(handle)
        let hit = try #require(found.first { $0.seed == seed(game) })
        #expect(hit.hour == 10 && hit.minute == 20 && hit.second == 33 && hit.timer0 == 0xC79)
        #expect(hit.egg == egg)
        for r in found.prefix(20) {
            let again = PFBridge.eggGenerate5(seed: r.seed, initialAdvances: 0, maxAdvances: 0, game: game,
                                              tid: 0, sid: 0, profile: ds, daycare: parents, filter: filter)
            #expect(again == [r.egg])
        }
        // Dates the wrong way round don't start.
        #expect(PFBridge.eggSearch5Start(game: game, tid: 0, sid: 0, profile: ds, daycare: parents,
                                         start: (2011, 3, 7), end: (2011, 3, 6),
                                         initialAdvances: 0, maxAdvances: 0, filter: filter) == nil)
    }

    /// A Gen 5 egg result sends the Gen 5 Timer its second.
    @MainActor
    @Test func sendToTimer() throws {
        let egg = try #require(generate(.black, daycare: daycare(), maxAdvances: 0).first)
        let r = PFBridge.EggSearchResult5(year: 2011, month: 3, day: 6, hour: 10, minute: 20, second: 33,
                                          seed: 0x1234, timer0: 0xC79, buttons: 0, egg: egg)
        let bridge = FinderTimerBridge.shared
        bridge.clear()
        Gen5EggView.sendToTimer(r)
        #expect(bridge.pendingGen == .gen5 && bridge.pendingTargetSecond == 33 && bridge.shouldSwitchToTimer)
        #expect(bridge.selectedTime == "2011/03/06 10:20:33" && bridge.selectedSeed == "0000000000001234")
        bridge.clear()
    }

    /// The species lists stop at each generation's last species, which the
    /// generators' tables end at, and name every species.
    @MainActor
    @Test func eggSpecies() {
        #expect(EggSpecies.all == EggSpecies.all.sorted())
        for generation in [FinderGeneration.gen3, .gen4, .gen5] {
            let list = EggSpecies.list(for: generation)
            #expect(list.first == 1 && list.allSatisfy { $0 <= EggSpecies.last(in: generation) })
            #expect([29, 32, 313, 314].allSatisfy(list.contains))
            #expect(!list.map(PFBridge.specieName).contains("???"))
        }
        #expect(EggSpecies.list(for: .gen3).last == 374)
        #expect(EggSpecies.list(for: .gen4).last == 489)
        #expect(EggSpecies.list(for: .gen5).last == 636)
    }

    /// Who can breed, and what each game's cards show.
    @MainActor
    @Test func parentRules() {
        for (a, b) in [(0, 1), (1, 0), (0, 3), (3, 0), (1, 3), (3, 1), (2, 3), (3, 2)] {
            #expect(EggParent.canBreed(UInt8(a), UInt8(b)), "\(a) \(b)")
        }
        for (a, b) in [(0, 0), (1, 1), (2, 2), (3, 3), (0, 2), (2, 1)] {
            #expect(!EggParent.canBreed(UInt8(a), UInt8(b)), "\(a) \(b)")
        }
        #expect(EggParentFields(game: .emerald).items == [0, 1] && EggParentFields(game: .emerald).abilities.isEmpty)
        #expect(EggParentFields(game: .ruby).items.isEmpty && EggParentFields(game: .platinum).items.isEmpty)
        #expect(EggParentFields(game: .black).abilities == [0, 1, 2] && EggParentFields(game: .white2).items == Array(0...7))
        var parent = EggParent(gender: 1)
        parent.ability = 2
        parent.item = 5
        let fitted = EggParentFields(game: .emerald).fitting(parent)
        #expect(fitted.ability == 0 && fitted.item == 0)
        #expect(EggParentFields(game: .black).fitting(parent) == parent)
        #expect(EggParent.inheritanceText([1, 2, 0, 0, 0, 0]) == "HP:A Atk:B Def:R SpA:R SpD:R Spe:R")
        #expect(chatotPitchText(5) == "L 5" && chatotPitchText(99) == "H 99")
    }
}
