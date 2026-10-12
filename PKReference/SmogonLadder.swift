//
//  SmogonLadder.swift
//  PKReference
//
//  Smogon's monthly ladder stats, cut down on the device to the record the
//  PK Reference server serves (MetaAPI.LadderStats), for when there's no
//  server: which ladder is being asked for, which of Smogon's formats that
//  is, and the reduction itself.
//
//  `SmogonLadder.reduce` is the backend's LadderReducer, rule for rule
//  (BackendIntegration-PHASE5.md §3). Both must produce
//  backend/src/test/resources/golden/ladder-fixture.json from the fixture
//  beside it, so a change here is a change there, a new `reduction`, and the
//  golden file recorded again.
//

import Foundation

// MARK: - Which ladder

/// One ladder: a regulation's doubles or singles, best of one or three, as
/// players at or above a rating play it.
nonisolated struct LadderRequest: Hashable, Sendable {
    enum Mode: String, Sendable, CaseIterable {
        case doubles
        /// Battle Stadium Singles.
        case singles
    }

    /// Smogon's four cutoffs; 0 is every player.
    static let ratings = [0, 1500, 1630, 1760]

    var regulation: ChampionsRegulation
    var mode: Mode = .doubles
    /// 1 or 3. Smogon has best of three for doubles only.
    var bestOf = 1
    var rating = 1760

    /// What Team Search reads: doubles, best of one, weighted toward strong
    /// players.
    static func teamSearch(_ regulation: ChampionsRegulation) -> LadderRequest {
        LadderRequest(regulation: regulation)
    }
}

/// One of Smogon's Champions ladder formats, read from its ID:
/// "gen9championsvgc2026regmc" is M-C doubles, with "bo3" on the end best of
/// three; "gen9championsbssregmc" is M-C singles. The doubles ID has the
/// year in it, so formats are found by this pattern in a listing, never
/// built from a regulation. As the backend's LadderFormat.
nonisolated struct SmogonLadderFormat: Hashable, Sendable {
    let id: String
    let regulation: ChampionsRegulation
    let mode: LadderRequest.Mode
    let bestOf: Int

    /// nil when the ID isn't a Champions doubles or singles ladder of a
    /// regulation the app knows.
    init?(id: String) {
        guard let match = id.wholeMatch(of: /gen\d+champions(vgc\d{4}|bss)reg([a-z0-9]+?)(bo3)?/),
              // Smogon writes the regulation without its hyphen: "mc".
              let regulation = ChampionsRegulation.allCases.first(where: {
                  $0.rawValue.replacingOccurrences(of: "-", with: "") == match.2
              }) else { return nil }
        self.id = id
        self.regulation = regulation
        mode = match.1 == "bss" ? .singles : .doubles
        bestOf = match.3 == nil ? 1 : 3
    }

    /// A chaos file's name, "gen9championsvgc2026regmc-1760.json", as its
    /// format and rating.
    static func file(_ name: String) -> (format: SmogonLadderFormat, rating: Int)? {
        guard let match = name.wholeMatch(of: /(.+)-(\d+)\.json/), let rating = Int(match.2),
              let format = SmogonLadderFormat(id: String(match.1)) else { return nil }
        return (format, rating)
    }

    func matches(_ request: LadderRequest) -> Bool {
        mode == request.mode && bestOf == request.bestOf
    }
}

// MARK: - Reducing

nonisolated enum SmogonLadder {
    /// The version of the rule, as the backend's LadderReducer.REDUCTION.
    static let reduction = 1

    static let abilityLimit = 6
    static let itemLimit = 12
    static let moveLimit = 24
    static let natureLimit = 6
    static let spreadLimit = 10
    static let teammateLimit = 24
    /// Abilities, items, moves and natures on under 0.5% of the Pokémon's
    /// teams are left out.
    static let floor = 0.005

    private struct Count {
        let id: String
        let count: Double
    }

    /// Cuts a chaos file, and its leads file, down to the record the app
    /// shows. `leads` is the leads file's text, or nil. `vocabulary` and
    /// `names` are the format's regulation's; without them, Pokémon have no
    /// keys and IDs stay as they are.
    static func reduce(chaos: Data, leads: String?, format: SmogonLadderFormat, month: String, rating: Int,
                       vocabulary: TeamSearchVocabulary?, names: MetaNames?) throws -> MetaAPI.LadderStats {
        guard let root = try? JSONSerialization.jsonObject(with: chaos) as? [String: Any],
              let data = root["data"] as? [String: Any] else {
            throw SmogonUsageError.unreadableStats
        }
        let battles = number((root["info"] as? [String: Any])?["number of battles"]).map { Int($0) } ?? 0
        let leadShares = leadShares(leads)

        var pokemon: [MetaAPI.LadderPokemon] = []
        for (name, value) in data {
            guard let entry = value as? [String: Any],
                  let reduced = Self.pokemon(name, entry, vocabulary: vocabulary, names: names,
                                             leadShare: leadShares[name]) else { continue }
            pokemon.append(reduced)
        }
        pokemon.sort { $0.usage != $1.usage ? $0.usage > $1.usage : bytesPrecede($0.name, $1.name) }
        return MetaAPI.LadderStats(reduction: reduction, format: format.id,
                                   regulation: format.regulation.limitlessFormat, mode: format.mode.rawValue,
                                   bestOf: format.bestOf, month: month, rating: rating, battles: battles,
                                   pokemon: pokemon)
    }

    /// One Pokémon's entry, or nil when it has no usage or no weight to
    /// take shares of.
    private static func pokemon(_ name: String, _ entry: [String: Any], vocabulary: TeamSearchVocabulary?,
                                names: MetaNames?, leadShare: Double?) -> MetaAPI.LadderPokemon? {
        let usage = roundUsage(number(entry["usage"]) ?? 0)
        let abilities = counts(entry["Abilities"])
        // The Pokémon's own weight: what Smogon's moveset files divide by.
        let weight = abilities.reduce(0) { $0 + $1.count }
        guard usage > 0, weight > 0 else { return nil }

        let items = counts(entry["Items"])
        let spreads = counts(entry["Spreads"])

        var key: String?
        var megaStone: String?
        if let vocabulary, let term = vocabulary.term(showdownName: name) {
            key = TeamSearchVocabulary.Identity(speciesID: term.speciesID, formWords: Set(term.formWords)).key
            if term.mega != nil {
                // A Mega's entry is the Pokémon holding its stone: the stone
                // is its commonest item.
                for item in ranked(items) {
                    if let mega = vocabulary.mega(heldItem: item.id, speciesID: term.speciesID) {
                        megaStone = names?.itemName(id: mega.stoneID) ?? mega.stoneID
                        break
                    }
                }
            }
        }

        return MetaAPI.LadderPokemon(
            name: name, key: key, megaStone: megaStone, usage: usage, leadShare: leadShare,
            abilities: shares(abilities, weight, abilityLimit, floor) { names?.abilityName(id: $0) ?? $0 },
            items: shares(items, weight, itemLimit, floor) { id in
                names?.itemName(id: id) ?? (id == "nothing" ? MetaNames.noItem : id)
            },
            // An empty move slot is "".
            moves: shares(counts(entry["Moves"]), weight, moveLimit, floor) { id in
                id.isEmpty ? nil : names?.moveName(id: id) ?? id
            },
            natures: shares(natures(spreads), weight, natureLimit, floor) { $0 },
            spreads: shares(spreads, weight, spreadLimit, 0) { $0 },
            teammates: shares(counts(entry["Teammates"]), weight, teammateLimit, 0) { $0 })
    }

    /// An object of counts, in the order of its keys.
    private static func counts(_ object: Any?) -> [Count] {
        guard let object = object as? [String: Any] else { return [] }
        return object.compactMap { key, value in number(value).map { Count(id: key, count: $0) } }
            .sorted { bytesPrecede($0.id, $1.id) }
    }

    /// Biggest first; equal counts by key.
    private static func ranked(_ counts: [Count]) -> [Count] {
        counts.sorted { $0.count != $1.count ? $0.count > $1.count : bytesPrecede($0.id, $1.id) }
    }

    /// The `limit` biggest as shares of `weight`, leaving out those under
    /// `floor`, those of nothing, and those `name` has no name for.
    private static func shares(_ counts: [Count], _ weight: Double, _ limit: Int, _ floor: Double,
                               name: (String) -> String?) -> [MetaAPI.LadderShare] {
        var shares: [MetaAPI.LadderShare] = []
        for count in ranked(counts) {
            if shares.count == limit { break }
            let share = count.count / weight
            guard share > 0, share >= floor, let value = name(count.id) else { continue }
            shares.append(MetaAPI.LadderShare(value: value, share: round(share)))
        }
        return shares
    }

    /// The spreads' counts added up by nature: a spread is
    /// "Adamant:2/32/0/0/0/32".
    private static func natures(_ spreads: [Count]) -> [Count] {
        var byNature: [String: Double] = [:]
        // In the spreads' order, so each nature's sum is taken the same way
        // everywhere.
        for spread in spreads {
            guard let colon = spread.id.firstIndex(of: ":"), colon != spread.id.startIndex else { continue }
            byNature[String(spread.id[..<colon]), default: 0] += spread.count
        }
        return byNature.map { Count(id: $0.key, count: $0.value) }.sorted { bytesPrecede($0.id, $1.id) }
    }

    /// Each Pokémon's share of all leads, from the leads file's table:
    /// `| 1    | Sneasler           |  6.59479% | 204684 |  6.271% |`.
    static func leadShares(_ leads: String?) -> [String: Double] {
        guard let leads else { return [:] }
        var shares: [String: Double] = [:]
        // By newline of any kind: "\r\n" is one Character, which "\n" alone doesn't match.
        for line in leads.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard cells.count >= 4, !cells[1].isEmpty, cells[1].utf8.allSatisfy({ (48...57).contains($0) }),
                  cells[3].hasSuffix("%"), let percent = Double(cells[3].dropLast()) else { continue }
            shares[cells[2]] = roundUsage(percent / 100)
        }
        return shares
    }

    /// To five places, half to even: Java's Math.rint.
    static func round(_ share: Double) -> Double {
        (share * 100_000).rounded(.toNearestOrEven) / 100_000
    }

    /// Usage and lead shares, which Smogon publishes to seven places: to
    /// nine, half to even. Smogon writes some to more digits than a double
    /// holds, and JSONSerialization reads those a few units in the last
    /// place away from where the backend's parser does, so nothing goes out
    /// unrounded.
    static func roundUsage(_ usage: Double) -> Double {
        (usage * 1_000_000_000).rounded(.toNearestOrEven) / 1_000_000_000
    }

    /// Strings by their UTF-8 bytes: the same order in Swift and in Java,
    /// whatever the letters.
    static func bytesPrecede(_ a: String, _ b: String) -> Bool {
        a.utf8.lexicographicallyPrecedes(b.utf8)
    }

    /// A JSON number; nil for anything else, a true or false included.
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }
}
