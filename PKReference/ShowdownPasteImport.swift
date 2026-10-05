//
//  ShowdownPasteImport.swift
//  PKReference
//
//  Bridge layer between the lossless paste structs in `ShowdownPaste.swift`
//  and the app's own models: `PKMNStats` / `MoveData` / `HeldItem` / `Nature`
//  for display and persistence, `PokemonSet` for `ChampionsValidator`, and
//  `SavedSpread` / `TeamSlotInfo` on commit.
//
//  Three naming conventions meet here, and none of them agree:
//
//    * `PKMNStats.name`  — hyphen-joined capitalized, from PokeAPI slugs:
//                          "Mr-Rime", "Charizard-Mega-X", "Kommo-O"
//    * `MoveData.name`   — space-joined capitalized: "Fake Out", "U Turn"
//    * validator JSON    — human-pretty: "Mr. Rime", "Mega Charizard X",
//                          "Aurora Veil", "Snow Warning"
//    * Showdown pastes   — its own thing again: "Charizard-Mega-X", "U-turn"
//
//  Rather than pick a winner, everything joins on `toID` (the upstream
//  Showdown normalizer, which strips to `[a-z0-9]`) with a token-set fallback
//  so word order stops mattering — that's what lets "Charizard-Mega-X" find
//  the validator's "Mega Charizard X". Each target then keeps its own
//  spelling.
//
//  Resolution never throws away a set: an unresolvable species blocks that
//  one slot, everything else imports with an `ImportIssue` attached.
//

import Foundation

// MARK: - Name index

/// Case/punctuation/word-order-insensitive lookup over a named collection,
/// with a cheap fuzzy suggestion for misses.
struct NameIndex<Value> {
    private var byID: [ShowdownID: Value] = [:]
    /// Alphanumeric tokens, lowercased and sorted, joined by "|". Lets
    /// "Charizard-Mega-X" and "Mega Charizard X" land on the same key.
    private var byTokens: [String: Value] = [:]
    /// (normalized, original) for fuzzy suggestions.
    private var names: [(id: ShowdownID, display: String)] = []

    init(_ items: some Sequence<Value>, name: (Value) -> String) {
        for item in items {
            let display = name(item)
            let id = toID(display)
            guard !id.isEmpty else { continue }
            // First writer wins, so a canonical entry isn't displaced by a
            // later alias that happens to normalize the same way.
            if byID[id] == nil { byID[id] = item }
            let tokenKey = Self.tokenKey(display)
            if byTokens[tokenKey] == nil { byTokens[tokenKey] = item }
            names.append((id: id, display: display))
        }
    }

    static func tokenKey(_ name: String) -> String {
        name.lowercased()
            .split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) })
            .map(String.init)
            .sorted()
            .joined(separator: "|")
    }

    /// Exact normalized match, then token-set match.
    func resolve(_ raw: String) -> Value? {
        let id = toID(raw)
        if let hit = byID[id] { return hit }
        return byTokens[Self.tokenKey(raw)]
    }

    /// First candidate that resolves, in order.
    func resolve(anyOf candidates: [String]) -> Value? {
        for candidate in candidates {
            if let hit = resolve(candidate) { return hit }
        }
        return nil
    }

    /// Closest known display name by edit distance on the normalized forms,
    /// or nil when nothing is close enough to be worth suggesting.
    func closestName(to raw: String, maxDistance: Int = 3) -> String? {
        let target = toID(raw)
        guard !target.isEmpty else { return nil }
        var best: (name: String, distance: Int)?
        for entry in names {
            // Length gate first — editDistance is the expensive part.
            if abs(entry.id.count - target.count) > maxDistance { continue }
            let d = Self.editDistance(entry.id, target, cutoff: maxDistance)
            guard d <= maxDistance else { continue }
            if let current = best, d >= current.distance { continue }
            best = (name: entry.display, distance: d)
            if d == 1 { break }   // can't do better without being an exact hit
        }
        return best?.name
    }

    /// Levenshtein distance, two-row, abandoning once every cell in a row
    /// exceeds `cutoff`.
    static func editDistance(_ a: String, _ b: String, cutoff: Int) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }

        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)

        for i in 1...x.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...y.count {
                let substitution = previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
                rowMin = min(rowMin, current[j])
            }
            if rowMin > cutoff { return cutoff + 1 }
            swap(&previous, &current)
        }
        return previous[y.count]
    }
}

// MARK: - Issues

/// Something the importer had to work around. Distinct from `Violation`
/// (format legality) and `PasteDiagnostic` (malformed text) — this is the
/// "we couldn't match this to app data" layer.
enum ImportIssue: Equatable, Sendable {
    /// No Pokedex row for this species. The only blocking issue.
    case speciesUnresolved(raw: String, suggestion: String?)
    case moveUnresolved(slot: Int, raw: String, suggestion: String?)
    /// The item isn't one the app models (e.g. a damage-neutral berry).
    /// Kept as text so export still round-trips it.
    case itemUnrecognized(raw: String)
    case abilityUnrecognized(raw: String, suggestion: String?)
    /// Paste had no `X Nature` line; defaulted to a neutral nature rather
    /// than silently inheriting a stat-boosting one.
    case natureDefaulted
    case natureUnrecognized(raw: String)
    /// Paste had no `Level:` line.
    case levelDefaulted(Int)
    case evScaleConverted(from: StatScale, to: StatScale)
    case evClamped(stat: ShowdownStat, from: Int, to: Int)

    var isBlocking: Bool {
        if case .speciesUnresolved = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .speciesUnresolved(let raw, let suggestion):
            if let suggestion {
                return "Unknown species \"\(raw)\" — did you mean \(suggestion)?"
            }
            return "Unknown species \"\(raw)\"."
        case .moveUnresolved(let slot, let raw, let suggestion):
            if let suggestion {
                return "Move \(slot + 1) \"\(raw)\" not found — did you mean \(suggestion)?"
            }
            return "Move \(slot + 1) \"\(raw)\" not found."
        case .itemUnrecognized(let raw):
            return "\"\(raw)\" isn't modelled by the calculator; kept as text."
        case .abilityUnrecognized(let raw, let suggestion):
            if let suggestion {
                return "Ability \"\(raw)\" not found — did you mean \(suggestion)?"
            }
            return "Ability \"\(raw)\" not found."
        case .natureDefaulted:
            return "No nature in the paste; defaulted to Serious (neutral)."
        case .natureUnrecognized(let raw):
            return "Unknown nature \"\(raw)\"; defaulted to Serious (neutral)."
        case .levelDefaulted(let level):
            return "No level in the paste; assumed \(level)."
        case .evScaleConverted(let from, let to):
            let fromName = from == .mainline ? "mainline EVs" : "Champions points"
            let toName = to == .mainline ? "mainline EVs" : "Champions points"
            return "Converted \(fromName) to \(toName)."
        case .evClamped(let stat, let from, let to):
            return "\(stat.rawValue.uppercased()) \(from) exceeded the cap; clamped to \(to)."
        }
    }
}

// MARK: - Resolved slot

/// One paste set resolved against app data, ready to preview or commit.
struct ResolvedSlot: Identifiable {
    let id = UUID()
    /// The set as parsed, for re-export and for showing the user what they pasted.
    let source: ShowdownPasteSet

    let pokemon: PKMNStats?
    /// Ability in the app's convention ("intimidate"), for `SavedSpread`.
    let ability: String?
    /// Ability in the validator's convention ("Intimidate"), for `PokemonSet`.
    let validatorAbility: String?
    let item: HeldItem
    let nature: Nature
    let level: Int
    /// Four slots; nil where the move name didn't resolve.
    let moves: [MoveData?]
    /// Move names in the validator's convention, blanks dropped.
    let validatorMoves: [String]
    /// Species name in the validator's convention, for `PokemonSet`.
    let validatorSpecies: String
    /// EVs in `ImportPreview.targetScale`.
    let evs: ShowdownStats
    let ivs: ShowdownStats

    var issues: [ImportIssue]
    var violations: [Violation]

    /// True when this slot can't be imported at all.
    var isBlocked: Bool { pokemon == nil }

    /// What to show in the preview list.
    var displayName: String { pokemon?.name ?? source.species }

    /// The item to save: the modelled item's name, or the text as written
    /// when the calc doesn't model it (Air Balloon, Red Card), so it isn't
    /// lost. nil for no item.
    var itemText: String? {
        if item != .none { return item.rawValue }
        guard let raw = source.item, !raw.isEmpty else { return nil }
        return raw
    }

    var legalityViolations: [Violation] { violations.filter { $0.category.isLegality } }
    var coherenceViolations: [Violation] { violations.filter { !$0.category.isLegality } }
}

// MARK: - Preview

struct ImportPreview {
    var slots: [ResolvedSlot] = []
    /// Carried through from parsing so the sheet can show text-level problems.
    var parseDiagnostics: [PasteDiagnostic] = []
    /// Team-level violations (size, species clause). Only populated when a
    /// validator is available and every slot resolved.
    var teamViolations: [Violation] = []
    var targetScale: StatScale = .champions
    var scaleWasAmbiguous: Bool = false

    var importableSlots: [ResolvedSlot] { slots.filter { !$0.isBlocked } }
    var blockedCount: Int { slots.filter(\.isBlocked).count }
    var hasLegalityViolations: Bool {
        slots.contains { !$0.legalityViolations.isEmpty } ||
        teamViolations.contains { $0.category.isLegality }
    }
    /// Whether "Import" should be enabled at all.
    var isImportable: Bool { !importableSlots.isEmpty }
}

// MARK: - Importer

/// Resolves parsed pastes against the live Pokedex. Main-actor because
/// `PKMNStats` / `MoveData` are SwiftData models.
@MainActor
struct PasteImporter {

    private let speciesIndex: NameIndex<PKMNStats>
    private let moveIndex: NameIndex<MoveData>
    private let itemIndex: NameIndex<HeldItem>
    private let natureIndex: NameIndex<Nature>

    private let validator: ChampionsValidator?
    private let validatorSpecies: NameIndex<String>
    private let validatorMoves: NameIndex<String>
    private let validatorAbilities: NameIndex<String>

    /// Scale the imported EVs are stored in. Champions by default, matching
    /// the app's primary format and `SavedSpread.championsMode`.
    let targetScale: StatScale

    /// `validator` is required rather than defaulted: building one parses
    /// ~600 KB of bundled JSON, so the owning view must construct the
    /// importer once and hold it, not rebuild it per keystroke. Pass nil to
    /// skip legality checks entirely (non-Champions imports, unit tests).
    init(allPokemon: [PKMNStats],
         allMoves: [MoveData],
         validator: ChampionsValidator?,
         targetScale: StatScale = .champions) {
        self.speciesIndex = NameIndex(allPokemon) { $0.name }
        self.moveIndex = NameIndex(allMoves) { $0.name }
        // `.none` and the synthetic `.typeBoost` bucket aren't real item
        // names and must never win a lookup.
        self.itemIndex = NameIndex(
            HeldItem.allCases.filter { $0 != .none && $0 != .typeBoost }
        ) { $0.rawValue }
        self.natureIndex = NameIndex(allNatures) { $0.name }
        self.validator = validator
        self.targetScale = targetScale

        if let validator {
            // Learnset keys include Mega forms; the whitelist doesn't.
            var speciesNames = Array(validator.speciesWhitelist)
            speciesNames.append(contentsOf: validator.learnsets.keys)
            self.validatorSpecies = NameIndex(speciesNames) { $0 }
            self.validatorMoves = NameIndex(Set(validator.learnsets.values.joined())) { $0 }
            self.validatorAbilities = NameIndex(validator.abilityWhitelist) { $0 }
        } else {
            self.validatorSpecies = NameIndex([String]()) { $0 }
            self.validatorMoves = NameIndex([String]()) { $0 }
            self.validatorAbilities = NameIndex([String]()) { $0 }
        }
    }

    // MARK: Preview

    func preview(_ parsed: ParsedPaste) -> ImportPreview {
        var out = ImportPreview(
            parseDiagnostics: parsed.diagnostics,
            targetScale: targetScale,
            scaleWasAmbiguous: parsed.scaleWasAmbiguous
        )
        out.slots = parsed.sets.map { resolve($0, sourceScale: parsed.detectedScale) }

        // Team-level rules only make sense on a fully-resolved team.
        if let validator, !out.slots.contains(where: \.isBlocked), !out.slots.isEmpty {
            let sets = out.slots.map(pokemonSet(for:))
            let all = validator.validate(team: sets)
            // Per-set violations are already attached to their slot; keep only
            // the team-scoped categories here so the UI doesn't double-report.
            out.teamViolations = all.filter {
                [.wrongTeamSize, .speciesClause, .itemClause].contains($0.category)
            }
        }
        return out
    }

    private func resolve(_ set: ShowdownPasteSet, sourceScale: StatScale) -> ResolvedSlot {
        var issues: [ImportIssue] = []

        // Species: direct, then the form aliases the tournament importer
        // already needed (Floette-Eternal, Aegislash-Shield, ...).
        let candidates = TournamentSpeciesAlias.candidates(for: set.species)
        let pokemon = speciesIndex.resolve(set.species)
            ?? speciesIndex.resolve(anyOf: candidates)
        if pokemon == nil {
            issues.append(.speciesUnresolved(
                raw: set.species,
                suggestion: speciesIndex.closestName(to: set.species)))
        }

        // Validator species key: fall back to the raw text so the validator
        // reports "not legal" rather than the importer silently dropping it.
        let validatorSpeciesName = validatorSpecies.resolve(set.species)
            ?? validatorSpecies.resolve(anyOf: candidates)
            ?? pokemon?.name
            ?? set.species

        // Ability.
        var ability: String?
        var validatorAbility: String?
        if let raw = set.ability, !raw.isEmpty {
            ability = pokemon?.allAbilities.first { toID($0) == toID(raw) }
            validatorAbility = validatorAbilities.resolve(raw)
            if ability == nil && validatorAbility == nil {
                issues.append(.abilityUnrecognized(
                    raw: raw,
                    suggestion: validatorAbilities.closestName(to: raw)))
            }
            // Keep the raw text when only one side resolved, so nothing is lost.
            ability = ability ?? raw
            validatorAbility = validatorAbility ?? raw
        }

        // Item.
        var item = HeldItem.none
        if let raw = set.item, !raw.isEmpty {
            // A paste exported before an item was renamed uses its old name.
            if let resolved = itemIndex.resolve(HeldItem.currentName(raw)) {
                item = resolved
            } else {
                issues.append(.itemUnrecognized(raw: raw))
            }
        }

        // Nature — never default to a stat-boosting one.
        let neutral = allNatures.first { $0.id == "serious" } ?? allNatures[0]
        var nature = neutral
        if let raw = set.nature, !raw.isEmpty {
            if let resolved = natureIndex.resolve(raw) {
                nature = resolved
            } else {
                issues.append(.natureUnrecognized(raw: raw))
            }
        } else {
            issues.append(.natureDefaulted)
        }

        // Level.
        let level: Int
        if let parsedLevel = set.level {
            level = parsedLevel
        } else {
            level = Self.defaultLevel
            issues.append(.levelDefaulted(Self.defaultLevel))
        }

        // Moves.
        var moves: [MoveData?] = []
        var validatorMoveNames: [String] = []
        for (index, raw) in set.moves.enumerated() {
            let resolved = moveIndex.resolve(raw)
            moves.append(resolved)
            if resolved == nil {
                issues.append(.moveUnresolved(
                    slot: index, raw: raw,
                    suggestion: moveIndex.closestName(to: raw)))
            }
            validatorMoveNames.append(validatorMoves.resolve(raw) ?? raw)
        }
        while moves.count < 4 { moves.append(nil) }

        // EVs: convert and clamp into the target scale.
        var evs = ShowdownStats()
        if sourceScale != targetScale {
            issues.append(.evScaleConverted(from: sourceScale, to: targetScale))
        }
        for stat in ShowdownStat.allCases {
            let converted = StatScale.convert(
                set.evs[stat], from: sourceScale, to: targetScale)
            let capped = min(converted, targetScale.maxPerStat)
            if capped != converted {
                issues.append(.evClamped(stat: stat, from: converted, to: capped))
            }
            evs[stat] = capped
        }

        var slot = ResolvedSlot(
            source: set,
            pokemon: pokemon,
            ability: ability,
            validatorAbility: validatorAbility,
            item: item,
            nature: nature,
            level: level,
            moves: moves,
            validatorMoves: validatorMoveNames,
            validatorSpecies: validatorSpeciesName,
            evs: evs,
            ivs: set.ivs,
            issues: issues,
            violations: []
        )

        // Legality only means something on the Champions scale.
        if let validator, targetScale == .champions {
            slot.violations = validator.validate(set: pokemonSet(for: slot))
        }
        return slot
    }

    static let defaultLevel = 50

    // MARK: Mapping out

    /// The validator's view of a slot. Stat points are the Champions scale,
    /// which is what `validateStatPoints` checks against.
    func pokemonSet(for slot: ResolvedSlot) -> PokemonSet {
        let points = PokemonSet.StatPoints(
            hp: slot.evs.hp, atk: slot.evs.atk, def: slot.evs.def,
            spa: slot.evs.spa, spd: slot.evs.spd, spe: slot.evs.spe
        )
        return PokemonSet(
            species: slot.validatorSpecies,
            ability: slot.validatorAbility ?? "",
            item: slot.itemText,
            nature: slot.nature.name,
            teraType: slot.source.teraType,
            moves: slot.validatorMoves,
            statPoints: points,
            role: nil
        )
    }

    /// Persistable spread. Returns nil for a blocked slot — there's no
    /// Pokedex row to point at.
    func savedSpread(for slot: ResolvedSlot, name: String) -> SavedSpread? {
        guard let pokemon = slot.pokemon else { return nil }
        let moveIDs = slot.moves.map { $0?.id }
        return SavedSpread(
            name: name,
            pokemonID: pokemon.id,
            pokemonName: pokemon.name,
            abilityName: slot.ability,
            itemRawValue: slot.itemText,
            championsMode: targetScale == .champions,
            natureID: slot.nature.id,
            level: slot.level,
            evHP: slot.evs.hp, evAtk: slot.evs.atk, evDef: slot.evs.def,
            evSpAtk: slot.evs.spa, evSpDef: slot.evs.spd, evSpeed: slot.evs.spe,
            ivHP: slot.ivs.hp, ivAtk: slot.ivs.atk, ivDef: slot.ivs.def,
            ivSpAtk: slot.ivs.spa, ivSpDef: slot.ivs.spd, ivSpeed: slot.ivs.spe,
            moveID1: moveIDs[0], moveID2: moveIDs[1],
            moveID3: moveIDs[2], moveID4: moveIDs[3],
            teraType: slot.source.teraType
        )
    }

    /// Team slot snapshot, for adding an imported team to `SavedTeam`.
    func teamSlot(for slot: ResolvedSlot, spreadName: String) -> TeamSlotInfo? {
        guard let pokemon = slot.pokemon else { return nil }
        let types = [pokemon.type1] + [pokemon.type2].compactMap { $0 }
        let moveSlots = slot.moves.compactMap { move -> TeamMoveInfo? in
            guard let move else { return nil }
            let isAttacking = move.damageClass != "status"
            return TeamMoveInfo(
                moveID: move.id, moveName: move.name, moveType: move.type,
                damageClass: move.damageClass, power: move.power,
                isSTAB: isAttacking && types.contains(move.type)
            )
        }
        return TeamSlotInfo(
            spreadName: spreadName,
            pokemonID: pokemon.id,
            pokemonName: pokemon.name,
            type1: pokemon.type1, type2: pokemon.type2,
            abilityName: slot.ability,
            itemRawValue: slot.itemText,
            championsMode: targetScale == .champions,
            natureID: slot.nature.id,
            level: slot.level,
            evHP: slot.evs.hp, evAtk: slot.evs.atk, evDef: slot.evs.def,
            evSpAtk: slot.evs.spa, evSpDef: slot.evs.spd, evSpeed: slot.evs.spe,
            moveSlots: moveSlots,
            teraType: slot.source.teraType
        )
    }
}

// MARK: - Export

extension ResolvedSlot {

    /// Round-trips back to paste text. Uses the resolved names where they
    /// exist so an import/export cycle normalizes spelling, and falls back to
    /// the original text for anything that didn't resolve.
    ///
    /// `evsAreIn` must be the importer's `targetScale` — that's the scale
    /// `evs` were converted into. Converting for output is
    /// `showdownText(scale:)`'s job, so the two conversions can't stack.
    func exportSet(evsAreIn scale: StatScale) -> ShowdownPasteSet {
        var out = source
        if let pokemon { out.species = pokemon.name }
        if let ability { out.ability = ability }
        if item != .none { out.item = item.rawValue }
        out.nature = nature.name
        out.level = level
        out.evs = evs
        out.ivs = ivs
        out.evScale = scale
        out.moves = zip(moves, source.moves).map { resolved, raw in
            resolved?.name ?? raw
        }
        return out
    }
}
