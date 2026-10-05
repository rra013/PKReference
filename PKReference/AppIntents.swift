//
//  AppIntents.swift
//  PKReference
//
//  The actions Siri, Spotlight and Shortcuts can run: look up a Pokémon,
//  calculate damage, search tournament teams, compare speeds, check
//  legality and find counters. Each answers in place, with a spoken or shown answer and a
//  snippet whose "Open in PK Reference" button opens the page through an
//  Open intent and `AppNavigator`. The answers' wording is in
//  `IntentAnswers.swift`, the snippets in `IntentSnippets.swift`, and the
//  entities in `IntentEntities.swift`; saved sets and teams have their own
//  actions in `SavedIntents.swift`. HANDOFF.md's feature notes have the
//  decisions behind them.
//

import AppIntents
import SwiftData
import SwiftUI

// MARK: - Look Up Pokémon

struct LookUpPokemonIntent: AppIntent {
    static let title: LocalizedStringResource = "Look Up Pokémon"
    static let description = IntentDescription(
        "Says a Pokémon's types, what it's weak to and resists by type, and its base stat total.")

    @Parameter(title: "Pokémon", requestValueDialog: "Which Pokémon?")
    var pokemon: PokemonEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Look up \(\.$pokemon)")
    }

    init() {}

    init(pokemon: PokemonEntity) {
        self.pokemon = pokemon
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try IntentData.lookup(pokemon.id)
        return .result(dialog: "\(answer.spoken)", snippetIntent: PokemonSnippetIntent(pokemon: pokemon))
    }
}

struct PokemonSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Pokémon Summary"
    static let isDiscoverable = false

    @Parameter(title: "Pokémon")
    var pokemon: PokemonEntity

    init() {}

    init(pokemon: PokemonEntity) {
        self.pokemon = pokemon
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: PokemonSnippetView(answer: try IntentData.lookup(pokemon.id), pokemon: pokemon))
    }
}

struct OpenPokemonIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Pokémon"
    static let description = IntentDescription("Opens a Pokémon's page in PK Reference.")

    @Parameter(title: "Pokémon")
    var target: PokemonEntity

    init() {}

    init(target: PokemonEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let form = (try? IntentData.pokemon(target.id)).flatMap(IntentData.form)
        AppNavigator.shared.request = .pokemon(speciesID: target.speciesID, form: form)
        return .result()
    }
}

// MARK: - Calculate Damage

struct CalculateDamageIntent: AppIntent {
    static let title: LocalizedStringResource = "Calculate Damage"
    static let description = IntentDescription(
        """
        Answers how much damage one Pokémon's move does to another, such as how much Incineroar's Darkest \
        Lariat does to a Farigiraf with maxed Defense: the damage as a share of the defender's HP, and how \
        many hits it takes to knock it out, from PK Reference's damage calc.
        """,
        searchKeywords: ["damage", "damage calc", "calc", "how much damage", "KO", "OHKO", "2HKO",
                         "one-hit KO", "percent", "rolls", "EVs"])

    @Parameter(title: "Attacker", requestValueDialog: "Which Pokémon is attacking?")
    var attacker: PokemonEntity

    @Parameter(title: "Move", requestValueDialog: "Which move?")
    var move: MoveEntity

    @Parameter(title: "Defender", requestValueDialog: "Which Pokémon is it attacking?")
    var defender: PokemonEntity

    @Parameter(title: "Attacker's Stats", requestValueDialog: "Which stats for the attacker?",
               optionsProvider: AttackerStatsOptions())
    var attackerStats: StatsEntity

    @Parameter(title: "Defender's Stats", requestValueDialog: "Which stats for the defender?",
               optionsProvider: DefenderStatsOptions())
    var defenderStats: StatsEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$attacker)'s \(\.$move) against \(\.$defender)") {
            \.$attackerStats
            \.$defenderStats
        }
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try IntentData.damage(try request)
        return .result(dialog: "\(answer.spoken)", snippetIntent: DamageSnippetIntent(copying: self))
    }

    var request: CalcRequest {
        get throws {
            guard let attackerChoice = attackerStats.choice, let defenderChoice = defenderStats.choice else {
                throw IntentError.notFound("that saved set")
            }
            return CalcRequest(attackerID: attacker.id, attackerStats: attackerChoice,
                               defenderID: defender.id, defenderStats: defenderChoice, moveID: move.id)
        }
    }
}

struct DamageSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Damage Summary"
    static let isDiscoverable = false

    @Parameter(title: "Attacker") var attacker: PokemonEntity
    @Parameter(title: "Move") var move: MoveEntity
    @Parameter(title: "Defender") var defender: PokemonEntity
    @Parameter(title: "Attacker's Stats") var attackerStats: StatsEntity
    @Parameter(title: "Defender's Stats") var defenderStats: StatsEntity

    init() {}

    init(copying calc: CalculateDamageIntent) {
        attacker = calc.attacker
        move = calc.move
        defender = calc.defender
        attackerStats = calc.attackerStats
        defenderStats = calc.defenderStats
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let open = OpenCalcIntent(attacker: attacker, move: move, defender: defender,
                                  attackerStats: attackerStats, defenderStats: defenderStats)
        return .result(view: DamageSnippetView(answer: try IntentData.damage(try open.request), open: open))
    }
}

struct OpenCalcIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Damage Calc"
    static let description = IntentDescription("Opens PK Reference's damage calc with both Pokémon loaded.")
    static let supportedModes: IntentModes = .foreground
    static let isDiscoverable = false

    @Parameter(title: "Attacker") var attacker: PokemonEntity
    @Parameter(title: "Move") var move: MoveEntity
    @Parameter(title: "Defender") var defender: PokemonEntity
    @Parameter(title: "Attacker's Stats") var attackerStats: StatsEntity
    @Parameter(title: "Defender's Stats") var defenderStats: StatsEntity

    init() {}

    init(attacker: PokemonEntity, move: MoveEntity, defender: PokemonEntity,
         attackerStats: StatsEntity, defenderStats: StatsEntity) {
        self.attacker = attacker
        self.move = move
        self.defender = defender
        self.attackerStats = attackerStats
        self.defenderStats = defenderStats
    }

    var request: CalcRequest {
        get throws {
            guard let attackerChoice = attackerStats.choice, let defenderChoice = defenderStats.choice else {
                throw IntentError.notFound("that saved set")
            }
            return CalcRequest(attackerID: attacker.id, attackerStats: attackerChoice,
                               defenderID: defender.id, defenderStats: defenderChoice, moveID: move.id)
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.request = .calc(try request)
        return .result()
    }
}

// MARK: - Search Teams

struct SearchTeamsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Teams"
    static let description = IntentDescription(
        "Finds the popular tournament team compositions that match a description, such as \"Trick Room with Mega Gardevoir, no Incineroar\".")

    @Parameter(title: "Search", requestValueDialog: "What kind of team?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search teams for \(\.$query)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try await IntentData.teamSearch(query)
        return .result(dialog: "\(answer.spoken)", snippetIntent: TeamSearchSnippetIntent(query: query))
    }
}

struct TeamSearchSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Team Search Summary"
    static let isDiscoverable = false

    @Parameter(title: "Search")
    var query: String

    init() {}

    init(query: String) {
        self.query = query
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: TeamSearchSnippetView(answer: try await IntentData.teamSearch(query)))
    }
}

struct OpenTeamSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Team Search"
    static let description = IntentDescription("Opens PK Reference's Team Search with a search.")
    static let supportedModes: IntentModes = .foreground
    static let isDiscoverable = false

    @Parameter(title: "Search")
    var query: String

    init() {}

    init(query: String) {
        self.query = query
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.request = .teamSearch(query: query)
        return .result()
    }
}

// MARK: - Compare Speed

struct CompareSpeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Compare Speed"
    static let description = IntentDescription(
        "Says which of two Pokémon is faster, with each one's Speed.")

    @Parameter(title: "Pokémon", requestValueDialog: "Which Pokémon?")
    var first: PokemonEntity

    @Parameter(title: "Compared With", requestValueDialog: "Compared with which Pokémon?")
    var second: PokemonEntity

    @Parameter(title: "First Pokémon's Speed", requestValueDialog: "Which Speed for the first Pokémon?",
               optionsProvider: FirstSpeedOptions())
    var firstStats: SpeedStatsEntity

    @Parameter(title: "Second Pokémon's Speed", requestValueDialog: "Which Speed for the second Pokémon?",
               optionsProvider: SecondSpeedOptions())
    var secondStats: SpeedStatsEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Is \(\.$first) faster than \(\.$second)") {
            \.$firstStats
            \.$secondStats
        }
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try IntentData.speed(try request)
        return .result(dialog: "\(answer.spoken)", snippetIntent: SpeedSnippetIntent(copying: self))
    }

    var request: SpeedRequest {
        get throws {
            try SpeedRequest(first: first, firstStats: firstStats, second: second, secondStats: secondStats)
        }
    }
}

extension SpeedRequest {
    init(first: PokemonEntity, firstStats: SpeedStatsEntity,
         second: PokemonEntity, secondStats: SpeedStatsEntity) throws {
        guard let firstChoice = firstStats.choice, let secondChoice = secondStats.choice else {
            throw IntentError.notFound("that saved set")
        }
        self.init(firstID: first.id, firstStats: firstChoice, secondID: second.id, secondStats: secondChoice)
    }
}

struct SpeedSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Speed Comparison"
    static let isDiscoverable = false

    @Parameter(title: "Pokémon") var first: PokemonEntity
    @Parameter(title: "Compared With") var second: PokemonEntity
    @Parameter(title: "First Pokémon's Speed") var firstStats: SpeedStatsEntity
    @Parameter(title: "Second Pokémon's Speed") var secondStats: SpeedStatsEntity

    init() {}

    init(copying comparison: CompareSpeedIntent) {
        first = comparison.first
        second = comparison.second
        firstStats = comparison.firstStats
        secondStats = comparison.secondStats
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let open = OpenSpeedTiersIntent(first: first, second: second, firstStats: firstStats, secondStats: secondStats)
        return .result(view: SpeedSnippetView(answer: try IntentData.speed(try open.request), open: open))
    }
}

struct OpenSpeedTiersIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Speed Tiers"
    static let description = IntentDescription(
        "Opens PK Reference's Speed Tiers with the first Pokémon, and the second's investment as the benchmark.")
    static let supportedModes: IntentModes = .foreground
    static let isDiscoverable = false

    @Parameter(title: "Pokémon") var first: PokemonEntity
    @Parameter(title: "Compared With") var second: PokemonEntity
    @Parameter(title: "First Pokémon's Speed") var firstStats: SpeedStatsEntity
    @Parameter(title: "Second Pokémon's Speed") var secondStats: SpeedStatsEntity

    init() {}

    init(first: PokemonEntity, second: PokemonEntity, firstStats: SpeedStatsEntity, secondStats: SpeedStatsEntity) {
        self.first = first
        self.second = second
        self.firstStats = firstStats
        self.secondStats = secondStats
    }

    var request: SpeedRequest {
        get throws {
            try SpeedRequest(first: first, firstStats: firstStats, second: second, secondStats: secondStats)
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.request = .speed(try request)
        return .result()
    }
}

// MARK: - Check Legality

struct CheckLegalityIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Legality"
    static let description = IntentDescription(
        "Says whether a Pokémon, or one of its forms or Megas, is allowed in a Pokémon Champions regulation, and why not when it isn't.")

    @Parameter(title: "Pokémon", requestValueDialog: "Which Pokémon?")
    var pokemon: PokemonEntity

    @Parameter(title: "Regulation",
               description: "Leave it empty for the regulation chosen in PK Reference's settings. The answer always names the regulation.")
    var regulation: RegulationChoice?

    static var parameterSummary: some ParameterSummary {
        Summary("Is \(\.$pokemon) legal in \(\.$regulation)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try IntentData.legality(pokemon.id, regulation: regulation)
        return .result(dialog: "\(answer.spoken)",
                       snippetIntent: LegalitySnippetIntent(pokemon: pokemon, regulation: regulation))
    }
}

struct LegalitySnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Legality"
    static let isDiscoverable = false

    @Parameter(title: "Pokémon") var pokemon: PokemonEntity
    @Parameter(title: "Regulation") var regulation: RegulationChoice?

    init() {}

    init(pokemon: PokemonEntity, regulation: RegulationChoice?) {
        self.pokemon = pokemon
        self.regulation = regulation
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: LegalitySnippetView(answer: try IntentData.legality(pokemon.id, regulation: regulation), pokemon: pokemon))
    }
}

// MARK: - Find Counters

struct FindCountersIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Counters"
    static let description = IntentDescription(
        """
        Answers what beats a Pokémon: how many Pokémon knock it out in one hit, guaranteed, in Pokémon \
        Champions doubles, and the three that need the fewest stat points, moving first where they can, from \
        PK Reference's Problem Solver.
        """,
        searchKeywords: ["counter", "counters", "what beats", "how do I beat", "check", "OHKO",
                         "one-hit KO", "problem solver"])

    @Parameter(title: "Pokémon", requestValueDialog: "Which Pokémon do you need to beat?")
    var pokemon: PokemonEntity

    @Parameter(title: "Its Stats", requestValueDialog: "Which stats for it?",
               optionsProvider: TargetStatsOptions())
    var stats: TargetStatsEntity

    static var parameterSummary: some ParameterSummary {
        Summary("What beats \(\.$pokemon)") {
            \.$stats
        }
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let answer = try await IntentData.counters(try request)
        return .result(dialog: "\(answer.spoken)",
                       snippetIntent: CountersSnippetIntent(pokemon: pokemon, stats: stats))
    }

    var request: CountersRequest {
        get throws { try CountersRequest(pokemon: pokemon, stats: stats) }
    }
}

extension CountersRequest {
    init(pokemon: PokemonEntity, stats: TargetStatsEntity) throws {
        guard let choice = stats.choice else { throw IntentError.notFound("that saved set") }
        self.init(pokemonID: pokemon.id, stats: choice)
    }
}

struct CountersSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Counters"
    static let isDiscoverable = false

    @Parameter(title: "Pokémon") var pokemon: PokemonEntity
    @Parameter(title: "Its Stats") var stats: TargetStatsEntity

    init() {}

    init(pokemon: PokemonEntity, stats: TargetStatsEntity) {
        self.pokemon = pokemon
        self.stats = stats
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let open = OpenProblemSolverIntent(pokemon: pokemon, stats: stats)
        return .result(view: CountersSnippetView(answer: try await IntentData.counters(try open.request), open: open))
    }
}

struct OpenProblemSolverIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Problem Solver"
    static let description = IntentDescription("Opens PK Reference's Problem Solver on the Pokémon to beat.")
    static let supportedModes: IntentModes = .foreground
    static let isDiscoverable = false

    @Parameter(title: "Pokémon") var pokemon: PokemonEntity
    @Parameter(title: "Its Stats") var stats: TargetStatsEntity

    init() {}

    init(pokemon: PokemonEntity, stats: TargetStatsEntity) {
        self.pokemon = pokemon
        self.stats = stats
    }

    var request: CountersRequest {
        get throws { try CountersRequest(pokemon: pokemon, stats: stats) }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let target = try await IntentData.counterTarget(try request)
        guard let setup = SideSetup(target) else { throw IntentError.notFound("that Pokémon") }
        AppNavigator.shared.request = .problemSolver(setup)
        return .result()
    }
}

// MARK: - Search in the app

/// The system's in-app search, which Siri and Spotlight use for "search PK
/// Reference for …" and for requests they route to the app's search. It
/// opens the app on the result: the Pokémon, move or ability the words
/// name, or the Mon Index filtered to them.
@AppIntent(schema: .system.search)
struct SearchPKReferenceIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.request = IntentData.searchRequest(for: criteria.term)
        return .result()
    }
}

// MARK: - Siri phrases

struct PKReferenceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Every phrase names the app, as Siri requires; the ones starting
        // with it are the least likely to be answered from the web instead.
        AppShortcut(intent: LookUpPokemonIntent(), phrases: [
            "\(.applicationName), look up \(\.$pokemon)",
            "\(.applicationName), what is \(\.$pokemon) weak to",
            "Look up \(\.$pokemon) in \(.applicationName)",
            "What is \(\.$pokemon) weak to in \(.applicationName)",
            "\(.applicationName), look up a Pokémon",
            "Look up a Pokémon in \(.applicationName)",
        ], shortTitle: "Look Up Pokémon", systemImageName: "magnifyingglass")
        // A phrase can name only one Pokémon, so Siri asks for the move and
        // the other one.
        AppShortcut(intent: CalculateDamageIntent(), phrases: [
            "\(.applicationName), calculate damage",
            "\(.applicationName), how much damage does \(\.$attacker) do",
            "\(.applicationName), how much will \(\.$attacker) do",
            "\(.applicationName), how much damage does \(\.$defender) take",
            "Calculate damage in \(.applicationName)",
            "Run a damage calc in \(.applicationName)",
            "How much damage does \(\.$attacker) do in \(.applicationName)",
        ], shortTitle: "Calculate Damage", systemImageName: "bolt.fill")
        AppShortcut(intent: SearchTeamsIntent(), phrases: [
            "\(.applicationName), search teams",
            "Search teams in \(.applicationName)",
            "Find teams in \(.applicationName)",
        ], shortTitle: "Search Teams", systemImageName: "sparkle.magnifyingglass")
        // A phrase can name only one Pokémon, so Siri asks for the second.
        AppShortcut(intent: CompareSpeedIntent(), phrases: [
            "\(.applicationName), how fast is \(\.$first)",
            "\(.applicationName), compare speeds",
            "How fast is \(\.$first) in \(.applicationName)",
            "Compare speeds in \(.applicationName)",
        ], shortTitle: "Compare Speed", systemImageName: "hare")
        AppShortcut(intent: CheckLegalityIntent(), phrases: [
            "\(.applicationName), is \(\.$pokemon) legal",
            "\(.applicationName), check legality",
            "Check if \(\.$pokemon) is legal in \(.applicationName)",
            "Check legality in \(.applicationName)",
        ], shortTitle: "Check Legality", systemImageName: "checkmark.seal")
        AppShortcut(intent: ShowSetIntent(), phrases: [
            "\(.applicationName), show my set \(\.$savedSet)",
            "\(.applicationName), show a saved set",
            "Show my set \(\.$savedSet) in \(.applicationName)",
        ], shortTitle: "Show Saved Set", systemImageName: "square.and.pencil")
        AppShortcut(intent: LoadSetInCalcIntent(), phrases: [
            "\(.applicationName), load \(\.$savedSet) into the calc",
            "\(.applicationName), load a set into the calc",
            "Load \(\.$savedSet) into the calc in \(.applicationName)",
        ], shortTitle: "Load Set into Calc", systemImageName: "bolt.fill")
        AppShortcut(intent: SearchPKReferenceIntent(), phrases: [
            "Search in \(.applicationName)",
            "Search \(.applicationName)",
            "\(.applicationName), search the Pokédex",
        ], shortTitle: "Search", systemImageName: "magnifyingglass")
        AppShortcut(intent: FindCountersIntent(), phrases: [
            "\(.applicationName), what beats \(\.$pokemon)",
            "\(.applicationName), what counters \(\.$pokemon)",
            "\(.applicationName), how do I beat \(\.$pokemon)",
            "\(.applicationName), find counters",
            "What beats \(\.$pokemon) in \(.applicationName)",
            "Find counters in \(.applicationName)",
        ], shortTitle: "Find Counters", systemImageName: "scope")
        AppShortcut(intent: ShowTeamIntent(), phrases: [
            "\(.applicationName), show my team \(\.$team)",
            "\(.applicationName), show a saved team",
            "Show my team \(\.$team) in \(.applicationName)",
        ], shortTitle: "Show Saved Team", systemImageName: "person.3")
    }
}

// MARK: - Answers from the store

extension IntentData {
    static func lookup(_ id: Int, in store: ModelContext? = nil) throws -> PokemonLookupAnswer {
        let context = store ?? storeContext
        let stats = try pokemon(id, in: context)
        return PokemonLookupAnswer(
            name: IntentNames.spoken(name: stats.name, formName: stats.formName),
            types: [stats.type1] + [stats.type2].compactMap { $0 },
            baseStats: [stats.baseHP, stats.baseAtk, stats.baseDef, stats.baseSpAtk, stats.baseSpDef, stats.baseSpeed])
    }

    /// The calc's answer, from the same view model the calc screen uses,
    /// with its default field: no weather, terrain or other effects. A side
    /// without a saved set follows the Default Generation setting, as the
    /// calc does, unless `championsMode` says otherwise.
    static func damage(_ request: CalcRequest, championsMode: Bool? = nil,
                       in store: ModelContext? = nil) throws -> DamageAnswer {
        let context = store ?? storeContext
        let vm = DamageCalcVM()
        guard vm.load(request, championsMode: championsMode ?? championsByDefault, context: context),
              let attacker = vm.side1.pokemon, let defender = vm.side2.pokemon,
              let result = vm.side1Results.first else {
            throw IntentError.notFound("those Pokémon, that move, or that saved set")
        }
        return DamageAnswer(
            attacker: vm.side1.activeMegaForm?.displayName
                ?? IntentNames.spoken(name: attacker.name, formName: attacker.formName),
            defender: vm.side2.activeMegaForm?.displayName
                ?? IntentNames.spoken(name: defender.name, formName: defender.formName),
            move: result.move.name,
            minPercent: result.minPercent, maxPercent: result.maxPercent,
            minDamage: Int(result.damageMin), maxDamage: Int(result.damageMax),
            attackerSetup: setup(vm.side1, request.attackerStats),
            defenderSetup: setup(vm.side2, request.defenderStats),
            championsRules: vm.side1.championsMode, survival: result.survival)
    }

    /// "Sand Veil, no investment", "Intimidate, full investment, Adamant
    /// nature", or "Intimidate, your set Screenshot Test".
    private static func setup(_ side: CalcSide, _ choice: StatChoice) -> String {
        let ability = side.effectiveAbility.map(formatAbilityName) ?? "no ability"
        switch choice {
        case .noInvestment: return "\(ability), no investment"
        case .fullInvestment: return "\(ability), full investment"
        case .fullInvestmentBoostingNature: return "\(ability), full investment, \(side.nature.name) nature"
        case .savedSet: return "\(ability), your set \(side.loadedSpreadName ?? "")"
        }
    }

    /// Every Pokémon's keys, as `SearchReading` reads names: species first,
    /// so a key both share names the species.
    static func searchKeys(_ pokemon: [PKMNStats]) -> [String: Int] {
        var keys: [String: Int] = [:]
        for row in pokemon.sorted(by: { !$0.isForm && $1.isForm }) {
            for key in IntentNames.keys(name: row.name, formName: row.formName) where keys[key] == nil {
                keys[key] = row.id
            }
        }
        return keys
    }

    /// A form's names for opening its page on it; nil for a species itself.
    static func form(of stats: PKMNStats) -> AppNavigator.PokemonForm? {
        guard let formName = stats.formName, !formName.isEmpty else { return nil }
        return .init(formName: formName, spokenName: IntentNames.spoken(name: stats.name, formName: formName))
    }

    /// Where a search goes. Text that is just a name opens it: the page of
    /// the Pokémon, on the form or Mega it names, else the Move or Ability
    /// Index on the move or ability. Otherwise the words are read
    /// (`SearchReading`): two Pokémon and a damaging move open the damage
    /// calc on that matchup, the first attacking, each side with the
    /// investment said beside it or none; one Pokémon opens its page; a move
    /// opens the Move Index. Anything else filters the Mon Index. Names
    /// match as Siri says them: case, accents, spaces and punctuation don't
    /// matter.
    static func searchRequest(for text: String, in store: ModelContext? = nil) -> AppNavigator.Request {
        let context = store ?? storeContext
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = IntentNames.key(term)
        guard !wanted.isEmpty else { return .indexSearch(.monIndex, "") }
        let pokemon = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
        if let named = pokemon.first(where: { IntentNames.keys(name: $0.name, formName: $0.formName).contains(wanted) }) {
            return .pokemon(speciesID: named.speciesID, form: form(of: named))
        }
        let moves = (try? context.fetch(FetchDescriptor<MoveData>())) ?? []
        if let move = moves.first(where: { IntentNames.key($0.name) == wanted }) {
            return .indexSearch(.moveIndex, move.name)
        }
        let abilities = Set(pokemon.flatMap(\.allAbilities).map(formatAbilityName))
        if let ability = abilities.first(where: { IntentNames.key($0) == wanted }) {
            return .indexSearch(.abilityIndex, ability)
        }

        let reading = SearchReading(term, pokemon: searchKeys(pokemon), moves: Dictionary(
            moves.map { (IntentNames.key($0.name), $0.id) }, uniquingKeysWith: { first, _ in first }))
        let named = reading.pokemon
        let damaging = reading.moves.first { span in
            moves.first { $0.id == span.id }.map { $0.damageClass != "status" } ?? false
        }
        if named.count >= 2, let move = damaging {
            func stats(_ span: SearchReading.Span) -> StatChoice {
                switch reading.investment(of: span) {
                case .full: .fullInvestment
                case .fullWithNature: .fullInvestmentBoostingNature
                case .uninvested, nil: .noInvestment
                }
            }
            return .calc(CalcRequest(attackerID: named[0].id, attackerStats: stats(named[0]),
                                     defenderID: named[1].id, defenderStats: stats(named[1]),
                                     moveID: move.id))
        }
        if let first = named.first, let row = pokemon.first(where: { $0.id == first.id }) {
            return .pokemon(speciesID: row.speciesID, form: form(of: row))
        }
        if let first = reading.moves.first, let move = moves.first(where: { $0.id == first.id }) {
            return .indexSearch(.moveIndex, move.name)
        }
        return .indexSearch(.monIndex, term)
    }

    /// Whether a Pokémon without a saved set gets Champions rules: the
    /// Default Generation setting, as in the calc and Speed Tiers.
    static var championsByDefault: Bool {
        let defaultGeneration = UserDefaults.standard.string(forKey: AppSettings.defaultGeneration.name)
            ?? AppSettings.defaultGeneration.defaultValue
        return defaultGeneration == PokedexFilter.champions.rawValue
    }

    /// Which of two Pokémon is faster, each loaded as the calc loads a side.
    /// A Pokémon without a saved set follows the Default Generation setting
    /// unless `championsMode` says otherwise.
    static func speed(_ request: SpeedRequest, championsMode: Bool? = nil,
                      in store: ModelContext? = nil) throws -> SpeedAnswer {
        let context = store ?? storeContext
        let allPokemon = try allPokemon(in: context)
        let allMoves = (try? context.fetch(FetchDescriptor<MoveData>())) ?? []
        let mode = championsMode ?? championsByDefault
        let first = CalcSide(), second = CalcSide()
        guard first.load(pokemonID: request.firstID, speed: request.firstStats, championsMode: mode,
                         allPokemon: allPokemon, allMoves: allMoves, context: context),
              second.load(pokemonID: request.secondID, speed: request.secondStats, championsMode: mode,
                          allPokemon: allPokemon, allMoves: allMoves, context: context)
        else {
            throw IntentError.notFound("those Pokémon, or that saved set")
        }
        return SpeedAnswer(first: speedSide(first, request.firstStats),
                           second: speedSide(second, request.secondStats))
    }

    private static func speedSide(_ side: CalcSide, _ choice: SpeedChoice) -> SpeedAnswer.Side {
        let name = side.activeMegaForm?.displayName
            ?? side.pokemon.map { IntentNames.spoken(name: $0.name, formName: $0.formName) } ?? ""
        let setup: String
        switch choice {
        case .noInvestment: setup = "no investment"
        case .fullInvestment: setup = "full investment"
        case .fullInvestmentSpeedNature: setup = "full investment and a Speed nature"
        case .savedSet:
            var parts = ["your set \(side.loadedSpreadName ?? "")"]
            if side.holdsChoiceScarf { parts.append("with Choice Scarf") }
            setup = parts.joined(separator: ", ")
        }
        return SpeedAnswer.Side(name: name, speed: side.speedWithItem, setup: setup,
                                championsRules: side.championsMode)
    }

    /// Whether a Pokémon is in `choice`'s regulation, or the one chosen in
    /// Settings, from the files the validator reads.
    static func legality(_ id: Int, regulation choice: RegulationChoice?, in store: ModelContext? = nil,
                         now: Date = .now) throws -> LegalityAnswer {
        let context = store ?? storeContext
        let regulation = choice.flatMap { ChampionsRegulation(rawValue: $0.rawValue) } ?? .current
        let row = try pokemon(id, in: context)
        let speciesID = row.speciesID
        let baseRow = try allPokemon(in: context).first { $0.speciesID == speciesID && !$0.isForm }
        let dexName = try? context.fetch(FetchDescriptor<PKMN>(
            predicate: #Predicate { $0.nationalPokedexNumber == speciesID })).first?.name

        // The regulation's name for the species, whichever way the Pokédex
        // spells it: "Kommo-O" is its "Kommo-o", "Lycanroc-Midday" its
        // "Lycanroc". Champions' Floette is Eternal Floette, a form in the
        // Pokédex.
        let whitelist = regulation.speciesWhitelist()
        let listed: (String) -> String? = { name in
            whitelist.first { IntentNames.key($0) == IntentNames.key(name) }
        }
        let championsName = ChampionsFormat.canonicalChampionsSpecies(row.name)
        let isChampionsForm = championsName != row.name && listed(championsName) != nil
        let listedSpecies = [championsName, row.name, baseRow?.name, dexName].compactMap { $0 }
            .lazy.compactMap(listed).first

        let species = listedSpecies.flatMap { ChampionsLearnsetStore.store(for: regulation).data(for: $0) }
        let name = IntentNames.spoken(name: row.name, formName: row.formName)
        let verdict = PokemonLegality.verdict(
            formName: isChampionsForm ? nil : row.formName, spokenName: name, listedSpecies: listedSpecies,
            speciesName: baseRow.map { IntentNames.spoken(name: $0.name, formName: nil) } ?? name,
            rules: regulation.rules(),
            listing: species.map { .init(megas: $0.megas.map(\.name), forms: $0.alternateForms.map(\.name)) })
        return LegalityAnswer(
            name: name, regulation: regulation.displayName, verdict: verdict,
            schedule: LegalityAnswer.schedule(regulation: regulation.displayName, from: regulation.validFrom,
                                              until: regulation.validUntil, now: now))
    }

    /// The last search, so a snippet shown right after its answer doesn't
    /// load the tournament data again.
    private static var lastTeamSearch: TeamSearchAnswer?

    static func teamSearch(_ query: String) async throws -> TeamSearchAnswer {
        if let last = lastTeamSearch, last.query == query { return last }
        let model = TeamSearchModel()
        await model.load()
        if case .failed = model.status { throw IntentError.noTournamentData }
        model.setText(query)
        let results = model.results
        let answer = TeamSearchAnswer(
            query: query, compositions: results.count,
            teams: results.reduce(0) { $0 + $1.teams.count },
            top: results.prefix(3).map { .init(species: $0.species, teams: $0.teams.count) })
        lastTeamSearch = answer
        return answer
    }

    /// The last answer, so a snippet shown right after it doesn't solve
    /// again.
    private static var lastCounters: (request: CountersRequest, answer: CountersAnswer)?

    /// What beats a Pokémon, as the Problem Solver finds it in the
    /// regulation chosen in Settings, with tournament usage from Team
    /// Search's cache when it has the teams.
    static func counters(_ request: CountersRequest) async throws -> CountersAnswer {
        if let last = lastCounters, last.request == request { return last.answer }
        let regulation = ChampionsRegulation.current
        let answer = try await counters(request, regulation: regulation,
                                        usage: await cachedUsage(for: regulation), in: storeContext)
        lastCounters = (request, answer)
        return answer
    }

    /// The Problem Solver's answers, one hit, on a plain field, the
    /// Pokémon's own Intimidate applying. The first three Pokémon come in
    /// the screen's order (moving first, then fewest points), with usage
    /// breaking ties: among answers needing nothing, the ones teams bring.
    static func counters(_ request: CountersRequest, regulation: ChampionsRegulation,
                         usage: TournamentUsage?, in context: ModelContext) async throws -> CountersAnswer {
        let target = try counterTarget(request, usage: usage, in: context)
        guard let defender = target.snapshot() else { throw IntentError.notFound("that Pokémon") }
        let problem = ProblemSolver.Problem(defender: defender)
        let candidates = ProblemSolver.candidates(for: regulation, in: context)
        let found = await solveCounters(problem, candidates)

        var shares: [String: Double] = [:]
        if let usage {
            for counter in found where shares[counter.name] == nil { shares[counter.name] = usage.share(of: counter) }
        }
        let ordered = found.enumerated().sorted { a, b in
            (a.element.group, a.element.totalPoints, -(a.element.accuracy ?? 101), a.element.marks.count,
             -(shares[a.element.name] ?? 0), a.offset)
                < (b.element.group, b.element.totalPoints, -(b.element.accuracy ?? 101), b.element.marks.count,
                   -(shares[b.element.name] ?? 0), b.offset)
        }.map(\.element)
        let rows = Dictionary(try allPokemon(in: context).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let top = ProblemSolver.byPokemon(ordered).prefix(3).map { answers in
            let best = answers[0]
            return CountersAnswer.Pick(
                name: best.spokenName(row: rows[best.pokemonID]), types: best.attacker.effectiveTypes, move: best.move.name, item: best.itemName,
                investment: best.spokenInvestment, group: best.group, damage: best.percentLabel, notes: best.notes)
        }

        let name = target.activeMegaForm?.displayName
            ?? target.pokemon.map { IntentNames.spoken(name: $0.name, formName: $0.formName) } ?? ""
        let ability = target.effectiveAbility.map(formatAbilityName)
        let setName = target.loadedSpreadName
        var setup = [ability, request.stats.spoken].compactMap { $0 }
        if setName == nil { setup.append("a neutral nature") }
        return CountersAnswer(
            target: setName.map { "your set \($0)" } ?? [ability, name].compactMap { $0 }.joined(separator: " "),
            setup: setName.map { "\(name): your set \($0)" } ?? "\(name): " + setup.joined(separator: ", "),
            regulation: regulation.displayName,
            pokemonCount: Set(found.map(\.name)).count, wayCount: found.count, top: top,
            survival: problem.survival)
    }

    /// The Pokémon to beat, as Find Counters and the Problem Solver load it.
    static func counterTarget(_ request: CountersRequest) async throws -> CalcSide {
        try counterTarget(request, usage: await cachedUsage(for: .current), in: storeContext)
    }

    static func counterTarget(_ request: CountersRequest, usage: TournamentUsage?,
                              in context: ModelContext) throws -> CalcSide {
        let allPokemon = try allPokemon(in: context)
        let allMoves = (try? context.fetch(FetchDescriptor<MoveData>())) ?? []
        // Without a saved set, the ability tournament teams run most.
        let row = allPokemon.first { $0.id == request.pokemonID }
        let said = row.flatMap { usage?.mostUsedAbility(of: $0.name) }.map(IntentNames.key)
        let ability = said.flatMap { said in
            row?.allAbilities.first { IntentNames.key(formatAbilityName($0)) == said }
        }
        let side = CalcSide()
        guard side.load(pokemonID: request.pokemonID, target: request.stats, ability: ability,
                        allPokemon: allPokemon, allMoves: allMoves, context: context) else {
            throw IntentError.notFound("that Pokémon, or that saved set")
        }
        return side
    }

    /// Tournament usage from the teams Team Search has cached; nil without
    /// them. Never touches the network.
    static func cachedUsage(for regulation: ChampionsRegulation) async -> TournamentUsage? {
        guard let corpus = await TeamCorpusStore.shared.cachedCorpus(format: regulation.limitlessFormat),
              !corpus.teams.isEmpty,
              let vocabulary = try? TeamSearchVocabulary.bundled(for: regulation) else { return nil }
        return await usage(corpus, vocabulary)
    }

    @concurrent
    nonisolated private static func usage(_ corpus: TeamCorpus,
                                          _ vocabulary: TeamSearchVocabulary) async -> TournamentUsage {
        TournamentUsage(corpus: corpus, vocabulary: vocabulary)
    }

    @concurrent
    nonisolated private static func solveCounters(_ problem: ProblemSolver.Problem,
                                                  _ candidates: [ProblemSolver.Candidate]) async -> [ProblemSolver.Counter] {
        ProblemSolver.solve(problem, candidates: candidates)
    }
}

extension TargetStats {
    /// "full HP and Defense"; nil for a saved set, which says its own name.
    var spoken: String? {
        switch self {
        case .noInvestment: "no investment"
        case .physicallyBulky: "full HP and Defense"
        case .speciallyBulky: "full HP and Special Defense"
        case .savedSet: nil
        }
    }
}

extension ProblemSolver.Counter {
    /// As people say it, given its Pokédex row: "Alolan Ninetales", not
    /// "Ninetales-Alola"; a Mega by its own name.
    func spokenName(row: PKMNStats?) -> String {
        attacker.megaForm?.displayName
            ?? row.map { IntentNames.spoken(name: $0.name, formName: $0.formName) } ?? name
    }

    /// "no investment", "12 Attack points", or "12 Special Attack and 20
    /// Speed points".
    var spokenInvestment: String {
        var parts: [String] = []
        if let attackStat, attackPoints > 0 { parts.append("\(attackPoints) \(attackStat.spoken)") }
        if let speedPoints, speedPoints > 0 { parts.append("\(speedPoints) Speed") }
        return parts.isEmpty ? "no investment" : parts.joined(separator: " and ") + " points"
    }
}

extension EVSolver.Stat {
    /// "Special Attack".
    var spoken: String {
        switch self {
        case .hp: "HP"
        case .atk: "Attack"
        case .def: "Defense"
        case .spAtk: "Special Attack"
        case .spDef: "Special Defense"
        case .speed: "Speed"
        }
    }
}
