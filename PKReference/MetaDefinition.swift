//
//  MetaDefinition.swift
//  PKReference
//
//  What each of the Meta tab's numbers means, as its ⓘ shows it. The texts
//  are BackendIntegration-PLAN.md §4.2's word for word: change both
//  together.
//

import SwiftUI

nonisolated enum MetaDefinition: String, CaseIterable, Identifiable, Sendable {
    case usage, topCut, winRate, topEight, teamRecord, trend, core, archetype, set, windows, sample

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usage: "Usage"
        case .topCut: "Top-Cut Rate"
        case .winRate: "Win Rate"
        case .topEight: "Top-8 Rate"
        case .teamRecord: "Team Record"
        case .trend: "Trend"
        case .core: "Core"
        case .archetype: "Archetype"
        case .set: "Set"
        case .windows: "Windows"
        case .sample: "Sample Size"
        }
    }

    var text: String {
        switch self {
        case .usage:
            "The share of published teams in the window that have the Pokémon. Each team counts once."
        case .topCut:
            "Its share among teams that played in a top cut (a bracket phase of the event). Events without a "
                + "bracket add no top-cut teams. Next to usage, it shows whether a Pokémon does better or worse "
                + "than its popularity."
        case .winRate:
            "Match wins out of matches, for teams with it, from the pairings. Mirror matches (both teams have it) "
                + "don't count; a tie is half a win. It's shown with a 95% range (Wilson), and hidden under 30 "
                + "matches."
        case .topEight:
            "Its share among teams placed 1st to 8th. The device has placings but not the events' phases, so it "
                + "can't tell who played in a top cut."
        case .teamRecord:
            "The wins, losses and ties of teams with it, from their standings. Without pairings, mirror matches "
                + "can't be left out. A tie is half a win; shown with a 95% range and hidden under 30 matches, as "
                + "win rate is."
        case .trend:
            "Usage over the last 14 days against the 14 before, in percentage points. Hidden when either "
                + "fortnight has under 50 teams."
        case .core:
            "Two or three Pokémon on at least 4 teams together, with its lift: how much more often they're "
                + "together than chance would give."
        case .archetype:
            "Teams built around a core of four. The cores are the most common sets of four (on at least 4 teams "
                + "and 2% of them) that share at most two Pokémon with any more common core. Each team belongs to "
                + "the most common core it contains; teams with none are \"other\". An archetype has its own usage, "
                + "top-cut rate, record, and record against each other archetype."
        case .set:
            "A whole set (item, ability, nature and four moves), counted as one."
        case .windows:
            "The last 14 days, the last 30 days, or the regulation (every stored event of the format). Events have "
                + "16 players or more, as in the app's corpus."
        case .sample:
            "Every number comes with how many teams, events or matches it's from."
        }
    }

    /// Where the device's numbers differ, said under the definition.
    var deviceNote: String? {
        switch self {
        case .topEight, .teamRecord:
            "Worked out on this device, without a PK Reference server."
        default:
            nil
        }
    }

    /// The top-cut and win-rate definitions for a source: the device's stand
    /// in for them.
    static func topCut(_ source: MetaModel.Source) -> MetaDefinition { source == .server ? .topCut : .topEight }
    static func record(_ source: MetaModel.Source) -> MetaDefinition { source == .server ? .winRate : .teamRecord }
}

/// An ⓘ that opens a definition; with `titled`, the definition's name
/// beside it, where several sit together.
struct MetaInfoButton: View {
    let definition: MetaDefinition
    var titled = false
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            if titled {
                Label(definition.title, systemImage: "info.circle")
            } else {
                Image(systemName: "info.circle")
                    .imageScale(.medium)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("About \(definition.title.lowercased())")
        .sheet(isPresented: $showing) {
            MetaInfoSheet(definition: definition)
        }
    }
}

struct MetaInfoSheet: View {
    let definition: MetaDefinition
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(definition.text)
                    if let note = definition.deviceNote {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(definition.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        #if os(macOS)
        // A paragraph: smaller than `sheetSize()`'s lists need.
        .frame(minWidth: 420, idealWidth: 480, minHeight: 220, idealHeight: 260)
        #endif
    }
}
