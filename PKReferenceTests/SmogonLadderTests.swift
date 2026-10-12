//
//  SmogonLadderTests.swift
//  PKReferenceTests
//
//  The device's reduction of Smogon's ladder stats (SmogonLadder.reduce):
//  it must make the record the PK Reference server makes from the same two
//  files, number for number. Both sides check
//  backend/src/test/resources/golden/ladder-fixture.json, the fixture under
//  backend/src/test/resources/smogon reduced; the backend's
//  LadderGoldenFileTest and LadderReducerTest are the other half, and the
//  cases below follow theirs.
//

import Testing
import Foundation
@testable import PKReference

private let backend = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "backend/src/test/resources")

struct SmogonLadderTests {
    private struct Golden: Decodable {
        let stats: MetaAPI.LadderStats
    }

    private static let formatID = "gen9championsvgc2026regmc"
    private static let format = SmogonLadderFormat(id: formatID)!

    private static func fixture() throws -> (chaos: Data, leads: String) {
        let directory = backend.appending(path: "smogon/2026-09")
        return (try Data(contentsOf: directory.appending(path: "chaos/\(formatID)-1760.json")),
                try String(contentsOf: directory.appending(path: "leads/\(formatID)-1760.txt"), encoding: .utf8))
    }

    private static func reduce(_ chaos: String, leads: String? = nil) throws -> MetaAPI.LadderStats {
        try SmogonLadder.reduce(chaos: Data(chaos.utf8), leads: leads, format: format, month: "2026-09", rating: 1760,
                                vocabulary: try TeamSearchVocabulary.bundled(for: .mC),
                                names: try MetaNames.bundled(for: .mC))
    }

    private static func share(_ value: String, _ share: Double) -> MetaAPI.LadderShare {
        MetaAPI.LadderShare(value: value, share: share)
    }

    // MARK: The golden file

    @Test func matchesTheBackendsGoldenFile() throws {
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: backend
            .appending(path: "golden/ladder-fixture.json"))).stats
        let (chaos, leads) = try Self.fixture()
        let stats = try SmogonLadder.reduce(chaos: chaos, leads: leads, format: Self.format, month: "2026-09",
                                            rating: 1760, vocabulary: try TeamSearchVocabulary.bundled(for: .mC),
                                            names: try MetaNames.bundled(for: .mC))

        #expect(golden.pokemon.count == 27)
        #expect(stats.reduction == golden.reduction)
        #expect(stats.format == golden.format)
        #expect(stats.regulation == golden.regulation)
        #expect(stats.mode == golden.mode)
        #expect(stats.bestOf == golden.bestOf)
        #expect(stats.battles == golden.battles)
        #expect(stats.pokemon.map(\.name) == golden.pokemon.map(\.name))
        // One at a time, so a difference says which Pokémon and which list.
        for (mine, theirs) in zip(stats.pokemon, golden.pokemon) {
            #expect(mine.key == theirs.key, "\(mine.name)")
            #expect(mine.megaStone == theirs.megaStone, "\(mine.name)")
            #expect(mine.usage == theirs.usage, "\(mine.name)")
            #expect(mine.leadShare == theirs.leadShare, "\(mine.name)")
            #expect(mine.abilities == theirs.abilities, "\(mine.name)")
            #expect(mine.items == theirs.items, "\(mine.name)")
            #expect(mine.moves == theirs.moves, "\(mine.name)")
            #expect(mine.natures == theirs.natures, "\(mine.name)")
            #expect(mine.spreads == theirs.spreads, "\(mine.name)")
            #expect(mine.teammates == theirs.teammates, "\(mine.name)")
        }
        #expect(stats == golden)
    }

    // MARK: Formats

    @Test func readsSmogonsFormatIDs() throws {
        let doubles = try #require(SmogonLadderFormat(id: "gen9championsvgc2026regmc"))
        #expect(doubles.regulation == .mC && doubles.mode == .doubles && doubles.bestOf == 1)
        let bestOfThree = try #require(SmogonLadderFormat(id: "gen9championsvgc2026regmbbo3"))
        #expect(bestOfThree.regulation == .mB && bestOfThree.mode == .doubles && bestOfThree.bestOf == 3)
        let singles = try #require(SmogonLadderFormat(id: "gen9championsbssregmc"))
        #expect(singles.regulation == .mC && singles.mode == .singles && singles.bestOf == 1)
        // Another year's doubles, and another generation's.
        #expect(SmogonLadderFormat(id: "gen10championsvgc2027regma")?.regulation == .mA)

        for id in ["gen9championsou", "gen9championsuu", "gen9vgc2026regi", "gen9championsvgc2026regmz",
                   "gen9championsvgc2026regmc-1760", "gen9championsbssreg", "championsbssregmc", ""] {
            #expect(SmogonLadderFormat(id: id) == nil, "\(id)")
        }

        let file = try #require(SmogonLadderFormat.file("gen9championsbssregmb-1630.json"))
        #expect(file.format.id == "gen9championsbssregmb" && file.rating == 1630)
        #expect(SmogonLadderFormat.file("gen9championsou-1760.json") == nil)
        #expect(SmogonLadderFormat.file("gen9championsbssregmb.json") == nil)

        let request = LadderRequest(regulation: .mC, mode: .doubles, bestOf: 3, rating: 1500)
        #expect(SmogonLadderFormat(id: "gen9championsvgc2026regmbbo3")!.matches(request), "the regulation is chosen apart")
        #expect(!doubles.matches(request))
        #expect(!singles.matches(request))
        #expect(LadderRequest.teamSearch(.mB) == LadderRequest(regulation: .mB, mode: .doubles, bestOf: 1, rating: 1760))
    }

    // MARK: The rule

    @Test func speciesKeysAndMegas() throws {
        let (chaos, leads) = try Self.fixture()
        let stats = try SmogonLadder.reduce(chaos: chaos, leads: leads, format: Self.format, month: "2026-09",
                                            rating: 1760, vocabulary: try TeamSearchVocabulary.bundled(for: .mC),
                                            names: try MetaNames.bundled(for: .mC))
        func named(_ name: String) throws -> MetaAPI.LadderPokemon {
            try #require(stats.pokemon.first { $0.name == name })
        }
        #expect(try named("Sirfetch'd").key == "sirfetchd", "the regulation's files spell it without the apostrophe")
        let vocabulary = try TeamSearchVocabulary.bundled(for: .mC)
        #expect(vocabulary.term(showdownName: "Farfetch\u{2019}d") == vocabulary.term(showdownName: "Farfetch'd"))
        #expect(vocabulary.term(showdownName: "Farfetch'd")?.speciesID == "farfetchd")
        #expect(try named("Indeedee-F").key == "indeedee:female")
        #expect(try named("Tauros-Paldea-Aqua").key == "tauros:aqua-paldea")
        #expect(try named("Lucario-Mega").megaStone == "Lucarionite")
        #expect(try named("Lucario-Mega-Z").megaStone == "Lucarionite Z")
        #expect(try named("Salamence").megaStone == nil)
        // Zoroark leads as something else (Illusion), so the leads file doesn't list it.
        #expect(try named("Zoroark-Hisui").leadShare == nil)
        #expect(Set(stats.pokemon.map(\.name)).count == stats.pokemon.count)

        // Without the regulation's data: no keys, and IDs as Smogon has them.
        let bare = try SmogonLadder.reduce(chaos: chaos, leads: nil, format: Self.format, month: "2026-09",
                                           rating: 1760, vocabulary: nil, names: nil)
        #expect(bare.pokemon.count == 27)
        #expect(bare.pokemon.allSatisfy { $0.key == nil && $0.megaStone == nil && $0.leadShare == nil })
        #expect(bare.pokemon[0].items.first == Self.share("miracleseed", 0.62503))
    }

    @Test func awkwardInput() throws {
        let stats = try Self.reduce("""
            {"data": {
              "Nobodymon": {"usage": 0.5, "Abilities": {"madeupability": 10}, "Items": {"nothing": 6, "madeupitem": 4},
                            "Moves": {"": 3, "protect": 10, "madeupmove": 10}, "Spreads": {"Jolly:0/32/0/0/2/32": 4,
                            "Jolly:2/32/0/0/0/32": 4, "Timid:0/0/0/32/2/32": 2, "broken": 1},
                            "Teammates": {"Rillaboom": 5, "Gone": 0, "Minus": -1}},
              "Unused": {"usage": 0, "Abilities": {"overgrow": 10}},
              "Weightless": {"usage": 0.1, "Abilities": {}},
              "Bare": {"usage": 0.25, "Abilities": {"overgrow": 2}},
              "Rillaboom": {"usage": 0.5, "Abilities": {"overgrow": 1, "grassysurge": 1}, "Items": 7},
              "NotAnEntry": 3
             },
             "extra": [1, {"a": 2}],
             "info": {"number of battles": 12}}
            """)

        #expect(stats.battles == 12)
        // Equal usage: by name. No usage, or no weight: left out.
        #expect(stats.pokemon.map(\.name) == ["Nobodymon", "Rillaboom", "Bare"])

        let nobody = stats.pokemon[0]
        #expect(nobody.key == nil, "not in the regulation")
        // IDs nothing matches stay as they are; they're never guessed at.
        #expect(nobody.abilities == [Self.share("madeupability", 1)])
        #expect(nobody.items == [Self.share("No Item", 0.6), Self.share("madeupitem", 0.4)])
        // The empty move slot isn't a move. Equal counts: by ID.
        #expect(nobody.moves == [Self.share("madeupmove", 1), Self.share("Protect", 1)])
        #expect(nobody.natures == [Self.share("Jolly", 0.8), Self.share("Timid", 0.2)])
        #expect(nobody.spreads.map(\.value) == ["Jolly:0/32/0/0/2/32", "Jolly:2/32/0/0/0/32", "Timid:0/0/0/32/2/32",
                                                "broken"])
        #expect(nobody.teammates == [Self.share("Rillaboom", 0.5)])

        #expect(stats.pokemon[2].items.isEmpty && stats.pokemon[2].moves.isEmpty && stats.pokemon[2].spreads.isEmpty)
        #expect(stats.pokemon[1].abilities == [Self.share("Grassy Surge", 0.5), Self.share("Overgrow", 0.5)])
        #expect(stats.pokemon[1].items.isEmpty, "not an object")
    }

    @Test func cutsAndRounds() throws {
        let abilities = (0..<8).map { "\"ability\($0)\": \(8 - $0)" }.joined(separator: ", ")
        let stats = try Self.reduce("""
            {"data": {"Rillaboom": {"usage": 0.5, "Abilities": {\(abilities)},
                                    "Items": {"leftovers": 12, "lifeorb": 24, "sitrusberry": 0.1}}}}
            """)
        let pokemon = stats.pokemon[0]
        #expect(pokemon.abilities.count == SmogonLadder.abilityLimit)
        #expect(pokemon.abilities[0] == Self.share("ability0", 0.22222))
        // 0.1 of 36 is under half a percent.
        #expect(pokemon.items == [Self.share("Life Orb", 0.66667), Self.share("Leftovers", 0.33333)])
        #expect(SmogonLadder.round(0.000005) == 0, "half to even")
        #expect(SmogonLadder.round(0.000015) == 0.00002)
        // As Smogon wrote Salamence's usage, and as JSONSerialization reads it.
        #expect(SmogonLadder.roundUsage(0.0032668000000000003) == 0.0032668)
        #expect(SmogonLadder.roundUsage(0.0032668000000000016) == 0.0032668)
    }

    @Test func readsTheLeadsTable() {
        let shares = SmogonLadder.leadShares("""
             Total leads: 3263886
             + ---- + ------------------ + --------- + ------ + ------- +
             | Rank | Pokemon            | Usage %   | Raw    | %       |
             + ---- + ------------------ + --------- + ------ + ------- +
             | 1    | Sneasler           |  6.59479% | 204684 |  6.271% |\r
             | 2    | Mr. Rime           |  0.01127% | 4      |  0.000% |
             | x    | Not A Row          |  1.00000% | 4      |  0.000% |
             | 3    | Broken             |  lots     | 4      |  0.000% |
            """)
        #expect(shares.keys.sorted() == ["Mr. Rime", "Sneasler"])
        #expect(shares["Sneasler"] == 0.0659479)
        #expect(SmogonLadder.leadShares(nil).isEmpty)
    }

    @Test func notSmogonsStats() {
        for text in ["[]", "{\"info\": {}}", "<html>404</html>", "{\"data\": {\"Rillaboom\": {\"usage\": 0.5"] {
            #expect(throws: SmogonUsageError.unreadableStats, "\(text)") { try Self.reduce(text) }
        }
    }

    @Test func byteOrder() {
        #expect(["b", "a", "Z", "é", "a-b", "ab"].sorted(by: SmogonLadder.bytesPrecede) == ["Z", "a", "a-b", "ab", "b", "é"])
    }

    // MARK: Team Search's view

    @Test func teamSearchReadsUsageAndTeammates() throws {
        let stats = try Self.reduce(TeamSearchFixtures.smogonChaosJSON)
        let usage = SmogonUsage(stats)
        #expect(usage.battles == 1000)
        #expect(usage.format == Self.formatID && usage.month == "2026-09" && usage.rating == 1760)
        #expect(usage.regulation == .mC)
        #expect(usage.species.map(\.name) == ["Incineroar", "Garchomp", "Charizard-Mega-Y"])
        #expect(usage.species[0].usage == 0.4)
        #expect(usage.species[0].teammates == [.init(name: "Garchomp", share: 0.5),
                                               .init(name: "Charizard-Mega-Y", share: 0.3)])
        #expect(usage.species[1].teammates.map(\.share) == [0.75, 0.7])
    }
}
