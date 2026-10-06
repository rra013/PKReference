//
//  AppSettings.swift
//  PKReference
//
//  Every app-wide setting's storage key and default, in one place. Views
//  read and write them with `@AppStorage(AppSettings.defaultGeneration)`,
//  so two screens can't disagree on a key's spelling or its default.
//
//  The key names are what's stored in UserDefaults. Renaming one silently
//  resets that setting for everyone, so `AppSettingsTests` pins them.
//
//  The RNG tools' `finder_*` keys aren't here: they remember each tool's
//  form inputs rather than being settings.
//

import SwiftUI

struct SettingKey<Value> {
    let name: String
    let defaultValue: Value
}

enum AppSettings {
    /// The Mon Index's starting filter. Champions also puts the calc, set
    /// builder, speed tiers and paste import in Champions mode.
    static let defaultGeneration = SettingKey(name: "defaultGeneration",
                                              defaultValue: PokedexFilter.champions.rawValue)
    static let defaultTab = SettingKey(name: "defaultTab", defaultValue: AppTab.monIndex.rawValue)
    static let tabOrder = SettingKey(name: TabLayout.orderKey, defaultValue: "")
    static let hiddenTabs = SettingKey(name: TabLayout.hiddenKey, defaultValue: "")
    static let accentColor = SettingKey(name: "appAccentColor", defaultValue: AppAccentColor.blue.rawValue)
    static let appearance = SettingKey(name: "appAppearance", defaultValue: AppAppearance.system.rawValue)
    static let typeBadgeStyle = SettingKey(name: "typeBadgeStyle", defaultValue: TypeBadgeStyle.filled)
    /// The colors marking Pokémon 1 and 2 in the calc.
    static let matchupColors = SettingKey(name: "matchupColors", defaultValue: MatchupColors.tealPink)
    static let density = SettingKey(name: "density", defaultValue: Density.standard)
    /// Off by default: tints a Pokémon's page and cards with its types.
    static let typeBackgrounds = SettingKey(name: "typeBackgrounds", defaultValue: false)
    /// Defaults to `latest`, the same fallback `ChampionsRegulation.current`
    /// uses, so before anything is stored the picker shows the format the
    /// app is actually using.
    static let championsRegulation = SettingKey(name: ChampionsRegulation.userDefaultsKey,
                                                defaultValue: ChampionsRegulation.latest.rawValue)
    /// iPhone and narrow iPad windows: going back from a tab under More with
    /// work in progress, such as a battle, asks first. Turned off by "Leave & Don't Ask Again".
    static let warnBeforeLeavingTab = SettingKey(name: "warnBeforeLeavingTab", defaultValue: true)
    /// When true, swiping to delete a set skips the confirmation alert.
    /// Turned on by "Delete & Don't Ask Again"; Settings shows it inverted,
    /// as "Ask Before Deleting a Set".
    static let instantSetDelete = SettingKey(name: "instantSetDelete", defaultValue: false)
    /// Off by default: Team Search and the Problem Solver read tournament
    /// teams from the PK Reference server, falling back to Limitless.
    static let metaServerEnabled = SettingKey(name: MetaServerSettings.enabledKey, defaultValue: false)
    static let metaServerAddress = SettingKey(name: MetaServerSettings.addressKey,
                                              defaultValue: MetaServerSettings.defaultAddress)
}

extension AppStorage {
    init(_ key: SettingKey<Value>, store: UserDefaults? = nil) where Value == String {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    init(_ key: SettingKey<Value>, store: UserDefaults? = nil) where Value == Bool {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    init(_ key: SettingKey<Value>, store: UserDefaults? = nil)
    where Value: RawRepresentable, Value.RawValue == String {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }
}
