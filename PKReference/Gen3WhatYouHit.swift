//
//  Gen3WhatYouHit.swift
//  PKReference
//
//  Which Gen 3 frame you hit, from what you caught: the frames near the
//  target, from the seed the game started on, that make that Pokémon (as
//  RNG Reporter is used for it). And the seed itself, when it's only known
//  from the game: a new game's seed is the Trainer ID, and a caught
//  Pokémon's IVs lead back to it (IV→PID, then the 16-bit seed before it).
//  FireRed and LeafGreen's farmed seeds have their own Calibrate.
//

import SwiftUI

nonisolated enum Gen3HitSearch {
    /// A frame that makes what was caught.
    struct Hit: Identifiable, Hashable, Sendable {
        let frame: UInt32
        /// Frames from the target: late is positive.
        let offset: Int
        let pid: UInt32
        let ivs: [UInt8]
        let nature: UInt8
        let gender: UInt8
        let shiny: UInt8
        var id: UInt32 { frame }
    }

    /// The frames within `framesEitherSide` of `targetFrame`, counted from
    /// `initialSeed`, whose Pokémon matches `caught`, nearest first. With the
    /// encounter's template, gender follows its species; without one,
    /// gender isn't checked.
    static func search(initialSeed: UInt32, targetFrame: UInt32, framesEitherSide: UInt32,
                       method: FinderMethod, template: PFStaticTemplateRef?, game: PFGame,
                       tid: UInt16, sid: UInt16, caught: FRLGCatch) -> [Hit] {
        let start = targetFrame > framesEitherSide ? targetFrame - framesEitherSide : 0
        let span = targetFrame - start + framesEitherSide
        var natures = [Bool](repeating: caught.nature == nil, count: 25)
        if let nature = caught.nature { natures[Int(nature)] = true }
        let powers = [Bool](repeating: true, count: 16)
        let states = if let template {
            PFBridge.staticTemplateGenerate3(seed: initialSeed, initialAdvances: start, maxAdvances: span,
                                             method: finderMethodToPF(method), template: template,
                                             tid: tid, sid: sid, game: game,
                                             filterGender: caught.gender, filterShiny: caught.shiny,
                                             ivMin: caught.ivMin, ivMax: caught.ivMax, natures: natures, powers: powers)
        } else {
            PFBridge.staticGenerate3(seed: initialSeed, initialAdvances: start, maxAdvances: span,
                                     method: finderMethodToPF(method), tid: tid, sid: sid,
                                     filterShiny: caught.shiny,
                                     ivMin: caught.ivMin, ivMax: caught.ivMax, natures: natures, powers: powers)
        }
        return states.map { state in
            Hit(frame: state.advances, offset: Int(state.advances) - Int(targetFrame), pid: state.pid,
                ivs: state.ivs, nature: state.nature, gender: state.gender, shiny: state.shiny)
        }
        .sorted { abs($0.offset) < abs($1.offset) }
    }
}

nonisolated enum Gen3SeedFinder {
    /// A new game's seed: Emerald and FireRed/LeafGreen seed the RNG with
    /// the Trainer ID they make.
    static func seed(trainerID: UInt16) -> String { String(format: "%04X", trainerID) }

    /// A 16-bit seed and frame that make a Pokémon.
    struct Origin: Identifiable, Hashable, Sendable {
        let seed: UInt16
        let frame: UInt32
        let pid: UInt32
        let ivs: [UInt8]
        var id: String { "\(seed) \(frame) \(pid)" }
    }

    /// The most IV combinations tried.
    static let combinationLimit = 64

    /// The 16-bit seeds, and frames from them, that make a Pokémon with
    /// these IVs and nature by `method`: each of IV→PID's matches walked back
    /// to the first seed under 0x10000, fewest frames first. Every
    /// combination in the IV ranges is tried; nil when there are more than
    /// `combinationLimit`.
    static func origins(ivMin: [UInt8], ivMax: [UInt8], nature: UInt8, method: FinderMethod, tid: UInt16) -> [Origin]? {
        let ranges = (0..<6).map { ivMin[$0]...max(ivMin[$0], ivMax[$0]) }
        let combinations = ranges.reduce(1) { $0 * $1.count }
        guard combinations <= combinationLimit else { return nil }
        let wanted: LCRNGReverse.RNGMethod = switch method {
        case .method2: .method2
        case .method4: .method4
        default: .method1
        }
        var ivSets: [[UInt8]] = [[]]
        for range in ranges { ivSets = ivSets.flatMap { set in range.map { set + [$0] } } }
        var origins: [Origin] = []
        for ivs in ivSets {
            for match in LCRNGReverse.calculatePIDs(hp: ivs[0], atk: ivs[1], def: ivs[2], spa: ivs[3], spd: ivs[4],
                                                    spe: ivs[5], nature: nature, tid: tid)
            where match.method == wanted {
                let origin = PFBridge.seedToTimeOriginSeed3(seed: match.seed)
                origins.append(Origin(seed: origin.originSeed, frame: origin.advances, pid: match.pid, ivs: ivs))
            }
        }
        return Array(Set(origins)).sorted { ($0.frame, $0.seed) < ($1.frame, $1.seed) }
    }
}

// MARK: - What You Caught

/// What was caught: nature, gender, shininess and IVs, with the IVs worked
/// out from its stats when the species is known (Ten Lines' calculator, as
/// FireRed and LeafGreen's Calibrate has it).
struct Gen3CaughtEntry: View {
    @Binding var caught: FRLGCatch
    /// The encounter's template, for its base stats; nil to enter IVs only.
    let template: PFStaticTemplateRef?
    let level: Int?

    @State private var lines: [FRLGStatsLine] = []
    @State private var calculatorError: String?

    private static let ivNames = ["HP", "Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Nature") {
                Picker("Nature", selection: $caught.nature) {
                    Text("Any").tag(UInt8?.none)
                    ForEach(0..<25, id: \.self) { Text(pfNatureNames[$0]).tag(UInt8?.some(UInt8($0))) }
                }
            }
            row("Gender") {
                Picker("Gender", selection: $caught.gender) {
                    Text("Any").tag(UInt8(255))
                    Text("Male").tag(UInt8(0))
                    Text("Female").tag(UInt8(1))
                }
            }
            row("Shininess") {
                Picker("Shininess", selection: $caught.shiny) {
                    Text("Any").tag(UInt8(255))
                    Text("Shiny").tag(UInt8(3))
                }
            }
            if template != nil, caught.nature != nil {
                Text("Enter its stats from the summary screen; the IVs are worked out from them, and stay editable.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach($lines) { $line in
                    RNGOptIntField(label: "Level", value: $line.level)
                    ForEach(0..<6, id: \.self) { stat in
                        RNGOptIntField(label: FRLGIVCalculator.statNames[stat], value: $line.stats[stat])
                    }
                }
                if let calculatorError {
                    Text(calculatorError).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("IVs").font(.subheadline.bold()).padding(.top, 4)
            ForEach(0..<6, id: \.self) { index in
                FinderIVRangeRow(label: Self.ivNames[index], min: $caught.ivMin[index], max: $caught.ivMax[index])
            }
        }
        .onAppear {
            if lines.isEmpty { lines = [FRLGStatsLine(level: level)] }
        }
        .onChange(of: lines) { recalculate() }
        .onChange(of: caught.nature) { recalculate() }
    }

    private func recalculate() {
        guard let nature = caught.nature, let template, lines.contains(where: { !$0.isBlank }) else {
            calculatorError = nil
            return
        }
        switch FRLGIVCalculator.calculate(lines, template: template, nature: nature) {
        case .ivs(let min, let max):
            caught.ivMin = min
            caught.ivMax = max
            calculatorError = nil
        case .error(let message):
            calculatorError = message
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content().labelsHidden()
        }
    }
}

// MARK: - What You Hit

/// On a Gen 3 target's page: the frame you hit, from what you caught, for
/// the Timer's Frame Hit.
struct Gen3WhatYouHitCard: View {
    let target: StaticSearchResult
    /// A Generator's result counts frames from its seed; a Searcher's is a
    /// seed, whose frame comes from the game's initial seed.
    let fromGenerator: Bool
    let suggestedInitialSeed: UInt32
    let method: FinderMethod
    let template: PFStaticTemplateRef?
    let level: Int?
    let game: PFGame
    let tid: UInt16
    let sid: UInt16
    let sendHit: (TimerHit) -> Void

    @State private var initialSeedText = ""
    @State private var caught = FRLGCatch()
    @State private var framesEitherSide = 1000
    @State private var hits: [Gen3HitSearch.Hit]?
    @State private var searching = false

    private var initialSeed: UInt32? {
        fromGenerator ? target.seed : UInt32(initialSeedText.trimmingCharacters(in: .whitespaces), radix: 16)
    }

    private var targetFrame: UInt32? {
        guard let initialSeed else { return nil }
        return fromGenerator ? target.advances : PFBridge.lcrngDistance(from: initialSeed, to: target.seed)
    }

    var body: some View {
        SectionCard(title: "What You Hit", icon: "checkmark.shield") {
            Text("After catching it, enter what you caught to find the frame you hit, for the Timer's Frame Hit.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if fromGenerator {
                LabeledContent("Initial Seed") {
                    Text(String(format: "%04X", target.seed)).font(.system(.body, design: .monospaced))
                }
            } else {
                HStack {
                    Text("Initial Seed")
                    Spacer()
                    TextField("Hex", text: $initialSeedText)
                        .textFieldStyle(.roundedBorder).scaledWidth(110)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }
                Text("The seed the game started on: Emerald's is 0000, a dead battery's 05A0, a new game's your Trainer ID in hex.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let targetFrame {
                LabeledContent("Target Frame", value: targetFrame.formatted())
            }
            Gen3CaughtEntry(caught: $caught, template: template, level: level)
            RNGIntField(label: "Frames Either Side", value: $framesEitherSide, range: 1...100_000)
            Button {
                Task { await search() }
            } label: {
                if searching { ProgressView() } else { Label("Find What I Hit", systemImage: "magnifyingglass") }
            }
            .buttonStyle(.primaryAction)
            .disabled(searching || targetFrame == nil || !ivRangesValid)
            if let hits {
                if hits.isEmpty {
                    Text("No frame within \(framesEitherSide.formatted()) of the target makes that Pokémon. Check what you entered, or search further.")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(hits.prefix(20)) { hit in
                        hitRow(hit)
                        Divider()
                    }
                }
            }
        }
        .onAppear {
            if initialSeedText.isEmpty { initialSeedText = String(format: "%04X", suggestedInitialSeed) }
        }
    }

    private var ivRangesValid: Bool {
        (0..<6).allSatisfy { caught.ivMin[$0] <= caught.ivMax[$0] && caught.ivMax[$0] <= 31 }
    }

    private func search() async {
        guard let initialSeed, let targetFrame else { return }
        searching = true
        let (method, template, game, tid, sid, caught) = (method, template, game, tid, sid, caught)
        let leeway = UInt32(framesEitherSide)
        hits = await Task.detached {
            Gen3HitSearch.search(initialSeed: initialSeed, targetFrame: targetFrame, framesEitherSide: leeway,
                                 method: method, template: template, game: game, tid: tid, sid: sid, caught: caught)
        }.value
        searching = false
    }

    private func hitRow(_ hit: Gen3HitSearch.Hit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Frame \(hit.frame.formatted())").font(.headline)
                Text(offsetText(hit.offset)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if hit.shiny != 0 { Image(systemName: "star.fill").foregroundStyle(.yellow) }
            }
            Text("\(hit.ivs.map(String.init).joined(separator: "/")) · \(pfNatureNames[Int(hit.nature)])")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Button {
                sendHit(TimerHit(generation: .gen3, frameOffset: hit.offset,
                                 note: "You hit frame \(hit.frame.formatted())\(hit.offset == 0 ? ", the target" : ", " + offsetText(hit.offset)). Tap Update Calibration."))
            } label: {
                Label("Use as Frame Hit", systemImage: "tuningfork")
            }
            .buttonStyle(.borderless)
        }
    }

    private func offsetText(_ offset: Int) -> String {
        offset == 0 ? "the target" : offset > 0 ? "\(offset) late" : "\(-offset) early"
    }
}

// MARK: - Seed from a Pokémon

/// The Generator's seed from a caught Pokémon, when the game's seed is only
/// known from it (a FireRed/LeafGreen seed found from a Dratini's IVs, say).
struct Gen3SeedFromPokemonView: View {
    let method: FinderMethod
    let tid: UInt16
    let template: PFStaticTemplateRef?
    let level: Int?
    let use: (Gen3SeedFinder.Origin) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var caught = FRLGCatch()
    @State private var origins: [Gen3SeedFinder.Origin]?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            CardStack {
                SectionCard(title: "What You Caught", icon: "checkmark.shield") {
                    Text("Its nature and IVs lead back to the seed the game started on, and the frame it came from (\(method.rawValue)).")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Gen3CaughtEntry(caught: $caught, template: template, level: level)
                    Button {
                        find()
                    } label: {
                        Label("Find Seeds", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.primaryAction)
                    if let problem {
                        Text(problem).font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let origins {
                    SectionCard(title: "Seeds (\(origins.count))", icon: "number") {
                        if origins.isEmpty {
                            Text("No seed makes that Pokémon by \(method.rawValue). Check its nature and IVs.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        ForEach(origins.prefix(30)) { origin in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Seed \(String(format: "%04X", origin.seed))")
                                        .font(.system(.body, design: .monospaced).bold())
                                    Text("Frame \(origin.frame.formatted()) · \(origin.ivs.map(String.init).joined(separator: "/"))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Use") {
                                    use(origin)
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                            }
                            Divider()
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Seed from a Pokémon")
    }

    private func find() {
        guard let nature = caught.nature else {
            problem = "Choose its nature."
            return
        }
        guard let found = Gen3SeedFinder.origins(ivMin: caught.ivMin, ivMax: caught.ivMax, nature: nature,
                                                 method: method, tid: tid) else {
            problem = "Narrow its IVs down: at most \(Gen3SeedFinder.combinationLimit) combinations are tried. Its stats at another level narrow them."
            origins = nil
            return
        }
        problem = nil
        origins = found
    }
}
