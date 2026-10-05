import SwiftUI

/// Every game's wild areas, as the Finder lists them (`WildAreaData`): by
/// location, with each slot's chance.
struct EncounterBrowserView: View {
    @State private var generation: FinderGeneration = .gen3
    @State private var selectedGame: FinderGameVersion = .emerald
    @State private var selectedEncounter: PFEncounter = .grass
    @State private var expandedArea: String?
    /// Gen 4 and BDSP: 0 morning, 1 day, 2 night.
    @State private var time: Int32 = 0
    /// Gen 5: 0 spring to 3 winter.
    @State private var season: UInt8 = 0

    private static let generations: [FinderGeneration] = [.gen3, .gen4, .gen5, .gen8]

    private var availableGames: [FinderGameVersion] {
        FinderGameVersion.games(for: generation).filter { !$0.isSwSh }
    }

    private var availableEncounters: [PFEncounter] {
        switch generation {
        case .gen3: return [.grass, .surfing, .oldRod, .goodRod, .superRod, .rockSmash]
        case .gen4: return [.grass, .surfing, .oldRod, .goodRod, .superRod, .rockSmash, .headbutt]
        case .gen5: return [.grass, .grassDark, .grassRustling, .surfing, .surfingRippling, .superRod, .superRodRippling]
        case .gen8: return [.grass, .surfing, .oldRod, .goodRod, .superRod]
        }
    }

    private var settings: WildSettings {
        WildSettings(time: time, season: season)
    }

    /// By location ID, the game's map order, as the Finder lists them.
    private var areas: [WildArea] {
        WildAreaData.areas(for: selectedGame, encounter: selectedEncounter, settings: settings)
            .sorted { $0.location < $1.location }
    }

    /// Time of day changes Gen 4 and BDSP grass (and HeartGold and
    /// SoulSilver's fishing).
    private var showsTime: Bool {
        guard let type = EncounterType(from: selectedEncounter) else { return false }
        return WildAreaData.settingsShown(game: selectedGame, type: type, location: nil).contains(.time)
    }

    var body: some View {
        let areas = areas
        ScrollView {
            CardStack {
                Picker("Generation", selection: $generation) {
                    ForEach(Self.generations) { g in Text(g == .gen8 ? "BDSP" : g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: generation) {
                    let games = availableGames
                    if !games.contains(selectedGame) { selectedGame = games[0] }
                    let encounters = availableEncounters
                    if !encounters.contains(selectedEncounter) { selectedEncounter = encounters[0] }
                }

                HStack {
                    Picker("Game", selection: $selectedGame) {
                        ForEach(availableGames) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                    Picker("Type", selection: $selectedEncounter) {
                        ForEach(availableEncounters, id: \.rawValue) { e in
                            Text(e.displayName).tag(e)
                        }
                    }
                }

                if generation == .gen5 {
                    Picker("Season", selection: $season) {
                        Text("Spring").tag(UInt8(0))
                        Text("Summer").tag(UInt8(1))
                        Text("Autumn").tag(UInt8(2))
                        Text("Winter").tag(UInt8(3))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } else if showsTime {
                    Picker("Time", selection: $time) {
                        Text("Morning").tag(Int32(0))
                        Text("Day").tag(Int32(1))
                        Text("Night").tag(Int32(2))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

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
    }
}

struct EncounterAreaCard: View {
    let area: WildArea
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(area.name)
                            .font(.headline)
                        Text(area.rate > 0 ? "\(area.encounter.displayName) · Rate: \(area.rate)"
                                           : area.encounter.displayName)
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
                    ForEach(area.slots) { slot in
                        HStack {
                            Text(slot.slotRate)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .scaledWidth(40, relativeTo: .caption2, alignment: .trailing)
                            Text(slot.speciesName)
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
                        if slot.index < area.slots.count - 1 {
                            Divider().padding(.leading, 56)
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
