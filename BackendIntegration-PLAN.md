# Backend integration: plan

How the app gets real insight from tournament and ladder data through the
Kafka backend (`backend/`), to help players prepare for events and climb the
ranked ladder. Written 2026-10-06.

**Branch:** `backend-integration`, made from `main` at 4b2587e and pushed.
Each phase below is one PR into `backend-integration`. `main` is merged into
it as it moves. It merges into `main` at milestones, with the app's side off
by default, so nothing that works today changes until it's ready.

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

## 2. What there is today

### 2.1 The app

Each device fetches its own data:

- **Team Search and the Problem Solver** crawl Limitless themselves
  (`TeamCorpusStore`). The Problem Solver ranks counters by
  `TournamentUsage`, which it computes from that corpus. Limitless returned
  HTTP 429 after about five full crawls in an hour.
- **The Tournaments tab** browses Limitless live.
- **Team Search's teammate suggestions** come from Smogon's chaos JSON,
  downloaded and reduced on the device (`SmogonUsageStore`,
  `SmogonInsights`).
- **Species names:** `TeamSearchVocabulary` maps Limitless's names to the
  app's species identities, counting Megas by their stones.

### 2.2 The backend (#84, #85)

Spring Boot with Kafka:

```
TournamentIngestor (polls page 1 every 30 min) → tournaments.discovered
StandingsFetcher                               → standings.fetched
UsageConsumer → per-format counters (H2)       → pokemon.usage (compacted)
GET /api/usage?format=…, /api/usage/{species}
```

The parts worth keeping:
- idempotent aggregation per tournament;
- retries, then a dead-letter topic;
- `NameStandardizer` for hand-typed items, abilities and moves.

What stands in the way of insight:

1. **It can't recompute anything.** Decklists are thrown away once counted,
   and `standings.fetched` has Kafka's default 7-day retention. A new metric
   can't be worked out from older events.
2. **Its counts are all-time per format.** There are no time windows, no
   placings or top cut, no pairs or cores, no full sets and no win rates.
3. **It only polls page 1** of the tournament list, so there's no backfill.
4. **Its species keys are Limitless slugs or lowercased names.** The app's
   identities come from its vocabulary, with Megas counted by stone. The two
   would disagree.
5. **It's only run on the owner's Mac**, against Docker's Kafka and live
   Limitless, with an H2 file database and no caching, rate limiting or
   deployment. Phase 0 found three things that would break or lose data
   there:
   - **The broker kept its topics in `/tmp` inside the container**, so
     recreating the container lost them.
   - **The broker takes messages up to about 1 MB.** Standings are about
     1.2 KB of JSON a player, so an event of about 850 players or more would
     fail to send. Nothing waited on sends, so it would be lost silently and
     fetched again on every poll.
   - **The first poll makes 51 requests at once** (the list and 50
     standings), over Limitless's limit of 50 in 5 minutes.
6. **It doesn't fetch match results**, though Limitless has them.

## 3. Data sources

Checked on 2026-10-06 unless marked otherwise.

- **Limitless's limit:** without a key, 50 requests in 5 minutes, reported
  in its `ratelimit` and `ratelimit-policy` headers.
- **Limitless covers doubles only.** Its VGC game lists only doubles
  formats (M-A to M-C, and Scarlet and Violet's regulations). Singles (Battle
  Stadium Singles) comes from Smogon's BSS stats and Showdown's BSS replays.

| Source | What it adds | Access | Use |
|---|---|---|---|
| **Limitless standings** (`/tournaments/{id}/standings`) | Teams, placings, records | No key | Have; keep every team |
| **Limitless pairings** (`/tournaments/{id}/pairings`) | Every match: round, phase, table, players, winner | No key | **Add.** Win rates, matchups, archetypes vs archetypes |
| **Limitless details** (`/details`) | Phases (Swiss, top cut) | No key | Add. Tells us who made top cut |
| **Limitless webhook** (`tournament:ended`) | A POST when an event ends | Needs an approved access key, which also raises rate limits | **Apply.** Replaces polling; produce straight onto Kafka |
| **Smogon stats** (monthly) | Ladder usage, items, abilities, moves, **spreads**, teammates, **checks and counters**, at ratings 0/1500/1630/1760, Bo1 and Bo3; leads files | Public files | Move the app's download to the server. M-C is there from 2026-09 |
| **Showdown replays** (`replay.pokemonshowdown.com/search.json?format=…`, 51 per page, with ratings; each replay's `.json` has its log) | Team preview (all 6), which 4 were brought, leads, who won, at each rating | Public; be gentle | Sample rated games for bring and lead rates and win rates by rating. Ask Showdown's staff before running it as a service |
| **Showdown replays by player** (`search.json?user=…`) | One player's games | Public | **On the device**, for "My games" (§5.3). Nothing goes to our server |
| **RK9** (official Regionals, Internationals, Worlds) | Official pairings, standings and team lists: the highest-stakes data | No public API | Ask for permission. Until then, Limitless covers grassroots and online events |
| **Event calendar** (Play! Pokémon) | Upcoming events, for "days until your event" | Not checked | Start with a small list the server serves and the owner edits |
| **Pokémon Champions' own ranked data** | The game's own usage, if it publishes any. Scarlet and Violet's showed in Pokémon HOME | Not checked | Look into it. If it exists, it's the most direct ladder source |

**Not used:** Pikalytics, Labmaus and similar sites. They have no public API,
and their numbers come from the sources above anyway.

## 4. Target design

### 4.1 The pipeline

Kafka earns its place here as a **replayable log**, not for scale (it's a few
hundred events a month). The fetched data stays in compacted topics forever.
Each insight is a consumer group that builds its own Postgres tables. A new
metric is a new consumer read from offset 0, and fixing a metric means
rebuilding its tables from the log.

```
Limitless webhook ─┐
poller (fallback) ─┼→ tournaments.ended ─→ EventFetcher ─┬→ standings.fetched ─┐
backfill job ──────┘                                     └→ pairings.fetched ──┤
                                                                               ▼
                                                     TeamNormalizer → teams.normalized
Smogon monthly job ─→ ladder.stats (key format|month|rating) ──────────┐       │
Showdown sampler ───→ replays.fetched → replays.normalized ────────────┤       │
                                                                       ▼       ▼
                                   projections (consumer groups) → Postgres → API v1
                                   usage windows · top cut · trends · cores · sets ·
                                   archetypes · matchups · ladder · leads and brings
```

- **Compaction:** `standings.fetched`, `pairings.fetched` and
  `replays.fetched` are compacted by event or replay id, and never deleted.
- **Normalize once, the app's way.** `TeamNormalizer` reads the app's own
  `team_search_vocab.json`, `champions-*.json` and
  `showdown-champions-data.json`. Maven bundles them, as it does the data
  files `NameStandardizer` already reads. Species keys, Megas by stone and
  move names then match the app's exactly. Names nothing matches are kept and
  logged, and `GET /v1/admin/unknown-names` lists them.
- **Idempotence:** each projection records the events it has applied, with
  its version, so redelivery and replays are no-ops (as now).
- **Storage:** Postgres, with Flyway migrations, replaces the H2 file.

### 4.2 Metrics

Each definition goes into the app's info sheets word for word.

- **Usage:** the share of published teams in the window that have the
  Pokémon. Each team counts once.
- **Top-cut rate:** its share among teams that made top cut, from the
  event's phases (when there are none, the top 8). Next to usage, it shows
  whether a Pokémon does better or worse than its popularity.
- **Win rate:** match wins out of matches, for teams with it, from the
  pairings. Mirror matches don't count. It's shown with a 95% range (Wilson),
  and hidden under 30 matches.
- **Trend:** usage over the last 14 days against the 14 before, in
  percentage points.
- **Core:** a pair or trio that's on many teams together, against what
  chance would give.
- **Archetype:** teams that share at least 4 of 6 Pokémon with a core, named
  by the core's two most common members. It has its own usage, top-cut rate
  and record against the other archetypes.
- **Set:** a whole set (item, ability, nature and four moves), counted as
  one. Today each part is counted on its own.
- **Windows:** the regulation so far, the last 30 days and the last 14 days,
  with a minimum event size, as the app's corpus has.
- **Sample size:** every number comes with how many teams, events or
  matches it's from.

### 4.3 The API

Version 1 is read-only, the same for every user, and cached.

| Endpoint | Returns |
|---|---|
| `GET /v1/formats` | Formats, with their counts, date range and freshness |
| `GET /v1/formats/{f}/pokemon?window=` | Usage, top-cut rate, win rate and trend for each Pokémon |
| `GET /v1/formats/{f}/pokemon/{id}` | Sets, items, abilities, moves, teammates, cores, the matchups it wins and loses, and weekly usage |
| `GET /v1/formats/{f}/archetypes`, `/archetypes/{id}` | Archetypes, their record against each other, and example teams |
| `GET /v1/formats/{f}/teams?since=&cursor=` | **Team Search's corpus**, paged, so devices stop crawling Limitless |
| `GET /v1/formats/{f}/events?cursor=` | Recent events, with their top cut |
| `GET /v1/ladder/{f}?rating=&month=` | Smogon's stats, already reduced; leads, and brings once replays are in |
| `GET /v1/events/upcoming` | The event calendar |

- **Every response** carries `generatedAt`, `window` and its sample sizes.
- **HTTP:** responses have ETag and `Cache-Control` (15 minutes) and are
  gzipped, so a CDN in front can serve most requests.
- **OpenAPI:** springdoc is already set up for the API docs.
- **`/api/usage`:** drop it once v1 covers it. Nothing calls it.

### 4.4 The app

- **Client:** `PKReferenceServer` (an actor) behind a protocol, as with
  `TeamCorpusFetching`, so tests can use canned responses.
- **Setting:** it's **off by default**, under Settings → "Meta data from the
  PK Reference server (beta)". Off, or with the server unreachable, the app
  behaves exactly as it does today, fetching from Limitless and Smogon
  itself.
- **Server address:** while the app isn't deployed, the server is the
  owner's local Docker setup, so the setting has a server address that
  defaults to `http://localhost:8080`. That's the simulator's and the Mac's
  own machine; a phone needs the Mac's network address. App Transport
  Security's `NSAllowsLocalNetworking` allows plain HTTP to it.
- **Cache:** responses are kept on disk with their `generatedAt`, and each
  screen says how old its data is.
- **Shared corpus:** Team Search and the Problem Solver's `TournamentUsage`
  get the corpus from the server through a `TeamCorpusFetching` fetcher.
  They fall back to Limitless, so their code doesn't change.

## 5. The UI

### 5.1 Principles

1. **Lead with the finding.** A card says it in a sentence, such as "On 48%
   of teams, up 6 points in two weeks", with the numbers under it and the
   detail a tap away.
2. **One format picker for the whole app.** It's remembered and shared by
   the Meta tab, Team Search, the Problem Solver and Speed Tiers.
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
   columns with a sidebar.

### 5.2 A Meta tab

It **replaces the Tournaments tab** (decided 2026-10-06) and becomes the home
for tournament and ladder data. The Tournaments list moves into it as Events.
Saved settings that name the Tournaments tab (the default tab, the tab bar's
order) carry over to Meta. It covers doubles and singles (decided
2026-10-06), with a Doubles/Singles switch beside the format picker.

```
┌ Meta ─────────────────── [M-C ▾] ┐
│ 212 events · 9,410 teams · 12m ago│
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

Tapping a Pokémon opens its meta page:
- usage over time;
- its top sets, each with **Save set** and **Calc against this**;
- its teammates and cores;
- the matchups it wins and loses.

Team Search keeps its own tab (decided 2026-09-24), with links both ways.

### 5.3 Insight in today's screens

- **Mon Index:** an "In the meta" card, with usage, the trend, and the most
  common set with Save and Calc buttons.
- **Damage Calc:** "Common sets" loads a defender's or attacker's most-used
  set in one tap.
- **Speed Tiers:** a "Meta only" filter for Pokémon above a usage cutoff,
  with their common speed investment from Smogon's spreads.
- **Teams:** "Check against the meta" on a saved team opens the threat
  report below.
- **Problem Solver:** it already ranks by usage. It gets the server's
  numbers, and later the win rates too.

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

## 6. Phases

Each phase is one PR into `backend-integration`.

0. **Make it real** (backend only).
   - Run it once against Kafka (`docker compose`) and live Limitless,
     gently, and fix what breaks.
   - A throttle in `LimitlessClient` that keeps to 50 requests in 5
     minutes and reads Limitless's `ratelimit` headers. Without it, the
     first poll (the list and 50 standings) goes over.
   - Postgres and Flyway in `docker-compose.yml`.
   - Compacted, never-deleted fetched topics.
   - A GitHub Actions job running `mvn verify` (the repo has no CI).
1. **Keep everything, normalize once.**
   - `TeamStore` tables (events, teams, members, matches).
   - `TeamNormalizer` on the app's vocabulary.
   - A throttled, resumable backfill of the current and previous regulation.
   - Pairings and details fetched and stored.
2. **Insight projections and API v1.**
   - Usage windows, top-cut rate, trends, cores, full sets, win rates, and a
     first version of archetypes.
   - `/v1` with caching and OpenAPI.
3. **The app's client, behind the setting.**
   - Client, disk cache, the setting and freshness labels.
   - Team Search's corpus and the Problem Solver's usage from the server,
     with fallback.
   - The server is the owner's local Docker setup, through the setting's
     server address.
4. **Meta tab (first version).**
   - Home, the Pokémon page and the info sheets.
   - Mon Index's "In the meta" card.
   - The shared format picker.
5. **Ladder.**
   - Smogon's monthly download moves to the server (`ladder.stats`), with a
     rating band picker covering Bo1 and Bo3.
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
   - Merge into `main`, with the setting still off by default.

**Later:** push notifications when a big event's results are in.

## 7. Verification

- **Backend.** Each projection has unit tests on fixtures: real Limitless,
  Smogon and replay responses, saved once (tests never call live services).
  There's the embedded-Kafka pipeline test, and a **replay test**: building
  a projection again from its topics gives identical tables.
- **The server and the app must agree.** For the same corpus, the server's
  usage must equal the app's `TournamentUsage` exactly, and its Smogon
  reduction must equal `SmogonUsage.reduce`. Golden files shared by both
  test suites check this, so the two normalizers can't drift apart.
- **The app.** Swift tests with canned responses, including the fallbacks:
  the server down, slow, or answering with an old schema.
- **The UI.** Simulator runs and Mac snapshots of each new screen, and a
  VoiceOver pass over the charts.

## 8. Risks

- **Terms and rate limits** (Limitless, Showdown, RK9). Ask first and cache
  hard. One crawler for every user is lighter on Limitless than today's
  crawl on each device.
- **Thin data early in a regulation.** Show the counts and hide weak win
  rates. Build the planned "include last regulation's teams that are still
  legal" option.
- **Two normalizers drifting apart.** The shared vocabulary files and the
  golden tests (§7) guard against it.
- **Running a server.** Kafka is more to run than the volume needs. A
  single-node KRaft broker keeps it small. The app's fallback means an
  outage costs freshness, not features.
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
