//
//  FRLGSeedsView.swift
//  PKReference
//
//  The Finder's FireRed and LeafGreen initial seeds: the farmed seed lists
//  (bundled, or newer ones downloaded from the community's sheets), the
//  settings a player uses and the advances they can wait, and for each
//  target the seeds that reach it, when to press, and Send to Timer. The
//  search itself is in `FRLGSeeds.swift`, ported from Ten Lines.
//

import SwiftUI

// MARK: - The seed lists

/// The farmed lists: the bundled copies, or newer ones downloaded from the
/// public sheets into Application Support.
@MainActor @Observable
final class FRLGSeedStore {
    static let shared = FRLGSeedStore()

    /// When the downloaded copies were fetched; nil while the bundled ones
    /// are in use.
    private(set) var downloadedAt: Date?
    private(set) var updating = false
    private(set) var updateError: String?
    private var cache: [FRLGSeedSheet: FRLGSeedList] = [:]
    private let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "FRLGSeeds", directoryHint: .isDirectory)) {
        self.directory = directory
        let stamp = try? String(contentsOf: directory.appending(path: "fetched-at.txt"), encoding: .utf8)
        downloadedAt = stamp.flatMap { try? Date($0.trimmingCharacters(in: .whitespacesAndNewlines), strategy: .iso8601) }
    }

    /// When the bundled copies were downloaded (`tools/update_frlg_seeds.sh`
    /// writes it).
    var bundledDate: String? {
        Bundle.main.url(forResource: "frlg-seeds-date", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func list(_ sheet: FRLGSeedSheet) async -> FRLGSeedList? {
        if let cached = cache[sheet] { return cached }
        let downloaded = directory.appending(path: sheet.resourceName + ".csv")
        let url = FileManager.default.fileExists(atPath: downloaded.path(percentEncoded: false))
            ? downloaded : Bundle.main.url(forResource: sheet.resourceName, withExtension: "csv")
        guard let url, let list = await Self.read(url, sheet) else { return nil }
        cache[sheet] = list
        return list
    }

    @concurrent
    nonisolated private static func read(_ url: URL, _ sheet: FRLGSeedSheet) async -> FRLGSeedList? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return FRLGSeedList(sheet: sheet, csv: text)
    }

    /// Downloads every list from its public sheet. Each has to read as a
    /// list before any replaces the copies in use.
    func update() async {
        updating = true
        updateError = nil
        defer { updating = false }
        do {
            var fetched: [(FRLGSeedSheet, Data)] = []
            for sheet in FRLGSeedSheet.allCases {
                let (data, response) = try await URLSession.shared.data(from: sheet.url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let text = String(data: data, encoding: .utf8),
                      FRLGSeedList(sheet: sheet, csv: text).entries.count >= 100 else {
                    throw UpdateError.unreadable(sheet.rawValue)
                }
                fetched.append((sheet, data))
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (sheet, data) in fetched {
                try data.write(to: directory.appending(path: sheet.resourceName + ".csv"), options: .atomic)
            }
            let now = Date()
            try now.ISO8601Format().write(to: directory.appending(path: "fetched-at.txt"), atomically: true, encoding: .utf8)
            downloadedAt = now
            cache = [:]
        } catch {
            updateError = error.localizedDescription
        }
    }

    enum UpdateError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let sheet): "The \(sheet) list didn't download as a seed list, so nothing was changed."
            }
        }
    }
}

// MARK: - What the player uses

/// The Finder's FRLG settings, kept between launches, and the index of
/// seeds they allow.
@MainActor @Observable
final class FRLGSeedSearch {
    var enabled: Bool { didSet { defaults.set(enabled, forKey: "frlg_enabled") } }
    var version: FRLGVersion {
        didSet {
            if !version.consoles.contains(console) { console = version.consoles[0] }
            defaults.set(version.rawValue, forKey: "frlg_version")
            if version != oldValue { applyDefaults() }
        }
    }
    var console: FRLGConsole { didSet { defaults.set(console.rawValue, forKey: "frlg_console") } }
    var sound: FRLGSound? { didSet { defaults.set(sound?.rawValue ?? "", forKey: "frlg_sound") } }
    var buttonMode: FRLGButtonMode? { didSet { defaults.set(buttonMode?.rawValue ?? "", forKey: "frlg_buttonMode") } }
    var seedButton: FRLGSeedButton? { didSet { defaults.set(seedButton?.rawValue ?? "", forKey: "frlg_seedButton") } }
    var held: FRLGHeldButton? { didSet { defaults.set(held?.rawValue ?? "", forKey: "frlg_held") } }
    var minimumAdvances: Int { didSet { defaults.set(minimumAdvances, forKey: "frlg_minimum") } }
    var maximumAdvances: Int { didSet { defaults.set(maximumAdvances, forKey: "frlg_maximum") } }
    var teachyTV: Bool { didSet { defaults.set(teachyTV, forKey: "frlg_teachyTV") } }
    var teachyTVMinimumOutside: Int { didSet { defaults.set(teachyTVMinimumOutside, forKey: "frlg_teachyTVOutside") } }
    /// On Switch, the frames spent in the overworld before the press that
    /// gets the Pokémon, where the RNG advances twice a frame.
    var overworldFrames: Int { didSet { defaults.set(overworldFrames, forKey: "frlg_overworldFrames") } }
    /// From calibrating: added to each seed time sent to the timer, and the
    /// timer's calibration for the final press, both in milliseconds.
    var seedCalibrationMS: Int { didSet { defaults.set(seedCalibrationMS, forKey: "frlg_seedCalibration") } }
    var frameCalibrationMS: Int { didSet { defaults.set(frameCalibrationMS, forKey: "frlg_frameCalibration") } }

    /// The seeds the settings allow; nil until built.
    private(set) var index: FRLGSeedIndex?
    /// What `index` was built for.
    private(set) var builtKey: IndexKey?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "frlg_enabled") as? Bool ?? true
        let version = FRLGVersion(rawValue: defaults.string(forKey: "frlg_version") ?? "") ?? .fireRedSwitch
        self.version = version
        console = FRLGConsole(rawValue: defaults.string(forKey: "frlg_console") ?? "")
            .flatMap { version.consoles.contains($0) ? $0 : nil } ?? version.consoles[0]
        sound = FRLGSound(rawValue: defaults.string(forKey: "frlg_sound") ?? "")
        buttonMode = FRLGButtonMode(rawValue: defaults.string(forKey: "frlg_buttonMode") ?? "")
        seedButton = FRLGSeedButton(rawValue: defaults.string(forKey: "frlg_seedButton") ?? "")
        held = FRLGHeldButton(rawValue: defaults.string(forKey: "frlg_held") ?? "")
        minimumAdvances = defaults.object(forKey: "frlg_minimum") as? Int ?? 0
        maximumAdvances = defaults.object(forKey: "frlg_maximum") as? Int ?? 100_000
        teachyTV = defaults.bool(forKey: "frlg_teachyTV")
        teachyTVMinimumOutside = defaults.object(forKey: "frlg_teachyTVOutside") as? Int ?? 3600
        overworldFrames = defaults.object(forKey: "frlg_overworldFrames") as? Int ?? 600
        seedCalibrationMS = defaults.integer(forKey: "frlg_seedCalibration")
        frameCalibrationMS = defaults.integer(forKey: "frlg_frameCalibration")
        // The first time, start on what the list covers.
        if defaults.object(forKey: "frlg_buttonMode") == nil { applyDefaults() }
    }

    /// The game's own options, Mono sound and Help mode, pressing A: every
    /// list farms them.
    static let gameDefaults = FRLGSetting(sound: .mono, buttonMode: .help, seedButton: .a)

    /// Starts each option on a setting the version's list has: the game's
    /// defaults with no held button, or if a list lacks them, the first
    /// setting it has. Any is still there to choose.
    func applyDefaults() {
        let farmed = version.farmedSettings
        let setting = farmed.contains(Self.gameDefaults) ? Self.gameDefaults : farmed.first ?? Self.gameDefaults
        sound = setting.sound
        buttonMode = setting.buttonMode
        seedButton = setting.seedButton
        held = FRLGHeldButton.none
    }

    /// Whether the choices made can find any seed in the version's list.
    var isFarmed: Bool {
        version.isFarmed(sound: sound, buttonMode: buttonMode, seedButton: seedButton)
            && (held.map { version.heldButtons(buttonMode: buttonMode).contains($0) } ?? true)
    }

    var filter: FRLGSettingsFilter {
        FRLGSettingsFilter(sound: sound, buttonMode: buttonMode, seedButton: seedButton, held: held)
    }

    /// What the index depends on.
    struct IndexKey: Equatable {
        let version: FRLGVersion
        let filter: FRLGSettingsFilter
        let downloadedAt: Date?
    }

    var indexKey: IndexKey {
        IndexKey(version: version, filter: filter, downloadedAt: FRLGSeedStore.shared.downloadedAt)
    }

    /// `store` defaults to the shared one (a default argument can't name
    /// it: those are evaluated off the main actor).
    func rebuildIndex(store: FRLGSeedStore? = nil) async {
        let store = store ?? .shared
        let key = indexKey
        guard let list = await store.list(key.version.sheet) else {
            index = nil
            builtKey = nil
            return
        }
        let built = await Self.build(list, key.version, key.filter)
        guard key == indexKey else { return }
        index = built
        builtKey = key
    }

    /// What a target's nearest seed depends on: the seeds, and the advances
    /// allowed.
    struct ReachKey: Equatable {
        let index: IndexKey?
        let minimum: UInt32
        let maximum: UInt32
    }

    var reachKey: ReachKey { ReachKey(index: builtKey, minimum: range.minimum, maximum: range.maximum) }

    @concurrent
    nonisolated private static func build(_ list: FRLGSeedList, _ version: FRLGVersion,
                                          _ filter: FRLGSettingsFilter) async -> FRLGSeedIndex {
        FRLGSeedIndex(list: list, version: version, filter: filter)
    }

    /// Teachy TV mode needs that many advances outside it, and on Switch
    /// the overworld takes two a frame, so they're the least a seed can be
    /// from its target.
    private var range: (minimum: UInt32, maximum: UInt32) {
        var minimum = max(0, minimumAdvances)
        if usesTeachyTV { minimum = max(minimum, teachyTVMinimumOutside) }
        if version.isSwitch { minimum = max(minimum, 2 * max(0, overworldFrames)) }
        return (UInt32(clamping: minimum), UInt32(clamping: max(0, maximumAdvances)))
    }

    var usesTeachyTV: Bool { teachyTV && version.supportsTeachyTV }

    /// The fewest-advances seed that reaches `target` in range.
    func nearest(reaching target: UInt32) -> FRLGInitialSeed? {
        index?.nearest(reaching: target, minimum: range.minimum, maximum: range.maximum)
    }

    func seeds(reaching target: UInt32, limit: Int) -> [FRLGInitialSeed] {
        index?.seeds(reaching: target, minimum: range.minimum, maximum: range.maximum, limit: limit) ?? []
    }

    /// When to press, in milliseconds from startup.
    func seedTimeMS(_ seed: FRLGInitialSeed) -> Int {
        console.milliseconds(frames: Double(seed.seedTime) / 16)
    }

    /// The pre-timer: the seed time, with the seed press's calibration.
    func preTimerMS(_ seed: FRLGInitialSeed) -> Int { seedTimeMS(seed) + seedCalibrationMS }

    /// The frame to press on after the seed is set. On GBA it's the final
    /// press: the advances, or with Teachy TV the frames spent there plus
    /// the advances outside it. On Switch it's the continue screen's press,
    /// the overworld frames after it taking two advances each (Ten Lines'
    /// "Continue Screen Frames").
    func targetFrame(_ seed: FRLGInitialSeed) -> (frame: UInt32, teachyTVFrames: UInt32) {
        if version.isSwitch {
            return (seed.advances - min(seed.advances, UInt32(clamping: 2 * max(0, overworldFrames))), 0)
        }
        guard usesTeachyTV else { return (seed.advances, 0) }
        let split = TeachyTV.split(advances: seed.advances,
                                   minimumOutside: UInt32(clamping: max(0, teachyTVMinimumOutside)))
        return (split.ttvFrames + split.regularAdvances, split.ttvFrames)
    }

    /// The same frame for a calibration hit.
    func hitFrame(_ hit: FRLGCalibrationHit) -> UInt32 {
        if version.isSwitch { return hit.advances - min(hit.advances, UInt32(clamping: 2 * max(0, overworldFrames))) }
        return hit.finalFrame
    }

    /// Corrects the timer from an attempt that hit `hit` instead: the seed
    /// press by the difference in seed times, the final press by the
    /// frames it was off, as the Gen 3 timer's own calibration does.
    func calibrate(attempted: FRLGInitialSeed, hit: FRLGCalibrationHit) {
        let hitSeed = FRLGInitialSeed(seed: hit.seed, setting: attempted.setting, held: attempted.held,
                                      seedTime: hit.seedTime)
        seedCalibrationMS -= seedTimeMS(hitSeed) - seedTimeMS(attempted)
        let settings = CalibratorSettings(console: .gba, customFramerate: 60, precisionCalibration: false,
                                          minimumLength: EONTIMER_MINIMUM_LENGTH)
        frameCalibrationMS += calibrateGen3(settings, targetFrame: Int(targetFrame(attempted).frame),
                                            frameHit: Int(hitFrame(hit)))
    }

    func resetCalibration() {
        seedCalibrationMS = 0
        frameCalibrationMS = 0
    }
}

// MARK: - The settings card

/// The Finder's Initial Seed card, for FireRed and LeafGreen searches.
struct FRLGInitialSeedSection: View {
    @Bindable var search: FRLGSeedSearch
    /// Whether the Finder's game is FireRed (else LeafGreen).
    let fireRed: Bool
    private let store = FRLGSeedStore.shared

    var body: some View {
        SectionCard(title: "Initial Seed", icon: "power") {
            Toggle("Only targets I can reach", isOn: $search.enabled)
            Text("FireRed and LeafGreen seed the RNG when you press a button on the title screen. With this on, results are the targets reachable from a seed you can hit, fewest advances first.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if search.enabled {
                // Versions have long names, so the picker gets its own line.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version")
                    Picker("Version", selection: $search.version) {
                        ForEach(FRLGVersion.versions(fireRed: fireRed)) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                }
                labeled("Console") {
                    Picker("Console", selection: $search.console) {
                        ForEach(search.version.consoles) { Text($0.name).tag($0) }
                    }
                }
                labeled("Sound") {
                    Picker("Sound", selection: $search.sound) {
                        Text("Any").tag(FRLGSound?.none)
                        ForEach(FRLGSound.allCases, id: \.self) { sound in
                            Text(marked(sound.name, search.version.farmedSounds.contains(sound))).tag(Optional(sound))
                        }
                    }
                }
                labeled("Button Mode") {
                    Picker("Button Mode", selection: $search.buttonMode) {
                        Text("Any").tag(FRLGButtonMode?.none)
                        ForEach(FRLGButtonMode.allCases, id: \.self) { mode in
                            Text(marked(mode.name, search.version.farmedButtonModes.contains(mode))).tag(Optional(mode))
                        }
                    }
                }
                labeled("Seed Button") {
                    Picker("Seed Button", selection: $search.seedButton) {
                        Text("Any").tag(FRLGSeedButton?.none)
                        ForEach(FRLGSeedButton.allCases, id: \.self) { button in
                            Text(marked(button.name, search.version.farmedSeedButtons.contains(button))).tag(Optional(button))
                        }
                    }
                }
                labeled("Held Button") {
                    Picker("Held Button", selection: $search.held) {
                        Text("Any").tag(FRLGHeldButton?.none)
                        ForEach(heldButtons, id: \.self) { held in
                            Text(marked(held.name, search.version.heldButtons(buttonMode: search.buttonMode).contains(held)))
                                .tag(Optional(held))
                        }
                    }
                }
                coverageNote
                RNGIntField(label: "Minimum Advances", value: $search.minimumAdvances)
                RNGIntField(label: "Maximum Advances", value: $search.maximumAdvances)
                if search.version.isSwitch {
                    RNGIntField(label: "Overworld Frames", value: $search.overworldFrames)
                    Text("The frames you spend in the overworld before the press that gets the Pokémon. On Switch the RNG advances twice a frame there, so the timer's target is the press on the continue screen.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if search.seedCalibrationMS != 0 || search.frameCalibrationMS != 0 {
                    HStack {
                        Text("Calibration: seed press \(signed(search.seedCalibrationMS)) ms, final press \(signed(search.frameCalibrationMS)) ms")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset") { search.resetCalibration() }.font(.caption)
                    }
                }
                if search.version.supportsTeachyTV {
                    Toggle("Teachy TV", isOn: $search.teachyTV)
                    if search.teachyTV {
                        RNGIntField(label: "Advances Outside Teachy TV", value: $search.teachyTVMinimumOutside)
                        Text("In the Teachy TV the RNG advances 313 times a frame, so most of a long wait can be spent there.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                seedListInfo
            }
        }
        .task(id: search.indexKey) { await search.rebuildIndex() }
        .onChange(of: fireRed, initial: true) {
            if search.version.isFireRed != fireRed {
                search.version = fireRed ? .fireRedSwitch : .leafGreenSwitch
            }
        }
    }

    /// A picker with its name beside it, since a menu picker shows only its
    /// value here.
    private func labeled(_ title: String, @ViewBuilder picker: () -> some View) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            picker().labelsHidden()
        }
    }

    /// The held buttons the version knows, in any button mode.
    private var heldButtons: [FRLGHeldButton] {
        let known = Set(FRLGHeldButtons.offsets(for: search.version).map(\.held))
        return FRLGHeldButton.allCases.filter(known.contains)
    }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

    /// An option the version's list has no seeds for says so.
    private func marked(_ name: String, _ farmed: Bool) -> String {
        farmed ? name : "\(name) (not farmed)"
    }

    /// What a partly farmed list covers, and a warning when the choices
    /// made find nothing.
    @ViewBuilder
    private var coverageNote: some View {
        let version = search.version
        if !version.isFullyFarmed {
            Text("So far this version's seed list covers \(version.farmedSettings.map(\.name).joined(separator: "; ")). The community hasn't farmed the other settings yet, so they can't be searched.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !search.isFarmed {
            Label("No seeds are farmed for these settings on this version, so nothing can be found. Choose a setting without \"(not farmed)\", or set it to Any.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var seedListInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let index = search.index {
                    Text("\(index.count.formatted()) seeds you can hit with these settings, from the community's farmed list"
                         + (store.downloadedAt.map { ", updated \($0.formatted(date: .abbreviated, time: .omitted))." }
                            ?? store.bundledDate.map { " of \($0)." } ?? "."))
                } else {
                    Text("Loading the seed list…")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if store.updating {
                ProgressView().controlSize(.small)
            } else {
                Button("Update Seed Lists") { Task { await store.update() } }
                    .font(.subheadline)
            }
            if let error = store.updateError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

// MARK: - A result's seeds

/// One line under a Finder result: the seed that reaches it with the
/// fewest advances.
struct FRLGMatchLine: View {
    let seed: FRLGInitialSeed
    let search: FRLGSeedSearch

    var body: some View {
        Text("Seed \(String(format: "%04X", seed.seed)) · \(seed.advances.formatted()) advances · \(search.seedTimeMS(seed).formatted()) ms · \(seed.settingsName)")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
}

/// A target's reachable seeds, for its detail page.
struct FRLGInitialSeedList: View {
    let target: StaticSearchResult
    let search: FRLGSeedSearch
    /// What calibrating needs; nil where it can't (wild encounters).
    var calibration: FRLGCalibrationContext?
    /// The seed being calibrated, which the target's page pushes.
    @Binding var calibrating: FRLGInitialSeed?
    /// Sends a seed's timing to the Timer: pre-timer (ms), target frame.
    var onSendToTimer: (FRLGInitialSeed, Int, UInt32) -> Void

    private static let shown = 100

    var body: some View {
        let seeds = FRLGHeldChoice.merged(search.seeds(reaching: target.seed, limit: Self.shown))
        SectionCard(title: "Initial Seeds", icon: "power") {
            if seeds.isEmpty {
                Text("No seed you can hit with these settings reaches this target in \(search.minimumAdvances.formatted())–\(search.maximumAdvances.formatted()) advances.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Press the seed button at the seed time, then on the target frame. Fewest advances first\(seeds.count == Self.shown ? ", the first \(Self.shown)" : "").")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(seeds, id: \.seed) { choice in
                    row(choice)
                    Divider()
                }
            }
        }
        #if DEBUG && os(macOS)
        .task { await DebugSnapshot.openSheet("frlgCalibration") { calibrating = seeds.first?.seed } }
        #endif
    }

    private func row(_ choice: FRLGHeldChoice) -> some View {
        let seed = choice.seed
        let seedTime = search.seedTimeMS(seed)
        let target = search.targetFrame(seed)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Seed \(String(format: "%04X", seed.seed))").font(.system(.subheadline, design: .monospaced).bold())
                Spacer()
                Text("\(seed.advances.formatted()) advances").font(.system(.caption, design: .monospaced))
            }
            Text(choice.settingsName).font(.caption)
            Text("Seed time \(seedTime.formatted()) ms · target frame \(target.frame.formatted())"
                 + (target.teachyTVFrames > 0 ? " (\(target.teachyTVFrames.formatted()) in Teachy TV)" : "")
                 + (search.version.isSwitch ? " on the continue screen, then \(search.overworldFrames.formatted()) in the overworld" : ""))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button {
                    onSendToTimer(seed, search.preTimerMS(seed), target.frame)
                } label: {
                    Label("Send to Timer", systemImage: "timer")
                }
                if calibration != nil {
                    Button {
                        calibrating = seed
                    } label: {
                        Label("Calibrate", systemImage: "scope")
                    }
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }
}

/// One press that gives a seed, with every held button that gives it from
/// there (on Switch, holding R or L on the blackout screen does the same).
struct FRLGHeldChoice {
    let seed: FRLGInitialSeed
    let held: [FRLGHeldButton]

    /// "Mono · Help · A, holding Blackout R or Blackout L".
    var settingsName: String {
        let order = FRLGHeldButton.allCases
        let names = held.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }.map(\.name)
        return held == [.none] ? seed.setting.name : "\(seed.setting.name), holding \(names.joined(separator: " or "))"
    }

    /// Seeds in order, with neighbours that differ only by held button made
    /// one.
    static func merged(_ seeds: [FRLGInitialSeed]) -> [FRLGHeldChoice] {
        var merged: [FRLGHeldChoice] = []
        for seed in seeds {
            if let last = merged.last, last.seed.seed == seed.seed, last.seed.setting == seed.setting,
               last.seed.seedTime == seed.seedTime, last.seed.advances == seed.advances {
                merged[merged.count - 1] = FRLGHeldChoice(seed: last.seed, held: last.held + [seed.held])
            } else {
                merged.append(FRLGHeldChoice(seed: seed, held: [seed.held]))
            }
        }
        return merged
    }
}

// MARK: - Reachable Targets

/// A target the Finder found, and the seed that reaches it in the fewest
/// advances.
struct FRLGMatch: Identifiable {
    let result: StaticSearchResult
    let seed: FRLGInitialSeed
    var id: UUID { result.id }
}

/// The Finder's reachable targets, kept up as results come in: each new
/// result is checked once, and every one again only when the seeds or the
/// advances allowed change, so a long search's list doesn't slow down as it
/// grows.
final class FRLGMatchCache {
    private var key: FRLGSeedSearch.ReachKey?
    private var firstID: UUID?
    private var checked = 0
    private var matches: [FRLGMatch] = []

    /// Fewest advances first.
    func matches(for results: [StaticSearchResult], search: FRLGSeedSearch) -> [FRLGMatch] {
        let key = search.reachKey
        // A new search, or new settings.
        if key != self.key || results.first?.id != firstID || results.count < checked {
            self.key = key
            firstID = results.first?.id
            checked = 0
            matches = []
        }
        guard checked < results.count else { return matches }
        let found = results[checked...].compactMap { result in
            search.nearest(reaching: result.seed).map { FRLGMatch(result: result, seed: $0) }
        }
        checked = results.count
        if !found.isEmpty {
            matches.append(contentsOf: found)
            matches.sort { $0.seed.advances < $1.seed.advances }
        }
        return matches
    }
}

// MARK: - Calibrating

/// What calibrating a target needs from the Finder: the search's method and
/// trainer, and the encounter, for its template.
struct FRLGCalibrationContext {
    let method: FinderMethod
    let tid: UInt16
    let sid: UInt16
    let encounter: StaticEncounter?
}

/// After an attempt: what was caught says which seed and frame it hit, and
/// the timer is corrected for the next one. Ten Lines' calibration form,
/// with its IV calculator: the stats work out the IVs with the nature.
struct FRLGCalibrationView: View {
    let target: StaticSearchResult
    let attempted: FRLGInitialSeed
    let search: FRLGSeedSearch
    let context: FRLGCalibrationContext
    var onSendToTimer: (FRLGInitialSeed, Int, UInt32) -> Void

    @State private var template: PFStaticTemplateRef?
    /// Ten Lines' defaults: any shininess, nature and gender.
    @State private var shiny: UInt8 = 255
    @State private var nature: UInt8?
    @State private var gender: UInt8 = 255
    @State private var lines = [FRLGStatsLine()]
    @State private var ivMin: [UInt8] = Array(repeating: 0, count: 6)
    @State private var ivMax: [UInt8] = Array(repeating: 31, count: 6)
    @State private var calculatorError: String?
    @State private var seedLeeway = 20
    @State private var frameLeeway = 100
    @State private var teachyTVLeeway = 15
    @State private var hits: [FRLGCalibrationHit]?
    @State private var searchedAnyNature = false
    @State private var searching = false
    @State private var applied: FRLGCalibrationHit?

    private static let ivNames = ["HP", "Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed"]

    var body: some View {
        ScrollView {
            CardStack {
                attemptCard
                caughtCard
                searchCard
                if let hits { resultsCard(hits) }
            }
            .padding()
        }
        .dismissesKeyboard()
        .navigationTitle("Calibrate")
        .onAppear {
            guard template == nil, let encounter = context.encounter, encounter.generation == .gen3 else { return }
            template = encounter.template
            lines[0].level = Int(encounter.level)
        }
        .onChange(of: lines) { recalculate() }
        .onChange(of: nature) { recalculate() }
    }

    private var attemptCard: some View {
        let frame = search.targetFrame(attempted)
        return SectionCard(title: "Your Attempt", icon: "target") {
            LabeledContent("Seed", value: String(format: "%04X", attempted.seed))
                .font(.system(.body, design: .monospaced))
            LabeledContent("Settings", value: attempted.settingsName)
            LabeledContent("Seed time", value: "\(search.seedTimeMS(attempted).formatted()) ms")
            LabeledContent("Target frame", value: frame.frame.formatted())
            LabeledContent("Target", value: "\(target.ivSummary) · \(target.natureName)")
                .font(.system(.body, design: .monospaced))
        }
    }

    /// Ten Lines' IV calculator: with a nature, valid stats fill the IV
    /// ranges, which stay editable.
    private func recalculate() {
        guard let nature, let template, lines.contains(where: { !$0.isBlank }) else {
            calculatorError = nil
            return
        }
        switch FRLGIVCalculator.calculate(lines, template: template, nature: nature) {
        case .ivs(let min, let max):
            ivMin = min
            ivMax = max
            calculatorError = nil
        case .error(let message):
            calculatorError = message
        }
    }

    private var ivRangesValid: Bool {
        (0..<6).allSatisfy { ivMin[$0] <= ivMax[$0] && ivMax[$0] <= 31 }
    }

    private var caught: FRLGCatch {
        FRLGCatch(nature: nature, ivMin: ivMin, ivMax: ivMax, gender: gender, shiny: shiny)
    }

    private var caughtCard: some View {
        SectionCard(title: "What You Caught", icon: "checkmark.shield") {
            if context.encounter != nil, template == nil {
                Text("This encounter isn't in PokéFinder's tables, so it can't be calibrated.")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            pickerRow("Shininess", selection: $shiny) {
                Text("Any").tag(UInt8(255))
                Text("Star").tag(UInt8(1))
                Text("Square").tag(UInt8(2))
                Text("Star or Square").tag(UInt8(3))
            }
            pickerRow("Nature", selection: $nature) {
                Text("Any").tag(UInt8?.none)
                ForEach(0..<25, id: \.self) { Text(pfNatureNames[$0]).tag(UInt8?.some(UInt8($0))) }
            }
            pickerRow("Gender", selection: $gender) {
                Text("Any").tag(UInt8(255))
                Text("Male").tag(UInt8(0))
                Text("Female").tag(UInt8(1))
            }
            if nature == nil {
                Text("IV calculation is off: searching every nature, with any IVs. Pick its nature to work out its IVs from its stats.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                statsEntry
                Text("IVs").font(.subheadline.bold()).padding(.top, 4)
                ForEach(0..<6, id: \.self) { index in
                    FinderIVRangeRow(label: Self.ivNames[index], min: $ivMin[index], max: $ivMax[index])
                }
                if !ivRangesValid {
                    Text("Each IV range runs from 0 to 31, lowest first.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    /// The stats from its summary screen, a line per level: more lines,
    /// after levelling up, narrow the IVs down.
    @ViewBuilder
    private var statsEntry: some View {
        Text("Enter its stats from the summary screen. The IVs below are worked out from them, with its nature and base stats; you can still edit them.")
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
                RNGOptIntField(label: FRLGIVCalculator.statNames[stat], value: $line.stats[stat])
            }
        }
        if let calculatorError {
            Text(calculatorError)
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        Button {
            lines.append(FRLGStatsLine(level: lines.last?.level.map { min($0 + 1, 100) }))
        } label: {
            Label("Add Stats at Another Level", systemImage: "plus.circle")
        }
        .font(.caption)
        .buttonStyle(.borderless)
    }

    private func pickerRow<Value: Hashable, Content: View>(_ title: String, selection: Binding<Value>,
                                                         @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection, content: content)
                .labelsHidden()
        }
    }

    private var searchCard: some View {
        SectionCard(title: "Search", icon: "magnifyingglass") {
            RNGIntField(label: "Seeds Either Side", value: $seedLeeway)
            RNGIntField(label: "Frames Either Side", value: $frameLeeway)
            if search.usesTeachyTV {
                RNGIntField(label: "Teachy TV Frames Either Side", value: $teachyTVLeeway)
            }
            Button {
                Task { await runSearch() }
            } label: {
                if searching { ProgressView() } else { Label("Find What I Hit", systemImage: "magnifyingglass") }
            }
            .buttonStyle(.primaryAction)
            .disabled(searching || template == nil
                      || (nature != nil && (!ivRangesValid || calculatorError != nil)))
        }
    }

    private func runSearch() async {
        guard let template, let list = await FRLGSeedStore.shared.list(search.version.sheet) else { return }
        searching = true
        defer { searching = false }
        applied = nil
        let center = attempted.advances
        let ttvCenter = search.targetFrame(attempted).teachyTVFrames
        let finalCenter = search.usesTeachyTV ? search.targetFrame(attempted).frame : center
        let leeway = UInt32(clamping: max(0, frameLeeway))
        let frames = (finalCenter > leeway ? finalCenter - leeway : 0)...(finalCenter &+ leeway)
        let ttvLeeway = UInt32(clamping: max(0, teachyTVLeeway))
        let ttv: ClosedRange<UInt32>? = search.usesTeachyTV
            ? (ttvCenter > ttvLeeway ? ttvCenter - ttvLeeway : 0)...(ttvCenter + ttvLeeway) : nil
        searchedAnyNature = nature == nil
        hits = await Self.search(list: list, version: search.version, attempted: attempted, targetFrame: finalCenter,
                                 seedLeeway: max(0, seedLeeway), frames: frames, teachyTVFrames: ttv,
                                 method: finderMethodToPF(context.method), template: template,
                                 tid: context.tid, sid: context.sid, caught: caught)
    }

    @concurrent
    nonisolated private static func search(list: FRLGSeedList, version: FRLGVersion, attempted: FRLGInitialSeed,
                                           targetFrame: UInt32, seedLeeway: Int, frames: ClosedRange<UInt32>,
                                           teachyTVFrames: ClosedRange<UInt32>?, method: PFMethod,
                                           template: PFStaticTemplateRef, tid: UInt16, sid: UInt16,
                                           caught: FRLGCatch) async -> [FRLGCalibrationHit] {
        FRLGCalibration.search(list: list, version: version, attempted: attempted, targetFrame: targetFrame,
                               seedLeeway: seedLeeway, frames: frames, teachyTVFrames: teachyTVFrames,
                               method: method, template: template, tid: tid, sid: sid, caught: caught)
    }

    @ViewBuilder
    private func resultsCard(_ hits: [FRLGCalibrationHit]) -> some View {
        SectionCard(title: "What You Hit", icon: "scope") {
            if let applied {
                Label("Calibration updated from seed \(String(format: "%04X", applied.seed)): seed press \(signed(search.seedCalibrationMS)) ms, final press \(signed(search.frameCalibrationMS)) ms.",
                      systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    onSendToTimer(attempted, search.preTimerMS(attempted), search.targetFrame(attempted).frame)
                } label: {
                    Label("Send to Timer Again", systemImage: "timer")
                }
                .buttonStyle(.primaryAction)
            }
            if hits.isEmpty {
                Text("Nothing within \(seedLeeway) seeds and \(frameLeeway) frames of your attempt makes this Pokémon. Check the nature, gender and stats, or widen the search.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if searchedAnyNature {
                Text("With any nature and IVs, nearly every frame matches. Pick its nature and enter its stats to find what you hit.")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Nearest your attempt first. More than one can fit: pick the one closest to how your presses felt.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(hits.prefix(50), id: \.self) { hit in
                hitRow(hit)
                Divider()
            }
        }
    }

    private func hitRow(_ hit: FRLGCalibrationHit) -> some View {
        let hitSeed = FRLGInitialSeed(seed: hit.seed, setting: attempted.setting, held: attempted.held, seedTime: hit.seedTime)
        let seedMS = search.seedTimeMS(hitSeed) - search.seedTimeMS(attempted)
        let frames = Int(search.hitFrame(hit)) - Int(search.targetFrame(attempted).frame)
        let exact = hit.seedOffset == 0 && frames == 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Seed \(String(format: "%04X", hit.seed))").font(.system(.subheadline, design: .monospaced).bold())
                Spacer()
                Text(exact ? "Your target" : "\(placeName(hit.seedOffset)) · frame \(signed(frames))")
                    .font(.caption).foregroundStyle(exact ? .green : .primary)
            }
            Text("Seed press \(signed(seedMS)) ms · advance \(hit.advances.formatted())"
                 + (hit.teachyTVFrames > 0 ? " (\(hit.teachyTVFrames) Teachy TV frames)" : ""))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Text((["IVs " + hit.ivs.map(String.init).joined(separator: "/"), pfNatureNames[Int(hit.nature)],
                   genderName(hit.gender)] + (hit.shiny > 0 ? ["Shiny"] : [])).compactMap { $0 }.joined(separator: " · "))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            if !exact {
                Button("Calibrate from This") {
                    search.calibrate(attempted: attempted, hit: hit)
                    applied = hit
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
    }

    private func genderName(_ gender: UInt8) -> String? {
        switch gender {
        case 0: "Male"
        case 1: "Female"
        default: nil
        }
    }

    /// "Same seed", "3 seeds later", "1 seed earlier".
    private func placeName(_ offset: Int) -> String {
        switch offset {
        case 0: "Same seed"
        case 1: "1 seed later"
        case -1: "1 seed earlier"
        default: offset > 0 ? "\(offset) seeds later" : "\(-offset) seeds earlier"
        }
    }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
}
