//
//  PKReferenceApp.swift
//  PKReference
//
//  Created by Rishi Anand on 4/13/26.
//

import AppIntents
import SwiftUI
import SwiftData

@main
struct PokedexApp: App {
    let container = AppModelContainer.shared

    init() {
        TabLayout.migrateLegacyStorage()
        TabLayout.migrateRenamedTabs()
        IntentIndex.watchSaves()
        #if DEBUG
        AppNavigator.shared.requestFromLaunchArguments()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .task {
                    // Trigger the private helper function
                    await performStartupSync()
                }
                #if DEBUG && os(macOS)
                .modifier(DebugSnapshot.LaunchArguments())
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        .commands { AppCommands() }
        #endif
        #if DEBUG && os(macOS)
        .commands { DebugSnapshot.Commands() }
        #endif

        #if os(macOS)
        // The standard Settings window (⌘,), in place of iOS's Settings tab.
        Settings {
            SettingsView()
                .formStyle(.grouped)
                .frame(minWidth: 520, minHeight: 480)
                .modifier(AppearanceSettings())
                .modelContainer(container)
        }
        .defaultSize(width: 580, height: 700)
        .windowResizability(.contentMinSize)
        #endif
    }
    
    private func performStartupSync() async {
        let hasSynced = UserDefaults.standard.bool(forKey: "hasCompletedInitialSync")
        if !hasSynced {
            let syncManager = PokeSyncManager(modelContainer: container)
            do {
                print("Starting Pokedex sync...")
                try await syncManager.refreshPokedex()
                UserDefaults.standard.set(true, forKey: "hasCompletedInitialSync")
                print("Pokedex sync completed")
            } catch {
                print("Pokedex sync failed: \(error)")
            }
        }

        // Bumped to V4 when migrating off the stale `beta.pokeapi.co/graphql/v1beta`
        // endpoint to `graphql.pokeapi.co/v1beta2`, so existing installs
        // auto-resync and pick up Legends Z-A content (e.g. Mega Scovillain).
        let hasCalcData = UserDefaults.standard.bool(forKey: "hasCompletedCalcSyncV4")
        if !hasCalcData {
            let calcSync = CalcDataSyncManager(modelContainer: container)
            do {
                print("Starting calc data sync...")
                try await calcSync.syncCalcData()
                UserDefaults.standard.set(true, forKey: "hasCompletedCalcSyncV4")
                print("Calc data sync completed")
            } catch {
                print("Calc data sync failed: \(error)")
            }
        }

        await MainActor.run {
            BattleSimSeed.seedIfNeeded(modelContainer: container)
        }

        // Siri's phrases that name a Pokémon ("What is Garchomp weak to in
        // PK Reference") come from the roster, which is only there now; the
        // ones naming a set or team, and Spotlight's index of them, from
        // what's saved.
        await IntentIndex.refresh()
    }
}
