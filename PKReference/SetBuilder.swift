//
//  SetBuilder.swift
//  PKReference
//
//  Created by Rishi Anand on 4/16/26.
//

import SwiftUI
import SwiftData

// MARK: - Set List

struct SetListView: View {
    @Query(sort: \SavedSpread.createdAt, order: .reverse) private var savedSpreads: [SavedSpread]
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]
    @Environment(\.modelContext) private var modelContext
    @State private var showNewSetSheet = false

    /// When true, swipe-to-delete acts immediately without the confirmation
    /// alert. The alert's "Don't Ask Again" sets it; Settings clears it.
    @AppStorage(AppSettings.instantSetDelete) private var instantSetDelete: Bool
    /// Spread queued for deletion, awaiting alert confirmation.
    @State private var pendingDeletion: SavedSpread?
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selectedSpread: SavedSpread?
    /// A set an App Intent asked to open in the compact layout.
    @State private var requestedSpread: SavedSpread?

    var body: some View {
        Group {
            // Wide layouts get a list/editor split; compact (portrait) keeps the
            // original push navigation, unchanged.
            if hSize == .regular {
                wideBody
            } else {
                TabNavigationStack {
                    listColumn(selection: nil)
                        .navigationDestination(item: $requestedSpread) { spread in
                            SetEditorView(spread: spread, allPokemon: allPokemon, allMoves: allMoves)
                        }
                }
            }
        }
        .onChange(of: AppNavigator.shared.request, initial: true) { openRequestedSet() }
    }

    /// Opens the set an App Intent asked for: selected beside the list, or
    /// pushed.
    private func openRequestedSet() {
        guard case .savedSet(let id) = AppNavigator.shared.request else { return }
        AppNavigator.shared.request = nil
        guard let spread = savedSpreads.first(where: { $0.persistentModelID == id }) else { return }
        if hSize == .regular {
            selectedSpread = spread
        } else {
            requestedSpread = spread
        }
    }

    private var wideBody: some View {
        ListDetailSplit {
            listColumn(selection: $selectedSpread)
        } detail: {
            if let selectedSpread {
                // A new editor for each set: the editor loads its fields
                // once, so a reused one kept showing the first set, and
                // Save wrote those fields into the newly selected one.
                SetEditorView(spread: selectedSpread, allPokemon: allPokemon, allMoves: allMoves)
                    .id(selectedSpread.persistentModelID)
            } else {
                ContentUnavailableView {
                    Label("Select a Set", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a set from the list to edit it.")
                }
            }
        }
        #if DEBUG && os(macOS)
        .task { await DebugSnapshot.openFirstItem { selectedSpread = savedSpreads.first } }
        #endif
    }

    @ViewBuilder
    private func listColumn(selection: Binding<SavedSpread?>?) -> some View {
        Group {
            if savedSpreads.isEmpty {
                ContentUnavailableView {
                    Label("No Sets", systemImage: "tray")
                } description: {
                    Text("Create a set to get started. Sets can be loaded into teams for coverage analysis.")
                } actions: {
                    Button("New Set") { showNewSetSheet = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if let selection {
                // Wide: selection-driven rows feed the split editor pane.
                List(selection: selection) {
                    ForEach(savedSpreads) { spread in
                        SetRowView(spread: spread, allMoves: allMoves)
                            .tag(spread)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                deleteButton(for: spread)
                            }
                            #if os(macOS)
                            // Swiping needs a trackpad on the Mac. The same
                            // button, so it asks first too.
                            .contextMenu { deleteButton(for: spread) }
                            #endif
                    }
                }
            } else {
                // Compact: today's push rows, unchanged.
                List {
                    ForEach(savedSpreads) { spread in
                        NavigationLink {
                            SetEditorView(spread: spread, allPokemon: allPokemon, allMoves: allMoves)
                        } label: {
                            SetRowView(spread: spread, allMoves: allMoves)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            deleteButton(for: spread)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewSetSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewSetSheet) {
            NewSetSheet(allPokemon: allPokemon, allMoves: allMoves)
            .sheetSize()
        }
        #if DEBUG && os(macOS)
        .task { await DebugSnapshot.openSheet("newSet") { showNewSetSheet = true } }
        #endif
        .alert("Delete \(pendingDeletion?.name ?? "set")?",
               isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
               ),
               presenting: pendingDeletion) { spread in
            Button("Delete", role: .destructive) {
                modelContext.delete(spread)
                pendingDeletion = nil
            }
            Button("Delete & Don't Ask Again") {
                // Future swipe-deletes skip the alert until Settings'
                // "Ask Before Deleting a Set" is turned back on.
                instantSetDelete = true
                modelContext.delete(spread)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { _ in
            Text("This can't be undone. If you choose Don't Ask Again, you can turn this prompt back on in Settings.")
        }
    }

    @ViewBuilder
    private func deleteButton(for spread: SavedSpread) -> some View {
        Button(role: .destructive) {
            if instantSetDelete {
                modelContext.delete(spread)
            } else {
                pendingDeletion = spread
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
        // The app's accent tint would otherwise override the destructive red.
        .tint(.red)
    }
}

// MARK: - Set Row

private struct SetRowView: View {
    let spread: SavedSpread
    let allMoves: [MoveData]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(spread.name).font(.headline)
                Spacer()
                if spread.championsMode {
                    Text("Champions")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(.red)
                        .background(Color.red.opacity(0.15), in: Capsule())
                }
            }

            if let pkmn = spread.pokemonName {
                // Chips move to a new line rather than breaking mid-word,
                // as they did in the narrow iPad list.
                FlowLayout(spacing: 8, lineSpacing: 4) {
                    Text(pkmn).font(.subheadline).foregroundStyle(.secondary)
                    if let ability = spread.abilityName {
                        Text(formatAbilityName(ability))
                            .font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .foregroundStyle(ColorRole.ability.color)
                            .background(ColorRole.ability.color.opacity(0.12), in: Capsule())
                    }
                    if let item = spread.itemRawValue, item != HeldItem.none.rawValue {
                        Text(HeldItem.currentName(item))
                            .font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .foregroundStyle(ColorRole.item.color)
                            .background(ColorRole.item.color.opacity(0.12), in: Capsule())
                    }
                    if let nature = allNatures.first(where: { $0.id == spread.natureID }) {
                        Text(nature.name)
                            .font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .foregroundStyle(ColorRole.nature.color)
                            .background(ColorRole.nature.color.opacity(0.12), in: Capsule())
                    }
                }
            }

            let moveIDs = [spread.moveID1, spread.moveID2, spread.moveID3, spread.moveID4].compactMap { $0 }
            let moveNames = moveIDs.compactMap { mid in allMoves.first(where: { $0.id == mid })?.name }
            if !moveNames.isEmpty {
                Text(moveNames.joined(separator: " / "))
                    .font(.caption).foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Text("EVs: \(spread.evHP)/\(spread.evAtk)/\(spread.evDef)/\(spread.evSpAtk)/\(spread.evSpDef)/\(spread.evSpeed)")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - New Set Sheet

struct NewSetSheet: View {
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    var initialPokemon: PKMNStats? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.defaultGeneration) private var defaultGeneration: String

    @State private var name = ""
    @State private var side = CalcSide()
    @State private var showDiscardAlert = false

    private var hasChanges: Bool {
        side.pokemon != nil || !name.isEmpty
    }

    /// Predict Set's place: the middle of the top bar on iOS. A Mac sheet
    /// shows its toolbar only along the bottom, which has no middle spot,
    /// so there it sits with Cancel and Save.
    private static var predictButtonPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .principal
        #else
        .automatic
        #endif
    }

    var body: some View {
        NavigationStack {
            SetFormContent(name: $name, side: side, allPokemon: allPokemon, allMoves: allMoves)
                .navigationTitle("New Set")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: Self.predictButtonPlacement) {
                        SetPredictorButton(initialSpecies: side.pokemon?.name) { generated in
                            applyGeneratedSet(generated)
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if hasChanges {
                                showDiscardAlert = true
                            } else {
                                dismiss()
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveAndDismiss() }
                            .disabled(side.pokemon == nil)
                    }
                }
                .onAppear {
                    if defaultGeneration == PokedexFilter.champions.rawValue {
                        side.setChampionsMode(true)
                    }
                    if side.pokemon == nil, let initial = initialPokemon {
                        side.pokemon = initial
                        side.selectedAbility = initial.ability1
                        if name.isEmpty {
                            name = initial.name
                        }
                    }
                }
                .confirmationDialog("Discard Changes?", isPresented: $showDiscardAlert, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { dismiss() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You have unsaved changes. Are you sure you want to discard them?")
                }
        }
        .interactiveDismissDisabled(hasChanges)
        .presentationDetents([.large])
    }

    private func applyGeneratedSet(_ generated: PokemonSet) {
        if let match = allPokemon.first(where: { $0.name == generated.species }) {
            side.pokemon = match
            // The predictor emits abilities in the training-data convention
            // ("Flash Fire") but `PKMNStats.allAbilities` stores them as PokeAPI
            // slugs ("flash-fire"). The Picker binds on the slug, so we have
            // to translate before assignment — otherwise the selection
            // silently doesn't take.
            side.selectedAbility = resolveAbilitySlug(generated.ability, for: match)
            side.heldItem = HeldItem(rawValue: generated.item ?? "") ?? .none
            side.nature = allNatures.first(where: { $0.name == generated.nature })
                      ?? side.nature
            side.championsMode = true
            side.evHP = generated.statPoints.hp
            side.evAtk = generated.statPoints.atk
            side.evDef = generated.statPoints.def
            side.evSpAtk = generated.statPoints.spa
            side.evSpDef = generated.statPoints.spd
            side.evSpeed = generated.statPoints.spe
            side.ivHP = 31; side.ivAtk = 31; side.ivDef = 31
            side.ivSpAtk = 31; side.ivSpDef = 31; side.ivSpeed = 31

            for i in 0..<4 {
                let moveName = i < generated.moves.count ? generated.moves[i] : ""
                side.moves[i] = allMoves.first(where: { $0.name == moveName })
            }

            if name.isEmpty {
                name = "\(generated.species) (AI)"
            }
        }
    }

    /// Map the predictor's display-formatted ability name onto the slug the
    /// species' Pokedex row uses. Tries (in order): exact match against the
    /// species' ability list, slug conversion ("Flash Fire" → "flash-fire"
    /// with apostrophes stripped — "Mind's Eye" → "minds-eye"), and finally
    /// a `formatAbilityName` round-trip so a slug already in canonical form
    /// passes through untouched.
    private func resolveAbilitySlug(_ displayName: String, for pkmn: PKMNStats) -> String {
        let slug = displayName
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: " ", with: "-")
        // Prefer a slug that actually exists on this species so the Picker
        // binding has something concrete to latch onto.
        if pkmn.allAbilities.contains(slug) { return slug }
        if let match = pkmn.allAbilities.first(where: {
            formatAbilityName($0).caseInsensitiveCompare(displayName) == .orderedSame
        }) {
            return match
        }
        return slug
    }

    private func saveAndDismiss() {
        let finalName = name.isEmpty ? (side.pokemon?.name ?? "Untitled") : name
        let spread = side.toSavedSpread(name: finalName)
        modelContext.insert(spread)
        dismiss()
    }
}

// MARK: - Set Editor (edit existing spread)

struct SetEditorView: View {
    let spread: SavedSpread
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var side = CalcSide()
    @State private var hasLoaded = false
    @State private var isSaved = true
    @State private var showDiscardAlert = false

    /// Snapshot of the original spread for dirty-checking.
    @State private var originalSnapshot = ""

    private var currentSnapshot: String {
        let s = side.toSavedSpread(name: name)
        return "\(name)|\(s.pokemonID ?? 0)|\(s.natureID)|\(s.evHP)|\(s.evAtk)|\(s.evDef)|\(s.evSpAtk)|\(s.evSpDef)|\(s.evSpeed)|\(s.ivHP)|\(s.ivAtk)|\(s.ivDef)|\(s.ivSpAtk)|\(s.ivSpDef)|\(s.ivSpeed)|\(s.moveID1 ?? 0)|\(s.moveID2 ?? 0)|\(s.moveID3 ?? 0)|\(s.moveID4 ?? 0)|\(s.abilityName ?? "")|\(s.itemRawValue ?? "")|\(s.championsMode)|\(s.level)"
    }

    private var hasChanges: Bool {
        !isSaved && currentSnapshot != originalSnapshot
    }

    var body: some View {
        SetFormContent(name: $name, side: side, allPokemon: allPokemon, allMoves: allMoves)
            .navigationTitle(spread.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationBarBackButtonHidden(hasChanges)
            .toolbar {
                if hasChanges {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            showDiscardAlert = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        updateSpread()
                        isSaved = true
                        originalSnapshot = currentSnapshot
                    }
                    .bold(hasChanges)
                    .disabled(!hasChanges)
                }
                if hasChanges {
                    ToolbarItem(placement: .principal) {
                        Text("Unsaved Changes")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                name = spread.name
                side.loadSpread(spread, allPokemon: allPokemon, allMoves: allMoves)
                // Allow a tick for side to settle before snapshotting
                DispatchQueue.main.async {
                    originalSnapshot = currentSnapshot
                    isSaved = true
                }
            }
            .onChange(of: currentSnapshot) {
                isSaved = false
            }
            .confirmationDialog("Unsaved Changes", isPresented: $showDiscardAlert, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You have unsaved changes. Discard them?")
            }
    }

    private func updateSpread() {
        let finalName = name.isEmpty ? spread.name : name
        spread.name = finalName
        let updated = side.toSavedSpread(name: finalName)
        spread.pokemonID = updated.pokemonID
        spread.pokemonName = updated.pokemonName
        spread.abilityName = updated.abilityName
        spread.itemRawValue = updated.itemRawValue
        spread.teraType = updated.teraType
        spread.championsMode = updated.championsMode
        spread.natureID = updated.natureID
        spread.level = updated.level
        spread.evHP = updated.evHP; spread.evAtk = updated.evAtk; spread.evDef = updated.evDef
        spread.evSpAtk = updated.evSpAtk; spread.evSpDef = updated.evSpDef; spread.evSpeed = updated.evSpeed
        spread.ivHP = updated.ivHP; spread.ivAtk = updated.ivAtk; spread.ivDef = updated.ivDef
        spread.ivSpAtk = updated.ivSpAtk; spread.ivSpDef = updated.ivSpDef; spread.ivSpeed = updated.ivSpeed
        spread.moveID1 = updated.moveID1; spread.moveID2 = updated.moveID2
        spread.moveID3 = updated.moveID3; spread.moveID4 = updated.moveID4
    }
}

// MARK: - Shared Set Form Content

private struct SetFormContent: View {
    @Binding var name: String
    @Bindable var side: CalcSide
    let allPokemon: [PKMNStats]

    /// Every type, plus Stellar, which only exists as a Tera type.
    private let teraTypes = allTypes + ["Stellar"]

    private var regulationAllowsTera: Bool { ChampionsRegulation.current.rules().teraAllowed }

    /// Mainline sets always, Champions sets when the regulation has Tera,
    /// and any set that already has one (from a paste) so it can be seen
    /// and removed.
    private var showsTeraType: Bool {
        !side.championsMode || regulationAllowsTera || side.teraType != nil
    }

    private var teraFooter: String {
        if side.championsMode && !regulationAllowsTera {
            return "\(ChampionsRegulation.current.displayName) doesn't have Tera. The type stays with the set and in its paste."
        }
        return "Saved with the set and in its paste. The calc and Battle Sim don't Terastallize yet."
    }
    let allMoves: [MoveData]

    private var filteredPokemon: [PKMNStats] {
        let q = side.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return allPokemon.filter { $0.name.lowercased().contains(q) || String($0.id).contains(q) }.prefix(20).map { $0 }
    }

    var body: some View {
        Form {
            // Set Name
            Section("Set Name") {
                // Titled, with the example as its prompt: a Mac form shows a
                // field's title as a label beside it, and the section header
                // already says what this is.
                TextField("Set Name", text: $name, prompt: Text("e.g. Physical Sweeper"))
                    .labelsHidden()
            }

            // Pokemon
            Section("Pokemon") {
                if let p = side.pokemon {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.headline)
                            if p.isForm, let form = p.formName {
                                Text(form.split(separator: "-").map { $0.capitalized }.joined(separator: " "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        TypeBadge(type: p.type1)
                        if let t2 = p.type2 { TypeBadge(type: t2) }
                        Button {
                            side.pokemon = nil; side.searchText = ""
                            side.selectedAbility = nil; side.teraType = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        StatMini(label: "HP", value: p.baseHP)
                        StatMini(label: "Atk", value: p.baseAtk)
                        StatMini(label: "Def", value: p.baseDef)
                        StatMini(label: "SpA", value: p.baseSpAtk)
                        StatMini(label: "SpD", value: p.baseSpDef)
                        StatMini(label: "Spe", value: p.baseSpeed)
                    }
                    .font(.caption2)
                } else {
                    TextField("Search Mons", text: $side.searchText, prompt: Text("Search Mons..."))
                        .labelsHidden()
                    ForEach(filteredPokemon) { p in
                        Button {
                            side.pokemon = p
                            side.searchText = ""
                            side.selectedAbility = p.ability1
                            side.teraType = nil
                            side.moves = [nil, nil, nil, nil]
                            side.moveSearchTexts = ["", "", "", ""]
                        } label: {
                            HStack {
                                Text(p.dexLabel).foregroundStyle(.secondary).lineLimit(1).scaledWidth(50, alignment: .leading)
                                Text(p.name)
                                Spacer()
                                TypeBadge(type: p.type1)
                                if let t2 = p.type2 { TypeBadge(type: t2) }
                            }
                        }
                    }
                }
            }

            if let pkmn = side.pokemon {
                // Moves
                Section("Moves") {
                    Toggle("Legal moves only", isOn: $side.filterLegalMoves)
                        .font(.subheadline).tint(.red)

                    ForEach(0..<4, id: \.self) { i in
                        SetMoveSlot(index: i, side: side, allMoves: allMoves, allPokemon: allPokemon)
                    }
                }

                // Ability & Item
                Section("Ability & Item") {
                    Picker("Ability", selection: $side.selectedAbility) {
                        Text("None").tag(String?.none)
                        ForEach(pkmn.allAbilities, id: \.self) { a in
                            Text(formatAbilityName(a)).tag(Optional(a))
                        }
                    }
                    Picker("Item", selection: $side.heldItem) {
                        ForEach(HeldItem.pickerOptions(forSpeciesNamed: pkmn.name,
                                                       championsMode: side.championsMode,
                                                       keeping: side.heldItem)) { item in
                            Text(item.pickerLabel(championsMode: side.championsMode)).tag(item)
                        }
                    }
                }

                // Tera Type
                if showsTeraType {
                    Section {
                        Picker("Tera Type", selection: $side.teraType) {
                            Text("None").tag(String?.none)
                            ForEach(teraTypes, id: \.self) { type in
                                Text(type).tag(Optional(type))
                            }
                        }
                    } footer: {
                        Text(teraFooter)
                    }
                }

                // Nature & Level
                Section("Nature & Level") {
                    Picker("Nature", selection: $side.nature) {
                        ForEach(allNatures) { n in
                            Text("\(n.name) \(n.summary)").tag(n)
                        }
                    }
                    HStack {
                        Text("Level")
                        Spacer()
                        TextField("Level", value: $side.level, format: .number, prompt: Text("Lv"))
                            .labelsHidden()
                            .scaledWidth(60)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }

                // Champions Mode & EVs
                Section("EVs") {
                    Toggle("Champions Mode", isOn: Binding(
                        get: { side.championsMode },
                        set: { side.setChampionsMode($0) }
                    ))
                    .tint(.red)

                    if side.championsMode {
                        Text("EVs: 0-\(championsMaxEVPerStat) scale. IVs fixed at \(championsLockedIV).")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("\(side.totalEVs)/\(side.evTotalMax) EVs")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(side.totalEVs > side.evTotalMax ? .red : .secondary)
                        ProgressView(value: min(Double(side.totalEVs) / Double(max(side.evTotalMax, 1)), 1.0))
                            .tint(side.totalEVs >= side.evTotalMax ? .red : .accentColor)
                            .frame(maxWidth: 80)
                    }

                    let step = side.championsMode ? 1 : 4
                    SetEVRow(label: "HP", side: side, keyPath: \.evHP, step: step)
                    SetEVRow(label: "Atk", side: side, keyPath: \.evAtk, step: step)
                    SetEVRow(label: "Def", side: side, keyPath: \.evDef, step: step)
                    SetEVRow(label: "Sp.Atk", side: side, keyPath: \.evSpAtk, step: step)
                    SetEVRow(label: "Sp.Def", side: side, keyPath: \.evSpDef, step: step)
                    SetEVRow(label: "Speed", side: side, keyPath: \.evSpeed, step: step)
                }

                if !side.championsMode {
                    Section("IVs") {
                        SetIVRow(label: "HP", value: $side.ivHP)
                        SetIVRow(label: "Atk", value: $side.ivAtk)
                        SetIVRow(label: "Def", value: $side.ivDef)
                        SetIVRow(label: "Sp.Atk", value: $side.ivSpAtk)
                        SetIVRow(label: "Sp.Def", value: $side.ivSpDef)
                        SetIVRow(label: "Speed", value: $side.ivSpeed)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        // The same gray as the Form's own background, plus the type glow
        // when that's on.
        .scrollContentBackground(.hidden)
        .cardPage(types: side.effectiveTypes)
    }
}

// MARK: - Set Move Slot

private struct SetMoveSlot: View {
    let index: Int
    @Bindable var side: CalcSide
    let allMoves: [MoveData]
    let allPokemon: [PKMNStats]

    private var filteredMoves: [MoveData] {
        let q = side.moveSearchTexts[index].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var pool = allMoves
        if side.filterLegalMoves, let pkmn = side.pokemon {
            var legalIDs = Set(pkmn.learnableMoveIDs)
            if legalIDs.isEmpty {
                if let base = allPokemon.first(where: { $0.speciesID == pkmn.speciesID && !$0.isForm }) {
                    legalIDs = Set(base.learnableMoveIDs)
                }
            }
            pool = pool.filter { legalIDs.contains($0.id) }
        }
        return pool.filter { $0.name.lowercased().contains(q) }.prefix(15).map { $0 }
    }

    var body: some View {
        if let move = side.moves[index] {
            HStack(spacing: 6) {
                Text("\(index + 1).").font(.caption).foregroundStyle(.tertiary)
                Text(move.name).font(.subheadline.bold()).lineLimit(1)
                TypeBadge(type: move.type)
                if let power = move.power, power > 0 {
                    Text("\(power) BP").font(.caption).foregroundStyle(.secondary)
                }
                DamageClassBadge(damageClass: move.damageClass)
                Spacer()
                Button { side.moves[index] = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Move \(index + 1)", text: Binding(
                    get: { side.moveSearchTexts[index] },
                    set: { side.moveSearchTexts[index] = $0 }
                ), prompt: Text("Move \(index + 1)..."))
                .labelsHidden()
                .font(.subheadline)

                ForEach(filteredMoves) { move in
                    Button {
                        side.moves[index] = move
                        side.moveSearchTexts[index] = ""
                    } label: {
                        HStack {
                            Text(move.name)
                            Spacer()
                            TypeBadge(type: move.type)
                            if let power = move.power, power > 0 {
                                Text("\(power) BP").font(.caption).foregroundStyle(.secondary)
                            }
                            DamageClassBadge(damageClass: move.damageClass)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - EV / IV Rows

private struct SetEVRow: View {
    let label: String
    var side: CalcSide
    let keyPath: ReferenceWritableKeyPath<CalcSide, Int>
    var step: Int = 4

    private var cap: Int {
        side.maxAllowedEV(excluding: side[keyPath: keyPath])
    }

    var body: some View {
        HStack {
            Text(label).lineLimit(1).scaledWidth(58, alignment: .leading)
            Slider(value: Binding(
                get: { Double(side[keyPath: keyPath]) },
                set: { side[keyPath: keyPath] = max(0, min(Int($0), cap)) }
            ), in: 0...Double(max(side.evPerStatMax, 1)), step: Double(step))
            .tint(.red)
            Text("\(side[keyPath: keyPath])")
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .scaledWidth(36, relativeTo: .caption, alignment: .trailing)
        }
    }
}

private struct SetIVRow: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(label).lineLimit(1).scaledWidth(58, alignment: .leading)
            Slider(value: Binding(
                get: { Double(value) },
                set: { value = max(0, min(Int($0), 31)) }
            ), in: 0...31, step: 1)
            .tint(.red)
            Text("\(value)")
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .scaledWidth(36, relativeTo: .caption, alignment: .trailing)
        }
    }
}
