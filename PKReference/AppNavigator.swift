//
//  AppNavigator.swift
//  PKReference
//
//  Where an App Intent that opens the app wants it to go. The intent sets
//  `request`; the root view shows the request's tab, and that tab takes the
//  request and clears it. A request for a hidden tab is dropped.
//

import Foundation
import Observation
import SwiftData

@Observable
final class AppNavigator {
    static let shared = AppNavigator()

    /// A form of a Pokémon, as the Pokédex names it ("mega", "alola") and
    /// as it's said ("Mega Gardevoir"), for opening its page on that form.
    struct PokemonForm: Hashable, Sendable {
        let formName: String
        let spokenName: String
    }

    enum Request: Equatable {
        /// A Pokémon's page in the Mon Index, by National Dex number, on the
        /// given form when the regulation lists it.
        case pokemon(speciesID: Int, form: PokemonForm? = nil)
        /// The calc, with both sides loaded.
        case calc(CalcRequest)
        /// Team Search, with this query.
        case teamSearch(query: String)
        /// Speed Tiers, with the first Pokémon as yours and the second's
        /// investment as the benchmark.
        case speed(SpeedRequest)
        /// A saved set, open in Sets.
        case savedSet(PersistentIdentifier)
        /// A saved team, open in Teams.
        case savedTeam(PersistentIdentifier)
        /// The calc, with a saved set as the attacker and the defender kept.
        case calcSet(PersistentIdentifier)
        /// The calc with both sides set up exactly, as a Problem Solver
        /// answer is.
        case calcSides(CalcSides)
        /// The Problem Solver, with this set to beat.
        case problemSolver(SideSetup)
        /// An index, with its search field filled in: the Mon, Move or
        /// Ability Index.
        case indexSearch(AppTab, String)
        /// The calc with one of the meta's top sets as the defender, keeping
        /// the attacker, from a Meta Pokémon page.
        case calcDefender(MetaSetRequest)
        /// Settings, as the Meta tab's Change in Settings opens it on iPhone
        /// and iPad. The Mac opens its Settings window instead.
        case settings

        var tab: AppTab {
            switch self {
            case .pokemon: .monIndex
            case .calc, .calcSet, .calcSides, .calcDefender: .damageCalc
            case .teamSearch: .teamSearch
            case .speed: .speedTiers
            case .savedSet: .sets
            case .savedTeam: .teams
            case .indexSearch(let tab, _): tab
            case .problemSolver: .problemSolver
            case .settings: .settings
            }
        }
    }

    var request: Request?

    #if DEBUG
    /// Debug builds: `-debugNavigate pokemon:445`, `-debugNavigate
    /// "teamSearch:Trick Room"`, `-debugNavigate calc:445,485,89` (attacker,
    /// defender and move ids, both with no investment), `-debugNavigate
    /// speed:887,785` (the first with full investment and a Speed nature,
    /// the second with full investment), `set:`, `team:` or `calcSet:` and
    /// a saved set's or team's name, `search:` and words, as in-app search
    /// gets them, or `problem:` and a Pokémon for the Problem Solver, makes
    /// the same request an intent's Open button would, so opening the app
    /// can be checked without Siri.
    func requestFromLaunchArguments() {
        guard let argument = UserDefaults.standard.string(forKey: "debugNavigate"),
              let colon = argument.firstIndex(of: ":") else { return }
        let value = String(argument[argument.index(after: colon)...])
        switch argument[..<colon] {
        case "pokemon":
            if let id = Int(value) { request = .pokemon(speciesID: id) }
        case "teamSearch":
            request = .teamSearch(query: value)
        case "calc":
            let ids = value.split(separator: ",").compactMap { Int($0) }
            if ids.count == 3 {
                request = .calc(CalcRequest(attackerID: ids[0], attackerStats: .noInvestment,
                                            defenderID: ids[1], defenderStats: .noInvestment,
                                            moveID: ids[2]))
            }
        case "speed":
            let ids = value.split(separator: ",").compactMap { Int($0) }
            if ids.count == 2 {
                request = .speed(SpeedRequest(firstID: ids[0], firstStats: .fullInvestmentSpeedNature,
                                              secondID: ids[1], secondStats: .fullInvestment))
            }
        case "set", "calcSet":
            let context = AppModelContainer.shared.mainContext
            let spread = try? context.fetch(FetchDescriptor<SavedSpread>(predicate: #Predicate { $0.name == value })).first
            if let id = spread?.persistentModelID {
                request = argument.hasPrefix("set:") ? .savedSet(id) : .calcSet(id)
            }
        case "search":
            request = IntentData.searchRequest(for: value)
        case "problem":
            // `problem:Incineroar` or `problem:Incineroar,intimidate`: the
            // Pokémon, uninvested, with full HP and Defense when "bulky",
            // holding Sitrus Berry or Focus Sash when "sitrus" or "sash",
            // and with Sturdy when "sturdy".
            let parts = value.split(separator: ",").map(String.init)
            let context = AppModelContainer.shared.mainContext
            let all = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
            if let name = parts.first, let row = all.first(where: { $0.name == name && !$0.isForm }) {
                let side = CalcSide()
                side.loadUninvested(row, championsMode: true, allPokemon: all)
                if parts.contains("intimidate") { side.selectedAbility = "intimidate" }
                if parts.contains("bulky") { side.evHP = 32; side.evDef = 32 }
                if parts.contains("sitrus") { side.heldItem = .sitrusBerry }
                if parts.contains("sash") { side.heldItem = .focusSash }
                if parts.contains("sturdy") { side.selectedAbility = "sturdy" }
                if let setup = SideSetup(side) { request = .problemSolver(setup) }
            }
        case "team":
            let context = AppModelContainer.shared.mainContext
            let team = try? context.fetch(FetchDescriptor<SavedTeam>(predicate: #Predicate { $0.name == value })).first
            if let id = team?.persistentModelID { request = .savedTeam(id) }
        default:
            break
        }
    }
    #endif
}
