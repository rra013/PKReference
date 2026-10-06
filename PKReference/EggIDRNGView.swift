import SwiftUI

// MARK: - Parents

/// A parent in the daycare, as PokéFinder's Daycare takes it.
nonisolated struct EggParent: Hashable, Sendable {
    var ivs: [UInt8] = Array(repeating: 31, count: 6)
    /// 0, 1, or 2 for a hidden ability.
    var ability: UInt8 = 0
    /// 0 male, 1 female, 2 genderless, 3 Ditto.
    var gender: UInt8
    /// 0 none, 1 Everstone, 2 to 7 the power items (HP to Speed).
    var item: UInt8 = 0
    /// Passed down with an Everstone.
    var nature: UInt8 = 0

    static let genderNames = ["Male", "Female", "Genderless", "Ditto"]
    static let abilityNames = ["Ability 0", "Ability 1", "Hidden Ability"]
    static let itemNames = ["None", "Everstone", "Power Weight (HP)", "Power Bracer (Atk)", "Power Belt (Def)",
                            "Power Lens (SpA)", "Power Band (SpD)", "Power Anklet (Spe)"]

    /// PokéFinder's check (`EggSettings::isValid`): a male and a female, or
    /// Ditto with a male, a female or a genderless Pokémon.
    static func canBreed(_ a: UInt8, _ b: UInt8) -> Bool {
        switch (min(a, b), max(a, b)) {
        case (0, 1), (0, 3), (1, 3), (2, 3): return true
        default: return false
        }
    }

    static let cannotBreedText = "These two can't breed: pair a male with a female, or Ditto with anything but Ditto."

    /// Which parent gave each IV: "HP:A Atk:R …", A and B for the parents,
    /// R for random.
    static func inheritanceText(_ inheritance: [UInt8]) -> String {
        let labels = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
        return zip(labels, inheritance).map { label, parent in
            switch parent {
            case 1: return "\(label):A"
            case 2: return "\(label):B"
            default: return "\(label):R"
            }
        }.joined(separator: " ")
    }
}

/// What a game's egg generator reads from the parents besides their IVs and
/// gender, so their cards show only that (as PokéFinder's EggSettings
/// does). A parent's nature counts only with an Everstone.
struct EggParentFields: Equatable {
    var abilities: [UInt8] = []
    var items: [UInt8] = []

    init(game: FinderGameVersion) {
        switch game.generation {
        case .gen5:
            abilities = [0, 1, 2]
            items = Array(0...7)
        case .gen3 where game == .emerald:
            items = [0, 1]
        default:
            break
        }
    }

    /// `parent` with what this game doesn't read put back, so it can't
    /// change the eggs unseen.
    func fitting(_ parent: EggParent) -> EggParent {
        var p = parent
        if !abilities.contains(p.ability) { p.ability = 0 }
        if !items.contains(p.item) { p.item = 0 }
        return p
    }
}

/// A parent's IVs and gender and, where the game reads them, its ability,
/// held item and (with an Everstone) nature.
struct EggParentCard: View {
    let label: String
    @Binding var parent: EggParent
    let fields: EggParentFields

    private static let ivNames = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]

    var body: some View {
        SectionCard(title: label, icon: "figure.stand") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    IVField(label: Self.ivNames[i], value: $parent.ivs[i])
                }
            }

            LabeledContent("Gender") {
                Picker("Gender", selection: $parent.gender) {
                    ForEach(EggParent.genderNames.indices, id: \.self) { Text(EggParent.genderNames[$0]).tag(UInt8($0)) }
                }
                .labelsHidden()
            }

            if !fields.abilities.isEmpty {
                LabeledContent("Ability") {
                    Picker("Ability", selection: $parent.ability) {
                        ForEach(fields.abilities, id: \.self) { Text(EggParent.abilityNames[Int($0)]).tag($0) }
                    }
                    .labelsHidden()
                }
            }

            if !fields.items.isEmpty {
                LabeledContent("Held Item") {
                    Picker("Held Item", selection: $parent.item) {
                        ForEach(fields.items, id: \.self) { Text(EggParent.itemNames[Int($0)]).tag($0) }
                    }
                    .labelsHidden()
                }
                if parent.item == 1 {
                    LabeledContent("Nature") {
                        Picker("Nature", selection: $parent.nature) {
                            ForEach(0..<25, id: \.self) { Text(pfNatureNames[$0]).tag(UInt8($0)) }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
    }
}

// MARK: - Egg species

/// The species an egg can be, as PokéFinder lists them (`EggSettings`):
/// each family's first.
enum EggSpecies {
    static let all: [UInt16] = [
        1, 4, 7, 10, 13, 16, 19, 21, 23, 27, 29, 32, 37, 41, 43, 46, 48, 50, 52, 54, 56, 58, 60, 63, 66, 69,
        72, 74, 77, 79, 81, 83, 84, 86, 88, 90, 92, 95, 96, 98, 100, 102, 104, 108, 109, 111, 113, 114, 115, 116, 118, 120,
        122, 123, 127, 128, 129, 131, 133, 137, 138, 140, 142, 143, 147, 152, 155, 158, 161, 163, 165, 167, 170, 172, 173, 174, 175, 177,
        179, 183, 185, 187, 190, 191, 193, 194, 198, 200, 202, 203, 204, 206, 207, 209, 211, 213, 214, 215, 216, 218, 220, 222, 223, 225,
        226, 227, 228, 231, 234, 235, 236, 238, 239, 240, 241, 246, 252, 255, 258, 261, 263, 265, 270, 273, 276, 278, 280, 283, 285, 287,
        290, 292, 293, 296, 298, 299, 300, 302, 303, 304, 307, 309, 311, 312, 313, 314, 315, 316, 318, 320, 322, 324, 325, 327, 328, 331,
        333, 335, 336, 337, 338, 339, 341, 343, 345, 347, 349, 351, 352, 353, 355, 357, 358, 359, 360, 361, 363, 366, 369, 370, 371, 374,
        387, 390, 393, 396, 399, 401, 403, 406, 408, 410, 412, 415, 417, 418, 420, 422, 425, 427, 431, 433, 434, 436, 438, 439, 440, 441,
        442, 443, 446, 447, 449, 451, 453, 455, 456, 458, 459, 479, 489, 495, 498, 501, 504, 506, 509, 511, 513, 515, 517, 519, 522, 524,
        527, 529, 531, 532, 535, 538, 539, 540, 543, 546, 548, 550, 551, 554, 556, 557, 559, 561, 562, 564, 566, 568, 570, 572, 574, 577,
        580, 582, 585, 587, 588, 590, 592, 594, 595, 597, 599, 602, 605, 607, 610, 613, 615, 616, 618, 619, 621, 622, 624, 626, 627, 629,
        631, 632, 633, 636, 650, 653, 656, 659, 661, 664, 667, 669, 672, 674, 676, 677, 679, 682, 684, 686, 688, 690, 692, 694, 696, 698,
        701, 702, 703, 704, 707, 708, 710, 712, 714, 722, 725, 728, 731, 734, 736, 739, 741, 742, 744, 746, 747, 749, 751, 753, 755, 757,
        759, 761, 764, 765, 766, 767, 769, 771, 774, 775, 776, 777, 778, 779, 780, 781, 782,
    ]

    /// The last species in a generation's games: the generators read the
    /// species' gender ratio from a table that ends there.
    static func last(in generation: FinderGeneration) -> UInt16 {
        switch generation {
        case .gen3: return 386
        case .gen4, .gen8: return 493
        case .gen5: return 649
        }
    }

    static func list(for generation: FinderGeneration) -> [UInt16] {
        all.filter { $0 <= last(in: generation) }
    }
}

/// The egg's species, by name.
struct EggSpeciesPicker: View {
    let generation: FinderGeneration
    @Binding var specie: UInt16

    var body: some View {
        LabeledContent("Egg Species") {
            Picker("Egg Species", selection: $specie) {
                ForEach(EggSpecies.list(for: generation), id: \.self) { Text(PFBridge.specieName($0)).tag($0) }
            }
            .labelsHidden()
        }
        .onChange(of: generation, initial: true) {
            if !EggSpecies.list(for: generation).contains(specie) { specie = 1 }
        }
    }
}

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

    // Daycare
    @State private var parentA = EggParent(gender: 0)
    @State private var parentB = EggParent(gender: 1)
    @State private var eggSpecie: UInt16 = 1
    @State private var masuda: Bool = false
    @State private var compatibility: Int = 20

    // Filters
    @State private var selectedNatures: Set<UInt8> = []
    @State private var shinyOnly: Bool = false

    // Results
    @State private var results3: [PFBridge.EggResult3] = []
    @State private var results4: [PFBridge.EggResult4] = []
    @State private var searchTask: Task<Void, Never>?
    /// The last generate ran to the end, for saying it found nothing.
    @State private var finished = false

    /// Gen 8 eggs are the Finder's Egg mode.
    static let generations: [FinderGeneration] = [.gen3, .gen4, .gen5]

    private var parentFields: EggParentFields { EggParentFields(game: selectedGame) }

    /// The filters that are set, for when nothing's found.
    private var setFilterNames: [String] {
        (selectedNatures.isEmpty ? [] : ["natures"]) + (shinyOnly ? ["Shiny Only"] : [])
    }

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

    private var canBreed: Bool { EggParent.canBreed(parentA.gender, parentB.gender) }

    var body: some View {
        ScrollView {
            CardStack {
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

                if generation == .gen5 {
                    Gen5EggView(game: selectedGame, tid: tid, sid: sid)
                } else {
                    gen3And4Inputs
                }
            }
            .padding()
        }
        .dismissesKeyboard()
        #if DEBUG && os(macOS)
        .task { await DebugSnapshot.openSheet("eggs5") { generation = .gen5 } }
        #endif
        // Eggs from another game would read as this one's.
        .onChange(of: ["\(generation)", selectedGame.rawValue]) {
            searchTask?.cancel()
            searchTask = nil
            results3 = []
            results4 = []
            finished = false
            parentA = parentFields.fitting(parentA)
            parentB = parentFields.fitting(parentB)
        }
    }

    @ViewBuilder
    private var gen3And4Inputs: some View {
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

        // Daycare: Gen 3 reads the compatibility, Gen 4 the Masuda method.
        SectionCard(title: "Daycare", icon: "house") {
            if generation == .gen3 {
                Picker("Compatibility", selection: $compatibility) {
                    Text("The two seem to get along (20%)").tag(20)
                    Text("The two seem to get along very well (50%)").tag(50)
                    Text("The two don't seem to like each other (70%)").tag(70)
                }
            } else {
                Toggle("Masuda Method", isOn: $masuda)
            }

            EggSpeciesPicker(generation: generation, specie: $eggSpecie)
        }

        EggParentCard(label: "Parent A", parent: $parentA, fields: parentFields)
        EggParentCard(label: "Parent B", parent: $parentB, fields: parentFields)

        FinderNatureGrid(selected: $selectedNatures)

        Toggle("Shiny Only", isOn: $shinyOnly)
            .padding(.horizontal)

        Button {
            generateEggs()
        } label: {
            Label("Generate", systemImage: "sparkles")
        }
        .buttonStyle(.primaryAction)
        .disabled(tooManyResults || !canBreed)
        if !canBreed {
            Text(EggParent.cannotBreedText)
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if tooManyResults {
            Text("These ranges would list about \(Int(estimatedResults).formatted()) eggs, more than \(Self.resultLimit.formatted()). Narrow the held or pickup advances, or filter by nature or shininess.")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if finished && (generation == .gen3 ? results3.isEmpty : results4.isEmpty) {
            Text(noResultsText(filters: setFilterNames, widen: "the held or pickup advances"))
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
                    Text("Inherit: \(EggParent.inheritanceText(r.inheritance))")
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
                    Text("Inherit: \(EggParent.inheritanceText(r.inheritance))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Divider()
            }
        }
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
        let a = parentFields.fitting(parentA), b = parentFields.fitting(parentB)
        let spec = eggSpecie
        let mas = masuda
        let gameVal = selectedGame.pfGame
        let shiny = shinyOnly
        var natArr = [Bool](repeating: selectedNatures.isEmpty, count: 25)
        for n in selectedNatures { natArr[Int(n)] = true }
        let shinyFilter: UInt8 = pfShinyFilter(shiny)

        let eggMethod: PFMethod = (selectedGame == .emerald) ? .eBred : .rsFRLGBred

        searchTask?.cancel()
        finished = false
        results3 = []
        results4 = []
        searchTask = Task.detached {
            if gen == .gen3 {
                let r = PFBridge.eggGenerate3(
                    seedHeld: seedH, seedPickup: seedP,
                    initialAdvances: initAdv, maxAdvances: maxAdv,
                    initialAdvancesPickup: initAdvP, maxAdvancesPickup: maxAdvP,
                    calibration: cal, minRedraw: minR, maxRedraw: maxR,
                    method: eggMethod, compatibility: compat,
                    parentAIVs: a.ivs, parentBIVs: b.ivs,
                    parentAAbility: a.ability, parentBAbility: b.ability,
                    parentAGender: a.gender, parentBGender: b.gender,
                    parentAItem: a.item, parentBItem: b.item,
                    parentANature: a.nature, parentBNature: b.nature,
                    eggSpecie: spec, masuda: false,
                    tid: tID, sid: sID,
                    game: gameVal,
                    filterShiny: shinyFilter, natures: natArr)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    results3 = r
                    finished = true
                }
            } else {
                let r = PFBridge.eggGenerate4(
                    seedHeld: seedH, seedPickup: seedP,
                    initialAdvances: initAdv, maxAdvances: maxAdv,
                    initialAdvancesPickup: initAdvP, maxAdvancesPickup: maxAdvP,
                    parentAIVs: a.ivs, parentBIVs: b.ivs,
                    parentAAbility: a.ability, parentBAbility: b.ability,
                    parentAGender: a.gender, parentBGender: b.gender,
                    parentAItem: a.item, parentBItem: b.item,
                    parentANature: a.nature, parentBNature: b.nature,
                    eggSpecie: spec, masuda: mas,
                    tid: tID, sid: sID,
                    game: gameVal,
                    filterShiny: shinyFilter, natures: natArr)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    results4 = r
                    finished = true
                }
            }
        }
    }
}

// MARK: - ID RNG View

struct IDRNGView: View {
    /// Gen 3, 4 and 5. Gen 8's IDs are the Finder's TID/SID mode (the same
    /// BDSP generator); its tab ran Gen 4's generator, as Gen 5's did before
    /// it had PokéFinder's IDSearcher5.
    static let generations: [FinderGeneration] = [.gen3, .gen4, .gen5]

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
                    ForEach(Self.generations) { g in Text(g.rawValue).tag(g) }
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

                if generation == .gen5 {
                    Gen5IDView(game: selectedGame)
                } else if generation == .gen3 {
                    gen3Inputs
                } else {
                    gen4ModeSelector
                    if gen4Mode == 1 {
                        gen4SearcherInputs
                    } else {
                        gen4GeneratorInputs
                    }
                }

                if generation == .gen3 || (generation == .gen4 && gen4Mode == 0) {
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

                if finished && generation != .gen5 && (generation == .gen3 ? results3.isEmpty : results4.isEmpty) {
                    Text(noResultsText(filters: setFilterNames, widen: generation == .gen3 ? "the advances" : "the delays"))
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if generation == .gen3 && !results3.isEmpty {
                    idResults3Section
                }
                if generation == .gen4 && !results4.isEmpty {
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
        .dismissesKeyboard()
        .onDisappear { cancelSearch() }
        // IDs from another game or mode would read as this one's.
        .onChange(of: ["\(generation)", selectedGame.rawValue, "\(gen4Mode)"]) {
            cancelSearch()
            searchTask?.cancel()
            searchTask = nil
            results3 = []
            results4 = []
            selectedResult = nil
            finished = false
        }
        .leaveWarning(gen4Searching ? "The search in progress will stop." : nil)
    }

    @State private var gen3IsGameCube: Bool = false
    /// The last generate or search ran to the end, for saying it found
    /// nothing.
    @State private var finished = false

    /// Gen 4's filters that are set, for when nothing's found (Gen 3 lists
    /// every ID).
    private var setFilterNames: [String] {
        guard generation == .gen4 else { return [] }
        return [("TID", gen4FilterTID), ("SID", gen4FilterSID), ("TSV", gen4FilterTSV)]
            .filter(\.1).map(\.0)
    }

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
            Text("Set the DS date/time and delay range to generate possible TID/SID combinations. The delays are the ones to hit on a DS set to that year.")
                .font(.caption).foregroundStyle(.secondary)

            RNGIntField(label: "Min Delay", value: $gen4MinDelay, range: RNGFieldRange.word)
            RNGIntField(label: "Max Delay", value: $gen4MaxDelay, range: RNGFieldRange.word)

            HStack {
                Text("Date")
                Spacer()
                LiveIntField("Y", value: $gen4Year, range: 2000...2099, grouping: false)
                    .clamping($gen4Year, to: 2000...2099)
                    .textFieldStyle(.roundedBorder).scaledWidth(60)
                Text("/")
                LiveIntField("M", value: $gen4Month, range: 1...12, grouping: false)
                    .clamping($gen4Month, to: 1...12)
                    .textFieldStyle(.roundedBorder).scaledWidth(40)
                Text("/")
                LiveIntField("D", value: $gen4Day, range: 1...31, grouping: false)
                    .clamping($gen4Day, to: 1...31)
                    .textFieldStyle(.roundedBorder).scaledWidth(40)
            }

            HStack {
                Text("Time")
                Spacer()
                LiveIntField("H", value: $gen4Hour, range: 0...23, grouping: false)
                    .clamping($gen4Hour, to: 0...23)
                    .textFieldStyle(.roundedBorder).scaledWidth(40)
                Text(":")
                LiveIntField("M", value: $gen4Minute, range: 0...59, grouping: false)
                    .clamping($gen4Minute, to: 0...59)
                    .textFieldStyle(.roundedBorder).scaledWidth(40)
            }

            gen4FilterSection
        }
    }

    // MARK: - Gen 4 Searcher

    private var gen4SearcherInputs: some View {
        SectionCard(title: "Gen 4 ID Searcher", icon: "magnifyingglass") {
            Text("Exhaustively search all possible seeds for a target TID/SID. Set at least one filter to narrow results. The delays are the ones to hit on a DS set to the year.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("Year")
                Spacer()
                LiveIntField("", value: $gen4SearchYear, range: 2000...2099, grouping: false)
                    .clamping($gen4SearchYear, to: 2000...2099)
                    .textFieldStyle(.roundedBorder).scaledWidth(100).multilineTextAlignment(.trailing)
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
        let targetTSV = gen4TargetTSV, fTSV = gen4FilterTSV

        selectedResult = nil
        searchTask?.cancel()
        finished = false
        results3 = []
        results4 = []
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
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    results3 = r
                    finished = true
                }
            } else {
                let r = PFBridge.idGenerate4(
                    minDelay: minDel, maxDelay: maxDel,
                    year: yr, month: mo, day: dy,
                    hour: hr, minute: mn,
                    targetTID: targetTID, filterTID: fTID,
                    targetSID: targetSID, filterSID: fSID,
                    targetTSV: targetTSV, filterTSV: fTSV)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    results4 = r
                    finished = true
                }
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
        finished = false
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
                finished = true
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

// MARK: - Gen 5 IDs

/// Black, White, Black 2 and White 2's IDs, with the DS's parameters:
/// PokéFinder's IDSearcher5 over dates, or its seed finder from the TID you
/// got (its IDs5 screen).
struct Gen5IDView: View {
    let game: FinderGameVersion

    enum Mode: String, CaseIterable, Identifiable {
        case search = "Search"
        case find = "Find My Seed"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .search
    @State private var startDate = Gen5IDView.date(2000, 1, 1)
    @State private var endDate = Gen5IDView.date(2000, 1, 1)
    @State private var maxAdvances = 100
    @State private var filterTID = false
    @State private var targetTID: UInt16 = 0
    @State private var filterSID = false
    @State private var targetSID: UInt16 = 0
    @State private var shinyPID = false
    @State private var pidText = ""
    @State private var wildPID = false

    @State private var findTID: UInt16 = 0
    @State private var findDate = Date()
    @State private var findHour = 0
    @State private var findMinute = 0
    @State private var findMinSecond = 0
    @State private var findMaxSecond = 59
    @State private var findMaxAdvances = 100

    @State private var results: [PFBridge.IDSearchResult5] = []
    @State private var handle: OpaquePointer?
    @State private var searchTask: Task<Void, Never>?
    @State private var progress = 0
    @State private var finished = false

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    static func parts(_ date: Date) -> (year: UInt16, month: UInt8, day: UInt8) {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return (UInt16(clamping: c.year ?? 2000), UInt8(clamping: c.month ?? 1), UInt8(clamping: c.day ?? 1))
    }

    private var parameters: Gen5DSParameters { Gen5DSParametersCard.stored() }

    var body: some View {
        Gen5DSParametersCard(game: game, showsProfiles: true)

        Picker("Mode", selection: $mode) {
            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: mode) { clear() }
        .onChange(of: game) { clear() }

        if mode == .search {
            SectionCard(title: "Gen 5 ID Search", icon: "magnifyingglass") {
                Text("Every second of the dates, with your DS's parameters and keypresses. Set a filter: without one, every ID matches.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                RNGIntField(label: "Max Advances", value: $maxAdvances, range: RNGFieldRange.advances)
                Toggle("Filter TID", isOn: $filterTID)
                if filterTID { FinderUInt16Field(label: "Target TID", value: $targetTID) }
                Toggle("Filter SID", isOn: $filterSID)
                if filterSID { FinderUInt16Field(label: "Target SID", value: $targetSID) }
                Toggle("Shiny for a PID", isOn: $shinyPID)
                if shinyPID {
                    HStack {
                        Text("PID (hex)")
                        Spacer()
                        TextField("00000000", text: $pidText)
                            .textFieldStyle(.roundedBorder).scaledWidth(120).multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            #endif
                            .hexDigitsOnly($pidText, count: 8)
                    }
                    Toggle("A Wild or Stationary Pokémon", isOn: $wildPID)
                    Text("Their PIDs' top bit follows the IDs, so fewer IDs make one shiny.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            searchButton
        } else {
            SectionCard(title: "Find My Seed", icon: "scope") {
                Text("The TID you got, and the minute you started the game in.")
                    .font(.caption).foregroundStyle(.secondary)
                FinderUInt16Field(label: "TID", value: $findTID)
                DatePicker("Date", selection: $findDate, displayedComponents: .date)
                HStack {
                    Text("Time")
                    Spacer()
                    LiveIntField("H", value: $findHour, range: 0...23, grouping: false)
                        .clamping($findHour, to: 0...23)
                        .textFieldStyle(.roundedBorder).scaledWidth(44)
                    Text(":")
                    LiveIntField("M", value: $findMinute, range: 0...59, grouping: false)
                        .clamping($findMinute, to: 0...59)
                        .textFieldStyle(.roundedBorder).scaledWidth(44)
                }
                RNGIntField(label: "Seconds From", value: $findMinSecond, range: 0...59)
                RNGIntField(label: "Seconds To", value: $findMaxSecond, range: 0...59)
                RNGIntField(label: "Max Advances", value: $findMaxAdvances, range: RNGFieldRange.advances)
            }
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            Button {
                find()
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
            .buttonStyle(.primaryAction)
            .disabled(blockedReason != nil || searchTask != nil)
        }

        if let blockedReason {
            Text(blockedReason)
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if finished && results.isEmpty {
            Text(mode == .search ? "Nothing found. Widen the dates or the advances, or loosen a filter."
                                 : "Nothing found. Check the TID, date and minute, and your DS's parameters, or widen the seconds or the advances.")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !results.isEmpty {
            SectionCard(title: "Results (\(results.count))", icon: "list.bullet") {
                Text("Tap one to send it to the Timer: set your DS's clock to its minute, then press Continue on its second.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(results.prefix(500)) { r in
                    Button {
                        Self.sendToTimer(r)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(r.dateTimeText).font(.system(.caption, design: .monospaced))
                                Spacer()
                                Text("Adv: \(r.advances)").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("TID: \(r.tid)").font(.system(.caption, design: .monospaced))
                                Text("SID: \(r.sid)").font(.system(.caption, design: .monospaced))
                                Spacer()
                                Text("TSV: \(r.tsv)").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Text(String(format: "Seed %016llX  Timer0 %X  ", r.seed, r.timer0) + Gen5Buttons.describe(r.buttons))
                                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    /// Why Search or Find is off.
    private var blockedReason: String? {
        if parameters.isUnset { return "Set your DS's parameters first: Find My Parameters above." }
        if mode == .search && startDate > endDate { return "The start date is after the end date." }
        if mode == .search && shinyPID && UInt32(pidText, radix: 16) == nil { return "Enter the PID, in hex." }
        if mode == .find && findMinSecond > findMaxSecond { return "The seconds are the wrong way round." }
        return nil
    }

    private var searchButton: some View {
        VStack(spacing: 8) {
            if searchTask != nil {
                ProgressView(value: Double(progress), total: 100)
                    .progressViewStyle(.linear)
                Text("\(progress)% — \(results.count) found")
                    .font(.caption).foregroundStyle(.secondary)
                Button { stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.primaryAction)
                    .tint(.red)
            } else {
                Button { search() } label: { Label("Search", systemImage: "magnifyingglass") }
                    .buttonStyle(.primaryAction)
                    .disabled(blockedReason != nil)
                if results.count >= searchResultLimit {
                    Text(searchResultLimitNote)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func clear() {
        stop()
        results = []
        finished = false
    }

    private func search() {
        stop()
        results = []
        finished = false
        progress = 0
        guard let h = PFBridge.idSearch5Start(
            game: game.pfGame, profile: parameters, start: Self.parts(startDate), end: Self.parts(endDate),
            maxAdvances: UInt32(clamping: maxAdvances),
            pid: UInt32(pidText, radix: 16) ?? 0, checkPID: shinyPID, checkXOR: shinyPID && wildPID,
            tid: targetTID, filterTID: filterTID, sid: targetSID, filterSID: filterSID) else { return }
        handle = h
        searchTask = Task {
            while !PFBridge.idSearch5Done(h) {
                try? await Task.sleep(for: .milliseconds(250))
                guard handle == h else { break }
                progress = PFBridge.idSearch5Progress(h)
                // At most searchResultLimit, as every RNG search keeps.
                results.append(contentsOf: PFBridge.idSearch5Results(h).prefix(max(0, searchResultLimit - results.count)))
                if results.count >= searchResultLimit { PFBridge.idSearch5Cancel(h) }
            }
            if handle == h {
                results.append(contentsOf: PFBridge.idSearch5Results(h).prefix(max(0, searchResultLimit - results.count)))
                progress = PFBridge.idSearch5Progress(h)
                finished = true
                handle = nil
                searchTask = nil
            }
            await Task.detached { PFBridge.idSearch5Free(h) }.value
        }
    }

    private func find() {
        stop()
        results = []
        finished = false
        let date = Self.parts(findDate)
        let params = parameters
        let gameVal = game.pfGame
        let tid = findTID, hour = UInt8(clamping: findHour), minute = UInt8(clamping: findMinute)
        let seconds = UInt8(clamping: findMinSecond)...UInt8(clamping: findMaxSecond)
        let maxAdv = UInt32(clamping: findMaxAdvances)
        searchTask = Task {
            let found = await Task.detached {
                PFBridge.idFind5(game: gameVal, profile: params, tid: tid, year: date.year, month: date.month,
                                 day: date.day, hour: hour, minute: minute, seconds: seconds, maxAdvances: maxAdv)
            }.value
            results = found
            finished = true
            searchTask = nil
        }
    }

    private func stop() {
        if let handle { PFBridge.idSearch5Cancel(handle) }
        handle = nil
        searchTask = nil
    }

    /// The Gen 5 Timer's Standard mode: the result's second, after setting
    /// the DS's clock to its minute.
    static func sendToTimer(_ r: PFBridge.IDSearchResult5) {
        sendToTimer(second: r.second, dateTimeText: r.dateTimeText, buttons: r.buttons, seed: r.seed)
    }

    /// Any Gen 5 search result: its second, and its time, buttons and seed
    /// to show.
    static func sendToTimer(second: Int, dateTimeText: String, buttons: UInt16, seed: UInt64) {
        let bridge = FinderTimerBridge.shared
        bridge.pendingGen = .gen5
        bridge.pendingTargetSecond = second
        bridge.selectedTime = dateTimeText + (buttons == 0 ? "" : ", holding \(Gen5Buttons.describe(buttons))")
        bridge.selectedSeed = String(format: "%016llX", seed)
        bridge.shouldSwitchToTimer = true
    }
}
