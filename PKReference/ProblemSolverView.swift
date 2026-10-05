//
//  ProblemSolverView.swift
//  PKReference
//
//  The Problem Solver tab: the set to beat, edited like a side of the calc,
//  and the Pokémon, moves and investments that knock it out in one hit or
//  two, guaranteed, under Champions doubles rules (`ProblemSolver`). Each
//  answer opens in the damage calc exactly as solved, or saves as a set.
//  HANDOFF.md's feature notes have the owner's decisions.
//

import SwiftUI
import SwiftData

// MARK: - Solving

/// Runs the solver for the screen: off the main thread, with the
/// candidates built once per regulation. A new solve cancels the last.
/// Two-hit answers show as soon as the fast check has them, then the
/// battle simulator re-checks the ones it needs to, on the main actor
/// (its damage goes through `DamageCalcVM`). Tournament usage comes from
/// Team Search's Limitless teams.
@MainActor @Observable
final class ProblemSolverModel {
    enum Status: Equatable {
        /// No Pokémon to beat yet.
        case waiting
        case solving
        case solved
    }

    private(set) var status: Status = .waiting
    private(set) var counters: [ProblemSolver.Counter] = []
    private(set) var candidateCount = 0
    /// The battle simulator's progress through the two-hit answers it's
    /// re-checking; nil when it isn't.
    private(set) var simulating: (done: Int, of: Int)?
    private var candidates: [ChampionsRegulation: [ProblemSolver.Candidate]] = [:]

    enum UsageStatus: Equatable {
        case idle
        /// Fetching the regulation's tournament teams from Limitless.
        case loading(completed: Int, total: Int)
        case failed(String)
    }

    /// How often each Pokémon is brought to tournaments in the regulation;
    /// nil until loaded.
    private(set) var usage: TournamentUsage?
    private(set) var usageStatus: UsageStatus = .idle
    private var usageRegulation: ChampionsRegulation?
    private let corpusStore: TeamCorpusStore

    init(corpusStore: TeamCorpusStore = .shared) {
        self.corpusStore = corpusStore
    }

    /// Tournament usage for `regulation`, from the teams Team Search has
    /// cached. With `download`, the teams are fetched from Limitless when
    /// none are cached.
    func loadUsage(for regulation: ChampionsRegulation, download: Bool) async {
        if usageRegulation != regulation {
            (usage, usageRegulation, usageStatus) = (nil, regulation, .idle)
        }
        guard usage == nil else { return }
        var corpus = await corpusStore.cachedCorpus(format: regulation.limitlessFormat)
        if corpus?.teams.isEmpty ?? true {
            guard download else { return }
            usageStatus = .loading(completed: 0, total: 0)
            do {
                corpus = try await corpusStore.corpus(for: regulation) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, case .loading = self.usageStatus else { return }
                        self.usageStatus = .loading(completed: progress.completed, total: progress.total)
                    }
                }
            } catch {
                guard usageRegulation == regulation else { return }
                usageStatus = Task.isCancelled ? .idle : .failed(error.localizedDescription)
                return
            }
        }
        guard usageRegulation == regulation, !Task.isCancelled else { return }
        guard let corpus, !corpus.teams.isEmpty else {
            usageStatus = .failed("Limitless has no published teams for \(regulation.displayName) yet.")
            return
        }
        guard let vocabulary = try? TeamSearchVocabulary.bundled(for: regulation) else {
            usageStatus = .failed("The Team Search data for \(regulation.displayName) didn't load.")
            return
        }
        let loaded = await Self.usage(corpus, vocabulary)
        guard usageRegulation == regulation else { return }
        (usage, usageStatus) = (loaded, .idle)
    }

    @concurrent
    nonisolated private static func usage(_ corpus: TeamCorpus,
                                          _ vocabulary: TeamSearchVocabulary) async -> TournamentUsage {
        TournamentUsage(corpus: corpus, vocabulary: vocabulary)
    }

    /// `target` is the set to beat as the simulator loads it.
    func solve(_ problem: ProblemSolver.Problem?, target: SideSetup?, regulation: ChampionsRegulation,
               context: ModelContext) async {
        simulating = nil
        guard let problem else {
            status = .waiting
            counters = []
            return
        }
        status = .solving
        let list = candidates[regulation] ?? ProblemSolver.candidates(for: regulation, in: context)
        candidates[regulation] = list
        candidateCount = list.count
        let found = await Self.run(problem, list)
        guard !Task.isCancelled else { return }
        counters = found
        status = .solved
        if let target { await simulate(problem, target: target, context: context) }
    }

    /// Re-checks the answers that need it, then puts them back in order,
    /// without any the simulator found can't do it.
    private func simulate(_ problem: ProblemSolver.Problem, target: SideSetup, context: ModelContext) async {
        let pending = counters.indices.filter { ProblemSolver.needsSimulation(counters[$0], problem) }
        guard !pending.isEmpty else { return }
        let allPokemon = (try? context.fetch(FetchDescriptor<PKMNStats>())) ?? []
        let allMoves = (try? context.fetch(FetchDescriptor<MoveData>())) ?? []
        let moves = Dictionary(allMoves.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let vm = DamageCalcVM()
        vm.multi = true
        vm.weather = problem.field.weather
        vm.terrain = problem.field.terrain
        guard target.apply(to: vm.side2, allPokemon: allPokemon, allMoves: allMoves) else { return }

        var checked: [ProblemSolver.Counter?] = counters
        simulating = (0, pending.count)
        // Yielding after every answer costs a pass of the run loop each
        // time, which was most of the work; a slice of work a frame keeps
        // the screen live at a fraction of that.
        var slice = ContinuousClock.now
        for (done, index) in pending.enumerated() {
            if ContinuousClock.now - slice > .milliseconds(25) {
                simulating = (done, pending.count)
                await Task.yield()
                guard !Task.isCancelled else { return }
                slice = .now
            }
            guard let counter = checked[index], let move = moves[counter.move.id] else { continue }
            checked[index] = ProblemSolver.simulated(counter, problem, vm: vm, move: move,
                                                     allPokemon: allPokemon, allMoves: allMoves)
        }
        counters = ProblemSolver.sorted(checked.compactMap { $0 })
        simulating = nil
    }

    @concurrent
    nonisolated private static func run(_ problem: ProblemSolver.Problem,
                                        _ candidates: [ProblemSolver.Candidate]) async -> [ProblemSolver.Counter] {
        ProblemSolver.solve(problem, candidates: candidates, isCancelled: { Task.isCancelled })
    }
}

// MARK: - Screen

struct ProblemSolverView: View {
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]
    @AppStorage(ChampionsRegulation.userDefaultsKey) private var regulationRaw = ChampionsRegulation.latest.rawValue
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var problem = ProblemSolverView.newProblem()
    @State private var model = ProblemSolverModel()
    @State private var intimidate = true
    @State private var weather: WeatherCondition = .none
    @State private var terrain: TerrainCondition = .none
    @State private var helpingHand = false
    @State private var tailwind = false
    @State private var trickRoom = false
    @State private var twoHits = false
    /// Wide layouts show the chosen answer above the list.
    @State private var selected: ProblemSolver.Counter?

    private var regulation: ChampionsRegulation { ChampionsRegulation(rawValue: regulationRaw) ?? .current }

    /// A Pokémon to beat starts on Champions rules, like the rest of the
    /// screen.
    static func newProblem() -> CalcSide {
        let side = CalcSide()
        side.setChampionsMode(true)
        return side
    }

    /// The set to beat on the field chosen; nil without a Pokémon.
    private var rules: ProblemSolver.Problem? {
        problem.snapshot().map {
            ProblemSolver.Problem(defender: $0, intimidate: intimidate, weather: weather, terrain: terrain,
                                  helpingHand: helpingHand, tailwind: tailwind, trickRoom: trickRoom,
                                  twoHits: twoHits)
        }
    }

    private struct SolveKey: Equatable {
        let problem: CalcSnapshot?
        let intimidate, helpingHand, tailwind, trickRoom, twoHits: Bool
        let weather: WeatherCondition
        let terrain: TerrainCondition
        let regulation: ChampionsRegulation
    }

    private var solveKey: SolveKey {
        SolveKey(problem: problem.snapshot(), intimidate: intimidate, helpingHand: helpingHand,
                 tailwind: tailwind, trickRoom: trickRoom, twoHits: twoHits, weather: weather, terrain: terrain,
                 regulation: regulation)
    }

    var body: some View {
        TabNavigationStack {
            ScrollView {
                Group {
                    if allPokemon.isEmpty {
                        SectionCard(title: "Problem Solver", icon: "scope") {
                            Text("Downloading Pokémon and move data. This only happens once.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else if hSize == .regular {
                        HStack(alignment: .top, spacing: 16) {
                            CardStack {
                                problemCard
                                rulesCard
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            CardStack {
                                if let selected {
                                    CounterDetailCard(counter: selected, problem: problem, rules: rules,
                                                      usage: model.usage)
                                }
                                resultsCard(wide: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    } else {
                        CardStack {
                            problemCard
                            rulesCard
                            resultsCard(wide: false)
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Problem Solver")
            .cardPage()
            .navigationDestination(for: ProblemSolver.Counter.self) { counter in
                ScrollView {
                    CardStack {
                        CounterDetailCard(counter: counter, problem: problem, rules: rules, usage: model.usage)
                    }
                        .padding()
                }
                .navigationTitle(counter.name)
                .cardPage()
            }
            .task(id: solveKey) {
                // Let a burst of edits settle before searching.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await model.solve(rules, target: SideSetup(problem), regulation: regulation, context: modelContext)
            }
            .onChange(of: model.counters) {
                // The simulator may have changed or dropped the answer showing.
                if let selected { self.selected = model.counters.first { $0.id == selected.id } }
                #if DEBUG && os(macOS)
                // `-debugOpenFirst YES`: show the first answer, for snapshots.
                if selected == nil, UserDefaults.standard.bool(forKey: "debugOpenFirst") {
                    selected = model.counters.first
                }
                #endif
            }
            #if DEBUG
            // `-debugTwoHits YES`: start in two-hit mode, for snapshots.
            .onAppear { if UserDefaults.standard.bool(forKey: "debugTwoHits") { twoHits = true } }
            #endif
            .onChange(of: problem.championsMode) {
                // The solver works on Champions rules only.
                if !problem.championsMode { problem.setChampionsMode(true) }
            }
            .onChange(of: AppNavigator.shared.request, initial: true) { openRequestedProblem() }
        }
    }

    /// Loads the set an App Intent or launch argument asked to beat.
    private func openRequestedProblem() {
        guard case .problemSolver(let setup) = AppNavigator.shared.request else { return }
        AppNavigator.shared.request = nil
        let side = Self.newProblem()
        if setup.apply(to: side, allPokemon: allPokemon, allMoves: allMoves) {
            problem = side
            selected = nil
        }
    }

    private var problemCard: some View {
        SideCard(title: "Problem", role: .side2, side: problem, allPokemon: allPokemon, allMoves: allMoves,
                 icon: "target")
    }

    private var rulesCard: some View {
        SectionCard(title: "Rules", icon: "list.bullet.clipboard") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Knock out in").font(.subheadline).foregroundStyle(.secondary)
                Picker("Knock out in", selection: $twoHits) {
                    Text("One hit").tag(false)
                    Text("Two hits").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Text(twoHits
                 ? "\(regulation.displayName), doubles: spread moves do 0.75×. Only guaranteed two-hit KOs count: the same move on two turns running, from the lowest damage rolls, allowing for what happens between them (Sitrus Berry, Leftovers, Multiscale)."
                 : "\(regulation.displayName), doubles: spread moves do 0.75×. Only guaranteed one-hit KOs count, from the lowest damage roll.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if problem.selectedAbility == "intimidate" {
                Toggle("Its Intimidate lowers the counters' Attack", isOn: $intimidate)
                    .font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Weather").font(.subheadline).foregroundStyle(.secondary)
                Picker("Weather", selection: $weather) {
                    ForEach(WeatherCondition.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Terrain").font(.subheadline).foregroundStyle(.secondary)
                Picker("Terrain", selection: $terrain) {
                    ForEach(TerrainCondition.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if rules?.blocksPriority == true {
                    Text("Psychic Terrain stops priority moves hitting \(problem.effectiveDisplayName).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("Helping Hand from a partner", isOn: $helpingHand).font(.subheadline)
            Toggle("Tailwind on your side", isOn: $tailwind).font(.subheadline)
            Toggle("Trick Room", isOn: $trickRoom).font(.subheadline)
        }
    }

    private func resultsCard(wide: Bool) -> some View {
        CountersCard(model: model, problemName: problem.effectiveDisplayName,
                     regulation: regulation, trickRoom: trickRoom, twoHits: twoHits,
                     survival: rules?.survival, wide: wide, selected: $selected)
    }
}

// MARK: - Results

private enum CounterSort: String, CaseIterable, Identifiable {
    case fewestPoints = "Fewest points"
    case mostUsed = "Most used"

    var id: Self { self }
}

private struct CountersCard: View {
    let model: ProblemSolverModel
    let problemName: String
    let regulation: ChampionsRegulation
    let trickRoom: Bool
    let twoHits: Bool
    /// The target's Sturdy, Focus Sash or Disguise, which only some answers
    /// get past in one hit.
    let survival: SurvivalEffect?
    let wide: Bool
    @Binding var selected: ProblemSolver.Counter?

    @State private var filter = ""
    @State private var sort: CounterSort = .fewestPoints
    @State private var showingAll: Set<ProblemSolver.Group> = []
    /// Pokémon whose other answers are showing.
    @State private var expanded: Set<String> = []

    private static let firstShown = 25

    /// In the order chosen, then filtered. Until usage loads, "Most used"
    /// keeps the fewest-points order.
    private var shown: [ProblemSolver.Counter] {
        let ordered = sort == .mostUsed ? model.usage?.sorted(model.counters) ?? model.counters : model.counters
        return ordered.filter { $0.matches(filter: filter) }
    }

    private struct UsageRequest: Equatable {
        let regulation: ChampionsRegulation
        let download: Bool
    }

    var body: some View {
        SectionCard(title: "Counters", icon: "scope") {
            switch model.status {
            case .waiting:
                Text("Choose the Pokémon to beat.")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .solving:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Checking \(model.candidateCount.formatted()) Pokémon, abilities and moves…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            case .solved:
                SimulatorProgress(model: model)
                if let survival, !twoHits {
                    Label(Self.survivalNote(survival, problemName), systemImage: "shield.lefthalf.filled")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.counters.isEmpty {
                    Text("Nothing in \(regulation.displayName) knocks out \(problemName) in \(hitsPhrase), guaranteed.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    results
                }
            }
        }
        // Usage shows on the rows whenever Team Search has the teams;
        // "Most used" fetches them when it doesn't.
        .task(id: UsageRequest(regulation: regulation, download: sort == .mostUsed)) {
            await model.loadUsage(for: regulation, download: sort == .mostUsed)
        }
    }

    @ViewBuilder
    private var usageNote: some View {
        switch model.usageStatus {
        case .loading(let completed, let total):
            HStack(spacing: 8) {
                ProgressView()
                Text(total > 0 ? "Loading tournament teams from Limitless… \(completed) of \(total) events"
                               : "Loading tournament teams from Limitless…")
            }
            .font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text("Couldn't load tournament usage. \(message)")
                .font(.caption).foregroundStyle(.secondary)
        case .idle:
            if let usage = model.usage {
                Text("Usage: the share of \(usage.teamCount.formatted()) teams from \(usage.eventCount.formatted()) Limitless events that bring each Pokémon.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        let pokemon = Set(model.counters.map(\.name)).count
        Text("\(pokemon.formatted()) Pokémon can knock out \(problemName) in \(hitsPhrase), \(model.counters.count.formatted()) ways.")
            .font(.subheadline).foregroundStyle(.secondary)
        TextField("Filter by Pokémon, move or ability", text: $filter)
            .textFieldStyle(.roundedBorder)
        Picker("Sort", selection: $sort) {
            ForEach(CounterSort.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        usageNote
        let counters = shown
        if counters.isEmpty {
            Text("No answers match “\(filter)”.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        ForEach(ProblemSolver.Group.allCases, id: \.self) { group in
            let members = ProblemSolver.byPokemon(counters.filter { $0.group == group })
            if !members.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.title(trickRoom: trickRoom, twoHits: twoHits)).font(.headline)
                        Spacer()
                        Text("\(members.count) Pokémon").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(group.explanation(problemName, trickRoom: trickRoom, twoHits: twoHits))
                        .font(.caption).foregroundStyle(.secondary)
                    let shown = showingAll.contains(group) ? members : Array(members.prefix(Self.firstShown))
                    ForEach(shown, id: \.first!.id) { answers in
                        pokemonRows(answers)
                    }
                    if shown.count < members.count {
                        Button("Show all \(members.count)") { showingAll.insert(group) }
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var hitsPhrase: String { twoHits ? "two hits" : "one hit" }

    /// Why one hit isn't enough, and what gets through.
    static func survivalNote(_ survival: SurvivalEffect, _ name: String) -> String {
        switch survival {
        case .focusSash:
            "Focus Sash: from full HP, \(name) lives through any one hit with 1 HP. Only moves that hit more than once get past it here; Two hits shows the rest."
        case .sturdy:
            "Sturdy: from full HP, \(name) lives through any one hit with 1 HP. Only moves that hit more than once, and Mold Breaker or its like, get past it here; Two hits shows the rest."
        case .disguise:
            "Disguise: \(name)'s first hit is blocked. Only Mold Breaker or its like gets past it here; Two hits shows the rest."
        }
    }

    /// A Pokémon's best answer, then its others when opened.
    @ViewBuilder
    private func pokemonRows(_ answers: [ProblemSolver.Counter]) -> some View {
        let best = answers[0]
        row(best)
        if answers.count > 1 {
            let open = expanded.contains(best.name)
            if open {
                ForEach(answers.dropFirst()) { row($0).padding(.leading, 12) }
            }
            Button {
                if open { expanded.remove(best.name) } else { expanded.insert(best.name) }
            } label: {
                Text(open ? "Fewer" : "\(answers.count - 1) more: \(answers.dropFirst().map(\.move.name).joined(separator: ", "))")
                    .font(.caption)
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .padding(.leading, 12)
        }
    }

    @ViewBuilder
    private func row(_ counter: ProblemSolver.Counter) -> some View {
        if wide {
            Button { selected = counter } label: {
                CounterRow(counter: counter, ability: counter.abilityMatching(filter: filter),
                           usage: model.usage?.share(of: counter))
                    .padding(6)
                    .background(selected?.id == counter.id ? Color.accentColor.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: counter) {
                CounterRow(counter: counter, ability: counter.abilityMatching(filter: filter),
                           usage: model.usage?.share(of: counter))
            }
                .buttonStyle(.plain)
        }
    }
}

/// Its own view, so each step of the simulator's progress redraws the bar
/// and not the list.
private struct SimulatorProgress: View {
    let model: ProblemSolverModel

    var body: some View {
        if let progress = model.simulating {
            VStack(alignment: .leading, spacing: 4) {
                Text("Checking \(progress.of.formatted()) answers in the battle simulator…")
                    .font(.subheadline).foregroundStyle(.secondary)
                ProgressView(value: Double(progress.done), total: Double(max(progress.of, 1)))
            }
        }
    }
}

private struct CounterRow: View {
    let counter: ProblemSolver.Counter
    /// The ability the filter found it by, shown with the move.
    var ability: String? = nil
    /// The share of tournament teams with this Pokémon, when loaded.
    var usage: Double? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                // The badges wrap under a long name rather than splitting it.
                FlowLayout(spacing: 4) {
                    Text(counter.name).font(.subheadline.bold()).fixedSize()
                    ForEach(counter.attacker.effectiveTypes, id: \.self) { TypeBadge(type: $0) }
                }
                Text(([counter.move.name, counter.itemName] + [ability.map(formatAbilityName)].compactMap { $0 })
                        .joined(separator: " · "))
                    .font(.caption)
                Text(counter.pointsLabel)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if !counter.notes.isEmpty {
                    Text(counter.notes.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(counter.percentLabel)
                    .font(.caption.monospacedDigit())
                if counter.group != .priority {
                    Text("Spe \(counter.speed)")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let usage {
                    Text("Usage \(TournamentUsage.percent(usage))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

private struct CounterDetailCard: View {
    let counter: ProblemSolver.Counter
    let problem: CalcSide
    /// The field it was solved on.
    let rules: ProblemSolver.Problem?
    var usage: TournamentUsage? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var naming = false
    @State private var setName = ""
    @State private var saved = false

    var body: some View {
        SectionCard(title: counter.name, icon: "scope", types: counter.attacker.effectiveTypes) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(counter.move.name).font(.headline)
                    TypeBadge(type: counter.move.type)
                    DamageClassBadge(damageClass: counter.move.damageClass)
                }
                detail("Item", counter.itemName)
                detail(counter.abilities.count > 1 ? "Abilities" : "Ability",
                       counter.abilities.map(formatAbilityName).joined(separator: " or "))
                detail("Nature", counter.attacker.nature.name)
                detail("Stat points", counter.pointsLabel)
                if counter.attacker.atkStage != 0 || counter.attacker.spAtkStage != 0 {
                    detail("After Intimidate", counter.stagesLabel)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(counter.damageSummary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if let rules, counter.twoHits != nil {
                    ForEach(counter.twoHitNotes(rules, targetName: problem.effectiveDisplayName), id: \.self) { note in
                        Text(note).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(counter.speedLabel(against: ProblemSolver.speed(problemSnapshot, fieldSnapshot),
                                        problemName: problem.effectiveDisplayName,
                                        trickRoom: rules?.trickRoom ?? false))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let usage {
                    Text("On \(TournamentUsage.percent(usage.share(of: counter))) of \(usage.teamCount.formatted()) tournament teams on Limitless.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(counter.notes, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            Divider()
            HStack {
                Button {
                    guard let defender = SideSetup(problem) else { return }
                    AppNavigator.shared.request = .calcSides(CalcSides(
                        attacker: SideSetup(counter.attacker, pokemonID: counter.pokemonID),
                        defender: defender, doubles: true,
                        weather: fieldSnapshot.weather, terrain: fieldSnapshot.terrain))
                } label: {
                    Label("Open in Damage Calc", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                }
                Button {
                    setName = "\(counter.name) vs \(problem.effectiveDisplayName)"
                    naming = true
                } label: {
                    Label(saved ? "Saved" : "Save as Set", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .disabled(saved)
            }
            .buttonStyle(.bordered)
        }
        .alert("Save as Set", isPresented: $naming) {
            TextField("Name", text: $setName)
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: counter.id) { saved = false }
    }

    private var problemSnapshot: CalcSnapshot {
        problem.snapshot() ?? counter.attacker
    }

    private var fieldSnapshot: FieldSnapshot {
        rules?.field ?? ProblemSolver.Problem(defender: problemSnapshot).field
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value).font(.subheadline)
        }
    }

    private func save() {
        let name = setName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(counter.savedSpread(named: name))
        saved = true
    }
}

// MARK: - Wording

extension ProblemSolver.Group {
    func title(trickRoom: Bool, twoHits: Bool = false) -> String {
        let ko = twoHits ? "2HKOs" : "OHKOs"
        return switch self {
        case .outspeeds: trickRoom ? "Moves first in Trick Room, and \(ko)" : "Outspeeds and \(ko)"
        case .priority: "\(ko) with priority"
        case .slower: trickRoom ? "\(ko) but moves later" : "\(ko) but slower"
        }
    }

    func explanation(_ problemName: String, trickRoom: Bool, twoHits: Bool = false) -> String {
        switch self {
        case .outspeeds where twoHits && trickRoom:
            "Slower than \(problemName), so under Trick Room it hits first on both turns."
        case .outspeeds where twoHits: "Faster than \(problemName), so it hits first on both turns."
        case .outspeeds where trickRoom:
            "Slower than \(problemName), so under Trick Room it knocks it out before it moves."
        case .outspeeds: "Faster than \(problemName), so it knocks it out before it moves."
        case .priority: "A priority move goes first, whatever the Speeds."
        case .slower where twoHits && trickRoom: "Too fast for Trick Room: \(problemName) moves first each turn."
        case .slower where twoHits: "\(problemName) moves first each turn, unless Trick Room or Tailwind turns it around."
        case .slower where trickRoom: "Too fast for Trick Room: it needs a switch-in to land the hit."
        case .slower: "Needs Trick Room, Tailwind or a switch-in to land the hit."
        }
    }
}

extension ProblemSolver.Counter {
    /// Whether the results filter finds this answer by its Pokémon, move or
    /// one of its abilities, ignoring case, accents and punctuation ("speed
    /// boost" finds Speed Boost).
    func matches(filter: String) -> Bool {
        let wanted = IntentNames.key(filter)
        return wanted.isEmpty || IntentNames.key(name).contains(wanted)
            || IntentNames.key(move.name).contains(wanted) || abilityMatching(filter: filter) != nil
    }

    /// The ability the filter names, when that's what finds this answer
    /// rather than its Pokémon or move.
    func abilityMatching(filter: String) -> String? {
        let wanted = IntentNames.key(filter)
        guard !wanted.isEmpty, !IntentNames.key(name).contains(wanted),
              !IntentNames.key(move.name).contains(wanted) else { return nil }
        return abilities.first { IntentNames.key($0).contains(wanted) }
    }

    /// The item held: the move's booster, Choice Scarf, or a Mega's stone.
    var itemName: String {
        attacker.heldItem == .none ? "No item" : attacker.heldItem.rawValue
    }

    /// "28 SpA / 20 Spe", or "No investment needed".
    var pointsLabel: String {
        var parts: [String] = []
        if let attackStat, attackPoints > 0 { parts.append("\(attackPoints) \(attackStat.short)") }
        if let speedPoints, speedPoints > 0 { parts.append("\(speedPoints) Spe") }
        return parts.isEmpty ? "No investment needed" : parts.joined(separator: " / ")
    }

    /// "112.4% – 132.7%": the first hit, in two-hit mode.
    var percentLabel: String { Self.percentLabel(outcome) }

    private static func percentLabel(_ outcome: CalcOutcome) -> String {
        let hp = Double(max(outcome.defenderHP, 1))
        return "\(DamageAnswer.percent(outcome.damageMin / hp * 100)) – \(DamageAnswer.percent(outcome.damageMax / hp * 100))"
    }

    /// "218–258 damage (107.9% – 127.7%) of 202 HP: a guaranteed one-hit
    /// KO.", or both hits.
    var damageSummary: String {
        func range(_ hit: CalcOutcome) -> String {
            "\(Int(hit.damageMin))–\(Int(hit.damageMax)) damage (\(Self.percentLabel(hit)))"
        }
        guard let twoHits else {
            return "\(range(outcome)) of \(outcome.defenderHP) HP: a guaranteed one-hit KO."
        }
        let same = (twoHits.second.damageMin, twoHits.second.damageMax) == (twoHits.first.damageMin, twoHits.first.damageMax)
        let hits = same
            ? "Two hits of \(range(twoHits.first)) each"
            : "A first hit of \(range(twoHits.first)), then \(range(twoHits.second))"
        return "\(hits), of \(outcome.defenderHP) HP: a guaranteed two-hit KO."
    }

    /// What a two-hit answer allows for between the hits, and whether the
    /// battle simulator checked it.
    @MainActor
    func twoHitNotes(_ problem: ProblemSolver.Problem, targetName: String) -> [String] {
        let target = problem.defender
        let item = target.effectiveHeldItem
        var effects: [String] = []
        let survival = CalcEngine.oneHitSurvival(move: move, attacker: attacker, defender: target, field: problem.field)
        if let survival { effects.append("\(targetName)'s \(survival.rawValue)") }
        if [.sitrusBerry, .oranBerry, .leftovers].contains(item)
            || typeResistBerryMap[item] == move.type || item == .chilanBerry && move.type == "Normal" {
            effects.append("\(targetName)'s \(item.rawValue)")
        }
        if let ability = target.effectiveAbility, ProblemSolver.betweenHitAbilities.contains(ability),
           survival != .disguise {
            effects.append("\(targetName)'s \(formatAbilityName(ability))")
        }
        if problem.field.terrain == .grassy, problem.targetIsGrounded { effects.append("Grassy Terrain healing it") }
        if !ProblemSolver.selfStatChanges(for: move.name).isEmpty { effects.append("\(move.name) lowering its user's stats") }
        if BattleSimSeed.normalize(move.name) == "knockoff", item != .none { effects.append("Knock Off taking its item") }
        guard !effects.isEmpty else { return [] }

        var notes = ["Allows for \(effects.joined(separator: " and "))."]
        if simulated {
            notes.append("Checked in the battle simulator.")
        } else if problem.helpingHand {
            notes.append("Not checked in the battle simulator, which doesn't model Helping Hand.")
        }
        return notes
    }

    /// "Atk -1" or "Atk +1, SpA +2".
    var stagesLabel: String {
        [("Atk", attacker.atkStage), ("SpA", attacker.spAtkStage), ("Spe", attacker.speedStage)]
            .filter { $0.1 != 0 }
            .map { "\($0.0) \($0.1 > 0 ? "+" : "")\($0.1)" }
            .joined(separator: ", ")
    }

    func speedLabel(against target: Int, problemName: String, trickRoom: Bool = false) -> String {
        switch group {
        case .outspeeds where trickRoom:
            "Speed \(speed), slower than \(problemName)'s \(target), so it moves first in Trick Room."
        case .outspeeds: "Speed \(speed), faster than \(problemName)'s \(target)."
        case .priority: "\(move.name) has priority, so Speed doesn't matter."
        case .slower where marks.contains(.movesLast): "\(move.name) moves last, whatever the Speeds."
        case .slower where trickRoom:
            "Speed \(speed), not slower than \(problemName)'s \(target), so it moves later in Trick Room."
        case .slower: "Speed \(speed), slower than \(problemName)'s \(target)."
        }
    }

    /// Accuracy under 100% and each mark, as the results say them.
    var notes: [String] {
        var notes: [String] = []
        if let accuracy, accuracy < 100 { notes.append("\(accuracy)% accurate") }
        let order: [(ProblemSolver.Mark, String)] = [
            (.mustRecharge, "Must recharge"), (.faintsUser, "Faints the user"), (.chargesFirst, "Charges first"),
            (.firstTurnOnly, "First turn only"), (.failsIfHit, "Fails if hit first"), (.movesLast, "Moves last"),
            (.speedTie, "Can only tie on Speed"),
        ]
        notes += order.filter { marks.contains($0.0) }.map(\.1)
        for case .getsPast(let effect) in marks { notes.append("Gets past \(effect.rawValue)") }
        return notes
    }

    /// This answer as a saved set: its Pokémon, ability, item, nature,
    /// points and move, on Champions rules.
    func savedSpread(named name: String) -> SavedSpread {
        SavedSpread(
            name: name, pokemonID: pokemonID, pokemonName: attacker.species.name,
            abilityName: attacker.selectedAbility,
            itemRawValue: attacker.heldItem == .none ? nil : attacker.heldItem.rawValue,
            championsMode: attacker.championsMode, natureID: attacker.nature.id, level: attacker.level,
            evHP: attacker.evHP, evAtk: attacker.evAtk, evDef: attacker.evDef,
            evSpAtk: attacker.evSpAtk, evSpDef: attacker.evSpDef, evSpeed: attacker.evSpeed,
            moveID1: move.id)
    }
}

extension EVSolver.Stat {
    var short: String {
        switch self {
        case .hp: "HP"
        case .atk: "Atk"
        case .def: "Def"
        case .spAtk: "SpA"
        case .spDef: "SpD"
        case .speed: "Spe"
        }
    }
}
