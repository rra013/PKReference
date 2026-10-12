//
//  MetaLadderModel.swift
//  PKReference
//
//  State behind the Meta tab's ladder views, and their words
//  (BackendIntegration-PHASE5.md §6). The ladder is Settings' regulation's,
//  doubles or singles, at the rating and best-of the tab's pickers choose
//  (LadderRequest); the record comes through LadderStore.
//
//  Opening a ladder view never starts a download from Smogon: the model
//  shows the server's record, or what the device already has, and otherwise
//  says what the download would be and waits to be asked.
//

import Foundation
import Observation

/// What the Meta tab shows: tournament teams, or a ladder.
nonisolated enum MetaView: String, CaseIterable, Identifiable, Sendable {
    case tournaments
    case doublesLadder
    case singlesLadder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tournaments: "Tournaments"
        case .doublesLadder: "Doubles Ladder"
        case .singlesLadder: "Singles Ladder"
        }
    }

    /// The ladder's mode; nil for tournaments.
    var mode: LadderRequest.Mode? {
        switch self {
        case .tournaments: nil
        case .doublesLadder: .doubles
        case .singlesLadder: .singles
        }
    }
}

@MainActor
@Observable
final class LadderModel {
    enum Status: Equatable {
        case loading
        case ready
        case downloading
        case downloadFailed(String)
    }

    private(set) var status: Status = .loading
    /// The record shown, and where it's from.
    private(set) var answer: LadderStore.Answer?
    /// The ladder `answer` is for.
    private(set) var shown: LadderRequest?
    /// Why the server couldn't answer, when it's on.
    private(set) var serverProblem: MetaFailure?
    /// A month of Smogon's that isn't on this device: the ladder's own when
    /// there's nothing to show, or a newer one than the one shown.
    private(set) var offer: SmogonLadderStore.Offer?
    /// Why there's nothing to show and nothing to download.
    private(set) var notice: String?

    private let store: LadderStore
    /// The newest request; an older one that finishes later is dropped.
    private var generation = 0

    init(store: LadderStore = .shared) {
        self.store = store
    }

    /// Loads the ladder: the server's record by its cache's rule (asked
    /// again when `force`d), or what's on the device. Then, from Smogon's
    /// listing alone, whether there's a month to download.
    func load(_ request: LadderRequest, force: Bool = false) async {
        generation += 1
        let mine = generation
        if shown != request {
            status = .loading
            answer = nil
            offer = nil
            notice = nil
        }
        let loaded = await store.load(request, force: force)
        guard mine == generation else { return }
        answer = loaded.answer
        shown = request
        serverProblem = loaded.serverProblem
        status = .ready

        // The server's record needs nothing from Smogon.
        guard loaded.answer?.source != .server else {
            offer = nil
            notice = nil
            return
        }
        do {
            let offered = try await store.device.offer(request, forceRefresh: force)
            guard mine == generation else { return }
            if let offered, offered.month != loaded.answer?.stats.month {
                offer = offered
                notice = nil
            } else {
                offer = nil
                notice = loaded.answer == nil ? LadderText.nothingPublished(request) : nil
            }
        } catch {
            guard mine == generation else { return }
            offer = nil
            notice = loaded.answer == nil ? LadderText.cantReachSmogon(error.localizedDescription) : nil
        }
    }

    /// Downloads the offered month from Smogon and shows it.
    func download(_ request: LadderRequest) async {
        generation += 1
        let mine = generation
        status = .downloading
        do {
            let stats = try await store.device.stats(request)
            guard mine == generation else { return }
            if let stats {
                answer = LadderStore.Answer(stats: stats, source: .device)
                shown = request
                offer = nil
                notice = nil
            }
            status = .ready
        } catch {
            guard mine == generation else { return }
            status = .downloadFailed(error.localizedDescription)
        }
    }
}

// MARK: - Names

/// Names a ladder record's entries. Smogon's "Charizard-Mega-Y" reads as
/// "Mega Charizard Y" and "Arcanine-Hisui" as "Arcanine (Hisui)", the way the
/// rest of the app names them. Where the regulation's data can't tell two
/// entries apart ("Rotom-Wash" and "Rotom-Heat", "Basculegion" and
/// "Basculegion-F"), they keep Smogon's names.
nonisolated struct LadderNamer: Sendable {
    private let vocabulary: TeamSearchVocabulary?
    private let names: [String: String]

    init(_ stats: MetaAPI.LadderStats?, regulation: ChampionsRegulation) {
        self.init(stats, vocabulary: try? TeamSearchVocabulary.bundled(for: regulation))
    }

    init(_ stats: MetaAPI.LadderStats?, vocabulary: TeamSearchVocabulary?) {
        self.vocabulary = vocabulary
        var names: [String: String] = [:]
        var owners: [String: [String]] = [:]
        for pokemon in stats?.pokemon ?? [] {
            let display = vocabulary?.term(showdownName: pokemon.name)?.displayName ?? pokemon.name
            names[pokemon.name] = display
            owners[display, default: []].append(pokemon.name)
        }
        for (_, shared) in owners where shared.count > 1 {
            for name in shared { names[name] = name }
        }
        self.names = names
    }

    /// An entry's name, or a teammate's, by Smogon's name.
    func name(_ smogonName: String) -> String {
        names[smogonName] ?? vocabulary?.term(showdownName: smogonName)?.displayName ?? smogonName
    }
}

// MARK: - Words

/// The ladder views' sentences, as plain functions so tests can read them.
nonisolated enum LadderText {
    /// "All", "1500+": the rating picker's labels.
    static func rating(_ rating: Int) -> String {
        rating == 0 ? "All" : "\(rating)+"
    }

    /// "all players", "players rated 1760+".
    static func players(_ rating: Int) -> String {
        rating == 0 ? "all players" : "players rated \(rating)+"
    }

    static func bestOf(_ bestOf: Int) -> String {
        "Best of \(bestOf)"
    }

    /// "September 2026", from "2026-09"; the text itself when it isn't a month.
    static func month(_ month: String, locale: Locale = .current) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return month }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 15)) else { return month }
        var style = Date.FormatStyle(locale: locale).month(.wide).year()
        style.timeZone = .gmt
        return date.formatted(style)
    }

    /// "1,631,943 battles · September 2026".
    static func sample(_ stats: MetaAPI.LadderStats, locale: Locale = .current) -> String {
        "\(MetaText.count(stats.battles, "battle")) · \(month(stats.month, locale: locale))"
    }

    /// Where the numbers come from, and how old the server's copy is.
    static func source(_ source: LadderStore.Source, fetched: Date?, now: Date, locale: Locale = .current) -> String {
        switch source {
        case .server:
            let from = "Pokémon Showdown's ladder, from Smogon's stats through your PK Reference server"
            guard let fetched else { return from }
            return "\(from) · fetched \(MetaText.ago(fetched, now: now, locale: locale))"
        case .device:
            return "Pokémon Showdown's ladder, from Smogon's stats downloaded to this device"
        }
    }

    /// "Doubles, best of 3, players rated 1500+".
    static func ladder(_ request: LadderRequest) -> String {
        var parts = [request.mode == .doubles ? "Doubles" : "Singles"]
        if request.mode == .doubles { parts.append("best of \(request.bestOf)") }
        parts.append(players(request.rating))
        return parts.joined(separator: ", ")
    }

    /// "47%", and for small shares "6.6%" or "<0.1%".
    static func percent(_ share: Double) -> String {
        let value = share * 100
        if value >= 10 { return "\(Int(value.rounded()))%" }
        if value > 0 && value < 0.05 { return "<0.1%" }
        return String(format: "%.1f%%", value)
    }

    /// The most-used Pokémon, in a sentence.
    static func mostUsed(_ stats: MetaAPI.LadderStats, name: (String) -> String) -> String? {
        guard let first = stats.pokemon.first else { return nil }
        let teams = stats.rating == 0 ? "teams" : "teams of \(players(stats.rating))"
        var text = "\(name(first.name)) is on \(percent(first.usage)) of \(teams)"
        if stats.pokemon.count > 1 {
            let second = stats.pokemon[1]
            text += ", then \(name(second.name)) on \(percent(second.usage))"
        }
        return text + "."
    }

    /// How many leads a team sends out.
    static func leadsPerTeam(_ mode: String) -> Double {
        mode == LadderRequest.Mode.doubles.rawValue ? 2 : 1
    }

    /// The share of the teams with a Pokémon that lead with it: its lead
    /// share, times the leads a team sends out, over its usage. nil without
    /// a lead share.
    static func leadRate(_ pokemon: MetaAPI.LadderPokemon, mode: String) -> Double? {
        guard let share = pokemon.leadShare, pokemon.usage > 0 else { return nil }
        return min(1, share * leadsPerTeam(mode) / pokemon.usage)
    }

    /// "Leads on about 36% of the teams with it."
    static func leadRateSentence(_ pokemon: MetaAPI.LadderPokemon, mode: String) -> String? {
        leadRate(pokemon, mode: mode).map { "Leads on about \(percent($0)) of the teams with it." }
    }

    /// "Adamant · 2 HP / 32 Atk / 32 Spe", from "Adamant:2/32/0/0/0/32". The
    /// text itself when it doesn't read as a spread.
    static func spread(_ value: String) -> String {
        guard let parsed = LadderSpread(value) else { return value }
        let labels = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
        let points = zip(parsed.points, labels).filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return points.isEmpty ? "\(parsed.nature) · no stat points" : "\(parsed.nature) · \(points.joined(separator: " / "))"
    }

    /// "These 10 cover 21% of its teams."
    static func spreadsCover(_ spreads: [MetaAPI.LadderShare]) -> String? {
        guard !spreads.isEmpty else { return nil }
        let covered = min(1, spreads.reduce(0) { $0 + $1.share })
        let these = spreads.count == 1 ? "This one covers" : "These \(spreads.count) cover"
        return "\(these) \(percent(covered)) of its teams."
    }

    /// One row for VoiceOver.
    static func spoken(_ pokemon: MetaAPI.LadderPokemon, name: String) -> String {
        var text = "\(name). On \(percent(pokemon.usage)) of teams."
        if let trend = MetaText.trend(pokemon.trend) {
            text += " " + trend.replacingOccurrences(of: "▲", with: "Up").replacingOccurrences(of: "▼", with: "Down")
                + " since last month."
        }
        return text
    }

    /// The biggest gaps between usage at the highest rating a record has and
    /// at the lowest: positive is used more by stronger players.
    static func ratingGaps(_ stats: MetaAPI.LadderStats) -> [(pokemon: MetaAPI.LadderPokemon, low: Double, high: Double)] {
        guard let lowest = stats.ratings.min(), let highest = stats.ratings.max(), lowest != highest else { return [] }
        return stats.pokemon.compactMap { pokemon in
            guard let low = pokemon.usageByRating.first(where: { $0.rating == lowest })?.usage,
                  let high = pokemon.usageByRating.first(where: { $0.rating == highest })?.usage else { return nil }
            return (pokemon, low, high)
        }
    }

    // MARK: Nothing to show

    /// "5.9 MB"; nil when Smogon's listing didn't say.
    static func size(_ bytes: Int?) -> String? {
        bytes.map { Int64($0).formatted(.byteCount(style: .file)) }
    }

    /// The download card's text.
    static func download(_ offer: SmogonLadderStore.Offer, for request: LadderRequest, showing: String?,
                         locale: Locale = .current) -> String {
        let month = month(offer.month, locale: locale)
        var text: String
        if let showing {
            text = "Smogon has published \(month)'s stats. Showing \(Self.month(showing, locale: locale))'s."
        } else {
            text = "Smogon's \(month) stats for this ladder (\(ladder(request).lowercased())) aren't on this device yet."
        }
        if let size = size(offer.bytes) { text += " The download is \(size)." }
        return text
    }

    /// Smogon has nothing for the regulation's ladder.
    static func nothingPublished(_ request: LadderRequest) -> String {
        let ladder = request.mode == .doubles ? (request.bestOf == 3 ? "best-of-three doubles" : "doubles") : "singles"
        return "Smogon has no \(request.regulation.limitlessFormat) \(ladder) stats at this rating yet. "
            + "It publishes a month's stats on the 1st of the next month, so a new regulation has none for its "
            + "first weeks."
    }

    static func cantReachSmogon(_ reason: String) -> String {
        "Couldn't reach Smogon to look for this ladder's stats: \(reason)"
    }

    /// What a server adds, said where the device's record is shown.
    static let serverAdds = "With a PK Reference server (beta): what's rising since last month, and usage at "
        + "every rating, without a download for each."
}

/// A spread, read from Smogon's "Adamant:2/32/0/0/0/32": the nature, then
/// the stat points for HP, Attack, Defense, Sp. Atk, Sp. Def and Speed.
nonisolated struct LadderSpread: Equatable, Sendable {
    let nature: String
    let points: [Int]

    init?(_ value: String) {
        let halves = value.split(separator: ":", maxSplits: 1)
        guard halves.count == 2 else { return nil }
        let points = halves[1].split(separator: "/", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard points.count == 6, points.allSatisfy({ $0 >= 0 }) else { return nil }
        nature = String(halves[0])
        self.points = points
    }
}

// MARK: - Definitions

/// What each of the ladder's numbers means, as its ⓘ shows it. The texts are
/// BackendIntegration-PHASE5.md §6.4's word for word: change both together.
nonisolated enum LadderDefinition: String, CaseIterable, Identifiable, Sendable {
    case usage, ratingBand, leadShare, trend, spread

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usage: "Ladder Usage"
        case .ratingBand: "Rating Band"
        case .leadShare: "Lead Share"
        case .trend: "Trend"
        case .spread: "Spread"
        }
    }

    var text: String {
        switch self {
        case .usage:
            "The share of teams on Pokémon Showdown's ladder that month with the Pokémon on the team of six. Each "
                + "team counts by how likely its player is rated at or above the band, which is Smogon's weighting; "
                + "All players counts every team once. A Pokémon holding its Mega Stone counts as the Mega, apart "
                + "from its plain form."
        case .ratingBand:
            "Smogon publishes four: every player, and players rated about 1500, 1630 and 1760 or higher. The "
                + "battle count is the same at each: a higher band weighs most of them less, so it rests on fewer "
                + "players."
        case .leadShare:
            "Its share of all the Pokémon sent out first. In doubles each team leads two, so a Pokémon led by one "
                + "team in ten has 5%."
        case .trend:
            "Usage this month less last month's, in percentage points."
        case .spread:
            "A nature and the stat points put into HP, Attack, Defense, Sp. Atk, Sp. Def and Speed."
        }
    }

    var info: MetaInfo { MetaInfo(title: title, text: text, note: nil) }
}
