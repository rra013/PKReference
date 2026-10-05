//
//  IVCalculatorView.swift
//  PKReference
//
//  The RNG tools' IV calculator. For the RNG games it's PokéFinder's (its
//  Util/IVCalculator): each game's own base stats, IVs narrowed by the
//  nature, characteristic and Hidden Power, more lines from other levels,
//  and the level at which each stat next tells its IVs apart. A fresh catch
//  has no EVs. For today's games it uses the current base stats, with EVs.
//

import SwiftUI
import SwiftData

/// Which base stats to use: PokéFinder's tables for the RNG games, as its
/// IV calculator offers them, or today's.
enum IVCalcGame: String, CaseIterable, Identifiable {
    case gen3 = "Ruby, Sapphire, Emerald, FRLG"
    case dppt = "Diamond, Pearl, Platinum"
    case hgss = "HeartGold, SoulSilver"
    case bw = "Black, White, Black 2, White 2"
    case bdsp = "Brilliant Diamond, Shining Pearl"
    case swsh = "Sword, Shield"
    case current = "Today's Games"
    var id: String { rawValue }

    /// The PokéFinder table: Platinum's covers Diamond and Pearl, Black 2
    /// and White 2's Black and White, as in PokéFinder.
    var pfGame: PFGame? {
        switch self {
        case .gen3: .emerald
        case .dppt: .platinum
        case .hgss: .heartGold
        case .bw: .black2
        case .bdsp: .bd
        case .swsh: .sword
        case .current: nil
        }
    }

    /// Characteristics came in Gen 4.
    var hasCharacteristics: Bool { self != .gen3 }
}

/// "Modest (+SpA / -Atk)" for PokéFinder's nature `index` (pid % 25), whose
/// order isn't `allNatures`'.
func pfNatureLabel(_ index: Int) -> String {
    let name = pfNatureNames[index]
    guard let nature = allNatures.first(where: { $0.name == name }), nature.boosted != nil else { return name }
    return "\(name) (\(nature.summary))"
}

/// PokéFinder's IV calculator, for the RNG games.
nonisolated enum IVCalcEngine {
    struct Result: Equatable {
        /// Per stat, every IV that fits.
        let ivs: [[UInt8]]
        /// Per stat, the first level at which its stat narrows its IVs (the
        /// last line's level when it's known or no level does).
        let nextLevel: [UInt8]
    }

    enum Outcome: Equatable {
        case result(Result)
        case error(String)
    }

    static let statNames = ["HP", "Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed"]

    /// Lines after the first with no stats yet are left out, so adding one
    /// doesn't stop a calculation. `nature`, `characteristic` and
    /// `hiddenPower` are PokéFinder's indices, nil for any.
    static func calculate(game: PFGame, specie: UInt16, form: UInt8, lines: [FRLGStatsLine],
                          nature: UInt8?, characteristic: UInt8?, hiddenPower: UInt8?) -> Outcome {
        var parsed: [(level: UInt8, stats: [UInt16])] = []
        for (number, line) in zip(1..., lines) where number == 1 || !line.isBlank {
            let name = lines.count > 1 ? "Line \(number): " : ""
            guard let level = line.level else { return .error(name + "Enter its level.") }
            guard (1...100).contains(level) else { return .error(name + "Level must be 1–100.") }
            var stats: [UInt16] = []
            for (index, stat) in line.stats.enumerated() {
                guard let stat else { return .error(name + "Enter its \(statNames[index]).") }
                guard (1...999).contains(stat) else { return .error(name + "\(statNames[index]) must be 1–999.") }
                stats.append(UInt16(stat))
            }
            parsed.append((UInt8(level), stats))
        }
        guard let ivs = PFBridge.calcIVs(game: game, specie: specie, form: form, lines: parsed,
                                         nature: nature ?? 255, characteristic: characteristic ?? 255,
                                         hiddenPower: hiddenPower ?? 255) else {
            return .error("That Pokémon isn't in this game.")
        }
        if let index = ivs.firstIndex(where: \.isEmpty) {
            return .error("No \(statNames[index]) IV fits. Check the nature, level and stats.")
        }
        let next = PFBridge.nextLevel(game: game, specie: specie, form: form, ivs: ivs,
                                      level: parsed.last?.level ?? 1, nature: nature ?? 255)
        return .result(Result(ivs: ivs, nextLevel: next ?? Array(repeating: parsed.last?.level ?? 1, count: 6)))
    }

    /// "17–19", "17, 19, 21" or "31".
    static func text(_ ivs: [UInt8]) -> String {
        var runs: [ClosedRange<UInt8>] = []
        for iv in ivs.sorted() {
            if let last = runs.last, last.upperBound + 1 == iv {
                runs[runs.count - 1] = last.lowerBound...iv
            } else {
                runs.append(iv...iv)
            }
        }
        return runs.map { $0.count == 1 ? "\($0.lowerBound)" : $0.count == 2 ? "\($0.lowerBound), \($0.upperBound)" : "\($0.lowerBound)–\($0.upperBound)" }
            .joined(separator: ", ")
    }
}

struct IVCalculatorView: View {
    @AppStorage("ivcalc_game") private var game: IVCalcGame = .gen3

    var body: some View {
        ScrollView {
            CardStack {
                SectionCard(title: "Game", icon: "gamecontroller") {
                    Picker("Game", selection: $game) {
                        ForEach(IVCalcGame.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    Text(game == .current
                         ? "Today's base stats, with EVs, for a Pokémon from the current games."
                         : "That game's base stats, as PokéFinder has them: a fresh catch, with no EVs. Many species' stats changed in later games.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let pfGame = game.pfGame {
                    RNGGameIVCalc(game: game, pfGame: pfGame)
                        .id(game)
                } else {
                    CurrentGamesIVCalc()
                }
            }
            .padding()
        }
        .dismissesKeyboard()
    }
}

// MARK: - The RNG games

private struct RNGGameIVCalc: View {
    let game: IVCalcGame
    let pfGame: PFGame

    @State private var species: [(id: UInt16, name: String)] = []
    @State private var searchText = ""
    @State private var specie: UInt16?
    @State private var form: UInt8 = 0
    @State private var nature: UInt8?
    @State private var characteristic: UInt8?
    @State private var hiddenPower: UInt8?
    @State private var lines = [FRLGStatsLine(level: 50)]
    @State private var outcome: IVCalcEngine.Outcome?
    @FocusState private var searching: Bool

    private var matches: [(id: UInt16, name: String)] {
        let text = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return [] }
        return Array(species.filter { $0.name.lowercased().contains(text) }.prefix(20))
    }

    var body: some View {
        SectionCard(title: "Pokémon", icon: "sparkles") {
            TextField("Search Pokémon…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($searching)
                .onChange(of: searchText) {
                    if let specie, PFBridge.specieName(specie) != searchText { self.specie = nil }
                }
            if specie == nil {
                ForEach(matches, id: \.id) { match in
                    Button {
                        specie = match.id
                        form = 0
                        searchText = match.name
                        outcome = nil
                        searching = false
                    } label: {
                        Text(match.name).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
            if let specie {
                let forms = PFBridge.formCount(game: pfGame, specie: specie)
                if forms > 1 {
                    LabeledContent("Form") {
                        Picker("Form", selection: $form) {
                            ForEach(0..<forms, id: \.self) { index in
                                let name = PFBridge.formName(specie: specie, form: UInt8(index))
                                Text(name.isEmpty ? "\(index)" : name).tag(UInt8(index))
                            }
                        }
                        .labelsHidden()
                    }
                }
                if let base = PFBridge.baseStats(game: pfGame, specie: specie, form: form) {
                    baseStatsRow(base)
                }
            }
        }
        // Loaded on appearing: a game's list is up to 898 names.
        .onAppear { if species.isEmpty { loadSpecies() } }
        if specie != nil {
            SectionCard(title: "What You Know", icon: "slider.horizontal.3") {
                LabeledContent("Nature") {
                    Picker("Nature", selection: $nature) {
                        Text("Any").tag(UInt8?.none)
                        ForEach(0..<25, id: \.self) { Text(pfNatureLabel($0)).tag(UInt8?.some(UInt8($0))) }
                    }
                    .labelsHidden()
                }
                if game.hasCharacteristics {
                    LabeledContent("Characteristic") {
                        Picker("Characteristic", selection: $characteristic) {
                            Text("None").tag(UInt8?.none)
                            ForEach(0..<30, id: \.self) {
                                Text(PFBridge.characteristics[$0]).tag(UInt8?.some(UInt8($0)))
                            }
                        }
                        .labelsHidden()
                    }
                }
                LabeledContent("Hidden Power") {
                    Picker("Hidden Power", selection: $hiddenPower) {
                        Text("Any").tag(UInt8?.none)
                        ForEach(0..<16, id: \.self) { Text(hiddenPowerTypes[$0]).tag(UInt8?.some(UInt8($0))) }
                    }
                    .labelsHidden()
                }
            }
            SectionCard(title: "Stats", icon: "number") {
                Text("From its summary screen. Stats at more levels narrow its IVs down.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach($lines) { $line in
                    if lines.count > 1 {
                        HStack {
                            Text("Line \((lines.firstIndex { $0.id == line.id } ?? 0) + 1)").font(.subheadline.bold())
                            Spacer()
                            Button(role: .destructive) {
                                lines.removeAll { $0.id == line.id }
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                        .padding(.top, 4)
                    }
                    RNGOptIntField(label: "Level", value: $line.level)
                    ForEach(0..<6, id: \.self) { stat in
                        RNGOptIntField(label: IVCalcEngine.statNames[stat], value: $line.stats[stat])
                    }
                }
                Button {
                    lines.append(FRLGStatsLine(level: lines.last?.level.map { min($0 + 1, 100) }))
                } label: {
                    Label("Add Stats at Another Level", systemImage: "plus.circle")
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            Button {
                calculate()
            } label: {
                Label("Find IVs", systemImage: "function")
            }
            .buttonStyle(.primaryAction)
            if let outcome {
                resultsCard(outcome)
            }
        }
    }

    private func calculate() {
        guard let specie else { return }
        outcome = IVCalcEngine.calculate(game: pfGame, specie: specie, form: form, lines: lines,
                                         nature: nature, characteristic: game.hasCharacteristics ? characteristic : nil,
                                         hiddenPower: hiddenPower)
    }

    @ViewBuilder
    private func resultsCard(_ outcome: IVCalcEngine.Outcome) -> some View {
        SectionCard(title: "IVs", icon: "checkmark.circle") {
            switch outcome {
            case .error(let message):
                Text(message).font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            case .result(let result):
                ForEach(0..<6, id: \.self) { stat in
                    HStack(alignment: .firstTextBaseline) {
                        Text(IVCalcEngine.statNames[stat])
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(IVCalcEngine.text(result.ivs[stat]))
                                .font(.system(.body, design: .monospaced)).bold()
                            if result.ivs[stat].count > 1, let level = lines.last?.level,
                               Int(result.nextLevel[stat]) > level {
                                Text("Narrows at Lv \(result.nextLevel[stat])")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func baseStatsRow(_ base: [UInt8]) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                VStack(spacing: 2) {
                    Text(["HP", "Atk", "Def", "SpA", "SpD", "Spe"][index]).foregroundStyle(.secondary)
                    Text("\(base[index])").bold()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .font(.caption)
    }

    private func loadSpecies() {
        species = PFBridge.presentSpecies(game: pfGame).map { ($0, PFBridge.specieName($0)) }
            .sorted { $0.name < $1.name }
    }
}

// MARK: - Today's games

/// Today's base stats, from the Pokédex, with EVs.
private struct CurrentGamesIVCalc: View {
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @State private var searchText = ""
    @State private var selectedPokemon: PKMNStats?
    @State private var level: UInt8 = 50
    @State private var natureIndex: UInt8 = 3 // Adamant, PokéFinder's order

    @State private var evHP = 0; @State private var evAtk = 0; @State private var evDef = 0
    @State private var evSpAtk = 0; @State private var evSpDef = 0; @State private var evSpeed = 0

    @State private var statHP: UInt16 = 0; @State private var statAtk: UInt16 = 0
    @State private var statDef: UInt16 = 0; @State private var statSpAtk: UInt16 = 0
    @State private var statSpDef: UInt16 = 0; @State private var statSpeed: UInt16 = 0

    @State private var results: [IVCalcResult] = []
    @FocusState private var searching: Bool

    private var filteredPokemon: [PKMNStats] {
        let t = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return [] }
        return Array(allPokemon.filter { $0.name.lowercased().contains(t) }.prefix(20))
    }

    var body: some View {
        if allPokemon.isEmpty {
            ContentUnavailableView("Syncing Data", systemImage: "antenna.radiowaves.left.and.right",
                                   description: Text("Waiting for Pokémon data to sync…"))
        } else {
            pokemonSelector
            if selectedPokemon != nil {
                configSection
                statEntrySection
                calculateButton
                resultsSection
            }
        }
    }

    private var pokemonSelector: some View {
        SectionCard(title: "Pokémon", icon: "sparkles") {
            VStack(spacing: 8) {
                TextField("Search Pokémon…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .focused($searching)
                    .onChange(of: searchText) {
                        if selectedPokemon?.name != searchText { selectedPokemon = nil; results = [] }
                    }

                if !filteredPokemon.isEmpty && selectedPokemon == nil {
                    ForEach(filteredPokemon, id: \.id) { pkmn in
                        Button {
                            selectedPokemon = pkmn
                            searchText = pkmn.name
                            results = []
                            searching = false
                        } label: {
                            Text(pkmn.name).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4).padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let pkmn = selectedPokemon {
                    HStack(spacing: 12) {
                        baseStatPill("HP", pkmn.baseHP)
                        baseStatPill("Atk", pkmn.baseAtk)
                        baseStatPill("Def", pkmn.baseDef)
                        baseStatPill("SpA", pkmn.baseSpAtk)
                        baseStatPill("SpD", pkmn.baseSpDef)
                        baseStatPill("Spe", pkmn.baseSpeed)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func baseStatPill(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text("\(value)").bold()
        }
        .frame(maxWidth: .infinity)
    }

    private var configSection: some View {
        SectionCard(title: "Level and Nature", icon: "slider.horizontal.3") {
            HStack {
                Text("Level")
                Spacer()
                LiveIntField("Lv", value: $level, range: 1...100)
                    .textFieldStyle(.roundedBorder).scaledWidth(60)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Nature") {
                Picker("Nature", selection: $natureIndex) {
                    ForEach(0..<25, id: \.self) { Text(pfNatureLabel($0)).tag(UInt8($0)) }
                }
                .labelsHidden()
            }
        }
    }

    private var statEntrySection: some View {
        SectionCard(title: "Stats and EVs", icon: "number") {
            VStack(spacing: 8) {
                IVCalcRow16(label: "HP", stat: $statHP, ev: $evHP)
                IVCalcRow16(label: "Attack", stat: $statAtk, ev: $evAtk)
                IVCalcRow16(label: "Defense", stat: $statDef, ev: $evDef)
                IVCalcRow16(label: "Sp. Atk", stat: $statSpAtk, ev: $evSpAtk)
                IVCalcRow16(label: "Sp. Def", stat: $statSpDef, ev: $evSpDef)
                IVCalcRow16(label: "Speed", stat: $statSpeed, ev: $evSpeed)
            }
        }
    }

    private var calculateButton: some View {
        Button {
            guard let pkmn = selectedPokemon else { return }
            let baseStats: [UInt8] = [pkmn.baseHP, pkmn.baseAtk, pkmn.baseDef,
                                      pkmn.baseSpAtk, pkmn.baseSpDef, pkmn.baseSpeed].map { UInt8(clamping: $0) }
            let stats: [[UInt16]] = [[statHP, statAtk, statDef, statSpAtk, statSpDef, statSpeed]]
            results = pfCalculateIVRange(baseStats: baseStats, stats: stats, levels: [level], nature: natureIndex,
                                         evs: [evHP, evAtk, evDef, evSpAtk, evSpDef, evSpeed])
        } label: {
            Label("Find IVs", systemImage: "function")
        }
        .buttonStyle(.primaryAction)
    }

    @ViewBuilder
    private var resultsSection: some View {
        if !results.isEmpty {
            SectionCard(title: "IVs", icon: "checkmark.circle") {
                ForEach(results) { r in
                    HStack {
                        Text(r.statName).lineLimit(1)
                        Spacer()
                        if r.possibleIVs.isEmpty {
                            Text("None fits").foregroundStyle(.red).bold()
                        } else {
                            Text(IVCalcEngine.text(r.possibleIVs))
                                .font(.system(.body, design: .monospaced)).bold()
                        }
                    }
                }
            }
        }
    }
}
