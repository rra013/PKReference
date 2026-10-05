//
//  RegulationRulesTests.swift
//  PKReferenceTests
//
//  Covers `ChampionsRules`, each regulation's `rules` block: every bundled
//  regulation decodes it, its values are the ones the app used before they
//  were read from the JSON, the stat-point caps and IV lock follow it, and
//  so do the validator (from an edited copy of a regulation file) and Mega
//  Evolution in the calc and in battles. Every Mega a regulation's
//  learnsets list has its stone in the regulation's `mega_stones`.
//

import Testing
import Foundation
@testable import PKReference

@MainActor
@Suite("Regulation Rules")
struct RegulationRulesTests {

    // MARK: Reading the rules

    @Test("Every bundled regulation's rules block decodes", arguments: ChampionsRegulation.allCases)
    func rulesDecode(regulation: ChampionsRegulation) throws {
        let url = try #require(Bundle.main.url(forResource: regulation.bundleResourceName,
                                               withExtension: "json"))
        let rules = try ChampionsRules.decode(fromRegulationJSON: Data(contentsOf: url))
        #expect(regulation.rules() == rules)
    }

    /// Pinned so a regulation that changes a rule is noticed here first.
    @Test("Every regulation so far has the rules the app used before reading them",
          arguments: ChampionsRegulation.allCases)
    func rulesMatchEarlierValues(regulation: ChampionsRegulation) {
        let rules = regulation.rules()
        #expect(rules == .fallback)
        #expect(rules.statPointsMaxTotal == 66)
        #expect(rules.statPointsMaxPerStat == 32)
        #expect(rules.ivLockedAt == 31)
        #expect(rules.teamSize == 6)
        #expect(rules.speciesClause && !rules.itemClause)
        #expect(rules.megaEvolutionsAllowed && !rules.megaRayquazaAllowed)
        #expect(!rules.teraAllowed && !rules.zMovesAllowed && !rules.dynamaxAllowed)
    }

    @Test("The caps and IV lock follow the current regulation")
    func globalsFollowCurrentRules() {
        let rules = ChampionsRegulation.current.rules()
        #expect(championsMaxEVPerStat == rules.statPointsMaxPerStat)
        #expect(championsMaxTotalEVs == rules.statPointsMaxTotal)
        #expect(championsLockedIV == rules.ivLockedAt)
    }

    @Test("252 EVs are worth 32 stat points, rounding down")
    func evConversion() {
        #expect(mainEVToChampions(252) == 32)
        #expect(mainEVToChampions(4) == 0)
        #expect(mainEVToChampions(8) == 1)
        #expect(championsEVToMain(32) == 252)
        #expect(StatScale.convert(252, from: .mainline, to: .champions) == 32)
        #expect(StatScale.convert(4, from: .mainline, to: .champions) == 1)
    }

    // MARK: Mega Evolution

    private func rules(mega: Bool, rayquaza: Bool) -> ChampionsRules {
        let base = ChampionsRules.fallback
        return ChampionsRules(
            speciesClause: base.speciesClause, itemClause: base.itemClause,
            statPointsMaxTotal: base.statPointsMaxTotal,
            statPointsMaxPerStat: base.statPointsMaxPerStat,
            ivLockedAt: base.ivLockedAt, teamSize: base.teamSize,
            maxRestrictedPerTeam: base.maxRestrictedPerTeam,
            megaEvolutionsAllowed: mega, megaRayquazaAllowed: rayquaza,
            teraAllowed: base.teraAllowed, zMovesAllowed: base.zMovesAllowed,
            dynamaxAllowed: base.dynamaxAllowed)
    }

    private var megaCharizardY: MegaForm {
        MegaForms.all.first { $0.stone == .charizarditeY }!
    }

    private var megaRayquaza: MegaForm {
        MegaForms.moveTriggered.first { $0.speciesKey == "rayquaza" }!
    }

    @Test("Mega Evolution follows its switch, and Mega Rayquaza its own")
    func megaSwitches() {
        #expect(rules(mega: true, rayquaza: false).allowsMega(megaCharizardY))
        #expect(!rules(mega: false, rayquaza: false).allowsMega(megaCharizardY))
        #expect(!rules(mega: true, rayquaza: false).allowsMega(megaRayquaza))
        #expect(rules(mega: true, rayquaza: true).allowsMega(megaRayquaza))
        #expect(!rules(mega: false, rayquaza: true).allowsMega(megaRayquaza))
    }

    private func charizard() -> PKMNStats {
        PKMNStats(id: 6, speciesID: 6, name: "Charizard",
                  type1: "Fire", type2: "Flying",
                  baseHP: 78, baseAtk: 84, baseDef: 78,
                  baseSpAtk: 109, baseSpDef: 85, baseSpeed: 100,
                  ability1: "blaze")
    }

    @Test("The calc's Champions mode still allows a Mega the regulation allows")
    func calcChampionsMega() {
        let side = CalcSide()
        side.pokemon = charizard()
        side.heldItem = .charizarditeY
        side.setChampionsMode(true)
        #expect(side.canMegaEvolve)
        #expect(side.megaDisabledReason == nil)
    }

    private func battle(championsRules: ChampionsRules?) -> BattleEngine {
        let p = charizard()
        let slot = TeamSlotInfo(
            spreadName: "fixture", pokemonID: p.id, pokemonName: p.name,
            type1: p.type1, type2: p.type2, abilityName: "blaze",
            itemRawValue: HeldItem.charizarditeY.rawValue,
            championsMode: true, natureID: "hardy", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 0,
            moveSlots: [])
        let s1 = BattleSide(label: "Side 1", slots: [slot], format: .singles,
                            allPokemon: [p], allMoves: [])
        let s2 = BattleSide(label: "Side 2", slots: [slot], format: .singles,
                            allPokemon: [p], allMoves: [])
        return BattleEngine(format: .singles, side1: s1, side2: s2,
                            allPokemon: [p], allMoves: [], championsRules: championsRules)
    }

    @Test("A Champions battle allows Mega Evolution only if its regulation does")
    func battleMega() {
        #expect(battle(championsRules: nil).canMegaEvolve(side: 0, slot: 0))
        #expect(battle(championsRules: .fallback).canMegaEvolve(side: 0, slot: 0))
        #expect(!battle(championsRules: rules(mega: false, rayquaza: false))
            .canMegaEvolve(side: 0, slot: 0))
    }

    // MARK: The validator

    /// A validator for Regulation M-C with `changes` made to its rules block.
    private func validator(rulesChanges changes: [String: Any]) throws -> ChampionsValidator {
        let reg = ChampionsRegulation.mC
        let legalityURL = try #require(Bundle.main.url(forResource: reg.bundleResourceName,
                                                       withExtension: "json"))
        let learnsetsURL = try #require(Bundle.main.url(forResource: reg.learnsetBundleResourceName,
                                                        withExtension: "json"))
        var json = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: legalityURL)) as? [String: Any])
        var rules = try #require(json["rules"] as? [String: Any])
        rules.merge(changes) { _, new in new }
        json["rules"] = rules
        let edited = FileManager.default.temporaryDirectory
            .appendingPathComponent("RegulationRulesTests-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: json).write(to: edited)
        defer { try? FileManager.default.removeItem(at: edited) }
        return try #require(ChampionsValidator(legalityURL: edited, learnsetsURL: learnsetsURL))
    }

    private func garchomp(item: String?, statPoints: PokemonSet.StatPoints) -> PokemonSet {
        PokemonSet(species: "Garchomp", ability: "Rough Skin", item: item, nature: "Jolly",
                   teraType: nil, moves: ["Earthquake", "Dragon Claw", "Protect", "Rock Slide"],
                   statPoints: statPoints, role: nil)
    }

    private func categories(_ violations: [Violation]) -> Set<Violation.Category> {
        Set(violations.map(\.category))
    }

    @Test("The validator reads its caps from the regulation file")
    func validatorCaps() throws {
        let set = garchomp(item: nil, statPoints: .init(hp: 36, atk: 32, def: 0, spa: 0, spd: 0, spe: 0))
        let bundled = try validator(rulesChanges: [:])
        #expect(categories(bundled.validate(set: set))
            .isSuperset(of: [.statPointsOverCap, .statPointsPerStatOver]))
        let raised = try validator(rulesChanges: ["stat_points_max_total": 70,
                                                  "stat_points_max_per_stat": 40])
        #expect(categories(raised.validate(set: set))
            .isDisjoint(with: [.statPointsOverCap, .statPointsPerStatOver]))
    }

    @Test("The validator reads team size and both clauses from the regulation file")
    func validatorTeamRules() throws {
        let points = PokemonSet.StatPoints(hp: 32, atk: 32, def: 2, spa: 0, spd: 0, spe: 0)
        let team = Array(repeating: garchomp(item: "Sitrus Berry", statPoints: points), count: 4)

        let bundled = try validator(rulesChanges: [:])
        let bundledCategories = categories(bundled.validate(team: team))
        #expect(bundledCategories.isSuperset(of: [.wrongTeamSize, .speciesClause]))
        #expect(!bundledCategories.contains(.itemClause))

        let edited = try validator(rulesChanges: ["team_size": 4, "species_clause": false,
                                                  "item_clause": true])
        let editedCategories = categories(edited.validate(team: team))
        #expect(editedCategories.isDisjoint(with: [.wrongTeamSize, .speciesClause]))
        #expect(editedCategories.contains(.itemClause))
    }

    // MARK: Mega Stones

    private func bundledJSON(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "json"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// The validator's legal items and Team Search's Megas both come from
    /// `mega_stones`. Dragoninite was missing from all three regulations,
    /// so Mega Dragonite was an illegal item and unknown to Team Search.
    @Test("Every Mega a regulation lists has its stone", arguments: ChampionsRegulation.allCases)
    func megaStonesListed(regulation: ChampionsRegulation) throws {
        let stones = Set((try bundledJSON(regulation.bundleResourceName)["mega_stones"]
            as? [String: String] ?? [:]).values)
        let species = try #require(try bundledJSON(regulation.learnsetBundleResourceName)["species"]
            as? [String: [String: Any]])
        let megas = species.values.flatMap { entry in
            (entry["megas"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        }
        #expect(!megas.isEmpty)
        let missing = megas.filter { name in
            guard let stone = MegaForms.all.first(where: { $0.displayName == name })?.stone else { return true }
            return !stones.contains(stone.rawValue)
        }
        #expect(missing.isEmpty, "Megas without their stone in \(regulation.displayName): \(missing.sorted())")
    }

    @Test("Dragonite can hold Dragoninite, and Team Search knows Mega Dragonite",
          arguments: ChampionsRegulation.allCases)
    func dragoninite(regulation: ChampionsRegulation) throws {
        let validator = try #require(ChampionsValidator(regulation: regulation))
        let dragonite = PokemonSet(species: "Dragonite", ability: "Multiscale", item: "Dragoninite",
                                   nature: "Adamant", teraType: nil,
                                   moves: ["Extreme Speed", "Scale Shot", "Earthquake", "Protect"],
                                   statPoints: .init(hp: 2, atk: 32, def: 0, spa: 0, spd: 0, spe: 32), role: nil)
        #expect(categories(validator.validate(set: dragonite)).isDisjoint(with: [.illegalItem, .wrongMegaStone]))
        let vocabulary = try TeamSearchVocabulary.bundled(for: regulation)
        #expect(vocabulary.mega(heldItem: "Dragoninite", speciesID: "dragonite") != nil)
    }

    /// Regulation M-B added these items (Serebii's M-B page, "Newly Added
    /// Items"), but its item list was copied from M-A, so they were illegal
    /// items and Battle Sim refused Champions teams holding them.
    @Test("The items M-B added are legal from M-B on", arguments: ChampionsRegulation.allCases)
    func itemsAddedInMB(regulation: ChampionsRegulation) throws {
        let added = ["Wide Lens", "Muscle Band", "Wise Glasses", "Expert Belt", "Light Clay", "Life Orb",
                     "Zoom Lens", "Metronome", "Iron Ball", "Icy Rock", "Smooth Rock", "Heat Rock",
                     "Damp Rock", "Shed Shell", "Big Root"]
        let validator = try #require(ChampionsValidator(regulation: regulation))
        for item in added {
            #expect(validator.itemWhitelist.contains(item) == (regulation != .mA),
                    "\(item) in \(regulation.displayName)")
        }
        #expect(validator.choiceItems == ["Choice Scarf"])
    }

    /// The stones M-C added were first guessed as "Golisopodite" and
    /// "Baxcaliburite"; tournament teams and pastes use the game's names.
    @Test("Golisopod and Baxcalibur hold their stones by the game's names")
    func mCStoneNames() throws {
        let validator = try #require(ChampionsValidator(regulation: .mC))
        let golisopod = PokemonSet(species: "Golisopod", ability: "Emergency Exit", item: "Golisopite",
                                   nature: "Adamant", teraType: nil,
                                   moves: ["First Impression", "Leech Life", "Liquidation", "Protect"],
                                   statPoints: .init(hp: 32, atk: 32, def: 0, spa: 0, spd: 2, spe: 0), role: nil)
        let baxcalibur = PokemonSet(species: "Baxcalibur", ability: "Thermal Exchange", item: "Baxcalibrite",
                                    nature: "Adamant", teraType: nil,
                                    moves: ["Glaive Rush", "Icicle Crash", "Ice Shard", "Protect"],
                                    statPoints: .init(hp: 2, atk: 32, def: 0, spa: 0, spd: 0, spe: 32), role: nil)
        for set in [golisopod, baxcalibur] {
            #expect(categories(validator.validate(set: set)).isDisjoint(with: [.illegalItem, .wrongMegaStone]),
                    "\(set.species)")
        }
        let vocabulary = try TeamSearchVocabulary.bundled(for: .mC)
        #expect(vocabulary.mega(heldItem: "Golisopite", speciesID: "golisopod") != nil)
        #expect(vocabulary.mega(heldItem: "Baxcalibrite", speciesID: "baxcalibur") != nil)
    }

    /// A team saved with an old stone name still validates: the name is
    /// read as the current one before the validator sees it.
    @Test("A saved team holding an old stone name isn't an illegal item")
    func oldStoneNameInSavedTeam() throws {
        let validator = try #require(ChampionsValidator(regulation: .mC))
        let slot = TeamSlotInfo(
            spreadName: "test",
            pokemonID: 768, pokemonName: "Golisopod",
            type1: "Bug", type2: "Water",
            abilityName: "emergency-exit", itemRawValue: "Golisopodite",
            championsMode: true, natureID: "adamant", level: 50,
            evHP: 32, evAtk: 32, evDef: 0, evSpAtk: 0, evSpDef: 2, evSpeed: 0,
            moveSlots: []
        )
        #expect(ChampionsFormat.pokemonSet(from: slot).item == "Golisopite")
        let found = categories(ChampionsFormat.validate(slots: [slot], validator: validator))
        #expect(found.isDisjoint(with: [.illegalItem, .wrongMegaStone]))
    }
}
