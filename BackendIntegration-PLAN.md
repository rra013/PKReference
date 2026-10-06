# Backend integration: plan

How the app gets real insight from tournament and ladder data through the
Kafka backend (`backend/`), to help players prepare for events and climb the
ranked ladder. Written 2026-10-06; phases 0–4 are built.

This file is the roadmap: the goals, the design, the metrics' definitions,
the owner's decisions and the phases. How to run the backend is in
[`backend/README.md`](backend/README.md), the project's state in
[`HANDOFF.md`](HANDOFF.md), and the app's features in [`README.md`](README.md).
Phase 4 has its own file, [`BackendIntegration-PHASE4.md`](BackendIntegration-PHASE4.md).

**Branch:** `backend-integration`, made from `main` at 4b2587e. Each phase is
one or two PRs into it. It merges into `main` at milestones, with the app's
side off by default, so nothing that works today changes until it's ready.

## 1. What players get

Two questions drive everything here:

- **"What will I face at my event, and is my team ready?"** The teams that
  win right now, the threats that matter most to *my* team, and the calcs,
  speed checks and matchups to work through before the event.
- **"What's used at my rating, and what beats it?"** The ladder meta at the
  rating I'm at and the one above, what people bring and lead with, and where
  my own games go wrong.

Counting what people use answers neither. The plan adds what wins (top-cut
rate, win rates from match results), what's changing (trends), what goes
together (full sets, cores, archetypes), and how each of these meets the
player's own team. The app also has to keep working when the server doesn't.

## 2. Done: phases 0–4

Each PR's description says what it changed and what was checked.

| Phase | PRs | What shipped |
|---|---|---|
| Plan | #93 | This file. |
| 0, make it real | #94, #95 | Postgres with Flyway in place of the H2 file; Kafka and Postgres data in Docker volumes; `standings.fetched` compacted and never deleted, taking 5 MB records, compressed with zstd; every send awaited; `RequestThrottle` keeping to 40 Limitless requests in 5 minutes and reading its `ratelimit` header; consumers taking 10 records a poll with 15 minutes between polls. #95 runs `mvn verify` on GitHub Actions. |
| 1a, keep everything | #96 | `EventDiscovery` walks each format's list back through a lookback (`LIMITLESS_LOOKBACK`, longer once to backfill) with the app's rules: 16 players or more, final 48 hours after the start, fetched again every 6 hours until then. `EventFetcher` fetches details, standings and pairings. The team store tables: `event`, `event_phase`, `team`, `team_member(_move)`, `pairing`. Usage counters count only final standings. |
| 1b, normalize once | #97 | `SpeciesVocabularies`, a Java port of the app's `TeamSearchVocabulary`, gives each stored member the app's species key and Mega Stone. A golden file recorded from the app (`backend/src/test/resources/golden/species-identity.json`, 171 cases) is checked by both test suites. |
| 2a, insights | #98 | `/v1/formats` and `/v1/formats/{f}/pokemon[/{key}]`: usage windows, top-cut rate, trends, items, abilities, natures, moves, Mega Stones, teammates, whole sets and weekly usage. Worked out from the team store when asked and memoized on `store_version`, rather than kept in more tables: at a few thousand teams a format it takes milliseconds. Cached 15 minutes, with weak ETags, gzipped. |
| 2b, what wins | #99 | Win records from the pairings (mirrors left out, Wilson 95% ranges, none under 30 matches), `/v1/formats/{f}/cores` and `/v1/formats/{f}/archetypes`. Swagger UI describes every endpoint and field. |
| 3a, the corpus | #100 | `/v1/formats/{f}/tournaments` and `/v1/tournaments/{id}/standings`: the stored events in Limitless's own shapes. |
| 3b, the app's switch | #101 | Settings → PK Reference Server (Beta), off by default, with the address (`http://localhost:8080`) and Test Connection. With it on, Team Search's corpus, and so the Problem Solver's usage, comes from the server through `PreferredCorpusFetcher` (`PKReference/MetaServer.swift`), and from Limitless whenever the server can't answer. Checked end to end against the owner's server. |
| 4, the Meta tab | #102–#109 | The Meta tab in place of Tournaments, with Events inside it: what's winning, rising and falling, teams to beat, recent events, every Pokémon's and archetype's page, and an ⓘ definition for each number; Mon Index's "In the meta" card. The backend adds recent events, archetype pages and unique archetype names (#104). The app reads `/v1` through a disk cache with an explicit freshness rule (#103), and without the server works the same numbers out on the device from Team Search's teams, checked against the server by a shared golden file (#105). [`BackendIntegration-PHASE4.md`](BackendIntegration-PHASE4.md) has the design and each PR. |

**Findings worth keeping:**

- **What the first backend (#84, #85) would have broken or lost** on the
  owner's machine, found in Phase 0: the broker kept its topics in `/tmp`
  inside the container; standings were kept 7 days, so nothing could be
  recomputed; an event of about 850 players would pass the broker's 1 MB
  limit, and since nothing waited on sends it would be lost silently; and
  the first poll made 51 requests at once, over Limitless's 50 in 5 minutes.
- **Events were counted while they ran** (Phase 1a). Page 1 of the list
  includes events in progress; their part-way standings were counted,
  marked done and never fetched again.
- **H2 passed SQL that Postgres rejects** (a column named `placing`), so the
  store's tests also run on Postgres through Testcontainers.
- **Limitless covers doubles only.** Its VGC game lists only doubles formats.
  Singles needs Smogon's BSS stats and Showdown's BSS replays (Phase 5).
- **Limitless returned HTTP 429** after about five of the app's full crawls
  in an hour. One server crawling for every device is lighter on it.
- **URLSession's cache honored the server's 15-minute `Cache-Control`**, so
  Test Connection showed stale counts after new events came in. Phase 4
  fixes it (see its file).
- **Archetype names could repeat.** The name was the core's two most-used
  members, and two cores of four can share those (seen on the owner's server
  on 2026-10-06, and in the fixture event: two "rillaboom+incineroar").
  Phase 4b adds more of the core until names differ.

## 3. Data sources

Checked on 2026-10-06 unless marked otherwise.

- **Limitless's limit:** without a key, 50 requests in 5 minutes, reported
  in its `ratelimit` and `ratelimit-policy` headers.
- **Limitless covers doubles only.** Its VGC game lists only doubles
  formats (M-A to M-C, and Scarlet and Violet's regulations). Singles (Battle
  Stadium Singles) comes from Smogon's BSS stats and Showdown's BSS replays.

| Source | What it adds | Access | Use |
|---|---|---|---|
| **Limitless standings** (`/tournaments/{id}/standings`) | Teams, placings, records | No key | Used: every team kept |
| **Limitless pairings** (`/tournaments/{id}/pairings`) | Every match: round, phase, table, players, winner | No key | Used: win rates, archetype matchups |
| **Limitless details** (`/details`) | Phases (Swiss, top cut) | No key | Used: who made top cut |
| **Limitless webhook** (`tournament:ended`) | A POST when an event ends | Needs an approved access key, which also raises rate limits | Later (§9): replaces polling |
| **Smogon stats** (monthly) | Ladder usage, items, abilities, moves, **spreads**, teammates, **checks and counters**, at ratings 0/1500/1630/1760, Bo1 and Bo3; leads files | Public files | Phase 5: move the app's download to the server. M-C is there from 2026-09 |
| **Showdown replays** (`replay.pokemonshowdown.com/search.json?format=…`, 51 per page, with ratings; each replay's `.json` has its log) | Team preview (all 6), which 4 were brought, leads, who won, at each rating | Public; be gentle | Phase 5, once Showdown's staff have been asked (§9) |
| **Showdown replays by player** (`search.json?user=…`) | One player's games | Public | **On the device**, for "My games" (§5.4). Nothing goes to our server |
| **RK9** (official Regionals, Internationals, Worlds) | Official pairings, standings and team lists: the highest-stakes data | No public API | Ask for permission (later). Until then, Limitless covers grassroots and online events |
| **Event calendar** (Play! Pokémon) | Upcoming events, for "days until your event" | Not checked | Start with a small list the server serves and the owner edits |
| **Pokémon Champions' own ranked data** | The game's own usage, if it publishes any. Scarlet and Violet's showed in Pokémon HOME | Not checked | Look into it. If it exists, it's the most direct ladder source |

**Not used:** Pikalytics, Labmaus and similar sites. They have no public API,
and their numbers come from the sources above anyway.

## 4. Design

### 4.1 The pipeline

Kafka earns its place here as a **replayable log**, not for scale (it's a few
hundred events a month). The fetched data stays in compacted topics forever,
so anything built from it can be rebuilt by reading them again.

Built (phases 0–3):

```
EventDiscovery (every 30 min, walks the lookback) → tournaments.discovered
EventFetcher (details, standings, pairings)       → standings.fetched + pairings.fetched (compacted, kept)
TeamStoreConsumer                                 → Postgres team store
UsageConsumer                                     → usage_counter + pokemon.usage (the older /api/usage)
MetaService (from the team store, memoized)       → /v1 insights
CorpusRepository                                  → /v1 corpus, in Limitless's shapes
```

Still to come:

```
Limitless webhook ─→ tournaments.ended (replaces the poll; §9)
Smogon monthly job ─→ ladder.stats (key format|month|rating)            Phase 5
Showdown sampler ───→ replays.fetched → replays.normalized               Phase 5
```

- **Normalize once, the app's way.** The backend reads the app's own data
  files (`champions-*.json`, `team_search_vocab.json`,
  `showdown-champions-data.json`), which Maven bundles, so species keys,
  Megas by stone and move names match the app's. The golden file keeps the
  two sides from drifting. Still to build: `GET /v1/admin/unknown-names`,
  listing the names nothing matched.
- **Idempotence:** a newer fetch of an event replaces its rows and an older
  one is ignored; the usage counters record the events they've applied.
- **Projections:** insights are worked out from the team store when asked
  (§2, Phase 2a). If one gets slow, it becomes a consumer group with its own
  tables, rebuilt from the topics.

### 4.2 Metrics

Each definition goes into the app's info sheets word for word. They describe
what `MetaService` computes.

- **Usage:** the share of published teams in the window that have the
  Pokémon. Each team counts once.
- **Top-cut rate:** its share among teams that played in a top cut (a
  bracket phase of the event). Events without a bracket add no top-cut
  teams. Next to usage, it shows whether a Pokémon does better or worse than
  its popularity.
- **Win rate:** match wins out of matches, for teams with it, from the
  pairings. Mirror matches (both teams have it) don't count; a tie is half a
  win. It's shown with a 95% range (Wilson), and hidden under 30 matches.
- **Top-8 rate** (worked out on the device, without the server): its share
  among teams placed 1st to 8th. The device has placings but not the events'
  phases, so it can't tell who played in a top cut.
- **Team record** (on the device): the wins, losses and ties of teams with
  it, from their standings. Without pairings, mirror matches can't be left
  out. A tie is half a win; shown with a 95% range and hidden under 30
  matches, as win rate is.
- **Trend:** usage over the last 14 days against the 14 before, in
  percentage points. Hidden when either fortnight has under 50 teams.
- **Core:** two or three Pokémon on at least 4 teams together, with its
  lift: how much more often they're together than chance would give.
- **Archetype:** teams built around a core of four. The cores are the most
  common sets of four (on at least 4 teams and 2% of them) that share at most
  two Pokémon with any more common core. Each team belongs to the most common
  core it contains; teams with none are "other". An archetype has its own
  usage, top-cut rate, record, and record against each other archetype.
- **Set:** a whole set (item, ability, nature and four moves), counted as
  one.
- **Windows:** the last 14 days, the last 30 days, or the regulation (every
  stored event of the format). Events have 16 players or more, as in the
  app's corpus.
- **Sample size:** every number comes with how many teams, events or
  matches it's from.

### 4.3 The API

Version 1 is read-only, the same for every user, and cached: every response
has `Cache-Control` (15 minutes) and a weak ETag (a matching `If-None-Match`
gets a 304), is gzipped, and says its window, `generatedAt` and sample
sizes. Swagger UI documents each one; [`backend/README.md`](backend/README.md#api-v1)
has examples.

| Endpoint | Returns | State |
|---|---|---|
| `GET /v1/formats` | Formats, with their counts, date range and freshness | Built (2a) |
| `GET /v1/formats/{f}/pokemon?window=` | Usage, top-cut rate, win rate and trend for each Pokémon | Built (2a, 2b) |
| `GET /v1/formats/{f}/pokemon/{key}` | Items, abilities, natures, moves, Mega Stones, teammates, whole sets, weekly usage | Built (2a) |
| `GET /v1/formats/{f}/cores` | Pairs and trios, with their lift | Built (2b) |
| `GET /v1/formats/{f}/archetypes` | Archetypes, with their records against each other | Built (2b) |
| `GET /v1/formats/{f}/tournaments`, `/v1/tournaments/{id}/standings` | Team Search's corpus, in Limitless's shapes | Built (3a) |
| `GET /v1/formats/{f}/events` | Recent events, with their winners and top cut | Built (4b) |
| `GET /v1/formats/{f}/archetypes/{id}` | One archetype's example teams | Built (4b) |
| `GET /v1/formats/{f}/pokemon/{key}` matchups | The archetypes it does best and worst against | Later |
| `GET /v1/ladder/{f}?rating=&month=` | Smogon's stats, already reduced; leads, and brings once replays are in | Phase 5 |
| `GET /v1/events/upcoming` | The event calendar | Phase 6 |

`/api/usage`, the first backend's all-time counts, is still served. Nothing
calls it; drop it, with `UsageConsumer` and its tables, once nothing needs
it (Phase 7 at the latest).

### 4.4 The app

- **Setting:** Settings → PK Reference Server (Beta), **off by default**,
  with the server's address. While the app isn't deployed the server is the
  owner's local Docker setup, so the address defaults to
  `http://localhost:8080`: the simulator's and the Mac's own machine. A phone
  needs the Mac's network address. `NSAllowsLocalNetworking` allows plain
  HTTP to it.
- **Client:** `MetaServerClient` (`PKReference/MetaServer.swift`), a small
  struct that GETs and decodes JSON with short timeouts. Tests stub its
  `URLSession`.
- **Shared corpus:** with the switch on, Team Search and the Problem
  Solver's `TournamentUsage` read their corpus from the server through
  `PreferredCorpusFetcher`, and from Limitless whenever the server can't
  answer, so their code didn't change.
- **Insights** (Phase 4): a client for `/v1` on `MetaServerClient`, a disk
  cache, and the rule for when to ask fresh; without the server, the same
  insights worked out on the device from Team Search's corpus, where the
  corpus allows. See the Phase 4 file.

## 5. The UI

### 5.1 Principles

1. **Lead with the finding.** A card says it in a sentence, such as "On 48%
   of teams, up 6 points in two weeks", with the numbers under it and the
   detail a tap away.
2. **One regulation for the whole app:** Settings' Champions regulation,
   with a warning when a screen has nothing for it (decided 2026-10-06).
3. **Say where each number comes from, and how many it's from.** For
   example: "212 events · 9,410 teams · Limitless · updated 12 min ago".
   Small samples say so, and win rates under 30 matches are hidden.
4. **Plain words, each defined once.** Usage, top-cut rate, win rate and
   trend each get an ⓘ with its §4.2 definition. No "chaos", "conversion" or
   "Bo3 1760 cutoff" without explanation. "Players rated 1760+" says it.
5. **Put insight where players already are, before adding screens.** (§5.3)
6. **Guided flows over dashboards** for the two questions in §1 (§5.4).
7. **Charts** use Swift Charts: sparklines for trends, bars for shares. They
   have VoiceOver labels and never rely on color alone.
8. **Layout:** iPhone first, one column of cards. On iPad and the Mac, two
   columns.

### 5.2 A Meta tab

It **replaces the Tournaments tab** (decided 2026-10-06) and becomes the home
for tournament and ladder data. The Tournaments list moves into it as Events.
It covers doubles and singles (decided 2026-10-06); singles waits for Phase 5.
Team Search keeps its own tab (decided 2026-09-24), with links both ways.

```
┌ Meta ─────────────────────────────┐
│ M-C (Settings) · 212 events ·     │
│ 9,410 teams · 12m ago             │
│ [ Tournaments | Ladder 1760+ ]    │
│                                   │
│ What's winning                    │
│  Incineroar   48%  ▲6  top cut 55%│
│  …                     See all ›  │
│ Rising this fortnight             │
│ Teams to beat (archetypes)        │
│ Recent events                     │
│ [Prepare for an event] [Climb]    │
└───────────────────────────────────┘
```

Tapping a Pokémon opens its meta page: usage over time; its top sets, each
with **Save set** and **Calc against this**; its teammates and cores; and,
later, the matchups it wins and loses. The first version is Phase 4.

### 5.3 Insight in today's screens

- **Mon Index:** an "In the meta" card, with usage, the trend, and the most
  common set with Save and Calc buttons (Phase 4).
- **Damage Calc:** "Common sets" loads a defender's or attacker's most-used
  set in one tap.
- **Speed Tiers:** a "Meta only" filter for Pokémon above a usage cutoff,
  with their common speed investment from Smogon's spreads.
- **Teams:** "Check against the meta" on a saved team opens the threat
  report below.
- **Problem Solver:** it already ranks by usage, from the server's corpus
  when the switch is on. Win rates could join later.

### 5.4 The two flows

**Prepare for an event.** Pick a saved team, the format and the event's
date. Then:
1. **Threats:** the Pokémon and sets most worth worrying about, ranked by
   usage × how much damage they do to the team. The ranking uses the existing
   calc, as the Problem Solver does.
2. **Speed checks:** the meta's common speeds against the team's.
3. **Archetypes:** the team against the top archetypes, by type and the
   calc, with their records from pairings.
4. **Checklist:** notes saved with the team, and a countdown to the event.

**Climb the ladder.** Pick a rating band. Then:
1. What's common at that band, and what changes at the next one up
   (Smogon's 0/1500/1630/1760 cutoffs).
2. What people bring and lead with (replays, Phase 5).
3. The threats to the team at that band.
4. **My games** (optional): enter a Showdown username. The app fetches that
   player's public replays **itself** and shows their record against each
   Pokémon and archetype, and their worst matchups. Nothing is sent to our
   server.

## 6. Remaining phases

Each phase is one PR into `backend-integration`, or several where it's large.

5. **Ladder and singles.**
   - Smogon's monthly download moves to the server (`ladder.stats`), with a
     rating band picker covering Bo1 and Bo3, for doubles and BSS. This is
     what brings singles to the Meta tab, and its Doubles/Singles switch.
   - Once Showdown's staff have been asked (later; see §9), the replay
     sampler: leads, brings and win rates by band.
6. **The planning flows.**
   - Prepare for an event and Climb the ladder.
   - Teams' "Check against the meta" and Damage Calc's "Common sets".
   - My games, on the device.
7. **Launch** (when the app ships).
   - Hosting: one small host with single-node Kafka (KRaft), Postgres and
     the service, behind a CDN. Until then, the owner's local Docker setup.
   - Monitoring: ingest lag, the newest event's age, dead-letter growth and
     unknown names.
   - Backups and the cost.
   - Ask Limitless for an access key and the webhook, and about running a
     public service on their API.
   - Drop `/api/usage`.
   - Merge into `main`, with the setting still off by default.

**Later:** push notifications when a big event's results are in.

## 7. Verification

- **Backend.** Unit tests on fixtures: real Limitless responses, saved once
  with players' names replaced (tests never call live services); the
  embedded-Kafka pipeline tests; and the store and insight tests on H2 and
  on Postgres. Insight numbers are checked against the same numbers worked
  out independently (in Python, for 2a and 2b). Phase 5's Smogon and replay
  fixtures follow the same rule. Still to add: a **replay test**, building a
  projection again from its topics and getting identical tables.
- **The server and the app must agree.** Species keys already do: the golden
  file (§2, 1b) is checked by both suites. Phase 4 adds a second golden
  file, the fixture event's insights, checked by the backend and by the
  app's device version. Still to add: the server's Smogon reduction
  (Phase 5) must equal `SmogonUsage.reduce`.
- **The app.** Swift tests with canned responses, including the fallbacks:
  the server down, slow, or answering with an old schema.
- **The UI.** Simulator runs and Mac snapshots of each new screen, and a
  VoiceOver pass over the charts.

## 8. Risks

- **Terms and rate limits** (Limitless, Showdown, RK9). Ask first and cache
  hard. One crawler for every user is lighter on Limitless than today's
  crawl on each device.
- **Thin data early in a regulation.** Show the counts, and hide weak win
  rates and trends. Build the planned "include last regulation's teams that
  are still legal" option.
- **Two normalizers drifting apart.** The shared vocabulary files and the
  golden tests (§7) guard against it.
- **Running a server.** Kafka is more to run than the volume needs. A
  single-node KRaft broker keeps it small. The app's fallback means an
  outage costs freshness and some features, not the tab: Team Search reads
  Limitless again, and the Meta tab works out usage, sets, cores and
  archetypes on the device, without top cuts, mirror-free win rates or
  matchups (the Phase 4 file, §6).
- **Privacy.** There are no accounts, and nothing personal goes to the
  server. My games stays on the device.

## 9. The owner's decisions (2026-10-06)

1. **Hosting:** the owner's local Docker setup while the app isn't deployed.
   Hosting is decided when the app ships (Phase 7).
2. **The Meta tab:** it replaces the Tournaments tab. Team Search stays its
   own tab.
3. **Scope:** doubles and singles. Limitless covers doubles only, so singles
   comes from Smogon's and Showdown's BSS data.
4. **Contacting Limitless, Showdown's staff and RK9:** later. Until then,
   the server keeps to Limitless's keyless limits, polls instead of using the
   webhook, and doesn't sample Showdown's replays. My games (one player's
   own replays, fetched on the device) doesn't wait for this.
5. **The setting:** off by default.
6. **The regulation:** every screen, the Meta tab included, uses Settings'
   regulation, with a warning when there's nothing for it.
7. **Without the server**, the Meta tab works out what it can on the
   device, from Team Search's teams.
8. **The Meta tab's defaults:** named "Meta", icon `chart.bar.xaxis`, window
   30 days.
