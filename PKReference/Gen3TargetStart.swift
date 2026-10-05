//
//  Gen3TargetStart.swift
//  PKReference
//
//  Where a Gen 3 target's frames count from. Emerald boots on seed 0000
//  every time, and Ruby and Sapphire on 05A0 once their battery is dead (the
//  seed PokéFinder's Gen 3 Generators take for a dead-battery profile). With
//  a live battery, Ruby and Sapphire's seed comes from the clock. A
//  Generator seed that isn't one of these was learnt in game.
//

import Foundation

struct Gen3TargetStart: Equatable {
    enum Kind: Equatable {
        /// Every boot starts on this seed: Emerald's, or a dead battery's.
        case boot
        /// Ruby and Sapphire with a live battery: the clock makes the seed.
        case clock
        /// The Generator's seed, which the game doesn't boot on: one learnt
        /// in game, such as a new game's Trainer ID.
        case generatorSeed
        /// FireRed and LeafGreen without their seed list: the 16-bit seed
        /// before the target.
        case origin
    }

    let kind: Kind
    /// The seed the frames count from.
    let seed: UInt32
    /// Frames from `seed` to the target.
    let frame: Int

    /// Counted from boot (or the clock's seed at boot), so the Timer's
    /// Standard mode; a seed learnt in game may be Variable Target's.
    var fromBoot: Bool { kind == .boot || kind == .clock }

    /// The seed every boot starts on, if the game has one.
    static func bootSeed(game: FinderGameVersion?, deadBattery: Bool) -> UInt32? {
        switch game {
        case .emerald: 0
        case .ruby, .sapphire: deadBattery ? 0x5A0 : nil
        default: nil
        }
    }

    /// A Searcher's target carries its own frame's seed (`seed`); a
    /// Generator's, the Generator's seed and the frames from it (`advances`).
    static func of(seed: UInt32, advances: UInt32, fromGenerator: Bool,
                   game: FinderGameVersion?, deadBattery: Bool) -> Gen3TargetStart {
        let boot = bootSeed(game: game, deadBattery: deadBattery)
        let rubySapphire = game == .ruby || game == .sapphire
        if fromGenerator {
            if let boot, seed == boot {
                return Gen3TargetStart(kind: .boot, seed: boot, frame: Int(advances))
            }
            if boot == nil && rubySapphire {
                let origin = PFBridge.seedToTimeOriginSeed3(seed: seed)
                return Gen3TargetStart(kind: .clock, seed: UInt32(origin.originSeed),
                                       frame: Int(origin.advances) + Int(advances))
            }
            return Gen3TargetStart(kind: .generatorSeed, seed: seed, frame: Int(advances))
        }
        if let boot {
            return Gen3TargetStart(kind: .boot, seed: boot, frame: Int(PFBridge.lcrngDistance(from: boot, to: seed)))
        }
        let origin = PFBridge.seedToTimeOriginSeed3(seed: seed)
        return Gen3TargetStart(kind: rubySapphire ? .clock : .origin, seed: UInt32(origin.originSeed),
                               frame: Int(origin.advances))
    }
}

/// Ruby and Sapphire's clock: the day count its seed uses.
nonisolated enum RSClock {
    /// Days from 1 January to `month`/`day` of 2000, a leap year, as the
    /// game's day count (Day 1 is 1 January). PokéFinder's dates are in 2000.
    static func dayNumber(month: Int, day: Int) -> Int {
        let monthLengths = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return monthLengths.prefix(max(0, month - 1)).reduce(0, +) + day
    }
}
