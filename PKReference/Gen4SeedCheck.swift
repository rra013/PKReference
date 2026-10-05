//
//  Gen4SeedCheck.swift
//  PKReference
//
//  Which Gen 4 seed you hit, as PokéFinder's (and RNG Reporter's) Seed to
//  Time calibration works it out: list the seeds a few delays and seconds
//  either side of the target, and narrow them down by what the game shows
//  right after loading. In Diamond, Pearl and Platinum that's the Pokétch's
//  Coin Toss; in HeartGold and SoulSilver, where the roamers moved to (the
//  Pokégear map) and Elm's or Irwin's calls. The delay you hit is the
//  Timer's Delay Hit.
//

import SwiftUI

/// A Gen 4 target as Seed to Time gives it: the DS clock's date and time,
/// to the second, and the delay.
nonisolated struct Gen4SeedTime: Codable, Hashable, Sendable {
    var year = 2000
    var month = 1
    var day = 1
    var hour = 0
    var minute = 0
    var second = 0
    var delay = 600

    /// PokéFinder's `Utilities4::calcSeed`.
    var seed: UInt32 {
        let ab = UInt32((month * day + minute + second) & 0xFF)
        return ((ab << 24) | (UInt32(hour & 0xFF) << 16)) &+ UInt32(truncatingIfNeeded: delay + year - 2000)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// The clock `seconds` later (earlier when negative), rolling over the
    /// minute, hour and day as the DS does (PokéFinder's `addSeconds`).
    func adding(seconds: Int) -> Gen4SeedTime {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = Self.calendar.date(from: components),
              let moved = Self.calendar.date(byAdding: .second, value: seconds, to: date) else { return self }
        let parts = Self.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: moved)
        var result = self
        result.year = parts.year ?? year
        result.month = parts.month ?? month
        result.day = parts.day ?? day
        result.hour = parts.hour ?? hour
        result.minute = parts.minute ?? minute
        result.second = parts.second ?? second
        return result
    }

    /// "07/28 17:54:23", as Seed to Time shows it.
    var timeText: String {
        String(format: "%02d/%02d %02d:%02d:%02d", month, day, hour, minute, second)
    }

    static func decoded(_ data: Data) -> Gen4SeedTime? {
        try? JSONDecoder().decode(Gen4SeedTime.self, from: data)
    }

    var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }
}

nonisolated enum Gen4SeedCheck {
    /// One seed to check.
    struct Candidate: Identifiable, Hashable, Sendable {
        /// Its clock time, when the target's is known.
        let time: Gen4SeedTime?
        let seed: UInt32
        let delay: Int
        let delayOffset: Int
        let secondOffset: Int
        /// The Pokétch's first coin flips (true is heads).
        let flips: [Bool]
        /// Elm's and Irwin's first calls after the roamers move: 0 E, 1 K, 2 P.
        let calls: [UInt8]
        /// PRNG advances the roamers took before the calls.
        let skips: UInt8
        /// Each roamer's new route (Raikou, Entei, Latias/Latios); 0 when inactive.
        let roamerRoutes: [UInt8]

        var id: UInt32 { seed }
        var closeness: Int { abs(delayOffset) + 1000 * abs(secondOffset) }
    }

    /// How many coin flips and calls each candidate keeps.
    static let sequenceLength = 20

    /// The seeds `delays` either side of the target's delay and `seconds`
    /// either side of its second (PokéFinder's `SeedToTimeCalculator4::calibrate`),
    /// nearest first.
    static func candidates(around target: Gen4SeedTime, delays: Int, seconds: Int,
                           roamers: [Bool] = [false, false, false], previousRoutes: [UInt8] = [0, 0, 0]) -> [Candidate] {
        var result: [Candidate] = []
        for secondOffset in -seconds...seconds {
            let time = target.adding(seconds: secondOffset)
            for delayOffset in -delays...delays where target.delay + delayOffset >= 0 {
                var at = time
                at.delay = target.delay + delayOffset
                result.append(candidate(seed: at.seed, time: at, delay: at.delay, delayOffset: delayOffset,
                                        secondOffset: secondOffset, roamers: roamers, previousRoutes: previousRoutes))
            }
        }
        return result.sorted { $0.closeness < $1.closeness }
    }

    /// The same around a seed whose clock time isn't known (the Finder's
    /// Generator): a second either way moves the seed's top byte by one,
    /// and a delay its low half.
    static func candidates(aroundSeed seed: UInt32, delays: Int, seconds: Int,
                           roamers: [Bool] = [false, false, false], previousRoutes: [UInt8] = [0, 0, 0]) -> [Candidate] {
        let ab = Int(seed >> 24), cd = (seed >> 16) & 0xFF, efgh = Int(seed & 0xFFFF)
        var result: [Candidate] = []
        for secondOffset in -seconds...seconds {
            for delayOffset in -delays...delays where (0...0xFFFF).contains(efgh + delayOffset) {
                let near = (UInt32((ab + secondOffset) & 0xFF) << 24) | (cd << 16) | UInt32(efgh + delayOffset)
                result.append(candidate(seed: near, time: nil, delay: efgh + delayOffset, delayOffset: delayOffset,
                                        secondOffset: secondOffset, roamers: roamers, previousRoutes: previousRoutes))
            }
        }
        return result.sorted { $0.closeness < $1.closeness }
    }

    private static func candidate(seed: UInt32, time: Gen4SeedTime?, delay: Int, delayOffset: Int, secondOffset: Int,
                                  roamers: [Bool], previousRoutes: [UInt8]) -> Candidate {
        let roamer = roamers.contains(true)
            ? PFBridge.hgssRoamers(seed: seed, active: roamers, previousRoutes: previousRoutes)
            : (skips: UInt8(0), routes: [UInt8](repeating: 0, count: 3))
        return Candidate(time: time, seed: seed, delay: delay, delayOffset: delayOffset, secondOffset: secondOffset,
                         flips: coinFlips(seed: seed, count: sequenceLength),
                         calls: calls(seed: seed, skips: roamer.skips, count: sequenceLength),
                         skips: roamer.skips, roamerRoutes: roamer.routes)
    }

    /// The candidates everything seen agrees with: the coin flips and calls
    /// so far (from the first), and each roamer's route that was checked
    /// (nil for not checked).
    static func matches(_ candidates: [Candidate], flips: [Bool] = [], calls: [UInt8] = [],
                        routes: [UInt8?] = [nil, nil, nil]) -> [Candidate] {
        candidates.filter { candidate in
            candidate.flips.starts(with: flips)
                && candidate.calls.starts(with: calls)
                && zip(routes, candidate.roamerRoutes).allSatisfy { seen, route in seen.map { $0 == route } ?? true }
        }
    }

    /// The Pokétch's Coin Toss: the Mersenne Twister from the seed, heads
    /// on an odd number (PokéFinder's `Utilities4::coinFlips`).
    static func coinFlips(seed: UInt32, count: Int) -> [Bool] {
        var mt = [UInt32](repeating: 0, count: 624)
        mt[0] = seed
        for i in 1..<624 {
            mt[i] = 1812433253 &* (mt[i - 1] ^ (mt[i - 1] >> 30)) &+ UInt32(i)
        }
        for i in 0..<624 {
            let y = (mt[i] & 0x8000_0000) | (mt[(i + 1) % 624] & 0x7fff_ffff)
            mt[i] = mt[(i + 397) % 624] ^ (y >> 1)
            if y & 1 != 0 { mt[i] ^= 0x9908_b0df }
        }
        return (0..<min(count, 624)).map { index in
            var y = mt[index]
            y ^= y >> 11
            y ^= (y << 7) & 0x9d2c_5680
            y ^= (y << 15) & 0xefc6_0000
            y ^= y >> 18
            return y & 1 != 0
        }
    }

    /// Elm's and Irwin's calls: the PRNG from the seed, after the roamers'
    /// advances, its top half mod 3 (PokéFinder's `Utilities4::getCalls`).
    static func calls(seed: UInt32, skips: UInt8, count: Int) -> [UInt8] {
        var state = seed
        func next() -> UInt16 {
            state = state &* 0x41C6_4E6D &+ 0x6073
            return UInt16(state >> 16)
        }
        for _ in 0..<skips { _ = next() }
        return (0..<count).map { _ in UInt8(next() % 3) }
    }

    /// Raikou and Entei roam Johto's routes, Latias or Latios Kanto's
    /// (PokéFinder's `getRouteJ` and `getRouteK`).
    static let johtoRoutes: [UInt8] = Array(29...39) + Array(42...46)
    static let kantoRoutes: [UInt8] = Array(1...22) + [24, 26, 28]
    static let roamerNames = ["Raikou", "Entei", "Latias/Latios"]

    static func callName(_ call: UInt8) -> String { call == 0 ? "E" : call == 1 ? "K" : "P" }
}

// MARK: - View

/// Narrows the seeds near the target down to the one you hit, from what the
/// game shows after loading, and hands its delay to the Timer.
struct Gen4SeedCheckView: View {
    /// The target's clock time, or nil to check around a bare seed.
    @State var target: Gen4SeedTime
    let bareSeed: UInt32?
    @State var heartGoldSoulSilver: Bool
    /// The delay you hit, and how far it is from the target's.
    let use: (Gen4SeedCheck.Candidate) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var delays = 20
    @State private var seconds = 1
    @State private var flips: [Bool] = []
    @State private var calls: [UInt8] = []
    @State private var roamers = [false, false, false]
    @State private var previousRoutes: [UInt8] = [0, 0, 0]
    @State private var seenRoutes: [UInt8] = [0, 0, 0]

    init(target: Gen4SeedTime, bareSeed: UInt32? = nil, heartGoldSoulSilver: Bool,
         use: @escaping (Gen4SeedCheck.Candidate) -> Void) {
        _target = State(initialValue: target)
        self.bareSeed = bareSeed
        _heartGoldSoulSilver = State(initialValue: heartGoldSoulSilver)
        self.use = use
    }

    private var candidates: [Gen4SeedCheck.Candidate] {
        let roamersIn = heartGoldSoulSilver ? roamers : [false, false, false]
        if let bareSeed {
            return Gen4SeedCheck.candidates(aroundSeed: bareSeed, delays: delays, seconds: seconds,
                                            roamers: roamersIn, previousRoutes: previousRoutes)
        }
        return Gen4SeedCheck.candidates(around: target, delays: delays, seconds: seconds,
                                        roamers: roamersIn, previousRoutes: previousRoutes)
    }

    private var evidenceCount: Int {
        heartGoldSoulSilver ? calls.count + seenRoutes.enumerated().filter { roamers[$0.offset] && $0.element != 0 }.count
                            : flips.count
    }

    var body: some View {
        ScrollView {
            CardStack {
                targetCard
                SectionCard(title: "Seeds to Check", icon: "scope") {
                    RNGIntField(label: "Delays Either Side", value: $delays, range: 0...500)
                    RNGIntField(label: "Seconds Either Side", value: $seconds, range: 0...5)
                    Picker("Game", selection: $heartGoldSoulSilver) {
                        Text("Diamond / Pearl / Platinum").tag(false)
                        Text("HeartGold / SoulSilver").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if heartGoldSoulSilver {
                    roamerCard
                    callsCard
                } else {
                    flipsCard
                }
                resultsCard
            }
            .padding()
        }
        .dismissesKeyboard()
        .navigationTitle("Check Your Seed")
    }

    @ViewBuilder
    private var targetCard: some View {
        SectionCard(title: "Target", icon: "target") {
            if let bareSeed {
                LabeledContent("Seed", value: String(format: "%08X", bareSeed))
                    .font(.system(.body, design: .monospaced))
                Text("A second either way is the seed's first byte one up or down.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The DS clock's date and time, and the delay, from Seed to Time.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                RNGIntField(label: "Month", value: $target.month, range: 1...12)
                RNGIntField(label: "Day", value: $target.day, range: 1...31)
                RNGIntField(label: "Hour", value: $target.hour, range: 0...23)
                RNGIntField(label: "Minute", value: $target.minute, range: 0...59)
                RNGIntField(label: "Second", value: $target.second, range: 0...59)
                RNGIntField(label: "Delay", value: $target.delay, range: 0...65535)
                LabeledContent("Seed", value: String(format: "%08X", target.seed))
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private var flipsCard: some View {
        SectionCard(title: "Coin Flips", icon: "circle.lefthalf.filled") {
            Text("Load your game, open the Pokétch's Coin Toss and flip it 10 times, entering each.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            sequenceRow(flips.map { $0 ? "H" : "T" })
            HStack(spacing: 12) {
                Group {
                    Button("Heads") { flips.append(true) }
                    Button("Tails") { flips.append(false) }
                }
                .disabled(flips.count >= Gen4SeedCheck.sequenceLength)
                Spacer()
                undoClear(isEmpty: flips.isEmpty) { flips.removeLast() } clear: { flips.removeAll() }
            }
            .buttonStyle(.bordered)
        }
    }

    private var roamerCard: some View {
        SectionCard(title: "Roamers", icon: "map") {
            Text("Load your game and open the Pokégear map: each roamer still free has moved. Its old route matters only if you saved where it could reroll onto it.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(0..<3, id: \.self) { index in
                Toggle(Gen4SeedCheck.roamerNames[index], isOn: $roamers[index])
                if roamers[index] {
                    routePicker("Was On", selection: $previousRoutes[index], index: index, none: "Unknown")
                    routePicker("Now On", selection: $seenRoutes[index], index: index, none: "Not Checked")
                }
            }
        }
    }

    private func routePicker(_ title: String, selection: Binding<UInt8>, index: Int, none: String) -> some View {
        LabeledContent(title) {
            Picker(title, selection: selection) {
                Text(none).tag(UInt8(0))
                ForEach(index == 2 ? Gen4SeedCheck.kantoRoutes : Gen4SeedCheck.johtoRoutes, id: \.self) { route in
                    Text("Route \(route)").tag(route)
                }
            }
            .labelsHidden()
        }
    }

    private var callsCard: some View {
        SectionCard(title: "Elm and Irwin's Calls", icon: "phone") {
            Text("Call Elm or Irwin and enter each answer: E, K or P as RNG Reporter names them. Irwin has all three from the start.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            sequenceRow(calls.map(Gen4SeedCheck.callName))
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { call in
                    Button(Gen4SeedCheck.callName(UInt8(call))) { calls.append(UInt8(call)) }
                }
                .disabled(calls.count >= Gen4SeedCheck.sequenceLength)
                Spacer()
                undoClear(isEmpty: calls.isEmpty) { calls.removeLast() } clear: { calls.removeAll() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func sequenceRow(_ items: [String]) -> some View {
        Text(items.isEmpty ? "None yet" : items.joined(separator: " "))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(items.isEmpty ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func undoClear(isEmpty: Bool, undo: @escaping () -> Void, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button("Undo", action: undo)
            Button("Clear", role: .destructive, action: clear)
        }
        .disabled(isEmpty)
    }

    private var resultsCard: some View {
        let all = candidates
        let matching = Gen4SeedCheck.matches(all, flips: heartGoldSoulSilver ? [] : flips,
                                             calls: heartGoldSoulSilver ? calls : [],
                                             routes: (0..<3).map { roamers[$0] && heartGoldSoulSilver && seenRoutes[$0] != 0 ? seenRoutes[$0] : nil })
        return SectionCard(title: "Seeds That Match", icon: "checkmark.seal") {
            if evidenceCount == 0 {
                Text("\(all.count.formatted()) seeds to check. Enter what the game shows to narrow them down.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if matching.isEmpty {
                Text("None of the \(all.count.formatted()) seeds matches. Check what you entered, or check more delays or seconds.")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if matching.count > 1 {
                    Text("\(matching.count) seeds match. Enter more to narrow them down.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(matching.prefix(20)) { candidate in
                    candidateRow(candidate, only: matching.count == 1)
                    Divider()
                }
                if let best = matching.first, matching.count == 1, best.delay % 2 != target.delay % 2, bareSeed == nil {
                    Text("You hit an \(best.delay % 2 == 1 ? "odd" : "even") delay, and your target's is \(target.delay % 2 == 1 ? "odd" : "even"). A DS keeps hitting delays of one kind: change the DS year by 1 (and Seed to Time's), or put a GBA game in Slot 2.")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func candidateRow(_ candidate: Gen4SeedCheck.Candidate, only: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Delay \(candidate.delay)").font(.headline)
                Text(offsetText(candidate.delayOffset)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%08X", candidate.seed)).font(.system(.caption, design: .monospaced))
            }
            if candidate.secondOffset != 0 {
                Text("\(candidate.secondOffset > 0 ? "\(candidate.secondOffset) s late" : "\(-candidate.secondOffset) s early") on the clock\(candidate.time.map { " (\($0.timeText))" } ?? "")")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text(heartGoldSoulSilver ? sequenceText(candidate) : candidate.flips.prefix(10).map { $0 ? "H" : "T" }.joined(separator: " "))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Button {
                use(candidate)
                dismiss()
            } label: {
                Label("Use Delay \(candidate.delay) as Delay Hit", systemImage: "tuningfork")
            }
            .buttonStyle(.borderless)
            .font(.callout.weight(only ? .semibold : .regular))
        }
    }

    private func sequenceText(_ candidate: Gen4SeedCheck.Candidate) -> String {
        let routes = (0..<3).filter { roamers[$0] }.map { "\(["R", "E", "L"][$0]) \(candidate.roamerRoutes[$0])" }
        let calls = candidate.calls.prefix(10).map(Gen4SeedCheck.callName).joined(separator: " ")
        return (routes + [calls]).joined(separator: " · ")
    }

    private func offsetText(_ offset: Int) -> String {
        offset == 0 ? "the target" : offset > 0 ? "+\(offset)" : "\(offset)"
    }
}
