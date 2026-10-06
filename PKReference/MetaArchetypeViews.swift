//
//  MetaArchetypeViews.swift
//  PKReference
//
//  The Meta tab's archetypes: Teams to beat on its home, and one
//  archetype's page with its matchups and best-placed teams
//  (BackendIntegration-PHASE4.md §3.3).
//

import SwiftUI

/// The archetypes with the most teams in a top cut (or the top 8).
struct MetaTeamsToBeatCard: View {
    let snapshot: MetaModel.Snapshot
    let namer: MetaNamer

    /// The five with the most top-cut teams, then the most teams.
    static func teams(_ snapshot: MetaModel.Snapshot) -> [MetaAPI.Archetype]? {
        snapshot.archetypes.map { all in
            Array(all.archetypes.sorted {
                $0.topCutTeams != $1.topCutTeams ? $0.topCutTeams > $1.topCutTeams : $0.teams > $1.teams
            }.prefix(5))
        }
    }

    var body: some View {
        if let teams = Self.teams(snapshot) {
            SectionCard(title: "Teams to Beat", icon: "shield.lefthalf.filled") {
                if teams.isEmpty {
                    Text("No archetype has enough teams yet: each needs 4 teams and 2% of them.")
                        .font(.subheadline)
                } else {
                    ForEach(teams, id: \.id) { archetype in
                        NavigationLink(value: MetaRoute.archetype(archetype.id)) {
                            MetaArchetypeRow(archetype: archetype, namer: namer, source: snapshot.source)
                        }
                        .buttonStyle(.plain)
                    }
                }
                MetaInfoButton(definition: .archetype, titled: true)
                    .font(.caption)
            }
        }
    }
}

private struct MetaArchetypeRow: View {
    let archetype: MetaAPI.Archetype
    let namer: MetaNamer
    let source: MetaModel.Source

    private var summary: String {
        var parts = ["\(MetaText.percent(archetype.usage)) of teams"]
        if let top = archetype.topCutUsage {
            parts.append("\(MetaText.percent(top)) of \(source == .server ? "top-cut" : "top-8") teams")
        }
        if let rate = archetype.record?.winRate {
            parts.append("\(source == .server ? "wins" : "record") \(MetaText.percent(rate))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(MetaText.archetypeName(archetype, name: namer.name))
                    .font(.body.weight(.semibold))
                Text(archetype.core.map(namer.name).joined(separator: ", "))
                    .font(.subheadline)
                Text(summary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MetaChevron()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - An archetype's page

struct MetaArchetypePage: View {
    let id: String
    let snapshot: MetaModel.Snapshot
    let namer: MetaNamer
    @State private var detail: MetaAPI.ArchetypeDetail?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            CardStack {
                if let detail {
                    MetaArchetypeContent(detail: detail, snapshot: snapshot, namer: namer)
                } else if loaded {
                    ContentUnavailableView("No Archetype", systemImage: "shield.lefthalf.filled",
                                           description: Text("No archetype in \(MetaText.windowPhrase(snapshot.window)) has this core, or the server couldn't answer."))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .card()
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle(detail.map { MetaText.archetypeName($0.archetype, name: namer.name) } ?? "Archetype")
        .cardPage()
        .task(id: id) {
            detail = await MetaModel.archetype(id, in: snapshot)
            loaded = true
        }
    }
}

private struct MetaArchetypeContent: View {
    let detail: MetaAPI.ArchetypeDetail
    let snapshot: MetaModel.Snapshot
    let namer: MetaNamer

    private var archetype: MetaAPI.Archetype { detail.archetype }
    private var source: MetaModel.Source { snapshot.source }

    /// Its matchups with a rate (30 matches or more), best first.
    private var rated: [MetaAPI.Matchup] {
        archetype.matchups.filter { $0.record.winRate != nil }.sorted { $0.record.winRate! > $1.record.winRate! }
    }

    /// Other archetypes by id, to name them.
    private var others: [String: MetaAPI.Archetype] {
        Dictionary(uniqueKeysWithValues: (snapshot.archetypes?.archetypes ?? []).map { ($0.id, $0) })
    }

    var body: some View {
        SectionCard(title: "Core", icon: "person.3") {
            ForEach(archetype.core, id: \.self) { key in
                NavigationLink(value: MetaRoute.pokemon(key)) {
                    HStack {
                        Text(namer.name(key))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        MetaChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("\(MetaText.count(archetype.teams, "team")) · \(MetaText.percent(archetype.usage)) of \(MetaText.count(detail.sample.teams, "team")) in \(MetaText.windowPhrase(snapshot.window))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 14) {
                MetaInfoButton(definition: .archetype, titled: true)
                MetaInfoButton(definition: MetaDefinition.topCut(source), titled: true)
                MetaInfoButton(definition: MetaDefinition.record(source), titled: true)
            }
            .font(.caption)
        }
        SectionCard(title: "How It Does", icon: "chart.bar") {
            if let top = archetype.topCutUsage {
                MetaShareBar(label: "Usage", share: archetype.usage)
                MetaShareBar(label: source == .server ? "Top-cut teams" : "Top-8 teams", share: top)
            }
            if let record = MetaText.record(archetype.record, source: source) {
                Text(record)
                    .font(.subheadline)
            }
        }
        matchupsCard
        examplesCard
        Button("Search These Teams", systemImage: "sparkle.magnifyingglass") {
            AppNavigator.shared.request = .teamSearch(query: archetype.core.map(namer.name).joined(separator: " "))
        }
        .buttonStyle(.primaryAction)
    }

    @ViewBuilder
    private var matchupsCard: some View {
        SectionCard(title: "Against Other Archetypes", icon: "arrow.left.arrow.right") {
            if source == .device {
                Text("Matchups need who played whom, which only a PK Reference server has.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if rated.isEmpty {
                Text("No matchup has 30 matches yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rated, id: \.against) { matchup in
                    let name = others[matchup.against].map { MetaText.archetypeName($0, name: namer.name) }
                        ?? matchup.against.split(separator: "+").map { namer.name(String($0)) }.joined(separator: " + ")
                    NavigationLink(value: MetaRoute.archetype(matchup.against)) {
                        HStack {
                            Text(name)
                            Spacer()
                            Text("\(MetaText.percent(matchup.record.winRate!)) · \(matchup.record.wins)–\(matchup.record.losses)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            MetaChevron()
                        }
                        .font(.subheadline)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Against \(name): wins \(MetaText.percent(matchup.record.winRate!)) of \(MetaText.count(matchup.record.matches, "match", plural: "matches"))")
                }
            }
        }
    }

    @ViewBuilder
    private var examplesCard: some View {
        if !detail.examples.isEmpty {
            SectionCard(title: "Best-Placed Teams", icon: "trophy") {
                ForEach(Array(detail.examples.enumerated()), id: \.offset) { _, team in
                    NavigationLink {
                        StandingDetailView(standing: team.standing)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(team.player ?? "Unnamed player") · \(MetaText.placing(team.placing, of: team.players))")
                                .font(.subheadline.weight(.semibold))
                            Text(team.eventName ?? team.eventId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(team.members.map { $0.key.map(namer.name) ?? $0.name }.joined(separator: ", "))
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .trailing) { MetaChevron() }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    Divider()
                }
            }
        }
    }
}
