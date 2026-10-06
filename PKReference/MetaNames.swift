//
//  MetaNames.swift
//  PKReference
//
//  Canonical spellings for the names players type into Limitless decklists
//  (items, abilities, moves, natures), so "MIRACLE SEED", "Miracle seed" and
//  "Focus Slash" count as Miracle Seed and Focus Sash. A port of the
//  backend's NameStandardizer and NameDictionary, so the Meta tab's numbers
//  worked out on the device (MetaDeviceInsights) match the server's.
//
//  The names come from the bundled regulation files and their learnsets,
//  and showdown-champions-data.json, as the backend's do. The backend also
//  reads a snapshot of Serebii's Champions item page, which the app doesn't
//  bundle, so an item in no regulation's list can spell differently here.
//  A name that matches nothing is kept, title-cased.
//

import Foundation
import Synchronization

nonisolated struct MetaNames: Sendable {
    /// What a blank or "none" item becomes, as on the server.
    static let noItem = "No Item"

    static let natureNames = [
        "Hardy", "Lonely", "Brave", "Adamant", "Naughty", "Bold", "Docile", "Relaxed", "Impish", "Lax",
        "Timid", "Hasty", "Serious", "Jolly", "Naive", "Modest", "Mild", "Quiet", "Bashful", "Rash",
        "Calm", "Gentle", "Sassy", "Careful", "Quirky",
    ]

    private let items: Dictionary
    private let abilities: Dictionary
    private let moves: Dictionary
    private let allItems: Dictionary
    private let allAbilities: Dictionary
    private let allMoves: Dictionary
    private let natures = Dictionary(natureNames)

    /// The names for `regulation`, with every bundled regulation and
    /// Showdown's data to fall back on. Loaded once per regulation.
    static func bundled(for regulation: ChampionsRegulation, in bundle: Bundle = .main) throws -> MetaNames {
        if let cached = cache.withLock({ $0[regulation] }) { return cached }
        let names = try MetaNames(regulation: regulation, bundle: bundle)
        cache.withLock { $0[regulation] = names }
        return names
    }

    private static let cache = Mutex<[ChampionsRegulation: MetaNames]>([:])

    private init(regulation: ChampionsRegulation, bundle: Bundle) throws {
        func json(_ name: String) throws -> Any {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw TeamSearchVocabularyError.missingResource(name + ".json")
            }
            return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        }
        func strings(_ value: Any?) -> [String] {
            switch value {
            case let list as [String]: list
            case let map as [String: String]: map.keys.sorted().compactMap { map[$0] }
            case let list as [Any]: list.compactMap { $0 as? String }
            default: []
            }
        }

        // Showdown's data: every move, and every species' abilities.
        let showdown = try json("showdown-champions-data") as? [String: Any] ?? [:]
        var unionItems: [String] = []
        var unionAbilities: [String] = []
        var unionMoves = ((showdown["moves"] as? [String: Any])?.keys.sorted() ?? []).filter { !$0.hasPrefix("(") }
        for (_, species) in ((showdown["species"] as? [String: Any]) ?? [:]).sorted(by: { $0.key < $1.key }) {
            unionAbilities += strings((species as? [String: Any])?["abilities"])
        }

        var own: (items: [String], abilities: [String], moves: [String]) = ([], [], [])
        for each in ChampionsRegulation.allCases {
            let file = try json(each.bundleResourceName) as? [String: Any] ?? [:]
            let items = strings(file["items_whitelist"]) + strings(file["berries_whitelist"])
                + strings(file["mega_stones"])
            var abilities: [String] = []
            var moves: [String] = []
            let learnsets = try json(each.learnsetBundleResourceName) as? [String: Any] ?? [:]
            for (_, species) in ((learnsets["species"] as? [String: Any]) ?? [:]).sorted(by: { $0.key < $1.key }) {
                let entry = species as? [String: Any]
                abilities += strings(entry?["abilities"])
                moves += strings(entry?["moves"])
            }
            unionItems += items
            unionAbilities += abilities
            unionMoves += moves
            if each == regulation { own = (items, abilities, moves) }
        }
        items = Dictionary(own.items)
        abilities = Dictionary(own.abilities)
        moves = Dictionary(own.moves)
        allItems = Dictionary(unionItems)
        allAbilities = Dictionary(unionAbilities)
        allMoves = Dictionary(unionMoves)
    }

    /// Blank and "none"-style values become "No Item"; nil stays nil (no
    /// item given).
    func item(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let key = Self.key(raw)
        if key.isEmpty || ["none", "noitem", "noitems"].contains(key) { return Self.noItem }
        return items.resolve(raw, fallback: allItems)
    }

    func ability(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return abilities.resolve(raw, fallback: allAbilities)
    }

    func move(_ raw: String) -> String? {
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return moves.resolve(raw, fallback: allMoves)
    }

    func nature(_ raw: String?) -> String? {
        raw.map { natures.resolve($0, fallback: nil) }
    }

    // MARK: The dictionary

    /// Lowercase ASCII letters and digits only: "Fake-out", "FAKE OUT" and
    /// "Fake Out" all become "fakeout". As the server's, which drops "é".
    static func key(_ raw: String) -> String {
        String(String.UnicodeScalarView(raw.lowercased().unicodeScalars.filter {
            ("a"..."z").contains($0) || ("0"..."9").contains($0)
        }))
    }

    /// Canonical spellings for one kind of name, with exact and
    /// typo-tolerant lookup.
    struct Dictionary: Sendable {
        /// Normalized key → the first spelling given for it.
        private let byKey: [String: String]
        /// The keys, for the near-miss search.
        private let keys: [String]

        init(_ names: [String]) {
            var byKey: [String: String] = [:]
            var keys: [String] = []
            for name in names {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = MetaNames.key(trimmed)
                if byKey[key] == nil {
                    byKey[key] = trimmed
                    keys.append(key)
                }
            }
            self.byKey = byKey
            self.keys = keys
        }

        /// An exact match here, then in `fallback`, then a single near miss
        /// here, then in `fallback`; otherwise the name title-cased.
        func resolve(_ raw: String, fallback: Dictionary?) -> String {
            let key = MetaNames.key(raw)
            return byKey[key] ?? fallback?.byKey[key] ?? nearest(key) ?? fallback?.nearest(key) ?? Self.titleCase(raw)
        }

        /// The one candidate within a small edit distance that shares the
        /// first letter. A tie gives nil rather than a guess; names under 5
        /// letters need an exact match.
        private func nearest(_ key: String) -> String? {
            let k = Array(key.utf8)
            let limit = k.count < 5 ? 0 : k.count < 10 ? 1 : 2
            guard limit > 0 else { return nil }
            var best: String?
            var bestDistance = limit + 1
            var tie = false
            for candidate in keys {
                let c = Array(candidate.utf8)
                guard let first = c.first, first == k[0], abs(c.count - k.count) <= limit else { continue }
                let d = Self.distance(k, c, cap: limit)
                guard d <= limit else { continue }
                let value = byKey[candidate]!
                if d < bestDistance {
                    best = value
                    bestDistance = d
                    tie = false
                } else if d == bestDistance && value != best {
                    tie = true
                }
            }
            return tie ? nil : best
        }

        /// Optimal string alignment distance (edits, plus swapping two
        /// neighbouring letters), stopping once it passes `cap`.
        static func distance(_ a: [UInt8], _ b: [UInt8], cap: Int) -> Int {
            var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
            for i in 0...a.count { d[i][0] = i }
            for j in 0...b.count { d[0][j] = j }
            guard !a.isEmpty, !b.isEmpty else { return d[a.count][b.count] }
            for i in 1...a.count {
                var rowMin = Int.max
                for j in 1...b.count {
                    let cost = a[i - 1] == b[j - 1] ? 0 : 1
                    d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                    if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                        d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                    }
                    rowMin = min(rowMin, d[i][j])
                }
                if rowMin > cap { return cap + 1 }
            }
            return d[a.count][b.count]
        }

        /// "life  ORB" → "Life Orb"; a hyphen starts a word too
        /// ("never-melt ice" → "Never-Melt Ice").
        static func titleCase(_ raw: String) -> String {
            var out = ""
            var upper = true
            for c in raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                if c.isWhitespace {
                    if let last = out.last, last != " " { out.append(" ") }
                    upper = true
                    continue
                }
                out += upper ? c.uppercased() : String(c)
                upper = c == "-"
            }
            return out
        }
    }
}
