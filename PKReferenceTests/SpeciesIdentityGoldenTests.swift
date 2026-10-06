//
//  SpeciesIdentityGoldenTests.swift
//  PKReferenceTests
//
//  The backend names Limitless team members' species the app's way, so its
//  numbers can match the app's. Both sides check the same golden file,
//  backend/src/test/resources/golden/species-identity.json; the backend's
//  SpeciesVocabularyGoldenTest is the other half.
//

import Testing
import Foundation
@testable import PKReference

@MainActor
struct SpeciesIdentityGoldenTests {
    private struct Golden: Decodable {
        let cases: [Case]
        struct Case: Decodable {
            let format: String
            let name: String
            let slug: String?
            let item: String?
            let key: String
            let mega: String?
        }
    }

    private static var goldenURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "backend/src/test/resources/golden/species-identity.json")
    }

    @Test func matchesTheBackendsGoldenFile() throws {
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: Self.goldenURL))
        #expect(golden.cases.count > 150)
        var vocabularies: [ChampionsRegulation: TeamSearchVocabulary] = [:]
        for c in golden.cases {
            let key: String
            let mega: String?
            if let regulation = ChampionsRegulation(rawValue: c.format.lowercased()) {
                let vocabulary = try vocabularies[regulation] ?? TeamSearchVocabulary.bundled(for: regulation)
                vocabularies[regulation] = vocabulary
                let identity = vocabulary.identity(name: c.name, slug: c.slug)
                key = identity.key
                mega = vocabulary.mega(heldItem: c.item, speciesID: identity.speciesID)?.stoneID
            } else {
                key = toID(c.slug.flatMap { $0.isEmpty ? nil : $0 } ?? c.name)
                mega = nil
            }
            #expect(key == c.key, "\(c.format) \(c.name) \(c.slug ?? "-")")
            #expect(mega == c.mega, "\(c.format) \(c.name) \(c.item ?? "-")")
        }
    }
}
