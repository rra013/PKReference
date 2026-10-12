# Backend integration, Phase 5: the ladder, and singles

The detailed plan for Phase 5 of [`BackendIntegration-PLAN.md`](BackendIntegration-PLAN.md).
The plan has the goals and the owner's decisions (§9); this file says what
Phase 5 builds, how, and in which PRs. Written 2026-10-12, against
`backend-integration` at a9df83a.

## 1. What ships

- **The ladder in the Meta tab.** One switch at the top: **Tournaments**
  (what the tab shows today), **Doubles Ladder** and **Singles Ladder**
  (decided 2026-10-12). Singles is Battle Stadium Singles; Limitless has no
  singles events, so singles is ladder only.
- **A rating band picker:** All players, 1500+, 1630+ and 1760+, Smogon's
  four cutoffs. Doubles also picks Best of 1 or Best of 3.
- **Ladder home:** the month and how many battles it's from, the most-used
  Pokémon, the common leads, what's rising since last month and what's used
  more at higher ratings.
- **A Pokémon's ladder page:** its usage at each band, items, abilities,
  moves, natures, **stat-point spreads** (which Limitless doesn't publish),
  teammates and how often it leads, with Save Set and Calc Against This.
- **The server fetches Smogon's stats once for everyone** (`ladder.stats`),
  reduces each file to what the app shows, and serves it at `/v1/ladder`.
- **Without the server, the app downloads Smogon's file itself** and works
  out the same numbers (decided 2026-10-12), as Team Search does today.
  Team Search's "often paired with" reads through the same store.

Out of Phase 5:

- **The replay sampler** (what people bring, win rates by band). It waits
  until Showdown's staff have been asked (the plan's decision 4).
- **The planning flows** (Climb the ladder, Prepare for an event), Damage
  Calc's "Common sets" and Speed Tiers' "Meta only": Phase 6.

## 2. What Smogon publishes

Checked on 2026-10-12 against `https://www.smogon.com/stats/2026-09/`.

- **A month's files appear on the 1st of the next month** and never change
  (2026-09's are dated 1 October).
- **Champions formats**, each at ratings 0, 1500, 1630 and 1760:

  | Format id | What | In 2026-09 |
  |---|---|---|
  | `gen9championsvgc2026reg<id>` | Doubles, best of 1 | M-B, M-C |
  | `gen9championsvgc2026reg<id>bo3` | Doubles, best of 3 | M-B, M-C |
  | `gen9championsbssreg<id>` | Singles (BSS), best of 1 | M-B, M-C |

  `gen9championsou` and `gen9championsuu` are Smogon's own six-on-six tiers,
  not the game's ranked formats, and aren't used.
- **`chaos/<format>-<rating>.json`** has everything per Pokémon: usage,
  abilities, items, moves, spreads, teammates. 0.2 to 7.3 MB a file; 48 MB
  for a month of the formats above.
- **`leads/<format>-<rating>.txt`** is a table of each Pokémon's share of
  all leads. Shares add to 100% in doubles too (two leads a team).
- **Sizes of the sample**, at 1760 in 2026-09: M-C doubles 1,631,943
  battles, M-C doubles best of 3 223,477, M-C singles 69,462.

**Findings:**

- **Spreads are stat points**, as the game has them: `Adamant:2/32/0/0/0/32`
  is the nature, then HP/Atk/Def/SpA/SpD/Spe. How much the top spreads say
  depends on the Pokémon: at 1760 in M-C doubles, Sneasler's top ten cover
  61% of its teams, and Rillaboom's cover 21% of 17,460 spreads. So the page
  shows natures added up across every spread next to the top spreads, and
  says how much the top spreads cover.
- **A Mega is its own entry.** A Pokémon holding its Mega Stone is counted
  as `Salamence-Mega`, apart from `Salamence`. The ladder views keep them
  apart (decided 2026-10-12): each has its own items, moves and spreads.
- **"Checks and Counters" is nearly empty** for Champions: 4 of 277
  Pokémon have any at 1760 in M-C doubles, none in singles. Not used.
- **Tera Types is always "nothing"** and Happiness carries no information.
  Not used.
- **Usage adds to 6**: it's the share of teams with the Pokémon on the team
  of six, not of teams that brought it to the battle.
- **The year is in the doubles format's id** (`vgc2026`), so the app and the
  server find formats by pattern and never build an id from a regulation.

## 3. The reduced record

One file's worth of stats, cut down to what the app shows: 0.4 to 1 MB of
JSON (M-C doubles at 1760 is 0.8 MB, 0.15 MB gzipped), in place of up to
7.3 MB. The server and the app each
make it from Smogon's files, and a golden file keeps them equal (§8).

```
LadderStats (reduction 1)
  format      "gen9championsvgc2026regmc"
  regulation  "M-C"            Limitless's id, as /v1/formats has it
  mode        "doubles" | "singles"
  bestOf      1 | 3
  month       "2026-09"
  rating      0 | 1500 | 1630 | 1760
  battles     1631943
  pokemon[]   most used first
    name       "Salamence-Mega"    Smogon's name; unique in the record
    key        "salamence"         the app's species key; null when nothing matched
    megaStone  "Salamencite"       null unless the entry is a Mega
    usage      0.415               0 to 1
    leadShare  0.0337              share of all leads; null when the leads file has no row
    abilities[], items[], moves[], natures[], spreads[], teammates[]
               each { value, share }, most common first
```

- **Shares** are a count over the Pokémon's own weight, which is the sum of
  its ability counts: the figure Smogon's moveset files print, and what
  `SmogonUsage.reduce` does today. Moves add to 4.
- **Names.** Items, abilities and moves are Smogon's ids (`choicescarf`),
  turned into the app's names (`Choice Scarf`) by the name standardizer each
  side already has. Only an exact match counts: an id is never misspelled,
  so one nothing matches stays as it is rather than becoming its nearest
  neighbor. Smogon's `nothing` is "No Item", and its empty move slot isn't
  a move. Teammates keep Smogon's names, which are mostly the record's own
  `name`s (Smogon leaves the least-used Pokémon out of a file).
- **Species.** `key` is read from Smogon's name the way Team Search reads
  it, with apostrophes dropped first (Smogon writes "Sirfetch'd", the
  regulation files "Sirfetchd"). A name with "Mega" in it is a Mega, and its
  `megaStone` is the commonest of its items that is one of its own species'
  stones. Two entries can share a `key` and have no stone ("Basculegion" and
  "Basculegion-F", "Rotom-Wash" and "Rotom-Heat"): the regulation files
  don't list those forms. `name` is what's unique. A Pokémon the
  regulation's vocabulary doesn't know keeps its entry, with a null `key`.
- **Natures** are the spreads' counts added up by nature, before spreads
  are cut.
- **Cuts:** abilities 6, items 12, moves 24, natures 6, spreads 10,
  teammates 24; entries under 0.5% dropped, except spreads and teammates.
  Pokémon with no usage or no weight are left out.
- **Same bits on both sides.** Sums are taken in the order of the keys,
  sorted as UTF-8 bytes; equal counts are ordered by key the same way;
  shares are rounded half to even at five places. So Java and Swift get
  identical numbers and the golden file can compare exactly. `usage` and
  `leadShare` are as Smogon publishes them.
- **`reduction`** counts the rule's versions. When the rule changes, the
  server fetches the months it holds again; Smogon keeps every month.

## 4. The backend

```
LadderDiscovery (every 12 h) ─→ SmogonClient: index, month listings, chaos + leads
                              ─→ LadderReducer ─→ ladder.stats (key format|month|rating; compacted, kept)
LadderStoreConsumer           ─→ Postgres ladder_stats
LadderService                 ─→ /v1/ladder
```

- **`SmogonClient`**: the index, a month's `chaos/` listing, a chaos file
  and a leads file. It waits 2 seconds between requests and names the
  project in its `User-Agent`. Smogon's `robots.txt` doesn't close `/stats/`.
- **`LadderDiscovery`** looks at the newest months (`SMOGON_LOOKBACK_MONTHS`,
  2 by default; longer once to backfill), picks the Champions doubles and
  singles formats by pattern, and fetches each format, month and rating not
  yet stored at the current reduction. A month is 24 files today, fetched
  once. Formats of a regulation the bundled data doesn't know are skipped
  and logged.
- **`LadderReducer`** reads a chaos file as a stream, one Pokémon at a
  time, so a 7 MB file doesn't need a 7 MB tree in a server with a 768 MB
  heap.
- **`ladder.stats`** holds the reduced records, not Smogon's files: the
  biggest file is over the topics' 5 MB limit, and Smogon keeps every month
  since 2014, so the raw files can always be fetched again. The table can
  be rebuilt from the topic.
- **`ladder_stats`** (Flyway V5): one row per format, month and rating,
  with the battles, the reduction, when it was fetched, the record as JSON
  text, and each Pokémon's usage by itself, so trends and the other
  ratings' usage are read without reading whole records. A record replaces
  the stored one unless that was made by a newer rule, or by the same rule
  from a newer fetch.
- **Settings** (`pkref.smogon`): `ingest-enabled`, `poll-interval`,
  `lookback-months`, `ratings`, `request-gap`.

### The API

| Endpoint | Returns |
|---|---|
| `GET /v1/ladder` | What's stored: each format's regulation, mode, best of, months, ratings and battles |
| `GET /v1/ladder/{format}?rating=&month=` | One reduced record. `rating` defaults to 1760 and `month` to the newest. 404 when it isn't stored |

The second adds what only the server can, since it holds the other files:

- **`trend`** for each Pokémon: its usage less last month's, same format
  and rating; null when last month isn't stored.
- **`usageByRating`** for each Pokémon: its usage at each stored rating of
  the same month.

Both endpoints are cached and signed as the rest of `/v1` is: 15 minutes,
weak ETags, gzipped, and behind the access token when keys are configured.
Swagger UI describes them.

## 5. The app

- **`MetaAPI`** gains the two answers' shapes and requests.
- **`SmogonLadder.reduce`** is the device's reducer: the same record from
  the same two files. It replaces `SmogonUsage.reduce`.
- **`LadderStore`** answers "the stats for this regulation, mode, best of
  and rating":
  1. the server, through `MetaInsights` and its cache, when the switch is on;
  2. otherwise, or when the server can't answer, Smogon's own files:
     the month is chosen from Smogon's listing (kept for 12 hours), the file
     downloaded once, reduced, and kept on disk. A published month never
     changes, so a reduced month never expires.
- **Opening a ladder view never starts a download from Smogon**, as
  opening Tournaments never downloads events. It shows what's on the device;
  when there's nothing, a card names the month and the file's size (the
  listing has it) with a Download button. Team Search downloads its one
  file by itself, as it does now, so 1760+ doubles is usually there already.
- **Team Search** reads its usage and teammates through `LadderStore` at
  1760+, doubles, best of 1, as now. It keeps its fallback to the newest
  month of an earlier regulation, with the label it has today. The old
  `SmogonUsage` cache is removed on first run.
- **Settings**' storage row counts and clears the ladder cache.
- **Without the server** there's no trend and usage only at the band
  shown, since each band is another download. The page says so.

## 6. Screens

### 6.1 The switch

A segmented control under the regulation in the header: **Tournaments ·
Doubles Ladder · Singles Ladder**, kept in `AppSettings.metaView`
(Tournaments at first, so nothing changes until it's touched). Tournaments
is today's tab, unchanged. The window picker (14 days, 30 days, regulation)
shows only there; the ladder shows its rating and best-of pickers instead.

### 6.2 Ladder home

```
┌ Meta ──────────────────────────────┐
│ Regulation M-C      Change in Set… │
│ [Tournaments|Doubles Ladder|Singles]│
│ [1760+ ▾]  [Best of 1 ▾]           │
│ 1,631,943 battles · September 2026 │
│ Smogon, through your server        │
│                                    │
│ Most used                        ⓘ │
│  Rillaboom is on 47% of teams of   │
│  players rated 1760+.              │
│  Rillaboom        47%  ▲ 2.1       │
│  Sneasler         37%              │
│  …                      See all ›  │
│ Common leads                     ⓘ │
│ Rising since August                │
│ More used at higher ratings        │
└────────────────────────────────────┘
```

- **Most used:** the top eight, each with its usage, its trend when the
  server has last month, and a link to its page. See all lists every
  Pokémon, searchable, as the Tournaments list is.
- **Common leads:** the eight biggest lead shares.
- **Rising since `<month>`** and **Falling:** the biggest changes in usage
  from last month. Only from the server, and only when last month is stored.
- **More used at higher ratings:** the biggest gaps between usage at 1760+
  and among all players, both ways ("Used less at higher ratings"). Only
  from the server.
- **Defaults:** 1760+ (the app's cutoff today) and Best of 1 (seven times
  the battles of Best of 3).
- **Nothing for the regulation yet** (the month after a regulation starts,
  Smogon has none): the tab says so, says which regulations have stats, and
  links to Settings, as Tournaments does. No other regulation's numbers are
  shown in its place.

### 6.3 A Pokémon's ladder page

- Its usage in a sentence, and a bar for each rating band (server).
- Items, abilities, moves, natures: share bars, as on the tournament page.
- **Spreads:** the top spreads as nature and stat points, each with its
  share, and a line saying how much of the Pokémon's teams they cover
  between them ("These ten cover 21% of its teams").
- **Leads:** its share of all leads, and how often a team with it leads
  with it: lead share × leads a team (1 in singles, 2 in doubles) ÷ usage.
- **Teammates**, each a link to its own page.
- **Most common choices:** the top item, ability, spread and four moves,
  with **Save Set** and **Calc Against This**. It says these are each the
  most common on their own, not one player's set: Smogon doesn't publish
  whole sets. The stat points are real, not predicted.
- A link to the same Pokémon's tournament page, and back, when both have it.

### 6.4 Info sheets

One ⓘ each, in `MetaDefinition`, with the words below.

- **Ladder usage:** the share of teams on Pokémon Showdown's ladder that
  month with the Pokémon on the team of six. Each team counts by how likely
  its player is rated at or above the band, which is Smogon's weighting;
  All players counts every team once. A Pokémon holding its Mega Stone
  counts as the Mega, apart from its plain form.
- **Rating band:** Smogon publishes four: every player, and players rated
  about 1500, 1630 and 1760 or higher. Higher bands rest on fewer battles.
- **Lead share:** its share of all the Pokémon sent out first. In doubles
  each team leads two, so a Pokémon led by one team in ten has 5%.
- **Trend:** usage this month less last month's, in percentage points.
- **Spread:** a nature and the stat points put into HP, Attack, Defense,
  Sp. Atk, Sp. Def and Speed.

### 6.5 Mon Index's card

"In the meta" gains a ladder line when the ladder has the Pokémon: "On 41%
of teams of players rated 1760+ on the doubles ladder (September 2026)."
From the server or what's on the device; the card never starts a download
from Smogon.

## 7. PRs, in order

| PR | What |
|---|---|
| 5a | This file, and the plan's updates |
| 5b | Backend: `SmogonClient`, `LadderDiscovery`, `LadderReducer`, `ladder.stats`, `ladder_stats`, `/v1/ladder`, the golden file, README |
| 5c | App data: the shapes, `SmogonLadder.reduce` against the golden file, `LadderStore`, Team Search reading through it, Settings' storage row |
| 5d | App screens: the switch, ladder home, the list, the Pokémon's ladder page, info sheets |
| 5e | Save Set and Calc Against This with real stat points; Mon Index's ladder line; HANDOFF and README brought up to date |

Each is checked on its own before it's opened, and merged before the next
is opened.

## 8. Checks

- **Fixtures.** A chaos file and a leads file cut down from Smogon's real
  2026-09 M-C doubles files at 1760 to 27 Pokémon, each with its 25 biggest
  spreads and 30 biggest teammates, every count kept being as published;
  saved once under `backend/src/test/resources/smogon/`. Tests never call
  Smogon.
- **The golden file.** `golden/ladder-fixture.json` is the reduced record
  for the fixture. The backend's reducer and the app's must both produce it
  exactly. It's first checked against the same reduction worked out
  independently in Python.
- **Backend.** The reducer on odd input (no leads row, an unknown Pokémon,
  zero weight, a missing section); discovery against a stubbed Smogon (what
  it fetches, what it skips, a second poll fetching nothing, a changed
  reduction fetching again); the pipeline on embedded Kafka; the store on
  H2 and on Postgres; the endpoints through the web layer, signed in and
  not; `mvn verify`.
- **Live, once, on an isolated stack** (`pkreftest`, never the owner's
  containers): the server fetching the real 2026-09 files, with the app on
  the simulator reading them, and the same numbers from the app's own
  download with the server off.
- **The app.** Swift tests with canned answers: the server's record, the
  device's, the server failing over to Smogon, an old server without
  `/v1/ladder` (404), nothing for the regulation. The full suite on the
  simulator; iOS and Mac builds with no warnings.
- **The screens.** Simulator runs and Mac snapshots of ladder home, the
  list and a page, in doubles and singles, at phone and iPad widths, with
  VoiceOver labels on the bars.

## 9. Risks

- **Smogon's files are a courtesy, not an API.** The listing is an HTML
  directory page; a change to it stops new months arriving and nothing
  else. Discovery logs what it couldn't read, and stored months keep being
  served. One server fetching once is lighter on Smogon than every device
  fetching for itself.
- **A month's delay.** September's ladder appears on 1 October. The header
  always names the month. Tournaments stay the fresher source.
- **A new regulation has no ladder for its first weeks**, and its first
  month can be a part month.
- **Showdown's ladder isn't the game's.** It's the best public stand-in;
  the info sheet says whose ladder it is.
- **Phone downloads without the server:** up to 7 MB for a band, once a
  month. The download card says how big it is, and nothing downloads until
  it's tapped (§5).

## 10. Decisions (2026-10-12)

1. **One switch:** Tournaments, Doubles Ladder, Singles Ladder.
2. **Megas have their own rows** on the ladder, as Smogon counts them.
3. **Without the server, the app downloads from Smogon** and works the
   ladder out itself.

Taken without asking, and easy to change: the defaults (1760+, Best of 1);
the ladder never showing another regulation's numbers in place of the
chosen one's; singles meaning BSS only.
