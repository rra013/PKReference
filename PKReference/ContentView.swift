//
//  ContentView.swift
//  PKReference
//
//  Created by Rishi Anand on 4/13/26.
//

import SwiftUI
import SwiftData
import WebKit

// MARK: - Adaptive layout helper

extension EnvironmentValues {
    /// True when there's room for a multi-column / split ("wide") layout —
    /// i.e. a regular horizontal size class (large/foldable iPhone in landscape,
    /// iPad, wide multitasking panes). iPhone **portrait is always compact**, so
    /// this is the single gate that keeps portrait on its original,
    /// untouched single-column code path.
    var isWideLayout: Bool { horizontalSizeClass == .regular }
}

extension View {
    /// A sheet's size on the Mac, where a sheet is as big as its content
    /// asks, and a list asks for no height: the calc's Load Spread sheet
    /// opened as just its title bar. iOS sizes sheets itself.
    func sheetSize() -> some View {
        #if os(macOS)
        frame(minWidth: 480, idealWidth: 560, minHeight: 440, idealHeight: 640)
        #else
        self
        #endif
    }
}

/// A tab's list beside the selected item's page, for wide layouts. On iOS,
/// a split view whose detail has its own navigation stack. The Mac's
/// sidebar is already a split view, and a split view inside it pushed its
/// detail's content right by the sidebar's width a second time, leaving an
/// empty band and running the page off the window. So on the Mac the list
/// and page share the tab's navigation stack, which sits beside the
/// sidebar, in a resizable split; a page the detail opens is pushed over
/// both.
struct ListDetailSplit<ListColumn: View, Detail: View>: View {
    @ViewBuilder var list: ListColumn
    @ViewBuilder var detail: Detail

    var body: some View {
        #if os(macOS)
        TabNavigationStack {
            HSplitView {
                list.frame(minWidth: 260, idealWidth: 300, maxWidth: 440)
                detail.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #else
        NavigationSplitView {
            list
        } detail: {
            NavigationStack { detail }
        }
        #endif
    }
}

// MARK: - App Tab Definition

enum AppTab: String, CaseIterable, Identifiable {
    case monIndex, moveIndex, abilityIndex, damageCalc, sets, teams, speedTiers, problemSolver, battleSim, rngTools, meta, teamSearch, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monIndex:     return "Mon Index"
        case .moveIndex:    return "Move Index"
        case .abilityIndex: return "Ability Index"
        case .damageCalc:   return "Damage Calc"
        case .sets:         return "Sets"
        case .teams:        return "Teams"
        case .speedTiers:   return "Speed Tiers"
        case .problemSolver: return "Problem Solver"
        case .battleSim:    return "Battle Sim"
        case .rngTools:     return "RNG Tools"
        case .meta:         return "Meta"
        case .teamSearch:   return "Team Search"
        case .settings:     return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .monIndex:     return "list.bullet"
        case .moveIndex:    return "text.book.closed"
        case .abilityIndex: return "sparkles"
        case .damageCalc:   return "bolt.fill"
        case .sets:         return "square.and.pencil"
        case .teams:        return "person.3"
        case .speedTiers:   return "hare"
        case .problemSolver: return "scope"
        case .battleSim:    return "gamecontroller.fill"
        case .rngTools:     return "dice"
        case .meta:         return "chart.bar.xaxis"
        case .teamSearch:   return "sparkle.magnifyingglass"
        case .settings:     return "gear"
        }
    }

    static let allUserTabs: [AppTab] = [.monIndex, .moveIndex, .abilityIndex, .damageCalc, .sets, .teams, .speedTiers, .problemSolver, .battleSim, .rngTools, .meta, .teamSearch]
}

// MARK: - Accent Color

enum AppAccentColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .mint:   return .mint
        case .teal:   return .teal
        case .cyan:   return .cyan
        case .blue:   return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink:   return .pink
        }
    }
}

// MARK: - Appearance Mode

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// The viewer's appearance settings, applied to a window's content: the
/// main window, and on the Mac the Settings window too.
struct AppearanceSettings: ViewModifier {
    @AppStorage(AppSettings.accentColor) private var accentColorRaw: String
    @AppStorage(AppSettings.appearance) private var appearanceRaw: String
    @AppStorage(AppSettings.typeBadgeStyle) private var typeBadgeStyle: TypeBadgeStyle
    @AppStorage(AppSettings.matchupColors) private var matchupColors: MatchupColors
    @AppStorage(AppSettings.density) private var density: Density
    @AppStorage(AppSettings.typeBackgrounds) private var typeBackgrounds: Bool

    private var accentColor: Color {
        (AppAccentColor(rawValue: accentColorRaw) ?? .blue).color
    }

    private var appearance: ColorScheme? {
        (AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme
    }

    func body(content: Content) -> some View {
        content
            .tint(accentColor)
            .preferredColorScheme(appearance)
            .environment(\.typeBadgeStyle, typeBadgeStyle)
            .environment(\.matchupColors, matchupColors)
            .environment(\.density, density)
            .environment(\.typeBackgrounds, typeBackgrounds)
    }
}

struct ContentView: View {
    @AppStorage(AppSettings.tabOrder) private var tabOrderRaw: String
    @AppStorage(AppSettings.hiddenTabs) private var hiddenTabsRaw: String
    @AppStorage(AppSettings.defaultTab) private var defaultTabRaw: String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The arrangement the tab bar shows. It follows the stored one, except
    /// while the Arrange Tabs page is open.
    @State private var shownLayout: TabLayout
    /// Whether the tab bar shows the More list. It follows the window's
    /// width on iPad, with the same exception.
    @State private var showsMoreList: Bool
    @State private var selectedTab: RootTab
    /// The More tab's navigation, and the tab open in it (nil while the
    /// list shows).
    @State private var morePath = NavigationPath()
    @State private var moreOpenTab: AppTab?
    /// The default tab, when it lives under More: opened right after
    /// launch. A page in the stack's initial path is drawn without its
    /// large title until it's scrolled. Pages with a search field still
    /// are when opened in code rather than by a tap (iOS 26.4).
    @State private var launchTabInMore: AppTab?
    @State private var isArrangingTabs = false

    init() {
        // Read storage directly: `@AppStorage` values aren't available
        // until the view is installed, and the first frame should already
        // select the default tab, even one that lives under More.
        let defaults = UserDefaults.standard
        let layout = TabLayout(
            orderRaw: defaults.string(forKey: AppSettings.tabOrder.name) ?? AppSettings.tabOrder.defaultValue,
            hiddenRaw: defaults.string(forKey: AppSettings.hiddenTabs.name) ?? AppSettings.hiddenTabs.defaultValue)
        let launch = layout.launchTab(
            for: defaults.string(forKey: AppSettings.defaultTab.name) ?? AppSettings.defaultTab.defaultValue)
        // The size class isn't known yet either. A narrow iPad window
        // moves tabs under More when it arrives, in `applyStoredLayout`.
        let moreList = TabLayout.usesMoreList(in: nil)
        _shownLayout = State(initialValue: layout)
        _showsMoreList = State(initialValue: moreList)
        if Self.split(of: layout, moreList: moreList).more.contains(launch) {
            _selectedTab = State(initialValue: .more)
            _launchTabInMore = State(initialValue: launch)
        } else {
            _selectedTab = State(initialValue: .tab(launch))
        }
    }

    /// The tabs in the bar and in the More list, if there is one. On the
    /// Mac, the tabs are in a sidebar and Settings is its own window.
    private static func split(of layout: TabLayout, moreList: Bool) -> (bar: [AppTab], more: [AppTab]) {
        #if os(macOS)
        (layout.visible, [])
        #else
        moreList ? layout.compactSplit : (layout.visible + [.settings], [])
        #endif
    }

    var body: some View {
        let split = Self.split(of: shownLayout, moreList: showsMoreList)
        TabView(selection: $selectedTab) {
            #if os(macOS)
            ForEach(split.bar) { tab in
                Tab(tab.label, systemImage: tab.icon, value: RootTab.tab(tab)) {
                    tabContent(for: tab)
                }
            }
            #else
            ForEach(split.bar) { tab in
                tabContent(for: tab)
                    .tabItem { Label(tab.label, systemImage: tab.icon) }
                    .tag(RootTab.tab(tab))
            }
            if !split.more.isEmpty {
                MoreList(tabs: split.more, path: $morePath, openTab: $moreOpenTab) { tabContent(for: $0) }
                    .tabItem { Label("More", systemImage: "ellipsis") }
                    .tag(RootTab.more)
            }
            #endif
        }
        #if os(macOS)
        .tabViewStyle(.sidebarAdaptable)
        .focusedSceneValue(\.selectedTab, $selectedTab)
        .frame(minWidth: 900, minHeight: 600)
        // Forms were laid out for iOS's grouped sections. The Mac's default
        // puts labels and controls in two columns, which pushed the Set
        // Editor's rows off the side of the window.
        .formStyle(.grouped)
        #endif
        .modifier(AppearanceSettings())
        .environment(\.isArrangingTabs, $isArrangingTabs)
        .onChange(of: tabOrderRaw) { applyStoredLayout() }
        .onChange(of: hiddenTabsRaw) { applyStoredLayout() }
        .onChange(of: isArrangingTabs) { applyStoredLayout() }
        .onChange(of: horizontalSizeClass, initial: true) { applyStoredLayout() }
        .task {
            guard let tab = launchTabInMore else { return }
            launchTabInMore = nil
            await Task.yield()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                morePath = NavigationPath([tab])
                moreOpenTab = tab
            }
        }
        .onChange(of: AppNavigator.shared.request, initial: true) {
            guard let request = AppNavigator.shared.request else { return }
            Task {
                await Task.yield()
                show(request.tab)
            }
        }
    }

    /// Shows `tab` for an App Intent's request: in the bar or sidebar, or
    /// opened from the More list. The tab then takes the request; a request
    /// for a hidden tab is dropped.
    private func show(_ tab: AppTab) {
        let split = Self.split(of: shownLayout, moreList: showsMoreList)
        if split.bar.contains(tab) {
            selectedTab = .tab(tab)
        } else if split.more.contains(tab) {
            selectedTab = .more
            if moreOpenTab != tab {
                morePath = NavigationPath([tab])
                moreOpenTab = tab
            }
        } else {
            AppNavigator.shared.request = nil
        }
    }

    /// Brings the tab bar up to date with the stored arrangement and the
    /// window's width, keeping the open tab in view if it moved between the
    /// bar and the More list. A tab that moves is opened afresh in its new
    /// place, so resizing an iPad window across the compact width closes
    /// the tabs after the fourth.
    private func applyStoredLayout() {
        guard !isArrangingTabs else { return }
        let layout = TabLayout(orderRaw: tabOrderRaw, hiddenRaw: hiddenTabsRaw)
        let moreList = TabLayout.usesMoreList(in: horizontalSizeClass)
        guard layout != shownLayout || moreList != showsMoreList else { return }

        let wasInMore = selectedTab == .more
        let open: AppTab? = switch selectedTab {
        case .tab(let tab): tab
        case .more: moreOpenTab
        }
        let split = Self.split(of: layout, moreList: moreList)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            shownLayout = layout
            showsMoreList = moreList
            if let open {
                let nowInBar = split.bar.contains(open)
                let nowInMore = split.more.contains(open)
                if nowInBar && wasInMore {
                    selectedTab = .tab(open)
                    morePath = NavigationPath()
                    moreOpenTab = nil
                } else if nowInMore && !wasInMore {
                    selectedTab = .more
                    morePath = NavigationPath([open])
                    moreOpenTab = open
                } else if !nowInBar && !nowInMore {
                    // The open tab was hidden.
                    selectedTab = .tab(split.bar[0])
                    morePath = NavigationPath()
                    moreOpenTab = nil
                }
                // Otherwise it's still where it was.
            } else if split.more.isEmpty {
                // The More list was showing, and it's gone.
                selectedTab = .tab(split.bar[0])
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .monIndex:     PokedexTab()
        case .moveIndex:    MoveIndexTab()
        case .abilityIndex: AbilityIndexTab()
        case .damageCalc:   DamageCalculatorView()
        case .sets:         SetListView()
        case .teams:        TeamListView()
        case .speedTiers:   SpeedTierView()
        case .problemSolver: ProblemSolverView()
        case .battleSim:    BattleSimulatorView()
        case .rngTools:     RNGToolsView()
        case .meta:         MetaTab()
        case .teamSearch:   TeamSearchView()
        case .settings:     SettingsView()
        }
    }
}

// MARK: - Pokédex Tab (extracted from original ContentView)

private struct PokedexTab: View {
    @Query(sort: \PKMN.nationalPokedexNumber) private var allPokemon: [PKMN]
    @AppStorage(AppSettings.defaultGeneration) private var defaultGeneration: String
    @State private var selectedFilter: PokedexFilter?
    @State private var searchText = ""
    @State private var championsFilters: ChampionsFilters = .none
    @State private var showFilterSheet: Bool = false
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.isInMoreList) private var isInMoreList
    @State private var selectedMon: PKMN?
    /// Compact-layout navigation path. Value-based navigation rather than
    /// destination-based `NavigationLink` so there's an observable value to
    /// hang the selection haptic on — a destination-based link changes no
    /// state we can see.
    @State private var path: [PKMN] = []
    /// A Pokémon an App Intent asked to open while this tab is under More,
    /// whose navigation stack is the More list's.
    @State private var requestedMon: PKMN?
    /// Whether the list has been on screen a moment, so a request can be
    /// shown; see the task that sets it.
    @State private var isSettled = false
    /// The form an App Intent asked to open a Pokémon on, until another
    /// Pokémon is chosen.
    @State private var requestedForm: RequestedForm?

    private struct RequestedForm: Equatable {
        let speciesID: Int
        let form: FormChoice
    }

    /// A detail page's identity: a new page for each Pokémon, and for a
    /// request to open it on another form.
    private struct PageID: Hashable {
        let pokemon: PersistentIdentifier
        let form: FormChoice
    }

    /// The form to open `mon`'s page on: the requested one, if any.
    private func form(for mon: PKMN) -> FormChoice {
        requestedForm?.speciesID == mon.nationalPokedexNumber ? requestedForm?.form ?? .base : .base
    }

    private var activeFilter: PokedexFilter {
        selectedFilter ?? PokedexFilter(rawValue: defaultGeneration) ?? .champions
    }

    /// Champions filters only apply to the Champions list — when the user
    /// switches to a generation view, hand the empty value down so
    /// `FilteredList` skips its match pass entirely.
    private var effectiveChampionsFilters: ChampionsFilters {
        activeFilter == .champions ? championsFilters : .none
    }

    var body: some View {
        Group {
            // Wide layouts get a roster/detail split; compact (portrait) keeps the
            // original single-column push navigation, unchanged.
            if hSize == .regular {
                wideBody
            } else if isInMoreList {
                // Opened from the More list: its stack does the pushing, so
                // there's no path of ours to tick the haptic on.
                compactColumn
            } else {
                NavigationStack(path: $path) {
                    compactColumn
                }
                // The push animation reads as "something happened next" rather
                // than "your tap landed". Ticking on the path change confirms the
                // hit at the moment it registers.
                .sensoryFeedback(.selection, trigger: path)
            }
        }
        .onChange(of: AppNavigator.shared.request) {
            if isSettled { openRequestedPokemon() }
        }
        // Choosing another Pokémon, or going back to the list, ends the
        // request: the requested Pokémon opens on its base form next time.
        .onChange(of: selectedMon) {
            if selectedMon?.nationalPokedexNumber != requestedForm?.speciesID { requestedForm = nil }
        }
        .onChange(of: path) { if path.isEmpty { requestedForm = nil } }
        .onChange(of: requestedMon) { if requestedMon == nil { requestedForm = nil } }
        .task {
            // This tab is on screen from launch, so a request that opened
            // the app arrives during its first layout, when a selection is
            // lost (on the Mac it can lay the split view out absurdly wide,
            // as `DebugSnapshot.openFirstItem` found) and the search field
            // drops text set before it exists. So that request waits a
            // moment, as a click would. The tab is built twice at launch;
            // the first, discarded at once, leaves the request alone.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            isSettled = true
            openRequestedPokemon()
        }
    }

    /// Opens the Pokémon an App Intent asked for, by National Dex number:
    /// selected beside the list, or pushed. An in-app search that names no
    /// Pokémon fills in the search field instead.
    private func openRequestedPokemon() {
        if case .indexSearch(.monIndex, let term) = AppNavigator.shared.request {
            AppNavigator.shared.request = nil
            searchText = term
            return
        }
        guard case .pokemon(let speciesID, let form) = AppNavigator.shared.request else { return }
        AppNavigator.shared.request = nil
        guard let mon = allPokemon.first(where: { $0.nationalPokedexNumber == speciesID }) else { return }
        // A form the regulation lists; otherwise the species' page as usual.
        requestedForm = form
            .flatMap { form in ChampionsLearnsetStore.shared.data(for: mon.name).flatMap { FormChoice.matching(form, in: $0) } }
            .map { RequestedForm(speciesID: speciesID, form: $0) }
        if hSize == .regular {
            selectedMon = mon
        } else if isInMoreList {
            requestedMon = mon
        } else {
            path = [mon]
        }
    }

    private var compactColumn: some View {
        indexColumn(selection: nil)
            .navigationDestination(for: PKMN.self) { mon in
                monIndexDestination(for: mon, filter: activeFilter, form: form(for: mon))
            }
            .navigationDestination(item: $requestedMon) { mon in
                monIndexDestination(for: mon, filter: activeFilter, form: form(for: mon))
            }
    }

    /// Two-pane split for wide layouts: roster list on the left, live detail on
    /// the right (no push/pop — ideal for glancing alongside the game).
    private var wideBody: some View {
        ListDetailSplit {
            indexColumn(selection: $selectedMon)
        } detail: {
            if let selectedMon {
                // A new page for each Pokémon, so a form or move search
                // chosen on one doesn't carry over to the next.
                monIndexDestination(for: selectedMon, filter: activeFilter, form: form(for: selectedMon))
                    .id(PageID(pokemon: selectedMon.persistentModelID, form: form(for: selectedMon)))
            } else {
                ContentUnavailableView {
                    Label("Select a Pokémon", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a Pokémon from the list to see its details.")
                }
            }
        }
        #if DEBUG && os(macOS)
        .task {
            await DebugSnapshot.openFirstItem {
                selectedMon = allPokemon.first { activeFilter != .champions || championsRoster.contains($0.name) }
            }
        }
        #endif
        // Drop the selection when the roster changes so the detail pane never
        // shows a mon that isn't in the newly-selected dex/regulation.
        .onChange(of: activeFilter) { _, _ in selectedMon = nil }
        // Picking a mon is the natural "done searching" signal — put the
        // keyboard away so the detail pane isn't obscured.
        .onChange(of: selectedMon) { _, newValue in
            if newValue != nil { dismissSearchKeyboard() }
        }
        // The wide layout has no push animation, so a sidebar tap otherwise
        // only registers as a tint change in the corner of the eye. A
        // selection tick confirms the hit — especially useful while the detail
        // pane's web view is still loading.
        .sensoryFeedback(.selection, trigger: selectedMon)
    }

    private func dismissSearchKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil)
        #endif
    }

    /// The roster column (list + search + filters). `selection == nil` renders
    /// today's push rows (compact); a non-nil binding drives the split detail.
    @ViewBuilder
    private func indexColumn(selection: Binding<PKMN?>?) -> some View {
        Group {
            if allPokemon.isEmpty {
                ContentUnavailableView {
                    Label("No Mons Found", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Syncing with PokeAPI... please wait.")
                }
            } else {
                VStack(spacing: 0) {
                    if activeFilter == .champions && championsFilters.isActive {
                        ChampionsFilterChipStrip(filters: $championsFilters)
                            .background(.bar)
                    }
                    FilteredList(filter: activeFilter,
                                 searchText: searchText,
                                 championsFilters: effectiveChampionsFilters,
                                 selection: selection)
                }
                // No tap-to-dismiss gesture on the roster: a tap recognizer
                // above the `List` swallows row taps, so rows stopped
                // selecting in the wide layout (iOS 26.4) as they once
                // stopped pushing in the compact one. Picking a Pokémon,
                // the Search key and scrolling all put the keyboard away.
            }
        }
        .navigationTitle("Mon Index")
        .searchable(text: $searchText, prompt: "Search Mons")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(PokedexFilter.allCases) { filter in
                        Button(filter.title) { selectedFilter = filter }
                    }
                } label: {
                    Label(activeFilter.title, systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            if activeFilter == .champions {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        Label("Filters",
                              systemImage: championsFilters.isActive
                                ? "slider.horizontal.3"
                                : "slider.horizontal.below.rectangle")
                            .symbolVariant(championsFilters.isActive ? .fill : .none)
                    }
                }
            }
        }
        // Wide layout only: the split sidebar's search keyboard can't be
        // dismissed by dragging when a search narrows the list to a few rows
        // (nothing to scroll). A `.searchable` field is a UIKit `UISearchBar`,
        // so a SwiftUI `.keyboard` toolbar won't attach — instead dismiss on the
        // keyboard's Search/return key. Gated to `.regular` so portrait's return
        // behavior is left exactly as-is.
        .onSubmit(of: .search) {
            if hSize == .regular { dismissSearchKeyboard() }
        }
        .sheet(isPresented: $showFilterSheet) {
            ChampionsFilterSheet(
                filters: $championsFilters,
                availableAbilities: ChampionsFilterOptions.availableAbilities(),
                availableMoves: ChampionsFilterOptions.availableMoves()
            )
            .sheetSize()
        }
    }
}

// MARK: - Filter Enum

enum PokedexFilter: String, CaseIterable, Identifiable {
    case all, gen1, gen2, gen3, gen4, gen5, gen6, gen7, gen8, gen9, champions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:       return "All"
        case .gen1:      return "Gen I"
        case .gen2:      return "Gen II"
        case .gen3:      return "Gen III"
        case .gen4:      return "Gen IV"
        case .gen5:      return "Gen V"
        case .gen6:      return "Gen VI"
        case .gen7:      return "Gen VII"
        case .gen8:      return "Gen VIII"
        case .gen9:      return "Gen IX"
        case .champions: return "Champions"
        }
    }
}

// MARK: - Filtered List

struct FilteredList: View {
    @Query private var filteredPokemon: [PKMN]
    @Query(sort: \PKMNStats.id) private var allStats: [PKMNStats]
    private let filter: PokedexFilter
    private let searchText: String
    private let championsFilters: ChampionsFilters
    /// When non-nil the list drives a `NavigationSplitView` detail pane via this
    /// selection (wide layout). When nil it renders today's push
    /// `NavigationLink` rows verbatim (compact / portrait).
    private let selection: Binding<PKMN?>?

    init(filter: PokedexFilter,
         searchText: String,
         championsFilters: ChampionsFilters = .none,
         selection: Binding<PKMN?>? = nil) {
        self.filter = filter
        self.searchText = searchText
        self.championsFilters = championsFilters
        self.selection = selection
        let predicate: Predicate<PKMN> = {
            switch filter {
            case .all:       return #Predicate<PKMN> { _ in true }
            case .gen1:      return #Predicate<PKMN> { $0.genOneLink != nil }
            case .gen2:      return #Predicate<PKMN> { $0.genTwoLink != nil }
            case .gen3:      return #Predicate<PKMN> { $0.genThreeLink != nil }
            case .gen4:      return #Predicate<PKMN> { $0.genFourLink != nil }
            case .gen5:      return #Predicate<PKMN> { $0.genFiveLink != nil }
            case .gen6:      return #Predicate<PKMN> { $0.genSixLink != nil }
            case .gen7:      return #Predicate<PKMN> { $0.genSevenLink != nil }
            case .gen8:      return #Predicate<PKMN> { $0.genEightLink != nil }
            case .gen9:      return #Predicate<PKMN> { $0.genNineLink != nil }
            // Champions is filtered AT RUNTIME against the live regulation
            // roster (`championsRoster` -> `ChampionsRegulation.current`) so
            // edits to the bundled JSON take effect without requiring users
            // to re-sync the Pokedex. The `@Query` returns every species;
            // the actual whitelist filter happens in `visiblePokemon`.
            case .champions: return #Predicate<PKMN> { _ in true }
            }
        }()
        _filteredPokemon = Query(filter: predicate, sort: \.nationalPokedexNumber)
    }

    private var visiblePokemon: [PKMN] {
        // Apply the regulation roster filter live for Champions so changes to
        // the bundled JSON appear without a Pokedex re-sync. The other filters
        // are already scoped at the @Query layer via their gen-link predicates.
        let baseList: [PKMN] = {
            guard filter == .champions else { return filteredPokemon }
            let roster = championsRoster
            return filteredPokemon.filter { roster.contains($0.name) }
        }()

        // Type / ability / move filters. The match needs every form belonging
        // to a species (base + mega + regional) so a "Dragon" filter still
        // surfaces Charizard because of Mega-Y. Build the lookup once per
        // body evaluation rather than per row, and hoist the learnset store
        // out of the per-row predicate so it isn't re-resolved (UserDefaults
        // read + NSLock acquire) ~250 times per render.
        let filteredByChampions: [PKMN]
        if championsFilters.isActive {
            var formsBySpeciesID: [Int: [PKMNStats]] = [:]
            var speciesIDByName: [String: Int] = [:]
            for stats in allStats {
                formsBySpeciesID[stats.speciesID, default: []].append(stats)
                if !stats.isForm {
                    speciesIDByName[stats.name] = stats.speciesID
                } else if speciesIDByName[stats.name] == nil {
                    // Fall back when the base entry isn't loaded yet — this
                    // way Mega-only species still get a species-ID hit.
                    speciesIDByName[stats.name] = stats.speciesID
                }
            }
            let store = ChampionsLearnsetStore.shared
            filteredByChampions = baseList.filter { pkmn in
                let speciesID = speciesIDByName[pkmn.name]
                let forms = speciesID.flatMap { formsBySpeciesID[$0] } ?? []
                return championsFilters.matches(speciesName: pkmn.name,
                                                formStats: forms,
                                                store: store)
            }
        } else {
            filteredByChampions = baseList
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return filteredByChampions }
        return filteredByChampions.filter {
            $0.name.localizedStandardContains(trimmed) ||
            String($0.nationalPokedexNumber).contains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(filter.title).font(.headline)
                Spacer()
                Text("\(visiblePokemon.count)").foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if let selection {
                // Wide layout: selection-driven rows feed the split-view detail
                // pane. No per-row NavigationLink — the detail column observes
                // `selection`.
                List(selection: selection) {
                    ForEach(visiblePokemon) { pokemon in
                        PokemonRow(pokemon: pokemon).tag(pokemon)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                // Compact layout: push navigation, now value-based so the
                // enclosing `NavigationStack`'s path drives the haptic. The
                // destination itself is built by `monIndexDestination`, which
                // the wide layout already shares.
                List(visiblePokemon) { pokemon in
                    // Rows with no detail page in this dex stay inert, exactly
                    // as they did before — only rows that go somewhere become
                    // links.
                    if filter == .champions || pokemon.detailURL(for: filter) != nil {
                        NavigationLink(value: pokemon) {
                            PokemonRow(pokemon: pokemon)
                        }
                        .buttonStyle(MonRowPressStyle())
                    } else {
                        PokemonRow(pokemon: pokemon)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }
}

/// Detail destination for a Mon Index row — the Champions structured page, or
/// the Serebii web view for generation dexes. Shared by the compact push rows
/// (implicitly, via the same views) and the wide split-view detail pane.
@ViewBuilder
func monIndexDestination(for pokemon: PKMN, filter: PokedexFilter, form: FormChoice = .base) -> some View {
    let detailURL = pokemon.detailURL(for: filter)
    if filter == .champions {
        ChampionsPokemonDetailView(pokemon: pokemon, detailURL: detailURL, form: form)
    } else if let detailURL {
        PokemonDetailView(pokemon: pokemon, filter: filter, detailURL: detailURL)
    } else {
        ContentUnavailableView {
            Label(pokemon.name, systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("No detail page is available for this Pokémon in the \(filter.title) dex.")
        }
    }
}

// MARK: - Row & Detail Views

/// Press highlight for Mon Index rows.
///
/// `NavigationLink` exposes no pressed state, so the highlight has to come
/// from a button style applied to the link itself. The fill is grown past the
/// label with negative padding so it reads as a full-row highlight without
/// touching the row's layout metrics — `listRowInsets` would have shifted
/// every row's spacing to achieve the same thing.
private struct MonRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.09 : 0))
                    .padding(.vertical, -6)
                    .padding(.horizontal, -10)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PokemonRow: View {
    let pokemon: PKMN

    var body: some View {
        HStack {
            Text(pokemon.dexLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .scaledWidth(50, alignment: .leading)
            Text(pokemon.name)
            // Claim the full row width so the highlight and hit target cover
            // the whole cell rather than just the two labels.
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

private struct PokemonDetailView: View {
    let pokemon: PKMN
    let filter: PokedexFilter
    let detailURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(filter.title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Link(detailURL.absoluteString, destination: detailURL)
                .font(.footnote)
            PokemonWebView(url: detailURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .navigationTitle(pokemon.name)
        .padding()
    }
}

private struct PokemonWebView: ViewRepresentable {
    let url: URL

    func makeView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
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
private typealias ViewRepresentable = UIViewRepresentable
private extension PokemonWebView {
    func makeUIView(context: Context) -> WKWebView { makeView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { updateView(webView, context: context) }
}
#else
private typealias ViewRepresentable = NSViewRepresentable
private extension PokemonWebView {
    func makeNSView(context: Context) -> WKWebView { makeView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { updateView(webView, context: context) }
}
#endif

// MARK: - URL Helper

private extension PKMN {
    /// Champions Serebii URL with live fallback. Prefers the stored
    /// `champsLink` (populated at Pokedex sync time) but computes the URL
    /// on the fly for species that were added to the regulation roster
    /// after the last sync — so a newly-included species like Scovillain
    /// gets a working tap-through without forcing the user to re-sync.
    /// Returns nil for species that aren't in the current regulation
    /// roster, so the `.all` fall-through path correctly skips ahead to
    /// gen links instead of building broken champions URLs.
    var resolvedChampsLink: String? {
        if let stored = champsLink { return stored }
        guard championsRoster.contains(name) else { return nil }
        // Match the slug `pokedbPopulator` produced from PokeAPI's
        // lowercase-hyphenated `pokemon_species.name` (e.g. "mr-rime",
        // "kommo-o"). Apostrophes and dots get stripped, spaces become
        // hyphens; existing hyphens are preserved.
        let slug = name.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: " ", with: "-")
        return "https://serebii.net/pokedex-champions/\(slug)/"
    }

    func detailURL(for filter: PokedexFilter) -> URL? {
        let link: String? = switch filter {
        case .all:       resolvedChampsLink ?? genNineLink ?? genEightLink ?? genSevenLink ?? genSixLink ?? genFiveLink ?? genFourLink ?? genThreeLink ?? genTwoLink ?? genOneLink
        case .gen1:      genOneLink
        case .gen2:      genTwoLink
        case .gen3:      genThreeLink
        case .gen4:      genFourLink
        case .gen5:      genFiveLink
        case .gen6:      genSixLink
        case .gen7:      genSevenLink
        case .gen8:      genEightLink
        case .gen9:      genNineLink
        case .champions: resolvedChampsLink
        }
        guard let link else { return nil }
        return URL(string: link)
    }
}
