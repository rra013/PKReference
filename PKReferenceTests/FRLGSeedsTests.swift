//
//  FRLGSeedsTests.swift
//  PKReferenceTests
//
//  Covers FireRed and LeafGreen initial seeds, ported from Ten Lines: the
//  RNG distance against walking the generator; the farmed lists read as
//  Ten Lines reads them (Switch and GBA layouts, skipped and repeated
//  seeds, seed times); held-button offsets; the search by advances; and,
//  end to end, that a target from PokéFinder's searcher comes back from
//  its initial seed after the advances found, by PokéFinder's generator.
//  Timing and Teachy TV follow Ten Lines' arithmetic.
//

import Testing
import Foundation
@testable import PKReference

@MainActor
@Suite("FRLG Initial Seeds")
struct FRLGSeedsTests {

    private func advanced(_ seed: UInt32, _ steps: Int) -> UInt32 {
        (0..<steps).reduce(seed) { state, _ in PokeRNG.next(state) }
    }

    private func bundled(_ sheet: FRLGSeedSheet) throws -> FRLGSeedList {
        let url = try #require(Bundle.main.url(forResource: sheet.resourceName, withExtension: "csv"),
                               "\(sheet.resourceName).csv isn't bundled")
        return FRLGSeedList(sheet: sheet, csv: try String(contentsOf: url, encoding: .utf8))
    }

    @Test("The distance between two states is the advances between them")
    func distance() {
        for (start, steps) in [(UInt32(0), 0), (0, 1), (0x11C7, 5_000), (0xDEAD_BEEF, 123_457), (0xFFFF, 1 << 20)] {
            #expect(PokeRNG.distance(from: start, to: advanced(start, steps)) == UInt32(steps), "\(steps)")
        }
        #expect(PokeRNG.distancesFromZero[0x11C7] == PokeRNG.distance(from: 0, to: 0x11C7))
    }

    @Test("Every list is bundled and reads as a seed list", arguments: FRLGSeedSheet.allCases)
    func bundledLists(sheet: FRLGSeedSheet) throws {
        let list = try bundled(sheet)
        #expect(list.entries.count > 1_000)
        #expect(Set(list.entries.map(\.setting)) == Set(sheet.columns.map(\.setting)))
    }

    /// The Switch FireRed list's first row: seed time 23385 (+5737), then
    /// 11C7 for Mono and Stereo Help/A, and 11BF for Mono Help/Start.
    @Test("A Switch list gives each row's time")
    func switchList() throws {
        let list = try bundled(.fireRedSwitch)
        let first = list.entries.filter { $0.seedTime == 23_385 + 5_737 }
        let help = FRLGSetting(sound: .mono, buttonMode: .help, seedButton: .a)
        #expect(first.contains(FRLGSeedEntry(setting: help, seedTime: 29_122, seed: 0x11C7)))
        #expect(first.contains(FRLGSeedEntry(setting: FRLGSetting(sound: .stereo, buttonMode: .help, seedButton: .a),
                                             seedTime: 29_122, seed: 0x11C7)))
        #expect(first.contains(FRLGSeedEntry(setting: FRLGSetting(sound: .mono, buttonMode: .help, seedButton: .start),
                                             seedTime: 29_122, seed: 0x11BF)))
    }

    /// GBA rows are consecutive frames from the list's starting frame; an
    /// empty or "-" seed is a gap, a repeat stands in for the first, and a
    /// row without a first cell doesn't count.
    @Test("A GBA list counts frames by row")
    func gbaList() {
        let csv = """
            "Frame","x","x","MonoLRA","MonoLA"
            "1","","","1234","ABCD"
            "","","","9999","9999"
            "2","","","-","ABCD"
            "3","","","5678","ABCE"
            """
        let list = FRLGSeedList(sheet: .fireRed, csv: csv)
        let lr = FRLGSetting(sound: .mono, buttonMode: .lr, seedButton: .a)
        let lEqualsA = FRLGSetting(sound: .mono, buttonMode: .lEqualsA, seedButton: .a)
        #expect(list.entries.filter { $0.setting == lr }
                == [FRLGSeedEntry(setting: lr, seedTime: 2031 * 16, seed: 0x1234),
                    FRLGSeedEntry(setting: lr, seedTime: 2033 * 16, seed: 0x5678)])
        #expect(list.entries.filter { $0.setting == lEqualsA }
                == [FRLGSeedEntry(setting: lEqualsA, seedTime: 2031 * 16, seed: 0xABCD),
                    FRLGSeedEntry(setting: lEqualsA, seedTime: 2033 * 16, seed: 0xABCE)])
    }

    /// On Switch, holding R or L on the blackout screen in Help mode takes
    /// 36 off the seed.
    @Test("Held buttons shift the seed by the version's offsets")
    func heldButtons() throws {
        let help = FRLGSetting(sound: .mono, buttonMode: .help, seedButton: .a)
        let list = try bundled(.fireRedSwitch)
        let index = FRLGSeedIndex(list: list, version: .fireRedSwitch,
                                  filter: FRLGSettingsFilter(sound: .mono, buttonMode: .help, seedButton: .a))
        let target: UInt32 = 0x11C7 - 36
        let held = index.seeds(reaching: target, minimum: 0, maximum: 0)
        // Both come from the press that gives 11C7 without a held button.
        #expect(held.contains { $0.seed == 0x11C7 - 36 && $0.held == .blackoutR && $0.seedTime == 29_122 && $0.setting == help })
        #expect(held.contains { $0.held == .blackoutL && $0.seedTime == 29_122 })
        let plain = FRLGSeedIndex(list: list, version: .fireRedSwitch,
                                  filter: FRLGSettingsFilter(sound: .mono, buttonMode: .help, seedButton: .a, held: FRLGHeldButton.none))
        #expect(plain.seeds(reaching: target, minimum: 0, maximum: 0).allSatisfy { $0.held == .none && $0.seedTime != 29_122 })
        #expect(plain.seeds(reaching: 0x11C7, minimum: 0, maximum: 0).first?.seedTime == 29_122)

        // Shown as one press: R and L do the same.
        let choices = FRLGHeldChoice.merged(held.filter { $0.seedTime == 29_122 })
        #expect(choices.map(\.settingsName) == ["Mono · Help · A, holding Blackout R or Blackout L"])
    }

    @Test("Seeds reaching a target come in range, fewest advances first")
    func search() throws {
        let index = FRLGSeedIndex(list: try bundled(.fireRedSwitch), version: .fireRedSwitch)
        let target = advanced(0x11C7, 5_000)
        let seeds = index.seeds(reaching: target, minimum: 1_000, maximum: 200_000)
        #expect(!seeds.isEmpty)
        #expect(seeds.map(\.advances) == seeds.map(\.advances).sorted())
        for seed in seeds.prefix(20) {
            #expect((1_000...200_000).contains(seed.advances))
            #expect(advanced(UInt32(seed.seed), Int(seed.advances)) == target)
        }
        #expect(index.nearest(reaching: target, minimum: 1_000, maximum: 200_000) == seeds.first)
        #expect(index.seeds(reaching: target, minimum: 0, maximum: 5_000).contains { $0.seed == 0x11C7 && $0.advances == 5_000 })
    }

    /// A 31-IV target from PokéFinder's Static 1 searcher, found from a seed
    /// on Switch FireRed: PokéFinder's generator, from that seed and that
    /// many advances, makes the same Pokémon.
    @Test("A target comes back from its initial seed, by PokéFinder's generator")
    func endToEnd() throws {
        let targets = staticSearchGen3(minIVs: (31, 31, 31, 31, 31, 31), maxIVs: (31, 31, 31, 31, 31, 31),
                                       natures: [], tid: 0, sid: 0, shinyOnly: false, method: .method1)
        let target = try #require(targets.first)
        let index = FRLGSeedIndex(list: try bundled(.fireRedSwitch), version: .fireRedSwitch)
        let seed = try #require(index.nearest(reaching: target.seed, minimum: 0, maximum: .max))
        let generated = PFBridge.staticGenerate3(seed: UInt32(seed.seed), initialAdvances: seed.advances,
                                                 maxAdvances: 0, method: .method1, tid: 0, sid: 0,
                                                 natures: Array(repeating: true, count: 25),
                                                 powers: Array(repeating: true, count: 16))
        let made = try #require(generated.first)
        #expect(made.advances == seed.advances)
        #expect(made.pid == target.pid && made.ivs == [31, 31, 31, 31, 31, 31])
    }

    // MARK: Finder Search

    /// The Finder's Gen 3 static search streams: results and progress come
    /// in as PokéFinder's searcher goes, the same results its one-shot
    /// search gives.
    @Test("The Gen 3 static search streams the one-shot search's results, with progress")
    func streamingSearch() {
        var progress: [Double] = []
        var streamed: [StaticSearchResult] = []
        staticSearchGen3Streaming(minIVs: (31, 31, 31, 31, 0, 0), maxIVs: (31, 31, 31, 31, 31, 31),
                                  natures: [], tid: 0, sid: 0, shinyOnly: false, method: .method1,
                                  onProgress: { progress.append($0) }) { streamed.append($0) }
        let oneShot = PFBridge.staticSearch3(method: .method1, tid: 0, sid: 0,
                                             ivMin: [31, 31, 31, 31, 0, 0], ivMax: [31, 31, 31, 31, 31, 31],
                                             natures: Array(repeating: true, count: 25),
                                             powers: Array(repeating: true, count: 16))
        #expect(!streamed.isEmpty)
        #expect(Set(streamed.map(\.pid)) == Set(oneShot.map(\.pid)) && streamed.count == oneShot.count)
        #expect(progress.last == 100 && progress == progress.sorted())
    }

    /// Without the Pokémon, PokéFinder's searcher has no gender ratio and
    /// every result is genderless; with its template, gender follows it, so
    /// a gender filter finds something.
    @Test("The Gen 3 static search and generator take gender from the encounter")
    func searchGender() throws {
        let eevee = try #require(PFBridge.staticTemplate3(species: 133, game: .fireRed, preferring: 2))
        func search(template: PFStaticTemplateRef?, gender: UInt8 = 255) -> [StaticSearchResult] {
            var results: [StaticSearchResult] = []
            staticSearchGen3Streaming(minIVs: (31, 31, 31, 31, 31, 0), maxIVs: (31, 31, 31, 31, 31, 31),
                                      natures: [], tid: 0, sid: 0, shinyOnly: false, method: .method1,
                                      game: .fireRed, template: template, filterGender: gender) { results.append($0) }
            return results
        }
        #expect(Set(search(template: nil).map(\.gender)) == [2])
        #expect(search(template: nil, gender: 1).isEmpty)
        let all = search(template: eevee)
        #expect(Set(all.map(\.gender)) == [0, 1])
        let female = search(template: eevee, gender: 1)
        #expect(!female.isEmpty && female.allSatisfy { $0.gender == 1 } && female.count < all.count)

        var generated: [StaticSearchResult] = []
        staticGenerateGen3Streaming(seed: 0x11C7, initialAdvance: 0, maxAdvance: 200, natures: [],
                                    tid: 0, sid: 0, shinyOnly: false, method: .method1,
                                    game: .fireRed, template: eevee) { generated.append($0) }
        #expect(Set(generated.map(\.gender)) == [0, 1])
    }

    /// Stopping a search stops PokéFinder's searcher too.
    @Test("Cancelling the Gen 3 static search stops it")
    func cancelSearch() async {
        let started = ContinuousClock.now
        let task = Task.detached {
            var count = 0
            staticSearchGen3Streaming(minIVs: (0, 0, 0, 0, 0, 0), maxIVs: (31, 31, 31, 31, 31, 31),
                                      natures: [], tid: 0, sid: 0, shinyOnly: true, method: .method1) { _ in count += 1 }
            return count
        }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()
        _ = await task.value
        // The whole search takes minutes.
        #expect(ContinuousClock.now - started < .seconds(3))
    }

    /// The reachable list checks each result once as results come in, and
    /// gives what checking them all at once does.
    @Test("Reachable targets keep up with a search's results")
    func reachableCache() async throws {
        let suite = "FRLGSeedsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let search = FRLGSeedSearch(defaults: defaults)
        search.maximumAdvances = 200_000
        await search.rebuildIndex()
        #expect(search.index != nil)
        let results = staticSearchGen3(minIVs: (31, 31, 31, 31, 31, 25), maxIVs: (31, 31, 31, 31, 31, 31),
                                       natures: [], tid: 0, sid: 0, shinyOnly: false, method: .method1)
        func all(_ results: [StaticSearchResult]) -> [UUID] {
            results.compactMap { r in search.nearest(reaching: r.seed).map { (r.id, $0.advances) } }
                .sorted { $0.1 < $1.1 }.map(\.0)
        }
        let cache = FRLGMatchCache()
        let half = Array(results.prefix(results.count / 2))
        #expect(cache.matches(for: half, search: search).map(\.id) == all(half))
        let matches = cache.matches(for: results, search: search)
        #expect(!matches.isEmpty && matches.map(\.id) == all(results))
        // New settings check every result again.
        search.maximumAdvances = 50_000
        #expect(cache.matches(for: results, search: search).map(\.id) == all(results))
        // A new search starts over.
        #expect(cache.matches(for: [], search: search).isEmpty)
    }

    @Test("Timing and Teachy TV follow Ten Lines")
    func timing() {
        // 59.7275 frames a second; Switch 2 is 750 ms earlier than Switch.
        #expect(FRLGConsole.switch1.milliseconds(frames: 29_122.0 / 16) == 30_473)
        #expect(FRLGConsole.switch2.milliseconds(frames: 29_122.0 / 16) == 30_473 - 750)
        #expect(FRLGConsole.gba.milliseconds(frames: 600) == 10_045 - 260)
        let split = TeachyTV.split(advances: 3_600 + 313 * 100 + 7, minimumOutside: 3_600)
        #expect(split.ttvFrames == 100 && split.regularAdvances == 3_607)
        #expect(TeachyTV.split(advances: 1_000, minimumOutside: 3_600) == (0, 1_000))
        #expect(!FRLGVersion.fireRedSwitch.supportsTeachyTV && FRLGVersion.fireRed.supportsTeachyTV)
    }

    /// Every version starts on Mono, Help and A, with no held button: the
    /// game's own options, which every list farms. A setting a list hasn't
    /// farmed can still be chosen, and says it finds nothing.
    @Test("Options start on what each version's list has farmed")
    func defaults() throws {
        let suite = "FRLGSeedsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let search = FRLGSeedSearch(defaults: defaults)
        #expect(search.version == .fireRedSwitch)
        #expect(search.sound == .mono && search.buttonMode == .help && search.seedButton == .a && search.held == FRLGHeldButton.none)
        #expect(search.isFarmed)

        for version in FRLGVersion.allCases {
            #expect(version.farmedSettings.contains(FRLGSeedSearch.gameDefaults), "\(version)")
        }
        search.buttonMode = .lr
        #expect(!search.isFarmed)
        search.version = .leafGreenSwitch
        #expect(search.buttonMode == .help && search.isFarmed)

        #expect(FRLGVersion.fireRed.isFullyFarmed && !FRLGVersion.fireRedSwitch.isFullyFarmed)
        #expect(FRLGVersion.fireRedSwitch.farmedButtonModes == [.help])
        #expect(FRLGVersion.fireRedSwitch.heldButtons(buttonMode: .help) == [.none, .blackoutR, .blackoutL])
        #expect(FRLGVersion.fireRedSwitch.heldButtons(buttonMode: .lr).isEmpty)
        #expect(FRLGVersion.fireRedJPN10.farmedSeedButtons == [.a])
    }

    // MARK: Calibration

    /// An attempt aimed at a seed and advance, that pressed two seeds late
    /// and five frames late: PokéFinder's generator says what it caught,
    /// and calibration finds that press and frame from the catch alone.
    @Test("Calibration finds the seed and frame an attempt hit, and corrects the timer")
    func calibration() throws {
        let list = try bundled(.fireRedSwitch)
        let help = FRLGSetting(sound: .mono, buttonMode: .help, seedButton: .a)
        let timeline = list.timeline(help, offset: 0)
        let aimed = timeline[100], late = timeline[102]
        let attempted = FRLGInitialSeed(seed: aimed.seed, setting: help, held: .none, seedTime: aimed.seedTime,
                                        advances: 5_000)
        let made = try #require(PFBridge.staticGenerate3(seed: UInt32(late.seed), initialAdvances: 5_005, maxAdvances: 0,
                                                         method: .method1, tid: 0, sid: 0,
                                                         natures: Array(repeating: true, count: 25),
                                                         powers: Array(repeating: true, count: 16)).first)
        let caught = FRLGCatch(nature: made.nature, ivMin: made.ivs, ivMax: made.ivs)
        let bulbasaur = try #require(PFBridge.staticTemplate3(species: 1, game: .fireRed, preferring: 0))
        let hits = FRLGCalibration.search(list: list, version: .fireRedSwitch, attempted: attempted, targetFrame: 5_000,
                                          seedLeeway: 5, frames: 4_900...5_100, method: .method1, template: bulbasaur,
                                          tid: 0, sid: 0, caught: caught)
        let hit = try #require(hits.first { $0.seed == late.seed && $0.advances == 5_005 })
        #expect(hit.seedOffset == 2 && hit.pid == made.pid)

        let suite = "FRLGSeedsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let search = FRLGSeedSearch(defaults: defaults)
        search.overworldFrames = 0
        let lateMS = search.seedTimeMS(FRLGInitialSeed(seed: late.seed, setting: help, held: .none, seedTime: late.seedTime))
        search.calibrate(attempted: attempted, hit: hit)
        // Pressed late: the seed press comes earlier next time, and so does
        // the final press, by five GBA frames.
        #expect(search.seedCalibrationMS == -(lateMS - search.seedTimeMS(attempted)) && search.seedCalibrationMS < 0)
        #expect(search.frameCalibrationMS == -84)
        #expect(search.preTimerMS(attempted) == search.seedTimeMS(attempted) + search.seedCalibrationMS)
        search.resetCalibration()
        #expect(search.seedCalibrationMS == 0 && search.frameCalibrationMS == 0)
    }

    /// With any nature, every frame matches, as in Ten Lines: the nearest
    /// come first, the attempt's own press and frame at the top. Gender
    /// comes from the template's species.
    @Test("Calibration's nature, gender and shiny filters")
    func calibrationFilters() throws {
        let list = try bundled(.fireRedSwitch)
        let help = FRLGSetting(sound: .mono, buttonMode: .help, seedButton: .a)
        let aimed = list.timeline(help, offset: 0)[100]
        let attempted = FRLGInitialSeed(seed: aimed.seed, setting: help, held: .none, seedTime: aimed.seedTime,
                                        advances: 5_000)
        let bulbasaur = try #require(PFBridge.staticTemplate3(species: 1, game: .fireRed, preferring: 0))
        func hits(_ caught: FRLGCatch) -> [FRLGCalibrationHit] {
            FRLGCalibration.search(list: list, version: .fireRedSwitch, attempted: attempted, targetFrame: 5_000,
                                   seedLeeway: 2, frames: 4_990...5_010, method: .method1, template: bulbasaur,
                                   tid: 0, sid: 0, caught: caught)
        }
        let any = hits(FRLGCatch(nature: nil, ivMin: Array(repeating: 31, count: 6)))
        // Five seeds, 21 frames each, the IVs ignored with any nature.
        #expect(any.count == 5 * 21)
        #expect(any.first?.seedOffset == 0 && any.first?.advances == 5_000)
        let female = hits(FRLGCatch(nature: nil, gender: 1))
        #expect(!female.isEmpty && female.allSatisfy { $0.gender == 1 })
        // Bulbasaur is seven in eight male.
        #expect(female.count < any.count / 4)
        let shiny = hits(FRLGCatch(nature: nil, shiny: 3))
        #expect(shiny.allSatisfy { $0.shiny > 0 })
    }

    /// Ten Lines' IV calculator, worked by hand for a level 5 Bulbasaur
    /// (base 45/49/49/65/65/45) with 31s: HP 21, the rest 11/11/13/13/11.
    @Test("IV calculator works out IVs from stats and nature")
    func ivCalculator() throws {
        let bulbasaur = try #require(PFBridge.staticTemplate3(species: 1, game: .fireRed, preferring: 0))
        let level5 = FRLGStatsLine(level: 5, stats: [21, 11, 11, 13, 13, 11])
        // Hardy is neutral.
        #expect(FRLGIVCalculator.calculate([level5], template: bulbasaur, nature: 0)
                == .ivs(min: [30, 22, 22, 30, 30, 30], max: [31, 31, 31, 31, 31, 31]))
        // Adamant raises Attack and lowers Special Attack: 11 Attack is
        // 10 before it, and no Special Attack IV makes 13.
        var adamant = level5
        adamant.stats[3] = 11
        #expect(FRLGIVCalculator.calculate([adamant], template: bulbasaur, nature: 3)
                == .ivs(min: [30, 2, 22, 30, 30, 30], max: [31, 21, 31, 31, 31, 31]))
        #expect(FRLGIVCalculator.calculate([level5], template: bulbasaur, nature: 3)
                == .error("No possible Special Attack IV. Check the nature, level and stats."))
        // A second line, at level 100, narrows it to the 31s.
        let level100 = FRLGStatsLine(level: 100, stats: [231, 134, 134, 166, 166, 126])
        #expect(FRLGIVCalculator.calculate([level5, level100], template: bulbasaur, nature: 0)
                == .ivs(min: Array(repeating: 31, count: 6), max: Array(repeating: 31, count: 6)))
    }

    @Test("IV calculator checks the stats as Ten Lines does")
    func ivCalculatorValidation() throws {
        let bulbasaur = try #require(PFBridge.staticTemplate3(species: 1, game: .fireRed, preferring: 0))
        func error(_ lines: [FRLGStatsLine]) -> FRLGIVCalculator.Outcome {
            FRLGIVCalculator.calculate(lines, template: bulbasaur, nature: 0)
        }
        let line = FRLGStatsLine(level: 5, stats: [21, 11, 11, 13, 13, 11])
        #expect(error([FRLGStatsLine(level: nil, stats: line.stats)]) == .error("Enter its level."))
        #expect(error([FRLGStatsLine(level: 0, stats: line.stats)]) == .error("Level must be 1–100."))
        #expect(error([FRLGStatsLine(level: 5)]) == .error("Enter its HP."))
        var high = line
        high.stats[5] = 480
        #expect(error([high]) == .error("Speed must be 1–479."))
        #expect(error([line, FRLGStatsLine(level: 6, stats: [22, nil, nil, nil, nil, nil])])
                == .error("Line 2: Enter its Attack."))
        // A line added but not filled in yet is left out.
        #expect(error([line, FRLGStatsLine(level: 6)]) == error([line]))
    }

    @Test("Encounters find their PokéFinder template")
    func templates() throws {
        let lapras = try #require(PFBridge.staticTemplate3(species: 131, game: .fireRed, preferring: 2))
        #expect(lapras.type == 2)
        #expect(PFBridge.staticTemplate3(species: 131, game: .leafGreen) != nil)
        // Treecko is a Hoenn starter.
        #expect(PFBridge.staticTemplate3(species: 252, game: .fireRed) == nil)
        // Every FireRed and LeafGreen encounter the Finder offers is a
        // template of that species, Mew too (Emerald's, PokéFinder having
        // none for FireRed and LeafGreen).
        let all = StaticEncounterCategory.allCases.flatMap { StaticEncounterData.encounters(for: .fireRed, category: $0) }
        #expect(all.contains { $0.species == 151 })
        for encounter in all {
            let template = PFBridge.getStaticEncounters3(type: encounter.type)[Int(encounter.index)]
            #expect(template.specie == encounter.species, "\(encounter.speciesName)")
        }
    }

    /// On Switch the overworld advances twice a frame, so the timer aims at
    /// the continue screen's press.
    @Test("On Switch the target frame is the continue screen's press")
    func switchOverworld() throws {
        let suite = "FRLGSeedsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let search = FRLGSeedSearch(defaults: defaults)
        #expect(search.overworldFrames == 600)
        let seed = FRLGInitialSeed(seed: 0x11C7, setting: FRLGSeedSearch.gameDefaults, held: .none, seedTime: 29_122,
                                   advances: 5_000)
        #expect(search.targetFrame(seed).frame == 5_000 - 1_200)
        search.version = .fireRed
        #expect(search.targetFrame(seed).frame == 5_000)
    }
}
