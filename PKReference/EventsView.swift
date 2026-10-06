//
//  EventsView.swift
//  PKReference
//
//  Created by Rishi Anand on 5/1/26.
//
//  Events: Limitless's tournaments, browsed live by game and format, with
//  each one's standings and team sheets. It was the Tournaments tab; it's
//  now a page inside the Meta tab (BackendIntegration-PHASE4.md §2.2), and
//  always reads Limitless, whether or not the PK Reference server is on.
//

import SwiftUI
import SwiftData
import WebKit

// MARK: - View Model

@Observable
final class EventsViewModel {
    var games: [LimitlessGame] = []
    var tournaments: [LimitlessTournament] = []
    var selectedGameID: String = "VGC"
    var selectedFormatID: String?
    var searchText = ""
    var minPlayers: Int = 0
    var isLoading = false
    var errorMessage: String?
    var currentPage = 1
    var hasMorePages = true

    /// Opens on one VGC format, such as the Meta tab's regulation ("M-C"),
    /// or every format.
    init(format: String? = nil) {
        selectedFormatID = format
    }

    var selectedGame: LimitlessGame? {
        games.first { $0.id == selectedGameID }
    }

    var availableFormats: [(key: String, value: String)] {
        guard let game = selectedGame else { return [] }
        return game.formats.sorted { $0.value < $1.value }
    }

    var filteredTournaments: [LimitlessTournament] {
        var result = tournaments
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedStandardContains(searchText) }
        }
        if minPlayers > 0 {
            result = result.filter { $0.players >= minPlayers }
        }
        return result
    }

    var selectedFormatName: String? {
        guard let formatID = selectedFormatID, let game = selectedGame else { return nil }
        return game.formats[formatID]
    }

    func loadGames() async {
        do {
            games = try await LimitlessAPIService.shared.fetchGames()
        } catch {
            errorMessage = "Failed to load games: \(error.localizedDescription)"
        }
    }

    func loadTournaments(reset: Bool = true) async {
        if reset {
            currentPage = 1
            hasMorePages = true
        }
        isLoading = true
        errorMessage = nil
        do {
            let results = try await LimitlessAPIService.shared.fetchTournaments(
                game: selectedGameID,
                format: selectedFormatID,
                limit: 50,
                page: currentPage
            )
            if reset {
                tournaments = results
            } else {
                tournaments.append(contentsOf: results)
            }
            hasMorePages = results.count >= 50
        } catch {
            errorMessage = "Failed to load events: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func loadNextPage() async {
        guard hasMorePages, !isLoading else { return }
        currentPage += 1
        await loadTournaments(reset: false)
    }
}

// MARK: - Events

/// The event list, pushed from the Meta tab.
struct EventsView: View {
    @State private var vm: EventsViewModel
    @State private var showFilters = false

    init(format: String? = nil) {
        _vm = State(initialValue: EventsViewModel(format: format))
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.tournaments.isEmpty {
                ProgressView("Loading events…")
            } else if let error = vm.errorMessage, vm.tournaments.isEmpty {
                ContentUnavailableView {
                    Label("Failed to Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await vm.loadTournaments() }
                    }
                }
            } else if vm.filteredTournaments.isEmpty {
                ContentUnavailableView.search(text: vm.searchText)
            } else {
                tournamentList
            }
        }
        .navigationTitle("Events")
        .searchable(text: $vm.searchText, prompt: "Search events")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showFilters = true
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            EventFilterSheet(vm: vm)
            .sheetSize()
        }
        .task {
            if vm.games.isEmpty {
                await vm.loadGames()
            }
            if vm.tournaments.isEmpty {
                await vm.loadTournaments()
            }
        }
        #if DEBUG && os(macOS)
        .task { await DebugSnapshot.openSheet("metaEventFilters") { showFilters = true } }
        #endif
    }

    private var tournamentList: some View {
        List {
            if let formatName = vm.selectedFormatName {
                Section {
                    HStack {
                        Label(vm.selectedGame?.name ?? vm.selectedGameID, systemImage: "gamecontroller")
                        Spacer()
                        Text(formatName)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            Section {
                ForEach(vm.filteredTournaments) { tournament in
                    NavigationLink {
                        TournamentDetailView(tournament: tournament)
                    } label: {
                        EventRow(tournament: tournament)
                    }
                }

                if vm.hasMorePages && vm.searchText.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task {
                            await vm.loadNextPage()
                        }
                }
            } header: {
                Text("\(vm.filteredTournaments.count) events")
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Tournament Row

struct EventRow: View {
    let tournament: LimitlessTournament

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tournament.name)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label(tournament.displayDate, systemImage: "calendar")
                Label("\(tournament.players)", systemImage: "person.2")
                Text(tournament.format)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary, in: Capsule())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Filter Sheet

private struct EventFilterSheet: View {
    @Bindable var vm: EventsViewModel
    @Environment(\.dismiss) private var dismiss

    private let playerThresholds = [0, 8, 16, 32, 64, 128, 256]

    var body: some View {
        NavigationStack {
            Form {
                Section("Game") {
                    Picker("Game", selection: $vm.selectedGameID) {
                        ForEach(vm.games.filter { $0.metagame }) { game in
                            Text(game.name).tag(game.id)
                        }
                    }
                    .onChange(of: vm.selectedGameID) {
                        vm.selectedFormatID = nil
                    }
                }

                Section("Format") {
                    if vm.availableFormats.isEmpty {
                        Text("No formats available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Format", selection: Binding(
                            get: { vm.selectedFormatID ?? "__all__" },
                            set: { vm.selectedFormatID = $0 == "__all__" ? nil : $0 }
                        )) {
                            Text("All Formats").tag("__all__")
                            ForEach(vm.availableFormats, id: \.key) { key, value in
                                Text(value).tag(key)
                            }
                        }
                    }
                }

                Section("Minimum Players") {
                    Picker("Min Players", selection: $vm.minPlayers) {
                        Text("Any").tag(0)
                        ForEach(playerThresholds.dropFirst(), id: \.self) { count in
                            Text("\(count)+").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .navigationTitle("Filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        dismiss()
                        Task { await vm.loadTournaments() }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Tournament Detail

struct TournamentDetailView: View {
    let tournament: LimitlessTournament
    @State private var detail: LimitlessTournamentDetail?
    @State private var standings: [LimitlessStanding] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedPlacingFilter: PlacingFilter = .all

    enum PlacingFilter: String, CaseIterable, Identifiable {
        case all, top4, top8, top16, top32
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .top4: return "Top 4"
            case .top8: return "Top 8"
            case .top16: return "Top 16"
            case .top32: return "Top 32"
            }
        }
        var maxPlacing: Int? {
            switch self {
            case .all: return nil
            case .top4: return 4
            case .top8: return 8
            case .top16: return 16
            case .top32: return 32
            }
        }

        /// Unranked players (nil placing) only show under "All".
        func includes(placing: Int?) -> Bool {
            guard let maxPlacing else { return true }
            guard let placing else { return false }
            return placing <= maxPlacing
        }
    }

    private var filteredStandings: [LimitlessStanding] {
        var result = standings.filter { selectedPlacingFilter.includes(placing: $0.placing) }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedStandardContains(searchText) ||
                ($0.deck?.name?.localizedStandardContains(searchText) ?? false) ||
                ($0.decklist ?? []).contains { $0.name.localizedStandardContains(searchText) }
            }
        }
        return result
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading details…")
            } else if let error = errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else {
                standingsContent
            }
        }
        .navigationTitle(tournament.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadData()
        }
    }

    private var standingsContent: some View {
        List {
            tournamentInfoSection

            if !standings.isEmpty {
                standingsSection
            }
        }
        .searchable(text: $searchText, prompt: "Search players or teams")
        .scrollDismissesKeyboard(.interactively)
    }

    private var tournamentInfoSection: some View {
        Section("Tournament Info") {
            LabeledContent("Game", value: tournament.game)
            LabeledContent("Format", value: tournament.format)
            LabeledContent("Date", value: tournament.displayDate)
            LabeledContent("Players", value: "\(tournament.players)")
            if let detail {
                if let org = detail.organizer?.name {
                    LabeledContent("Organizer", value: org)
                }
                if let isOnline = detail.isOnline {
                    LabeledContent("Type", value: isOnline ? "Online" : "In-Person")
                }
                if let phases = detail.phases, !phases.isEmpty {
                    LabeledContent("Rounds") {
                        let totalRounds = phases.compactMap(\.rounds).reduce(0, +)
                        Text("\(totalRounds)")
                    }
                }
            }
        }
    }

    private var standingsSection: some View {
        Section {
            Picker("Filter", selection: $selectedPlacingFilter) {
                ForEach(PlacingFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowSeparator(.hidden)

            ForEach(filteredStandings) { standing in
                if standing.decklist != nil {
                    NavigationLink {
                        StandingDetailView(standing: standing)
                    } label: {
                        StandingRow(standing: standing)
                    }
                } else {
                    StandingRow(standing: standing)
                }
            }
        } header: {
            Text("Standings (\(filteredStandings.count))")
        }
    }

    private func loadData() async {
        isLoading = true
        do {
            async let detailFetch = LimitlessAPIService.shared.fetchTournamentDetail(id: tournament.id)
            async let standingsFetch = LimitlessAPIService.shared.fetchStandings(tournamentID: tournament.id)
            detail = try await detailFetch
            standings = LimitlessStanding.sortedByPlacing(try await standingsFetch)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Standing Row

private struct StandingRow: View {
    let standing: LimitlessStanding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(standing.placing.map { "#\($0)" } ?? "—")
                    .font(.headline)
                    .foregroundStyle(placingColor)
                    .lineLimit(1)
                    .scaledWidth(44, relativeTo: .headline, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let country = standing.country {
                            Text(flagEmoji(for: country))
                        }
                        Text(standing.name)
                            .font(.body.weight(.medium))
                    }

                    HStack(spacing: 8) {
                        if let record = standing.record {
                            Text(record.display)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let deckName = standing.deck?.name {
                            Text(deckName)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.fill.tertiary, in: Capsule())
                        }
                        if standing.drop != nil {
                            Text("Dropped")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Spacer()
            }

            if let team = standing.decklist, !team.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(team) { member in
                        Text(member.name)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.fill.quaternary, in: Capsule())
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 2)
    }

    private var placingColor: Color {
        switch standing.placing {
        case 1?: return .yellow
        case 2?: return .gray
        case 3?: return .orange
        case nil: return .secondary
        default: return .primary
        }
    }

    private func flagEmoji(for countryCode: String) -> String {
        let base: UInt32 = 127397
        return countryCode
            .uppercased()
            .unicodeScalars
            .compactMap { Unicode.Scalar(base + $0.value) }
            .map { String($0) }
            .joined()
    }
}

// MARK: - Standing Detail (Team View)

/// One player's team sheet, with save buttons. Team Search opens it too.
struct StandingDetailView: View {
    let standing: LimitlessStanding
    @Query(sort: \PKMN.nationalPokedexNumber) private var allPokemon: [PKMN]
    @Query(sort: \PKMNStats.name) private var allStats: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]
    @Environment(\.modelContext) private var modelContext
    @State private var savedMemberName: String?
    @State private var fullTeamSaveState: FullTeamSaveState = .idle
    /// Persistent alert payload — one line per Limitless name that didn't
    /// resolve. Mixes species mismatches ("no match found for X") and move
    /// mismatches ("no match found for move X on Y") in a single list so the
    /// user sees the full debug report in one pass.
    @State private var unmatchedAlertLines: [String] = []
    @State private var showUnmatchedAlert: Bool = false
    /// When on, every spread saved from this screen (single member OR full
    /// team) runs through `StatNaturePredictor` so the saved record has a
    /// best-guess stat spread instead of all zeros. The Limitless API doesn't
    /// expose stat points, so this toggle is the only way downloaded teams
    /// gain them. It fills the nature only when Limitless didn't send one.
    @State private var predictStatsAndNature: Bool = false

    /// Tracks the result of the most recent "Save Full Team" press so we can flash
    /// feedback in the toolbar without committing to a long-lived banner.
    private enum FullTeamSaveState: Equatable {
        case idle
        case saved(savedCount: Int)
        case noTeam
    }

    /// Save Full Team's place: the top bar's trailing edge on iOS, the
    /// primary spot in a Mac window's toolbar.
    private static var saveTeamPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    var body: some View {
        List {
            Section("Player") {
                LabeledContent("Name", value: standing.name)
                if let country = standing.country {
                    LabeledContent("Country", value: flagEmoji(for: country) + " " + country)
                }
                LabeledContent("Placing", value: standing.placing.map { "#\($0)" } ?? "Unranked")
                if let record = standing.record {
                    LabeledContent("Record", value: record.display)
                }
            }

            if let team = standing.decklist, !team.isEmpty {
                Section {
                    Toggle(isOn: $predictStatsAndNature) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Predict Stats & Nature", systemImage: "sparkles")
                                .font(.subheadline)
                            Text("Fills in stat points using the on-device model, since Limitless doesn't publish them. Also fills the nature when the event didn't record one.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.purple)
                }

                Section("Team (\(team.count))") {
                    ForEach(team) { member in
                        TeamMemberRow(
                            member: member,
                            pokemon: findPokemon(named: member.name),
                            onSave: { saveSet(member: member) }
                        )
                        .overlay(alignment: .topTrailing) {
                            if savedMemberName == member.name {
                                Text("Saved!")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.green)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(standing.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: Self.saveTeamPlacement) {
                Button {
                    saveFullTeam()
                } label: {
                    Label("Save Full Team", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled((standing.decklist ?? []).isEmpty)
            }
            // Inline feedback so the user knows the save happened. Stays in the
            // toolbar so it doesn't push the team list around.
            if case .saved(let savedCount) = fullTeamSaveState {
                ToolbarItem(placement: .status) {
                    Text("Saved \(savedCount)-mon team")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            } else if case .noTeam = fullTeamSaveState {
                ToolbarItem(placement: .status) {
                    Text("No decklist to save")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
        .alert("Couldn't match team data",
               isPresented: $showUnmatchedAlert,
               presenting: unmatchedAlertLines) { _ in
            Button("OK", role: .cancel) {}
        } message: { lines in
            // Each entry is already formatted (species: "no match found for X";
            // move: "no match found for move X on Y") so the user can copy the
            // names straight into the alias map or sync logs.
            Text(lines.joined(separator: "\n"))
        }
    }

    private func findPokemon(named name: String) -> PKMN? {
        let candidates = TournamentSpeciesAlias.candidates(for: name)
        for candidate in candidates {
            let lower = candidate.lowercased()
            if let hit = allPokemon.first(where: { $0.name.lowercased() == lower }) {
                return hit
            }
        }
        return nil
    }

    /// Species, moves and everything else resolve through the shared
    /// Limitless importer, which Team Search uses too. Built per save: it's
    /// cheap next to a tap, and always sees the current Pokedex.
    private func makeImporter() -> LimitlessTeamImporter {
        LimitlessTeamImporter(allPokemon: allStats, allMoves: allMoves)
    }

    private func saveSet(member: LimitlessStanding.TeamMember) {
        switch makeImporter().planSpread(member, taken: takenSpreadNames(),
                                         predictStats: predictStatsAndNature) {
        case .failure(let unmatched):
            showUnmatched(unmatched)
            return
        case .success(let spread):
            modelContext.insert(spread)
        }
        withAnimation {
            savedMemberName = member.name
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                if savedMemberName == member.name {
                    savedMemberName = nil
                }
            }
        }
    }

    /// Names a new spread must avoid. Team slots find their spread by name
    /// (`SavedTeam.resolvedSlots`), so reusing a name — every Incineroar used
    /// to be saved as "Incineroar" — made older teams load the newest spread.
    /// Read from the context at save time rather than from `@Query`, so a
    /// spread inserted a moment ago counts too.
    private func takenSpreadNames() -> Set<String> {
        let spreads = (try? modelContext.fetch(FetchDescriptor<SavedSpread>())) ?? []
        let teams = (try? modelContext.fetch(FetchDescriptor<SavedTeam>())) ?? []
        return TeamPasteImport.takenNames(spreads: spreads, teams: teams)
    }

    /// Persists a SavedSpread per member and a SavedTeam that references them
    /// by name.
    ///
    /// **All or nothing:** if any species or move doesn't resolve, nothing is
    /// saved and a persistent alert lists each unmatched name — silently
    /// saving a partial team or partial moveset makes the gap impossible to
    /// debug. Alert lines follow the "no match found for <X>" / "no match
    /// found for move <X> on <Y>" format so the missing names are easy to
    /// copy into the alias map or sync logs.
    private func saveFullTeam() {
        guard let members = standing.decklist, !members.isEmpty else {
            withAnimation { fullTeamSaveState = .noTeam }
            scheduleFullTeamStateReset()
            return
        }
        switch makeImporter().planTeam(members, teamName: "\(standing.name)'s Team",
                                       taken: takenSpreadNames(),
                                       predictStats: predictStatsAndNature) {
        case .failure(let unmatched):
            showUnmatched(unmatched)
        case .success(let plan):
            for spread in plan.spreads { modelContext.insert(spread) }
            modelContext.insert(plan.team)
            withAnimation { fullTeamSaveState = .saved(savedCount: plan.team.slots.count) }
            scheduleFullTeamStateReset()
        }
    }

    private func showUnmatched(_ unmatched: LimitlessUnmatchedNames) {
        unmatchedAlertLines = unmatched.lines
        showUnmatchedAlert = true
    }

    private func scheduleFullTeamStateReset() {
        let snapshot = fullTeamSaveState
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                if fullTeamSaveState == snapshot {
                    fullTeamSaveState = .idle
                }
            }
        }
    }

    private func flagEmoji(for countryCode: String) -> String {
        let base: UInt32 = 127397
        return countryCode
            .uppercased()
            .unicodeScalars
            .compactMap { Unicode.Scalar(base + $0.value) }
            .map { String($0) }
            .joined()
    }
}

private struct TeamMemberRow: View {
    let member: LimitlessStanding.TeamMember
    let pokemon: PKMN?
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let pokemon, let url = pokemon.detailURL {
                    NavigationLink {
                        MonIndexDetailView(pokemon: pokemon, detailURL: url)
                    } label: {
                        Text(member.name)
                            .font(.headline)
                    }
                } else {
                    Text(member.name)
                        .font(.headline)
                }
                if let tera = member.tera {
                    Text("Tera: \(tera)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary, in: Capsule())
                }
                Spacer()
                Button {
                    onSave()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 12) {
                if let ability = member.ability {
                    Label(ability, systemImage: "sparkles")
                }
                if let item = member.item {
                    Label(item, systemImage: "bag")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let attacks = member.attacks, !attacks.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(attacks, id: \.self) { move in
                        Text(move)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mon Index Detail (from tournament)

private struct MonIndexDetailView: View {
    let pokemon: PKMN
    let detailURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Link(detailURL.absoluteString, destination: detailURL)
                .font(.footnote)
            TournamentWebView(url: detailURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .navigationTitle(pokemon.name)
        .padding()
    }
}

private struct TournamentWebView: TournamentViewRepresentable {
    let url: URL

    func makeView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.allowsBackForwardNavigationGestures = true
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        return webView
    }

    func updateView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}

#if os(iOS)
private typealias TournamentViewRepresentable = UIViewRepresentable
private extension TournamentWebView {
    func makeUIView(context: Context) -> WKWebView { makeView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { updateView(webView, context: context) }
}
#else
private typealias TournamentViewRepresentable = NSViewRepresentable
private extension TournamentWebView {
    func makeNSView(context: Context) -> WKWebView { makeView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { updateView(webView, context: context) }
}
#endif

// MARK: - PKMN Detail URL Helper

private extension PKMN {
    var detailURL: URL? {
        let link = champsLink ?? genNineLink ?? genEightLink ?? genSevenLink ?? genSixLink ?? genFiveLink ?? genFourLink ?? genThreeLink ?? genTwoLink ?? genOneLink
        guard let link else { return nil }
        return URL(string: link)
    }
}
