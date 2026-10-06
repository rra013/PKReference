# Backend integration, Phase 4: the Meta tab (first version)

The detailed plan for Phase 4 of [`BackendIntegration-PLAN.md`](BackendIntegration-PLAN.md).
The plan has the goals, the metrics' definitions (§4.2) and the owner's
decisions (§9); this file says what Phase 4 builds, how, and in which PRs.
Written 2026-10-06, against `backend-integration` at 93db120.

## 1. What ships

- **The Meta tab replaces the Tournaments tab.** The Tournaments list lives
  on inside it as Events, so nothing the tab does today is lost.
- **Meta home:** Settings' regulation, freshness and sample sizes, What's
  winning, Rising, Teams to beat and Recent events.
- **The Pokémon page** and **the archetype page**, with an info sheet (ⓘ)
  for each metric.
- **Mon Index's "In the meta" card.**
- **The app's `/v1` client**, with a disk cache and a rule for when to ask
  the server again, and the fix for the stale connection test.
- **A version worked out on the device**, from Team Search's Limitless
  teams, for when the server is off or can't be reached (§6).
- **Doubles only**, from Limitless. Singles comes with Phase 5 (§7).

Reading `/v1` needs Settings → PK Reference Server (Beta), which stays
**off by default** (§9 of the plan). With it off, or the server unreachable,
the tab works out what it can on the device and browses events from
Limitless, as Tournaments does today (§6).

Out of Phase 4: the ladder, singles, the planning flows, Damage Calc's
"Common sets", Speed Tiers' "Meta only" and a Pokémon's matchups against
archetypes (phases 5 and 6).

## 2. The tab

### 2.1 Replacing `AppTab.tournaments`

- `AppTab.tournaments` (`ContentView.swift`) becomes `AppTab.meta`, raw
  value `"meta"`, labelled "Meta", with the icon `chart.bar.xaxis`. It keeps
  its place in `allUserTabs`, between RNG Tools and Team Search.
  `tabContent(for:)` shows `MetaTab()`.
- **Saved settings that name the old tab move to the new one.** Three are
  stored as raw values: `AppSettings.defaultTab`, `AppSettings.tabOrder` and
  `AppSettings.hiddenTabs` (`TabLayout`'s `tabOrder` and `hiddenTabs`).
  Without a migration, `TabLayout.parse` drops the unknown `"tournaments"`,
  `TabLayout.init` adds Meta at the end of the order as a new tab, a hidden
  Tournaments tab comes back as a visible Meta tab, and `launchTab(for:)`
  opens a user whose default was Tournaments on their first visible tab.
- **The migration:** `TabLayout.migrateRenamedTabs(in:)`, run in
  `PKReferenceApp.init` beside `migrateLegacyStorage()` and after it, so it
  also catches an `enabledTabs` list the legacy migration just converted.
  It replaces `tournaments` with `meta` in the three stored strings, keeping
  the order and the hidden state (someone who hid Tournaments doesn't get
  Meta in their tab bar), and does nothing once nothing names the old tab.
  A table `[old: new]` holds the one rename, for any later one.
- The setting keys don't change, so `AppSettingsTests`' pinned names stay.
- **Debug launch arguments** that name the tab change from
  `-defaultTab tournaments` to `-defaultTab meta`; HANDOFF's Known
  limitations, which lists Tournaments among tabs with a search field,
  changes with it.

### 2.2 Events, inside Meta

- `TournamentsTab` (`TournamentsView.swift`) splits in two: its list becomes
  `EventsView`, a pushable screen with no navigation stack of its own, and
  the tab's `TabNavigationStack` moves to `MetaTab`. `TournamentsViewModel`,
  the filter sheet, `TournamentDetailView` and `StandingDetailView` don't
  change. The file is renamed `EventsView.swift` and its titles say
  "Events".
- Meta home's Recent events card ends with **See all ›**, which pushes
  `EventsView`. It opens on Settings' regulation; its filter sheet still offers
  every Limitless game and format.
- Events always browses Limitless live, as Tournaments does, with the switch
  on or off: the server keeps only the formats it's set to and events of 16
  players or more, and Events has always shown every event.
- The search field moves with the list, onto `EventsView`. Meta home has no
  search field, so the large-title glitch for search tabs under More
  (HANDOFF, Known limitations) no longer applies to this tab.

### 2.3 The regulation

**Every screen uses Settings' regulation** (decided 2026-10-06):
`ChampionsRegulation.current`, stored as `AppSettings.championsRegulation`,
which already sets the calc, legality, the Problem Solver, the Mon Index's
roster and Team Search's starting regulation.

- **No new setting and no picker of Meta's own.** Meta home's header names
  the regulation ("M-C") with **Change in Settings**, which opens Settings
  (its window on the Mac). Changing it there reloads Meta, its pages and Mon
  Index's card.
- **Team Search's own picker doesn't change** in Phase 4: it still starts on
  Settings' regulation each launch.
- **A warning when it filters everything out.** When the source has nothing
  for the regulation, Meta says so rather than showing empty cards:
  - the server's `/v1/formats` doesn't list it: "The server has no M-B
    events. It has M-C (36 events). Change the regulation in Settings, or
    add M-B to the server's `LIMITLESS_FORMATS`."
  - the window has no teams: "No M-C events in the last 14 days." with the
    longer windows' counts;
  - on the device, Team Search has no teams for it (§6).

  Formats the server has that the app doesn't know (the owner's server has
  "CUSTOM") are never offered.

## 3. Screens

Every screen is laid out with `cardPage()`, `CardStack` and `SectionCard`
(`Theme.swift`), leads each card with a sentence, and shows its sample.

### 3.1 Meta home

```
┌ Meta ─────────────────────────────────┐
│ M-C · Change in Settings              │
│ 36 events · 1,990 teams · 355 in top  │
│ cuts · Limitless via your server ·    │
│ updated 12 min ago                    │
│ [ 14 days | 30 days | Regulation ]    │
│                                       │
│ What's winning                     ⓘ  │
│  Rillaboom is on 55% of teams and 54% │
│  of top-cut teams.                    │
│  Rillaboom    55%  top cut 54%  W 48% │
│  Incineroar   …                       │
│                          See all ›    │
│ Rising                             ⓘ  │
│ Teams to beat                      ⓘ  │
│ Recent events            See all ›    │
└───────────────────────────────────────┘
```

- **Header:** the regulation (§2.3), and a line from the window's `sample`
  and the format's `lastFetched` in `/v1/formats`, or, on the device, from
  the corpus (§6). The
  window picker (segmented, `.labelsHidden()`) defaults to 30 days and is
  remembered (`AppSettings.metaWindow`).
- **What's winning:** the five most-used Pokémon in the window
  (`/v1/formats/{f}/pokemon?window=`), each with usage, top-cut rate and win
  rate (hidden under 30 matches, as the server sends it). The lead sentence
  names the most-used one, and says when a top-five Pokémon's top-cut rate
  is well above or below its usage. **See all ›** opens the full list:
  sortable by usage, top-cut rate, win rate and trend, filterable by name,
  each row opening the Pokémon page.
- **Rising:** the three biggest rises and falls in `trend`. Trend is always
  the last 14 days against the 14 before, whatever the window, and the card
  says so. While every trend is null (under 50 teams in either fortnight,
  as on the owner's server today with a 7-day lookback), the card says that
  instead of showing nothing: "Trends need 50 teams in each of the last two
  fortnights."
- **Teams to beat:** the five archetypes with the most top-cut teams
  (`/v1/formats/{f}/archetypes`), each with its four Pokémon, usage, top-cut
  rate and record. Tapping one opens the archetype page (§3.3).
- **Recent events:** the five newest stored events, with their size and
  winner's six Pokémon (`/v1/formats/{f}/events`, §5). **See all ›** opens
  Events.
- **Refreshing:** pull to refresh (⌘R on the Mac) asks the server fresh
  (§4.3).

### 3.2 The Pokémon page

From What's winning, the full list, a teammate, an archetype, or Mon
Index's card. It reads `/v1/formats/{f}/pokemon/{key}?window=`.

- **The numbers:** usage, top-cut rate, win rate with its range, and trend,
  each a tile with an ⓘ, and the sample under them.
- **Usage over time:** a Swift Charts line of `weekly` usage.
- **Sets:** the top whole sets, each with its share, **Save Set** (into
  Sets, through the importer `LimitlessTeamImport` uses) and **Calc
  Against This** (the calc with this set as the defender, keeping the calc's
  attacker: a new `AppNavigator` destination beside `.calcSet`, which loads
  a saved set as the attacker).
- **Items, abilities, natures, moves and Mega Stones:** share bars, top
  eight each, the rest a tap away.
- **Teammates:** the most common, each opening its own page.
- **Cores:** the pairs and trios from `/v1/formats/{f}/cores` that include
  it, with their lift.
- **Links:** Open in Mon Index (`.pokemon`), and Search Teams with it (Team
  Search, `.teamSearch(query:)`).
- **A Mega:** the server counts a Mega under its species, with its stone in
  `megaStones`. A Mega's page is its species' page, with the stone's share
  at the top.

### 3.3 The archetype page

From Teams to beat. Its core, usage, top-cut rate and record; its record
against each other archetype it has played (from `matchups`, best and worst
first, with their match counts); its best-placed example teams (§5), each
opening the team sheet `StandingDetailView` shows; and **Search These
Teams** in Team Search, with the core as the query.

### 3.4 Info sheets

One sheet component, `MetaInfoSheet`, shows a metric's definition from
`MetaDefinition`, an enum whose texts are the plan's §4.2 definitions word
for word: usage, top-cut rate, win rate, trend, core, archetype, set,
windows and sample size. Every ⓘ opens it, with `.sheetSize()` and a Done
button. When §4.2 changes, `MetaDefinition` changes in the same PR.

### 3.5 Mon Index's "In the meta" card

On `ChampionsPokemonDetailView`, under the base stats, for a species in
Settings' regulation:

- "On 55% of teams in M-C over the last 30 days, top cut 54%", the trend
  when there is one, and the most common set with Save Set and Calc
  Against This. **More ›** opens the Pokémon page.
- It reads the same answers as Meta home: the server's cached answers (§4),
  so opening a Pokémon doesn't usually ask the server anything, or the
  device's (§6), labelled "from this device" with its top-8 rate.
- **Hidden** when there's nothing to show: no server answer and no Team
  Search teams for the regulation, or the species on no team. Mon Index
  doesn't get an empty state or start a download: it's a reference first.

### 3.6 Species keys and names

The server names Pokémon by the app's species keys ("arcanine:hisui"). The
app makes a key with `TeamSearchVocabulary.identity(name:slug:).key`, as
`TournamentUsage` does. Phase 4 adds the reverse,
`TeamSearchVocabulary.species(forKey:)` (built in 4a), giving the species
term, and so the name and form, to show and open. A test runs every key in the golden file
(`backend/src/test/resources/golden/species-identity.json`) through it. A key
it can't name shows as the server sent it.

## 4. Reading `/v1`

### 4.1 The client

- **Models:** `MetaAPI.swift` decodes `/v1`'s responses: `Formats`,
  `PokemonList`, `PokemonDetail`, `Cores`, `Archetypes` and the new `Events`
  and `ArchetypeDetail`, mirroring `MetaResponses.java`. Fields the app can
  do without are optional, so a newer server's additions don't break an
  older app. Dates decode as ISO 8601 with or without fractional seconds:
  the server sends both (`generatedAt` has them, `lastEvent` doesn't).
- **Requests:** `MetaServerClient.fetch(_:etag:)` sends `If-None-Match`
  and answers `.notModified` for a 304. Each answer is a `MetaAPI.Endpoint`
  (`formats`, `pokemon(format:window:)`, `pokemon(format:key:window:)`,
  `cores` and `archetypes`; `archetype(id:)` and `events` come once 4b's
  endpoints exist), read through `MetaInsights`' `cached(_:)` and
  `load(_:force:)` (§4.3).
- **Errors:** `MetaFailure` tells apart "can't reach the server" (no
  connection, a timeout, a refused connection), "the server answered HTTP
  n", and "the answer didn't read" (a schema the app doesn't know), because
  §6 shows each differently.

### 4.2 The stale connection test

Settings' Test Connection showed old counts after new events had come in.
`MetaServerClient.session` uses `URLSessionConfiguration.default`, whose
`URLCache` honors the server's `Cache-Control: max-age=900`, so for 15
minutes `/v1/formats` came from the phone's cache without asking the server.
The same applies to `ServerCorpusFetcher`'s tournament list, so pulling to
refresh Team Search with the switch on could miss events for 15 minutes.

**The fix:** the session gets `urlCache = nil` and
`requestCachePolicy = .reloadIgnoringLocalCacheData`. URLSession then never
answers from its own cache, and the app's cache (§4.3) is the only one, with
one rule. A test stubs a server whose answer changes between two calls and
expects the second call to see the change; it fails before the fix.

### 4.3 The cache, and when to ask fresh

`MetaCache`, an actor, keeps each answer on disk in
`Caches/MetaServer/`, keyed by the server's address, the path and the
query, with its ETag, the time the app fetched it and the body.

The rule:

1. **Show what's cached straight away**, however old, with its age ("updated
   2 h ago").
2. **Ask the server when the cached answer is more than 15 minutes old**, or
   there's none: when a screen appears and when the app comes back to the
   foreground. Fifteen minutes is the server's own `max-age`, and the server's
   data changes only when it stores an event, at most once per 30-minute
   discovery poll.
3. **Always ask, whatever the age,** on pull to refresh (⌘R), Test
   Connection, turning the switch on, and changing the address.
4. **Every request sends the cached ETag.** A 304 keeps the cached body and
   resets its time, so asking costs the server almost nothing.
5. **When asking fails**, the cached answer stays on screen with "Couldn't
   reach the server. Showing data from 2 h ago." Nothing cached is thrown
   away for being old.
6. **A cached answer that no longer decodes** (the app was updated) is
   deleted and asked for again.
7. **Clearing:** Settings → Data Management's "Clear Team Search Data"
   becomes "Clear Tournament Data" and empties both caches, with their
   combined size. Turning the switch off keeps the cache, so turning it back
   on shows the old data at once.

Freshness shown to players is the format's `lastFetched` ("updated 12 min
ago": when the server last fetched an event), not when the app last asked.

## 5. Backend additions

Built in 4b, with tests on the fixture event on H2 and Postgres, and
Swagger annotations:

1. **`GET /v1/formats/{f}/events?limit=`**: the newest stored events, each
   with its name, date, players, whether its standings are final, and its
   top-cut size (`topCutPlayers`), and the winner's name, record and six
   species keys. For the
   Recent events card; `/v1/formats/{f}/tournaments` has Limitless's shape,
   which has no winner.
2. **Unique archetype names.** The name is the core's two most-used members,
   and two archetypes can share them (two "rillaboom+incineroar" on the
   owner's server on 2026-10-06). Add the next most-used member until the
   names differ. `id` doesn't change.
3. **`GET /v1/formats/{f}/archetypes/{id}?window=`**: one archetype, as in
   the list, with its five best-placed teams (event, placing, record and the
   six members' sets) for the archetype page. Best-placed means the lowest
   placing, then the bigger event, then the newer one.
4. **`golden/meta-fixture.json`**, for §10's check that the device and the
   server agree: the fixture event's usage, trends, the 12 most-used
   Pokémon's pages, cores and archetypes, recorded from `MetaService` and
   checked by `MetaGoldenFileTest` (`-Dgolden.record=true` records it
   again).

Nothing else is needed: the home, Pokémon page and Mon Index card use the
existing endpoints.

## 6. With the switch off, or the server unreachable

Unlike Team Search's corpus, `/v1`'s insights have no Limitless
equivalent, so the app works out what it can itself (decided 2026-10-06).

### 6.1 Which source

1. **The switch on and the server answering, or an answer of the server's
   cached** (§4.3): the server's numbers.
2. **Otherwise** (the switch off, the default; or on, with nothing cached
   and the server unreachable): the device's numbers, from Team Search's
   corpus for the regulation.

Every screen says which: "Limitless via your server" or "From 36 events
Team Search downloaded from Limitless, on this device". When the server is
on but unreachable, a banner says so above the device's numbers, with
**Try Again**.

### 6.2 What the device works out

`MetaDeviceInsights`, `nonisolated`, works from a `TeamCorpus` (the corpus
Team Search and the Problem Solver already use) into the same models the
server's answers decode into, so the screens don't care where the numbers
came from. A few thousand teams take milliseconds, off the main actor.
Items, abilities, natures and moves are standardized by `MetaNames`, a port
of the server's `NameStandardizer` built from the same bundled regulation
and Showdown files. The server also reads a snapshot of Serebii's Champions
item page, which the app doesn't bundle, so an item in no regulation's list
can be spelled differently on the device.

Built in 4c. `MetaDeviceInsightsTests` checks it against the backend's
`golden/meta-fixture.json`, and on 2026-10-06 it matched the owner's server
on live data (46 events, 2,633 teams): usage, trends, cores, archetypes, the
25 most-used Pokémon's pages and the newest events' winners were identical.

| Metric | On the device |
|---|---|
| Usage, trend, sets, items, abilities, moves, Mega Stones, teammates, weekly usage | The same as the server's: decklists carry everything they need, and the same windows, 16-player minimum and 50-team trend rule apply. |
| Cores | The same as the server's. |
| Archetypes | The same grouping as the server's, without matchups. |
| Top-cut rate | **Top-8 rate** instead: the share among teams placed 1st to 8th. The corpus has placings but not the events' phases, so it can't tell who played in a top cut. It has its own name and definition, so it's never mistaken for the server's. |
| Win rate | **Team record** instead: the wins, losses and ties of teams with the Pokémon, from their standings. The corpus has no pairings, so mirror matches can't be left out. Own name and definition; hidden under 30 matches, with the same Wilson range. |
| Archetype matchups | Not shown. They need pairings. |
| Recent events | The corpus's newest events, with their winners from the standings. |

The two device-only definitions join `MetaDefinition` (§3.4) and the plan's
§4.2.

### 6.3 Where the teams come from

- **What Team Search already downloaded.** Opening Meta reads
  `TeamCorpusStore.cachedCorpus(format:)` and never crawls Limitless by
  itself: Limitless returned HTTP 429 after about five full crawls in an
  hour.
- **Nothing downloaded yet:** a card says "Usage comes from tournament teams
  Team Search downloads from Limitless. None for M-C on this device yet."
  with **Download Events**, which loads the corpus the way the Problem
  Solver's "download" does (`TeamCorpusStore`, with its waits and retries
  after rate limits), with progress. With the switch on, that download
  comes from the server anyway (`PreferredCorpusFetcher`).
- **Pull to refresh** on the device's numbers refreshes the corpus as Team
  Search's pull to refresh does: the event list again, and only the events
  it doesn't have.

### 6.4 The states

| State | Meta home shows |
|---|---|
| Switch off, teams downloaded | The device's numbers, and under the source line, "More from a PK Reference server (beta): win rates without mirrors, top cuts, archetype matchups." with **Open Settings**. |
| Switch off, nothing downloaded | The Download Events card (§6.3), and Recent events from Limitless (the first page of Events, as Tournaments shows it). |
| On, server answering or cached | The server's numbers; when cached and unreachable, the banner from §4.3, rule 5. |
| On, nothing cached, unreachable | "Couldn't reach the server at http://localhost:8080" with **Try Again** and **Open Settings**, over the device's numbers or the Download Events card. |
| The source has nothing for the regulation | The warning in §2.3. |
| On, the answer doesn't read | "The server's answer is in a format this version can't read. Update the app or the server.", over the device's numbers. |

## 7. Doubles and singles

- **Now:** doubles. Limitless lists only doubles formats, and the server
  holds the Champions regulations it's set to (M-C on the owner's server).
- **Phase 5:** singles, from Smogon's BSS stats moved to the server, and the
  ladder. That's when a Doubles/Singles switch and the plan's
  "Tournaments | Ladder" control appear. Phase 4 shows
  neither, rather than a switch with nothing behind one side.
- **So Phase 5 adds rather than reworks:** the screens take a `MetaFormat`
  value (Settings' regulation, and doubles), not a bare regulation, and the
  home's cards take the data they show rather than
  fetching it themselves, so a ladder source can fill the same cards.

## 8. Layout and accessibility

- **iPhone:** one column of cards; the full Pokémon list is a `List`.
- **iPad and the Mac:** two columns of cards where the width allows
  (`DynamicTypeSize.gridColumns`), and the full Pokémon list beside its page
  through `ListDetailSplit`. On the Mac, the window picker is in the toolbar
  and ⌘R refreshes.
- **Large text:** stat tiles and rows use `AdaptiveStack` and
  `FlowLayout`, so they wrap into one column at accessibility sizes.
- **Charts:** every chart has an accessibility label and value per mark
  ("Week of 28 September: 52%"), and the weekly usage chart an
  `AXChartDescriptor`, so VoiceOver's audio graph works.
- **Not color alone:** trends show ▲/▼ and a signed number ("▲ 6 points");
  above or below popularity is said in words; bars carry their percentage as
  text.
- **One element per row:** a Pokémon row reads as one VoiceOver element:
  "Rillaboom. On 55% of teams, 54% of top-cut teams. Wins 48% of 2,280
  matches. No trend yet." Info buttons are labelled "About usage" and so on.
- **Colors:** any new color with a meaning is a `ColorRole`, held by
  `ColorRoleTests` to its contrast rules. Light and dark mode both checked.

## 9. PRs, in order

Each is a PR into `backend-integration`, updates the docs it affects, and
lists what was and wasn't checked.

1. **4a, app: the `/v1` client and the cache.** `MetaAPI` models, `MetaInsights`,
   ETags on `MetaServerClient`, `MetaCache` with §4.3's rule, the URL cache
   fix (§4.2), `species(forKey:)`. No new screens; Test Connection and Team
   Search's refresh see new events at once.
2. **4b, backend: events and archetypes** (§5), and the shared golden file
   of the fixture event's insights (§10).
3. **4c, app: insights on the device.** `MetaDeviceInsights` and
   `MetaNames` (§6.2), checked against the golden file, and the app's models
   and requests for 4b's events and archetype pages. No new screens.
4. **4d, app: the Meta tab.** The rename and its migration, Events inside
   Meta, the regulation header and its warnings, the window choice, the
   source rule and the states (§6), with Recent events. Built: `MetaTab`,
   `MetaModel` (the source rule, and `MetaText`'s sentences) and
   `EventsView`; `TabLayout` also reads the old tab name wherever one is
   stored, so a very old saved tab list keeps it.
5. **4e, app: Meta home's cards and the Pokémon page**, with the full list
   and the info sheets.
6. **4f, app: Teams to beat and the archetype page**, with the links to
   Team Search.
7. **4g, app: Mon Index's card.**

4a, 4b and 4c don't depend on each other, except that 4c's golden file
comes from 4b. 4e's Recent events and 4f's example teams need 4b with the
switch on.

## 10. Checks

- **Unit tests** (Swift Testing, canned responses, no network):
  - the tab migration: order, hidden and default kept, run twice, and run
    after the legacy migration;
  - decoding real `/v1` answers, saved once from the owner's server with
    read-only GETs, as fixtures in `PKReferenceTests`;
  - `MetaCache`: fresh, stale, 304, forced, failing with and without a
    cached answer, an old schema, and a changed address, with an injected
    clock;
  - the connection test regression (§4.2);
  - `species(forKey:)` over the golden file;
  - **the device and the server agree:** `golden/meta-fixture.json`,
    recorded from `MetaService` on the backend's fixture event
    (`backend/src/test/resources/limitless/`), holds its usage, trends,
    sets, teammates, cores and archetypes. The backend's tests and the app's
    `MetaDeviceInsights` tests both check it, as the species golden file is
    checked, so the two can't drift (the plan's §7);
  - the device's top-8 rate and team record on the same event, against
    numbers worked out by hand;
  - the source rule (§6.1) and each state in §6.4, with stubbed sources;
  - the lead sentences and VoiceOver labels, as plain functions, as
    `IntentAnswers` does;
  - the regulation warnings (§2.3);
  - `AppSettingsTests` pinning `metaWindow`.
- **Backend:** `mvn verify` (CI runs it), with the new endpoints on the
  fixture event on H2 and Postgres.
- **Builds:** iOS and Mac with no warnings (grep the logs for `warning:`).
- **Simulator** (the iPhone 17 Pro Max, `-parallel-testing-enabled NO`), in
  light and dark and at an accessibility text size:
  - the switch off, with and without Team Search's teams downloaded, and
    Download Events;
  - a regulation the server has no events for (M-B on the owner's server);
  - on, against the owner's server (read only);
  - on, with a wrong port (unreachable), with and without a cache;
  - a stored default tab of `tournaments` opening on Meta;
  - Meta under More.
- **Mac snapshots** (`DebugSnapshot.swift`), run with
  `-defaultTab meta -metaServerEnabled YES` and new `-debugOpenSheet` names:
  `metaPokemon` (the first Pokémon's page), `metaArchetype`, `metaEvents`
  and `metaInfo` (the usage info sheet). The settings passed this way apply
  to that run only.
- **VoiceOver:** on the owner's device or with Accessibility Inspector on
  the Mac build, over the charts and rows.
- **The owner's server isn't touched:** read-only GETs only. Anything that
  needs a server in another state (no events, an old schema) uses stubs, or
  an isolated test stack on other ports.

## 11. Decisions

The owner's, on 2026-10-06:

1. **Every screen uses Settings' regulation**, with a warning when that
   leaves nothing to show (§2.3).
2. **The default window is 30 days.**
3. **The device works out what it can** when the server is off or can't be
   reached (§6).
4. **The tab is "Meta"**, with the icon `chart.bar.xaxis`.

Still the owner's to do: **a backfill.** Rising stays empty until the server
has two fortnights of 50 teams or more; on 2026-10-06 it had looked back 7
days. `LIMITLESS_LOOKBACK=120d` (see
[`backend/README.md`](backend/README.md#finding-events-and-backfilling))
does it.
