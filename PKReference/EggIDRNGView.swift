import SwiftUI

// MARK: - Egg RNG View

struct EggRNGView: View {
    @State private var generation: FinderGeneration = .gen3
    @State private var selectedGame: FinderGameVersion = .emerald

    // Profile
    @State private var tid: UInt16 = 0
    @State private var sid: UInt16 = 0
    @State private var savedProfiles: [FinderProfile] = FinderProfileStore.load()
    @State private var selectedProfileID: UUID? = FinderProfileStore.lastProfileID

    // Seeds
    @State private var seedHeldText = ""
    @State private var seedPickupText = ""

    // Advances
    @State private var initialAdvances: Int = 0
    @State private var maxAdvances: Int = 5000
    @State private var initialAdvancesPickup: Int = 0
    @State private var maxAdvancesPickup: Int = 100

    // Emerald-specific
    @State private var calibration: Int = 0
    @State private var minRedraw: Int = 0
    @State private var maxRedraw: Int = 0

    // Parent A
    @State private var parentAHP: UInt8 = 31
    @State private var parentAAtk: UInt8 = 31
    @State private var parentADef: UInt8 = 31
    @State private var parentASpA: UInt8 = 31
    @State private var parentASpD: UInt8 = 31
    @State private var parentASpe: UInt8 = 31
    @State private var parentAAbility: UInt8 = 0
    @State private var parentAGender: UInt8 = 0
    @State private var parentAItem: UInt8 = 0
    @State private var parentANature: UInt8 = 0

    // Parent B
    @State private var parentBHP: UInt8 = 31
    @State private var parentBAtk: UInt8 = 31
    @State private var parentBDef: UInt8 = 31
    @State private var parentBSpA: UInt8 = 31
    @State private var parentBSpD: UInt8 = 31
    @State private var parentBSpe: UInt8 = 31
    @State private var parentBAbility: UInt8 = 0
    @State private var parentBGender: UInt8 = 1
    @State private var parentBItem: UInt8 = 0
    @State private var parentBNature: UInt8 = 0

    // Egg species
    @State private var eggSpecie: Int = 1
    @State private var masuda: Bool = false
    @State private var compatibility: Int = 20

    // Filters
    @State private var selectedNatures: Set<UInt8> = []
    @State private var shinyOnly: Bool = false

    // Results
    @State private var results3: [PFBridge.EggResult3] = []
    @State private var results4: [PFBridge.EggResult4] = []
    @State private var searchTask: Task<Void, Never>?

    static let generations: [FinderGeneration] = [.gen3, .gen4]

    /// PokéFinder pairs every held egg with every pickup advance and keeps
    /// them all, so wide ranges run out of memory: 10,000 by 10,000 is 100
    /// million Gen 4 eggs.
    static let resultLimit = 1_000_000

    /// About how many eggs the generator will list: held × pickup advances,
    /// in Gen 3 times the chance an egg is made at all (and each Emerald
    /// redraw), less what the nature and shiny filters drop.
    static func estimatedResults(held: ClosedRange<Int>?, pickup: ClosedRange<Int>?, gen3Compatibility: Int?,
                                 redraws: Int = 1, natures: Int, shinyOnly: Bool) -> Double {
        guard let held, let pickup else { return 0 }
        var estimate = Double(held.count) * Double(pickup.count)
        if let gen3Compatibility { estimate *= Double(gen3Compatibility) / 100 * Double(max(1, redraws)) }
        if natures > 0 { estimate *= Double(natures) / 25 }
        // Generous for the Masuda method's extra rolls.
        if shinyOnly { estimate /= 1_000 }
        return estimate
    }

    private var estimatedResults: Double {
        Self.estimatedResults(
            held: initialAdvances <= maxAdvances ? initialAdvances...maxAdvances : nil,
            pickup: initialAdvancesPickup <= maxAdvancesPickup ? initialAdvancesPickup...maxAdvancesPickup : nil,
            gen3Compatibility: generation == .gen3 ? compatibility : nil,
            redraws: selectedGame == .emerald ? maxRedraw - minRedraw + 1 : 1,
            natures: selectedNatures.count, shinyOnly: shinyOnly)
    }

    private var tooManyResults: Bool { estimatedResults > Double(Self.resultLimit) }

    var body: some View {
        ScrollView {
            CardStack {
                // Gen 3 and 4 only: Gen 8 eggs are the Finder's Egg mode, and
                // Gen 5's need the DS profile.
                Picker("Generation", selection: $generation) {
                    ForEach(Self.generations) { g in Text(g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: generation) {
                    let games = FinderGameVersion.games(for: generation)
                    if !games.contains(selectedGame) { selectedGame = games[0] }
                }

                Picker("Game", selection: $selectedGame) {
                    ForEach(FinderGameVersion.games(for: generation)) { g in
                        Text(g.rawValue).tag(g)
                    }
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

                // Seeds
                SectionCard(title: "Seeds", icon: "number") {
                    HStack {
                        Text("Held Seed")
                        Spacer()
                        TextField("Hex", text: $seedHeldText)
                            .textFieldStyle(.roundedBorder).scaledWidth(120)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Text("Pickup Seed")
                        Spacer()
                        TextField("Hex", text: $seedPickupText)
                            .textFieldStyle(.roundedBorder).scaledWidth(120)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                    RNGIntField(label: "Initial Advance", value: $initialAdvances, range: RNGFieldRange.advances)
                    RNGIntField(label: "Max Advance", value: $maxAdvances, range: RNGFieldRange.advances)
                    RNGIntField(label: "Pickup Init Adv", value: $initialAdvancesPickup, range: RNGFieldRange.advances)
                    RNGIntField(label: "Pickup Max Adv", value: $maxAdvancesPickup, range: RNGFieldRange.advances)

                    if generation == .gen3 && selectedGame == .emerald {
                        RNGIntField(label: "Calibration", value: $calibration, range: RNGFieldRange.byte)
                        RNGIntField(label: "Min Redraw", value: $minRedraw, range: RNGFieldRange.byte)
                        RNGIntField(label: "Max Redraw", value: $maxRedraw, range: RNGFieldRange.byte)
                    }
                }

                // Daycare
                SectionCard(title: "Daycare", icon: "house") {
                    Picker("Compatibility", selection: $compatibility) {
                        Text("The two seem to get along (20%)").tag(20)
                        Text("The two seem to get along very well (50%)").tag(50)
                        Text("The two don't seem to like each other (70%)").tag(70)
                    }

                    Toggle("Masuda Method", isOn: $masuda)

                    HStack {
                        Text("Egg Species #")
                        Spacer()
                        TextField("", value: $eggSpecie, format: .number)
                            .clamping($eggSpecie, to: 1...Int(UInt16.max))
                            .textFieldStyle(.roundedBorder).scaledWidth(80)
                            .multilineTextAlignment(.trailing)
                    }
                }

                parentSection(label: "Parent A",
                              hp: $parentAHP, atk: $parentAAtk, def: $parentADef,
                              spa: $parentASpA, spd: $parentASpD, spe: $parentASpe,
                              ability: $parentAAbility, gender: $parentAGender,
                              item: $parentAItem, nature: $parentANature)

                parentSection(label: "Parent B",
                              hp: $parentBHP, atk: $parentBAtk, def: $parentBDef,
                              spa: $parentBSpA, spd: $parentBSpD, spe: $parentBSpe,
                              ability: $parentBAbility, gender: $parentBGender,
                              item: $parentBItem, nature: $parentBNature)

                FinderNatureGrid(selected: $selectedNatures)

                Toggle("Shiny Only", isOn: $shinyOnly)
                    .padding(.horizontal)

                Button {
                    generateEggs()
                } label: {
                    Label("Generate", systemImage: "sparkles")
                }
                .buttonStyle(.primaryAction)
                .disabled(tooManyResults)
                if tooManyResults {
                    Text("These ranges would list about \(Int(estimatedResults).formatted()) eggs, more than \(Self.resultLimit.formatted()). Narrow the held or pickup advances, or filter by nature or shininess.")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if generation == .gen3 && !results3.isEmpty {
                    eggResults3Section
                }
                if generation == .gen4 && !results4.isEmpty {
                    eggResults4Section
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        #if os(iOS)
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        #endif
    }

    private func parentSection(label: String,
                                hp: Binding<UInt8>, atk: Binding<UInt8>, def: Binding<UInt8>,
                                spa: Binding<UInt8>, spd: Binding<UInt8>, spe: Binding<UInt8>,
                                ability: Binding<UInt8>, gender: Binding<UInt8>,
                                item: Binding<UInt8>, nature: Binding<UInt8>) -> some View {
        SectionCard(title: label, icon: "figure.stand") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                IVSliderRow8(label: "HP", value: hp)
                IVSliderRow8(label: "Atk", value: atk)
                IVSliderRow8(label: "Def", value: def)
                IVSliderRow8(label: "SpA", value: spa)
                IVSliderRow8(label: "SpD", value: spd)
                IVSliderRow8(label: "Spe", value: spe)
            }

            Picker("Gender", selection: gender) {
                Text("Male").tag(UInt8(0))
                Text("Female").tag(UInt8(1))
                Text("Ditto").tag(UInt8(3))
            }

            Picker("Ability", selection: ability) {
                Text("Ability 0").tag(UInt8(0))
                Text("Ability 1").tag(UInt8(1))
            }

            Picker("Nature", selection: nature) {
                ForEach(0..<25, id: \.self) { i in
                    Text(pfNatureNames[i]).tag(UInt8(i))
                }
            }

            Picker("Held Item", selection: item) {
                Text("None").tag(UInt8(0))
                Text("Everstone").tag(UInt8(1))
                Text("Power Weight (HP)").tag(UInt8(2))
                Text("Power Bracer (Atk)").tag(UInt8(3))
                Text("Power Belt (Def)").tag(UInt8(4))
                Text("Power Lens (SpA)").tag(UInt8(5))
                Text("Power Band (SpD)").tag(UInt8(6))
                Text("Power Anklet (Spe)").tag(UInt8(7))
            }
        }
    }

    private var eggResults3Section: some View {
        SectionCard(title: "Results (\(results3.count))", icon: "list.bullet") {
            ForEach(results3.prefix(500)) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Adv: \(r.advances)")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text("Pickup: \(r.pickupAdvances)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("PID: \(String(format: "%08X", r.pid))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(pfNatureNames[Int(r.nature)]).font(.caption2).bold()
                        if r.shiny > 0 {
                            Image(systemName: "star.fill")
                                .font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                    Text("IVs: \(r.ivs.map(String.init).joined(separator: "/"))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Inherit: \(inheritanceString(r.inheritance))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Divider()
            }
        }
    }

    private var eggResults4Section: some View {
        SectionCard(title: "Results (\(results4.count))", icon: "list.bullet") {
            ForEach(results4.prefix(500)) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Adv: \(r.advances)")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text("Pickup: \(r.pickupAdvances)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("PID: \(String(format: "%08X", r.pid))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(pfNatureNames[Int(r.nature)]).font(.caption2).bold()
                        if r.chatot > 0 {
                            Text("C:\(r.chatot)").font(.caption2).foregroundStyle(.orange)
                        }
                        if r.shiny > 0 {
                            Image(systemName: "star.fill")
                                .font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                    Text("IVs: \(r.ivs.map(String.init).joined(separator: "/"))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Inherit: \(inheritanceString(r.inheritance))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Divider()
            }
        }
    }

    private func inheritanceString(_ inh: [UInt8]) -> String {
        let labels = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
        return (0..<6).map { i in
            switch inh[i] {
            case 1: return "\(labels[i]):A"
            case 2: return "\(labels[i]):B"
            default: return "\(labels[i]):R"
            }
        }.joined(separator: " ")
    }

    private func generateEggs() {
        let gen = generation
        let seedH = UInt32(seedHeldText, radix: 16) ?? 0
        let seedP = UInt32(seedPickupText, radix: 16) ?? 0
        let tID = tid, sID = sid
        let initAdv = UInt32(clamping: initialAdvances), maxAdv = UInt32(clamping: maxAdvances)
        let initAdvP = UInt32(clamping: initialAdvancesPickup), maxAdvP = UInt32(clamping: maxAdvancesPickup)
        let cal = UInt8(clamping: calibration), minR = UInt8(clamping: minRedraw), maxR = UInt8(clamping: maxRedraw)
        let compat = UInt8(clamping: compatibility)
        let pAIVs = [parentAHP, parentAAtk, parentADef, parentASpA, parentASpD, parentASpe]
        let pBIVs = [parentBHP, parentBAtk, parentBDef, parentBSpA, parentBSpD, parentBSpe]
        let pAA = parentAAbility, pBA = parentBAbility
        let pAG = parentAGender, pBG = parentBGender
        let pAI = parentAItem, pBI = parentBItem
        let pAN = parentANature, pBN = parentBNature
        let spec = UInt16(clamping: eggSpecie)
        let mas = masuda
        let gameVal = selectedGame.pfGame
        let isDeadBattery = selectedGame == .emerald
        let shiny = shinyOnly
        var natArr = [Bool](repeating: selectedNatures.isEmpty, count: 25)
        for n in selectedNatures { natArr[Int(n)] = true }
        let shinyFilter: UInt8 = pfShinyFilter(shiny)

        let eggMethod: PFMethod = (selectedGame == .emerald) ? .eBred : .rsFRLGBred

        searchTask = Task.detached {
            if gen == .gen3 {
                let r = PFBridge.eggGenerate3(
                    seedHeld: seedH, seedPickup: seedP,
                    initialAdvances: initAdv, maxAdvances: maxAdv,
                    initialAdvancesPickup: initAdvP, maxAdvancesPickup: maxAdvP,
                    calibration: cal, minRedraw: minR, maxRedraw: maxR,
                    method: eggMethod, compatibility: compat,
                    parentAIVs: pAIVs, parentBIVs: pBIVs,
                    parentAAbility: pAA, parentBAbility: pBA,
                    parentAGender: pAG, parentBGender: pBG,
                    parentAItem: pAI, parentBItem: pBI,
                    parentANature: pAN, parentBNature: pBN,
                    eggSpecie: spec, masuda: mas,
                    tid: tID, sid: sID,
                    game: gameVal, deadBattery: isDeadBattery,
                    filterShiny: shinyFilter, natures: natArr)
                await MainActor.run { results3 = r }
            } else {
                let r = PFBridge.eggGenerate4(
                    seedHeld: seedH, seedPickup: seedP,
                    initialAdvances: initAdv, maxAdvances: maxAdv,
                    initialAdvancesPickup: initAdvP, maxAdvancesPickup: maxAdvP,
                    parentAIVs: pAIVs, parentBIVs: pBIVs,
                    parentAAbility: pAA, parentBAbility: pBA,
                    parentAGender: pAG, parentBGender: pBG,
                    parentAItem: pAI, parentBItem: pBI,
                    parentANature: pAN, parentBNature: pBN,
                    eggSpecie: spec, masuda: mas,
                    tid: tID, sid: sID,
                    game: gameVal,
                    filterShiny: shinyFilter, natures: natArr)
                await MainActor.run { results4 = r }
            }
        }
    }
}

// MARK: - ID RNG View

struct IDRNGView: View {
    @State private var generation: FinderGeneration = .gen3
    @State private var selectedGame: FinderGameVersion = .emerald

    // Gen 3
    @State private var gen3SeedText = ""
    @State private var gen3TID: UInt16 = 0
    @State private var gen3InitAdvance: Int = 0
    @State private var gen3MaxAdvance: Int = 100000

    // Gen 4 - Generator
    @State private var gen4Mode: Int = 0 // 0 = Generator, 1 = Searcher
    @State private var gen4MinDelay: Int = 500
    @State private var gen4MaxDelay: Int = 10000
    @State private var gen4Year: Int = 2000
    @State private var gen4Month: Int = 1
    @State private var gen4Day: Int = 1
    @State private var gen4Hour: Int = 0
    @State private var gen4Minute: Int = 0
    @State private var gen4TargetTID: UInt16 = 0
    @State private var gen4FilterTID: Bool = false
    @State private var gen4TargetSID: UInt16 = 0
    @State private var gen4FilterSID: Bool = false
    @State private var gen4TargetTSV: UInt16 = 0
    @State private var gen4FilterTSV: Bool = false

    // Gen 4 - Searcher
    @State private var gen4SearchInfinite: Bool = false
    @State private var gen4SearchYear: Int = 2000
    @State private var gen4SearchMinDelay: Int = 500
    @State private var gen4SearchMaxDelay: Int = 10000
    @State private var gen4SearchHandle: OpaquePointer?
    @State private var gen4SearchProgress: Int = 0
    @State private var gen4Searching: Bool = false

    // Seed verification
    @State private var selectedResult: PFBridge.IDResult4?

    // Results
    @State private var results3: [PFBridge.IDResult] = []
    @State private var results4: [PFBridge.IDResult4] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            CardStack {
                Picker("Generation", selection: $generation) {
                    ForEach(FinderGeneration.allCases) { g in Text(g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: generation) {
                    let games = FinderGameVersion.games(for: generation)
                    if !games.contains(selectedGame) { selectedGame = games[0] }
                    cancelSearch()
                }

                Picker("Game", selection: $selectedGame) {
                    ForEach(FinderGameVersion.games(for: generation)) { g in
                        Text(g.rawValue).tag(g)
                    }
                }

                if generation == .gen3 {
                    gen3Inputs
                } else {
                    if generation == .gen4 {
                        gen4ModeSelector
                    }
                    if generation == .gen4 && gen4Mode == 1 {
                        gen4SearcherInputs
                    } else {
                        gen4GeneratorInputs
                    }
                }

                if generation == .gen3 || !(generation == .gen4 && gen4Mode == 1) {
                    Button {
                        generateIDs()
                    } label: {
                        Label("Generate", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.primaryAction)
                }

                if generation == .gen4 && gen4Mode == 1 {
                    gen4SearchButton
                }

                if generation == .gen3 && !results3.isEmpty {
                    idResults3Section
                }
                if generation != .gen3 && !results4.isEmpty {
                    idResults4Section
                }

                if generation == .gen4 {
                    if let result = selectedResult {
                        seedVerificationSection(for: result)
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        #if os(iOS)
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        #endif
        .onDisappear { cancelSearch() }
        .leaveWarning(gen4Searching ? "The search in progress will stop." : nil)
    }

    @State private var gen3IsGameCube: Bool = false

    private var gen3Inputs: some View {
        SectionCard(title: "Gen 3 ID Generation", icon: "number") {
            Toggle("GameCube (XD/Colo)", isOn: $gen3IsGameCube)

            if gen3IsGameCube {
                HStack {
                    Text("Initial Seed")
                    Spacer()
                    TextField("Hex", text: $gen3SeedText)
                        .textFieldStyle(.roundedBorder).scaledWidth(120)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                }
                Text("XD/Colosseum: Enter seed to generate TID/SID combos")
                    .font(.caption).foregroundStyle(.secondary)
            } else if selectedGame == .ruby || selectedGame == .sapphire {
                HStack {
                    Text("Initial Seed")
                    Spacer()
                    TextField("Hex", text: $gen3SeedText)
                        .textFieldStyle(.roundedBorder).scaledWidth(120)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                }
            } else {
                FinderUInt16Field(label: "TID", value: $gen3TID)
                Text("FRLG/Emerald: Enter your TID to find matching SIDs")
                    .font(.caption).foregroundStyle(.secondary)
            }
            RNGIntField(label: "Initial Advance", value: $gen3InitAdvance, range: RNGFieldRange.advances)
            RNGIntField(label: "Max Advance", value: $gen3MaxAdvance, range: RNGFieldRange.advances)
        }
    }

    // MARK: - Gen 4 Mode Selector

    private var gen4ModeSelector: some View {
        Picker("Mode", selection: $gen4Mode) {
            Text("Generator").tag(0)
            Text("Searcher").tag(1)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: gen4Mode) {
            cancelSearch()
            results4 = []
            selectedResult = nil
        }
    }

    // MARK: - Gen 4 Generator

    private var gen4GeneratorInputs: some View {
        SectionCard(title: "Gen 4 ID Generator", icon: "number") {
            Text("Set the DS date/time and delay range to generate possible TID/SID combinations.")
                .font(.caption).foregroundStyle(.secondary)

            RNGIntField(label: "Min Delay", value: $gen4MinDelay, range: RNGFieldRange.word)
            RNGIntField(label: "Max Delay", value: $gen4MaxDelay, range: RNGFieldRange.word)

            HStack {
                Text("Date")
                Spacer()
                TextField("Y", value: $gen4Year, format: .number.grouping(.never))
                    .clamping($gen4Year, to: 2000...2099)
                    .textFieldStyle(.roundedBorder).scaledWidth(60)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Text("/")
                TextField("M", value: $gen4Month, format: .number.grouping(.never))
                    .clamping($gen4Month, to: 1...12)
                    .textFieldStyle(.roundedBorder).scaledWidth(40)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Text("/")
                TextField("D", value: $gen4Day, format: .number.grouping(.never))
                    .clamping($gen4Day, to: 1...31)
                    .textFieldStyle(.roundedBorder).scaledWidth(40)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }

            HStack {
                Text("Time")
                Spacer()
                TextField("H", value: $gen4Hour, format: .number.grouping(.never))
                    .clamping($gen4Hour, to: 0...23)
                    .textFieldStyle(.roundedBorder).scaledWidth(40)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Text(":")
                TextField("M", value: $gen4Minute, format: .number.grouping(.never))
                    .clamping($gen4Minute, to: 0...59)
                    .textFieldStyle(.roundedBorder).scaledWidth(40)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }

            gen4FilterSection
        }
    }

    // MARK: - Gen 4 Searcher

    private var gen4SearcherInputs: some View {
        SectionCard(title: "Gen 4 ID Searcher", icon: "magnifyingglass") {
            Text("Exhaustively search all possible seeds for a target TID/SID. Set at least one filter to narrow results.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("Year")
                Spacer()
                TextField("", value: $gen4SearchYear, format: .number.grouping(.never))
                    .clamping($gen4SearchYear, to: 2000...2099)
                    .textFieldStyle(.roundedBorder).scaledWidth(100).multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }
            RNGIntField(label: "Min Delay", value: $gen4SearchMinDelay, range: RNGFieldRange.word)
            RNGIntField(label: "Max Delay", value: $gen4SearchMaxDelay, range: RNGFieldRange.word)

            Toggle("Search All Delays", isOn: $gen4SearchInfinite)
            if gen4SearchInfinite {
                Text("Searches all possible delays (can take a long time)")
                    .font(.caption).foregroundStyle(.orange)
            }

            gen4FilterSection
        }
    }

    private var gen4FilterSection: some View {
        Group {
            Toggle("Filter TID", isOn: $gen4FilterTID)
            if gen4FilterTID {
                FinderUInt16Field(label: "Target TID", value: $gen4TargetTID)
            }

            Toggle("Filter SID", isOn: $gen4FilterSID)
            if gen4FilterSID {
                FinderUInt16Field(label: "Target SID", value: $gen4TargetSID)
            }

            Toggle("Filter TSV", isOn: $gen4FilterTSV)
            if gen4FilterTSV {
                FinderUInt16Field(label: "Target TSV", value: $gen4TargetTSV)
            }
        }
    }

    // MARK: - Gen 4 Search Button

    private var gen4SearchButton: some View {
        VStack(spacing: 8) {
            if gen4Searching {
                ProgressView(value: Double(gen4SearchProgress), total: 100)
                    .progressViewStyle(.linear)
                Text("Searching... \(gen4SearchProgress)%")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    cancelSearch()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.primaryAction)
                .tint(.red)
            } else {
                Button {
                    startSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.primaryAction)
            }
        }
    }

    // MARK: - Results

    private var idResults3Section: some View {
        SectionCard(title: "Results (\(results3.count))", icon: "list.bullet") {
            ForEach(results3.prefix(500)) { r in
                HStack {
                    Text("Adv: \(r.advances)")
                        .font(.system(.caption, design: .monospaced))
                    Spacer()
                    Text("TID: \(r.tid)")
                        .font(.system(.caption, design: .monospaced))
                    Text("SID: \(r.sid)")
                        .font(.system(.caption, design: .monospaced))
                    Text("TSV: \(r.tsv)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Divider()
            }
        }
    }

    private var idResults4Section: some View {
        SectionCard(title: "Results (\(results4.count))", icon: "list.bullet") {
            ForEach(results4.prefix(500)) { r in
                Button {
                    selectedResult = (selectedResult?.id == r.id) ? nil : r
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Seed: \(String(format: "%08X", r.seed))")
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text("Delay: \(r.delay)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("TID: \(r.tid)")
                                .font(.system(.caption, design: .monospaced))
                            Text("SID: \(r.sid)")
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text("TSV: \(r.tsv)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if r.seconds > 0 {
                                Text("Sec: \(r.seconds)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .background(selectedResult?.id == r.id ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    // MARK: - Seed Verification

    private func seedVerificationSection(for result: PFBridge.IDResult4) -> some View {
        SectionCard(title: "Seed Verification", icon: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Seed")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%08X", result.seed))
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("TID / SID / TSV")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(result.tid) / \(result.sid) / \(result.tsv)")
                        .font(.system(.body, design: .monospaced))
                }

                Divider()

                let isHGSS = selectedGame == .heartGold || selectedGame == .soulSilver

                Text(isHGSS ? "Elm Responses" : "Coin Flips")
                    .font(.subheadline.weight(.semibold))

                Text(isHGSS
                     ? "Call Professor Elm after selecting your starter to verify your seed. Compare the responses below with what you see in-game."
                     : "Use the coin flip app on the Pokétch to verify your seed. Compare the sequence below with your in-game flips.")
                    .font(.caption).foregroundStyle(.secondary)

                if isHGSS {
                    let calls = PFBridge.getCalls(result.seed, skips: 0)
                    elmCallsDisplay(calls)
                } else {
                    let flips = PFBridge.coinFlips(result.seed)
                    coinFlipDisplay(flips)
                }

                Divider()

                Text("Seed to Time")
                    .font(.subheadline.weight(.semibold))
                Text("Set your DS clock to hit this seed:")
                    .font(.caption).foregroundStyle(.secondary)

                let times = PFBridge.seedToTime4(seed: result.seed,
                                                  year: UInt16(gen4Mode == 0 ? gen4Year : gen4SearchYear))
                if times.isEmpty {
                    Text("No matching date/time found for this seed and year.")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    ForEach(Array(times.prefix(10).enumerated()), id: \.offset) { _, st in
                        HStack {
                            Text(String(format: "%04d/%02d/%02d %02d:%02d:%02d",
                                        st.dateTime.year, st.dateTime.month, st.dateTime.day,
                                        st.dateTime.hour, st.dateTime.minute, st.dateTime.second))
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text("Delay: \(st.delay)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func coinFlipDisplay(_ flips: String) -> some View {
        let items = flips.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return FlowLayout(spacing: 4) {
            ForEach(Array(items.prefix(20).enumerated()), id: \.offset) { _, flip in
                let isHeads = flip == "H"
                Text(flip)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(isHeads ? .orange : .blue)
                    .frame(width: 22, height: 22)
                    .background(isHeads ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                    .clipShape(Circle())
            }
        }
    }

    private func elmCallsDisplay(_ calls: String) -> some View {
        let cleaned = calls.replacingOccurrences(of: "(", with: "")
                           .replacingOccurrences(of: ")", with: "")
                           .replacingOccurrences(of: "skipped", with: "")
        let items = cleaned.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return FlowLayout(spacing: 4) {
            ForEach(Array(items.prefix(20).enumerated()), id: \.offset) { _, call in
                let letter = String(call.prefix(1))
                let color: Color = switch letter {
                case "E": .green
                case "K": .orange
                case "P": .purple
                default: .gray
                }
                Text(letter)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .background(color.opacity(0.15))
                    .clipShape(Circle())
            }
        }
    }

    private struct FlowLayout: Layout {
        var spacing: CGFloat = 4

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let rows = computeRows(proposal: proposal, subviews: subviews)
            var height: CGFloat = 0
            for row in rows {
                height += row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            }
            height += CGFloat(max(0, rows.count - 1)) * spacing
            return CGSize(width: proposal.width ?? 0, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let rows = computeRows(proposal: proposal, subviews: subviews)
            var y = bounds.minY
            for row in rows {
                var x = bounds.minX
                var rowHeight: CGFloat = 0
                for idx in row {
                    let size = subviews[idx].sizeThatFits(.unspecified)
                    subviews[idx].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                    x += size.width + spacing
                    rowHeight = max(rowHeight, size.height)
                }
                y += rowHeight + spacing
            }
        }

        private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[Int]] {
            let maxWidth = proposal.width ?? .infinity
            var rows: [[Int]] = [[]]
            var currentWidth: CGFloat = 0
            for (i, sub) in subviews.enumerated() {
                let size = sub.sizeThatFits(.unspecified)
                if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                    rows.append([])
                    currentWidth = 0
                }
                rows[rows.count - 1].append(i)
                currentWidth += size.width + spacing
            }
            return rows
        }
    }

    // MARK: - Actions

    private func generateIDs() {
        let gen = generation
        let game = selectedGame
        let seedText = gen3SeedText
        let initAdv = UInt32(clamping: gen3InitAdvance)
        let maxAdv = UInt32(clamping: gen3MaxAdvance)
        let tID = gen3TID
        let isGameCube = gen3IsGameCube
        let minDel = UInt32(clamping: gen4MinDelay), maxDel = UInt32(clamping: gen4MaxDelay)
        let yr = UInt16(clamping: gen4Year), mo = UInt8(clamping: gen4Month), dy = UInt8(clamping: gen4Day)
        let hr = UInt8(clamping: gen4Hour), mn = UInt8(clamping: gen4Minute)
        let targetTID = gen4TargetTID, fTID = gen4FilterTID
        let targetSID = gen4TargetSID, fSID = gen4FilterSID

        selectedResult = nil
        searchTask = Task.detached {
            if gen == .gen3 {
                let r: [PFBridge.IDResult]
                if isGameCube {
                    let seed = UInt32(seedText, radix: 16) ?? 0
                    r = PFBridge.idGenerate3XDColo(seed: seed,
                                                     initialAdvances: initAdv,
                                                     maxAdvances: maxAdv)
                } else if game == .ruby || game == .sapphire {
                    let seed = UInt16(seedText, radix: 16) ?? 0
                    r = PFBridge.idGenerate3RS(seed: seed,
                                                initialAdvances: initAdv,
                                                maxAdvances: maxAdv)
                } else {
                    r = PFBridge.idGenerate3FRLGE(tid: tID,
                                                    initialAdvances: initAdv,
                                                    maxAdvances: maxAdv)
                }
                await MainActor.run { results3 = r }
            } else {
                let r = PFBridge.idGenerate4(
                    minDelay: minDel, maxDelay: maxDel,
                    year: yr, month: mo, day: dy,
                    hour: hr, minute: mn,
                    targetTID: targetTID, filterTID: fTID,
                    targetSID: targetSID, filterSID: fSID)
                await MainActor.run { results4 = r }
            }
        }
    }

    private func startSearch() {
        let infinite = gen4SearchInfinite
        let year = UInt16(clamping: gen4SearchYear)
        let minDel = UInt32(clamping: gen4SearchMinDelay)
        let maxDel = UInt32(clamping: gen4SearchMaxDelay)
        let targetTID = gen4TargetTID, fTID = gen4FilterTID
        let targetSID = gen4TargetSID, fSID = gen4FilterSID
        let targetTSV = gen4TargetTSV, fTSV = gen4FilterTSV

        results4 = []
        selectedResult = nil
        gen4Searching = true
        gen4SearchProgress = 0

        let handle = PFBridge.idSearch4Start(
            infinite: infinite, year: year,
            minDelay: minDel, maxDelay: maxDel,
            targetTID: targetTID, filterTID: fTID,
            targetSID: targetSID, filterSID: fSID,
            targetTSV: targetTSV, filterTSV: fTSV)
        gen4SearchHandle = handle

        // Read until the search thread ends (Cancel ends it early), so
        // freeing the handle never waits on it. Once cancelled, the search
        // is no longer the screen's, and its results are dropped.
        searchTask = Task {
            while !PFBridge.idSearch4Done(handle) {
                try? await Task.sleep(for: .milliseconds(250))
                guard gen4SearchHandle == handle else { continue }
                gen4SearchProgress = PFBridge.idSearch4Progress(handle)
                results4.append(contentsOf: PFBridge.idSearch4GetResults(handle))
            }
            if gen4SearchHandle == handle {
                results4.append(contentsOf: PFBridge.idSearch4GetResults(handle))
                gen4SearchProgress = PFBridge.idSearch4Progress(handle)
                gen4SearchHandle = nil
                gen4Searching = false
            }
            PFBridge.idSearch4Free(handle)
        }
    }

    private func cancelSearch() {
        if let handle = gen4SearchHandle {
            PFBridge.idSearch4Cancel(handle)
        }
        gen4SearchHandle = nil
        gen4Searching = false
    }
}
