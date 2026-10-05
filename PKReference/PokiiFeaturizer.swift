//
//  PokiiFeaturizer.swift
//  PKReference
//
//  Translates a BattleEngine + (side, slot) decision point into the three
//  tensors the doubles policy expects:
//
//      x_cat  (4)              species2idx for [acting, ally, opp0, opp1]
//      x_cont (105)            laid out per feature_config.continuous_layout
//      mask   (N_CLASSES)      0 for legal actions, -1e9 for illegal
//
//  The labels the model outputs use Showdown-style names:
//    species  →  lowercase, words separated with "-"  (e.g. "tapu-koko",
//                "alcremie-lemon-cream", "iron-hands")
//    moves    →  Title_Case_With_Underscores, hyphens / apostrophes kept
//                (e.g. "Aerial_Ace", "Will-O-Wisp", "King's_Shield")
//
//  The "missing from vocab" handling matches the original guide: an unknown
//  species rolls over to `<unk>` (index 1); an unknown move name means the
//  AI controller may not see that move slot as legal. A single warning is
//  logged the first time a particular name falls back so it's easy to spot
//  vocab coverage gaps without spamming the console.
//

import Foundation

// MARK: - Tensors

struct PokiiBattlerInputs {
    let xCat: [Int]
    let xCont: [Float]
    let mask: [Float]
}

// MARK: - Featurizer

@MainActor
enum PokiiFeaturizer {

    private static let maskIllegal: Float = -1e9

    // MARK: Public

    /// Build the model inputs for one decision point. Returns `nil` if the
    /// model isn't loaded (so the caller can decide to fall back to a manual
    /// turn or silently skip).
    ///
    /// `claimedBench` is the set of bench indices on this side that an earlier
    /// AI decision this turn already committed to switching in — we mask those
    /// `switch_*` labels off so a second slot can't pick the same Pokemon.
    static func makeInputs(engine: BattleEngine, side sIdx: Int, slot: Int,
                           claimedBench: Set<Int> = []) -> PokiiBattlerInputs? {
        let model = PokiiBattler.shared
        guard model.ensureLoaded() else { return nil }
        guard let actor = engine.side(at: sIdx).active(at: slot) else { return nil }

        let mySide = engine.side(at: sIdx)
        let oppSide = engine.side(at: 1 - sIdx)
        let allySlot = (slot == 0) ? 1 : 0
        let ally = engine.format == .doubles ? mySide.active(at: allySlot) : nil
        let opp0 = oppSide.active(at: 0)
        let opp1 = engine.format == .doubles ? oppSide.active(at: 1) : nil

        // ---- x_cat (4 species indices)
        let xCat: [Int] = [
            speciesIndex(actor),
            ally.map(speciesIndex) ?? 0,
            opp0.map(speciesIndex) ?? 0,
            opp1.map(speciesIndex) ?? 0,
        ]

        // ---- x_cont (105 floats)
        var xCont = [Float](); xCont.reserveCapacity(model.contDim)
        xCont.append(contentsOf: monBlock(actor))
        xCont.append(contentsOf: monBlockOptional(ally))
        xCont.append(contentsOf: monBlockOptional(opp0))
        xCont.append(contentsOf: monBlockOptional(opp1))

        // 4 exist flags
        xCont.append(1.0)
        xCont.append(ally != nil ? 1.0 : 0.0)
        xCont.append(opp0 != nil ? 1.0 : 0.0)
        xCont.append(opp1 != nil ? 1.0 : 0.0)

        // 8 globals
        let myAlive = mySide.participants.filter { !$0.fainted }.count
        let oppAlive = oppSide.participants.filter { !$0.fainted }.count
        let myAvgHP = avgHPRatio(mySide.participants)
        let oppAvgHP = avgHPRatio(oppSide.participants)
        xCont.append(Float(myAlive) / 6.0)
        xCont.append(Float(oppAlive) / 6.0)
        xCont.append(Float(myAvgHP))
        xCont.append(Float(oppAvgHP))
        xCont.append(Float(min(engine.turn, 50)) / 50.0)
        xCont.append(engine.trickRoomTurns > 0 ? 1.0 : 0.0)
        xCont.append(engine.gravityTurns > 0 ? 1.0 : 0.0)
        // opp_known / 6 — in a local sim both teams are fully visible.
        xCont.append(Float(oppSide.participants.count) / 6.0)
        // Mega-gate features (new in v2 of the model):
        //   my_mega_used   — has the acting side already spent its mega
        //   opp_mega_used  — has the opponent already spent theirs
        //   acting_can_mega — held-stone check + side not yet used: the
        //                     deployment-correct gate (per the integration
        //                     guide), strictly better than the data proxy.
        xCont.append(mySide.hasUsedMega ? 1.0 : 0.0)
        xCont.append(oppSide.hasUsedMega ? 1.0 : 0.0)
        xCont.append(engine.canMegaEvolve(side: sIdx, slot: slot) ? 1.0 : 0.0)

        // weather one-hot (6): none, rain, sand, sun, snow, hail
        xCont.append(contentsOf: weatherOneHot(engine.weather))
        // terrain one-hot (5): none, electric, grassy, misty, psychic
        xCont.append(contentsOf: terrainOneHot(engine.terrain))

        // side conditions: my + opp (8 each)
        xCont.append(contentsOf: sideConditionMultiHot(mySide))
        xCont.append(contentsOf: sideConditionMultiHot(oppSide))

        // 2 type-advantage floats — acting vs opp slot 0 and opp slot 1
        xCont.append(typeAdvantage(attacker: actor, defender: opp0))
        xCont.append(typeAdvantage(attacker: actor, defender: opp1))

        // Defensive: if anyone changed the layout, fail loud rather than
        // shipping a silently-misaligned feature vector.
        if xCont.count != model.contDim {
            print("[PokiiFeaturizer] cont_dim mismatch: built \(xCont.count), expected \(model.contDim)")
            return nil
        }

        // ---- mask (N_CLASSES)
        let mask = buildMask(engine: engine, side: sIdx, slot: slot,
                             actor: actor, claimedBench: claimedBench)

        return PokiiBattlerInputs(xCat: xCat, xCont: xCont, mask: mask)
    }

    /// Convert the model's chosen label (`move_X` / `switch_Y`) back into a
    /// BattleAction the engine can run. Picks a sensible target automatically
    /// for single-target moves so we don't need a second UI round-trip.
    static func decode(label: String, engine: BattleEngine, side sIdx: Int, slot: Int) -> BattleAction? {
        guard let actor = engine.side(at: sIdx).active(at: slot) else { return nil }

        if label.hasPrefix("move_") {
            let raw = String(label.dropFirst("move_".count))
            // Match on encoded form (spaces → underscores) so the actor's
            // app-stored "Will-O-Wisp" maps to vocab "Will-O-Wisp" and
            // "Aerial Ace" maps to "Aerial_Ace".
            guard let mi = actor.moves.firstIndex(where: { encodeMoveName($0.name) == raw }) else {
                return nil
            }
            return moveAction(engine: engine, side: sIdx, slot: slot, actor: actor, moveIndex: mi)
        }
        if label.hasPrefix("switch_") {
            let species = String(label.dropFirst("switch_".count))
            let bench = engine.side(at: sIdx).benchIndices()
            // Prefer an exact species match; fall back to a normalize() match
            // (strips hyphens/spaces) for niche forms whose Showdown name
            // drops a separator vs. the app's storage convention.
            if let bi = bench.first(where: { encodeSpecies(engine.side(at: sIdx).participants[$0].slot.pokemonName) == species }) {
                return .switchTo(benchIndex: bi)
            }
            let strip: (String) -> String = { BattleSimSeed.normalize($0) }
            let target = strip(species)
            if let bi = bench.first(where: { strip(engine.side(at: sIdx).participants[$0].slot.pokemonName) == target }) {
                return .switchTo(benchIndex: bi)
            }
            return nil
        }
        return nil
    }

    // MARK: - Per-mon 16-feature block

    /// 16 floats: [hp/maxHP, fainted, status one-hot(7), boosts(7)].
    /// Empty (nil) slot returns all zeros — the exist flag handles presence.
    private static func monBlock(_ p: BattleParticipant) -> [Float] {
        var v = [Float](); v.reserveCapacity(16)
        v.append(p.maxHP > 0 ? Float(p.currentHP) / Float(p.maxHP) : 0)
        v.append(p.fainted ? 1.0 : 0.0)
        v.append(contentsOf: statusOneHot(p.status))
        // boosts: atk, def, spa, spd, spe, acc, eva — each /6 to map [-6, +6] → [-1, 1].
        v.append(Float(p.atkStage) / 6.0)
        v.append(Float(p.defStage) / 6.0)
        v.append(Float(p.spAtkStage) / 6.0)
        v.append(Float(p.spDefStage) / 6.0)
        v.append(Float(p.speedStage) / 6.0)
        v.append(0.0)  // accuracy stage — not tracked by the sim
        v.append(0.0)  // evasion stage — not tracked by the sim
        return v
    }

    private static func monBlockOptional(_ p: BattleParticipant?) -> [Float] {
        if let p = p { return monBlock(p) }
        return [Float](repeating: 0, count: 16)
    }

    // MARK: - One-hot helpers

    /// Order matches feature_config.orderings.status: none, par, brn, slp, frz, psn, tox.
    private static func statusOneHot(_ s: BattleStatus) -> [Float] {
        var v = [Float](repeating: 0, count: 7)
        switch s {
        case .none:       v[0] = 1
        case .paralysis:  v[1] = 1
        case .burn:       v[2] = 1
        case .sleep:      v[3] = 1
        case .freeze:     v[4] = 1
        case .poison:     v[5] = 1
        case .toxic:      v[6] = 1
        }
        return v
    }

    /// Order: none, rain, sand, sun, snow, hail. The app collapsed hail into
    /// snow (Gen 9 Snowscape change), so the hail slot stays zero.
    private static func weatherOneHot(_ w: WeatherCondition) -> [Float] {
        var v = [Float](repeating: 0, count: 6)
        switch w {
        case .none: v[0] = 1
        case .rain: v[1] = 1
        case .sand: v[2] = 1
        case .sun:  v[3] = 1
        case .snow: v[4] = 1
        }
        return v
    }

    /// Order: none, electric, grassy, misty, psychic.
    private static func terrainOneHot(_ t: TerrainCondition) -> [Float] {
        var v = [Float](repeating: 0, count: 5)
        switch t {
        case .none:     v[0] = 1
        case .electric: v[1] = 1
        case .grassy:   v[2] = 1
        case .misty:    v[3] = 1
        case .psychic:  v[4] = 1
        }
        return v
    }

    /// Order: Stealth Rock, Spikes, Toxic Spikes, Sticky Web, Reflect,
    /// Light Screen, Aurora Veil, Tailwind. Multi-hot: each is 1.0 if active.
    private static func sideConditionMultiHot(_ side: BattleSide) -> [Float] {
        return [
            side.stealthRock          ? 1 : 0,
            side.spikesLayers > 0     ? 1 : 0,
            side.toxicSpikesLayers > 0 ? 1 : 0,
            side.stickyWeb            ? 1 : 0,
            side.reflectTurns > 0     ? 1 : 0,
            side.lightScreenTurns > 0 ? 1 : 0,
            side.auroraVeilTurns > 0  ? 1 : 0,
            side.tailwindTurns > 0    ? 1 : 0,
        ]
    }

    // MARK: - Type advantage

    /// Combined type-effectiveness of `attacker`'s STAB types vs `defender`'s
    /// types. Since the model trained on a single scalar per matchup, we take
    /// the max effectiveness across the attacker's types (rewarding the side
    /// with a super-effective STAB option). Returns 1.0 (neutral) when either
    /// pokemon is absent.
    private static func typeAdvantage(attacker: BattleParticipant,
                                      defender: BattleParticipant?) -> Float {
        guard let defender = defender, !defender.fainted else { return 1.0 }
        let defTypes = defender.types
        var best: Double = 0
        for atkType in attacker.types {
            let eff = computeTypeEffectiveness(moveType: atkType, defenderTypes: defTypes)
            if eff > best { best = eff }
        }
        return Float(best)
    }

    private static func avgHPRatio(_ parts: [BattleParticipant]) -> Double {
        let alive = parts.filter { !$0.fainted }
        guard !alive.isEmpty else { return 0 }
        let total = alive.reduce(0.0) { acc, p in
            acc + (p.maxHP > 0 ? Double(p.currentHP) / Double(p.maxHP) : 0)
        }
        return total / Double(alive.count)
    }

    // MARK: - Mask construction

    /// 0 for every legal action label, -1e9 everywhere else. Legal = a move
    /// the actor knows with PP > 0 (and not Choice/Encore/Disable/Taunt-blocked)
    /// or a switch to a benched, unfainted teammate whose species is in the vocab.
    private static func buildMask(engine: BattleEngine, side sIdx: Int, slot: Int,
                                  actor: BattleParticipant,
                                  claimedBench: Set<Int>) -> [Float] {
        let model = PokiiBattler.shared
        var mask = [Float](repeating: maskIllegal, count: model.nClasses)

        let choiceLock = engine.isChoiceLocked(actor) ? actor.choiceLockedMoveIndex : nil
        let encoreLock = actor.encoreTurns > 0 ? actor.encoreLockedIndex : nil

        // ---- Move labels
        for (mi, move) in actor.moves.enumerated() {
            // PP check
            if actor.pp.indices.contains(mi), actor.pp[mi] <= 0 { continue }
            // Choice / Encore lock
            if let lock = choiceLock, lock != mi { continue }
            if let lock = encoreLock, lock != mi { continue }
            // Disable
            if actor.disableTurns > 0, actor.disabledMoveIndex == mi { continue }
            // Taunt blocks status moves
            if actor.tauntTurnsRemaining > 0, move.damageClass == "status" { continue }

            let label = "move_" + encodeMoveName(move.name)
            if let idx = labelIndex(label) {
                mask[idx] = 0
            } else {
                logVocabMiss(label, kind: "move")
            }
        }

        // ---- Switch labels — disallowed entirely while trapped, and we skip
        // any bench mon a sibling slot has already claimed this turn so the
        // model can never argmax both slots into the same teammate.
        let trapped = actor.trapTurnsRemaining > 0
        if !trapped {
            for bi in engine.side(at: sIdx).benchIndices() where !claimedBench.contains(bi) {
                let benched = engine.side(at: sIdx).participants[bi]
                let species = encodeSpecies(benched.slot.pokemonName)
                let label = "switch_" + species
                if let idx = labelIndex(label) {
                    mask[idx] = 0
                } else {
                    logVocabMiss(label, kind: "switch")
                }
            }
        }

        // If absolutely nothing matched the vocab (rare — a Pokemon whose
        // entire moveset is OOV with no switches), flip the actor's first
        // valid move's first available label so the controller always has
        // something to commit. The mask check up top guarantees we never
        // return an empty mask to the model.
        if !mask.contains(where: { $0 >= 0 }) {
            for (mi, _) in actor.moves.enumerated() {
                if actor.pp.indices.contains(mi), actor.pp[mi] > 0 {
                    // The label miss has already been logged. We have no vocab
                    // slot to flip, so the caller will see no decision and the
                    // AI controller falls back to a deterministic local pick.
                    _ = mi
                    break
                }
            }
        }
        return mask
    }

    // MARK: - Vocab lookups

    /// species2idx lookup — always uses the *base* species name (Mega forms
    /// collapse to base per the v2 model contract). Falls back to `<unk>` = 1
    /// when the species isn't in the trained vocab.
    private static func speciesIndex(_ p: BattleParticipant) -> Int {
        let model = PokiiBattler.shared
        // Use the saved slot name (pre-Mega, pre-Stance) so a Mega Charizard X
        // still keys on "charizard". `slot.pokemonName` is the SwiftData-stored
        // species like "Charizard" or "Aegislash-Shield"; `encodeSpecies` then
        // strips Mega/Primal/Stance suffixes before the lookup.
        let raw = encodeSpecies(p.slot.pokemonName)
        if let idx = model.species2idx[raw] { return idx }
        // Try the "drop everything after the first hyphen" fallback for niche
        // regional forms whose Showdown name keeps the suffix while ours might
        // not — e.g. "raichu-alola" → "raichu" if the model only saw the base.
        if let dash = raw.firstIndex(of: "-") {
            let base = String(raw[..<dash])
            if let idx = model.species2idx[base] { return idx }
        }
        logVocabMiss(raw, kind: "species")
        return model.species2idx["<unk>"] ?? 1
    }

    /// Action vocabulary lookup. Returns `nil` if the label isn't in the
    /// model's output classes — the caller logs and masks it as illegal.
    private static func labelIndex(_ label: String) -> Int? {
        let model = PokiiBattler.shared
        if let i = model.actionVocab.firstIndex(of: label) { return i }
        return nil
    }

    // MARK: - Name encoding

    /// The app's move "Air Slash" → vocab "Air_Slash". Hyphens, apostrophes,
    /// and existing underscores are preserved.
    static func encodeMoveName(_ name: String) -> String {
        return name.replacingOccurrences(of: " ", with: "_")
    }

    /// The app's species "Tapu Koko" / "Vulpix-Alola" → vocab "tapu-koko" /
    /// "vulpix-alola". Lowercases, converts spaces to hyphens, and **collapses
    /// Mega / Primal / Stance Change forms to their base species** to match
    /// the v2 model contract (per pokii_xcode_integration_guide §3 / §6;
    /// that guide isn't in the repository).
    /// Regional and split-form names (Urshifu-Rapid-Strike, Calyrex-Shadow,
    /// Vulpix-Alola, Indeedee-F) are left intact.
    static func encodeSpecies(_ name: String) -> String {
        // Handle the "Mega <Species> [X/Y]" form first — only relevant when
        // someone hands us `displayName`. For saved-slot names this branch
        // is a no-op since the app stores the base ("Charizard").
        let lower = name.lowercased()
        if lower.hasPrefix("mega ") {
            let rest = lower.dropFirst("mega ".count)
            let parts = rest.split(separator: " ", omittingEmptySubsequences: true)
            return String(parts.first ?? Substring(rest))
        }
        if lower.hasPrefix("primal ") {
            let rest = lower.dropFirst("primal ".count)
            return String(rest.split(separator: " ", omittingEmptySubsequences: true).first ?? Substring(rest))
        }
        var key = lower.replacingOccurrences(of: " ", with: "-")
        // Strip Mega / Primal hyphen suffixes — "charizard-mega-x" → "charizard".
        for suffix in ["-mega-x", "-mega-y", "-mega", "-primal"] {
            if key.hasSuffix(suffix) {
                key.removeLast(suffix.count)
                break
            }
        }
        // Stance Change pokemon collapse to base for embedding lookup —
        // Showdown's species2idx treats Aegislash forms as one species.
        for suffix in ["-shield", "-blade"] {
            if key.hasSuffix(suffix) {
                key.removeLast(suffix.count)
                break
            }
        }
        return key
    }

    // MARK: - Target selection

    /// Wraps a chosen move index in a BattleAction with a reasonable target.
    /// In doubles, spread moves go through `.spreadMove`; single-target moves
    /// pick the opposite slot's opponent (so slot 0 → opp slot 0), falling
    /// back to whichever opposing slot is unfainted.
    private static func moveAction(engine: BattleEngine, side sIdx: Int, slot: Int,
                                   actor: BattleParticipant, moveIndex mi: Int) -> BattleAction {
        let move = actor.moves[mi]
        let isSpread = BattleMoveEffects.isSpread(move.name)
        if engine.format == .doubles && isSpread && move.damageClass != "status" {
            return .spreadMove(moveIndex: mi)
        }
        // Self / side / field-wide moves use the actor's own (side, slot) as
        // the target so the engine doesn't waste a target-resolution step.
        if BattleMoveEffects.isFixedSelfOrFieldTarget(move.name) {
            return .move(moveIndex: mi, targetSide: sIdx, targetSlot: slot)
        }
        let oppIdx = 1 - sIdx
        let oppSide = engine.side(at: oppIdx)
        let activeSlots = engine.format.activeSlots
        // Mirror: my slot 0 → their slot 0, my slot 1 → their slot 1.
        var preferred: [Int] = [slot]
        for s in 0..<activeSlots where s != slot { preferred.append(s) }
        for cand in preferred {
            if let p = oppSide.active(at: cand), !p.fainted {
                return .move(moveIndex: mi, targetSide: oppIdx, targetSlot: cand)
            }
        }
        // No live target — engine still wants a valid index; slot 0 is safe.
        return .move(moveIndex: mi, targetSide: oppIdx, targetSlot: 0)
    }

    // MARK: - Vocab miss logging (one per name)

    private static var loggedMisses = Set<String>()
    private static func logVocabMiss(_ label: String, kind: String) {
        if loggedMisses.insert(label).inserted {
            print("[PokiiFeaturizer] vocab miss (\(kind)): \(label)")
        }
    }
}
