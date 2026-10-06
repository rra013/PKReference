//
//  AppSettingsTests.swift
//  PKReferenceTests
//
//  Covers `AppSettings`: the stored key names (renaming one resets that
//  setting for everyone, so they're pinned here), that no two settings
//  share a key, and that values read back through `@AppStorage` the way
//  they're stored, falling back to the default when missing or unreadable.
//  Also covers `Density`'s spacing.
//

import Testing
import SwiftUI
@testable import PKReference

@MainActor
@Suite("App Settings")
struct AppSettingsTests {

    private var names: [String] {
        [AppSettings.defaultGeneration.name, AppSettings.defaultTab.name,
         AppSettings.tabOrder.name, AppSettings.hiddenTabs.name,
         AppSettings.accentColor.name, AppSettings.appearance.name,
         AppSettings.typeBadgeStyle.name, AppSettings.density.name,
         AppSettings.typeBackgrounds.name,
         AppSettings.championsRegulation.name, AppSettings.instantSetDelete.name,
         AppSettings.warnBeforeLeavingTab.name, AppSettings.matchupColors.name,
         AppSettings.metaServerEnabled.name, AppSettings.metaServerAddress.name]
    }

    @Test("Key names match what earlier versions stored")
    func pinnedNames() {
        #expect(names == ["defaultGeneration", "defaultTab",
                          "tabOrder", "hiddenTabs",
                          "appAccentColor", "appAppearance",
                          "typeBadgeStyle", "density",
                          "typeBackgrounds",
                          "championsRegulationRaw", "instantSetDelete",
                          "warnBeforeLeavingTab", "matchupColors",
                          "metaServerEnabled", "metaServerAddress"])
    }

    @Test("No two settings share a key")
    func uniqueNames() {
        #expect(Set(names).count == names.count)
    }

    @Test("Defaults match what the screens used before")
    func defaults() {
        #expect(AppSettings.defaultGeneration.defaultValue == PokedexFilter.champions.rawValue)
        #expect(AppSettings.defaultTab.defaultValue == AppTab.monIndex.rawValue)
        #expect(AppSettings.accentColor.defaultValue == AppAccentColor.blue.rawValue)
        #expect(AppSettings.appearance.defaultValue == AppAppearance.system.rawValue)
        #expect(AppSettings.typeBadgeStyle.defaultValue == .filled)
        #expect(AppSettings.matchupColors.defaultValue == .tealPink)
        #expect(AppSettings.density.defaultValue == .standard)
        #expect(AppSettings.typeBackgrounds.defaultValue == false)
        #expect(AppSettings.instantSetDelete.defaultValue == false)
        #expect(AppSettings.warnBeforeLeavingTab.defaultValue == true)
        #expect(AppSettings.metaServerEnabled.defaultValue == false)
        #expect(AppSettings.metaServerAddress.defaultValue == "http://localhost:8080")
    }

    /// A throwaway defaults suite, removed when `body` returns.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("Choices are stored as their raw strings and read back")
    func enumRoundTrip() {
        withDefaults { store in
            #expect(AppStorage(AppSettings.density, store: store).wrappedValue == .standard)

            store.set("compact", forKey: AppSettings.density.name)
            store.set("tinted", forKey: AppSettings.typeBadgeStyle.name)
            store.set("blueGold", forKey: AppSettings.matchupColors.name)
            #expect(AppStorage(AppSettings.density, store: store).wrappedValue == .compact)
            #expect(AppStorage(AppSettings.typeBadgeStyle, store: store).wrappedValue == .tinted)
            #expect(AppStorage(AppSettings.matchupColors, store: store).wrappedValue == .blueGold)

            store.set("bogus", forKey: AppSettings.density.name)
            #expect(AppStorage(AppSettings.density, store: store).wrappedValue == .standard)
        }
    }

    @Test("String and Bool settings read their stored values")
    func plainRoundTrip() {
        withDefaults { store in
            #expect(AppStorage(AppSettings.defaultTab, store: store).wrappedValue == AppTab.monIndex.rawValue)
            store.set("teams", forKey: AppSettings.defaultTab.name)
            store.set(true, forKey: AppSettings.instantSetDelete.name)
            #expect(AppStorage(AppSettings.defaultTab, store: store).wrappedValue == "teams")
            #expect(AppStorage(AppSettings.instantSetDelete, store: store).wrappedValue == true)
        }
    }

    @Test("Standard density keeps spacings; compact scales them by three quarters")
    func densitySpacing() {
        #expect(Density.standard.spacing(CardMetrics.padding) == 16)
        #expect(Density.compact.spacing(CardMetrics.padding) == 12)
        #expect(Density.compact.spacing(CardMetrics.insetPadding) == 9)
        #expect(Density.compact.spacing(20) == 15)
    }
}
