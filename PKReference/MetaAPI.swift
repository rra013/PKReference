//
//  MetaAPI.swift
//  PKReference
//
//  The PK Reference server's insights at /v1, as the app reads them: the
//  answers' shapes (mirroring the backend's MetaResponses.java) and the
//  requests that ask for them. MetaCache.swift keeps the answers and decides
//  when to ask again (BackendIntegration-PHASE4.md §4).
//
//  Shares are 0 to 1. Fields the app can do without are optional, or empty
//  when missing, so a newer server's additions and removals don't stop an
//  older app reading it.
//

import Foundation

nonisolated enum MetaAPI {

    /// The time an answer covers.
    enum Window: String, CaseIterable, Sendable {
        case days14 = "14d"
        case days30 = "30d"
        case regulation
    }

    /// What the numbers rest on.
    struct Sample: Decodable, Sendable, Equatable {
        let events: Int
        let teams: Int
        /// Teams that played in a top cut (a bracket phase).
        let topCutTeams: Int
    }

    // MARK: /v1/formats

    struct Formats: Decodable, Sendable {
        let generatedAt: Date?
        let formats: [Format]
    }

    struct Format: Decodable, Sendable, Equatable {
        /// Limitless's format ID: "M-C".
        let format: String
        let events: Int
        let teams: Int
        let firstEvent: Date?
        let lastEvent: Date?
        /// When the server last fetched an event of the format.
        let lastFetched: Date?
    }

    // MARK: /v1/formats/{f}/pokemon

    /// Match results for teams with a Pokémon, mirror matches left out. The
    /// rate and its 95% range are nil under 30 matches.
    struct WinRecord: Decodable, Sendable, Equatable {
        let wins: Int
        let losses: Int
        let ties: Int
        let matches: Int
        let winRate: Double?
        let winRateLow: Double?
        let winRateHigh: Double?
    }

    struct PokemonUsage: Decodable, Sendable, Equatable {
        /// The app's species key: "rillaboom", "arcanine:hisui".
        let key: String
        let teams: Int
        let usage: Double
        let topCutTeams: Int
        /// nil when the window had no top cut.
        let topCutUsage: Double?
        /// Usage in the last 14 days less the 14 before; nil when either has
        /// under 50 teams.
        let trend: Double?
        let record: WinRecord?
    }

    struct PokemonList: Decodable, Sendable {
        let format: String
        let window: String
        let from: Date?
        let to: Date?
        let generatedAt: Date?
        let sample: Sample
        let pokemon: [PokemonUsage]
    }

    // MARK: /v1/formats/{f}/pokemon/{key}

    /// A value, and how many had it.
    struct Share: Decodable, Sendable, Equatable {
        let value: String
        let count: Int
        let share: Double
    }

    /// A whole set, counted as one.
    struct PokemonSet: Decodable, Sendable, Equatable {
        let item: String?
        let ability: String?
        let nature: String?
        let moves: [String]
        let count: Int
        let share: Double
    }

    /// Usage in one week (Monday to Sunday, UTC) of the window.
    struct WeekUsage: Decodable, Sendable, Equatable {
        /// "2026-09-28", the week's Monday.
        let week: String
        let teams: Int
        let withPokemon: Int
        let usage: Double
    }

    struct PokemonDetail: Decodable, Sendable {
        let format: String
        let key: String
        let window: String
        let generatedAt: Date?
        let sample: Sample
        let usage: PokemonUsage?
        let items: [Share]
        let abilities: [Share]
        let natures: [Share]
        let moves: [Share]
        let megaStones: [Share]
        let teammates: [Share]
        let sets: [PokemonSet]
        let weekly: [WeekUsage]

        private enum CodingKeys: String, CodingKey {
            case format, key, window, generatedAt, sample, usage, items, abilities, natures, moves,
                 megaStones, teammates, sets, weekly
        }

        init(format: String, key: String, window: String, generatedAt: Date?, sample: Sample,
             usage: PokemonUsage?, items: [Share], abilities: [Share], natures: [Share], moves: [Share],
             megaStones: [Share], teammates: [Share], sets: [PokemonSet], weekly: [WeekUsage]) {
            self.format = format
            self.key = key
            self.window = window
            self.generatedAt = generatedAt
            self.sample = sample
            self.usage = usage
            self.items = items
            self.abilities = abilities
            self.natures = natures
            self.moves = moves
            self.megaStones = megaStones
            self.teammates = teammates
            self.sets = sets
            self.weekly = weekly
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            format = try c.decode(String.self, forKey: .format)
            key = try c.decode(String.self, forKey: .key)
            window = try c.decode(String.self, forKey: .window)
            generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt)
            sample = try c.decode(Sample.self, forKey: .sample)
            usage = try c.decodeIfPresent(PokemonUsage.self, forKey: .usage)
            items = try c.decodeIfPresent([Share].self, forKey: .items) ?? []
            abilities = try c.decodeIfPresent([Share].self, forKey: .abilities) ?? []
            natures = try c.decodeIfPresent([Share].self, forKey: .natures) ?? []
            moves = try c.decodeIfPresent([Share].self, forKey: .moves) ?? []
            megaStones = try c.decodeIfPresent([Share].self, forKey: .megaStones) ?? []
            teammates = try c.decodeIfPresent([Share].self, forKey: .teammates) ?? []
            sets = try c.decodeIfPresent([PokemonSet].self, forKey: .sets) ?? []
            weekly = try c.decodeIfPresent([WeekUsage].self, forKey: .weekly) ?? []
        }
    }

    // MARK: /v1/formats/{f}/cores

    /// Pokémon on teams together.
    struct Core: Decodable, Sendable, Equatable {
        /// Species keys, sorted.
        let members: [String]
        let teams: Int
        let share: Double
        /// `share` over what chance would give: above 1, they're chosen together.
        let lift: Double
    }

    struct Cores: Decodable, Sendable {
        let format: String
        let window: String
        let generatedAt: Date?
        let sample: Sample
        let pairs: [Core]
        let trios: [Core]
    }

    // MARK: /v1/formats/{f}/archetypes

    struct Matchup: Decodable, Sendable, Equatable {
        /// The other archetype's id.
        let against: String
        let record: WinRecord
    }

    /// Teams built around a core of four.
    struct Archetype: Decodable, Sendable, Equatable {
        /// The core's species keys, sorted, joined with "+". Unique.
        let id: String
        /// Its two most-used members, joined with "+", and more of its core
        /// when an archetype with more teams has that name. Unique.
        let name: String
        /// The core, most used first.
        let core: [String]
        let teams: Int
        let usage: Double
        let topCutTeams: Int
        let topCutUsage: Double?
        let record: WinRecord?
        let matchups: [Matchup]

        private enum CodingKeys: String, CodingKey {
            case id, name, core, teams, usage, topCutTeams, topCutUsage, record, matchups
        }

        init(id: String, name: String, core: [String], teams: Int, usage: Double, topCutTeams: Int,
             topCutUsage: Double?, record: WinRecord?, matchups: [Matchup]) {
            self.id = id
            self.name = name
            self.core = core
            self.teams = teams
            self.usage = usage
            self.topCutTeams = topCutTeams
            self.topCutUsage = topCutUsage
            self.record = record
            self.matchups = matchups
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            core = try c.decode([String].self, forKey: .core)
            teams = try c.decode(Int.self, forKey: .teams)
            usage = try c.decode(Double.self, forKey: .usage)
            topCutTeams = try c.decode(Int.self, forKey: .topCutTeams)
            topCutUsage = try c.decodeIfPresent(Double.self, forKey: .topCutUsage)
            record = try c.decodeIfPresent(WinRecord.self, forKey: .record)
            matchups = try c.decodeIfPresent([Matchup].self, forKey: .matchups) ?? []
        }
    }

    struct Archetypes: Decodable, Sendable {
        let format: String
        let window: String
        let generatedAt: Date?
        let sample: Sample
        /// Teams in no archetype.
        let other: Int
        let archetypes: [Archetype]
    }

    // MARK: /v1/formats/{f}/archetypes/{id}

    /// A Pokémon on an example team, its names standardized.
    struct ExampleMember: Decodable, Sendable, Equatable {
        /// nil when the server has no key for it yet.
        let key: String?
        /// The name Limitless gave.
        let name: String
        let item: String?
        let ability: String?
        let nature: String?
        let moves: [String]
    }

    /// One team in an archetype, with where it placed.
    struct ExampleTeam: Decodable, Sendable, Equatable {
        let eventId: String
        let eventName: String?
        let eventDate: Date?
        /// The event's size.
        let players: Int
        /// The player's name, as Limitless shows it.
        let player: String?
        let placing: Int?
        let wins: Int
        let losses: Int
        let ties: Int
        let members: [ExampleMember]
    }

    struct ArchetypeDetail: Decodable, Sendable {
        let format: String
        let window: String
        let generatedAt: Date?
        let sample: Sample
        let archetype: Archetype
        /// The best-placed teams: by placing, then the bigger event, then the
        /// newer one.
        let examples: [ExampleTeam]
    }

    // MARK: /v1/formats/{f}/events

    struct EventWinner: Decodable, Sendable, Equatable {
        let player: String?
        let wins: Int
        let losses: Int
        let ties: Int
        /// Species keys, in the team's order; empty with no published team.
        let team: [String]
    }

    struct EventSummary: Decodable, Sendable, Equatable {
        let id: String
        let name: String?
        let date: Date?
        let players: Int
        /// False while the standings may still change.
        let standingsFinal: Bool
        /// Players in its top cut; nil when it had none, or it isn't known.
        let topCutPlayers: Int?
        /// nil until someone has placed first.
        let winner: EventWinner?
    }

    struct Events: Decodable, Sendable {
        let format: String
        let generatedAt: Date?
        /// Newest first.
        let events: [EventSummary]
    }

    // MARK: Requests

    /// One answer to ask for: its path under the server's address, its
    /// query, and what it decodes into.
    struct Endpoint<Answer: Decodable & Sendable>: Sendable {
        let path: String
        var query: [URLQueryItem] = []

        func url(on base: URL) -> URL {
            var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
            if !query.isEmpty { components.queryItems = query }
            return components.url!
        }
    }

    static let formats = Endpoint<Formats>(path: "v1/formats")

    static func pokemon(format: String, window: Window) -> Endpoint<PokemonList> {
        Endpoint(path: "v1/formats/\(format)/pokemon", query: [URLQueryItem(name: "window", value: window.rawValue)])
    }

    static func pokemon(format: String, key: String, window: Window) -> Endpoint<PokemonDetail> {
        Endpoint(path: "v1/formats/\(format)/pokemon/\(key)",
                 query: [URLQueryItem(name: "window", value: window.rawValue)])
    }

    static func cores(format: String, window: Window) -> Endpoint<Cores> {
        Endpoint(path: "v1/formats/\(format)/cores", query: [URLQueryItem(name: "window", value: window.rawValue)])
    }

    static func archetypes(format: String, window: Window) -> Endpoint<Archetypes> {
        Endpoint(path: "v1/formats/\(format)/archetypes",
                 query: [URLQueryItem(name: "window", value: window.rawValue)])
    }

    static func archetype(format: String, id: String, window: Window) -> Endpoint<ArchetypeDetail> {
        Endpoint(path: "v1/formats/\(format)/archetypes/\(id)",
                 query: [URLQueryItem(name: "window", value: window.rawValue)])
    }

    static func events(format: String, limit: Int = 10) -> Endpoint<Events> {
        Endpoint(path: "v1/formats/\(format)/events", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    // MARK: Decoding

    /// The server's dates are ISO 8601, some with fractional seconds
    /// ("generatedAt") and some without ("lastEvent").
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: .iso8601.year().month().day()
                .time(includingFractionalSeconds: true).timeZone(separator: .omitted)) {
                return date
            }
            if let date = try? Date(text, strategy: .iso8601) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Not an ISO 8601 date: \(text)"))
        }
        return try decoder.decode(type, from: data)
    }
}

extension MetaAPI.Formats {
    /// For Settings' connection test: "M-C: 212 events, 9,410 teams" for
    /// each format.
    var summary: String {
        guard !formats.isEmpty else { return "Connected, but the server has no events yet." }
        return formats.map { "\($0.format): \($0.events.formatted()) events, \($0.teams.formatted()) teams" }
            .joined(separator: "\n")
    }
}
