# PK Reference: handoff

State of `main` and of the `backend-integration` branch as of 2026-10-06,
how the codebase fits together for the next change, and what's worth doing
next. The [README](README.md) describes
the app itself; this file is for whoever works on it.

## Contents

1. [Recent work](#recent-work)
2. [Where things live](#where-things-live)
3. [Recipes](#recipes)
4. [Conventions](#conventions)
5. [Feature notes](#feature-notes)
6. [Building and testing](#building-and-testing)
7. [Known limitations](#known-limitations)
8. [What's next](#whats-next)
9. [Other documents](#other-documents)

---

## Recent work

From #57 to #101 (2026-09-30 to 2026-10-06), by area. Each PR's description
says what changed and what was checked. #93–#101 are on `backend-integration`,
not yet in `main`.

| PRs | Area |
|---|---|
| [#57](https://github.com/rra013/PKReference/pull/57)–[#59](https://github.com/rra013/PKReference/pull/59) | Siri, Spotlight and Shortcuts, Phase 2: Compare Speed, Check Legality, saved sets and teams (in Spotlight too), the system's in-app search, and search sentences read into a damage calc. See [Feature notes](#siri-spotlight-and-shortcuts). |
| [#60](https://github.com/rra013/PKReference/pull/60)–[#67](https://github.com/rra013/PKReference/pull/67), [#69](https://github.com/rra013/PKReference/pull/69) | The Problem Solver: the solver and its tab, field options, grouping by Pokémon, two hits, an ability filter, usage ranking, Siri's Find Counters, and Sturdy, Focus Sash and Disguise taking a hit in the calc. See [Feature notes](#problem-solver). |
| [#68](https://github.com/rra013/PKReference/pull/68), [#85](https://github.com/rra013/PKReference/pull/85) | Champions data: Dragoninite in every regulation; the 15 items M-B added, which M-B and M-C lacked; and the game's names for Golisopite and Baxcalibrite. Sets saved with the old names still load (`HeldItem.renamed`). |
| [#70](https://github.com/rra013/PKReference/pull/70)–[#83](https://github.com/rra013/PKReference/pull/83), [#87](https://github.com/rra013/PKReference/pull/87)–[#89](https://github.com/rra013/PKReference/pull/89) | RNG tools: FireRed/LeafGreen initial seeds and calibration from Ten Lines (#70–#72), a Mac crash opening Calibrate (#73), then the fixes from the 2026-10-03 audit (#74–#83, #87–#89), last of all wild areas from PokéFinder's tables, the Gen 4 tools' year, and Gen 5 profiles. See [Feature notes](#rng-tools). |
| [#91](https://github.com/rra013/PKReference/pull/91) | RNG tools: the Eggs tool's Gen 5 tab, with PokéFinder's egg generator and its searcher over dates with the DS's parameters. Every egg tab now shows only the parent fields its game reads, and picks the species by name. |
| [#92](https://github.com/rra013/PKReference/pull/92) | RNG tools: the Finder's BDSP Egg mode takes the egg's species, Ditto and genderless parents, the Destiny Knot and a hidden-ability filter, checks and orders the parents as PokéFinder's Eggs8 does, and applies the Oval Charm. |
| [#84](https://github.com/rra013/PKReference/pull/84), [#85](https://github.com/rra013/PKReference/pull/85) | An optional backend in `backend/`: Limitless tournaments through Kafka into usage counts served over REST, with hand-typed names standardized. |
| [#93](https://github.com/rra013/PKReference/pull/93)–[#101](https://github.com/rra013/PKReference/pull/101) | On `backend-integration`: the backend integration's plan and phases 0–3. The backend keeps every event's teams and matches, names species the app's way, and serves insights and Team Search's corpus at `/v1`; the app's Settings → PK Reference Server (Beta), off by default, reads Team Search's corpus from it. See [`BackendIntegration-PLAN.md`](BackendIntegration-PLAN.md) §2. Phase 4's PRs follow from #102; [`BackendIntegration-PHASE4.md`](BackendIntegration-PHASE4.md) §9 lists them. |

Before that, #23–#56 were the UI pass, game data into JSON, iPad fixes, the
Mac app, Siri Phase 1 and the rename to PK Reference.

Full suite on 2026-10-06, on `backend-integration` with Phase 4f: 1,323 tests,
all passing on the iPhone 17 Pro Max simulator. The iOS and Mac builds had no warnings.

---

## Where things live

**`PKReference/Theme.swift`**: every shared style. Use these rather than
hand-rolling colors, radii or paddings.

| Piece | What it's for |
|---|---|
| `TypePalette` | Type colors, the text color for each, and the tint and wash strengths. WCAG math lives here too. |
| `TypeBadge`, `typeBadgeBackground(_:)` | A type's capsule, in the viewer's badge style (filled or tinted). |
| `ColorRole` | Colors with one meaning: `ability`, `item`, `nature`, and `field` (the calc's weather, terrain and other field conditions), each with light and dark values. |
| `MatchupColors`, `MatchupSide` | The viewer's colors for Pokémon 1 and 2 in the calc (Teal & Pink, Blue & Gold, Blue & Red). Draw a side with `matchupColors.color(for:)`, reading `\.matchupColors`. |
| `card()`, `insetCard()`, `cardPage()`, `CardStack`, `SectionCard`, `CardMetrics`, `Density` | Card surfaces, their spacing, and Compact density. `types:` adds the type-colored wash. |
| `.buttonStyle(.primaryAction)` | A screen's main action. Add `.tint(.red)` for stop or cancel. |
| `scaledWidth`, `scaledFont`, `AdaptiveStack`, `FlowLayout`, `DynamicTypeSize.gridColumns(_:)` | Layouts that hold up at large text sizes. |
| `EnvironmentValues`: `typeBadgeStyle`, `matchupColors`, `density`, `typeBackgrounds` | Set once in `ContentView`, read by the views above. |

**`PKReference/AppSettings.swift`**: every app-wide setting's key and default.
Views use `@AppStorage(AppSettings.x)`. The RNG tools' `finder_*` keys are
form inputs and stay where they are.

**`PKReference/TabLayout.swift`**: the user's tab order and hidden tabs, and
`compactSplit`, which decides what goes in the iPhone tab bar and what goes
under More.

**`PKReference/MoreTab.swift`**: the iPhone More tab. `TabNavigationStack` is a
tab's navigation root that joins More's stack when opened from it.
`leaveWarning(_:)` is how a tab says closing it loses work.
`TabReselectGuard` stops a second tap on More from closing a tab silently.
It works by sitting in front of the UITabBarController's delegate, the only
code that changes how the tab bar behaves underneath SwiftUI, so check it
first if tab switching ever misbehaves.

**Game data in `PKReference/`**: facts that change with games and regulations
are JSON, each loaded strictly (a misspelled name fails the file) and
checked by a test that it loads:

| File | Holds | Loaded by |
|---|---|---|
| `champions-<id>.json` | a regulation's species, items, Mega stones and `rules` | `ChampionsRegulation`, `ChampionsValidator` |
| `mega_forms.json` | every Mega form; its stone becomes a held item | `MegaForms` |
| `battle_moves.json` | the Battle Sim's move effects, and setup moves | `BattleMoveEffects` |
| `type_chart.json` | the 18 types and their matchups | `TypeChart` |

The Showdown damage port has its own data (`showdown-champions-data.json`);
`TypeChartTests` checks the two type charts agree.

What stays in Swift, because it's behavior rather than data: items with
effects (`HeldItem.builtIns`, with `typeBoostingItemMap` and
`typeResistBerryMap`), the Battle Sim's dispatch lists for moves that need
their own code, and the damage engines.

**`backend/`**: an optional Java 21 / Spring Boot service with Kafka and
Postgres, separate from the app. It collects Limitless's events and serves
insights and Team Search's corpus at `/v1`. Running, testing and rebuilding it
are in [`backend/README.md`](backend/README.md); where it's going is in
[`BackendIntegration-PLAN.md`](BackendIntegration-PLAN.md). Its
`NameStandardizer` and `SpeciesVocabularies` read the repo-root
`champions-*.json` and `PKReference/`'s `team_search_vocab.json` and
`showdown-champions-data.json`, which Maven bundles, so a new regulation needs
nothing there; a change to how the app names species must keep
`SpeciesIdentityGoldenTests` passing on both sides.

**`PKReference/MetaServer.swift`**: the app's side of the server. Settings →
PK Reference Server (Beta) stores `metaServerEnabled` and `metaServerAddress`;
`PreferredCorpusFetcher`, `TeamCorpusStore`'s default source, reads them at
each call and asks the server, then Limitless whenever the server can't
answer. `MetaServerClient`'s session has no URL cache, so nothing it asks is
answered from an old copy. `MetaAPI.swift` decodes the `/v1` insights, and
`MetaCache.swift` keeps them on disk with the rule for when to ask again
(`MetaInsights.load`); tests read real answers saved in
`PKReferenceTests/MetaFixtures/`. Without the server, `MetaDeviceInsights.swift`
works the same insights out from Team Search's corpus, in the same shapes,
with `MetaNames.swift` (a port of the backend's `NameStandardizer`) for the
names. It counts as the backend's `MetaService` does, so a change to how
either side counts must keep `MetaDeviceInsightsTests` and the backend's
`MetaGoldenFileTest` passing against `golden/meta-fixture.json`.

**RNG tools** (`RNGToolsView.swift` and the files beside it): PokéFinder's
C++ core is called through `PFBridge.h`/`.mm`, with `PFBridgeSwift.swift` as
the Swift side. Fixes go in the bridge or the app, not in `PKReference/Core`,
whose changes `MODIFICATIONS.md` lists. [Feature notes](#rng-tools) lists
the patterns new RNG code follows: streaming searches, chunked generators,
the result limit, live number fields. FireRed and LeafGreen's
initial seeds, ported from [Ten Lines](https://github.com/Lincoln-LM/ten-lines)
(GPL-3.0, no "or later"), are `FRLGSeeds.swift` (the engine) and
`FRLGSeedsView.swift` (the screens), with the community's farmed lists
bundled as `PKReference/frlg-seeds-*.csv` and refreshed by
`tools/update_frlg_seeds.sh` (Update Seed Lists does it in the app). On
Switch the overworld advances twice a frame, so the Timer's target there is
the continue screen's frame.

---

## Recipes

**Adding a tab**
1. Add a case to `AppTab` (`ContentView.swift`) with a label and icon, and
   add it to `allUserTabs`. Existing users' saved order gains it at the end
   automatically.
2. Wrap its root view in `TabNavigationStack`, not `NavigationStack`, or it
   shows two back buttons under More.
3. If it holds work that closing it would lose, add
   `.leaveWarning(condition ? "What would be lost." : nil)` to its `body`.
4. Lay it out with `cardPage()`, `CardStack` and `SectionCard`, and use
   `.primaryAction` for its main button.
5. For a list beside the selected item's page in wide layouts, use
   `ListDetailSplit { list } detail: { page }` (`ContentView.swift`), not a
   `NavigationSplitView`. On iOS it is one; on the Mac, a split view inside
   the app's sidebar pushed its page right by the sidebar's width a second
   time, so there it's a resizable split in the tab's navigation stack.
6. In a form, give a text field a title and put its example in `prompt:`,
   with `.labelsHidden()` if a header or label already names it: a Mac form
   shows the title as a label beside the field. Segmented pickers get
   `.labelsHidden()` too; iOS never shows their label, and on the Mac it
   repeated the caption above them.
7. A sheet's content gets `.sheetSize()`: a Mac sheet is as big as its
   content asks, and a list asks for no height. Give it a Cancel or Done
   toolbar button (Mac sheets can't be swiped away), and don't put a button
   at `.principal`, which a Mac sheet doesn't show.
8. Rows that delete by swiping also get a Mac-only `.contextMenu` with the
   same Delete: swipes need a trackpad, and Mac lists have no edit mode.

**Adding a setting**
1. Add a `SettingKey` to `AppSettings`.
2. Add its name and default to `AppSettingsTests` (the names are pinned:
   renaming one resets that setting for everyone).
3. If it changes how many views draw, read it in `AppearanceSettings`
   (`ContentView.swift`) and pass it through `EnvironmentValues`, as
   `density` does. That modifier also dresses the Mac's Settings window.

**Adding a Champions regulation**: follow [`tools/README.md`](tools/README.md).
The bar is that a regulation is data: its two JSON files, a line per new
Mega in `mega_forms.json`, and its case in `ChampionsRegulation` and in
`RegulationChoice` (`IntentEntities.swift`, for Siri; `AppIntentsTests`
fails until it's there). No validator constants, Battle Sim tables or
gimmick gates change. The Problem Solver and Team Search build their lists
from the regulation's files.

**Adding a Battle Sim move effect**: add the move to the right table in
`PKReference/battle_moves.json` (its `notes` say what each holds), keyed by its
normalized name (`BattleSimSeed.normalize`: "Swords Dance" is
`swordsdance`). That's all when the effect is one the engine already has.
A move that needs new behavior needs code; the dispatch lists for those
(tier 3 and 5 status moves, fixed damage, damage modifiers) are in
`BattleMoveEffects`. `BattleMovesDataTests` fails on a misspelled kind,
stat or key.

**Adding a Mega Evolution**: add a line to `PKReference/mega_forms.json` (its
`about` field explains each key). Its stone becomes a held item from that
line; there's nothing to add in Swift. For a Champions regulation, the
stone also needs to be in that regulation's `mega_stones` and item list.

**Adding a held item** (not a Mega stone): items have effects, so this is
code. In `PokemonStatsModels.swift`, add a `static let` to `HeldItem` and
put it in `HeldItem.builtIns`, in picker order; then implement its effect
where the others are (`computeItemModifiers`, the Battle Sim). A 1.2×
type item or a resist berry only needs an entry in `typeBoostingItemMap`
or `typeResistBerryMap`. If the Champions calc doesn't model the item, add
it to `HeldItem.nonChampionsItems` too: Champions-mode pickers then leave it
out, and a set already holding it shows it marked "not in Champions".

**Adding a color with meaning**: add a case to `ColorRole` with light and
dark values. `ColorRoleTests` fails until both clear 4.5:1 contrast, and
until the new role is at least 12 apart from every other role and 8 from
every matchup side (distance in OKLab ×100).

**Adding a matchup pair**: add a case to `MatchupColors` with a label and
both sides' light and dark values. `ColorRoleTests` holds each pair to the
same contrast rules, and checks its sides stay apart from each other and
from the ability and item colors.

**Adding a note or build input inside `PKReference/`**: the folder is synced, so
Xcode copies every file in it into the app. Add a file the app doesn't
read to the "Exceptions for PKReference folder" list in the target's file
membership (Xcode's File inspector, or `membershipExceptions` in
`project.pbxproj`), as the developer notes and PokéFinder's generator
inputs are. The list takes files, not folders: a folder path is ignored.
Or keep notes at the repository root.

PokéFinder's `Core/Resources/embed.py` compiles its `i18n/*.txt` and
`Personal/*.bin` into `i18n.hpp` and `Personal.hpp`, which the app builds
from. Those inputs, the scripts and `Core/External/CMakeLists.txt` are
excluded; a new file in those folders needs adding to the list too.

---

## Conventions

**`nonisolated` for pure types.** The module builds with main-actor default
isolation, so every unannotated type, value types included, is
main-actor-bound. Anything that runs off the main thread (the damage port,
calc snapshots, the EV and two-hit solvers, the paste parser, Team Search's
engine and stores) is explicitly `nonisolated`. It's load-bearing, not
style. Three things learned applying it:
- It only widens; it can't break an existing main-actor caller.
- A protocol's default implementation in an unannotated extension stays
  main-actor-isolated and drags the conformance with it. If you see
  "conformance … crosses into main actor-isolated code", look for a default
  implementation, not the conforming type.
- Expect cascades: annotate, check diagnostics, repeat.

**Champions rules come from the regulation JSON.** Stat-point caps, the IV
lock, team size, clauses and which gimmicks are allowed live in each
`champions-<id>.json`'s `rules` block. Read them with
`ChampionsRegulation.current.rules()`, or `championsMaxEVPerStat`,
`championsMaxTotalEVs` and `championsLockedIV`; don't type 66, 32 or 31.
The one fixed number is `championsStatPointsPer252EVs`, the exchange rate
between EVs and stat points, which is a game mechanic.

**Calc snapshots.** `CalcSnapshot` holds raw inputs (base stats, EVs, IVs,
nature, stages), not finished stats, because the solvers vary an EV and
recompute. `CalcOutcome.rolls` is optional (only the Showdown port has real
rolls), damage is `Double` as both engines compute it, and `snapshot()`
returns nil with no species rather than solving against a phantom 1/1/1
statline. Imported sets with no nature default to Serious.

**Deterministic battle tests.** Set `BattleEngine.rollOverride` to
`.init(crit: false, roll: .max)` before `executeTurn()` in any test that
compares damage across runs. Don't loosen thresholds instead: at low power
the damage bands are close enough that a loose threshold stops the test
catching the mechanic failing. It covers crits and damage rolls only; a test
that depends on another random draw (paralysis, sleep length, speed ties…)
needs its own guard.

**Parity suites.** The nine `BattleTier` files, `DamageCalcMegaEvolutionTests`,
`AbilityTests`, `BattleItemsTests`, `TypeChartTests`, "Known Damage Ranges"
and "Damage Engine" encode damage numbers that can't be re-derived. If a calc
change keeps them passing, it's faithful.

**UI changes are checked on the simulator**, in light and dark mode and, for
layout changes, at an accessibility text size. Each PR lists what was and
wasn't checked.

---

## Feature notes

How three finished pieces of work were designed, and the owner's decisions
that still hold for changes to them. Their plans were removed on 2026-10-05
and 2026-10-06; git history has them.

### Siri, Spotlight and Shortcuts

App Intents, on iPhone, iPad and the Mac: `AppIntents.swift`,
`SavedIntents.swift`, `IntentEntities.swift`, `IntentAnswers.swift` (the
wording, as plain functions the tests call) and `IntentSnippets.swift`.
`AppNavigator` opens the app on a page. None of Apple's assistant schemas
fit a Pokémon reference, so they're plain App Intents.

- **Ten App Shortcuts, the most an app can have:** Look Up Pokémon,
  Calculate Damage, Search Teams, Compare Speed, Check Legality, Find
  Counters (the Problem Solver's), Show Saved Set, Show Saved Team, Load Set
  into Damage Calc, and the system's in-app search (`.system.search`, which
  the new Siri looks for). A new action has to replace one.
- **Saved sets and teams are in Spotlight** (`IndexedEntity`), refreshed at
  launch and a second after a save (`IntentIndex`).
- **The owner's decisions (2026-09-30):**
  - Every action answers in place, with an "Open in PK Reference" button.
    Load Set into Damage Calc is the exception: opening the calc is what
    it's for, and it keeps the calc's defender, as the Load button does.
  - Calculate Damage and Compare Speed assume nothing. Each side's stats are
    a required choice, which Siri asks for: a saved set of that Pokémon, no
    investment, full investment, or full investment and a boosting nature
    (Jolly for Speed). Each choice says exactly what it means, and takes the
    words players use ("max def", "uninvested") as synonyms.
  - A phrase holds one parameter, so Compare Speed's phrases name the first
    Pokémon and Siri asks for the second.
  - Check Legality's regulation is optional (the one in Settings, always
    named in the answer), and legality comes from the regulation's files:
    species, Megas and forms.
  - Show Saved Team checks a Champions team with the Battle Sim's check and
    says the first problem.
  - Phrases follow how the owner asks ("how much will \(attacker) do").
  - With no Pokédex data yet, an action says to open the app once.
- **Checking it:** `AppIntentsTests` covers the answers, entity queries
  and each `perform()`. The build writes the intents and phrases to
  `Metadata.appintents` in the app, which shows what the system will offer.
  On the Mac, `-debugSnippets YES` renders the snippets and `-debugNavigate`
  makes an Open button's request. The simulator runs Shortcuts but not
  Apple Intelligence, so Siri itself needs the owner's devices.

### Problem Solver

`ProblemSolver.swift` (the search), `TwoHitSolver.swift` and
`ProblemSolverView.swift` (the tab, in More on the iPhone and the bar on
iPad and the Mac), with `ProblemSolverTests`.

- **Brute force through the calc.** The owner's first idea, Pokémon with a
  super-effective STAB move at full investment, misses real answers: a
  neutral move with Adaptability or Huge Power, a Mega, the target's own
  ability, a strongest move that's a trap (Explosion, Hyper Beam). So every
  legal Pokémon, form and Mega, with each ability and damaging move, goes
  through `CalcEngine.evaluate`, the calc screen's own door, and `EVSolver`
  scales each answer down to the fewest points. The idea survives as the
  search's order. All of M-C, 25,922 candidates, solves in about 2 s in a
  debug build, so the planned pruning bound wasn't built.
- **The owner's decisions (2026-09-30):**
  - Champions doubles rules: level 50, the regulation's caps, spread moves
    at 0.75× as if both foes are in.
  - Guaranteed only: the lowest roll, no crit, must KO.
  - The target's Intimidate applies to physical answers, with a switch.
  - Items: the move type's 1.2× booster, or a Mega's stone. Choice Scarf is
    a second pass for answers that can't otherwise move first.
  - An attacking nature and a Speed nature are both tried; the one needing
    fewer points wins.
  - Two hits: a fast check over the whole roster, then, when something
    acts between the hits (a Sitrus Berry, Leftovers, Multiscale), each
    answer played out in the battle simulator.
  - Usage is a sort option ("Most used"), from Team Search's Limitless
    teams.
  - Find Counters asks for the target's investment each time.
  - One PR per feature.
- **What building it showed:**
  - Negative priority (Focus Punch) moves last, whatever the Speeds.
  - Intimidate cuts both ways: Defiant and Competitive answers get stronger
    (`ProblemSolver.intimidated(ability:)`).
  - Sturdy, Focus Sash and Disguise take a hit (`CalcEngine.oneHitSurvival`),
    so against them only multi-hit moves or Mold Breaker count in one hit.
  - The simulator re-check runs on the main actor (the simulator's damage
    goes through `DamageCalcVM`), so it works in 25 ms slices.
  - The set to beat is the calc's `SideCard` without moves, so it loads,
    pastes and saves as a calc side does.
- **Checking it:** `-debugNavigate problem:Incineroar,intimidate,bulky`
  opens the tab on a set.

### RNG tools

The 2026-10-03 audit checked the RNG tools against independent maths,
round-tripped every Searcher through its Generator, diffed the encounter
data against PokéFinder's tables, and walked every tool on the iPhone and
the Mac. PokéFinder's maths held wherever it was checked; almost every
problem was in the app's glue: the bridge's filters, the values it passed,
and the data and screens around it. Fourteen PRs (#74–#83, #87–#89) fixed
its 45 findings and 13 found since. Each PR's description says which, and
what was checked.

- **Rules that still hold:**
  - Don't edit PokéFinder's code (`PKReference/Core`): fixes go in the
    bridge (`PFBridge.mm`/`.h`, `PFBridgeSwift.swift`) or the app.
  - Offer what PokéFinder's screens offer for each game. Its generators read
    only their own leads, methods, modes and encounter settings, and
    ignore or misread any other: Gen 4 wild has Method J or K by game, Gen 5
    one method, Sword and Shield only raids.
- **Patterns new RNG code follows:**
  - A long search gets a streaming handle, as `pf_staticSearch3_start` and
    the rest have: the bridge sets the progress total before it starts and
    a `done` flag when its thread returns, and Swift frees the handle off
    the main actor.
  - A generator runs through `generateInChunks`, 10,000 advances at a time,
    and every search and generate stops at `searchResultLimit` (100,000)
    and says so.
  - A number field is a `LiveIntField` (or `RNGIntField`, `RNGOptIntField`,
    `IVField`) with an `RNGFieldRange` or `.clamping`; hex values, such as
    Gen 5's parameters, use `HexField`.
  - Leads are `PFLead`; Shiny Only is `pfShinyFilter` (star or square).
  - Encounters are references into PokéFinder's tables: statics by type and
    index (`StaticEncounterData`), wild areas by location ID with the
    settings that change their slots (`WildAreaData`).
  - Results clear when what they were found for changes, and a run that
    finds nothing says why (`noResultsText`).
  - Breeding parents are `EggParent`s on `EggParentCard`s, which show only
    what the game's egg generator reads (`EggParentFields`), and the species
    is an `EggSpeciesPicker`, kept to the species PokéFinder's tables hold.
    Gen 5 and BDSP parents go to PokéFinder in the game's order, the female
    or else Ditto second, as its `reorderParents` swaps them (`EggDaycare`,
    which `Gen5Daycare` and `BDSPDaycare` share); results still name the
    parents as entered.
  - Handoffs to the Timer go through `FinderTimerBridge` to
    `RNGTimerEngine.shared`: Gen 3 targets with `Gen3TargetStart`, Gen 4
    with the whole clock time and year that Check Your Seed reads, Gen 5
    with the second to press Continue.
- **The owner's decisions (2026-10-03 and 04):**
  - FireRed and LeafGreen's Mew is the one app-only static, generated from
    Emerald's Mew template.
  - Shiny Only means star or square.
  - Gen 3 static offers Methods 1 and 4, which PokéFinder has in both
    modes.
  - The Eggs tool and TID/SID have no Gen 8 tab: the Finder's Egg and
    TID/SID modes are BDSP's.
  - Gen 5 parameters come from the calibrator, with no table of per-console
    values unless one with a source turns up.
  - IV Calc offers each game's PokéFinder checker and base stats, or
    today's stats with EVs.
- **Checking it:** the audit's probes became unit tests (`RNGToolsTests`).
  Recorded simulator runs and Mac snapshots (`-debugOpenSheet finder`,
  `routes`, `frlgCalibration`, `gameCubeSearch`, `eggs5`) checked the
  screens.

---

## Building and testing

```bash
xcodebuild test -project PKReference.xcodeproj -scheme PKReference \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -parallel-testing-enabled NO
```

- **Keep `-parallel-testing-enabled NO`.** The default clones the simulator,
  and a clone left by an interrupted run makes the next launch fail
  ("Application failed preflight checks"). With more than one simulator of
  that name, pass `id=<udid>` instead.
- `xcodebuild` sometimes hangs after the tests finish. Once the
  `Test run with N tests` line appears, it's safe to stop it.
- `-test-iterations` doesn't repeat Swift Testing tests; loop
  `test-without-building` instead.
- The device's text size and appearance can be switched from the command
  line for checks: `xcrun simctl ui <udid> content_size accessibility-large`
  and `xcrun simctl ui <udid> appearance dark`.

The backend's tests (`mvn verify` in `backend/`) run on GitHub Actions for
changes to the backend and the data files it reads
(`.github/workflows/backend.yml`). The app's tests need the simulator, so
they have no CI.

The Mac app builds from the same target.
It only builds from a checkout as deep as the owner's
(`/Users/rra/Documents/YukiSoft/PKDex`): the project finds Homebrew's
`libzstd` by a path relative to the project folder
(`../../../../../opt/homebrew/…`).
This signs it to run on this Mac only:

```bash
xcodebuild build -project PKReference.xcodeproj -scheme PKReference -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

- **Wrap iOS-only APIs in `#if os(iOS)`**, or the Mac build fails:
  `navigationBarTitleDisplayMode`, `keyboardType`,
  `textInputAutocapitalization`, `UIApplication`, `UIPasteboard`,
  `EditMode`/`EditButton`, and the `.topBarLeading`/`.topBarTrailing`
  placements. The compiler reports only the first in each modifier chain, so
  after fixing one, search the file for the rest.
- **Mac builds use no entitlements file** (`CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`
  is empty): the iOS file's increased-memory-limit entitlement doesn't exist
  on macOS. The sandbox, outgoing-network and user-selected-file
  entitlements come from the build settings.
- The iOS background colors the views name (`systemGroupedBackground` and
  three others) are defined for `NSColor` in `Theme.swift`, with iOS's
  values.
- **Checking Mac screens: use the app's own snapshots, not screen capture**
  (the owner prefers no screen access). Debug Mac builds draw their windows
  into pictures themselves (`DebugSnapshot.swift`). Run the app's binary
  with launch arguments; settings passed the same way apply to that run only:

  ```bash
  "<path>/PK Reference.app/Contents/MacOS/PK Reference" -debugSnapshot calc -debugSnapshotQuit YES \
    -debugSnapshotStdout YES -defaultTab damageCalc -appAppearance light \
    -debugWindowSize 1280x820 > run.log
  ```

  Each open window's picture is printed as a `[DebugSnapshot png <name>]
  <base64>` line; decode those from the log. Don't read the pictures from
  the app's container: macOS asks permission before another app reads it,
  and the prompt stalls a script. To reach a screen:
  - `-debugOpenFirst YES`: the first item in Mon Index, Sets, Teams or Team
    Search.
  - `-debugOpenSheet <name>`: `save`, `paste` or `load` (the calc), `newSet`
    (Sets). A presenter adds a name with `DebugSnapshot.openSheet`.
    `frlgCalibration`, with `-defaultTab rngTools -finder_generation "Gen 3"
    -finder_mode Searcher -finder_game FireRed -finder_encounterMode Static
    -finder_encounterCategory Gifts -frlg_version fr_nx`, goes from the
    Finder to an Eevee target and its first seed's Calibrate.
  - `-debugOpenSheet metaEvents` (Events, from the Meta tab) and
    `metaEventFilters` (its filter sheet), with `-defaultTab meta`. Events
    loads from Limitless, so give it `-debugSnapshotDelay 8`.
    `metaPokemon` opens the most-used Pokémon's page, `metaArchetype` the
    first team to beat's page and `metaInfo` the usage info sheet; with the server on, give them `-debugSnapshotDelay 8` too.
  - `-debugOpenSettings YES`: the Settings window, as `<name>-Settings`.
  - `-debugMenus YES` prints the menu bar with shortcuts, as `[menu]` lines.

  Glass comes out blank (the app's sidebar, search fields), as do web
  views. For a screen reached by hand, Debug › Save Window Snapshot (⇧⌘S)
  saves the window into the container and plays a sound; ask the owner to
  share it.
- **A page that pushes another mustn't read `@Environment(\.dismiss)`.**
  On the Mac, once a screen was pushed on top of the Finder's target page,
  the dismiss action changed on every update, so the page redrew until
  AppKit threw "more Update Constraints in Window passes than there are
  views" and the app crashed. The page now takes a `close` closure from
  the Finder instead. If a Mac window hangs or throws that, sample the
  process (`sample <pid> 3`) and add `let _ = Self._printChanges()` to the
  bodies in the loop: it names what keeps changing.
- **If every Mac window opens blank**, a layout blew up once and the window
  saved it as its sidebar's divider position (widths in the billions under
  `NSSplitView Subview Frames` in the app's preferences). Delete those
  entries with `defaults delete` on the container's preferences file.
  Opening an already-running app doesn't reload it: quit it first to try a
  new build.

---

## Known limitations

From the recent PRs, each also noted in its description:

- **Launching into a tab with a search field under More.** When a tab with a
  search field (Mon Index, Move Index, Ability Index, Speed Tiers,
  Team Search) is under More *and* set as Open To, its large
  title appears only after the first scroll at launch (iOS 26.4). Tapping
  into it is fine; four workarounds didn't help. (#32)
- **Mon Index haptic under More.** The selection tick when opening a Pokémon
  is skipped while Mon Index is under More, because More's stack has no path
  of Mon Index's to watch. (#32)
- **The iPad tab bar pages.** A wide iPad window's tab bar can't show all
  twelve tabs, so it scrolls, and the open tab can scroll out of view. The
  sidebar-adaptable tab style fixes that, but on iPadOS 26.4 a split-view tab
  (Sets, Teams, Team Search) first opened from its sidebar lays out under the
  floating tab bar, which covers the tab's own buttons, so it was reverted.
  (#37)
- **Resizing an iPad window across the compact width** reopens the tabs
  after the fourth in their new place (the tab bar or the app's More list),
  so work in them is lost. (#37)
- **Not checked on screen:**
  - iPad in landscape: the simulator panel can't rotate a device
  - the leave prompt for the RNG searches (the timer's was checked in #37)
  - type-colored backgrounds on the compare page, and with large text or
    Compact density (#31)
- **Battle log at accessibility sizes.** It stays at a fixed 220pt, which is
  about three lines at the largest size. Usable, but it could shrink there.
  (#29)

---

## What's next

Roughly in order of value for effort. Only open work is listed; what's done
is in [Recent work](#recent-work) and the README.

1. **RNG tools: what the fixes left out.** See [Feature notes](#rng-tools).
   - Gen 5 needle calibration. PokéFinder's calibrator also works from the
     Unova Link's needle (`ProfileNeedleSearcher5`); the app's has IVs and
     a seed.
   - The Gen 5 Timer's C-Gear and Entralink modes aren't set from a result:
     PokéFinder's Gen 5 results carry no delay.
   - Honey trees, Headbutt and the Bug-Catching Contest. PokéFinder's Gen 4
     wild screens search them (honey trees and the Poké Radar by one slot);
     the Finder doesn't offer them, though the Routes browser lists
     Headbutt.
2. **The items M-B added that sets can't hold.** #85 made M-B's 15 items
   legal, but 11 have no `HeldItem`: Wide Lens, Muscle Band, Wise Glasses,
   Zoom Lens, Iron Ball, Shed Shell, Big Root and the four weather rocks.
   Pickers don't offer them, and the calc treats a set holding one as
   holding nothing. The Showdown port already models Muscle Band, Wise
   Glasses and Iron Ball (`ShowdownChampions.swift`,
   `ShowdownMechanics.swift`), so adding those to `HeldItem.builtIns` (the
   "Adding a held item" recipe) makes them work in the calc and the Problem
   Solver. The rest only matter in the Battle Sim, where each needs code.
3. **Siri, Spotlight and Shortcuts.** See [Feature notes](#siri-spotlight-and-shortcuts).
   - Left of Phase 3: try the phrases with the conversational Siri on the
     owner's devices, and tune the descriptions to what it picks.
   - Spotlight on the Mac closed after Calculate Damage (2026-09-30). The
     calc ran and answered, then the Shortcuts runner logged "No LSRecord
     for yukisoft.PKReference". Suspected: the Xcode build runs from
     `~/Library`, which the runner's sandbox can't read. To check, try a
     build in Applications.
   - On the owner's Mac (2026-09-30), Spotlight refused every third-party
     app's items, this app's sets and teams included ("Failed to request
     donation": the connection to `com.apple.SetStoreUpdateService` is
     invalidated; Chrome and Claude failed the same way). That's macOS: on
     the simulator they're indexed and open from Spotlight. Recheck after a
     macOS update.
   - **Known system bug, not the app's:** in the iOS Shortcuts app, PK
     Reference's suggested tile can be titled with one Pokémon ("Hydrapple",
     the last suggested) and run with another (Venusaur, the first). The
     system's stored App Shortcut phrases (Biome's `App.Shortcut.Phrase`
     set) share one reference per phrase template and don't record which
     Pokémon each names, so the tile passes id 3. Siri resolves the same
     phrases correctly (checked by the owner on the Mac, 2026-09-30). A
     no-default options provider and `parameterPresentation` didn't change
     the tile. Worth a Feedback report to Apple; don't chase it in the app.
4. **Mac app releases outside the App Store.** The Mac app is a destination
   of `main` since 2026-09-30. Left: Developer ID signing, the hardened
   runtime, notarization, and releases on GitHub with the tagged source for
   the GPL; optionally Sparkle for updates. It needs the owner's Apple
   developer account. Left out on purpose: a menu command for paste import,
   since the calc has two sides to paste into.
5. **Team Search open risks.**
   - Limitless rate-limits hard (its limit and the app's HTTP 429s are in
     the backend plan's §2 and §3), so tests don't crawl it. Its terms for a
     public service are still to be asked (the plan's Phase 7).
   - Early in a regulation there's little data. An "include last
     regulation's teams" option (keeping only teams legal now) was planned
     but not built.
   - Names Limitless writes that the alias table doesn't know still search,
     but saving a team reports them; a log of them would show the gaps.
6. **The backend integration**, on `backend-integration` (PRs go there,
   not to `main`). Phases 0–3 are done. Phase 4, the Meta tab in place of
   Tournaments, is under way: its PRs and what's left are in
   [`BackendIntegration-PHASE4.md`](BackendIntegration-PHASE4.md) §9. Phases
   5–7 (ladder and singles, the planning flows, launch) are in
   [`BackendIntegration-PLAN.md`](BackendIntegration-PLAN.md). The server
   runs on the owner's machine in Docker; leave their containers, topics and
   consumer groups alone, and check changes on a separate stack.
7. **FireRed and LeafGreen's open items.** Wild calibration (Ten Lines'
   `check_seeds_wild`); Teachy TV on Switch, which Ten Lines hasn't worked
   out either; and the Switch lists' settings nobody has farmed yet (Ten
   Lines leaves those columns out, and so does the app). The Mew event uses
   Emerald's Mew template since #76, so it can be searched and calibrated.
8. **Gen 9 in the Showdown port.** Only Champions is ported; other
   generations use the legacy engine, and `calculateShowdown` stops with a
   clear error for them. See [`PKReference/ShowdownPort-NOTES.md`](PKReference/ShowdownPort-NOTES.md).
9. **Game data that waits on features.** Moving game data into JSON
   finished on 2026-09-28. What's left needs the feature first:
   - Terastallizing. Sets and teams store a Tera type, but nothing uses it.
     The Showdown port supports `teraType`, so the calc's Champions path
     could pass it, with a "Terastallized" toggle, once a regulation allows
     Tera. The legacy engine and Battle Sim have no Tera.
   - The validator's `teraNotAllowed`, unused: flagging it now would warn
     on every Gen 9 paste imported into Champions and block those teams in
     the Battle Sim, for a type nothing uses.
   - Dynamax level and a Z-Move slot: add them with the feature that uses
     them.
10. **App Store.** Blocked on the GPL until PokéFinder's authors give
    permission, or the RNG core is rewritten per
    [`RNGRewrite-PLAN.md`](RNGRewrite-PLAN.md) (on hold).

---

## Other documents

| File | What it covers |
|---|---|
| [`README.md`](README.md) | The app: features, architecture, building, data sources, license |
| [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | Bundled third-party code and its licenses |
| [`PKReference/Core/MODIFICATIONS.md`](PKReference/Core/MODIFICATIONS.md) | Changes made to PokéFinder's code (required by its GPL) |
| [`PKReference/ShowdownPort-NOTES.md`](PKReference/ShowdownPort-NOTES.md) | Scope and wiring of the `@smogon/calc` port |
| [`PKReference/AbilityReference.md`](PKReference/AbilityReference.md) | Which abilities the legacy damage engine models (matchups the port can't take) |
| [`RNGRewrite-PLAN.md`](RNGRewrite-PLAN.md) | Plan for an independent RNG core (on hold) |
| [`BackendIntegration-PLAN.md`](BackendIntegration-PLAN.md) | The backend integration's roadmap: what's done, data sources, design, metric definitions, UI, remaining phases and the owner's decisions |
| [`BackendIntegration-PHASE4.md`](BackendIntegration-PHASE4.md) | Phase 4 in detail: the Meta tab, the app's `/v1` client and cache, and its PRs |
| [`tools/README.md`](tools/README.md) | Adding a Champions regulation, and the scripts that regenerate the bundled data |
| [`backend/README.md`](backend/README.md) | Running, testing, backfilling and rebuilding the optional backend, and its API |

Removed on 2026-10-06, in git history: `RNGFixes-PLAN.md` (every PR built;
its rules, patterns and the owner's decisions are in
[Feature notes](#rng-tools), what it left out is item 1 above, and its
findings, numbered 1–58, are in its history and each PR's description).

Removed on 2026-10-05, all in git history: `AppIntents-PLAN.md` and
`ProblemSolver-PLAN.md` (finished; their decisions are in
[Feature notes](#feature-notes)), `PKReference/CompartmentalizationPlan.md`
(finished; what's left is item 9 above, and its bar for a new regulation is
in [Recipes](#recipes)) and `DocsCleanup-HANDOFF.md` (this cleanup's
handoff).

Removed on 2026-09-27: `CalcCore-HANDOFF.md` (the EV
solver work, finished; its conventions are above; it was also being copied
into the app),
`TeamSearch-PLAN.md` (finished; its open risks are above) and
`PKDex/ProjectDocumentation.md` (an April file-by-file reference, replaced by
the README's architecture section).
