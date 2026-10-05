//
//  TeamBuilder.swift
//  PKReference
//
//  Created by Rishi Anand on 4/16/26.
//

import SwiftUI
import SwiftData

// MARK: - Team List

struct TeamListView: View {
    @Query(sort: \SavedTeam.createdAt, order: .reverse) private var savedTeams: [SavedTeam]
    @Query(sort: \SavedSpread.createdAt, order: .reverse) private var savedSpreads: [SavedSpread]
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]
    @Environment(\.modelContext) private var modelContext
    @State private var showNewTeam = false
    @State private var showImportTeam = false
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selectedTeam: SavedTeam?
    /// A team an App Intent asked to open in the compact layout.
    @State private var requestedTeam: SavedTeam?

    var body: some View {
        Group {
            // Wide layouts get a list/detail split; compact (portrait) keeps the
            // original push navigation, unchanged.
            if hSize == .regular {
                wideBody
            } else {
                TabNavigationStack {
                    listColumn(selection: nil)
                        .navigationDestination(item: $requestedTeam) { team in
                            TeamDetailView(team: team, savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
                        }
                }
            }
        }
        .onChange(of: AppNavigator.shared.request, initial: true) { openRequestedTeam() }
    }

    /// Opens the team an App Intent asked for: selected beside the list, or
    /// pushed.
    private func openRequestedTeam() {
        guard case .savedTeam(let id) = AppNavigator.shared.request else { return }
        AppNavigator.shared.request = nil
        guard let team = savedTeams.first(where: { $0.persistentModelID == id }) else { return }
        if hSize == .regular {
            selectedTeam = team
        } else {
            requestedTeam = team
        }
    }

    private var wideBody: some View {
        ListDetailSplit {
            listColumn(selection: $selectedTeam)
        } detail: {
            if let selectedTeam {
                // A new page for each team: it loads the team once, so a
                // reused one kept showing the first team.
                TeamDetailView(team: selectedTeam, savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
                    .id(selectedTeam.persistentModelID)
            } else {
                ContentUnavailableView {
                    Label("Select a Team", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a team from the list to see its coverage.")
                }
            }
        }
        #if DEBUG && os(macOS)
        .task { await DebugSnapshot.openFirstItem { selectedTeam = savedTeams.first } }
        #endif
    }

    @ViewBuilder
    private func listColumn(selection: Binding<SavedTeam?>?) -> some View {
        Group {
            if savedTeams.isEmpty {
                ContentUnavailableView {
                    Label("No Teams", systemImage: "person.3")
                } description: {
                    Text("Create a team of six to see type coverage analysis.")
                } actions: {
                    Button("New Team") { showNewTeam = true }
                        .buttonStyle(.borderedProminent)
                    Button("Import Paste") { showImportTeam = true }
                        .buttonStyle(.bordered)
                }
            } else if let selection {
                // Wide: selection-driven rows feed the split detail pane.
                List(selection: selection) {
                    ForEach(savedTeams) { team in
                        TeamRowView(team: team, savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
                            .tag(team)
                            #if os(macOS)
                            // Swiping to delete needs a trackpad on the Mac.
                            .contextMenu {
                                Button("Delete", role: .destructive) { modelContext.delete(team) }
                            }
                            #endif
                    }
                    .onDelete { indices in
                        for i in indices { modelContext.delete(savedTeams[i]) }
                    }
                }
            } else {
                // Compact: today's push rows, unchanged.
                List {
                    ForEach(savedTeams) { team in
                        NavigationLink {
                            TeamDetailView(team: team, savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
                        } label: {
                            TeamRowView(team: team, savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
                        }
                    }
                    .onDelete { indices in
                        for i in indices { modelContext.delete(savedTeams[i]) }
                    }
                }
            }
        }
        .navigationTitle("Teams")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewTeam = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Team")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showImportTeam = true } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .accessibilityLabel("Import Team from Paste")
            }
        }
        .sheet(isPresented: $showNewTeam) {
            NewTeamSheet(savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
            .sheetSize()
        }
        .sheet(isPresented: $showImportTeam) {
            TeamPasteImportSheet(savedSpreads: savedSpreads, savedTeams: savedTeams,
                                 allPokemon: allPokemon, allMoves: allMoves)
            .sheetSize()
        }
    }
}

// MARK: - Team Row

private struct TeamRowView: View {
    let team: SavedTeam
    let savedSpreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(team.name).font(.headline)
            let slots = team.resolvedSlots(allSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
            if slots.isEmpty {
                Text("Empty team").font(.caption).foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 6) {
                    ForEach(slots) { slot in
                        Text(slot.pokemonName)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - New Team Sheet

private struct NewTeamSheet: View {
    let savedSpreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var slots: [TeamSlotInfo] = []
    @State private var showDiscardAlert = false

    private var hasChanges: Bool {
        !slots.isEmpty || !name.isEmpty
    }

    var body: some View {
        NavigationStack {
            TeamEditorContent(name: $name, slots: $slots, savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
                .navigationTitle("New Team")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
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
                        Button("Save") {
                            let finalName = name.isEmpty ? "Untitled Team" : name
                            let team = SavedTeam(name: finalName, slots: slots)
                            modelContext.insert(team)
                            dismiss()
                        }
                        .disabled(slots.isEmpty)
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

    private func appendGeneratedToTeam(_ generated: PokemonSet) {
        guard slots.count < 6 else { return }
        guard let slot = buildSlot(from: generated) else { return }
        slots.append(slot)
    }

    private func replaceTeamWithGenerated(name teamName: String?,
                                          members: [PokemonSet]) {
        let built = members.compactMap { buildSlot(from: $0) }
        slots = built
        if name.isEmpty, let teamName, !teamName.isEmpty {
            name = teamName
        }
    }

    private func buildSlot(from generated: PokemonSet) -> TeamSlotInfo? {
        guard let pokemon = allPokemon.first(where: { $0.name == generated.species })
        else { return nil }
        let moveSlots: [TeamMoveInfo] = generated.moves.compactMap { moveName in
            guard let move = allMoves.first(where: { $0.name == moveName })
            else { return nil }
            let types = [pokemon.type1] + [pokemon.type2].compactMap { $0 }
            return TeamMoveInfo(
                moveID: move.id, moveName: move.name, moveType: move.type,
                damageClass: move.damageClass, power: move.power,
                isSTAB: move.damageClass != "status" && types.contains(move.type)
            )
        }
        return TeamSlotInfo(
            spreadName: "\(generated.species) (AI)",
            pokemonID: pokemon.id,
            pokemonName: pokemon.name,
            type1: pokemon.type1, type2: pokemon.type2,
            abilityName: generated.ability,
            itemRawValue: generated.item,
            championsMode: true,
            natureID: allNatures.first(where: { $0.name == generated.nature })?.id
                      ?? "adamant",
            level: 50,
            evHP: generated.statPoints.hp, evAtk: generated.statPoints.atk,
            evDef: generated.statPoints.def, evSpAtk: generated.statPoints.spa,
            evSpDef: generated.statPoints.spd, evSpeed: generated.statPoints.spe,
            moveSlots: moveSlots
        )
    }
}

// MARK: - Team Detail View

struct TeamDetailView: View {
    let team: SavedTeam
    let savedSpreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var slots: [TeamSlotInfo] = []
    @State private var hasLoaded = false
    @State private var isSaved = true
    @State private var showDiscardAlert = false
    @State private var originalName = ""
    @State private var originalSlots: [TeamSlotInfo] = []

    private var hasChanges: Bool {
        !isSaved && (name != originalName || slots != originalSlots)
    }

    var body: some View {
        TeamEditorContent(name: $name, slots: $slots, savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
            .navigationTitle(team.name)
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
                        team.name = name.isEmpty ? team.name : name
                        team.slots = slots
                        isSaved = true
                        originalName = name
                        originalSlots = slots
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
                name = team.name
                // Resolve through live SavedSpread data so the editor shows the latest
                // moves/EVs/ability for each slot, not the snapshot from when it was added.
                slots = team.resolvedSlots(allSpreads: savedSpreads,
                                           allPokemon: allPokemon,
                                           allMoves: allMoves)
                originalName = name
                originalSlots = slots
            }
            .onChange(of: name) { isSaved = false }
            .onChange(of: slots) { isSaved = false }
            .confirmationDialog("Unsaved Changes", isPresented: $showDiscardAlert, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You have unsaved changes. Discard them?")
            }
    }
}

// MARK: - Shared Team Editor Content

private struct TeamEditorContent: View {
    @Binding var name: String
    @Binding var slots: [TeamSlotInfo]
    let savedSpreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    @State private var showAddSlot = false

    var body: some View {
        ScrollView {
            CardStack {
                // Team Name
                VStack(alignment: .leading, spacing: 6) {
                    Label("Team Name", systemImage: "pencil")
                        .font(.headline)
                    TextField("Team Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                .card()

                // Team Slots
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Team (\(slots.count)/6)", systemImage: "person.3.fill").font(.headline)
                        Spacer()
                        if slots.count < 6 {
                            Button { showAddSlot = true } label: {
                                Label("Add", systemImage: "plus.circle.fill")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Divider()

                    if slots.isEmpty {
                        Text("Add sets from your saved spreads to build your team.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    } else {
                        ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                            TeamSlotCard(slot: slot, onRemove: { slots.remove(at: index) })
                        }
                    }
                }
                .card()

                // Coverage Analysis
                if !slots.isEmpty {
                    TypeCoverageCard(slots: slots)
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        #if os(iOS)
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        #endif
        .cardPage()
        .sheet(isPresented: $showAddSlot) {
            AddSlotSheet(slots: $slots, savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
            .sheetSize()
        }
    }
}

// MARK: - Team Slot Card

private struct TeamSlotCard: View {
    let slot: TeamSlotInfo
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(slot.pokemonName).font(.subheadline.bold())
                TypeBadge(type: slot.type1)
                if let t2 = slot.type2 { TypeBadge(type: t2) }
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }

            if !slot.moveSlots.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(slot.moveSlots) { move in
                        HStack(spacing: 3) {
                            Text(move.moveName)
                                .font(.caption2)
                            if move.isSTAB {
                                Text("STAB")
                                    .scaledFont(size: 8, weight: .bold, relativeTo: .caption2)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(TypePalette.fill(for: move.moveType).opacity(0.2), in: Capsule())
                        .font(.caption2)
                    }
                }
            }

            if let ability = slot.abilityName {
                HStack(spacing: 6) {
                    Text(formatAbilityName(ability))
                        .font(.caption2)
                        .foregroundStyle(ColorRole.ability.color)
                    if let item = slot.itemRawValue {
                        Text(HeldItem.currentName(item))
                            .font(.caption2)
                            .foregroundStyle(ColorRole.item.color)
                    }
                }
            }

            Text("EVs: \(slot.evHP)/\(slot.evAtk)/\(slot.evDef)/\(slot.evSpAtk)/\(slot.evSpDef)/\(slot.evSpeed)")
                .font(.caption2.monospaced()).foregroundStyle(.tertiary)
        }
        .insetCard(types: [slot.type1] + [slot.type2].compactMap { $0 })
    }
}

// MARK: - Add Slot Sheet (pick from saved spreads)

private struct AddSlotSheet: View {
    @Binding var slots: [TeamSlotInfo]
    let savedSpreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [SavedSpread] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return savedSpreads }
        return savedSpreads.filter {
            ($0.name.lowercased().contains(q)) ||
            ($0.pokemonName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if savedSpreads.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Sets", systemImage: "tray")
                    } description: {
                        Text("Create sets in the Sets tab first, then add them to your team here.")
                    }
                } else {
                    List(filtered) { spread in
                        Button {
                            addSpread(spread)
                        } label: {
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
                                    Text(pkmn).font(.subheadline).foregroundStyle(.secondary)
                                }
                                let moveIDs = [spread.moveID1, spread.moveID2, spread.moveID3, spread.moveID4].compactMap { $0 }
                                let moveNames = moveIDs.compactMap { mid in allMoves.first(where: { $0.id == mid })?.name }
                                if !moveNames.isEmpty {
                                    Text(moveNames.joined(separator: " / "))
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(slots.count >= 6)
                    }
                    .searchable(text: $searchText, prompt: "Search sets...")
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("Add Set to Team")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addSpread(_ spread: SavedSpread) {
        guard slots.count < 6 else { return }
        let pokemon = allPokemon.first(where: { $0.id == spread.pokemonID })
        if let slotInfo = TeamSlotInfo.from(spread: spread, pokemon: pokemon, moves: allMoves) {
            slots.append(slotInfo)
            dismiss()
        }
    }
}

// MARK: - Type Coverage Analysis

struct CoverageSource: Identifiable {
    let id = UUID()
    let pokemonName: String
    let moveName: String
    let moveType: String
    let isSTAB: Bool
}

struct TypeCoverageEntry: Identifiable {
    let id: String // the defender type
    let defenderType: String
    let stabSources: [CoverageSource]
    let nonStabSources: [CoverageSource]

    var isCovered: Bool { !stabSources.isEmpty || !nonStabSources.isEmpty }
    var hasSTABCoverage: Bool { !stabSources.isEmpty }
}

func computeTypeCoverage(slots: [TeamSlotInfo]) -> [TypeCoverageEntry] {
    allTypes.map { defenderType in
        var stabSources: [CoverageSource] = []
        var nonStabSources: [CoverageSource] = []

        for slot in slots {
            for move in slot.moveSlots {
                // Skip status moves (no power)
                guard move.damageClass != "status", let power = move.power, power > 0 else { continue }

                let effectiveness = typeEffectivenessChart[move.moveType]?[defenderType] ?? 1.0
                if effectiveness > 1.0 {
                    let source = CoverageSource(
                        pokemonName: slot.pokemonName,
                        moveName: move.moveName,
                        moveType: move.moveType,
                        isSTAB: move.isSTAB
                    )
                    if move.isSTAB {
                        stabSources.append(source)
                    } else {
                        nonStabSources.append(source)
                    }
                }
            }
        }

        return TypeCoverageEntry(
            id: defenderType,
            defenderType: defenderType,
            stabSources: stabSources,
            nonStabSources: nonStabSources
        )
    }
}

// MARK: - Type Coverage Card

private struct TypeCoverageCard: View {
    let slots: [TeamSlotInfo]

    private var entries: [TypeCoverageEntry] {
        computeTypeCoverage(slots: slots)
    }

    private var stabCovered: [TypeCoverageEntry] {
        entries.filter { $0.hasSTABCoverage }
    }

    private var nonStabOnly: [TypeCoverageEntry] {
        entries.filter { !$0.hasSTABCoverage && $0.isCovered }
    }

    private var uncovered: [TypeCoverageEntry] {
        entries.filter { !$0.isCovered }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Type Coverage", systemImage: "shield.checkered").font(.headline)
            Divider()

            // Summary bar
            HStack(spacing: 12) {
                CoverageStat(label: "STAB SE", count: stabCovered.count, total: allTypes.count, color: .green)
                CoverageStat(label: "Non-STAB SE", count: nonStabOnly.count, total: allTypes.count, color: .yellow)
                CoverageStat(label: "Uncovered", count: uncovered.count, total: allTypes.count, color: .red)
            }

            // STAB super-effective
            if !stabCovered.isEmpty {
                CoverageSectionView(
                    title: "STAB Super-Effective",
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    entries: stabCovered,
                    showSTAB: true
                )
            }

            // Non-STAB super-effective
            if !nonStabOnly.isEmpty {
                CoverageSectionView(
                    title: "Non-STAB Super-Effective",
                    icon: "checkmark.circle",
                    iconColor: .yellow,
                    entries: nonStabOnly,
                    showSTAB: false
                )
            }

            // Uncovered
            if !uncovered.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("No Super-Effective Coverage").font(.subheadline.bold())
                    }

                    FlowLayout(spacing: 6) {
                        ForEach(uncovered) { entry in
                            TypeBadge(type: entry.defenderType)
                        }
                    }
                }
            }

            if uncovered.isEmpty {
                HStack {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("Full type coverage!").font(.subheadline.bold()).foregroundStyle(.green)
                }
            }
        }
        .card()
    }
}

private struct CoverageStat: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CoverageSectionView: View {
    let title: String
    let icon: String
    let iconColor: Color
    let entries: [TypeCoverageEntry]
    let showSTAB: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(iconColor)
                Text(title).font(.subheadline.bold())
            }

            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    TypeBadge(type: entry.defenderType)

                    let sources = showSTAB ? entry.stabSources : entry.nonStabSources
                    ForEach(sources) { source in
                        FlowLayout(spacing: 4) {
                            Text(source.pokemonName)
                                .font(.caption.bold())
                            Text("with")
                                .font(.caption).foregroundStyle(.tertiary)
                            Text(source.moveName)
                                .font(.caption)
                            TypeBadge(type: source.moveType)
                            if source.isSTAB {
                                Text("STAB")
                                    .scaledFont(size: 8, weight: .bold, relativeTo: .caption2)
                                    .padding(.horizontal, 3).padding(.vertical, 1)
                                    .foregroundStyle(.yellow)
                                    .background(Color.yellow.opacity(0.2), in: Capsule())
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
