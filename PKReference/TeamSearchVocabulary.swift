//
//  TeamSearchVocabulary.swift
//  PKReference
//
//  Everything Team Search knows about names: the regulation's species, their
//  forms and Mega Stones, the moves a query can name, and the team styles
//  ("archetypes") it can tag and search for. It's built from the
//  regulation's two bundled JSONs plus team_search_vocab.json, which holds
//  the query words and the style definitions, so adding a style, keyword or
//  nickname is a JSON edit.
//
//  A team member's species has two levels: its base species ("arcanine")
//  and the form words that set it apart ({"hisui"}). A query that doesn't
//  name a form matches every form; one that does matches only that form.
//  Form words are limited to the forms the regulation lists, so Limitless's
//  "floette-eternal" and "floette", the same Pokémon in Champions, share an
//  identity.
//

import Foundation

nonisolated struct TeamArchetype: Hashable, Sendable, Identifiable {
    let id: String
    let label: String
}

nonisolated enum TeamSearchVocabularyError: Error, Equatable {
    case missingResource(String)
}

nonisolated struct TeamSearchVocabulary: Sendable {

    struct Species: Sendable {
        /// `toID` of the name: "arcanine", "kommoo", "mrrime".
        let id: String
        let name: String
        /// The name's words, as the query parser tokenizes them.
        let words: [String]
        /// Form words the regulation lists for it: {"hisui"}, {"female"}.
        let formWords: Set<String>
        let megas: [Mega]
    }

    struct Mega: Sendable, Equatable {
        let stoneID: ShowdownID
        let stoneName: String
        /// "x", "y" or "z" when the species has more than one Mega.
        let variant: String?
        /// The Mega's abilities, e.g. Drought for Charizardite Y.
        let abilities: Set<ShowdownID>
    }

    struct Signals: Sendable {
        let moves: Set<ShowdownID>
        let abilities: Set<ShowdownID>
        let items: Set<ShowdownID>

        func matches(moves: Set<ShowdownID>, abilities: Set<ShowdownID>,
                     items: Set<ShowdownID>) -> Bool {
            !self.moves.isDisjoint(with: moves)
                || !self.abilities.isDisjoint(with: abilities)
                || !self.items.isDisjoint(with: items)
        }
    }

    /// A style: the words that ask for it, and what on a team shows it. A
    /// team has the style when any signal is present and, if `requires` is
    /// set, one of those too (Perish Song plus a trapper).
    struct ArchetypeRule: Sendable {
        let archetype: TeamArchetype
        let keywords: [String]
        /// A few words on what the style is, for Apple Intelligence.
        let hint: String?
        let signals: Signals
        let requires: Signals?
    }

    /// A team member's species identity.
    struct Identity: Hashable, Sendable {
        let speciesID: String
        let formWords: Set<String>

        /// "arcanine", or "arcanine:hisui" with form words sorted.
        var key: String {
            formWords.isEmpty ? speciesID : speciesID + ":" + formWords.sorted().joined(separator: "-")
        }
    }

    let species: [Species]
    let speciesByID: [String: Species]
    /// Moves a query can name, by ID: every multi-word legal move, plus the
    /// single-word ones on the vocabulary's allowlist. Single words are
    /// opt-in so "counter" or "protect" in a description aren't read as moves.
    let queryMoves: [ShowdownID: String]
    let archetypes: [ArchetypeRule]
    let negations: Set<String>
    /// Words that pass a negation on to the next item: "or", "nor".
    let connectors: Set<String>
    /// Words that end a passed-on negation: "no Incineroar, but Garchomp".
    let contrastWords: Set<String>
    /// Words the parser skips. Includes the contrast words.
    let stopWords: Set<String>
    let formNoise: Set<String>
    /// Nickname → species ID.
    let nicknames: [String: String]
    private let megasByStone: [ShowdownID: (speciesID: String, mega: Mega)]
    private let speciesByFirstWord: [String: [Species]]

    // MARK: Loading

    /// The vocabulary for a bundled regulation.
    static func bundled(for regulation: ChampionsRegulation,
                        in bundle: Bundle = .main) throws -> TeamSearchVocabulary {
        func data(_ name: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw TeamSearchVocabularyError.missingResource(name + ".json")
            }
            return try Data(contentsOf: url)
        }
        return try TeamSearchVocabulary(
            regulation: try data(regulation.bundleResourceName),
            learnsets: try data(regulation.learnsetBundleResourceName),
            vocabulary: try data("team_search_vocab"))
    }

    init(regulation: Data, learnsets: Data, vocabulary: Data) throws {
        let decoder = JSONDecoder()
        let reg = try decoder.decode(RegulationFile.self, from: regulation)
        let learn = try decoder.decode(LearnsetsFile.self, from: learnsets)
        let vocab = try decoder.decode(VocabularyFile.self, from: vocabulary)
        let words = LimitlessSpeciesResolver.words
        let noise = Set(vocab.form_noise)

        // Form words, from the learnsets' alternate forms ("Hisuian Form")
        // and the regulation's allowed regional forms ("Paldea-Combat").
        var formWords: [String: Set<String>] = [:]
        for (name, entry) in learn.species {
            for form in entry.alternate_forms ?? [] {
                formWords[name, default: []].formUnion(words(form.name))
            }
        }
        for regional in reg.regional_forms_allowed ?? [] {
            formWords[regional.base, default: []].formUnion(words(regional.form))
        }

        // Megas, from the regulation's stones ("Charizard-Y": "Charizardite Y")
        // and the learnsets' Mega entries for their abilities.
        var megas: [String: [Mega]] = [:]
        for (key, stone) in reg.mega_stones {
            var parts = key.split(separator: "-").map(String.init)
            var variant: String?
            if parts.count > 1, let last = parts.last?.lowercased(), ["x", "y", "z"].contains(last) {
                variant = last
                parts.removeLast()
            }
            let base = parts.joined(separator: "-")
            let keyWords = words(key)
            let abilities = learn.species[base]?.megas?
                .first { words($0.name).filter { $0 != "mega" } == keyWords }?
                .abilities ?? []
            megas[base, default: []].append(Mega(
                stoneID: toID(stone), stoneName: stone, variant: variant,
                abilities: Set(abilities.map(toID))))
        }

        let names = Set(reg.species_whitelist).union(learn.species.keys)
        species = names.sorted().map { name in
            Species(id: toID(name), name: name,
                    words: TeamQueryParser.tokens(name),
                    formWords: (formWords[name] ?? []).subtracting(noise),
                    megas: (megas[name] ?? []).sorted { ($0.variant ?? "") < ($1.variant ?? "") })
        }
        speciesByID = Dictionary(species.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        speciesByFirstWord = Dictionary(grouping: species.filter { !$0.words.isEmpty }) { $0.words[0] }
        megasByStone = Dictionary(
            species.flatMap { s in s.megas.map { ($0.stoneID, (speciesID: s.id, mega: $0)) } },
            uniquingKeysWith: { first, _ in first })

        let singleWordMoves = Set(vocab.single_word_moves.map(toID))
        var queryMoves: [ShowdownID: String] = [:]
        for entry in learn.species.values {
            let pools = [entry.moves] + (entry.alternate_forms ?? []).map { $0.moves ?? [] }
            for move in pools.joined() where queryMoves[toID(move)] == nil {
                if words(move).count > 1 || singleWordMoves.contains(toID(move)) {
                    queryMoves[toID(move)] = move
                }
            }
        }
        self.queryMoves = queryMoves

        archetypes = vocab.archetypes.map { entry in
            ArchetypeRule(
                archetype: TeamArchetype(id: entry.id, label: entry.label),
                keywords: entry.keywords,
                hint: entry.hint,
                signals: entry.signals.resolved,
                requires: entry.requires?.resolved)
        }
        negations = Set(vocab.negations)
        connectors = Set(vocab.connectors)
        contrastWords = Set(vocab.contrast_words)
        stopWords = Set(vocab.stop_words).union(vocab.contrast_words)
        formNoise = noise
        nicknames = vocab.species_nicknames.compactMapValues { target in
            names.contains(target) ? toID(target) : nil
        }
    }

    // MARK: Lookups

    /// A Limitless member's species identity, from its slug ("arcanine-hisui")
    /// when there is one, otherwise its display name ("Hisuian Arcanine").
    /// A species outside the regulation keeps its slug or name as its ID.
    func identity(name: String, slug: String?) -> Identity {
        if let slug, !slug.isEmpty,
           let hit = match(LimitlessSpeciesResolver.words(slug), prefixOnly: true) {
            return hit
        }
        if let hit = match(LimitlessSpeciesResolver.words(name), prefixOnly: false) {
            return hit
        }
        return Identity(speciesID: toID(slug.flatMap { $0.isEmpty ? nil : $0 } ?? name),
                        formWords: [])
    }

    /// A Smogon or Showdown species name as a species term: "Charizard-Mega-Y"
    /// → Mega Charizard Y, "Floette-Mega" → Mega Floette, "Arcanine-Hisui" →
    /// Arcanine (Hisui). nil for a species outside the regulation.
    func term(showdownName name: String) -> SpeciesTerm? {
        var words = LimitlessSpeciesResolver.words(name)
        var mega: SpeciesTerm.Mega?
        if let megaIndex = words.firstIndex(of: "mega") {
            let variant = words.dropFirst(megaIndex + 1).first
            mega = variant.flatMap { ["x", "y", "z"].contains($0) ? .variant($0) : nil } ?? .any
            words = Array(words[..<megaIndex])
        }
        guard let identity = match(words, prefixOnly: true),
              let species = speciesByID[identity.speciesID] else { return nil }
        // A variant letter on a species with a single Mega means that Mega.
        if case .variant(let variant)? = mega, !species.megas.contains(where: { $0.variant == variant }) {
            mega = .any
        }
        return SpeciesTerm(speciesID: species.id, name: species.name,
                           formWords: words.filter(identity.formWords.contains), mega: mega)
    }

    /// A species key, as the PK Reference server sends it ("arcanine:hisui",
    /// `Identity.key`), as a species term: Arcanine (Hisui). nil for a
    /// species outside the regulation, or a form word it doesn't list.
    func species(forKey key: String) -> SpeciesTerm? {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard let first = parts.first, let species = speciesByID[first] else { return nil }
        let formWords = parts.count > 1 ? parts[1].split(separator: "-").map(String.init) : []
        guard formWords.allSatisfy(species.formWords.contains) else { return nil }
        return SpeciesTerm(speciesID: species.id, name: species.name, formWords: formWords)
    }

    /// The Mega a member can become: the held item must be one of its own
    /// species' stones.
    func mega(heldItem: String?, speciesID: String) -> Mega? {
        guard let heldItem, let hit = megasByStone[toID(heldItem)],
              hit.speciesID == speciesID else { return nil }
        return hit.mega
    }

    /// The longest species whose words appear in `words`: at the start for a
    /// slug, anywhere for a display name. The leftover words that are forms
    /// the regulation lists become the identity's form words.
    private func match(_ words: [String], prefixOnly: Bool) -> Identity? {
        var best: (species: Species, range: Range<Int>)?
        for start in words.indices {
            if prefixOnly && start > 0 { break }
            for candidate in speciesByFirstWord[words[start]] ?? [] {
                let end = start + candidate.words.count
                guard end <= words.count, Array(words[start..<end]) == candidate.words
                else { continue }
                if best == nil || candidate.words.count > best!.species.words.count {
                    best = (candidate, start..<end)
                }
            }
        }
        guard let best else { return nil }
        let rest = words.indices.filter { !best.range.contains($0) }.map { words[$0] }
        return Identity(speciesID: best.species.id,
                        formWords: Set(rest).intersection(best.species.formWords))
    }

    // MARK: Files

    private struct RegulationFile: Decodable {
        let species_whitelist: [String]
        let regional_forms_allowed: [RegionalForm]?
        let mega_stones: [String: String]

        struct RegionalForm: Decodable {
            let base: String
            let form: String
        }
    }

    private struct LearnsetsFile: Decodable {
        let species: [String: Entry]

        struct Entry: Decodable {
            let moves: [String]
            let megas: [MegaEntry]?
            let alternate_forms: [FormEntry]?
        }

        struct MegaEntry: Decodable {
            let name: String
            let abilities: [String]?
        }

        struct FormEntry: Decodable {
            let name: String
            let moves: [String]?
        }
    }

    private struct VocabularyFile: Decodable {
        let archetypes: [ArchetypeEntry]
        let negations: [String]
        let connectors: [String]
        let contrast_words: [String]
        let stop_words: [String]
        let form_noise: [String]
        let species_nicknames: [String: String]
        let single_word_moves: [String]

        struct ArchetypeEntry: Decodable {
            let id: String
            let label: String
            let keywords: [String]
            let hint: String?
            let signals: SignalsEntry
            let requires: SignalsEntry?
        }

        struct SignalsEntry: Decodable {
            let moves: [String]?
            let abilities: [String]?
            let items: [String]?

            var resolved: Signals {
                Signals(moves: Set((moves ?? []).map(toID)),
                        abilities: Set((abilities ?? []).map(toID)),
                        items: Set((items ?? []).map(toID)))
            }
        }
    }
}
