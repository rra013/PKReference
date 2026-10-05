//
//  SavedIntents.swift
//  PKReference
//
//  The player's saved sets and teams, for Siri, Spotlight and Shortcuts:
//  entities found by name; actions that answer with a set, or with a team
//  and its legality, and open it; and one that loads a set into the damage
//  calc. `IntentIndex` keeps Spotlight's index of them and Siri's list of
//  their names up to date.
//

import AppIntents
import CoreSpotlight
import SwiftData
import SwiftUI

// MARK: - Entities

nonisolated struct SavedSetEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Saved Set", numericFormat: "\(placeholder: .int) saved sets")
    static let defaultQuery = SavedSetQuery()

    /// The set's `PersistentIdentifier`, as `StoredID` text.
    let id: String
    let name: String
    /// Its Pokémon, as it's said.
    let pokemon: String
    let championsMode: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(pokemon) · \(championsMode ? "Champions" : "Mainline")",
                              image: .init(systemName: "square.and.pencil"))
    }
}

nonisolated struct SavedSetQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SavedSetEntity] {
        await IntentData.savedSetEntities(ids: identifiers)
    }

    /// By the set's name or its Pokémon's.
    func entities(matching string: String) async throws -> [SavedSetEntity] {
        await IntentData.savedSetEntities(matching: string)
    }

    /// Every saved set, newest first.
    func suggestedEntities() async throws -> [SavedSetEntity] {
        await IntentData.savedSetEntities()
    }
}

nonisolated struct SavedTeamEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Saved Team", numericFormat: "\(placeholder: .int) saved teams")
    static let defaultQuery = SavedTeamQuery()

    /// The team's `PersistentIdentifier`, as `StoredID` text.
    let id: String
    let name: String
    /// Its Pokémon, as they're said.
    let members: [String]

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)",
                              subtitle: "\(members.isEmpty ? "No Pokémon yet" : members.joined(separator: ", "))",
                              image: .init(systemName: "person.3"))
    }
}

nonisolated struct SavedTeamQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SavedTeamEntity] {
        await IntentData.savedTeamEntities(ids: identifiers)
    }

    /// By the team's name or one of its Pokémon's.
    func entities(matching string: String) async throws -> [SavedTeamEntity] {
        await IntentData.savedTeamEntities(matching: string)
    }

    /// Every saved team, newest first.
    func suggestedEntities() async throws -> [SavedTeamEntity] {
        await IntentData.savedTeamEntities()
    }
}

// MARK: - Sets

struct ShowSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Saved Set"
    static let description = IntentDescription(
        "Says one of your saved sets: its Pokémon, ability, item, nature and moves.")

    @Parameter(title: "Set", requestValueDialog: "Which set?")
    var savedSet: SavedSetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$savedSet)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try IntentData.setAnswer(savedSet.id)
        return .result(dialog: "\(answer.spoken)", snippetIntent: SetSnippetIntent(savedSet: savedSet))
    }
}

struct SetSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Saved Set"
    static let isDiscoverable = false

    @Parameter(title: "Set")
    var savedSet: SavedSetEntity

    init() {}

    init(savedSet: SavedSetEntity) {
        self.savedSet = savedSet
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: SetSnippetView(answer: try IntentData.setAnswer(savedSet.id), savedSet: savedSet))
    }
}

struct OpenSetIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Saved Set"
    static let description = IntentDescription("Opens one of your saved sets in PK Reference's Sets.")

    @Parameter(title: "Set")
    var target: SavedSetEntity

    init() {}

    init(target: SavedSetEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let identifier = StoredID.identifier(target.id) else { throw IntentError.notFound("that set") }
        AppNavigator.shared.request = .savedSet(identifier)
        return .result()
    }
}

struct LoadSetInCalcIntent: AppIntent {
    static let title: LocalizedStringResource = "Load Set into Damage Calc"
    static let description = IntentDescription(
        "Opens PK Reference's damage calc with one of your saved sets as the attacker, keeping the defender.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Set", requestValueDialog: "Which set?")
    var savedSet: SavedSetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Load \(\.$savedSet) into the damage calc")
    }

    init() {}

    init(savedSet: SavedSetEntity) {
        self.savedSet = savedSet
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let identifier = StoredID.identifier(savedSet.id) else { throw IntentError.notFound("that set") }
        AppNavigator.shared.request = .calcSet(identifier)
        return .result()
    }
}

// MARK: - Teams

struct ShowTeamIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Saved Team"
    static let description = IntentDescription(
        "Says one of your saved teams' Pokémon and, for a Champions team, whether it's legal in the regulation chosen in PK Reference's settings.")

    @Parameter(title: "Team", requestValueDialog: "Which team?")
    var team: SavedTeamEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$team)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try IntentData.teamAnswer(team.id)
        return .result(dialog: "\(answer.spoken)", snippetIntent: TeamSnippetIntent(team: team))
    }
}

struct TeamSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Saved Team"
    static let isDiscoverable = false

    @Parameter(title: "Team")
    var team: SavedTeamEntity

    init() {}

    init(team: SavedTeamEntity) {
        self.team = team
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: TeamSnippetView(answer: try IntentData.teamAnswer(team.id), team: team))
    }
}

struct OpenTeamIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Saved Team"
    static let description = IntentDescription("Opens one of your saved teams in PK Reference's Teams.")

    @Parameter(title: "Team")
    var target: SavedTeamEntity

    init() {}

    init(target: SavedTeamEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let identifier = StoredID.identifier(target.id) else { throw IntentError.notFound("that team") }
        AppNavigator.shared.request = .savedTeam(identifier)
        return .result()
    }
}

// MARK: - Reading the store

extension IntentData {
    private static func spokenName(of pokemonID: Int?, among pokemon: [PKMNStats], stored: String?) -> String {
        if let row = pokemon.first(where: { $0.id == pokemonID }) {
            return IntentNames.spoken(name: row.name, formName: row.formName)
        }
        return stored.map { IntentNames.spoken(name: $0, formName: nil) } ?? "No Pokémon"
    }

    private static func allSpreads(in context: ModelContext) -> [SavedSpread] {
        (try? context.fetch(FetchDescriptor<SavedSpread>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    // Sets

    /// Every saved set, newest first. `ids` gives the entities the ids
    /// they were asked for by.
    static func savedSetEntities(in store: ModelContext? = nil) -> [SavedSetEntity] {
        let context = store ?? storeContext
        let pokemon = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
        return allSpreads(in: context).compactMap { spread in
            StoredID.text(spread.persistentModelID).map { savedSetEntity(spread, id: $0, pokemon: pokemon) }
        }
    }

    private static func savedSetEntity(_ spread: SavedSpread, id: String, pokemon: [PKMNStats]) -> SavedSetEntity {
        SavedSetEntity(id: id, name: spread.name,
                       pokemon: spokenName(of: spread.pokemonID, among: pokemon, stored: spread.pokemonName),
                       championsMode: spread.championsMode)
    }

    static func savedSetEntities(ids: [String], in store: ModelContext? = nil) -> [SavedSetEntity] {
        let context = store ?? storeContext
        let pokemon = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
        return ids.compactMap { id in
            StoredID.identifier(id).flatMap { savedSpread($0, in: context) }
                .map { savedSetEntity($0, id: id, pokemon: pokemon) }
        }
    }

    static func savedSetEntities(matching text: String, in store: ModelContext? = nil) -> [SavedSetEntity] {
        let all = savedSetEntities(in: store)
        let candidates = all.enumerated().map { index, set in
            IntentNames.Candidate(id: index, keys: [IntentNames.key(set.name), IntentNames.key(set.pokemon)],
                                  length: set.name.count)
        }
        return IntentNames.matches(text, in: candidates).map { all[$0] }
    }

    static func setAnswer(_ entityID: String, in store: ModelContext? = nil) throws -> SetAnswer {
        let context = store ?? storeContext
        guard let identifier = StoredID.identifier(entityID), let spread = savedSpread(identifier, in: context) else {
            throw IntentError.notFound("that set")
        }
        let pokemon = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
        let row = pokemon.first { $0.id == spread.pokemonID }
        let moves = (try? context.fetch(FetchDescriptor<MoveData>())) ?? []
        let moveNames = [spread.moveID1, spread.moveID2, spread.moveID3, spread.moveID4].compactMap { id in
            moves.first { $0.id == id }?.name
        }
        return SetAnswer(
            name: spread.name,
            pokemon: spokenName(of: spread.pokemonID, among: pokemon, stored: spread.pokemonName),
            types: row.map { [$0.type1] + [$0.type2].compactMap { $0 } } ?? [],
            ability: spread.abilityName.map(formatAbilityName),
            item: spread.itemRawValue.map(HeldItem.currentName),
            nature: allNatures.first { $0.id == spread.natureID }?.name,
            level: spread.level,
            championsMode: spread.championsMode,
            investment: SetAnswer.investment(hp: spread.evHP, atk: spread.evAtk, def: spread.evDef,
                                             spAtk: spread.evSpAtk, spDef: spread.evSpDef, speed: spread.evSpeed),
            moves: moveNames)
    }

    // Teams

    private static func savedTeam(_ identifier: PersistentIdentifier, in context: ModelContext) -> SavedTeam? {
        try? context.fetch(FetchDescriptor<SavedTeam>(predicate: #Predicate { $0.persistentModelID == identifier })).first
    }

    /// A team's Pokémon as the Teams tab shows them: each slot's live set,
    /// or the copy saved with the team when the set is gone.
    private static func slots(of team: SavedTeam, in context: ModelContext) -> [TeamSlotInfo] {
        team.resolvedSlots(allSpreads: allSpreads(in: context),
                           allPokemon: (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? [],
                           allMoves: (try? context.fetch(FetchDescriptor<MoveData>())) ?? [])
    }

    private static func savedTeamEntity(_ team: SavedTeam, id: String, pokemon: [PKMNStats],
                                        context: ModelContext) -> SavedTeamEntity {
        SavedTeamEntity(id: id, name: team.name, members: slots(of: team, in: context).map {
            spokenName(of: $0.pokemonID, among: pokemon, stored: $0.pokemonName)
        })
    }

    /// Every saved team, newest first.
    static func savedTeamEntities(in store: ModelContext? = nil) -> [SavedTeamEntity] {
        let context = store ?? storeContext
        let pokemon = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
        let teams = (try? context.fetch(FetchDescriptor<SavedTeam>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        return teams.compactMap { team in
            StoredID.text(team.persistentModelID).map { savedTeamEntity(team, id: $0, pokemon: pokemon, context: context) }
        }
    }

    static func savedTeamEntities(ids: [String], in store: ModelContext? = nil) -> [SavedTeamEntity] {
        let context = store ?? storeContext
        let pokemon = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
        return ids.compactMap { id in
            StoredID.identifier(id).flatMap { savedTeam($0, in: context) }
                .map { savedTeamEntity($0, id: id, pokemon: pokemon, context: context) }
        }
    }

    static func savedTeamEntities(matching text: String, in store: ModelContext? = nil) -> [SavedTeamEntity] {
        let all = savedTeamEntities(in: store)
        let candidates = all.enumerated().map { index, team in
            IntentNames.Candidate(id: index, keys: Set([IntentNames.key(team.name)] + team.members.map(IntentNames.key)),
                                  length: team.name.count)
        }
        return IntentNames.matches(text, in: candidates).map { all[$0] }
    }

    /// The team's Pokémon and, when any of them is on Champions rules, the
    /// Battle Sim's legality check against the regulation chosen in
    /// Settings.
    static func teamAnswer(_ entityID: String, in store: ModelContext? = nil) throws -> TeamAnswer {
        let context = store ?? storeContext
        guard let identifier = StoredID.identifier(entityID), let team = savedTeam(identifier, in: context) else {
            throw IntentError.notFound("that team")
        }
        let pokemon = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
        let slots = slots(of: team, in: context)
        let members = slots.map { slot in
            TeamAnswer.Member(name: spokenName(of: slot.pokemonID, among: pokemon, stored: slot.pokemonName),
                              types: [slot.type1] + [slot.type2].compactMap { $0 },
                              item: slot.itemRawValue.map(HeldItem.currentName))
        }
        let regulation = ChampionsRegulation.current
        guard slots.contains(where: \.championsMode), let validator = ChampionsValidator(regulation: regulation) else {
            return TeamAnswer(name: team.name, members: members, regulation: nil, problems: [], warnings: [])
        }
        let violations = ChampionsFormat.validate(slots: slots, validator: validator)
        return TeamAnswer(name: team.name, members: members, regulation: regulation.displayName,
                          problems: violations.filter { $0.category.isLegality }.map(\.message),
                          warnings: violations.filter { !$0.category.isLegality }.map(\.message))
    }
}

// MARK: - Spotlight and Siri

/// Keeps Spotlight's index of saved sets and teams, and Siri's list of
/// their names for phrases like "show my team Sand Offense", up to date: at
/// launch, and a second after the last save that adds, changes or deletes
/// one.
@MainActor
enum IntentIndex {
    private static var pending: Task<Void, Never>?

    static func refresh() async {
        let index = CSSearchableIndex.default()
        do {
            try await index.deleteAppEntities(ofType: SavedSetEntity.self)
            try await index.deleteAppEntities(ofType: SavedTeamEntity.self)
            try await index.indexAppEntities(IntentData.savedSetEntities())
            try await index.indexAppEntities(IntentData.savedTeamEntities())
        } catch {
            print("[IntentIndex] Spotlight indexing failed: \(error)")
        }
        PKReferenceShortcuts.updateAppShortcutParameters()
    }

    /// Refreshes after saves from any context, once per burst of saves.
    static func watchSaves() {
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { note in
            guard changesSavedItems(note.userInfo) else { return }
            MainActor.assumeIsolated { scheduleRefresh() }
        }
    }

    private static func scheduleRefresh() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    /// Whether a save added, changed or deleted a saved set or team. A save
    /// that doesn't say what changed might have.
    nonisolated static func changesSavedItems(_ userInfo: [AnyHashable: Any]?) -> Bool {
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        let lists = keys.compactMap { userInfo?[$0.rawValue] as? [PersistentIdentifier] }
        guard !lists.isEmpty else { return true }
        return lists.joined().contains { $0.entityName == "SavedSpread" || $0.entityName == "SavedTeam" }
    }
}
