//
//  HeldItemTests.swift
//  PKReferenceTests
//
//  Covers `HeldItem`: the built-in items plus a Mega stone for every
//  stone-triggered form in `mega_forms.json` make up every item; names are
//  unique; an unknown name isn't an item; the item tables only use
//  built-in items; and the picker puts a species' own stones first and
//  hides the rest, leaves out the items the Champions calc ignores in
//  Champions mode only, and always lists the item a set holds. When the item enum became data-backed (2026-09-28), the
//  items, the type tables and every Mega species' picker list were checked
//  identical to the enum's.
//

import Testing
@testable import PKReference

@Suite("Held Items")
struct HeldItemTests {

    @Test("Every item is a built-in one or a stone from mega_forms.json")
    func allCases() {
        let stones = MegaForms.all.compactMap(\.stone)
        #expect(HeldItem.allCases == HeldItem.builtIns + stones)
        #expect(HeldItem.builtIns.count == 70)
        #expect(stones.count == 86)
        #expect(HeldItem.builtIns.allSatisfy { !$0.isMegaStone })
        #expect(stones.allSatisfy { $0.isMegaStone })
    }

    @Test("Names are unique, and look up the same item")
    func names() {
        let names = HeldItem.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
        for item in HeldItem.allCases {
            #expect(HeldItem(rawValue: item.rawValue) == item)
            #expect(item.description == item.rawValue)
        }
        #expect(HeldItem(rawValue: "Pikachunite") == nil)
        #expect(HeldItem(rawValue: "leftovers") == nil)
    }

    /// Sets saved before Golisopite and Baxcalibrite were renamed hold the
    /// old names; they still load as the stone, under its current name.
    @Test("A renamed item's old name gives the item under its current name")
    func renamedItems() {
        let names = Set(HeldItem.allCases.map(\.rawValue))
        for (old, current) in HeldItem.renamed {
            #expect(!names.contains(old), "\(old)")
            #expect(names.contains(current), "\(current)")
            #expect(HeldItem(rawValue: old)?.rawValue == current)
            #expect(HeldItem(rawValue: old)?.isMegaStone == true)
            #expect(HeldItem.currentName(old) == current)
        }
        #expect(HeldItem(rawValue: "Golisopodite")?.rawValue == "Golisopite")
        #expect(HeldItem(rawValue: "Baxcaliburite")?.rawValue == "Baxcalibrite")
        #expect(HeldItem.currentName("Leftovers") == "Leftovers")
        #expect(HeldItem.currentName("Not An Item") == "Not An Item")
    }

    @Test("The item tables only use built-in items")
    func tablesUseBuiltIns() {
        let builtIns = Set(HeldItem.builtIns)
        #expect(Set(typeBoostingItemMap.keys).isSubset(of: builtIns))
        #expect(Set(typeResistBerryMap.keys).isSubset(of: builtIns))
        #expect(HeldItem.nonChampionsItems.isSubset(of: builtIns))
        #expect(typeBoostingItemMap.count == 18)
        #expect(typeResistBerryMap.count == 17)
    }

    @Test("A species' picker lists its own stones first and no others")
    func pickerStones() {
        let options = HeldItem.pickerOptions(forSpeciesNamed: "Charizard", championsMode: true)
        #expect(options.prefix(2).map(\.rawValue) == ["Charizardite X", "Charizardite Y"])
        #expect(options.filter(\.isMegaStone).count == 2)
        #expect(HeldItem.pickerOptions(forSpeciesNamed: "Pikachu", championsMode: true)
            .allSatisfy { !$0.isMegaStone })
    }

    @Test("Champions mode leaves out the items its calc ignores; mainline lists them")
    func pickerByMode() {
        let champions = HeldItem.pickerOptions(forSpeciesNamed: "Heatran", championsMode: true)
        let mainline = HeldItem.pickerOptions(forSpeciesNamed: "Heatran", championsMode: false)
        #expect(champions.allSatisfy { !HeldItem.nonChampionsItems.contains($0) })
        #expect(HeldItem.nonChampionsItems.isSubset(of: Set(mainline)))
        #expect(mainline.count == champions.count + HeldItem.nonChampionsItems.count)
    }

    /// A set saved in mainline mode, or pasted, can hold an item the picker
    /// wouldn't offer; it's listed, once, so the picker isn't blank.
    @Test("The held item is always listed, once", arguments: [true, false])
    func pickerKeepsCurrent(championsMode: Bool) {
        for (species, held) in [("Heatran", HeldItem.choiceSpecs), ("Pikachu", .charizarditeX),
                                ("Heatran", .leftovers), ("Heatran", .none)] {
            let options = HeldItem.pickerOptions(forSpeciesNamed: species, championsMode: championsMode,
                                                 keeping: held)
            #expect(options.filter { $0 == held }.count == 1, "\(species) holding \(held)")
            #expect(Set(options).count == options.count)
        }
    }

    @Test("An item the Champions calc ignores says so in Champions mode")
    func pickerLabels() {
        #expect(HeldItem.choiceSpecs.pickerLabel(championsMode: true) == "Choice Specs (not in Champions)")
        #expect(HeldItem.choiceSpecs.pickerLabel(championsMode: false) == "Choice Specs")
        #expect(HeldItem.leftovers.pickerLabel(championsMode: true) == "Leftovers")
    }
}
