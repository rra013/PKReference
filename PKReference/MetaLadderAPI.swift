//
//  MetaLadderAPI.swift
//  PKReference
//
//  The ladder, as the app reads it: one month of Smogon's usage stats for a
//  format at a rating, reduced to what the app shows
//  (BackendIntegration-PHASE5.md §3). The PK Reference server serves it at
//  /v1/ladder (the backend's Ladder.java and LadderResponses.java), and
//  SmogonLadder.reduce makes the same record on the device from Smogon's own
//  files, so everything past this point reads one shape whatever the source.
//
//  Shares are 0 to 1. What only the server can add (the change since last
//  month, usage at the other ratings) is nil or empty from the device.
//

import Foundation

nonisolated extension MetaAPI {

    /// A value, and the share of the Pokémon's teams with it.
    struct LadderShare: Codable, Sendable, Equatable {
        let value: String
        let share: Double
    }

    struct RatingUsage: Codable, Sendable, Equatable {
        let rating: Int
        let usage: Double
    }

    struct LadderPokemon: Codable, Sendable, Equatable {
        /// Smogon's name, unique in the record: "Salamence-Mega". A Pokémon
        /// holding its Mega Stone is its own entry.
        let name: String
        /// The app's species key, "salamence"; nil when the regulation's
        /// data doesn't know the Pokémon. Two entries can share one
        /// ("Basculegion" and "Basculegion-F").
        let key: String?
        /// "Salamencite" when the entry is a Mega.
        let megaStone: String?
        /// Share of teams with it on the team of six, weighted for the rating.
        let usage: Double
        /// Usage less the month before's; nil when that month isn't known.
        let trend: Double?
        /// Its usage at each rating the server has for the month.
        let usageByRating: [RatingUsage]
        /// Its share of all leads; nil when Smogon's leads file doesn't list it.
        let leadShare: Double?
        let abilities: [LadderShare]
        let items: [LadderShare]
        /// Shares add to 4: each team has four moves.
        let moves: [LadderShare]
        /// The spreads' shares added up by nature.
        let natures: [LadderShare]
        /// "Adamant:2/32/0/0/0/32": the nature, then stat points for
        /// HP/Atk/Def/SpA/SpD/Spe.
        let spreads: [LadderShare]
        /// Other entries of the record, by their names.
        let teammates: [LadderShare]

        private enum CodingKeys: String, CodingKey {
            case name, key, megaStone, usage, trend, usageByRating, leadShare, abilities, items, moves, natures,
                 spreads, teammates
        }

        init(name: String, key: String?, megaStone: String?, usage: Double, trend: Double? = nil,
             usageByRating: [RatingUsage] = [], leadShare: Double?, abilities: [LadderShare] = [],
             items: [LadderShare] = [], moves: [LadderShare] = [], natures: [LadderShare] = [],
             spreads: [LadderShare] = [], teammates: [LadderShare] = []) {
            self.name = name
            self.key = key
            self.megaStone = megaStone
            self.usage = usage
            self.trend = trend
            self.usageByRating = usageByRating
            self.leadShare = leadShare
            self.abilities = abilities
            self.items = items
            self.moves = moves
            self.natures = natures
            self.spreads = spreads
            self.teammates = teammates
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            key = try c.decodeIfPresent(String.self, forKey: .key)
            megaStone = try c.decodeIfPresent(String.self, forKey: .megaStone)
            usage = try c.decode(Double.self, forKey: .usage)
            trend = try c.decodeIfPresent(Double.self, forKey: .trend)
            usageByRating = try c.decodeIfPresent([RatingUsage].self, forKey: .usageByRating) ?? []
            leadShare = try c.decodeIfPresent(Double.self, forKey: .leadShare)
            abilities = try c.decodeIfPresent([LadderShare].self, forKey: .abilities) ?? []
            items = try c.decodeIfPresent([LadderShare].self, forKey: .items) ?? []
            moves = try c.decodeIfPresent([LadderShare].self, forKey: .moves) ?? []
            natures = try c.decodeIfPresent([LadderShare].self, forKey: .natures) ?? []
            spreads = try c.decodeIfPresent([LadderShare].self, forKey: .spreads) ?? []
            teammates = try c.decodeIfPresent([LadderShare].self, forKey: .teammates) ?? []
        }
    }

    /// GET /v1/ladder/{format}, or the device's own reduction.
    struct LadderStats: Codable, Sendable, Equatable {
        /// The version of the rule that reduced Smogon's file.
        let reduction: Int
        /// Smogon's format ID: "gen9championsvgc2026regmc".
        let format: String
        /// The regulation, as Limitless names it: "M-C".
        let regulation: String
        /// "doubles" or "singles".
        let mode: String
        let bestOf: Int
        /// "2026-09".
        let month: String
        /// Smogon's rating cutoff: 0 is every player.
        let rating: Int
        let battles: Int
        /// When the server fetched Smogon's file.
        let fetchedAt: Date?
        /// The month trends are measured from; nil when it isn't known.
        let previousMonth: String?
        /// The ratings the server has for the month.
        let ratings: [Int]
        /// Most used first.
        let pokemon: [LadderPokemon]

        private enum CodingKeys: String, CodingKey {
            case reduction, format, regulation, mode, bestOf, month, rating, battles, fetchedAt, previousMonth,
                 ratings, pokemon
        }

        init(reduction: Int, format: String, regulation: String, mode: String, bestOf: Int, month: String,
             rating: Int, battles: Int, fetchedAt: Date? = nil, previousMonth: String? = nil, ratings: [Int] = [],
             pokemon: [LadderPokemon]) {
            self.reduction = reduction
            self.format = format
            self.regulation = regulation
            self.mode = mode
            self.bestOf = bestOf
            self.month = month
            self.rating = rating
            self.battles = battles
            self.fetchedAt = fetchedAt
            self.previousMonth = previousMonth
            self.ratings = ratings
            self.pokemon = pokemon
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            reduction = try c.decodeIfPresent(Int.self, forKey: .reduction) ?? 0
            format = try c.decode(String.self, forKey: .format)
            regulation = try c.decode(String.self, forKey: .regulation)
            mode = try c.decode(String.self, forKey: .mode)
            bestOf = try c.decode(Int.self, forKey: .bestOf)
            month = try c.decode(String.self, forKey: .month)
            rating = try c.decode(Int.self, forKey: .rating)
            battles = try c.decodeIfPresent(Int.self, forKey: .battles) ?? 0
            fetchedAt = try c.decodeIfPresent(Date.self, forKey: .fetchedAt)
            previousMonth = try c.decodeIfPresent(String.self, forKey: .previousMonth)
            ratings = try c.decodeIfPresent([Int].self, forKey: .ratings) ?? []
            pokemon = try c.decode([LadderPokemon].self, forKey: .pokemon)
        }
    }

    /// One stored month of a format at a rating.
    struct LadderEntry: Decodable, Sendable, Equatable {
        let format: String
        let regulation: String
        let mode: String
        let bestOf: Int
        let month: String
        let rating: Int
        let battles: Int
        let fetchedAt: Date?
    }

    /// GET /v1/ladder: what the server has.
    struct LadderIndex: Decodable, Sendable {
        let stats: [LadderEntry]
    }

    static let ladder = Endpoint<LadderIndex>(path: "v1/ladder")

    static func ladder(format: String, rating: Int, month: String) -> Endpoint<LadderStats> {
        Endpoint(path: "v1/ladder/\(format)", query: [URLQueryItem(name: "rating", value: String(rating)),
                                                      URLQueryItem(name: "month", value: month)])
    }
}
