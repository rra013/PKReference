//
//  TeamSearchModel.swift
//  PKReference
//
//  State behind the Team Search tab. It loads the regulation's vocabulary
//  and tournament corpus, indexes the corpus, parses what the user types,
//  and runs the search. Cached teams show at once; a refresh then runs in
//  the background. The slow parts (JSON loading, indexing) run off the main
//  actor. Parsing and searching take a few milliseconds.
//
//  The parsed query shows as chips the user can edit: remove one, or flip
//  it between "include" and "exclude". Edits apply until the text changes
//  and is parsed again.
//
//  Smogon's ladder usage stats load alongside, for "often paired with"
//  suggestions and usage figures. They're optional: if they can't load,
//  search works as before.
//
//  When the parser leaves words it can't place, Apple Intelligence can
//  read them, if the device has it. What it adds is marked on its chips,
//  and kept until the text changes.
//

import Foundation
import Observation

@MainActor @Observable
final class TeamSearchModel {

    enum Status: Equatable {
        case idle
        /// First load, with nothing cached to show yet.
        case loading(completed: Int, total: Int)
        case ready
        case failed(String)
    }

    /// One thing the parser understood, or didn't, shown as a chip.
    enum Chip: Identifiable, Equatable {
        case species(SpeciesTerm, excluded: Bool)
        case move(MoveTerm, excluded: Bool)
        case style(TeamArchetype, excluded: Bool)
        case correction(TeamQuery.Correction)
        case unrecognized(String)

        var id: String {
            switch self {
            case .species(let term, let excluded): return "species|\(excluded)|\(term.displayName)"
            case .move(let term, let excluded): return "move|\(excluded)|\(term.id)"
            case .style(let style, let excluded): return "style|\(excluded)|\(style.id)"
            case .correction(let correction): return "correction|\(correction.typed)"
            case .unrecognized(let word): return "unrecognized|\(word)"
            }
        }

        var label: String {
            switch self {
            case .species(let term, let excluded): return (excluded ? "No " : "") + term.displayName
            case .move(let term, let excluded): return (excluded ? "No " : "") + term.name
            case .style(let style, let excluded): return (excluded ? "No " : "") + style.label
            case .correction(let correction): return "\(correction.typed) → \(correction.interpreted)"
            case .unrecognized(let word): return word
            }
        }

        var isExcluded: Bool {
            switch self {
            case .species(_, let excluded), .move(_, let excluded), .style(_, let excluded):
                return excluded
            case .correction, .unrecognized:
                return false
            }
        }

        /// Species, moves and styles can flip between include and exclude.
        var canInvert: Bool {
            switch self {
            case .species, .move, .style: return true
            case .correction, .unrecognized: return false
            }
        }
    }

    /// Reading the description with Apple Intelligence.
    enum Interpretation: Equatable {
        case idle
        case running
        /// It read the current text; `added` are the chips it added.
        case finished(added: [String])
        case failed(String)
    }

    var regulation: ChampionsRegulation
    private(set) var status: Status = .idle
    /// A background refresh is running while cached results show.
    private(set) var isRefreshing = false
    /// Why the last refresh failed, when cached results are still showing.
    private(set) var refreshError: String?
    private(set) var query = TeamQuery()
    private(set) var results: [TeamComposition] = []
    private(set) var teamCount = 0
    private(set) var eventCount = 0
    private(set) var missingEventCount = 0
    /// When the tournament list was last fetched.
    private(set) var updatedAt: Date?
    /// Smogon's usage stats for the regulation, or for the latest earlier
    /// one while the regulation has none. nil until loaded, or if unavailable.
    private(set) var insights: SmogonInsights?
    /// Teammates Smogon pairs with the query's species.
    private(set) var suggestions: [SmogonInsights.Suggestion] = []
    private(set) var interpretation: Interpretation = .idle
    private(set) var interpreterAvailability: TeamInterpreterAvailability = .unsupported

    private let store: TeamCorpusStore
    private let ladderStore: LadderStore
    private let loadVocabulary: @Sendable (ChampionsRegulation) throws -> TeamSearchVocabulary
    private let interpreter: TeamQueryInterpreting
    private let now: () -> Date
    private var loadedRegulation: ChampionsRegulation?
    private var parser: TeamQueryParser?
    /// What Apple Intelligence added to the query, by ID.
    private var interpretedSpecies: Set<String> = []
    private var interpretedMoves: Set<ShowdownID> = []
    private var interpretedStyles: Set<String> = []
    private var index: TeamSearchIndex?
    private var text = ""

    init(regulation: ChampionsRegulation = .current,
         store: TeamCorpusStore = .shared,
         ladderStore: LadderStore = .shared,
         loadVocabulary: @escaping @Sendable (ChampionsRegulation) throws -> TeamSearchVocabulary = {
             try TeamSearchVocabulary.bundled(for: $0)
         },
         interpreter: TeamQueryInterpreting = AppleIntelligenceInterpreter(),
         now: @escaping () -> Date = Date.init) {
        self.regulation = regulation
        self.store = store
        self.ladderStore = ladderStore
        self.loadVocabulary = loadVocabulary
        self.interpreter = interpreter
        self.now = now
    }

    // MARK: Loading

    /// Loads the corpus for `regulation`, first from cache, then from
    /// Limitless, and then Smogon's usage stats. After a change of
    /// regulation, it starts over.
    func load(forceRefresh: Bool = false) async {
        let regulation = self.regulation
        interpreterAvailability = interpreter.availability
        if loadedRegulation != regulation {
            loadedRegulation = regulation
            parser = nil
            index = nil
            insights = nil
            results = []
            suggestions = []
            status = .idle
            resetInterpretation()
            let loader = loadVocabulary
            do {
                let vocabulary = try await Task.detached { try loader(regulation) }.value
                guard self.regulation == regulation else { return }
                parser = TeamQueryParser(vocabulary: vocabulary)
                query = parser?.parse(text) ?? TeamQuery()
            } catch {
                loadedRegulation = nil
                status = .failed("This regulation's data couldn't be loaded.")
                return
            }
            if let cached = await store.cachedCorpus(format: regulation.limitlessFormat),
               !cached.teams.isEmpty {
                await apply(cached, for: regulation)
            }
        }
        guard !Task.isCancelled, self.regulation == regulation else { return }
        await loadCorpus(for: regulation, forceRefresh: forceRefresh)
        guard !Task.isCancelled, self.regulation == regulation else { return }
        await loadInsights(for: regulation, forceRefresh: forceRefresh)
    }

    private func loadCorpus(for regulation: ChampionsRegulation, forceRefresh: Bool) async {
        // Coming back to the tab shouldn't re-read and re-index the cache
        // while the list is still fresh.
        if !forceRefresh, index != nil, let updatedAt,
           now().timeIntervalSince(updatedAt) < TeamCorpusConfiguration().listTTL {
            return
        }

        if index == nil { status = .loading(completed: 0, total: 0) } else { isRefreshing = true }
        defer { isRefreshing = false }
        do {
            let corpus = try await store.corpus(for: regulation, forceRefresh: forceRefresh) {
                [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, case .loading = self.status, self.regulation == regulation else { return }
                    self.status = .loading(completed: progress.completed, total: progress.total)
                }
            }
            await apply(corpus, for: regulation)
            refreshError = corpus.listRefreshError
        } catch {
            guard self.regulation == regulation else { return }
            if index == nil {
                status = .failed(error.localizedDescription)
            } else {
                refreshError = error.localizedDescription
            }
        }
    }

    /// Loads Smogon's stats, from the PK Reference server or from Smogon
    /// (LadderStore): what's on the device at once, then a check for a
    /// newer month. Failures leave the insights as they were.
    private func loadInsights(for regulation: ChampionsRegulation, forceRefresh: Bool) async {
        guard let vocabulary = parser?.vocabulary else { return }
        let request = LadderRequest.teamSearch(regulation)
        if insights == nil, let cached = await ladderStore.cached(request, fallBack: true) {
            await applyInsights(SmogonUsage(cached.stats), vocabulary: vocabulary, for: regulation)
        }
        guard let stats = try? await ladderStore.fetch(request, fallBack: true, force: forceRefresh).answer?.stats
        else { return }
        let usage = SmogonUsage(stats)
        guard usage != insights?.usage else { return }
        await applyInsights(usage, vocabulary: vocabulary, for: regulation)
    }

    private func applyInsights(_ usage: SmogonUsage, vocabulary: TeamSearchVocabulary,
                               for regulation: ChampionsRegulation) async {
        let insights = await Task.detached { SmogonInsights(usage: usage, vocabulary: vocabulary) }.value
        guard self.regulation == regulation else { return }
        self.insights = insights
        search()
    }

    private func apply(_ corpus: TeamCorpus, for regulation: ChampionsRegulation) async {
        guard let vocabulary = parser?.vocabulary else { return }
        let index = await Task.detached { TeamSearchIndex(corpus: corpus, vocabulary: vocabulary) }.value
        guard self.regulation == regulation else { return }
        self.index = index
        teamCount = corpus.teams.count
        eventCount = corpus.events.count
        missingEventCount = corpus.missingEvents.count
        updatedAt = corpus.listFetchedAt
        status = .ready
        search()
    }

    // MARK: Query

    /// Parses `text` and searches. Chip edits, and what Apple Intelligence
    /// added, are dropped. Unchanged text (submitting it again) keeps them.
    func setText(_ text: String) {
        interpreterAvailability = interpreter.availability
        guard text != self.text else { return }
        self.text = text
        query = parser?.parse(text) ?? TeamQuery()
        resetInterpretation()
        search()
    }

    // MARK: Apple Intelligence

    /// Whether to offer Apple Intelligence: the parser left words it
    /// couldn't place, or it has already run on this text. Hidden on
    /// devices that can't run it.
    var offersInterpretation: Bool {
        guard interpreterAvailability != .unsupported, parser != nil,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !query.unrecognized.isEmpty || interpretation != .idle
    }

    /// Asks Apple Intelligence what the words the parser couldn't place
    /// mean, reads the text again with its answers, and adds what that
    /// finds. Words it couldn't place either stay unrecognized.
    func interpret() async {
        interpreterAvailability = interpreter.availability
        guard interpreterAvailability == .available, interpretation != .running,
              let parser else { return }
        let text = self.text
        let regulation = self.regulation
        let phrases = parser.unplacedPhrases(in: text)
        guard !phrases.isEmpty else {
            interpretation = .finished(added: [])
            return
        }
        interpretation = .running
        let result: Result<[String: String], Error>
        do {
            result = .success(try await interpreter.meanings(of: phrases, in: text,
                                                             vocabulary: parser.vocabulary))
        } catch {
            result = .failure(error)
        }
        // The text or regulation changed while it ran: the answer is stale.
        guard self.text == text, self.regulation == regulation, interpretation == .running else { return }
        switch result {
        case .success(let meanings):
            let baseline = parser.parse(text)
            let reread = parser.parse(text, meanings: meanings)
            let added = query.add(reread, beyond: baseline)
            interpretedSpecies.formUnion((added.species + added.excludedSpecies).map(\.speciesID))
            interpretedMoves.formUnion((added.moves + added.excludedMoves).map(\.id))
            interpretedStyles.formUnion((added.archetypes + added.excludedArchetypes).map(\.id))
            // Words still unplaced, less any the user removed.
            var removed = baseline.unrecognized
            for word in query.unrecognized {
                if let found = removed.firstIndex(of: word) { removed.remove(at: found) }
            }
            var unplaced = reread.unrecognized
            for word in removed {
                if let found = unplaced.firstIndex(of: word) { unplaced.remove(at: found) }
            }
            query.unrecognized = unplaced
            interpretation = .finished(added: Self.chips(for: added).map(\.label))
            search()
        case .failure(let error):
            interpretation = .failed(error.localizedDescription)
        }
    }

    /// Whether Apple Intelligence added the chip's species, move or style.
    func isInterpreted(_ chip: Chip) -> Bool {
        switch chip {
        case .species(let term, _): return interpretedSpecies.contains(term.speciesID)
        case .move(let term, _): return interpretedMoves.contains(term.id)
        case .style(let style, _): return interpretedStyles.contains(style.id)
        case .correction, .unrecognized: return false
        }
    }

    private func resetInterpretation() {
        interpretation = .idle
        interpretedSpecies = []
        interpretedMoves = []
        interpretedStyles = []
    }

    var chips: [Chip] { Self.chips(for: query) }

    private static func chips(for query: TeamQuery) -> [Chip] {
        var chips: [Chip] = []
        chips += query.species.map { .species($0, excluded: false) }
        chips += query.archetypes.map { .style($0, excluded: false) }
        chips += query.moves.map { .move($0, excluded: false) }
        chips += query.excludedSpecies.map { .species($0, excluded: true) }
        chips += query.excludedArchetypes.map { .style($0, excluded: true) }
        chips += query.excludedMoves.map { .move($0, excluded: true) }
        chips += query.corrections.map { .correction($0) }
        // A word typed twice shows once; removing it removes both.
        var seen = Set<String>()
        chips += query.unrecognized.filter { seen.insert($0).inserted }.map { .unrecognized($0) }
        return chips
    }

    func remove(_ chip: Chip) {
        switch chip {
        case .species(let term, _):
            query.species.removeAll { $0 == term }
            query.excludedSpecies.removeAll { $0 == term }
        case .move(let term, _):
            query.moves.removeAll { $0 == term }
            query.excludedMoves.removeAll { $0 == term }
        case .style(let style, _):
            query.archetypes.removeAll { $0 == style }
            query.excludedArchetypes.removeAll { $0 == style }
        case .correction(let correction):
            query.corrections.removeAll { $0 == correction }
        case .unrecognized(let word):
            query.unrecognized.removeAll { $0 == word }
        }
        search()
    }

    /// Flips a species, move or style between include and exclude.
    func invert(_ chip: Chip) {
        switch chip {
        case .species(let term, let excluded):
            remove(chip)
            if excluded { query.species.append(term) } else { query.excludedSpecies.append(term) }
        case .move(let term, let excluded):
            remove(chip)
            if excluded { query.moves.append(term) } else { query.excludedMoves.append(term) }
        case .style(let style, let excluded):
            remove(chip)
            if excluded { query.archetypes.append(style) } else { query.excludedArchetypes.append(style) }
        case .correction, .unrecognized:
            return
        }
        search()
    }

    private func search() {
        suggestions = insights?.suggestions(for: query) ?? []
        guard let index else {
            results = []
            return
        }
        results = TeamSearchEngine.search(query, in: index, now: now())
    }
}
