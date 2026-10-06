//
//  Gen5Profile.swift
//  PKReference
//
//  A DS's Gen 5 parameters (PokéFinder's Profile5): what Black, White,
//  Black 2 and White 2 make their seed from besides the date and time. The
//  DS Parameters card shows and keeps them (the Finder's `finder_gen5*`
//  settings), and the calibrator finds them from a game you start, with
//  PokéFinder's ProfileSearcher5. RNG fixes PR 12.
//

import SwiftUI

// MARK: - Parameters

/// A DS's Gen 5 parameters. All zeros, which no DS has, until they're found.
nonisolated struct Gen5DSParameters: Codable, Hashable, Sendable {
    var mac: UInt64 = 0
    var timer0Min: UInt16 = 0
    var timer0Max: UInt16 = 0
    var vcount: UInt8 = 0
    var gxstat: UInt8 = 0
    var vframe: UInt8 = 0
    /// Which counts of held buttons a search tries: none, then 1 to 8.
    var keypresses: [Bool] = [true] + Array(repeating: false, count: 8)
    var skipLR = false
    /// PokéFinder's DSType: 0 DS, 1 DSi, 2 3DS.
    var dsType: UInt8 = 0
    /// PokéFinder's Language: English, French, German, Italian, Japanese,
    /// Korean, Spanish.
    var language: UInt8 = 0
    var memoryLink = false
    var shinyCharm = false

    /// Not found yet: a DS has a MAC address, a Timer0 and a VCount.
    var isUnset: Bool { mac == 0 || timer0Max == 0 || vcount == 0 }

    var pf: PFProfile5 {
        let k = (0..<9).map { $0 < keypresses.count && keypresses[$0] }
        return PFProfile5(mac: mac, keypresses: (k[0], k[1], k[2], k[3], k[4], k[5], k[6], k[7], k[8]),
                          vcount: vcount, gxstat: gxstat, vframe: vframe, skipLR: skipLR,
                          timer0Min: timer0Min, timer0Max: timer0Max, memoryLink: memoryLink,
                          shinyCharm: shinyCharm, dsType: dsType, language: language)
    }

    /// The calibrator's starting ranges for a game and DS, as PokéFinder's
    /// calibrator sets them (`ProfileCalibrator5::updateParameters`): ranges
    /// to search, not any console's values.
    static func calibratorRanges(game: FinderGameVersion, dsType: UInt8)
        -> (vcount: ClosedRange<Int>, timer0: ClosedRange<Int>) {
        let blackWhite = game == .black || game == .white
        if dsType == 0 {
            return blackWhite ? (0x50...0x70, 0xC60...0xCA0) : (0x70...0x90, 0x10E0...0x1130)
        }
        return blackWhite ? (0x80...0x92, 0x1140...0x12D0) : (0xA0...0xC0, 0x1400...0x1900)
    }

    static let dsTypes = ["DS / DS Lite", "DSi / DSi XL", "3DS"]
    static let languages = ["English", "French", "German", "Italian", "Japanese", "Korean", "Spanish"]
}

extension FinderProfile {
    /// A Gen 5 profile's DS parameters.
    var gen5Parameters: Gen5DSParameters {
        get {
            Gen5DSParameters(mac: mac, timer0Min: timer0Min, timer0Max: timer0Max, vcount: vcount,
                             gxstat: gxstat, vframe: vframe,
                             keypresses: keypresses.count == 9 ? keypresses : Gen5DSParameters().keypresses,
                             skipLR: skipLR, dsType: dsType, language: language,
                             memoryLink: memoryLink, shinyCharm: shinyCharm)
        }
        set {
            mac = newValue.mac
            timer0Min = newValue.timer0Min
            timer0Max = newValue.timer0Max
            vcount = newValue.vcount
            gxstat = newValue.gxstat
            vframe = newValue.vframe
            keypresses = newValue.keypresses
            skipLR = newValue.skipLR
            dsType = newValue.dsType
            language = newValue.language
            memoryLink = newValue.memoryLink
            shinyCharm = newValue.shinyCharm
        }
    }
}

/// The DS's buttons, in PokéFinder's `Buttons` bit order.
enum Gen5Buttons {
    static let names = ["R", "L", "X", "Y", "A", "B", "Select", "Start", "Right", "Left", "Up", "Down"]

    /// "None", or the buttons held: "A + Start".
    static func describe(_ bits: UInt16) -> String {
        let held = names.indices.filter { bits & (1 << $0) != 0 }.map { names[$0] }
        return held.isEmpty ? "None" : held.joined(separator: " + ")
    }
}

/// The stored DS parameters (the Finder's settings), shared by every Gen 5
/// screen.
enum Gen5DSParameterKeys {
    static let mac = "finder_gen5mac"
    static let timer0Min = "finder_gen5timer0Min"
    static let timer0Max = "finder_gen5timer0Max"
    static let vcount = "finder_gen5vcount"
    static let gxstat = "finder_gen5gxstat"
    static let vframe = "finder_gen5vframe"
    static let keypresses = "finder_gen5keypresses"
    static let skipLR = "finder_gen5skipLR"
    static let dsType = "finder_gen5dsType"
    static let language = "finder_gen5language"
    static let memoryLink = "finder_gen5memoryLink"
    static let shinyCharm = "finder_gen5shinyCharm"

    /// Keypresses stored as nine 0s and 1s.
    static func keypresses(from text: String) -> [Bool] {
        let bits = text.map { $0 == "1" }
        return bits.count == 9 ? bits : Gen5DSParameters().keypresses
    }

    static func text(from keypresses: [Bool]) -> String {
        keypresses.map { $0 ? "1" : "0" }.joined()
    }
}

// MARK: - Hex field

/// A number entered and shown in hexadecimal, as PokéFinder and the guides
/// give Timer0, VCount, GxStat and VFrame.
struct HexField: View {
    let label: String
    @Binding var value: Int
    var digits = 4
    var range: ClosedRange<Int> = 0...0xFFFF
    @State private var text = ""

    var body: some View {
        AdaptiveStack(spacing: 6) {
            Text(label).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField(String(repeating: "0", count: digits), text: $text)
                .textFieldStyle(.roundedBorder).scaledWidth(100).multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
                .onAppear { text = String(format: "%X", value) }
                .onChange(of: text) {
                    let filtered = String(text.uppercased().filter(\.isHexDigit).prefix(digits))
                    if filtered != text { text = filtered }
                    if let n = Int(filtered, radix: 16) { value = n.clamped(to: range) }
                }
                .onChange(of: value) {
                    if Int(text, radix: 16) != value { text = String(format: "%X", value) }
                }
        }
    }
}

// MARK: - DS Parameters card

/// The DS's Gen 5 parameters, with Find My Parameters, shared by the Finder
/// and the TID/SID tool.
struct Gen5DSParametersCard: View {
    let game: FinderGameVersion
    /// Lists the saved Gen 5 profiles to load (the TID/SID tool; the Finder
    /// loads them under Trainer).
    var showsProfiles = false

    @AppStorage(Gen5DSParameterKeys.mac) private var macText = ""
    @AppStorage(Gen5DSParameterKeys.timer0Min) private var timer0Min = 0
    @AppStorage(Gen5DSParameterKeys.timer0Max) private var timer0Max = 0
    @AppStorage(Gen5DSParameterKeys.vcount) private var vcount = 0
    @AppStorage(Gen5DSParameterKeys.gxstat) private var gxstat = 0
    @AppStorage(Gen5DSParameterKeys.vframe) private var vframe = 0
    @AppStorage(Gen5DSParameterKeys.keypresses) private var keypressText = "100000000"
    @AppStorage(Gen5DSParameterKeys.skipLR) private var skipLR = false
    @AppStorage(Gen5DSParameterKeys.dsType) private var dsType: UInt8 = 0
    @AppStorage(Gen5DSParameterKeys.language) private var language: UInt8 = 0
    @AppStorage(Gen5DSParameterKeys.memoryLink) private var memoryLink = false
    @AppStorage(Gen5DSParameterKeys.shinyCharm) private var shinyCharm = false

    @State private var calibrating = false
    @State private var profiles: [FinderProfile] = []

    /// The parameters as stored.
    static func stored(_ defaults: UserDefaults = .standard) -> Gen5DSParameters {
        Gen5DSParameters(
            mac: UInt64(defaults.string(forKey: Gen5DSParameterKeys.mac)?.replacingOccurrences(of: ":", with: "") ?? "", radix: 16) ?? 0,
            timer0Min: UInt16(clamping: defaults.integer(forKey: Gen5DSParameterKeys.timer0Min)),
            timer0Max: UInt16(clamping: defaults.integer(forKey: Gen5DSParameterKeys.timer0Max)),
            vcount: UInt8(clamping: defaults.integer(forKey: Gen5DSParameterKeys.vcount)),
            gxstat: UInt8(clamping: defaults.integer(forKey: Gen5DSParameterKeys.gxstat)),
            vframe: UInt8(clamping: defaults.integer(forKey: Gen5DSParameterKeys.vframe)),
            keypresses: Gen5DSParameterKeys.keypresses(from: defaults.string(forKey: Gen5DSParameterKeys.keypresses) ?? ""),
            skipLR: defaults.bool(forKey: Gen5DSParameterKeys.skipLR),
            dsType: UInt8(clamping: defaults.integer(forKey: Gen5DSParameterKeys.dsType)),
            language: UInt8(clamping: defaults.integer(forKey: Gen5DSParameterKeys.language)),
            memoryLink: defaults.bool(forKey: Gen5DSParameterKeys.memoryLink),
            shinyCharm: defaults.bool(forKey: Gen5DSParameterKeys.shinyCharm))
    }

    /// Stores `p` as the DS parameters.
    static func store(_ p: Gen5DSParameters, _ defaults: UserDefaults = .standard) {
        defaults.set(String(format: "%012llX", p.mac), forKey: Gen5DSParameterKeys.mac)
        defaults.set(Int(p.timer0Min), forKey: Gen5DSParameterKeys.timer0Min)
        defaults.set(Int(p.timer0Max), forKey: Gen5DSParameterKeys.timer0Max)
        defaults.set(Int(p.vcount), forKey: Gen5DSParameterKeys.vcount)
        defaults.set(Int(p.gxstat), forKey: Gen5DSParameterKeys.gxstat)
        defaults.set(Int(p.vframe), forKey: Gen5DSParameterKeys.vframe)
        defaults.set(Gen5DSParameterKeys.text(from: p.keypresses), forKey: Gen5DSParameterKeys.keypresses)
        defaults.set(p.skipLR, forKey: Gen5DSParameterKeys.skipLR)
        defaults.set(Int(p.dsType), forKey: Gen5DSParameterKeys.dsType)
        defaults.set(Int(p.language), forKey: Gen5DSParameterKeys.language)
        defaults.set(p.memoryLink, forKey: Gen5DSParameterKeys.memoryLink)
        defaults.set(p.shinyCharm, forKey: Gen5DSParameterKeys.shinyCharm)
    }

    private var parameters: Gen5DSParameters {
        Gen5DSParameters(mac: UInt64(macText.replacingOccurrences(of: ":", with: ""), radix: 16) ?? 0,
                         timer0Min: UInt16(clamping: timer0Min), timer0Max: UInt16(clamping: timer0Max),
                         vcount: UInt8(clamping: vcount), gxstat: UInt8(clamping: gxstat), vframe: UInt8(clamping: vframe),
                         keypresses: Gen5DSParameterKeys.keypresses(from: keypressText), skipLR: skipLR,
                         dsType: dsType, language: language, memoryLink: memoryLink, shinyCharm: shinyCharm)
    }

    private func apply(_ p: Gen5DSParameters) {
        Self.store(p)
    }

    private var keypresses: Binding<[Bool]> {
        Binding(get: { Gen5DSParameterKeys.keypresses(from: keypressText) },
                set: { keypressText = Gen5DSParameterKeys.text(from: $0) })
    }

    var body: some View {
        SectionCard(title: "DS Parameters", icon: "wifi") {
            if parameters.isUnset {
                Text("Your DS's parameters aren't set, so a search can't find the seeds your DS makes. Find My Parameters works them out from a game you start and what it gives you.")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                calibrating = true
            } label: {
                Label("Find My Parameters", systemImage: "scope")
            }
            .buttonStyle(.borderless)

            if showsProfiles {
                let gen5 = profiles.filter(\.isGen5)
                if !gen5.isEmpty {
                    LabeledContent("Profile") {
                        Menu("Load") {
                            ForEach(gen5) { profile in
                                Button(profile.displayName) { apply(profile.gen5Parameters) }
                            }
                        }
                    }
                }
            }

            HStack {
                Text("MAC Address")
                Spacer()
                TextField("0009BF123456", text: $macText)
                    .textFieldStyle(.roundedBorder)
                    .scaledWidth(160)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
            }
            HexField(label: "Timer0 Min (hex)", value: $timer0Min)
            HexField(label: "Timer0 Max (hex)", value: $timer0Max)
            HexField(label: "VCount (hex)", value: $vcount, digits: 2, range: 0...0xFF)
            HexField(label: "GxStat (hex)", value: $gxstat, digits: 2, range: 0...0xFF)
            HexField(label: "VFrame (hex)", value: $vframe, digits: 2, range: 0...0xFF)

            LabeledContent("DS Type") {
                Picker("DS Type", selection: $dsType) {
                    ForEach(Gen5DSParameters.dsTypes.indices, id: \.self) { Text(Gen5DSParameters.dsTypes[$0]).tag(UInt8($0)) }
                }
                .labelsHidden()
            }
            LabeledContent("Language") {
                Picker("Language", selection: $language) {
                    ForEach(Gen5DSParameters.languages.indices, id: \.self) { Text(Gen5DSParameters.languages[$0]).tag(UInt8($0)) }
                }
                .labelsHidden()
            }

            Toggle("Skip L/R", isOn: $skipLR)
            Toggle("Memory Link", isOn: $memoryLink)
            if game == .black2 || game == .white2 {
                Toggle("Shiny Charm", isOn: $shinyCharm)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Keypresses").font(.subheadline).foregroundStyle(.secondary)
                let labels = ["None", "1 Button", "2 Buttons", "3 Buttons",
                              "4 Buttons", "5 Buttons", "6 Buttons", "7 Buttons", "8 Buttons"]
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 4) {
                    ForEach(0..<9, id: \.self) { i in
                        Toggle(labels[i], isOn: keypresses[i])
                            .toggleStyle(.button)
                            .font(.caption)
                    }
                }
            }
        }
        .onAppear { profiles = FinderProfileStore.load() }
        .sheet(isPresented: $calibrating) {
            NavigationStack {
                Gen5CalibratorView(game: game, current: parameters) { found in
                    apply(found)
                    calibrating = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { calibrating = false }
                    }
                }
            }
            .sheetSize()
        }
    }
}

// MARK: - Calibrator

/// PokéFinder's profile calibrator: start the game at a known date and
/// time, then the parameters that make what it gives you (a Pokémon's IVs,
/// or a seed you know).
struct Gen5CalibratorView: View {
    let game: FinderGameVersion
    let current: Gen5DSParameters
    /// The parameters found, with the rest kept from `current`.
    let use: (Gen5DSParameters) -> Void

    enum Kind: String, CaseIterable, Identifiable {
        case ivs = "IVs"
        case seed = "Seed"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .ivs
    @State private var dsType: UInt8 = 0
    @State private var language: UInt8 = 0
    @State private var macText = ""
    @State private var buttons: UInt16 = 0
    @State private var date = Date()
    @State private var hour = 0
    @State private var minute = 0
    @State private var minSecond = 0
    @State private var maxSecond = 59
    @State private var minVCount = 0
    @State private var maxVCount = 0
    @State private var minTimer0 = 0
    @State private var maxTimer0 = 0
    @State private var minGxStat = 6
    @State private var maxGxStat = 6
    @State private var minVFrame = 0
    @State private var maxVFrame = 10
    @State private var minIVs: [Int] = Array(repeating: 0, count: 6)
    @State private var maxIVs: [Int] = Array(repeating: 31, count: 6)
    @State private var seedText = ""

    @State private var results: [PFBridge.ProfileResult5] = []
    @State private var progress = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var handle: OpaquePointer?
    @State private var finished = false
    @State private var started = false

    private static let statNames = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    var body: some View {
        ScrollView {
            CardStack {
                SectionCard(title: "Your Game", icon: "gamecontroller") {
                    Text("Start \(game.rawValue) at a date and time you note, holding the buttons below if any. Then, for IVs, check the IVs of a Pokémon made at the first IV frame; or enter a seed you know.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    HStack {
                        Text("Time")
                        Spacer()
                        LiveIntField("H", value: $hour, range: 0...23, grouping: false)
                            .clamping($hour, to: 0...23)
                            .textFieldStyle(.roundedBorder).scaledWidth(44)
                        Text(":")
                        LiveIntField("M", value: $minute, range: 0...59, grouping: false)
                            .clamping($minute, to: 0...59)
                            .textFieldStyle(.roundedBorder).scaledWidth(44)
                    }
                    RNGIntField(label: "Seconds From", value: $minSecond, range: 0...59)
                    RNGIntField(label: "Seconds To", value: $maxSecond, range: 0...59)
                    LabeledContent("Buttons Held") {
                        Menu(Gen5Buttons.describe(buttons)) {
                            ForEach(Gen5Buttons.names.indices, id: \.self) { i in
                                Toggle(Gen5Buttons.names[i], isOn: Binding(
                                    get: { buttons & (1 << i) != 0 },
                                    set: { buttons = $0 ? buttons | (1 << i) : buttons & ~(1 << i) }))
                            }
                        }
                    }
                }

                SectionCard(title: "Your DS", icon: "wifi") {
                    HStack {
                        Text("MAC Address")
                        Spacer()
                        TextField("0009BF123456", text: $macText)
                            .textFieldStyle(.roundedBorder).scaledWidth(160).multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            #endif
                    }
                    LabeledContent("DS Type") {
                        Picker("DS Type", selection: $dsType) {
                            ForEach(Gen5DSParameters.dsTypes.indices, id: \.self) { Text(Gen5DSParameters.dsTypes[$0]).tag(UInt8($0)) }
                        }
                        .labelsHidden()
                    }
                    LabeledContent("Language") {
                        Picker("Language", selection: $language) {
                            ForEach(Gen5DSParameters.languages.indices, id: \.self) { Text(Gen5DSParameters.languages[$0]).tag(UInt8($0)) }
                        }
                        .labelsHidden()
                    }
                    Text("The ranges to search start at PokéFinder's for your game and DS type.")
                        .font(.caption).foregroundStyle(.secondary)
                    HexField(label: "VCount From", value: $minVCount, digits: 2, range: 0...0xFF)
                    HexField(label: "VCount To", value: $maxVCount, digits: 2, range: 0...0xFF)
                    HexField(label: "Timer0 From", value: $minTimer0)
                    HexField(label: "Timer0 To", value: $maxTimer0)
                    HexField(label: "GxStat From", value: $minGxStat, digits: 2, range: 0...0xFF)
                    HexField(label: "GxStat To", value: $maxGxStat, digits: 2, range: 0...0xFF)
                    HexField(label: "VFrame From", value: $minVFrame, digits: 2, range: 0...0xFF)
                    HexField(label: "VFrame To", value: $maxVFrame, digits: 2, range: 0...0xFF)
                }
                .onChange(of: dsType) { setRanges() }

                SectionCard(title: "What You Got", icon: "checkmark.seal") {
                    Picker("Kind", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if kind == .ivs {
                        Text("The IVs (or ranges, if not sure) of the Pokémon.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(0..<6, id: \.self) { i in
                            HStack {
                                Text(Self.statNames[i]).frame(width: 40, alignment: .leading)
                                Spacer()
                                LiveIntField("0", value: $minIVs[i], range: 0...31, grouping: false)
                                    .clamping($minIVs[i], to: 0...31)
                                    .textFieldStyle(.roundedBorder).scaledWidth(50).multilineTextAlignment(.trailing)
                                Text("–")
                                LiveIntField("31", value: $maxIVs[i], range: 0...31, grouping: false)
                                    .clamping($maxIVs[i], to: 0...31)
                                    .textFieldStyle(.roundedBorder).scaledWidth(50).multilineTextAlignment(.trailing)
                            }
                        }
                    } else {
                        HStack {
                            Text("Seed (hex)")
                            Spacer()
                            TextField("0123456789ABCDEF", text: $seedText)
                                .textFieldStyle(.roundedBorder).scaledWidth(200).multilineTextAlignment(.trailing)
                                .font(.body.monospacedDigit())
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.characters)
                                #endif
                                .hexDigitsOnly($seedText, count: 16)
                        }
                    }
                }

                searchButton

                if let invalid = invalidReason {
                    Text(invalid)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if results.count >= searchResultLimit {
                    Text(searchResultLimitNote)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if finished && results.isEmpty {
                    Text("Nothing found. Check the date, time and buttons, or widen the seconds or the ranges.")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !results.isEmpty {
                    SectionCard(title: "Parameters Found (\(results.count))", icon: "list.bullet") {
                        Text("Tap one to use it. More than one can fit: calibrate again with another game to tell them apart.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(results.prefix(200)) { r in
                            Button {
                                use(found(r))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(format: "Timer0 %X  VCount %X  VFrame %X  GxStat %X", r.timer0, r.vcount, r.vframe, r.gxstat))
                                        .font(.system(.caption, design: .monospaced))
                                    Text(String(format: "Second %d  Seed %016llX", r.second, r.seed))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
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
            .padding()
        }
        .dismissesKeyboard()
        .navigationTitle("Find My Parameters")
        .onAppear {
            guard !started else { return }
            started = true
            dsType = current.dsType
            language = current.language
            macText = current.mac == 0 ? "" : String(format: "%012llX", current.mac)
            // The DS's clock is local time: start from yours.
            let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
            hour = now.hour ?? 0
            minute = now.minute ?? 0
            setRanges()
        }
        .onDisappear { cancel() }
    }

    private func setRanges() {
        let ranges = Gen5DSParameters.calibratorRanges(game: game, dsType: dsType)
        minVCount = ranges.vcount.lowerBound
        maxVCount = ranges.vcount.upperBound
        minTimer0 = ranges.timer0.lowerBound
        maxTimer0 = ranges.timer0.upperBound
    }

    private var mac: UInt64? { UInt64(macText.replacingOccurrences(of: ":", with: ""), radix: 16) }

    /// Why Search is off.
    private var invalidReason: String? {
        if mac == nil || mac == 0 { return "Enter your DS's MAC address: Wi-Fi settings show it." }
        if minSecond > maxSecond || minVCount > maxVCount || minTimer0 > maxTimer0
            || minGxStat > maxGxStat || minVFrame > maxVFrame {
            return "A From is above its To."
        }
        if kind == .seed && UInt64(seedText, radix: 16) == nil { return "Enter the seed, in hex." }
        if kind == .ivs && (0..<6).contains(where: { minIVs[$0] > maxIVs[$0] }) { return "An IV's low end is above its high end." }
        // Any IVs fit every parameter.
        if kind == .ivs && minIVs.allSatisfy({ $0 == 0 }) && maxIVs.allSatisfy({ $0 == 31 }) {
            return "Enter the Pokémon's IVs: with every IV from 0 to 31, every set of parameters fits."
        }
        return nil
    }

    private var searchButton: some View {
        VStack(spacing: 8) {
            if searchTask != nil {
                ProgressView(value: Double(progress), total: 100)
                    .progressViewStyle(.linear)
                Text("\(progress)% — \(results.count) found")
                    .font(.caption).foregroundStyle(.secondary)
                Button { cancel() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.primaryAction)
                    .tint(.red)
            } else {
                Button { search() } label: { Label("Search", systemImage: "magnifyingglass") }
                    .buttonStyle(.primaryAction)
                    .disabled(invalidReason != nil)
            }
        }
    }

    /// The parameters found, with the rest kept from `current`.
    private func found(_ r: PFBridge.ProfileResult5) -> Gen5DSParameters {
        var p = current
        p.mac = mac ?? current.mac
        p.dsType = dsType
        p.language = language
        p.timer0Min = r.timer0
        p.timer0Max = r.timer0
        p.vcount = r.vcount
        p.vframe = r.vframe
        p.gxstat = r.gxstat
        return p
    }

    private func search() {
        cancel()
        results = []
        finished = false
        progress = 0
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let mac,
              let h = PFBridge.profileSearch5Start(
                bySeed: kind == .seed, game: game.pfGame, language: language, dsType: dsType, mac: mac,
                buttons: buttons,
                year: UInt16(clamping: parts.year ?? 2000), month: UInt8(clamping: parts.month ?? 1),
                day: UInt8(clamping: parts.day ?? 1), hour: UInt8(clamping: hour), minute: UInt8(clamping: minute),
                seconds: UInt8(clamping: minSecond)...UInt8(clamping: maxSecond),
                vcount: UInt8(clamping: minVCount)...UInt8(clamping: maxVCount),
                timer0: UInt16(clamping: minTimer0)...UInt16(clamping: maxTimer0),
                gxstat: UInt8(clamping: minGxStat)...UInt8(clamping: maxGxStat),
                vframe: UInt8(clamping: minVFrame)...UInt8(clamping: maxVFrame),
                ivMin: minIVs.map { UInt8(clamping: $0) }, ivMax: maxIVs.map { UInt8(clamping: $0) },
                seed: UInt64(seedText, radix: 16) ?? 0)
        else { return }
        handle = h
        searchTask = Task {
            while !PFBridge.profileSearch5Done(h) {
                try? await Task.sleep(for: .milliseconds(150))
                guard handle == h else { break }
                progress = PFBridge.profileSearch5Progress(h)
                // At most searchResultLimit, as every RNG search keeps.
                results.append(contentsOf: PFBridge.profileSearch5Results(h).prefix(max(0, searchResultLimit - results.count)))
                if results.count >= searchResultLimit { PFBridge.profileSearch5Cancel(h) }
            }
            if handle == h {
                results.append(contentsOf: PFBridge.profileSearch5Results(h).prefix(max(0, searchResultLimit - results.count)))
                progress = 100
                finished = true
                handle = nil
                searchTask = nil
            }
            // The thread has ended (or been told to), so freeing doesn't wait.
            await Task.detached { PFBridge.profileSearch5Free(h) }.value
        }
    }

    private func cancel() {
        if let handle { PFBridge.profileSearch5Cancel(handle) }
        handle = nil
        searchTask = nil
    }
}

// MARK: - Bridge

nonisolated extension PFBridge {
    struct ProfileResult5: Identifiable, Hashable, Sendable {
        var id: String { "\(seed)-\(timer0)-\(vcount)-\(vframe)-\(gxstat)-\(second)" }
        let seed: UInt64
        let timer0: UInt16
        let vcount: UInt8
        let vframe: UInt8
        let gxstat: UInt8
        let second: UInt8
    }

    static func profileSearch5Start(bySeed: Bool, game: PFGame, language: UInt8, dsType: UInt8, mac: UInt64,
                                    buttons: UInt16, year: UInt16, month: UInt8, day: UInt8, hour: UInt8, minute: UInt8,
                                    seconds: ClosedRange<UInt8>, vcount: ClosedRange<UInt8>, timer0: ClosedRange<UInt16>,
                                    gxstat: ClosedRange<UInt8>, vframe: ClosedRange<UInt8>,
                                    ivMin: [UInt8] = [0, 0, 0, 0, 0, 0], ivMax: [UInt8] = [31, 31, 31, 31, 31, 31],
                                    seed: UInt64 = 0) -> OpaquePointer? {
        pf_profileSearch5_start(bySeed, game.rawValue, language, dsType, mac, buttons,
                                year, month, day, hour, minute,
                                seconds.lowerBound, seconds.upperBound, vcount.lowerBound, vcount.upperBound,
                                timer0.lowerBound, timer0.upperBound, gxstat.lowerBound, gxstat.upperBound,
                                vframe.lowerBound, vframe.upperBound, ivMin, ivMax, seed).map(OpaquePointer.init)
    }

    static func profileSearch5Progress(_ handle: OpaquePointer) -> Int {
        Int(pf_profileSearch5_progress(UnsafeMutableRawPointer(handle)))
    }

    static func profileSearch5Done(_ handle: OpaquePointer) -> Bool {
        pf_profileSearch5_done(UnsafeMutableRawPointer(handle))
    }

    static func profileSearch5Results(_ handle: OpaquePointer) -> [ProfileResult5] {
        var count: Int32 = 0
        guard let ptr = pf_profileSearch5_getResults(UnsafeMutableRawPointer(handle), &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return ProfileResult5(seed: r.seed, timer0: r.timer0, vcount: r.vcount, vframe: r.vframe,
                                  gxstat: r.gxstat, second: r.second)
        }
    }

    static func profileSearch5Cancel(_ handle: OpaquePointer) {
        pf_profileSearch5_cancel(UnsafeMutableRawPointer(handle))
    }

    static func profileSearch5Free(_ handle: OpaquePointer) {
        pf_profileSearch5_free(UnsafeMutableRawPointer(handle))
    }

    /// The seed `profile`'s DS makes for a game started at that time, with
    /// `buttons` held, at `timer0`.
    static func gen5InitialSeed(game: PFGame, profile: Gen5DSParameters, timer0: UInt16, buttons: UInt16 = 0,
                                year: UInt16, month: UInt8, day: UInt8,
                                hour: UInt8, minute: UInt8, second: UInt8) -> UInt64 {
        var p = profile.pf
        return pf_gen5InitialSeed(game.rawValue, &p, timer0, buttons, year, month, day, hour, minute, second)
    }

    // MARK: Gen 5 IDs

    struct IDSearchResult5: Identifiable, Hashable, Sendable {
        var id: String { "\(seed)-\(timer0)-\(buttons)-\(advances)" }
        let year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int
        let seed: UInt64
        let timer0: UInt16
        let buttons: UInt16
        let advances: UInt32
        let tid: UInt16
        let sid: UInt16
        let tsv: UInt16

        var dateTimeText: String {
            String(format: "%04d/%02d/%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
        }
    }

    private static func idResults5(_ ptr: UnsafeMutablePointer<PFIDSearchResult5>?, count: Int32) -> [IDSearchResult5] {
        guard let ptr else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { i in
            let r = ptr[i]
            return IDSearchResult5(year: Int(r.dateTime.year), month: Int(r.dateTime.month), day: Int(r.dateTime.day),
                                   hour: Int(r.dateTime.hour), minute: Int(r.dateTime.minute), second: Int(r.dateTime.second),
                                   seed: r.seed, timer0: r.timer0, buttons: r.buttons, advances: r.advances,
                                   tid: r.tid, sid: r.sid, tsv: r.tsv)
        }
    }

    /// Gen 5 IDs over every second of the dates: nil when the dates or the
    /// profile's Timer0 range are the wrong way round.
    static func idSearch5Start(game: PFGame, profile: Gen5DSParameters,
                               start: (year: UInt16, month: UInt8, day: UInt8),
                               end: (year: UInt16, month: UInt8, day: UInt8),
                               maxAdvances: UInt32, pid: UInt32 = 0, checkPID: Bool = false, checkXOR: Bool = false,
                               tid: UInt16 = 0, filterTID: Bool = false,
                               sid: UInt16 = 0, filterSID: Bool = false) -> OpaquePointer? {
        var p = profile.pf
        return pf_idSearch5_start(game.rawValue, &p, start.year, start.month, start.day, end.year, end.month, end.day,
                                  maxAdvances, pid, checkPID, checkXOR, tid, filterTID, sid, filterSID)
            .map(OpaquePointer.init)
    }

    static func idSearch5Progress(_ handle: OpaquePointer) -> Int {
        Int(pf_idSearch5_progress(UnsafeMutableRawPointer(handle)))
    }

    static func idSearch5Done(_ handle: OpaquePointer) -> Bool {
        pf_idSearch5_done(UnsafeMutableRawPointer(handle))
    }

    static func idSearch5Results(_ handle: OpaquePointer) -> [IDSearchResult5] {
        var count: Int32 = 0
        let ptr = pf_idSearch5_getResults(UnsafeMutableRawPointer(handle), &count)
        return idResults5(ptr, count: count)
    }

    static func idSearch5Cancel(_ handle: OpaquePointer) {
        pf_idSearch5_cancel(UnsafeMutableRawPointer(handle))
    }

    static func idSearch5Free(_ handle: OpaquePointer) {
        pf_idSearch5_free(UnsafeMutableRawPointer(handle))
    }

    /// PokéFinder's IDGenerator5 from one seed: each advance's IDs.
    static func idGenerate5(seed: UInt64, game: PFGame, profile: Gen5DSParameters,
                            maxAdvances: UInt32) -> [(advances: UInt32, tid: UInt16, sid: UInt16)] {
        let p = profile
        var count: Int32 = 0
        let k = (0..<9).map { $0 < p.keypresses.count && p.keypresses[$0] }
        guard let ptr = pf_idGenerate5(seed, 0, maxAdvances, 0, false, false, 0, 0, game.rawValue,
                                       p.mac, k, p.vcount, p.gxstat, p.vframe, p.skipLR, p.timer0Min, p.timer0Max,
                                       p.memoryLink, p.shinyCharm, p.dsType, p.language,
                                       0, false, 0, false, &count) else { return [] }
        defer { pf_freeResults(ptr) }
        return (0..<Int(count)).map { (ptr[$0].advances, ptr[$0].tid, ptr[$0].sid) }
    }

    /// The seeds that gave `tid`, for a game started in that minute.
    static func idFind5(game: PFGame, profile: Gen5DSParameters, tid: UInt16,
                        year: UInt16, month: UInt8, day: UInt8, hour: UInt8, minute: UInt8,
                        seconds: ClosedRange<UInt8>, maxAdvances: UInt32) -> [IDSearchResult5] {
        var p = profile.pf
        var count: Int32 = 0
        let ptr = pf_idFind5(game.rawValue, &p, tid, year, month, day, hour, minute,
                             seconds.lowerBound, seconds.upperBound, maxAdvances, &count)
        return idResults5(ptr, count: count)
    }
}

extension View {
    /// Keeps `text` to `count` hex digits, upper case, as typed.
    func hexDigitsOnly(_ text: Binding<String>, count: Int) -> some View {
        onChange(of: text.wrappedValue) {
            let filtered = String(text.wrappedValue.uppercased().filter(\.isHexDigit).prefix(count))
            if filtered != text.wrappedValue { text.wrappedValue = filtered }
        }
    }
}
