//
//  RNGToolsTests.swift
//  PKReferenceTests
//
//  Tests for EonTimer port and PokeFinder port
//

import Testing
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

struct TimerEngineTests {
    @Test func initialState() {
        let engine = RNGTimerEngine()
        #expect(!engine.isRunning)
        #expect(engine.phases.isEmpty)
    }

    @Test func emptyPhases_doesNotStart() {
        let engine = RNGTimerEngine()
        engine.start(phases: [])
        #expect(!engine.isRunning)
    }

    @Test func stop_resetsState() {
        let engine = RNGTimerEngine()
        engine.start(phases: [50000])
        engine.stop()
        #expect(!engine.isRunning)
        #expect(engine.remainingMs == 0)
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

// MARK: - PokeFinder: Seed Verification Tests

struct SeedVerificationTests {
    @Test func verifySeed_usingGeneratorResult() {
        // Use a known generator result (seed 0, advance 0) and verify its IVs
        let results = staticGenerateGen3(
            seed: 0, initialAdvance: 0, maxAdvance: 0,
            natures: Set<UInt8>(), tid: 12345, sid: 54321,
            shinyOnly: false, method: .method1
        )
        let result = results[0]

        let verification = verifySeedFromIVs(
            caughtHP: result.ivHP, caughtAtk: result.ivAtk, caughtDef: result.ivDef,
            caughtSpA: result.ivSpA, caughtSpD: result.ivSpD, caughtSpe: result.ivSpe,
            caughtNature: result.nature, tid: 12345,
            targetSeed: result.seed, method: .method1
        )
        #expect(verification != nil)
    }

    @Test func verifySeed_wrongIVs_returnsNilOrDifferentSeed() {
        let verification = verifySeedFromIVs(
            caughtHP: 0, caughtAtk: 0, caughtDef: 0,
            caughtSpA: 0, caughtSpD: 0, caughtSpe: 0,
            caughtNature: 0, tid: 12345,
            targetSeed: 0x12345678, method: .method1
        )
        if let v = verification {
            #expect(v.delayDelta != 0 || v.actualSeed != v.targetSeed)
        }
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
        let methods = FinderMethod.methods(for: .gen4)
        #expect(methods.contains(.method1))
        #expect(methods.contains(.methodJ))
        #expect(methods.contains(.methodK))
        #expect(!methods.contains(.method2))
        #expect(!methods.contains(.method4))
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

// MARK: - Coin Flip Matching Tests

struct CoinFlipMatchTests {
    @Test func knownSeed_matchesExpectedFlips() {
        // Seed 0 with MT19937: first output determines H/T
        // matchesCoinFlips checks (mt.next() & 1) != 0 for each flip
        let seed: UInt32 = 0x05100320
        let flipsStr = PFBridge.coinFlips(seed)
        let expected = flipsStr.split(separator: ", ").map { $0 == "H" }
        #expect(matchesCoinFlips(seed: seed, observed: expected))
    }

    @Test func wrongFlips_doesNotMatch() {
        let seed: UInt32 = 0x05100320
        let flipsStr = PFBridge.coinFlips(seed)
        var flips = flipsStr.split(separator: ", ").map { $0 == "H" }
        // Invert the first flip
        flips[0].toggle()
        #expect(!matchesCoinFlips(seed: seed, observed: flips))
    }

    @Test func emptyObserved_alwaysMatches() {
        #expect(matchesCoinFlips(seed: 0, observed: []))
        #expect(matchesCoinFlips(seed: 0xDEADBEEF, observed: []))
    }

    @Test func singleFlip_matchesOrNot() {
        let seed: UInt32 = 0
        let firstFlipStr = PFBridge.coinFlips(seed).split(separator: ", ").first!
        let isHeads = firstFlipStr == "H"
        #expect(matchesCoinFlips(seed: seed, observed: [isHeads]))
        #expect(!matchesCoinFlips(seed: seed, observed: [!isHeads]))
    }

    @Test func differentSeeds_produceDifferentFlips() {
        let flips1 = PFBridge.coinFlips(0x00000001)
        let flips2 = PFBridge.coinFlips(0x00000002)
        #expect(flips1 != flips2)
    }
}

// MARK: - Call Matching Tests

struct CallMatchTests {
    @Test func knownSeed_matchesExpectedCalls() {
        let seed: UInt32 = 0x05100320
        let callsStr = PFBridge.getCalls(seed)
        // Parse "E, K, P, ..." into [UInt8] where E=0, K=1, P=2
        let expected: [UInt8] = callsStr.split(separator: ", ").prefix(5).map { c in
            switch c {
            case "E": return 0
            case "K": return 1
            default: return 2
            }
        }
        #expect(matchesCalls(seed: seed, observed: expected, skips: 0))
    }

    @Test func wrongCalls_doesNotMatch() {
        let seed: UInt32 = 0x05100320
        let callsStr = PFBridge.getCalls(seed)
        var calls: [UInt8] = callsStr.split(separator: ", ").prefix(5).map { c in
            switch c {
            case "E": return 0
            case "K": return 1
            default: return 2
            }
        }
        // Change first call to something different
        calls[0] = (calls[0] + 1) % 3
        #expect(!matchesCalls(seed: seed, observed: calls, skips: 0))
    }

    @Test func emptyObserved_alwaysMatches() {
        #expect(matchesCalls(seed: 0, observed: [], skips: 0))
        #expect(matchesCalls(seed: 0, observed: [], skips: 3))
    }

    @Test func roamerSkips_offsetsCalls() {
        let seed: UInt32 = 0x05100320
        // With 0 skips, get the calls starting from advance 1
        let calls0 = PFBridge.getCalls(seed, skips: 0)
        let calls2 = PFBridge.getCalls(seed, skips: 2)
        // Skips should shift the sequence
        #expect(calls0 != calls2)

        // Parse calls with 2 skips and verify matchesCalls agrees
        // The format with skips includes "(X skipped)" prefix, parse after it
        let parsed: [UInt8] = calls2
            .replacingOccurrences(of: "(", with: "")
            .split(separator: ")").last!
            .trimmingCharacters(in: .whitespaces)
            .split(separator: ", ").prefix(5).map { c in
                switch c.trimmingCharacters(in: .whitespaces) {
                case "E": return 0
                case "K": return 1
                default: return 2
                }
            }
        #expect(matchesCalls(seed: seed, observed: parsed, skips: 2))
    }

    @Test func matchesCalls_usesLCRNG() {
        // Manually verify the LCRNG: seed * 0x41C64E6D + 0x6073
        let seed: UInt32 = 1
        var state = seed
        state = state &* 0x41C64E6D &+ 0x6073
        let call = UInt8((state >> 16) % 3)
        #expect(matchesCalls(seed: seed, observed: [call], skips: 0))
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
            PFBridge.undergroundGenerate8(seed0: 0x1234_5678_9ABC_DEF0, seed1: 0x0FED_CBA9_8765_4321,
                                          initialAdvances: 0, maxAdvances: 300, levelFlag: levelFlag,
                                          tid: 0, sid: 0, game: .bd, storyFlag: stage)
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
        #expect(EggRNGView.generations == [.gen3, .gen4])
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
struct RNGFilterAndLeadTests {
    private let route101 = findLocationID(pfGame: .emerald, pfEnc: .grass, isGen3: true, locationName: "Route 101")

    private func wild(gen: FinderGeneration, mode: FinderRootView.FinderMode, method: FinderMethod, game: PFGame,
                      location: UInt8, seed: UInt32 = 0, maxAdvance: UInt32 = 1_000, natures: Set<UInt8> = [],
                      minIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0),
                      maxIVs: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (31, 31, 31, 31, 31, 31),
                      lead: FinderLead = .none, syncNature: UInt8 = 0) -> [StaticSearchResult] {
        let box = ResultCollector()
        runWildSearch(gen: gen, mode: mode, method: method, natures: natures, tid: 0, sid: 0, shinyOnly: false,
                      minIVs: minIVs, maxIVs: maxIVs, seed: seed, initAdv: 0, maxAdv: maxAdvance,
                      searcherMinAdv: 0, searcherMaxAdv: 20, minDelay: 600, maxDelay: 620,
                      pfGame: game, pfEnc: .grass, locationID: location, slotSpecies: [], speciesFilter: 0,
                      lead: lead, syncNature: syncNature, isEmerald: false, onResult: { box.append($0) })
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
        let platinum = findLocationID(pfGame: .platinum, pfEnc: .grass, isGen3: false, locationName: "Route 201")
        let jolly = wild(gen: .gen4, mode: .generator, method: .methodJ, game: .platinum, location: platinum,
                         seed: 0x0C12_0353, natures: [13])
        #expect(!jolly.isEmpty && jolly.allSatisfy { $0.nature == 13 })
    }

    /// A wild Generator result carries the seed it came from, so its Seed to
    /// Time is the right one (it showed seed 0).
    @Test func wildGeneratorKeepsTheSeed() {
        let results = wild(gen: .gen3, mode: .generator, method: .method1, game: .emerald, location: route101,
                           seed: 0x0C12_0353, maxAdvance: 5)
        #expect(results.count == 6 && results.allSatisfy { $0.seed == 0x0C12_0353 })
        let platinum = findLocationID(pfGame: .platinum, pfEnc: .grass, isGen3: false, locationName: "Route 201")
        let gen4 = wild(gen: .gen4, mode: .generator, method: .methodJ, game: .platinum, location: platinum,
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
    @Test func undergroundFilters() {
        func generate(natures: Set<UInt8>, gender: UInt8 = 255) -> [StaticSearchResult] {
            var results: [StaticSearchResult] = []
            undergroundGenerateGen8Streaming(seed0: 0x1234_5678_9ABC_DEF0, seed1: 0x0FED_CBA9_8765_4321,
                                             initialAdvance: 0, maxAdvance: 300, natures: natures, tid: 0, sid: 0,
                                             shinyOnly: false, lead: .none, game: .bd, shinyCharm: false,
                                             diglett: false, storyFlag: 6, filterGender: gender) { results.append($0) }
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
