//
//  MetaTab.swift
//  PKReference
//
//  The Meta tab, in place of the Tournaments tab: what's winning in
//  Settings' regulation, from the PK Reference server or, without it, from
//  the events Team Search downloaded (MetaModel). The Tournaments list lives
//  on inside it as Events. BackendIntegration-PHASE4.md has the design.
//

import SwiftUI

struct MetaTab: View {
    @AppStorage(AppSettings.championsRegulation) private var regulationRaw: String
    @AppStorage(AppSettings.metaWindow) private var window: MetaAPI.Window
    @AppStorage(AppSettings.metaServerEnabled) private var serverEnabled: Bool
    @AppStorage(AppSettings.metaServerAddress) private var serverAddress: String
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var model = MetaModel()
    @State private var showingEvents = false
    /// `-debugOpenSheet metaInfo`: the usage info sheet, for snapshots.
    @State private var showingInfo = false
    /// `-debugOpenSheet metaPokemon`: a page opened in code, for snapshots.
    @State private var debugRoute: MetaRoute?

    private var regulation: ChampionsRegulation {
        ChampionsRegulation(rawValue: regulationRaw) ?? .current
    }

    /// Anything that changes what's shown reloads it.
    private var loadKey: String {
        "\(regulation.rawValue)|\(window.rawValue)|\(serverEnabled)|\(serverAddress)"
    }

    var body: some View {
        TabNavigationStack {
            ScrollView {
                CardStack {
                    MetaHeaderCard(regulation: regulation, window: $window, snapshot: model.snapshot)
                    if let problem = model.serverProblem {
                        MetaNoticeCard(icon: "exclamationmark.triangle.fill", tint: .orange,
                                       text: MetaText.serverProblem(problem, showing: model.snapshot?.source,
                                                                    updated: model.snapshot?.updated, now: .now)) {
                            Button("Try Again") { Task { await model.load(regulation, window: window, force: true) } }
                        }
                    }
                    if let warning = model.warning {
                        MetaNoticeCard(icon: "info.circle.fill", tint: .secondary, text: warning) {
                            OpenSettingsButton(title: "Change in Settings")
                        }
                    }
                    statusCard
                    if model.snapshot?.source == .device && !serverEnabled {
                        MetaNoticeCard(icon: "server.rack", tint: .secondary,
                                       text: "More from a PK Reference server (beta): win rates without mirror "
                                           + "matches, top cuts, and how archetypes do against each other.") {
                            OpenSettingsButton(title: "Open Settings")
                        }
                    }
                    let namer = MetaNamer(regulation)
                    let recent = MetaRecentEventsCard(regulation: regulation, snapshot: model.snapshot,
                                                      limitlessEvents: model.limitlessEvents) { showingEvents = true }
                    if let snapshot = model.snapshot, !snapshot.list.pokemon.isEmpty {
                        // Two columns where there's room: iPad and the Mac.
                        if horizontalSizeClass == .regular {
                            HStack(alignment: .top, spacing: 16) {
                                CardStack { MetaWhatsWinningCard(snapshot: snapshot, namer: namer) }
                                    .frame(maxWidth: .infinity, alignment: .top)
                                CardStack {
                                    MetaRisingCard(snapshot: snapshot, namer: namer)
                                    recent
                                }
                                .frame(maxWidth: .infinity, alignment: .top)
                            }
                        } else {
                            MetaWhatsWinningCard(snapshot: snapshot, namer: namer)
                            MetaRisingCard(snapshot: snapshot, namer: namer)
                            recent
                        }
                    } else {
                        recent
                    }
                }
                .frame(maxWidth: horizontalSizeClass == .regular ? 1100 : 760)
                .frame(maxWidth: .infinity)
                .padding()
            }
            .navigationTitle("Meta")
            .cardPage()
            .refreshable { await model.refresh(regulation, window: window) }
            #if os(macOS)
            .toolbar {
                ToolbarItem {
                    Button { Task { await model.refresh(regulation, window: window) } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            #endif
            .navigationDestination(isPresented: $showingEvents) {
                EventsView(format: regulation.limitlessFormat)
            }
            .navigationDestination(for: MetaRoute.self) { destination($0) }
            #if DEBUG && os(macOS)
            .navigationDestination(item: $debugRoute) { destination($0) }
            #endif
            .task(id: loadKey) { await model.load(regulation, window: window) }
            .onChange(of: scenePhase) {
                if scenePhase == .active { Task { await model.load(regulation, window: window) } }
            }
            #if DEBUG && os(macOS)
            .task { await DebugSnapshot.openSheet("metaEvents") { showingEvents = true } }
            .task { await DebugSnapshot.openSheet("metaInfo") { showingInfo = true } }
            .task {
                // `-debugOpenSheet metaPokemon`: the most-used Pokémon's page.
                await DebugSnapshot.openSheet("metaPokemon") {}
                guard UserDefaults.standard.string(forKey: "debugOpenSheet") == "metaPokemon" else { return }
                for _ in 0..<20 where model.snapshot == nil { try? await Task.sleep(for: .milliseconds(250)) }
                if let key = model.snapshot?.list.pokemon.first?.key { debugRoute = .pokemon(key) }
            }
            .sheet(isPresented: $showingInfo) { MetaInfoSheet(definition: .usage) }
            #endif
        }
    }

    @ViewBuilder
    private func destination(_ route: MetaRoute) -> some View {
        if let snapshot = model.snapshot {
            switch route {
            case .pokemon(let key):
                MetaPokemonPage(key: key, snapshot: snapshot, namer: MetaNamer(regulation))
            case .allPokemon:
                MetaPokemonListView(snapshot: snapshot, namer: MetaNamer(regulation))
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch model.status {
        case .loading where model.snapshot == nil:
            ProgressView("Loading the meta…")
                .frame(maxWidth: .infinity)
                .card()
        case .needsDownload:
            downloadCard(failure: nil)
        case .downloadFailed(let reason):
            downloadCard(failure: reason)
        case .downloading(let completed, let total):
            SectionCard(title: "Downloading Events", icon: "arrow.down.circle") {
                if total > 0 {
                    ProgressView(value: Double(completed), total: Double(total)) {
                        Text("\(completed) of \(total) events")
                    }
                } else {
                    ProgressView("Finding events…")
                }
                Text("Limitless limits how fast events can be downloaded, so the first download can take a few minutes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    private func downloadCard(failure: String?) -> some View {
        SectionCard(title: "Tournament Teams", icon: "arrow.down.circle") {
            Text(MetaText.needsDownload(regulation))
                .font(.subheadline)
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await model.download(regulation, window: window) }
            } label: {
                Label(failure == nil ? "Download Events" : "Try Again", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.primaryAction)
        }
    }
}

// MARK: - Header

/// The regulation, what the numbers rest on and where they're from, and the
/// window.
private struct MetaHeaderCard: View {
    let regulation: ChampionsRegulation
    @Binding var window: MetaAPI.Window
    let snapshot: MetaModel.Snapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline) {
                Text(regulation.displayName)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                OpenSettingsButton(title: "Change in Settings")
                    .font(.subheadline)
            }
            if let snapshot {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MetaText.sample(snapshot.list.sample, source: snapshot.source))
                        .font(.subheadline)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(MetaText.source(snapshot.source, updated: snapshot.updated, now: context.date))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Picker("Window", selection: $window) {
                ForEach(MetaAPI.Window.allCases, id: \.self) { window in
                    Text(MetaText.window(window)).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Window")
        }
        .card()
    }
}

/// A short notice with an action: the server couldn't answer, nothing in
/// the window, and so on.
private struct MetaNoticeCard<Action: View>: View {
    let icon: String
    let tint: Color
    let text: String
    @ViewBuilder let action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(text).font(.subheadline)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            action
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Opens Settings: its window on the Mac, the Settings tab elsewhere.
struct OpenSettingsButton: View {
    let title: String
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        Button(title) {
            #if os(macOS)
            openSettings()
            #else
            AppNavigator.shared.request = .settings
            #endif
        }
    }
}

// MARK: - Recent events

private struct MetaRecentEventsCard: View {
    let regulation: ChampionsRegulation
    let snapshot: MetaModel.Snapshot?
    let limitlessEvents: [LimitlessTournament]
    let seeAll: () -> Void

    private var vocabulary: TeamSearchVocabulary? { try? TeamSearchVocabulary.bundled(for: regulation) }

    var body: some View {
        SectionCard(title: "Recent Events", icon: "trophy") {
            if let events = snapshot?.events.prefix(5), !events.isEmpty {
                let vocabulary = vocabulary
                ForEach(Array(events), id: \.id) { event in
                    NavigationLink {
                        TournamentDetailView(tournament: Self.tournament(event, format: regulation.limitlessFormat))
                    } label: {
                        MetaEventRow(event: event, vocabulary: vocabulary)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            } else if !limitlessEvents.isEmpty {
                ForEach(limitlessEvents) { tournament in
                    NavigationLink {
                        TournamentDetailView(tournament: tournament)
                    } label: {
                        EventRow(tournament: tournament)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            } else {
                Text("No \(regulation.limitlessFormat) events to show yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(action: seeAll) {
                Label("All Events", systemImage: "list.bullet")
            }
            .font(.subheadline)
        }
    }

    /// The event as Limitless lists it, for its standings page.
    static func tournament(_ event: MetaAPI.EventSummary, format: String) -> LimitlessTournament {
        let date = event.date.map {
            $0.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        } ?? ""
        return LimitlessTournament(id: event.id, name: event.name ?? "Event", game: "VGC", format: format,
                                   date: date, players: event.players)
    }
}

private struct MetaEventRow: View {
    let event: MetaAPI.EventSummary
    let vocabulary: TeamSearchVocabulary?

    private var team: String? {
        guard let winner = event.winner, !winner.team.isEmpty else { return nil }
        return winner.team.map { vocabulary?.species(forKey: $0)?.displayName ?? $0 }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.name ?? "Event")
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 12) {
                if let date = event.date {
                    Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                Label("\(event.players) players", systemImage: "person.2")
                if !event.standingsFinal {
                    Text("Not final")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let winner = event.winner {
                Text(MetaText.winner(winner))
                    .font(.subheadline)
                if let team {
                    Text(team)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
