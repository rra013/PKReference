import SwiftUI

// MARK: - GameCube RNG View

enum GameCubeGame: String, CaseIterable, Identifiable {
    case colosseum = "Colosseum"
    case xd = "XD: Gales of Darkness"
    var id: String { rawValue }
    var pfGameValue: UInt32 {
        switch self {
        case .colosseum: return PFGame.colosseum.rawValue
        case .xd: return PFGame.gales.rawValue
        }
    }
}

enum GameCubeMode: String, CaseIterable, Identifiable {
    case shadow = "Shadow"
    case nonShadow = "Non-Shadow"
    case channel = "Channel Jirachi"
    case pokeSpot = "Poké Spot"
    var id: String { rawValue }
}

enum GameCubeSearchMode: String, CaseIterable, Identifiable {
    case generator = "Generator"
    case searcher = "Searcher"
    var id: String { rawValue }
}

struct GameCubeRNGView: View {
    @State private var selectedGame: GameCubeGame = .xd
    @State private var mode: GameCubeMode = .shadow
    @State private var searchMode: GameCubeSearchMode = .generator

    // Profile
    @State private var tid: UInt16 = 0
    @State private var sid: UInt16 = 0
    @State private var savedProfiles: [FinderProfile] = FinderProfileStore.load()
    @State private var selectedProfileID: UUID? = FinderProfileStore.lastProfileID

    // Seed & Advances (generator)
    @State private var seedText = ""
    @State private var initialAdvances: Int = 0
    @State private var maxAdvances: Int = 10000

    // Searcher IV ranges
    @State private var minHP: UInt8 = 0
    @State private var maxHP: UInt8 = 31
    @State private var minAtk: UInt8 = 0
    @State private var maxAtk: UInt8 = 31
    @State private var minDef: UInt8 = 0
    @State private var maxDef: UInt8 = 31
    @State private var minSpA: UInt8 = 0
    @State private var maxSpA: UInt8 = 31
    @State private var minSpD: UInt8 = 0
    @State private var maxSpD: UInt8 = 31
    @State private var minSpe: UInt8 = 0
    @State private var maxSpe: UInt8 = 31

    // Shadow
    @State private var shadowTemplates: [PFBridge.ShadowTemplateInfo] = []
    @State private var selectedShadowIndex: Int = 0
    @State private var unset: Bool = false

    // Non-shadow static (type 8 = gales/colo, type 9 = channel)
    @State private var staticTemplates: [PFStaticTemplateSwift] = []
    @State private var selectedStaticIndex: Int = 0

    // PokeSpot
    @State private var pokeSpotAreas: [PFBridge.PokeSpotArea] = []
    @State private var selectedPokeSpotIndex: Int = 0
    @State private var seedFoodText = ""
    @State private var seedEncounterText = ""
    @State private var initialAdvancesEncounter: Int = 0
    @State private var maxAdvancesEncounter: Int = 10000

    // Filters
    @State private var selectedNatures: Set<UInt8> = []
    @State private var shinyOnly: Bool = false

    // Generator results
    @State private var results: [PFBridge.GameCubeResult] = []
    @State private var searcherResults: [PFSearcherStateSwift] = []
    @State private var pokeSpotResults: [PFBridge.PokeSpotResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var searchWorkTask: Task<Void, Never>?
    /// 0–100, or -1 before the first report.
    @State private var searchProgress: Double = -1
    private var isSearching: Bool { searchTask != nil }
    /// The last search stopped at `searchResultLimit`.
    @State private var stoppedAtLimit = false
    /// The last search or generate ran to the end, for saying it found
    /// nothing.
    @State private var finished = false

    /// What a running search or generate sends back.
    private enum SearchEvent: Sendable {
        case generated([PFBridge.GameCubeResult])
        case pokeSpot([PFBridge.PokeSpotResult])
        case searched([PFSearcherStateSwift])
        case progress(Double)
    }

    /// The list the current mode fills.
    private var resultCount: Int {
        mode == .pokeSpot ? pokeSpotResults.count : searchMode == .searcher ? searcherResults.count : results.count
    }

    /// The filters that are set, for when nothing's found.
    private var setFilterNames: [String] {
        var names: [String] = []
        // Only the Searcher shows the IV ranges.
        if searchMode == .searcher && mode != .pokeSpot
            && ([minHP, minAtk, minDef, minSpA, minSpD, minSpe].contains { $0 > 0 }
                || [maxHP, maxAtk, maxDef, maxSpA, maxSpD, maxSpe].contains { $0 < 31 }) {
            names.append("IVs")
        }
        if !selectedNatures.isEmpty { names.append("natures") }
        if shinyOnly { names.append("Shiny Only") }
        return names
    }

    // Seed Searcher
    @State private var showSeedSearcher = false

    // Jirachi Pattern
    @State private var showJirachiPattern = false

    var body: some View {
        ScrollView {
            CardStack {
                Picker("Game", selection: $selectedGame) {
                    ForEach(GameCubeGame.allCases) { g in Text(g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: selectedGame) { loadTemplates() }

                Picker("Mode", selection: $mode) {
                    ForEach(availableModes) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: mode) { loadTemplates() }

                if mode != .pokeSpot {
                    Picker("", selection: $searchMode) {
                        ForEach(GameCubeSearchMode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Profile
                SectionCard(title: "Trainer", icon: "person") {
                    if !savedProfiles.isEmpty {
                        Picker("Profile", selection: $selectedProfileID) {
                            Text("None").tag(UUID?.none)
                            ForEach(savedProfiles) { p in
                                Text(p.displayName).tag(UUID?.some(p.id))
                            }
                        }
                        .onChange(of: selectedProfileID) {
                            if let pid = selectedProfileID,
                               let profile = savedProfiles.first(where: { $0.id == pid }) {
                                tid = profile.tid
                                sid = profile.sid
                            }
                        }
                    }
                    FinderUInt16Field(label: "TID", value: $tid)
                    FinderUInt16Field(label: "SID", value: $sid)
                }

                if mode == .pokeSpot {
                    pokeSpotInputs
                } else if searchMode == .generator {
                    generatorInputs
                } else {
                    searcherInputs
                }

                // Pokemon selection
                if mode == .shadow {
                    shadowPicker
                } else if mode == .nonShadow {
                    staticPicker
                } else if mode == .pokeSpot {
                    pokeSpotPicker
                }

                FinderNatureGrid(selected: $selectedNatures)

                Toggle("Shiny Only", isOn: $shinyOnly)
                    .padding(.horizontal)

                if isSearching {
                    VStack(spacing: 8) {
                        if searchProgress < 0 {
                            ProgressView()
                                .padding(.vertical, 4)
                        } else {
                            ProgressView(value: searchProgress, total: 100)
                                .progressViewStyle(.linear)
                                .padding(.horizontal)
                            Text("\(Int(searchProgress))% — \(resultCount) found")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button {
                            stopSearch()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.primaryAction)
                        .tint(.red)
                    }
                } else {
                    Button {
                        executeSearch()
                    } label: {
                        Label(searchMode == .searcher && mode != .pokeSpot ? "Search" : "Generate",
                              systemImage: "sparkles")
                    }
                    .buttonStyle(.primaryAction)
                    if stoppedAtLimit {
                        Text(searchResultLimitNote)
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if finished && resultCount == 0 {
                        Text(noResultsText(filters: setFilterNames,
                                           widen: searchMode == .searcher && mode != .pokeSpot ? nil : "the advances"))
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if mode == .pokeSpot && !pokeSpotResults.isEmpty {
                    pokeSpotResultsSection
                } else if searchMode == .searcher && !searcherResults.isEmpty && mode != .pokeSpot {
                    searcherResultsSection
                } else if !results.isEmpty {
                    resultsSection
                }

                // Tools section
                SectionCard(title: "Tools", icon: "wrench") {
                    Button {
                        showSeedSearcher = true
                    } label: {
                        Label("Seed Searcher", systemImage: "magnifyingglass")
                    }

                    if selectedGame == .xd {
                        Button {
                            showJirachiPattern = true
                        } label: {
                            Label("Jirachi Pattern", systemImage: "star")
                        }
                    }
                }
            }
            .padding()
        }
        .dismissesKeyboard()
        .onAppear { loadTemplates() }
        .onDisappear { stopSearch() }
        // Results found for another game, mode or Pokémon would read as this one's.
        .onChange(of: [selectedGame.rawValue, mode.rawValue, "\(selectedShadowIndex)", "\(selectedStaticIndex)",
                       "\(selectedPokeSpotIndex)", "\(unset)"]) { clearResults() }
        // The Searcher and Generator keep their own lists.
        .onChange(of: searchMode) { stopSearch() }
        #if DEBUG && os(macOS)
        // With `-debugOpenSheet gameCubeSearch`: searches the first shadow
        // Pokémon for shinies, as Search does. Few turn up, so a snapshot
        // catches it running (drawing 500 results for one takes minutes).
        .task {
            await DebugSnapshot.openSheet("gameCubeSearch") {
                searchMode = .searcher
                shinyOnly = true
                executeSearch()
            }
        }
        #endif
        .leaveWarning(isSearching ? "The search in progress will stop." : nil)
        .sheet(isPresented: $showSeedSearcher) {
            NavigationStack {
                SeedSearcherView(game: selectedGame)
                    .navigationTitle("Seed Searcher")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSeedSearcher = false }
                        }
                    }
            }
            .sheetSize()
        }
        .sheet(isPresented: $showJirachiPattern) {
            NavigationStack {
                JirachiPatternView()
                    .navigationTitle("Jirachi Pattern")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showJirachiPattern = false }
                        }
                    }
            }
            .sheetSize()
        }
    }

    private var availableModes: [GameCubeMode] {
        if selectedGame == .xd {
            return GameCubeMode.allCases
        } else {
            return [.shadow, .nonShadow]
        }
    }

    private var generatorInputs: some View {
        SectionCard(title: "Seed", icon: "number") {
            HStack {
                Text("Seed")
                Spacer()
                TextField("Hex", text: $seedText)
                    .textFieldStyle(.roundedBorder).scaledWidth(120)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            RNGIntField(label: "Initial Advance", value: $initialAdvances, range: RNGFieldRange.advances)
            RNGIntField(label: "Max Advance", value: $maxAdvances, range: RNGFieldRange.advances)
        }
    }

    private var searcherInputs: some View {
        SectionCard(title: "IV Ranges", icon: "number.square") {
            FinderIVRangeRow(label: "HP", min: $minHP, max: $maxHP)
            FinderIVRangeRow(label: "Attack", min: $minAtk, max: $maxAtk)
            FinderIVRangeRow(label: "Defense", min: $minDef, max: $maxDef)
            FinderIVRangeRow(label: "Sp. Atk", min: $minSpA, max: $maxSpA)
            FinderIVRangeRow(label: "Sp. Def", min: $minSpD, max: $maxSpD)
            FinderIVRangeRow(label: "Speed", min: $minSpe, max: $maxSpe)
        }
    }

    private var pokeSpotInputs: some View {
        SectionCard(title: "Seeds", icon: "number") {
            HStack {
                Text("Food Seed")
                Spacer()
                TextField("Hex", text: $seedFoodText)
                    .textFieldStyle(.roundedBorder).scaledWidth(120)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            HStack {
                Text("Encounter Seed")
                Spacer()
                TextField("Hex", text: $seedEncounterText)
                    .textFieldStyle(.roundedBorder).scaledWidth(120)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            RNGIntField(label: "Food Init Adv", value: $initialAdvances, range: RNGFieldRange.advances)
            RNGIntField(label: "Food Max Adv", value: $maxAdvances, range: RNGFieldRange.advances)
            RNGIntField(label: "Enc Init Adv", value: $initialAdvancesEncounter, range: RNGFieldRange.advances)
            RNGIntField(label: "Enc Max Adv", value: $maxAdvancesEncounter, range: RNGFieldRange.advances)
        }
    }

    private var filteredShadowTemplates: [PFBridge.ShadowTemplateInfo] {
        shadowTemplates.filter { t in
            if selectedGame == .colosseum { return t.isColosseum }
            return !t.isColosseum
        }
    }

    private var shadowPicker: some View {
        SectionCard(title: "Shadow Pokemon", icon: "flame") {
            let filtered = filteredShadowTemplates
            if filtered.isEmpty {
                Text("No shadow templates available")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Pokemon", selection: $selectedShadowIndex) {
                    ForEach(filtered) { t in
                        Text("\(t.specieName) (Lv. \(t.level))")
                            .tag(t.id)
                    }
                }
                if selectedGame == .xd {
                    Toggle("1st Shadow Unset", isOn: $unset)
                }
            }
        }
    }

    private var staticPicker: some View {
        SectionCard(title: "Static Pokemon", icon: "star") {
            if staticTemplates.isEmpty {
                Text("No static templates available")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Pokemon", selection: $selectedStaticIndex) {
                    ForEach(Array(staticTemplates.enumerated()), id: \.offset) { idx, t in
                        Text("\(t.specieName) (Lv. \(t.level))")
                            .tag(idx)
                    }
                }
            }
        }
    }

    private var pokeSpotPicker: some View {
        SectionCard(title: "Poké Spot", icon: "mappin.and.ellipse") {
            if pokeSpotAreas.isEmpty {
                Text("No Poké Spot data available")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Location", selection: $selectedPokeSpotIndex) {
                    ForEach(Array(pokeSpotAreas.enumerated()), id: \.offset) { idx, area in
                        Text(area.locationName).tag(idx)
                    }
                }

                if selectedPokeSpotIndex < pokeSpotAreas.count {
                    let area = pokeSpotAreas[selectedPokeSpotIndex]
                    ForEach(area.slots) { slot in
                        HStack {
                            Text(slot.specieName).font(.caption)
                            Spacer()
                            Text("Lv\(slot.minLevel)-\(slot.maxLevel)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var resultsSection: some View {
        SectionCard(title: "Results (\(results.count))", icon: "list.bullet") {
            ForEach(results.prefix(500)) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Adv: \(r.advances)")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        if r.shiny > 0 {
                            Image(systemName: "star.fill")
                                .font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                    HStack {
                        Text("PID: \(String(format: "%08X", r.pid))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(pfNatureNames[Int(r.nature)])
                            .font(.caption2).bold()
                        Text(r.gender == 0 ? "♂" : r.gender == 1 ? "♀" : "-")
                            .font(.caption2)
                    }
                    Text("IVs: \(r.ivs.map(String.init).joined(separator: "/"))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("HP: \(hiddenPowerTypes[Int(r.hiddenPower)])")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("(\(r.hiddenPowerStrength))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                Divider()
            }
        }
    }

    private var searcherResultsSection: some View {
        SectionCard(title: "Results (\(searcherResults.count))", icon: "list.bullet") {
            ForEach(searcherResults.prefix(500)) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Seed: \(String(format: "%08X", r.seed))")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        if r.shiny > 0 {
                            Image(systemName: "star.fill")
                                .font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                    HStack {
                        Text("PID: \(String(format: "%08X", r.pid))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(pfNatureNames[Int(r.nature)])
                            .font(.caption2).bold()
                        Text(r.gender == 0 ? "♂" : r.gender == 1 ? "♀" : "-")
                            .font(.caption2)
                    }
                    Text("IVs: \(r.ivs.map(String.init).joined(separator: "/"))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("HP: \(hiddenPowerTypes[Int(r.hiddenPower)])")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("(\(r.hiddenPowerStrength))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                Divider()
            }
        }
    }

    private var pokeSpotResultsSection: some View {
        SectionCard(title: "Results (\(pokeSpotResults.count))", icon: "list.bullet") {
            ForEach(pokeSpotResults.prefix(500)) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(r.specieName).font(.caption).bold()
                        Text("Lv\(r.level)").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("Food: \(r.advances)  Enc: \(r.encounterAdvances)")
                            .font(.system(.caption2, design: .monospaced))
                        if r.shiny > 0 {
                            Image(systemName: "star.fill")
                                .font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                    HStack {
                        Text("PID: \(String(format: "%08X", r.pid))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(pfNatureNames[Int(r.nature)])
                            .font(.caption2).bold()
                        Text(r.gender == 0 ? "♂" : r.gender == 1 ? "♀" : "-")
                            .font(.caption2)
                    }
                    Text("IVs: \(r.ivs.map(String.init).joined(separator: "/"))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("HP: \(hiddenPowerTypes[Int(r.hiddenPower)])")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("(\(r.hiddenPowerStrength))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                Divider()
            }
        }
    }

    private func loadTemplates() {
        if mode == .shadow {
            if shadowTemplates.isEmpty {
                shadowTemplates = PFBridge.getShadowTemplates()
            }
            let filtered = filteredShadowTemplates
            if !filtered.isEmpty && !filtered.contains(where: { $0.id == selectedShadowIndex }) {
                selectedShadowIndex = filtered[0].id
            }
        } else if mode == .nonShadow {
            staticTemplates = PFBridge.getStaticEncounters3(type: 8)
            selectedStaticIndex = 0
        } else if mode == .channel {
            staticTemplates = PFBridge.getStaticEncounters3(type: 9)
            selectedStaticIndex = 0
        } else if mode == .pokeSpot {
            if pokeSpotAreas.isEmpty {
                pokeSpotAreas = PFBridge.getPokeSpotEncounters()
            }
        }

        // PokeSpot & Channel only for XD
        if selectedGame == .colosseum && (mode == .pokeSpot || mode == .channel) {
            mode = .shadow
        }
    }

    private func executeSearch() {
        stopSearch()
        searchProgress = -1
        stoppedAtLimit = false
        finished = false
        results = []
        searcherResults = []
        pokeSpotResults = []
        if mode == .pokeSpot {
            generatePokeSpot()
        } else if searchMode == .searcher {
            searchIVs()
        } else {
            generate()
        }
    }

    private func generate() {
        let seed = UInt32(seedText, radix: 16) ?? 0
        let initAdv = UInt32(clamping: initialAdvances)
        let maxAdv = UInt32(clamping: maxAdvances)
        let tID = tid, sID = sid
        let gameVal = selectedGame.pfGameValue
        let shiny: UInt8 = pfShinyFilter(shinyOnly)
        var natArr = [Bool](repeating: selectedNatures.isEmpty, count: 25)
        for n in selectedNatures { natArr[Int(n)] = true }

        let currentMode = mode
        let shadowIdx = selectedShadowIndex
        let isUnset = unset
        let staticIdx = selectedStaticIndex

        let (stream, continuation) = AsyncStream.makeStream(of: SearchEvent.self)
        searchWorkTask = Task.detached {
            generateInChunks(initialAdvance: initAdv, maxAdvance: maxAdv,
                             onProgress: { continuation.yield(.progress($0)) }) { start, count in
                let r: [PFBridge.GameCubeResult] = switch currentMode {
                case .shadow:
                    PFBridge.gamecubeGenerateShadow(
                        seed: seed, initialAdvances: start, maxAdvances: count,
                        shadowIndex: shadowIdx, unset: isUnset,
                        tid: tID, sid: sID, game: gameVal,
                        filterShiny: shiny, natures: natArr)
                case .nonShadow:
                    PFBridge.gamecubeGenerateStatic(
                        seed: seed, initialAdvances: start, maxAdvances: count,
                        method: .xdColo, staticType: 8, staticIndex: staticIdx,
                        tid: tID, sid: sID, game: gameVal,
                        filterShiny: shiny, natures: natArr)
                case .channel:
                    PFBridge.gamecubeGenerateStatic(
                        seed: seed, initialAdvances: start, maxAdvances: count,
                        method: .channel, staticType: 9, staticIndex: 0,
                        tid: tID, sid: sID, game: PFGame.gales.rawValue,
                        filterShiny: shiny, natures: natArr)
                case .pokeSpot:
                    []
                }
                if !r.isEmpty { continuation.yield(.generated(r)) }
                return r.count
            }
            continuation.finish()
        }
        searchTask = Task { await collect(stream) }
    }

    private func stopSearch() {
        searchWorkTask?.cancel()
        searchWorkTask = nil
        searchTask?.cancel()
        searchTask = nil
    }

    /// Fills the lists from a running search or generate, up to the limit.
    private func collect(_ stream: AsyncStream<SearchEvent>) async {
        for await event in stream {
            if Task.isCancelled { return }
            let full: Bool
            switch event {
            case .generated(let batch): full = appendUpToLimit(batch, to: &results)
            case .pokeSpot(let batch): full = appendUpToLimit(batch, to: &pokeSpotResults)
            case .searched(let batch): full = appendUpToLimit(batch, to: &searcherResults)
            case .progress(let pct):
                searchProgress = pct
                continue
            }
            if full {
                stopSearch()
                stoppedAtLimit = true
                return
            }
        }
        // Stopping already cleared these, maybe for the next search.
        guard !Task.isCancelled else { return }
        finished = true
        searchWorkTask = nil
        searchTask = nil
    }

    /// Stops a running search and clears the results, which were found for
    /// another game, mode or Pokémon.
    private func clearResults() {
        stopSearch()
        results = []
        searcherResults = []
        pokeSpotResults = []
        stoppedAtLimit = false
        finished = false
    }

    private func searchIVs() {
        let tID = tid, sID = sid
        let gameVal = selectedGame.pfGameValue
        let shiny: UInt8 = pfShinyFilter(shinyOnly)
        var natArr = [Bool](repeating: selectedNatures.isEmpty, count: 25)
        for n in selectedNatures { natArr[Int(n)] = true }
        let ivMin = [minHP, minAtk, minDef, minSpA, minSpD, minSpe]
        let ivMax = [maxHP, maxAtk, maxDef, maxSpA, maxSpD, maxSpe]

        let currentMode = mode
        let shadowIdx = selectedShadowIndex
        let isUnset = unset
        let staticIdx = selectedStaticIndex

        searchProgress = 0

        let (stream, continuation) = AsyncStream.makeStream(of: SearchEvent.self)

        // The search runs off the main actor, which also frees its handle
        // (that waits for PokéFinder's thread to stop).
        searchWorkTask = Task.detached {
            let handle: UnsafeMutableRawPointer? = switch currentMode {
            case .shadow:
                PFBridge.gamecubeSearchShadowStart(
                    method: .xdColo, unset: isUnset,
                    tid: tID, sid: sID, game: gameVal,
                    filterShiny: shiny, ivMin: ivMin, ivMax: ivMax,
                    natures: natArr, shadowIndex: shadowIdx)
            case .nonShadow:
                PFBridge.gamecubeSearchStaticStart(
                    method: .xdColo,
                    tid: tID, sid: sID, game: gameVal,
                    filterShiny: shiny, ivMin: ivMin, ivMax: ivMax,
                    natures: natArr, staticType: 8, staticIndex: staticIdx)
            case .channel:
                PFBridge.gamecubeSearchStaticStart(
                    method: .channel,
                    tid: tID, sid: sID, game: PFGame.gales.rawValue,
                    filterShiny: shiny, ivMin: ivMin, ivMax: ivMax,
                    natures: natArr, staticType: 9, staticIndex: 0)
            case .pokeSpot:
                nil
            }
            if let handle {
                gameCubeSearchStreaming(handle, onProgress: { continuation.yield(.progress($0)) }) {
                    continuation.yield(.searched($0))
                }
            }
            continuation.finish()
        }

        searchTask = Task { await collect(stream) }
    }

    private func generatePokeSpot() {
        let seedFood = UInt32(seedFoodText, radix: 16) ?? 0
        let seedEnc = UInt32(seedEncounterText, radix: 16) ?? 0
        let initAdv = UInt32(clamping: initialAdvances)
        let maxAdv = UInt32(clamping: maxAdvances)
        let initAdvEnc = UInt32(clamping: initialAdvancesEncounter)
        let maxAdvEnc = UInt32(clamping: maxAdvancesEncounter)
        let tID = tid, sID = sid
        let gameVal = selectedGame.pfGameValue
        let shiny: UInt8 = pfShinyFilter(shinyOnly)
        var natArr = [Bool](repeating: selectedNatures.isEmpty, count: 25)
        for n in selectedNatures { natArr[Int(n)] = true }
        let spotIdx = selectedPokeSpotIndex

        let (stream, continuation) = AsyncStream.makeStream(of: SearchEvent.self)
        // A chunk of food advances at a time, each with every encounter
        // advance: PokéFinder sorts by food advance first, so the chunks stay
        // in order.
        searchWorkTask = Task.detached {
            generateInChunks(initialAdvance: initAdv, maxAdvance: maxAdv,
                             onProgress: { continuation.yield(.progress($0)) }) { start, count in
                let r = PFBridge.pokeSpotGenerate(
                    seedFood: seedFood, seedEncounter: seedEnc,
                    initialAdvances: start, maxAdvances: count,
                    initialAdvancesEncounter: initAdvEnc, maxAdvancesEncounter: maxAdvEnc,
                    tid: tID, sid: sID, game: gameVal,
                    pokeSpotIndex: spotIdx,
                    filterShiny: shiny, natures: natArr)
                if !r.isEmpty { continuation.yield(.pokeSpot(r)) }
                return r.count
            }
            continuation.finish()
        }
        searchTask = Task { await collect(stream) }
    }
}

// MARK: - GameCube Searcher

/// Runs a started GameCube search: sends what it finds and its progress
/// (0–100) every tenth of a second until it's done, then frees it. When the
/// task is cancelled, it stops the search.
nonisolated func gameCubeSearchStreaming(_ handle: UnsafeMutableRawPointer,
                                         onProgress: (Double) -> Void = { _ in },
                                         onResults: ([PFSearcherStateSwift]) -> Void) {
    defer { PFBridge.gamecubeSearchFree(handle) }

    func send(_ batch: [PFSearcherStateSwift]) {
        if !batch.isEmpty { onResults(batch) }
    }

    while !PFBridge.gamecubeSearchDone(handle) {
        if Task.isCancelled {
            PFBridge.gamecubeSearchCancel(handle)
            return
        }
        send(PFBridge.gamecubeSearchResults(handle))
        onProgress(Double(PFBridge.gamecubeSearchProgress(handle)))
        Thread.sleep(forTimeInterval: 0.1)
    }
    send(PFBridge.gamecubeSearchResults(handle))
    onProgress(100)
}

// MARK: - Seed Searcher View

struct SeedSearcherView: View {
    let game: GameCubeGame

    enum SeedSearchType: String, CaseIterable, Identifiable {
        case colo = "Colosseum"
        case gales = "XD: Gales"
        case channel = "Channel"
        var id: String { rawValue }
    }

    @State private var searchType: SeedSearchType = .gales

    // Colo criteria
    @State private var coloLead: UInt8 = 0
    @State private var coloTrainer: UInt8 = 0

    // Gales criteria
    @State private var galesEnemyHP0: UInt16 = 0
    @State private var galesEnemyHP1: UInt16 = 0
    @State private var galesPlayerHP0: UInt16 = 0
    @State private var galesPlayerHP1: UInt16 = 0
    @State private var galesEnemyIndex: UInt8 = 0
    @State private var galesPlayerIndex: UInt8 = 0

    // Channel criteria
    @State private var channelPattern: [UInt8] = []

    // State
    @State private var searchHandle: OpaquePointer?
    @State private var searching = false
    @State private var progress: Double = 0
    @State private var seedResults: [UInt32] = []
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            CardStack {
                Picker("Type", selection: $searchType) {
                    ForEach(availableTypes) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch searchType {
                case .colo:
                    coloInputs
                case .gales:
                    galesInputs
                case .channel:
                    channelInputs
                }

                if searching {
                    VStack(spacing: 8) {
                        ProgressView(value: progress, total: 100)
                            .progressViewStyle(.linear)
                        Text("\(Int(progress))%")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Cancel") { cancelSearch() }
                            .foregroundStyle(.red)
                    }
                } else {
                    Button {
                        startSearch()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.primaryAction)
                }

                if !seedResults.isEmpty {
                    SectionCard(title: "Seeds (\(seedResults.count))", icon: "list.bullet") {
                        ForEach(Array(seedResults.prefix(200).enumerated()), id: \.offset) { _, seed in
                            Text(String(format: "%08X", seed))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Divider()
                        }
                    }
                }
            }
            .padding()
        }
        .dismissesKeyboard()
        .onDisappear { cancelSearch() }
        .leaveWarning(searching ? "The search in progress will stop." : nil)
    }

    private var availableTypes: [SeedSearchType] {
        if game == .colosseum { return [.colo] }
        return [.gales, .channel]
    }

    private var coloInputs: some View {
        SectionCard(title: "Colosseum Criteria", icon: "gamecontroller") {
            Picker("Lead Pokemon", selection: $coloLead) {
                Text("Espeon").tag(UInt8(0))
                Text("Umbreon").tag(UInt8(1))
            }
            Picker("Trainer Battle", selection: $coloTrainer) {
                ForEach(0..<5, id: \.self) { i in
                    Text("Trainer \(i + 1)").tag(UInt8(i))
                }
            }
        }
    }

    private var galesInputs: some View {
        SectionCard(title: "XD Battle Criteria", icon: "gamecontroller") {
            HStack {
                Text("Enemy HP")
                Spacer()
                LiveIntField("Min", value: $galesEnemyHP0)
                    .textFieldStyle(.roundedBorder).scaledWidth(60)
                Text("-")
                LiveIntField("Max", value: $galesEnemyHP1)
                    .textFieldStyle(.roundedBorder).scaledWidth(60)
            }
            HStack {
                Text("Player HP")
                Spacer()
                LiveIntField("Min", value: $galesPlayerHP0)
                    .textFieldStyle(.roundedBorder).scaledWidth(60)
                Text("-")
                LiveIntField("Max", value: $galesPlayerHP1)
                    .textFieldStyle(.roundedBorder).scaledWidth(60)
            }
            Picker("Enemy Lead", selection: $galesEnemyIndex) {
                ForEach(0..<6, id: \.self) { i in
                    Text("Slot \(i + 1)").tag(UInt8(i))
                }
            }
            Picker("Player Lead", selection: $galesPlayerIndex) {
                ForEach(0..<6, id: \.self) { i in
                    Text("Slot \(i + 1)").tag(UInt8(i))
                }
            }
        }
    }

    private var channelInputs: some View {
        SectionCard(title: "Channel Jirachi Menu", icon: "gamecontroller") {
            Text("Enter the menu animation sequence (0 = left, 1 = right)")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(Array(channelPattern.enumerated()), id: \.offset) { idx, val in
                    Button {
                        channelPattern[idx] = (val + 1) % 2
                    } label: {
                        Text(val == 0 ? "L" : "R")
                            .font(.system(.caption, design: .monospaced)).bold()
                            .foregroundStyle(val == 0 ? .blue : .red)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(val == 0 ? Color.blue.opacity(0.15) : Color.red.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }

                if channelPattern.count < 10 {
                    Button { channelPattern.append(0) } label: {
                        Image(systemName: "plus.circle").foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !channelPattern.isEmpty {
                Button("Clear") { channelPattern.removeAll() }
                    .font(.caption)
            }
        }
    }

    private func startSearch() {
        searching = true
        progress = 0
        seedResults = []
        let threads = max(ProcessInfo.processInfo.activeProcessorCount - 1, 1)

        switch searchType {
        case .colo:
            searchHandle = PFBridge.coloSeedSearchStart(lead: coloLead, trainer: coloTrainer, threads: threads)
        case .gales:
            searchHandle = PFBridge.galesSeedSearchStart(
                enemyHP: (galesEnemyHP0, galesEnemyHP1),
                playerHP: (galesPlayerHP0, galesPlayerHP1),
                enemyIndex: galesEnemyIndex, playerIndex: galesPlayerIndex,
                threads: threads)
        case .channel:
            guard !channelPattern.isEmpty else { searching = false; return }
            searchHandle = PFBridge.channelSeedSearchStart(pattern: channelPattern, threads: threads)
        }

        guard let handle = searchHandle else { searching = false; return }

        // Progress until the search thread ends (Cancel ends it early); the
        // results are sorted at the end, so they're read then, and freeing
        // the handle never waits on the search. Once cancelled, the search
        // is no longer the screen's.
        pollTask = Task {
            while !PFBridge.seedSearchDone(handle) {
                if searchHandle == handle { progress = Double(PFBridge.seedSearchProgress(handle)) }
                try? await Task.sleep(for: .milliseconds(200))
            }
            if searchHandle == handle {
                progress = 100
                seedResults = PFBridge.seedSearchGetResults(handle)
                searchHandle = nil
                searching = false
            }
            PFBridge.seedSearchFree(handle)
        }
    }

    private func cancelSearch() {
        if let handle = searchHandle {
            PFBridge.seedSearchCancel(handle)
        }
        searchHandle = nil
        searching = false
    }
}

// MARK: - Jirachi Pattern View

struct JirachiPatternView: View {
    @State private var seedText = ""
    @State private var targetAdvance: Int = 0
    @State private var bruteForce: Int = 50
    @State private var actions: [UInt8] = []
    @State private var jirachiSeed: UInt32?

    var body: some View {
        ScrollView {
            CardStack {
                SectionCard(title: "Input", icon: "number") {
                    HStack {
                        Text("Seed")
                        Spacer()
                        TextField("Hex", text: $seedText)
                            .textFieldStyle(.roundedBorder).scaledWidth(120)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                    RNGIntField(label: "Target Advance", value: $targetAdvance, range: RNGFieldRange.advances)
                    RNGIntField(label: "Brute Force Range", value: $bruteForce, range: RNGFieldRange.advances)
                }

                Button {
                    calculate()
                } label: {
                    Label("Calculate", systemImage: "function")
                }
                .buttonStyle(.primaryAction)

                if let jSeed = jirachiSeed {
                    SectionCard(title: "Jirachi Seed", icon: "star") {
                        Text(String(format: "%08X", jSeed))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if !actions.isEmpty {
                    SectionCard(title: "Actions (\(actions.count) steps)", icon: "list.number") {
                        let labels = ["Advance (wait)", "A button"]
                        ForEach(Array(actions.enumerated()), id: \.offset) { idx, action in
                            HStack {
                                Text("\(idx + 1).")
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .scaledWidth(30, relativeTo: .caption, alignment: .trailing)
                                Text(Int(action) < labels.count ? labels[Int(action)] : "Action \(action)")
                                    .font(.caption)
                                Spacer()
                            }
                        }
                    }
                } else if jirachiSeed != nil {
                    Text("No action sequence found for this target.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .dismissesKeyboard()
    }

    private func calculate() {
        let seed = UInt32(seedText, radix: 16) ?? 0
        jirachiSeed = PFBridge.computeJirachiSeed(seed)
        actions = PFBridge.jirachiPattern(seed: seed,
                                            targetAdvance: UInt32(clamping: targetAdvance),
                                            bruteForce: UInt32(clamping: bruteForce))
    }
}
