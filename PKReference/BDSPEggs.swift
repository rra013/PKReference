//
//  BDSPEggs.swift
//  PKReference
//
//  Brilliant Diamond and Shining Pearl's eggs, the Finder's Egg mode: the
//  daycare as PokéFinder's Eggs8 screen takes it, with its parent checks
//  and the game's parent order.
//

import Foundation

/// The daycare as PokéFinder's EggGenerator8 takes it.
nonisolated struct BDSPDaycare: EggDaycare, Hashable, Sendable {
    var parentA: EggParent
    var parentB: EggParent
    var specie: UInt16
    var masuda: Bool

    /// The parent the egg's ability comes from: EggGenerator8 reads the
    /// second parent's (the female's), or the first's when the second is
    /// Ditto.
    var abilityParent: EggParent {
        let (first, second) = gameOrder
        return second.gender == 3 ? first : second
    }

    /// Why these parents can't make what's asked (PokéFinder's
    /// `EggSettings::isValid`): in BDSP the female passes down her hidden
    /// ability, or with Ditto the other parent its own.
    func blockedReason(hiddenAbility: Bool) -> String? {
        guard EggParent.canBreed(parentA.gender, parentB.gender) else { return EggParent.cannotBreedText }
        if hiddenAbility && abilityParent.ability != 2 {
            return "Only the female, or the parent bred with Ditto, passes down its hidden ability: set its ability to Hidden Ability, or the filter to another."
        }
        return nil
    }
}
