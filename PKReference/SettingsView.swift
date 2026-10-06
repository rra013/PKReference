//
//  SettingsView.swift
//  PKReference
//
//  Created by Rishi Anand on 4/16/26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage(AppSettings.defaultGeneration) private var defaultGeneration: String
    @AppStorage(AppSettings.tabOrder) private var tabOrderRaw: String
    @AppStorage(AppSettings.hiddenTabs) private var hiddenTabsRaw: String
    @AppStorage(AppSettings.defaultTab) private var defaultTabRaw: String
    @AppStorage(AppSettings.accentColor) private var accentColorRaw: String
    @AppStorage(AppSettings.appearance) private var appearanceRaw: String
    @AppStorage(AppSettings.typeBadgeStyle) private var typeBadgeStyle: TypeBadgeStyle
    @AppStorage(AppSettings.matchupColors) private var matchupColors: MatchupColors
    @AppStorage(AppSettings.density) private var density: Density
    @AppStorage(AppSettings.typeBackgrounds) private var typeBackgrounds: Bool
    @AppStorage(AppSettings.warnBeforeLeavingTab) private var warnBeforeLeavingTab: Bool
    @AppStorage(AppSettings.instantSetDelete) private var instantSetDelete: Bool
    @AppStorage(AppSettings.championsRegulation) private var championsRegulationRaw: String
    @AppStorage(AppSettings.metaServerEnabled) private var metaServerEnabled: Bool
    @AppStorage(AppSettings.metaServerAddress) private var metaServerAddress: String
    @State private var metaServerStatus: String?
    @State private var isTestingMetaServer = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showResetConfirmation = false
    @State private var showRedownloadConfirmation = false
    @State private var isRedownloading = false
    @State private var redownloadStatus: String?
    /// Size of Team Search's cached tournament data; nil until measured.
    @State private var teamSearchCacheBytes: Int?

    private var tabLayout: TabLayout {
        TabLayout(orderRaw: tabOrderRaw, hiddenRaw: hiddenTabsRaw)
    }

    /// iPhone, or a narrow iPad window: the tab bar has a More list.
    private var usesMoreList: Bool { TabLayout.usesMoreList(in: horizontalSizeClass) }

    private static let badgePreviewTypes = ["Fire", "Water", "Grass", "Electric", "Psychic", "Dark"]

    private var shownTabsSummary: String {
        let shown = tabLayout.visible.count
        let total = AppTab.allUserTabs.count
        return shown == total ? "All shown" : "\(shown) of \(total) shown"
    }

    var body: some View {
        TabNavigationStack {
            Form {
                // MARK: - Appearance
                Section {
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accent Color")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                            ForEach(AppAccentColor.allCases) { accent in
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if accentColorRaw == accent.rawValue {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .onTapGesture { accentColorRaw = accent.rawValue }
                                    .accessibilityLabel(accent.label)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    Picker("Type Badges", selection: $typeBadgeStyle) {
                        ForEach(TypeBadgeStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }

                    // A sample in the chosen style, attached to the picker row.
                    FlowLayout(spacing: 6) {
                        ForEach(Self.badgePreviewTypes, id: \.self) { TypeBadge(type: $0) }
                    }
                    .listRowSeparator(.hidden, edges: .top)
                    .accessibilityHidden(true)

                    Picker("Matchup Colors", selection: $matchupColors) {
                        ForEach(MatchupColors.allCases) { colors in
                            Text(colors.label).tag(colors)
                        }
                    }

                    // The calc's markers in the chosen colors, attached to the picker row.
                    FlowLayout(spacing: 16) {
                        ForEach(MatchupSide.allCases, id: \.self) { side in
                            HStack(spacing: 6) {
                                Image(systemName: side.symbol)
                                    .foregroundStyle(matchupColors.color(for: side))
                                Text("Pokémon \(side.number)")
                            }
                        }
                    }
                    .font(.subheadline)
                    // Run the separator below full width, as under the badges.
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    .listRowSeparator(.hidden, edges: .top)
                    .accessibilityHidden(true)

                    Picker("Density", selection: $density) {
                        ForEach(Density.allCases) { density in
                            Text(density.label).tag(density)
                        }
                    }

                    Toggle("Type-Colored Backgrounds", isOn: $typeBackgrounds)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Matchup colors mark Pokémon 1 and 2 on the Damage Calc; Blue & Gold stays easy to tell apart with red-green color blindness. Compact density tightens the spacing in and between cards on the Damage Calc, the builders, Battle Sim, RNG Tools and Pokémon pages. Type-colored backgrounds tint a Pokémon's page and the Set Builder with its types, and faintly tint its card on the calc and in teams.")
                }

                // MARK: - Tabs
                Section {
                    NavigationLink {
                        TabSettingsView()
                    } label: {
                        LabeledContent("Arrange Tabs", value: shownTabsSummary)
                    }

                    Picker("Open To", selection: $defaultTabRaw) {
                        ForEach(tabLayout.visible) { tab in
                            Label(tab.label, systemImage: tab.icon).tag(tab.rawValue)
                        }
                    }

                    // Only a tab bar with a More list closes tabs on leaving.
                    if usesMoreList {
                        Toggle("Warn Before Leaving a Tab", isOn: $warnBeforeLeavingTab)
                    }
                } header: {
                    Text("Tabs")
                } footer: {
                    if usesMoreList {
                        Text("Choose which tabs appear and in what order, and which one the app opens to. Leaving a tab under More closes it, so with a battle, a running timer or search, or Pokémon entered, going back asks first.")
                    } else {
                        Text("Choose which tabs appear and in what order, and which one the app opens to.")
                    }
                }

                // MARK: - Default Generation
                Section {
                    Picker("Default Generation", selection: $defaultGeneration) {
                        ForEach(PokedexFilter.allCases) { filter in
                            Text(filter.title).tag(filter.rawValue)
                        }
                    }
                } header: {
                    Text("Default Generation")
                } footer: {
                    Text("Sets the default filter for the Mon Index. When Champions is selected, the Damage Calculator will also default to Champions Mode.")
                }

                // MARK: - Champions Regulation
                Section {
                    Picker("Active Regulation", selection: $championsRegulationRaw) {
                        ForEach(ChampionsRegulation.allCases) { reg in
                            HStack {
                                Text(reg.displayName)
                                Spacer()
                                if let window = Self.legalWindowString(for: reg) {
                                    Text(window)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(reg.rawValue)
                        }
                    }
                } header: {
                    Text("Champions Regulation")
                } footer: {
                    Text("Switches the roster, learnsets, and validation rules used by the Mon Index, Set Builder, and Battle Simulator. New installs default to the latest regulation (by start date). Reopen any Champions screen after switching to pick up the new format.")
                }

                // MARK: - Sets
                Section {
                    Toggle("Ask Before Deleting a Set", isOn: Binding(
                        get: { !instantSetDelete },
                        set: { instantSetDelete = !$0 }
                    ))
                } header: {
                    Text("Sets")
                } footer: {
                    Text("Swiping to delete a saved set asks first. Choosing Delete & Don't Ask Again in that prompt turns this off.")
                }

                // MARK: - PK Reference Server
                Section {
                    Toggle("Use PK Reference Server", isOn: $metaServerEnabled)
                    if metaServerEnabled {
                        LabeledContent("Address") {
                            TextField(MetaServerSettings.defaultAddress, text: $metaServerAddress)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                #endif
                        }
                        Button {
                            testMetaServer()
                        } label: {
                            HStack {
                                Label("Test Connection", systemImage: "network")
                                Spacer()
                                if isTestingMetaServer { ProgressView() }
                            }
                        }
                        .disabled(isTestingMetaServer)
                        if let metaServerStatus {
                            Text(metaServerStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("PK Reference Server (Beta)")
                } footer: {
                    Text("Team Search and the Problem Solver read tournament teams from your PK Reference server instead of downloading them from Limitless. Whenever the server can't be reached, they use Limitless as before.")
                }

                // MARK: - Data Management
                Section("Data Management") {
                    Button {
                        showRedownloadConfirmation = true
                    } label: {
                        HStack {
                            Label("Redownload Pokemon & Move Data", systemImage: "arrow.trianglehead.2.counterclockwise")
                            Spacer()
                            if isRedownloading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRedownloading)

                    if let status = redownloadStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(status.contains("Failed") ? .red : .secondary)
                    }

                    Button {
                        Task {
                            try? await TeamCorpusStore.shared.clearCache()
                            try? await SmogonUsageStore.shared.clearCache()
                            try? await MetaCache.shared.clear()
                            teamSearchCacheBytes = await teamSearchCacheSize()
                        }
                    } label: {
                        HStack {
                            Label("Clear Tournament Data", systemImage: "trash")
                            Spacer()
                            if let bytes = teamSearchCacheBytes {
                                Text(bytes.formatted(.byteCount(style: .file)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(teamSearchCacheBytes == 0)

                    Button("Reset All Data", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .disabled(isRedownloading)
                }

                // MARK: - Disclaimers
                Section("About") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PK Reference")
                            .font(.headline)

                        Text("This app is a fan-made reference tool for competitive Pokemon. It is not affiliated with, endorsed by, or associated with Nintendo, The Pokemon Company, or Game Freak.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Pokemon and all related names, characters, and imagery are trademarks and copyrights of their respective owners.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Damage calculations follow Smogon's damage calculator for Champions and the Gen V+ formula otherwise, and may not be exact in every edge case.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Data from PokeAPI, Serebii and Limitless. The damage calculator is ported from Smogon's, and the RNG tools from PokéFinder, EonTimer and Ten Lines.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("PK Reference is free software under the GNU General Public License, version 3 or later, and comes with no warranty. The license and source code are under Acknowledgements & Licenses.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    NavigationLink {
                        AcknowledgementsView()
                    } label: {
                        Label("Acknowledgements & Licenses", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("Settings")
            .task { teamSearchCacheBytes = await teamSearchCacheSize() }
            .confirmationDialog(
                "Redownload Data",
                isPresented: $showRedownloadConfirmation,
                titleVisibility: .visible
            ) {
                Button("Redownload") {
                    Task { await performRedownload() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will redownload all Pokemon and Move data from PokeAPI. Your saved spreads and teams will not be affected.")
            }
            .confirmationDialog(
                "Reset All Data",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    performReset()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will restore the app to a fresh install state, deleting all downloaded data, saved spreads, teams, and preferences. The app will re-sync on next launch.")
            }
        }
    }

    /// Asks the server what it has, and says so under the button.
    private func testMetaServer() {
        guard let url = MetaServerSettings.url(from: metaServerAddress) else {
            metaServerStatus = "That address doesn't look like one: try http://localhost:8080."
            return
        }
        isTestingMetaServer = true
        metaServerStatus = nil
        Task {
            do {
                // Always asks the server, so the counts are today's.
                let answer = try await MetaInsights(baseURL: url).load(MetaAPI.formats, force: true)
                if let failure = answer.refreshError {
                    metaServerStatus = "Couldn't reach \(url.absoluteString). \(failure.message)"
                } else {
                    metaServerStatus = answer.value.summary
                }
            } catch {
                metaServerStatus = "Couldn't reach \(url.absoluteString). \(MetaFailure(error).message)"
            }
            isTestingMetaServer = false
        }
    }

    private func performRedownload() async {
        isRedownloading = true
        redownloadStatus = "Clearing old data…"

        try? modelContext.delete(model: PKMN.self)
        try? modelContext.delete(model: Gen8Pokemon.self)
        try? modelContext.delete(model: Gen9Pokemon.self)
        try? modelContext.delete(model: PKMNStats.self)
        try? modelContext.delete(model: MoveData.self)
        try? modelContext.save()

        let container = modelContext.container

        do {
            redownloadStatus = "Downloading Pokedex data…"
            let pokeSync = PokeSyncManager(modelContainer: container)
            try await pokeSync.refreshPokedex()
            UserDefaults.standard.set(true, forKey: "hasCompletedInitialSync")

            redownloadStatus = "Downloading stats & moves…"
            let calcSync = CalcDataSyncManager(modelContainer: container)
            try await calcSync.syncCalcData()
            UserDefaults.standard.set(true, forKey: "hasCompletedCalcSyncV4")

            redownloadStatus = "Data updated successfully."
        } catch {
            redownloadStatus = "Failed: \(error.localizedDescription)"
        }

        isRedownloading = false
    }

    /// "Apr 8 – Jun 16, 2026" style window for a regulation, or `nil` when
    /// neither bound is recorded in its JSON. Used by the regulation picker
    /// so users can see at-a-glance which format covers which dates.
    private static func legalWindowString(for reg: ChampionsRegulation) -> String? {
        let period = reg.legalPeriod
        if period.from == nil && period.until == nil { return nil }
        let fmt = legalWindowDateFormatter
        let from = period.from.map { fmt.string(from: $0) } ?? "?"
        let until = period.until.map { fmt.string(from: $0) } ?? "TBD"
        return "\(from) – \(until)"
    }

    private static let legalWindowDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df
    }()

    private func performReset() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        try? modelContext.delete(model: PKMN.self)
        try? modelContext.delete(model: Gen8Pokemon.self)
        try? modelContext.delete(model: Gen9Pokemon.self)
        try? modelContext.delete(model: PKMNStats.self)
        try? modelContext.delete(model: MoveData.self)
        try? modelContext.delete(model: SavedSpread.self)
        try? modelContext.delete(model: SavedTeam.self)
        try? modelContext.save()
        Task {
            try? await TeamCorpusStore.shared.clearCache()
            try? await SmogonUsageStore.shared.clearCache()
            try? await MetaCache.shared.clear()
            teamSearchCacheBytes = 0
        }
    }

    /// Team Search's tournament teams and Smogon usage stats, and the PK
    /// Reference server's answers.
    private func teamSearchCacheSize() async -> Int {
        let teams = await TeamCorpusStore.shared.cacheSize()
        let usage = await SmogonUsageStore.shared.cacheSize()
        let meta = await MetaCache.shared.size()
        return teams + usage + meta
    }
}

// MARK: - Arrange Tabs

/// Reorders and hides tabs. Each row's switch hides or shows its tab, and
/// Reorder shows the drag handles. The two can't share a mode: a list in
/// edit mode ignores taps on its rows' switches. Changes are saved as they're
/// made; the tab bar applies them when the page closes, and each row's note
/// previews where its tab will land. Mac lists reorder by dragging, with no
/// edit mode, so there's no Reorder button there.
private struct TabSettingsView: View {
    @AppStorage(AppSettings.tabOrder) private var tabOrderRaw: String
    @AppStorage(AppSettings.hiddenTabs) private var hiddenTabsRaw: String
    @AppStorage(AppSettings.defaultTab) private var defaultTabRaw: String
    @Environment(\.isArrangingTabs) private var isArrangingTabs
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    private var layout: TabLayout {
        get { TabLayout(orderRaw: tabOrderRaw, hiddenRaw: hiddenTabsRaw) }
        nonmutating set {
            tabOrderRaw = newValue.orderRaw
            hiddenTabsRaw = newValue.hiddenRaw
            defaultTabRaw = newValue.launchTab(for: defaultTabRaw).rawValue
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(layout.order) { tab in
                    Toggle(isOn: Binding(
                        get: { !layout.hidden.contains(tab) },
                        set: { layout.setHidden(tab, !$0) }
                    )) {
                        row(for: tab)
                    }
                    #if os(iOS)
                    .disabled(editMode.isEditing || !layout.canHide(tab))
                    #else
                    .disabled(!layout.canHide(tab))
                    #endif
                }
                .onMove { layout.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                #if os(iOS)
                Text("Tap Reorder, then drag tabs to change the order. With more than five tabs, iPhone and narrow iPad windows show the first four in the tab bar and the rest under More. Settings always comes last, and at least one other tab stays shown. The tab bar updates when you leave this page.")
                #else
                Text("Drag tabs to change their order in the sidebar. At least one tab stays shown.")
                #endif
            }
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        .toolbar {
            Button(editMode.isEditing ? "Done" : "Reorder") {
                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
            }
            .fontWeight(editMode.isEditing ? .semibold : .regular)
        }
        #endif
        .navigationTitle("Arrange Tabs")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { isArrangingTabs.wrappedValue = true }
        .onDisappear { isArrangingTabs.wrappedValue = false }
    }

    private func row(for tab: AppTab) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.label)
                // Only a compact tab bar splits into bar and More.
                if TabLayout.usesMoreList(in: horizontalSizeClass), let note = placementNote(for: tab) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: tab.icon)
        }
    }

    private func placementNote(for tab: AppTab) -> String? {
        switch layout.compactPlacement(of: tab) {
        case .tabBar: return "In tab bar"
        case .more:   return "Under More"
        case .hidden: return nil
        }
    }
}
