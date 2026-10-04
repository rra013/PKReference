import SwiftUI

struct EncounterBrowserView: View {
    @State private var generation: EncBrowserGen = .gen3
    @State private var selectedGame: PFGame = .emerald
    @State private var selectedEncounter: PFEncounter = .grass
    @State private var areas: [PFEncounterAreaSwift] = []
    @State private var expandedArea: UUID?

    // Gen 4 settings
    @State private var tid: UInt16 = 0
    @State private var sid: UInt16 = 0

    enum EncBrowserGen: String, CaseIterable, Identifiable {
        case gen3 = "Gen 3"
        case gen4 = "Gen 4"
        case gen5 = "Gen 5"
        var id: String { rawValue }
    }

    private var availableGames: [PFGame] {
        switch generation {
        case .gen3: return [.ruby, .sapphire, .emerald, .fireRed, .leafGreen]
        case .gen4: return [.diamond, .pearl, .platinum, .heartGold, .soulSilver]
        case .gen5: return [.black, .white, .black2, .white2]
        }
    }

    private var availableEncounters: [PFEncounter] {
        switch generation {
        case .gen3: return [.grass, .surfing, .oldRod, .goodRod, .superRod, .rockSmash]
        case .gen4: return [.grass, .surfing, .oldRod, .goodRod, .superRod, .rockSmash, .headbutt]
        case .gen5: return [.grass, .grassDark, .grassRustling, .surfing, .surfingRippling, .superRod, .superRodRippling]
        }
    }

    var body: some View {
        ScrollView {
            CardStack {
                Picker("Generation", selection: $generation) {
                    ForEach(EncBrowserGen.allCases) { g in Text(g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: generation) {
                    let games = availableGames
                    if !games.contains(selectedGame) { selectedGame = games[0] }
                    let encounters = availableEncounters
                    if !encounters.contains(selectedEncounter) { selectedEncounter = encounters[0] }
                    loadEncounters()
                }

                HStack {
                    Picker("Game", selection: $selectedGame) {
                        ForEach(availableGames, id: \.rawValue) { g in
                            Text(gameName(g)).tag(g)
                        }
                    }
                    Picker("Type", selection: $selectedEncounter) {
                        ForEach(availableEncounters, id: \.rawValue) { e in
                            Text(e.displayName).tag(e)
                        }
                    }
                }
                .onChange(of: selectedGame) { loadEncounters() }
                .onChange(of: selectedEncounter) { loadEncounters() }

                if areas.isEmpty {
                    ContentUnavailableView("No Encounters",
                                           systemImage: "map",
                                           description: Text("Select a game and encounter type above."))
                } else {
                    Text("\(areas.count) locations found")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVStack(spacing: 8) {
                        ForEach(areas) { area in
                            EncounterAreaCard(area: area,
                                              isExpanded: expandedArea == area.id) {
                                withAnimation(.snappy) {
                                    expandedArea = expandedArea == area.id ? nil : area.id
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear { loadEncounters() }
    }

    private func loadEncounters() {
        switch generation {
        case .gen3:
            areas = PFBridge.getEncounters3(encounter: selectedEncounter, game: selectedGame)
        case .gen4:
            areas = PFBridge.getEncounters4(encounter: selectedEncounter, game: selectedGame,
                                             tid: tid, sid: sid)
        case .gen5:
            areas = PFBridge.getEncounters5(encounter: selectedEncounter, game: selectedGame)
        }
    }

    private func gameName(_ game: PFGame) -> String {
        switch game {
        case .ruby: return "Ruby"
        case .sapphire: return "Sapphire"
        case .emerald: return "Emerald"
        case .fireRed: return "FireRed"
        case .leafGreen: return "LeafGreen"
        case .diamond: return "Diamond"
        case .pearl: return "Pearl"
        case .platinum: return "Platinum"
        case .heartGold: return "HeartGold"
        case .soulSilver: return "SoulSilver"
        case .black: return "Black"
        case .white: return "White"
        case .black2: return "Black 2"
        case .white2: return "White 2"
        default: return "Unknown"
        }
    }
}

struct EncounterAreaCard: View {
    let area: PFEncounterAreaSwift
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(area.locationName.isEmpty ? "Location \(area.location)" : area.locationName)
                            .font(.headline)
                        Text("\(area.encounter.displayName) · Rate: \(area.rate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if isExpanded {
                Divider()
                VStack(spacing: 0) {
                    ForEach(Array(area.slots.enumerated()), id: \.element.id) { index, slot in
                        HStack {
                            Text("#\(index)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .scaledWidth(24, relativeTo: .caption2, alignment: .trailing)
                            Text(slot.specieName)
                                .font(.body)
                            Spacer()
                            if slot.minLevel == slot.maxLevel {
                                Text("Lv. \(slot.minLevel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Lv. \(slot.minLevel)-\(slot.maxLevel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        if index < area.slots.count - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .card(padding: 0)
    }
}

struct StaticEncounterBrowserView: View {
    @State private var generation: FinderGeneration = .gen3
    @State private var category: StaticEncounterCategory = .legends

    /// The same list the Finder offers: PokéFinder's tables.
    private var categories: [StaticEncounterCategory] {
        StaticEncounterCategory.allCases.filter { category in
            StaticEncounterData.all.contains { $0.generation == generation && $0.category == category }
        }
    }

    private var encounters: [StaticEncounter] {
        StaticEncounterData.all.filter { $0.generation == generation && $0.category == category }
    }

    var body: some View {
        ScrollView {
            CardStack {
                Picker("Generation", selection: $generation) {
                    ForEach(FinderGeneration.allCases) { g in Text(g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: generation) {
                    if !categories.contains(category) { category = categories.first ?? .starters }
                }

                Picker("Category", selection: $category) {
                    ForEach(categories) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }

                let list = encounters
                if list.isEmpty {
                    ContentUnavailableView("No Encounters",
                                           systemImage: "sparkles",
                                           description: Text("No static encounters for this category."))
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(list) { encounter in
                            HStack {
                                Text(encounter.speciesName)
                                    .font(.body)
                                if encounter.shinyLocked {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2).foregroundStyle(.secondary)
                                        .accessibilityLabel("Shiny-locked")
                                }
                                Spacer()
                                Text("Lv. \(encounter.level)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(gameLabel(encounter.games))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .card(padding: 0)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func gameLabel(_ game: UInt32) -> String {
        let mapping: [(UInt32, String)] = [
            (1, "R"), (2, "S"), (3, "RS"), (4, "E"), (7, "RSE"),
            (8, "FR"), (16, "LG"), (24, "FRLG"),
            (32, "XD"), (64, "Colo"),
            (128, "D"), (256, "P"), (384, "DP"), (512, "Pt"), (896, "DPPt"),
            (1024, "HG"), (2048, "SS"), (3072, "HGSS"),
            (4096, "B"), (8192, "W"), (12288, "BW"),
            (16384, "B2"), (32768, "W2"), (49152, "B2W2"),
            (67108864, "BD"), (134217728, "SP"), (201326592, "BDSP"),
        ]
        for (val, name) in mapping {
            if game == val { return name }
        }
        if game & 7 != 0 { return "RSE" }
        if game & 24 != 0 { return "FRLG" }
        if game & 896 != 0 { return "DPPt" }
        if game & 3072 != 0 { return "HGSS" }
        if game & 12288 != 0 { return "BW" }
        if game & 49152 != 0 { return "B2W2" }
        if game & 201326592 != 0 { return "BDSP" }
        return String(format: "0x%X", game)
    }
}
