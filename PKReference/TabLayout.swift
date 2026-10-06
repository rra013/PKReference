//
//  TabLayout.swift
//  PKReference
//
//  The user's tab arrangement: every tab in their chosen order, plus the
//  ones they've hidden.
//
//  Order and visibility are stored separately. A hidden tab keeps its
//  place, so showing it again puts it back where it was. And a tab missing
//  from the stored order can only be one added in an update, so it's shown
//  at the end. The retired format, one list of visible tabs, couldn't tell
//  a hidden tab from a new one, and re-added every hidden tab on the next
//  launch.
//

import SwiftUI

struct TabLayout: Equatable {
    static let orderKey = "tabOrder"
    static let hiddenKey = "hiddenTabs"
    /// The retired format: the visible tabs, in order. Converted once, at
    /// launch, by `migrateLegacyStorage(in:)`.
    static let legacyEnabledKey = "enabledTabs"

    /// A compact-width tab bar (iPhone, or a narrow iPad window) holds this
    /// many items. With more, it shows one fewer and puts the rest under a
    /// More tab.
    static let compactBarCapacity = 5

    /// Every user tab, in display order. Settings isn't included: it always
    /// comes last and can't be hidden.
    private(set) var order: [AppTab]
    private(set) var hidden: Set<AppTab>

    init(order: [AppTab] = AppTab.allUserTabs, hidden: Set<AppTab> = []) {
        // Drop duplicates and non-user tabs, then add any tab the stored
        // order predates.
        var seen = Set<AppTab>()
        var cleaned = order.filter { AppTab.allUserTabs.contains($0) && seen.insert($0).inserted }
        cleaned += AppTab.allUserTabs.filter { !seen.contains($0) }
        self.order = cleaned
        self.hidden = hidden.intersection(AppTab.allUserTabs)
    }

    init(orderRaw: String, hiddenRaw: String) {
        self.init(order: Self.parse(orderRaw), hidden: Set(Self.parse(hiddenRaw)))
    }

    var orderRaw: String { Self.serialize(order) }
    /// Hidden tabs in display order, so the stored string is stable.
    var hiddenRaw: String { Self.serialize(order.filter(hidden.contains)) }

    /// The tabs to show, in order. Never empty: if every tab were hidden,
    /// which `setHidden` doesn't allow, all of them are shown.
    var visible: [AppTab] {
        let shown = order.filter { !hidden.contains($0) }
        return shown.isEmpty ? order : shown
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }

    /// False only for the last visible tab.
    func canHide(_ tab: AppTab) -> Bool { visible != [tab] }

    mutating func setHidden(_ tab: AppTab, _ isHidden: Bool) {
        if isHidden {
            guard canHide(tab) else { return }
            hidden.insert(tab)
        } else {
            hidden.remove(tab)
        }
    }

    /// The tab `raw` names if it's visible, otherwise the first visible
    /// tab, so hiding the default tab can't leave the app opening to one
    /// that isn't there.
    func launchTab(for raw: String) -> AppTab {
        if let tab = Self.tab(named: raw), visible.contains(tab) { return tab }
        return visible[0]
    }

    enum Placement: Equatable { case tabBar, more, hidden }

    /// A compact tab bar's contents, Settings included: the tabs in the bar,
    /// and the rest, which go in the More list. When everything fits there's
    /// no More list; otherwise the bar keeps one slot for the More tab.
    var compactSplit: (bar: [AppTab], more: [AppTab]) {
        let all = visible + [.settings]
        guard all.count > Self.compactBarCapacity else { return (all, []) }
        let fit = Self.compactBarCapacity - 1
        return (Array(all.prefix(fit)), Array(all.dropFirst(fit)))
    }

    /// Where `tab` lands in a compact-width tab bar.
    func compactPlacement(of tab: AppTab) -> Placement {
        let split = compactSplit
        if split.bar.contains(tab) { return .tabBar }
        if split.more.contains(tab) { return .more }
        return .hidden
    }

    /// Whether the tab bar overflows into the app's own More list: always
    /// on iPhone, and on iPad in a compact-width window, where the system
    /// tab bar is the iPhone one and would otherwise put the rest under its
    /// own More tab, with a second navigation bar. A wide iPad tab bar has
    /// room for every tab.
    static func usesMoreList(in sizeClass: UserInterfaceSizeClass?) -> Bool {
        #if os(iOS)
        usesMoreList(idiom: UIDevice.current.userInterfaceIdiom, sizeClass: sizeClass)
        #else
        false
        #endif
    }

    #if os(iOS)
    static func usesMoreList(idiom: UIUserInterfaceIdiom, sizeClass: UserInterfaceSizeClass?) -> Bool {
        idiom == .phone || sizeClass == .compact
    }
    #endif

    /// Converts the retired `enabledTabs` list, keeping its order and
    /// treating tabs it didn't list as hidden. Runs before any view reads
    /// the layout, so the first frame already uses it; does nothing once
    /// converted.
    static func migrateLegacyStorage(in defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: orderKey) == nil,
              let legacy = defaults.string(forKey: legacyEnabledKey) else { return }
        let enabled = parse(legacy)
        // The old code showed every tab when the list was empty or unreadable.
        let hidden = enabled.isEmpty ? [] : Set(AppTab.allUserTabs).subtracting(enabled)
        let layout = TabLayout(order: enabled, hidden: hidden)
        defaults.set(layout.orderRaw, forKey: orderKey)
        defaults.set(layout.hiddenRaw, forKey: hiddenKey)
        defaults.removeObject(forKey: legacyEnabledKey)
    }

    /// Tabs that were renamed: the stored name, and the tab it became. The
    /// Tournaments tab became Meta, with Events inside it (2026-10).
    static let renamedTabs = ["tournaments": AppTab.meta]

    /// Moves the default tab, the order and the hidden tabs from a renamed
    /// tab's old name to its new one, so it keeps its place and stays hidden
    /// if it was. Without this, the old name is dropped as unknown and the
    /// tab comes back at the end, shown. Runs at launch, after
    /// `migrateLegacyStorage(in:)`; does nothing once no setting names an
    /// old tab.
    static func migrateRenamedTabs(in defaults: UserDefaults = .standard) {
        func renamed(_ raw: String) -> String {
            raw.split(separator: ",", omittingEmptySubsequences: false)
                .map { renamedTabs[String($0)]?.rawValue ?? String($0) }
                .joined(separator: ",")
        }
        for key in [orderKey, hiddenKey, AppSettings.defaultTab.name] {
            guard let raw = defaults.string(forKey: key) else { continue }
            let new = renamed(raw)
            if new != raw { defaults.set(new, forKey: key) }
        }
    }

    /// The tab a stored name means, including a renamed tab's old name.
    static func tab(named raw: String) -> AppTab? {
        AppTab(rawValue: raw) ?? renamedTabs[raw]
    }

    private static func parse(_ raw: String) -> [AppTab] {
        raw.split(separator: ",").compactMap { tab(named: String($0)) }
    }

    private static func serialize(_ tabs: [AppTab]) -> String {
        tabs.map(\.rawValue).joined(separator: ",")
    }
}
