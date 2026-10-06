//
//  MetaInTheMetaCard.swift
//  PKReference
//
//  Mon Index's "In the meta" card (BackendIntegration-PHASE4.md §3.5): a
//  Champions Pokémon's usage in Settings' regulation, its trend, and its
//  most common set, from the same numbers the Meta tab shows. It reads what
//  the Meta tab would (the server's cached answers, or Team Search's
//  downloaded teams) and never downloads anything or asks Limitless itself.
//  With nothing to show, it isn't there: the Mon Index is a reference first.
//
//  The page loads it (`MetaInTheMeta.load`, from a task on its scroll view)
//  and the card only shows it: a view with nothing in it never runs its own
//  tasks.
//

import SwiftUI

@MainActor
@Observable
final class MetaInTheMeta {
    private(set) var snapshot: MetaModel.Snapshot?
    private(set) var page: MetaModel.Page?
    private let model: MetaModel

    init(model: MetaModel? = nil) {
        self.model = model ?? MetaModel()
    }

    /// The server's species key for the Pokémon shown: its species' name
    /// ("Arcanine") and the alternate form shown, if any ("Hisuian Form").
    /// A Mega counts under its species, as the server counts it.
    nonisolated static func key(species: String, alternateForm: String?, vocabulary: TeamSearchVocabulary) -> String {
        vocabulary.identity(name: [species, alternateForm].compactMap { $0 }.joined(separator: " "), slug: nil).key
    }

    /// What anything that changes the card is read from, for the page's
    /// task to reload on.
    static func loadKey(species: String, alternateForm: String?, defaults: UserDefaults = .standard) -> String {
        [species, alternateForm ?? "", ChampionsRegulation.current.rawValue,
         defaults.string(forKey: AppSettings.metaWindow.name) ?? "",
         String(defaults.bool(forKey: MetaServerSettings.enabledKey)),
         defaults.string(forKey: MetaServerSettings.addressKey) ?? ""].joined(separator: "|")
    }

    func load(species: String, alternateForm: String?) async {
        page = nil
        let regulation = ChampionsRegulation.current
        let window = UserDefaults.standard.string(forKey: AppSettings.metaWindow.name)
            .flatMap(MetaAPI.Window.init(rawValue:)) ?? AppSettings.metaWindow.defaultValue
        await model.load(regulation, window: window, limitless: false)
        snapshot = model.snapshot
        guard let snapshot, let vocabulary = try? TeamSearchVocabulary.bundled(for: regulation) else { return }
        let key = Self.key(species: species, alternateForm: alternateForm, vocabulary: vocabulary)
        guard snapshot.list.pokemon.contains(where: { $0.key == key }) else { return }
        page = await MetaModel.page(key, in: snapshot)
    }
}

struct MetaInTheMetaCard: View {
    let state: MetaInTheMeta

    var body: some View {
        if let snapshot = state.snapshot, let page = state.page, let usage = page.detail.usage {
            let namer = MetaNamer(snapshot.regulation)
            SectionCard(title: "In the Meta", icon: "chart.bar.xaxis") {
                Text(MetaText.inTheMeta(usage, regulation: snapshot.regulation, window: snapshot.window,
                                        source: snapshot.source))
                    .font(.subheadline)
                Text(MetaText.source(snapshot.source, updated: snapshot.updated, now: .now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let set = page.detail.sets.first {
                    Divider()
                    Text("Most common set")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    MetaSetRow(request: MetaSetRequest(key: page.detail.key, name: namer.name(page.detail.key),
                                                       set: set), set: set)
                }
                NavigationLink {
                    MetaPokemonPage(key: page.detail.key, snapshot: snapshot, namer: namer)
                } label: {
                    Label("More in Meta", systemImage: "chart.bar.xaxis")
                }
                .font(.subheadline)
            }
        }
    }
}
