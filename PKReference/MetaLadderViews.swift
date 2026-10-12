//
//  MetaLadderViews.swift
//  PKReference
//
//  The Meta tab's ladder: its home (most used, leads, what's rising, what
//  stronger players use more), the full list, and one Pokémon's ladder page
//  (BackendIntegration-PHASE5.md §6). They show LadderModel's record, from
//  the PK Reference server or from Smogon's own file on this device, and say
//  which; LadderDefinition's ⓘ says what each number means.
//

import Charts
import SwiftUI

/// Where the ladder's links go.
enum LadderRoute: Hashable {
    /// By Smogon's name, which is what's unique in a record.
    case pokemon(String)
    case allPokemon
}

// MARK: - Home

/// The ladder's part of the Meta tab's home, under its header.
struct MetaLadderHome: View {
    let request: LadderRequest
    let model: LadderModel
    let serverEnabled: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if let problem = model.serverProblem {
            MetaNoticeCard(icon: "exclamationmark.triangle.fill", tint: .orange,
                           text: problem.message + (model.answer.map {
                               $0.source == .server ? " Showing its last answer." : " Showing what's on this device."
                           } ?? "")) {
                Button("Try Again") { Task { await model.load(request, force: true) } }
            }
        }
        statusCard
        if let offer = model.offer, model.status != .downloading {
            LadderDownloadCard(offer: offer, request: request, showing: model.answer?.stats.month,
                               failure: failure) {
                Task { await model.download(request) }
            }
        }
        if let notice = model.notice {
            MetaNoticeCard(icon: "info.circle.fill", tint: .secondary, text: notice) {
                OpenSettingsButton(title: "Change the Regulation in Settings")
            }
        }
        if let answer = model.answer, !answer.stats.pokemon.isEmpty {
            let namer = LadderNamer(answer.stats, regulation: request.regulation)
            if answer.source == .device && !serverEnabled {
                MetaNoticeCard(icon: "server.rack", tint: .secondary, text: LadderText.serverAdds) {
                    OpenSettingsButton(title: "Open Settings")
                }
            }
            // Two columns where there's room: iPad and the Mac.
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    CardStack {
                        LadderMostUsedCard(stats: answer.stats, namer: namer)
                        LadderTrendCard(stats: answer.stats, namer: namer)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    CardStack {
                        LadderLeadsCard(stats: answer.stats, namer: namer)
                        LadderByRatingCard(stats: answer.stats, namer: namer)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                LadderMostUsedCard(stats: answer.stats, namer: namer)
                LadderLeadsCard(stats: answer.stats, namer: namer)
                LadderTrendCard(stats: answer.stats, namer: namer)
                LadderByRatingCard(stats: answer.stats, namer: namer)
            }
        }
    }

    private var failure: String? {
        if case .downloadFailed(let reason) = model.status { return reason }
        return nil
    }

    @ViewBuilder
    private var statusCard: some View {
        switch model.status {
        case .loading where model.answer == nil:
            ProgressView("Loading the ladder…")
                .frame(maxWidth: .infinity)
                .card()
        case .downloading:
            SectionCard(title: "Downloading from Smogon", icon: "arrow.down.circle") {
                ProgressView("Downloading and reading the month's stats…")
                Text("A month's file is a few megabytes. It's read once and kept on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }
}

/// The ladder's pickers, and what its numbers rest on: in the tab's header.
struct MetaLadderHeader: View {
    let mode: LadderRequest.Mode
    @Binding var rating: Int
    @Binding var bestOf: Int
    let answer: LadderStore.Answer?

    var body: some View {
        if let answer {
            VStack(alignment: .leading, spacing: 2) {
                Text(LadderText.sample(answer.stats))
                    .font(.subheadline)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(LadderText.source(answer.source, fetched: answer.stats.fetchedAt, now: context.date))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        HStack {
            Picker("Rating", selection: $rating) {
                ForEach(LadderRequest.ratings, id: \.self) { rating in
                    Text(LadderText.rating(rating))
                        .accessibilityLabel(LadderText.players(rating))
                        .tag(rating)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Rating")
            MetaInfoButton(info: LadderDefinition.ratingBand.info)
        }
        if mode == .doubles {
            Picker("Best Of", selection: $bestOf) {
                Text(LadderText.bestOf(1)).tag(1)
                Text(LadderText.bestOf(3)).tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Best of")
        }
    }
}

/// A month of Smogon's that isn't on this device, and the button that gets it.
private struct LadderDownloadCard: View {
    let offer: SmogonLadderStore.Offer
    let request: LadderRequest
    /// The month shown meanwhile, when there is one.
    let showing: String?
    let failure: String?
    let download: () -> Void

    var body: some View {
        SectionCard(title: "Smogon's Ladder Stats", icon: "arrow.down.circle") {
            Text(LadderText.download(offer, for: request, showing: showing))
                .font(.subheadline)
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(action: download) {
                Label(failure == nil ? "Download \(LadderText.month(offer.month))" : "Try Again",
                      systemImage: "arrow.down.circle")
            }
            .buttonStyle(.primaryAction)
        }
    }
}

// MARK: - Home cards

/// The most-used Pokémon, led by a sentence.
private struct LadderMostUsedCard: View {
    let stats: MetaAPI.LadderStats
    let namer: LadderNamer

    var body: some View {
        SectionCard(title: "Most Used", icon: "chart.bar.fill") {
            if let lead = LadderText.mostUsed(stats, name: namer.name) {
                Text(lead)
                    .font(.subheadline)
            }
            ForEach(stats.pokemon.prefix(8), id: \.name) { pokemon in
                NavigationLink(value: LadderRoute.pokemon(pokemon.name)) {
                    LadderPokemonRow(pokemon: pokemon, name: namer.name(pokemon.name))
                }
                .buttonStyle(.plain)
            }
            HStack {
                NavigationLink(value: LadderRoute.allPokemon) {
                    Label("All \(stats.pokemon.count) Pokémon", systemImage: "list.bullet")
                }
                Spacer()
            }
            .font(.subheadline)
            MetaInfoButton(info: LadderDefinition.usage.info, titled: true)
                .font(.caption)
        }
    }
}

/// One Pokémon's line: its usage, and its change since last month when the
/// record has one.
struct LadderPokemonRow: View {
    let pokemon: MetaAPI.LadderPokemon
    let name: String
    /// What the number on the right is; usage unless a list is sorted
    /// another way.
    var value: String?
    /// In a card; a List draws its own.
    var showsChevron = true

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(.body.weight(.semibold))
            Spacer()
            if let trend = MetaText.trend(pokemon.trend), value == nil {
                Text(trend)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(value ?? LadderText.percent(pokemon.usage))
                .font(.body.monospacedDigit())
            if showsChevron { MetaChevron() }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LadderText.spoken(pokemon, name: name))
        .accessibilityAddTraits(.isButton)
    }
}

/// The Pokémon sent out first most often.
private struct LadderLeadsCard: View {
    let stats: MetaAPI.LadderStats
    let namer: LadderNamer

    private var leads: [MetaAPI.LadderPokemon] {
        stats.pokemon.filter { $0.leadShare != nil }.sorted { $0.leadShare! > $1.leadShare! }
    }

    var body: some View {
        if !leads.isEmpty {
            SectionCard(title: "Common Leads", icon: "flag.checkered") {
                Text(stats.mode == LadderRequest.Mode.doubles.rawValue
                     ? "Each Pokémon's share of all leads. A team leads two."
                     : "Each Pokémon's share of all leads.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(leads.prefix(8), id: \.name) { pokemon in
                    NavigationLink(value: LadderRoute.pokemon(pokemon.name)) {
                        HStack {
                            Text(namer.name(pokemon.name))
                            Spacer()
                            Text(LadderText.percent(pokemon.leadShare ?? 0))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            MetaChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(namer.name(pokemon.name)): \(LadderText.percent(pokemon.leadShare ?? 0)) of all leads")
                }
                MetaInfoButton(info: LadderDefinition.leadShare.info, titled: true)
                    .font(.caption)
            }
        }
    }
}

/// The biggest rises and falls in usage since last month. Only the server
/// has last month.
private struct LadderTrendCard: View {
    let stats: MetaAPI.LadderStats
    let namer: LadderNamer

    var body: some View {
        if let previous = stats.previousMonth {
            let trending = stats.pokemon.filter { $0.trend != nil }
            let rising = trending.filter { $0.trend! > 0 }.sorted { $0.trend! > $1.trend! }.prefix(4)
            let falling = trending.filter { $0.trend! < 0 }.sorted { $0.trend! < $1.trend! }.prefix(4)
            if !rising.isEmpty || !falling.isEmpty {
                SectionCard(title: "Rising and Falling", icon: "arrow.up.right") {
                    Text("\(LadderText.month(stats.month)) against \(LadderText.month(previous)), in percentage points.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(Array(rising) + Array(falling), id: \.name) { pokemon in
                        NavigationLink(value: LadderRoute.pokemon(pokemon.name)) {
                            HStack {
                                Text(namer.name(pokemon.name))
                                Spacer()
                                Text(MetaText.trend(pokemon.trend) ?? "")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                MetaChevron()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LadderText.spoken(pokemon, name: namer.name(pokemon.name)))
                    }
                    MetaInfoButton(info: LadderDefinition.trend.info, titled: true)
                        .font(.caption)
                }
            }
        }
    }
}

/// What stronger players use more, and less: usage at the highest rating
/// against the lowest. Only the server has the other ratings.
private struct LadderByRatingCard: View {
    let stats: MetaAPI.LadderStats
    let namer: LadderNamer

    var body: some View {
        let gaps = LadderText.ratingGaps(stats)
        if !gaps.isEmpty, let lowest = stats.ratings.min(), let highest = stats.ratings.max() {
            let more = gaps.filter { $0.high > $0.low }.sorted { $0.high - $0.low > $1.high - $1.low }.prefix(4)
            let less = gaps.filter { $0.high < $0.low }.sorted { $0.high - $0.low < $1.high - $1.low }.prefix(4)
            SectionCard(title: "By Rating", icon: "arrow.up.forward.circle") {
                Text("Usage among \(LadderText.players(lowest)), then among \(LadderText.players(highest)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !more.isEmpty {
                    Text("Used more at higher ratings")
                        .font(.subheadline.weight(.semibold))
                    rows(Array(more), lowest: lowest, highest: highest)
                }
                if !less.isEmpty {
                    Text("Used less at higher ratings")
                        .font(.subheadline.weight(.semibold))
                    rows(Array(less), lowest: lowest, highest: highest)
                }
                MetaInfoButton(info: LadderDefinition.ratingBand.info, titled: true)
                    .font(.caption)
            }
        }
    }

    private func rows(_ gaps: [(pokemon: MetaAPI.LadderPokemon, low: Double, high: Double)], lowest: Int,
                      highest: Int) -> some View {
        ForEach(gaps, id: \.pokemon.name) { gap in
            NavigationLink(value: LadderRoute.pokemon(gap.pokemon.name)) {
                HStack {
                    Text(namer.name(gap.pokemon.name))
                    Spacer()
                    Text("\(LadderText.percent(gap.low)) → \(LadderText.percent(gap.high))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    MetaChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(namer.name(gap.pokemon.name)): \(LadderText.percent(gap.low)) among "
                + "\(LadderText.players(lowest)), \(LadderText.percent(gap.high)) among \(LadderText.players(highest))")
        }
    }
}

// MARK: - All Pokémon

struct LadderPokemonListView: View {
    let stats: MetaAPI.LadderStats
    let namer: LadderNamer
    @State private var search = ""
    @State private var order: Order = .usage

    enum Order: String, CaseIterable, Identifiable {
        case usage = "Usage"
        case leads = "Leads"
        case trend = "Trend"
        var id: String { rawValue }
    }

    /// Trend only when the record has last month.
    private var orders: [Order] {
        stats.previousMonth == nil ? [.usage, .leads] : Order.allCases
    }

    private var shown: [MetaAPI.LadderPokemon] {
        let found = search.isEmpty ? stats.pokemon
            : stats.pokemon.filter { namer.name($0.name).localizedStandardContains(search) }
        func value(_ pokemon: MetaAPI.LadderPokemon) -> Double {
            switch order {
            case .usage: pokemon.usage
            case .leads: pokemon.leadShare ?? -1
            case .trend: pokemon.trend ?? -1
            }
        }
        return found.sorted { value($0) != value($1) ? value($0) > value($1) : $0.usage > $1.usage }
    }

    private func value(_ pokemon: MetaAPI.LadderPokemon) -> String? {
        switch order {
        case .usage: nil
        case .leads: pokemon.leadShare.map(LadderText.percent) ?? "—"
        case .trend: MetaText.trend(pokemon.trend) ?? "—"
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Sort By", selection: $order) {
                    ForEach(orders) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } footer: {
                Text(LadderText.sample(stats) + " · " + LadderText.players(stats.rating))
            }
            Section {
                ForEach(shown, id: \.name) { pokemon in
                    NavigationLink(value: LadderRoute.pokemon(pokemon.name)) {
                        LadderPokemonRow(pokemon: pokemon, name: namer.name(pokemon.name), value: value(pokemon),
                                         showsChevron: false)
                    }
                }
            }
        }
        .navigationTitle("Ladder Pokémon")
        .searchable(text: $search, prompt: "Search Pokémon")
    }
}

// MARK: - A Pokémon's ladder page

struct LadderPokemonPage: View {
    /// Smogon's name.
    let name: String
    let answer: LadderStore.Answer
    let namer: LadderNamer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stats: MetaAPI.LadderStats { answer.stats }
    private var pokemon: MetaAPI.LadderPokemon? { stats.pokemon.first { $0.name == name } }

    var body: some View {
        ScrollView {
            CardStack {
                if let pokemon {
                    content(pokemon)
                } else {
                    ContentUnavailableView("No Numbers", systemImage: "chart.bar.xaxis",
                                           description: Text("\(namer.name(name)) isn't in \(LadderText.month(stats.month))'s stats for this ladder."))
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle(namer.name(name))
        .cardPage()
    }

    @ViewBuilder
    private func content(_ pokemon: MetaAPI.LadderPokemon) -> some View {
        Text("\(LadderText.sample(stats)) · \(LadderText.players(stats.rating))")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        LazyVGrid(columns: dynamicTypeSize.gridColumns(2), spacing: 12) {
            LadderStatTile(title: "Usage", value: LadderText.percent(pokemon.usage),
                           detail: "Of teams of \(LadderText.players(stats.rating))",
                           definition: .usage)
            LadderStatTile(title: "Lead Share", value: pokemon.leadShare.map(LadderText.percent) ?? "—",
                           detail: LadderText.leadRateSentence(pokemon, mode: stats.mode)
                               ?? "Smogon's leads table doesn't list it",
                           definition: .leadShare)
            if stats.previousMonth != nil {
                LadderStatTile(title: "Trend", value: MetaText.trend(pokemon.trend) ?? "—",
                               detail: "Since \(LadderText.month(stats.previousMonth ?? ""))",
                               definition: .trend)
            }
        }
        if pokemon.usageByRating.count > 1 {
            LadderByRatingChart(usage: pokemon.usageByRating, shownRating: stats.rating, name: namer.name(name))
        } else if answer.source == .device {
            Text("From Smogon's file for this rating alone: its change since last month, and its usage at the "
                 + "other ratings, come with a PK Reference server.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        LadderSharesCard(title: "Items", icon: "bag", shares: pokemon.items)
        LadderSharesCard(title: "Abilities", icon: "sparkles", shares: pokemon.abilities)
        LadderSharesCard(title: "Moves", icon: "bolt", shares: pokemon.moves)
        LadderSpreadsCard(natures: pokemon.natures, spreads: pokemon.spreads)
        if !pokemon.teammates.isEmpty {
            SectionCard(title: "Teammates", icon: "person.3") {
                ForEach(pokemon.teammates.prefix(10), id: \.value) { mate in
                    // A teammate too rare for the record has no page.
                    if stats.pokemon.contains(where: { $0.name == mate.value }) {
                        NavigationLink(value: LadderRoute.pokemon(mate.value)) {
                            MetaShareBar(label: namer.name(mate.value), share: mate.share)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        MetaShareBar(label: namer.name(mate.value), share: mate.share)
                    }
                }
            }
        }
    }
}

/// One number, what it's of, and its definition.
private struct LadderStatTile: View {
    let title: String
    let value: String
    let detail: String
    let definition: LadderDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                MetaInfoButton(info: definition.info)
            }
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
    }
}

/// Usage at each rating band, as bars: does it climb with rating?
private struct LadderByRatingChart: View {
    let usage: [MetaAPI.RatingUsage]
    let shownRating: Int
    let name: String

    private var bars: [MetaAPI.RatingUsage] { usage.sorted { $0.rating < $1.rating } }

    var body: some View {
        SectionCard(title: "Usage by Rating", icon: "chart.bar.xaxis") {
            Chart(bars, id: \.rating) { bar in
                BarMark(x: .value("Rating", LadderText.rating(bar.rating)), y: .value("Usage", bar.usage))
                    // The band the page is for stands out by more than its color.
                    .opacity(bar.rating == shownRating ? 1 : 0.45)
                    .annotation(position: .top) {
                        Text(LadderText.percent(bar.usage))
                            .font(.caption2.monospacedDigit())
                            .fontWeight(bar.rating == shownRating ? .bold : .regular)
                    }
                    .accessibilityLabel(LadderText.players(bar.rating))
                    .accessibilityValue(LadderText.percent(bar.usage))
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { if let v = value.as(Double.self) { Text(MetaText.percent(v)) } }
                }
            }
            .frame(height: 170)
            .accessibilityChartDescriptor(LadderByRatingDescriptor(name: name, bars: bars))
            HStack {
                Text("Among all players, then players at or above each rating.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                MetaInfoButton(info: LadderDefinition.ratingBand.info)
            }
        }
    }
}

/// The by-rating chart for VoiceOver's audio graph.
private struct LadderByRatingDescriptor: AXChartDescriptorRepresentable {
    let name: String
    let bars: [MetaAPI.RatingUsage]

    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXCategoricalDataAxisDescriptor(title: "Rating", categoryOrder: bars.map { LadderText.players($0.rating) })
        let y = AXNumericDataAxisDescriptor(title: "Usage", range: 0...1, gridlinePositions: []) {
            LadderText.percent($0)
        }
        let series = AXDataSeriesDescriptor(name: "Usage", isContinuous: false, dataPoints: bars.map {
            AXDataPoint(x: LadderText.players($0.rating), y: $0.usage)
        })
        return AXChartDescriptor(title: "\(name)'s usage by rating", summary: nil, xAxis: x, yAxis: y,
                                 additionalAxes: [], series: [series])
    }
}

/// Values and their shares, as labelled bars: the top eight, the rest a tap
/// away.
private struct LadderSharesCard: View {
    let title: String
    let icon: String
    let shares: [MetaAPI.LadderShare]
    @State private var showingAll = false

    var body: some View {
        if !shares.isEmpty {
            SectionCard(title: title, icon: icon) {
                ForEach(showingAll ? shares : Array(shares.prefix(8)), id: \.value) { share in
                    MetaShareBar(label: share.value, share: share.share)
                }
                if shares.count > 8 {
                    Button(showingAll ? "Show Fewer" : "Show All \(shares.count)") { showingAll.toggle() }
                        .font(.subheadline)
                }
            }
        }
    }
}

/// Natures, added up across every spread, then the commonest spreads with
/// how much of the Pokémon's teams they cover between them.
private struct LadderSpreadsCard: View {
    let natures: [MetaAPI.LadderShare]
    let spreads: [MetaAPI.LadderShare]

    var body: some View {
        if !natures.isEmpty || !spreads.isEmpty {
            SectionCard(title: "Natures and Spreads", icon: "slider.horizontal.3") {
                ForEach(natures, id: \.value) { nature in
                    MetaShareBar(label: nature.value, share: nature.share)
                }
                if !spreads.isEmpty {
                    HStack {
                        Text("Commonest Spreads")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        MetaInfoButton(info: LadderDefinition.spread.info)
                    }
                    ForEach(spreads, id: \.value) { spread in
                        HStack(alignment: .firstTextBaseline) {
                            Text(LadderText.spread(spread.value))
                            Spacer()
                            Text(LadderText.percent(spread.share))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                    if let cover = LadderText.spreadsCover(spreads) {
                        Text(cover)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
