//
//  Gen5Eggs.swift
//  PKReference
//
//  Black, White, Black 2 and White 2's eggs: PokéFinder's EggGenerator5
//  from a seed, and its egg searcher over dates with the DS's parameters
//  (its Eggs5 screen). Black and White work out each advance's egg; Black 2
//  and White 2 make the egg's IVs, nature and ability from the seed, and
//  only its PID from the advance.
//

import SwiftUI

// MARK: - Daycare

/// The daycare as PokéFinder's Gen 5 egg tools take it.
nonisolated struct Gen5Daycare: Hashable, Sendable {
    var parentA: EggParent
    var parentB: EggParent
    var specie: UInt16
    var masuda: Bool

    /// The game holds the female, or else Ditto, second; PokéFinder swaps
    /// the parents to match (`EggSettings::reorderParents`).
    var isReversed: Bool {
        switch (parentA.gender, parentB.gender) {
        case (1, 0), (1, 3), (3, 0), (3, 2): return true
        default: return false
        }
    }

    /// The parents in the game's order.
    var pf: PFDaycare {
        let (first, second) = isReversed ? (parentB, parentA) : (parentA, parentB)
        func six(_ v: [UInt8]) -> (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) { (v[0], v[1], v[2], v[3], v[4], v[5]) }
        return PFDaycare(parentAIVs: six(first.ivs), parentBIVs: six(second.ivs),
                         abilities: (first.ability, second.ability), genders: (first.gender, second.gender),
                         items: (first.item, second.item), natures: (first.nature, second.nature),
                         specie: specie, masuda: masuda)
    }

    /// Which of your parents gave each IV (1 Parent A, 2 Parent B), from
    /// the game's order.
    func yourParents(_ inheritance: [UInt8]) -> [UInt8] {
        guard isReversed else { return inheritance }
        return inheritance.map { $0 == 1 ? 2 : $0 == 2 ? 1 : $0 }
    }

    /// Why these parents can't make what's asked (PokéFinder's
    /// `EggSettings::isValid`): only a female passes down her hidden
    /// ability, and only with a male.
    func blockedReason(hiddenAbility: Bool) -> String? {
        guard EggParent.canBreed(parentA.gender, parentB.gender) else { return EggParent.cannotBreedText }
        if hiddenAbility {
            let female = parentA.gender == 1 ? parentA : parentB.gender == 1 ? parentB : nil
            let male = parentA.gender == 0 || parentB.gender == 0
            if female?.ability != 2 || !male {
                return "Only a female with her hidden ability passes it down, bred with a male: set her ability to Hidden Ability, or the filter to another."
            }
        }
        return nil
    }
}

/// What the eggs are filtered by.
nonisolated struct Gen5EggFilter: Hashable, Sendable {
    var ivMin: [UInt8] = Array(repeating: 0, count: 6)
    var ivMax: [UInt8] = Array(repeating: 31, count: 6)
    var natures: Set<UInt8> = []
    var hiddenPowers: Set<UInt8> = []
    /// 255 any, or 0, 1, 2 for a hidden ability.
    var ability: UInt8 = 255
    /// 255 any, 0 male, 1 female.
    var gender: UInt8 = 255
    var shinyOnly = false

    var natureFlags: [Bool] { (0..<25).map { natures.contains(UInt8($0)) } }
    var hiddenPowerFlags: [Bool] { (0..<16).map { hiddenPowers.contains(UInt8($0)) } }

    /// The filters that are set, for when nothing's found.
    var setNames: [String] {
        var names: [String] = []
        if ivMin.contains(where: { $0 > 0 }) || ivMax.contains(where: { $0 < 31 }) { names.append("IV ranges") }
        if !natures.isEmpty { names.append("natures") }
        if !hiddenPowers.isEmpty { names.append("Hidden Power") }
        if ability != 255 { names.append("ability") }
        if gender != 255 { names.append("gender") }
        if shinyOnly { names.append("Shiny Only") }
        return names
    }
}

// MARK: - Bridge

nonisolated extension PFBridge {
    struct EggResult5: Hashable, Sendable {
        let advances: UInt32
        let pid: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        /// 0, 1, or 2 for a hidden ability.
        let ability: UInt8
        let gender: UInt8
        let shiny: UInt8
        let hiddenPower: UInt8
        /// Which of your parents gave each IV: 0 neither, 1 Parent A, 2
        /// Parent B.
        let inheritance: [UInt8]
        /// Chatot's pitch, 0 to 99, for finding where you are.
        let chatot: UInt8

        init(_ r: PFEggGeneratorState5, daycare: Gen5Daycare) {
            advances = r.advances
            pid = r.pid
            ivs = [r.ivs.0, r.ivs.1, r.ivs.2, r.ivs.3, r.ivs.4, r.ivs.5]
            nature = r.nature
            ability = r.ability
            gender = r.gender
            shiny = r.shiny
            hiddenPower = r.hiddenPower
            inheritance = daycare.yourParents([r.inheritance.0, r.inheritance.1, r.inheritance.2,
                                               r.inheritance.3, r.inheritance.4, r.inheritance.5])
            chatot = r.chatot
        }
    }

    struct EggSearchResult5: Identifiable, Hashable, Sendable {
        var id: String { "\(seed)-\(timer0)-\(buttons)-\(egg.advances)" }
        let year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int
        let seed: UInt64
        let timer0: UInt16
        let buttons: UInt16
        let egg: EggResult5

        var dateTimeText: String {
            String(format: "%04d/%02d/%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
        }
    }

    /// PokéFinder's EggGenerator5 from one seed.
    static func eggGenerate5(seed: UInt64, initialAdvances: UInt32, maxAdvances: UInt32,
                             game: PFGame, tid: UInt16, sid: UInt16, profile: Gen5DSParameters,
                             daycare: Gen5Daycare, filter: Gen5EggFilter) -> [EggResult5] {
        var p = profile.pf
        var d = daycare.pf
        var count: Int32 = 0
        guard let ptr = pf_eggGenerate5(seed, initialAdvances, maxAdvances, 0, game.rawValue, tid, sid, &p, &d,
                                        filter.gender, filter.ability, pfShinyFilter(filter.shinyOnly),
                                        filter.ivMin, filter.ivMax, filter.natureFlags, filter.hiddenPowerFlags,
                                        &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { EggResult5(ptr[$0], daycare: daycare) }
    }

    /// Gen 5 eggs over every second of the dates: nil when the dates or the
    /// profile's Timer0 range are the wrong way round.
    static func eggSearch5Start(game: PFGame, tid: UInt16, sid: UInt16, profile: Gen5DSParameters,
                                daycare: Gen5Daycare,
                                start: (year: UInt16, month: UInt8, day: UInt8),
                                end: (year: UInt16, month: UInt8, day: UInt8),
                                initialAdvances: UInt32, maxAdvances: UInt32,
                                filter: Gen5EggFilter) -> OpaquePointer? {
        var p = profile.pf
        var d = daycare.pf
        return pf_eggSearch5_start(game.rawValue, tid, sid, &p, &d,
                                   start.year, start.month, start.day, end.year, end.month, end.day,
                                   initialAdvances, maxAdvances,
                                   filter.gender, filter.ability, pfShinyFilter(filter.shinyOnly),
                                   filter.ivMin, filter.ivMax, filter.natureFlags, filter.hiddenPowerFlags)
            .map(OpaquePointer.init)
    }

    static func eggSearch5Progress(_ handle: OpaquePointer) -> Int {
        Int(pf_eggSearch5_progress(UnsafeMutableRawPointer(handle)))
    }

    static func eggSearch5Done(_ handle: OpaquePointer) -> Bool {
        pf_eggSearch5_done(UnsafeMutableRawPointer(handle))
    }

    /// The results found since the last call.
    static func eggSearch5Results(_ handle: OpaquePointer, daycare: Gen5Daycare) -> [EggSearchResult5] {
        var count: Int32 = 0
        guard let ptr = pf_eggSearch5_getResults(UnsafeMutableRawPointer(handle), &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return EggSearchResult5(year: Int(r.dateTime.year), month: Int(r.dateTime.month), day: Int(r.dateTime.day),
                                    hour: Int(r.dateTime.hour), minute: Int(r.dateTime.minute),
                                    second: Int(r.dateTime.second),
                                    seed: r.seed, timer0: r.timer0, buttons: r.buttons,
                                    egg: EggResult5(r.egg, daycare: daycare))
        }
    }

    static func eggSearch5Cancel(_ handle: OpaquePointer) {
        pf_eggSearch5_cancel(UnsafeMutableRawPointer(handle))
    }

    static func eggSearch5Free(_ handle: OpaquePointer) {
        pf_eggSearch5_free(UnsafeMutableRawPointer(handle))
    }
}

// MARK: - View

/// The Eggs tool's Gen 5 tab, under its Trainer card: the DS's parameters,
/// the daycare, and PokéFinder's egg searcher or generator.
struct Gen5EggView: View {
    let game: FinderGameVersion
    let tid: UInt16
    let sid: UInt16

    enum Mode: String, CaseIterable, Identifiable {
        case searcher = "Searcher"
        case generator = "Generator"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .searcher
    @State private var startDate = Gen5IDView.date(2000, 1, 1)
    @State private var endDate = Gen5IDView.date(2000, 1, 1)
    @State private var seedText = ""
    // PokéFinder's defaults: 100 advances searched, 1,000 generated.
    @State private var searchInitialAdvances = 0
    @State private var searchMaxAdvances = 100
    @State private var initialAdvances = 0
    @State private var maxAdvances = 1000

    @State private var parentA = EggParent(gender: 0)
    @State private var parentB = EggParent(gender: 1)
    @State private var specie: UInt16 = 1
    @State private var masuda = false
    @State private var filter = Gen5EggFilter()

    @State private var generated: [PFBridge.EggResult5] = []
    @State private var searched: [PFBridge.EggSearchResult5] = []
    @State private var handle: OpaquePointer?
    @State private var searchTask: Task<Void, Never>?
    @State private var progress = 0
    @State private var finished = false

    private static let ivNames = ["HP", "Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed"]

    private var parameters: Gen5DSParameters { Gen5DSParametersCard.stored() }

    private var daycare: Gen5Daycare {
        let fields = EggParentFields(game: game)
        return Gen5Daycare(parentA: fields.fitting(parentA), parentB: fields.fitting(parentB),
                           specie: specie, masuda: masuda)
    }

    private var resultCount: Int { mode == .searcher ? searched.count : generated.count }

    var body: some View {
        Gen5DSParametersCard(game: game, showsProfiles: true)

        Picker("Mode", selection: $mode) {
            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: mode) { clear() }
        .onChange(of: game) { clear() }
        // Another generation's tab, or another tool: nothing shows the search.
        .onDisappear { stop() }

        if mode == .searcher {
            SectionCard(title: "Egg Search", icon: "magnifyingglass") {
                Text("Every second of the dates, with your DS's parameters and keypresses. Set the IVs, nature, ability or shininess you want: without a filter, every egg matches.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                RNGIntField(label: "Initial Advance", value: $searchInitialAdvances, range: RNGFieldRange.advances)
                RNGIntField(label: "Max Advances", value: $searchMaxAdvances, range: RNGFieldRange.advances)
            }
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        } else {
            SectionCard(title: "Seed", icon: "number") {
                HStack {
                    Text("Seed (hex)")
                    Spacer()
                    TextField("0000000000000000", text: $seedText)
                        .textFieldStyle(.roundedBorder).scaledWidth(200).multilineTextAlignment(.trailing)
                        .font(.body.monospacedDigit())
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .hexDigitsOnly($seedText, count: 16)
                }
                RNGIntField(label: "Initial Advance", value: $initialAdvances, range: RNGFieldRange.advances)
                RNGIntField(label: "Max Advances", value: $maxAdvances, range: RNGFieldRange.advances)
            }
        }

        SectionCard(title: "Daycare", icon: "house") {
            Toggle("Masuda Method", isOn: $masuda)
            EggSpeciesPicker(generation: .gen5, specie: $specie)
        }

        EggParentCard(label: "Parent A", parent: $parentA, fields: EggParentFields(game: game))
        EggParentCard(label: "Parent B", parent: $parentB, fields: EggParentFields(game: game))

        SectionCard(title: "IV Ranges", icon: "number.square") {
            ForEach(0..<6, id: \.self) { i in
                FinderIVRangeRow(label: Self.ivNames[i], min: $filter.ivMin[i], max: $filter.ivMax[i])
            }
        }

        FinderNatureGrid(selected: $filter.natures)

        SectionCard(title: "Filters", icon: "line.3.horizontal.decrease.circle") {
            Toggle("Shiny Only", isOn: $filter.shinyOnly)
            LabeledContent("Gender") {
                Picker("Gender", selection: $filter.gender) {
                    Text("Any").tag(UInt8(255))
                    Text("Male").tag(UInt8(0))
                    Text("Female").tag(UInt8(1))
                }
                .labelsHidden()
            }
            LabeledContent("Ability") {
                Picker("Ability", selection: $filter.ability) {
                    Text("Any").tag(UInt8(255))
                    ForEach(EggParent.abilityNames.indices, id: \.self) { Text(EggParent.abilityNames[$0]).tag(UInt8($0)) }
                }
                .labelsHidden()
            }
            FinderHiddenPowerGrid(selected: $filter.hiddenPowers)
        }

        actionButton

        if let blockedReason {
            Text(blockedReason)
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if finished && resultCount == 0 {
            Text(noResultsText(filters: filter.setNames,
                               widen: mode == .searcher ? "the dates or the advances" : "the advances"))
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if mode == .searcher && !searched.isEmpty {
            searchResults
        }
        if mode == .generator && !generated.isEmpty {
            SectionCard(title: "Results (\(generated.count))", icon: "list.bullet") {
                ForEach(generated.prefix(500), id: \.self) { egg in
                    eggRow(egg)
                    Divider()
                }
            }
        }
    }

    /// Why Search or Generate is off.
    private var blockedReason: String? {
        if mode == .searcher && parameters.isUnset { return "Set your DS's parameters first: Find My Parameters above." }
        if mode == .searcher && startDate > endDate { return "The start date is after the end date." }
        if mode == .generator && UInt64(seedText, radix: 16) == nil { return "Enter the seed, in hex." }
        return daycare.blockedReason(hiddenAbility: filter.ability == 2)
    }

    private var actionButton: some View {
        VStack(spacing: 8) {
            if searchTask != nil {
                if mode == .searcher {
                    ProgressView(value: Double(progress), total: 100)
                        .progressViewStyle(.linear)
                    Text("\(progress)% — \(searched.count) found")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
                Button { stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.primaryAction)
                    .tint(.red)
            } else {
                Button {
                    if mode == .searcher { search() } else { generate() }
                } label: {
                    Label(mode == .searcher ? "Search" : "Generate",
                          systemImage: mode == .searcher ? "magnifyingglass" : "sparkles")
                }
                .buttonStyle(.primaryAction)
                .disabled(blockedReason != nil)
                if resultCount >= searchResultLimit {
                    Text(searchResultLimitNote)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var searchResults: some View {
        SectionCard(title: "Results (\(searched.count))", icon: "list.bullet") {
            Text("Tap one to send it to the Timer: set your DS's clock to its minute, then press Continue on its second. Advance to its advance before you take the egg; Chatot's pitch shows where you are.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(searched.prefix(500)) { r in
                Button {
                    Self.sendToTimer(r)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.dateTimeText).font(.system(.caption, design: .monospaced))
                        Text(String(format: "Seed %016llX  Timer0 %X  ", r.seed, r.timer0) + Gen5Buttons.describe(r.buttons))
                            .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                        eggRow(r.egg)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    private func eggRow(_ egg: PFBridge.EggResult5) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Adv: \(egg.advances)").font(.system(.caption, design: .monospaced))
                Spacer()
                Text("Chatot: \(chatotPitchText(egg.chatot))")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack {
                Text("PID: \(String(format: "%08X", egg.pid))")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text(pfNatureNames[Int(egg.nature)]).font(.caption2).bold()
                Text(egg.ability == 2 ? "H" : "\(egg.ability)").font(.caption2)
                Text(egg.gender == 0 ? "♂" : egg.gender == 1 ? "♀" : "-").font(.caption2)
                if egg.shiny > 0 {
                    Image(systemName: "star.fill")
                        .font(.caption2).foregroundStyle(.yellow)
                        .accessibilityLabel("Shiny")
                }
            }
            Text("IVs: \(egg.ivs.map(String.init).joined(separator: "/"))  HP: \(hiddenPowerTypes[Int(egg.hiddenPower) % hiddenPowerTypes.count])")
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            Text("Inherit: \(EggParent.inheritanceText(egg.inheritance))")
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
        }
    }

    private func clear() {
        stop()
        generated = []
        searched = []
        finished = false
    }

    private func search() {
        stop()
        searched = []
        finished = false
        progress = 0
        let daycare = daycare
        guard let h = PFBridge.eggSearch5Start(
            game: game.pfGame, tid: tid, sid: sid, profile: parameters, daycare: daycare,
            start: Gen5IDView.parts(startDate), end: Gen5IDView.parts(endDate),
            initialAdvances: UInt32(clamping: searchInitialAdvances), maxAdvances: UInt32(clamping: searchMaxAdvances),
            filter: filter) else { return }
        handle = h
        searchTask = Task {
            while !PFBridge.eggSearch5Done(h) {
                try? await Task.sleep(for: .milliseconds(250))
                guard handle == h else { break }
                progress = PFBridge.eggSearch5Progress(h)
                // At most searchResultLimit, as every RNG search keeps.
                if appendUpToLimit(PFBridge.eggSearch5Results(h, daycare: daycare), to: &searched) {
                    PFBridge.eggSearch5Cancel(h)
                }
            }
            if handle == h {
                _ = appendUpToLimit(PFBridge.eggSearch5Results(h, daycare: daycare), to: &searched)
                progress = PFBridge.eggSearch5Progress(h)
                finished = true
                handle = nil
                searchTask = nil
            }
            await Task.detached { PFBridge.eggSearch5Free(h) }.value
        }
    }

    private func generate() {
        stop()
        generated = []
        finished = false
        let seed = UInt64(seedText, radix: 16) ?? 0
        let gameVal = game.pfGame, tid = tid, sid = sid
        let params = parameters, daycare = daycare, filter = filter
        let initial = UInt32(clamping: initialAdvances), max = UInt32(clamping: maxAdvances)
        searchTask = Task.detached {
            // A chunk at a time, as the Finder's generators run: every
            // advance can be an egg.
            var eggs: [PFBridge.EggResult5] = []
            generateInChunks(initialAdvance: initial, maxAdvance: max) { start, count in
                let chunk = PFBridge.eggGenerate5(seed: seed, initialAdvances: start, maxAdvances: count,
                                                  game: gameVal, tid: tid, sid: sid, profile: params,
                                                  daycare: daycare, filter: filter)
                _ = appendUpToLimit(chunk, to: &eggs)
                return chunk.count
            }
            let found = eggs
            await MainActor.run {
                guard !Task.isCancelled else { return }
                generated = found
                finished = true
                searchTask = nil
            }
        }
    }

    private func stop() {
        if let handle { PFBridge.eggSearch5Cancel(handle) }
        handle = nil
        searchTask?.cancel()
        searchTask = nil
    }

    /// The Gen 5 Timer's Standard mode: the result's second, after setting
    /// the DS's clock to its minute.
    static func sendToTimer(_ r: PFBridge.EggSearchResult5) {
        Gen5IDView.sendToTimer(second: r.second, dateTimeText: r.dateTimeText, buttons: r.buttons, seed: r.seed)
    }
}
