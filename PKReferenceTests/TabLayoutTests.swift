//
//  TabLayoutTests.swift
//  PKReferenceTests
//
//  Covers `TabLayout`: hidden tabs staying hidden across a reload (the old
//  format re-added them on every launch), new tabs appearing, reordering,
//  the last-visible-tab guard, the launch tab fallback, where tabs land in
//  a compact tab bar, when there's a More list, and converting the retired
//  `enabledTabs` list.
//

import Testing
import Foundation
import SwiftUI
@testable import PKReference

@MainActor
@Suite("Tab Layout")
struct TabLayoutTests {

    /// Saves `layout` the way the app does and reads it back.
    private func reloaded(_ layout: TabLayout) -> TabLayout {
        TabLayout(orderRaw: layout.orderRaw, hiddenRaw: layout.hiddenRaw)
    }

    // MARK: Storage

    @Test("Nothing stored gives every tab in the default order")
    func defaults() {
        let layout = TabLayout(orderRaw: "", hiddenRaw: "")
        #expect(layout.order == AppTab.allUserTabs)
        #expect(layout.visible == AppTab.allUserTabs)
    }

    @Test("A hidden tab stays hidden after a reload")
    func hiddenSurvivesReload() {
        var layout = TabLayout()
        layout.setHidden(.moveIndex, true)
        layout.setHidden(.abilityIndex, true)

        let restored = reloaded(layout)
        #expect(restored == layout)
        #expect(!restored.visible.contains(.moveIndex))
        #expect(!restored.visible.contains(.abilityIndex))
    }

    @Test("A tab missing from the stored order is added at the end, shown")
    func newTabAppended() {
        let layout = TabLayout(orderRaw: "teams,monIndex", hiddenRaw: "monIndex")
        #expect(Array(layout.order.prefix(2)) == [.teams, .monIndex])
        #expect(layout.order.count == AppTab.allUserTabs.count)
        #expect(layout.visible.last == AppTab.allUserTabs.last)
        #expect(layout.hidden == [.monIndex])
    }

    @Test("Unknown names, duplicates and Settings are dropped")
    func cleansStoredValues() {
        let layout = TabLayout(orderRaw: "teams,bogus,teams,settings", hiddenRaw: "settings,bogus")
        #expect(layout.order.first == .teams)
        #expect(layout.order.filter { $0 == .teams }.count == 1)
        #expect(!layout.order.contains(.settings))
        #expect(layout.hidden.isEmpty)
    }

    // MARK: Editing

    @Test("Moving a tab reorders it, and the order survives a reload")
    func moveReorders() {
        var layout = TabLayout()
        let teamsIndex = layout.order.firstIndex(of: .teams)!
        layout.move(fromOffsets: IndexSet(integer: teamsIndex), toOffset: 0)
        #expect(layout.order.first == .teams)
        #expect(reloaded(layout).order.first == .teams)
    }

    @Test("Showing a hidden tab again puts it back in its place")
    func hiddenKeepsPosition() {
        var layout = TabLayout()
        layout.setHidden(.moveIndex, true)
        layout.setHidden(.moveIndex, false)
        #expect(layout.visible == AppTab.allUserTabs)
    }

    @Test("The last shown tab can't be hidden")
    func lastVisibleStays() {
        var layout = TabLayout()
        for tab in AppTab.allUserTabs where tab != .teams {
            layout.setHidden(tab, true)
        }
        #expect(layout.visible == [.teams])
        #expect(!layout.canHide(.teams))

        layout.setHidden(.teams, true)
        #expect(layout.visible == [.teams])
    }

    // MARK: Launch tab

    @Test("The launch tab falls back to the first shown tab")
    func launchTabFallback() {
        var layout = TabLayout()
        #expect(layout.launchTab(for: "teams") == .teams)

        layout.setHidden(.teams, true)
        #expect(layout.launchTab(for: "teams") == .monIndex)
        #expect(layout.launchTab(for: "bogus") == .monIndex)
    }

    // MARK: Compact tab bar

    @Test("With more than five tabs, the first four are in the bar")
    func placementOverflow() {
        let layout = TabLayout()
        let placements = layout.visible.map(layout.compactPlacement)
        #expect(placements.prefix(4).allSatisfy { $0 == .tabBar })
        #expect(placements.dropFirst(4).allSatisfy { $0 == .more })
    }

    @Test("Four tabs plus Settings all fit in the bar")
    func placementFits() {
        var layout = TabLayout()
        for tab in AppTab.allUserTabs.dropFirst(4) {
            layout.setHidden(tab, true)
        }
        #expect(layout.visible.allSatisfy { layout.compactPlacement(of: $0) == .tabBar })
        #expect(layout.compactPlacement(of: AppTab.allUserTabs.last!) == .hidden)
    }

    @Test("Five tabs plus Settings overflow, so the fifth goes under More")
    func placementFiveTabs() {
        var layout = TabLayout()
        for tab in AppTab.allUserTabs.dropFirst(5) {
            layout.setHidden(tab, true)
        }
        #expect(layout.compactPlacement(of: layout.visible[3]) == .tabBar)
        #expect(layout.compactPlacement(of: layout.visible[4]) == .more)
    }

    @Test("With overflow, the bar holds four tabs and More holds the rest, Settings last")
    func splitOverflow() {
        let split = TabLayout().compactSplit
        #expect(split.bar == Array(AppTab.allUserTabs.prefix(4)))
        #expect(split.more == Array(AppTab.allUserTabs.dropFirst(4)) + [.settings])
    }

    @Test("When everything fits, the bar holds it all and there's no More list")
    func splitFits() {
        var layout = TabLayout()
        for tab in AppTab.allUserTabs.dropFirst(4) {
            layout.setHidden(tab, true)
        }
        let split = layout.compactSplit
        #expect(split.bar == Array(AppTab.allUserTabs.prefix(4)) + [.settings])
        #expect(split.more.isEmpty)
    }

    @Test("The split follows the user's order and skips hidden tabs")
    func splitOrderAndHidden() {
        var layout = TabLayout()
        layout.move(fromOffsets: IndexSet(integer: layout.order.firstIndex(of: .teams)!), toOffset: 0)
        layout.setHidden(.moveIndex, true)
        let split = layout.compactSplit
        #expect(split.bar.first == .teams)
        #expect(!split.bar.contains(.moveIndex) && !split.more.contains(.moveIndex))
        #expect(split.bar.count + split.more.count == AppTab.allUserTabs.count)  // 10 shown + Settings
    }

    @Test("iPhone always has a More list; iPad only in a compact-width window")
    func moreListByDevice() {
        #expect(TabLayout.usesMoreList(idiom: .phone, sizeClass: .regular))
        #expect(TabLayout.usesMoreList(idiom: .phone, sizeClass: .compact))
        #expect(TabLayout.usesMoreList(idiom: .pad, sizeClass: .compact))
        #expect(!TabLayout.usesMoreList(idiom: .pad, sizeClass: .regular))
        // Before the size class is known, an iPad starts without one.
        #expect(!TabLayout.usesMoreList(idiom: .pad, sizeClass: nil))
    }

    // MARK: Converting the retired format

    /// A throwaway defaults suite, removed when `body` returns.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "TabLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("The old list converts to an order, with unlisted tabs hidden")
    func migratesLegacyList() {
        withDefaults { defaults in
            defaults.set("damageCalc,monIndex", forKey: TabLayout.legacyEnabledKey)
            TabLayout.migrateLegacyStorage(in: defaults)

            let layout = TabLayout(orderRaw: defaults.string(forKey: TabLayout.orderKey) ?? "",
                                   hiddenRaw: defaults.string(forKey: TabLayout.hiddenKey) ?? "")
            #expect(layout.visible == [.damageCalc, .monIndex])
            #expect(layout.order.count == AppTab.allUserTabs.count)
            #expect(defaults.string(forKey: TabLayout.legacyEnabledKey) == nil)
        }
    }

    @Test("An empty old list hides nothing")
    func migratesEmptyLegacyList() {
        withDefaults { defaults in
            defaults.set("", forKey: TabLayout.legacyEnabledKey)
            TabLayout.migrateLegacyStorage(in: defaults)
            #expect(defaults.string(forKey: TabLayout.hiddenKey) == "")
        }
    }

    @Test("The Tournaments tab becomes Meta, keeping its place, its hidden state and the default tab")
    func migratesRenamedTab() {
        withDefaults { defaults in
            defaults.set("monIndex,tournaments,teams", forKey: TabLayout.orderKey)
            defaults.set("tournaments", forKey: TabLayout.hiddenKey)
            defaults.set("tournaments", forKey: AppSettings.defaultTab.name)
            TabLayout.migrateRenamedTabs(in: defaults)
            #expect(defaults.string(forKey: TabLayout.orderKey) == "monIndex,meta,teams")
            #expect(defaults.string(forKey: TabLayout.hiddenKey) == "meta")
            #expect(defaults.string(forKey: AppSettings.defaultTab.name) == "meta")

            let layout = TabLayout(orderRaw: defaults.string(forKey: TabLayout.orderKey) ?? "",
                                   hiddenRaw: defaults.string(forKey: TabLayout.hiddenKey) ?? "")
            #expect(layout.order.prefix(3) == [.monIndex, .meta, .teams])
            #expect(!layout.visible.contains(.meta))

            // Twice changes nothing more.
            TabLayout.migrateRenamedTabs(in: defaults)
            #expect(defaults.string(forKey: TabLayout.orderKey) == "monIndex,meta,teams")
        }
    }

    @Test("A legacy list naming Tournaments converts, then becomes Meta")
    func migratesLegacyListWithRenamedTab() {
        withDefaults { defaults in
            defaults.set("tournaments,monIndex", forKey: TabLayout.legacyEnabledKey)
            TabLayout.migrateLegacyStorage(in: defaults)
            TabLayout.migrateRenamedTabs(in: defaults)
            let layout = TabLayout(orderRaw: defaults.string(forKey: TabLayout.orderKey) ?? "",
                                   hiddenRaw: defaults.string(forKey: TabLayout.hiddenKey) ?? "")
            #expect(layout.visible == [.meta, .monIndex])
            #expect(TabLayout(orderRaw: "tournaments", hiddenRaw: "").order.first == .meta, "read before migrating")
            #expect(TabLayout().launchTab(for: "tournaments") == .meta)
        }
    }

    @Test("Nothing stored, or nothing renamed, is left alone")
    func renameLeavesOthersAlone() {
        withDefaults { defaults in
            TabLayout.migrateRenamedTabs(in: defaults)
            #expect(defaults.string(forKey: TabLayout.orderKey) == nil)
            defaults.set("teams,monIndex", forKey: TabLayout.orderKey)
            TabLayout.migrateRenamedTabs(in: defaults)
            #expect(defaults.string(forKey: TabLayout.orderKey) == "teams,monIndex")
        }
    }

    @Test("Conversion does nothing once the new order is stored")
    func migrationRunsOnce() {
        withDefaults { defaults in
            defaults.set("teams", forKey: TabLayout.orderKey)
            defaults.set("monIndex", forKey: TabLayout.legacyEnabledKey)
            TabLayout.migrateLegacyStorage(in: defaults)
            #expect(defaults.string(forKey: TabLayout.orderKey) == "teams")
            #expect(defaults.string(forKey: TabLayout.legacyEnabledKey) == "monIndex")
        }
    }
}
