//
//  MetaPokemonViews.swift
//  PKReference
//
//  The Meta tab's Pokémon: What's winning and Rising on its home, the full
//  list, and one Pokémon's page (BackendIntegration-PHASE4.md §3.1–3.2).
//  They show whichever source the home has (MetaModel.Snapshot): the
//  server's numbers or the device's, labelled by MetaDefinition.
//

import Charts
import SwiftData
import SwiftUI

/// A link row's chevron, as a list's.
struct MetaChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

/// Where the Meta tab's links go.
enum MetaRoute: Hashable {
    case pokemon(String)
    case allPokemon
    case archetype(String)
}

/// Names the server's species keys: "arcanine:hisui" → "Arcanine (Hisui)".
struct MetaNamer {
    let vocabulary: TeamSearchVocabulary?

    init(_ regulation: ChampionsRegulation) {
        vocabulary = try? TeamSearchVocabulary.bundled(for: regulation)
    }

    func name(_ key: String) -> String {
        vocabulary?.species(forKey: key)?.displayName ?? key
    }
}

// MARK: - Home cards

/// The most-used Pokémon, led by a sentence.
struct MetaWhatsWinningCard: View {
    let snapshot: MetaModel.Snapshot
    let namer: MetaNamer

    var body: some View {
        SectionCard(title: "What's Winning", icon: "chart.bar.fill") {
            let pokemon = snapshot.list.pokemon
            if let lead = MetaText.whatsWinning(pokemon, source: snapshot.source, name: namer.name) {
                Text(lead)
                    .font(.subheadline)
            }
            ForEach(pokemon.prefix(5), id: \.key) { p in
                NavigationLink(value: MetaRoute.pokemon(p.key)) {
                    MetaPokemonRow(pokemon: p, name: namer.name(p.key), source: snapshot.source)
                }
                .buttonStyle(.plain)
            }
            HStack {
                NavigationLink(value: MetaRoute.allPokemon) {
                    Label("All \(pokemon.count) Pokémon", systemImage: "list.bullet")
                }
                Spacer()
            }
            .font(.subheadline)
            FlowLayout(spacing: 14) {
                MetaInfoButton(definition: .usage, titled: true)
                MetaInfoButton(definition: MetaDefinition.topCut(snapshot.source), titled: true)
                MetaInfoButton(definition: MetaDefinition.record(snapshot.source), titled: true)
            }
            .font(.caption)
        }
    }
}

/// The biggest rises and falls in usage over the last fortnight.
struct MetaRisingCard: View {
    let snapshot: MetaModel.Snapshot
    let namer: MetaNamer

    var body: some View {
        SectionCard(title: "Rising and Falling", icon: "arrow.up.right") {
            let trending = snapshot.list.pokemon.filter { $0.trend != nil }
            let rising = trending.filter { $0.trend! > 0 }.sorted { $0.trend! > $1.trend! }.prefix(3)
            let falling = trending.filter { $0.trend! < 0 }.sorted { $0.trend! < $1.trend! }.prefix(3)
            Text("The last 14 days against the 14 before, whatever the window.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if trending.isEmpty {
                Text("Trends need 50 teams in each of the last two fortnights.")
                    .font(.subheadline)
            } else {
                ForEach(Array(rising) + Array(falling), id: \.key) { p in
                    NavigationLink(value: MetaRoute.pokemon(p.key)) {
                        HStack {
                            Text(namer.name(p.key))
                            Spacer()
                            Text(MetaText.trend(p.trend) ?? "")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            MetaChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MetaText.spoken(p, name: namer.name(p.key), source: snapshot.source))
                }
            }
            MetaInfoButton(definition: .trend, titled: true)
                .font(.caption)
        }
    }
}

/// One Pokémon's line: usage, top cut or top 8, record and trend.
struct MetaPokemonRow: View {
    let pokemon: MetaAPI.PokemonUsage
    let name: String
    let source: MetaModel.Source
    /// In a card; a List draws its own.
    var showsChevron = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(MetaText.percent(pokemon.usage))
                    .font(.body.monospacedDigit())
                if showsChevron { MetaChevron() }
            }
            FlowLayout(spacing: 10) {
                if let top = pokemon.topCutUsage {
                    Text("\(MetaText.topCutLabel(source)) \(MetaText.percent(top))")
                }
                if let rate = pokemon.record?.winRate {
                    Text("\(source == .server ? "wins" : "record") \(MetaText.percent(rate))")
                }
                if let trend = MetaText.trend(pokemon.trend) {
                    Text(trend)
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MetaText.spoken(pokemon, name: name, source: source))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - All Pokémon

struct MetaPokemonListView: View {
    let snapshot: MetaModel.Snapshot
    let namer: MetaNamer
    @State private var search = ""
    @State private var order: Order = .usage

    enum Order: String, CaseIterable, Identifiable {
        case usage = "Usage"
        case topCut = "Top Cut"
        case record = "Record"
        case trend = "Trend"
        var id: String { rawValue }
    }

    private var shown: [MetaAPI.PokemonUsage] {
        let found = search.isEmpty ? snapshot.list.pokemon
            : snapshot.list.pokemon.filter { namer.name($0.key).localizedStandardContains(search) }
        func value(_ p: MetaAPI.PokemonUsage) -> Double {
            switch order {
            case .usage: p.usage
            case .topCut: p.topCutUsage ?? -1
            case .record: p.record?.winRate ?? -1
            case .trend: p.trend ?? -1
            }
        }
        return found.sorted { value($0) != value($1) ? value($0) > value($1) : $0.usage > $1.usage }
    }

    var body: some View {
        List {
            Section {
                Picker("Sort By", selection: $order) {
                    ForEach(Order.allCases) { order in
                        Text(order == .topCut ? (snapshot.source == .server ? "Top Cut" : "Top 8")
                             : order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } footer: {
                Text(MetaText.sample(snapshot.list.sample, source: snapshot.source)
                     + " · " + MetaText.windowPhrase(snapshot.window))
            }
            Section {
                ForEach(shown, id: \.key) { p in
                    NavigationLink(value: MetaRoute.pokemon(p.key)) {
                        MetaPokemonRow(pokemon: p, name: namer.name(p.key), source: snapshot.source,
                                       showsChevron: false)
                    }
                }
            }
        }
        .navigationTitle("Pokémon")
        .searchable(text: $search, prompt: "Search Pokémon")
    }
}

// MARK: - A Pokémon's page

struct MetaPokemonPage: View {
    let key: String
    let snapshot: MetaModel.Snapshot
    let namer: MetaNamer
    @State private var page: MetaModel.Page?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            CardStack {
                if let page {
                    MetaPageContent(key: key, page: page, snapshot: snapshot, namer: namer)
                } else if loaded {
                    ContentUnavailableView("No Numbers", systemImage: "chart.bar.xaxis",
                                           description: Text("No team in \(MetaText.windowPhrase(snapshot.window)) has \(namer.name(key)), or the server couldn't answer."))
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
        .navigationTitle(namer.name(key))
        .cardPage()
        .task(id: key) {
            page = await MetaModel.page(key, in: snapshot)
            loaded = true
        }
    }
}

private struct MetaPageContent: View {
    let key: String
    let page: MetaModel.Page
    let snapshot: MetaModel.Snapshot
    let namer: MetaNamer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usage: MetaAPI.PokemonUsage? { page.detail.usage }

    var body: some View {
        if let usage {
            LazyVGrid(columns: dynamicTypeSize.gridColumns(2), spacing: 12) {
                MetaStatTile(title: "Usage", value: MetaText.percent(usage.usage),
                             detail: "\(usage.teams.formatted()) of \(page.detail.sample.teams.formatted()) teams",
                             definition: .usage)
                MetaStatTile(title: page.source == .server ? "Top-Cut Rate" : "Top-8 Rate",
                             value: usage.topCutUsage.map(MetaText.percent) ?? "—",
                             detail: "\(usage.topCutTeams.formatted()) of \(page.detail.sample.topCutTeams.formatted()) teams",
                             definition: MetaDefinition.topCut(page.source))
                MetaStatTile(title: page.source == .server ? "Win Rate" : "Team Record",
                             value: usage.record?.winRate.map(MetaText.percent) ?? "—",
                             detail: MetaText.record(usage.record, source: page.source) ?? "No matches",
                             definition: MetaDefinition.record(page.source))
                MetaStatTile(title: "Trend", value: MetaText.trend(usage.trend) ?? "—",
                             detail: usage.trend == nil ? "Too few teams for a trend" : "Last 14 days against the 14 before",
                             definition: .trend)
            }
        }
        if page.detail.weekly.count > 1 {
            MetaWeeklyChart(weekly: page.detail.weekly, name: namer.name(key))
        }
        MetaSetsCard(key: key, sets: page.detail.sets, namer: namer, regulation: snapshot.regulation)
        MetaSharesCard(title: "Items", icon: "bag", shares: page.detail.items)
        MetaSharesCard(title: "Abilities", icon: "sparkles", shares: page.detail.abilities)
        MetaSharesCard(title: "Moves", icon: "bolt", shares: page.detail.moves)
        MetaSharesCard(title: "Natures", icon: "leaf", shares: page.detail.natures)
        if !page.detail.megaStones.isEmpty {
            MetaSharesCard(title: "Mega Stones", icon: "circle.hexagongrid", shares: page.detail.megaStones)
        }
        MetaTeammatesCard(teammates: page.detail.teammates, pairs: page.pairs, trios: page.trios, key: key,
                          namer: namer)
        MetaLinksCard(key: key, namer: namer)
    }
}

/// One number, what it's out of, and its definition.
private struct MetaStatTile: View {
    let title: String
    let value: String
    let detail: String
    let definition: MetaDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                MetaInfoButton(definition: definition)
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

/// Usage week by week, as a line.
private struct MetaWeeklyChart: View {
    let weekly: [MetaAPI.WeekUsage]
    let name: String

    private static let weekFormat = Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC")!).year().month().day()

    private var points: [(date: Date, usage: Double, teams: Int)] {
        weekly.compactMap { week in
            (try? Date(week.week, strategy: Self.weekFormat)).map { ($0, week.usage, week.teams) }
        }
    }

    var body: some View {
        SectionCard(title: "Usage by Week", icon: "chart.xyaxis.line") {
            Chart(points, id: \.date) { point in
                LineMark(x: .value("Week", point.date, unit: .weekOfYear), y: .value("Usage", point.usage))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Week", point.date, unit: .weekOfYear), y: .value("Usage", point.usage))
                    .accessibilityLabel("Week of \(point.date.formatted(.dateTime.month().day()))")
                    .accessibilityValue("\(MetaText.percent(point.usage)) of \(point.teams) teams")
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { if let v = value.as(Double.self) { Text(MetaText.percent(v)) } }
                }
            }
            .frame(height: 160)
            .accessibilityChartDescriptor(MetaWeeklyDescriptor(name: name, points: points))
        }
    }
}

/// The weekly chart for VoiceOver's audio graph.
private struct MetaWeeklyDescriptor: AXChartDescriptorRepresentable {
    let name: String
    let points: [(date: Date, usage: Double, teams: Int)]

    func makeChartDescriptor() -> AXChartDescriptor {
        let x = AXCategoricalDataAxisDescriptor(
            title: "Week", categoryOrder: points.map { $0.date.formatted(.dateTime.month().day()) })
        let y = AXNumericDataAxisDescriptor(title: "Usage", range: 0...1, gridlinePositions: []) {
            MetaText.percent($0)
        }
        let series = AXDataSeriesDescriptor(name: "Usage", isContinuous: true, dataPoints: points.map {
            AXDataPoint(x: $0.date.formatted(.dateTime.month().day()), y: $0.usage)
        })
        return AXChartDescriptor(title: "\(name)'s usage by week", summary: nil, xAxis: x, yAxis: y,
                                 additionalAxes: [], series: [series])
    }
}

/// Values and their shares, as labelled bars: the top eight, the rest a tap
/// away.
private struct MetaSharesCard: View {
    let title: String
    let icon: String
    let shares: [MetaAPI.Share]
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

/// A label, its percentage as text, and a bar under it.
struct MetaShareBar: View {
    let label: String
    let share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                Spacer()
                Text(MetaText.percent(share))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.fill.tertiary)
                    Capsule().fill(.tint).frame(width: max(4, geometry.size.width * min(1, share)))
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The most common whole sets, each with Save Set and Calc Against This.
private struct MetaSetsCard: View {
    let key: String
    let sets: [MetaAPI.PokemonSet]
    let namer: MetaNamer
    let regulation: ChampionsRegulation

    var body: some View {
        if !sets.isEmpty {
            SectionCard(title: "Top Sets", icon: "square.stack.3d.up") {
                HStack {
                    Text(MetaText.predictedStats)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    MetaInfoButton(definition: .set)
                }
                ForEach(Array(sets.prefix(5).enumerated()), id: \.offset) { _, set in
                    MetaSetRow(request: MetaSetRequest(key: key, name: namer.name(key), set: set), set: set)
                    Divider()
                }
            }
        }
    }
}

/// One whole set: its item, ability, nature and moves, how common it is,
/// and Save Set and Calc Against This.
struct MetaSetRow: View {
    let request: MetaSetRequest
    let set: MetaAPI.PokemonSet
    @Query(sort: \PKMNStats.name) private var allStats: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]
    @Environment(\.modelContext) private var modelContext
    @State private var saved = false
    @State private var unmatched: [String] = []
    @State private var showingUnmatched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text([set.item, set.ability, set.nature].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(MetaText.percent(set.share)) · \(set.count.formatted())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(set.moves.joined(separator: ", "))
                .font(.subheadline)
            HStack {
                Button(saved ? "Saved" : "Save Set", systemImage: saved ? "checkmark" : "square.and.arrow.down") {
                    save()
                }
                Button("Calc Against This", systemImage: "bolt.fill") {
                    AppNavigator.shared.request = .calcDefender(request)
                }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .alert("Couldn't Save", isPresented: $showingUnmatched) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(unmatched.joined(separator: "\n"))
        }
    }

    private func save() {
        let spreads = (try? modelContext.fetch(FetchDescriptor<SavedSpread>())) ?? []
        let teams = (try? modelContext.fetch(FetchDescriptor<SavedTeam>())) ?? []
        switch LimitlessTeamImporter(allPokemon: allStats, allMoves: allMoves)
            .planSpread(request.member, taken: TeamPasteImport.takenNames(spreads: spreads, teams: teams),
                        predictStats: true) {
        case .success(let spread):
            modelContext.insert(spread)
            withAnimation { saved = true }
        case .failure(let failure):
            unmatched = failure.lines
            showingUnmatched = true
        }
    }
}

/// Its most common teammates, and the cores it's in.
private struct MetaTeammatesCard: View {
    let teammates: [MetaAPI.Share]
    let pairs: [MetaAPI.Core]
    let trios: [MetaAPI.Core]
    let key: String
    let namer: MetaNamer

    var body: some View {
        if !teammates.isEmpty {
            SectionCard(title: "Teammates", icon: "person.3") {
                ForEach(teammates.prefix(8), id: \.value) { mate in
                    NavigationLink(value: MetaRoute.pokemon(mate.value)) {
                        MetaShareBar(label: namer.name(mate.value), share: mate.share)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                let cores = (trios + pairs).sorted { $0.teams > $1.teams }.prefix(5)
                if !cores.isEmpty {
                    HStack {
                        Text("Cores")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        MetaInfoButton(definition: .core)
                    }
                    ForEach(Array(cores), id: \.members) { core in
                        HStack {
                            Text(core.members.map(namer.name).joined(separator: " + "))
                            Spacer()
                            Text("\(MetaText.percent(core.share)) · \(String(format: "%.1f", core.lift))×")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(core.members.map(namer.name).joined(separator: ", ")): on "
                            + "\(MetaText.percent(core.share)) of teams, \(String(format: "%.1f", core.lift)) "
                            + "times as often as chance would give")
                    }
                }
            }
        }
    }
}

/// The Pokémon elsewhere in the app.
private struct MetaLinksCard: View {
    let key: String
    let namer: MetaNamer
    @Query(sort: \PKMNStats.name) private var allStats: [PKMNStats]
    @State private var speciesID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let speciesID {
                Button("Open in Mon Index", systemImage: "list.bullet") {
                    AppNavigator.shared.request = .pokemon(speciesID: speciesID)
                }
            }
            Button("Search Teams with \(namer.name(key))", systemImage: "sparkle.magnifyingglass") {
                AppNavigator.shared.request = .teamSearch(query: namer.name(key))
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        // The National Dex number, through the importer that resolves
        // Limitless's names. Once: it indexes the whole Pokédex.
        .task(id: key) {
            let member = MetaSetRequest(key: key, name: namer.name(key), set: nil).member
            speciesID = LimitlessTeamImporter(allPokemon: allStats, allMoves: []).pokemon(for: member)?.speciesID
        }
    }
}
