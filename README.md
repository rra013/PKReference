# PK Reference

**PK Reference** is a SwiftUI + SwiftData app for competitive Pokémon players,
on iPhone, iPad and the Mac.
It is built mainly around **Pokémon Champions**, and it also covers the whole
National Pokédex and the classic RNG-manipulation games. Everything lives in
one app:

- a Pokédex, a move index and an ability index
- a damage calculator ported line by line from Smogon's `@smogon/calc`, with an EV solver
- set and team builders with Showdown paste import and export
- a speed tier checker
- a problem solver: pick a set that's giving you trouble and see every Pokémon, move and investment that knocks it out in one hit
- a singles and doubles battle simulator with an on-device AI opponent
- a full suite of Gen 3–5 RNG tools, ported from PokéFinder and EonTimer
- tournament results and team sheets from Limitless

The app is **PK Reference** (`PK Reference.app`, bundle ID
`yukisoft.PKReference`). The Xcode project, its targets and the Swift module
are named `PKReference`; until 2026-09-29 they were `PKDex`, the name older
commits use.

> PK Reference is an unofficial, fan-made tool. It is not affiliated with,
> endorsed by, or associated with Nintendo, The Pokémon Company, Creatures Inc.,
> or GAME FREAK. Pokémon and all related names are trademarks of their
> respective owners.

---

## Contents

1. [Features at a glance](#features-at-a-glance)
2. [The tabs in detail](#the-tabs-in-detail)
3. [Pokémon Champions support](#pokémon-champions-support)
4. [Siri, Spotlight and Shortcuts](#siri-spotlight-and-shortcuts)
5. [On-device machine learning](#on-device-machine-learning)
6. [Architecture](#architecture)
7. [Building, running and testing](#building-running-and-testing)
8. [Repository layout](#repository-layout)
9. [Data sources and credits](#data-sources-and-credits)
10. [License](#license)

---

## Features at a glance

| Tab | What it does |
|---|---|
| **Mon Index** | National Pokédex filtered by generation or by the current Champions roster. Champions entries open a structured page with stats, abilities, type chart, movepool, Mega and alternate forms, and comparison. |
| **Move Index** | Every move with its type, category and power. Tapping a move opens its Serebii Attackdex page. |
| **Ability Index** | Every ability. Tapping one opens its Serebii Abilitydex page. |
| **Damage Calc** | Two-sided calculator using a Swift port of Smogon's calc for Champions, with a legacy engine as fallback. Includes field conditions, Mega Evolution, Showdown paste import and export, saved spreads, and an **EV solver**. |
| **Sets** | Library of saved spreads, with a set editor and an on-device **set predictor**. |
| **Teams** | Six-slot teams built from saved sets, with type-coverage analysis and whole-team Showdown paste import. |
| **Speed Tiers** | Your Pokémon's final Speed, after every modifier, ranked against the roster. |
| **Problem Solver** | Pick the set you need to beat and see every Champions Pokémon, move and investment that knocks it out in one hit (or two), guaranteed, in doubles, grouped by whether it moves first. |
| **Battle Sim** | Singles and doubles battle engine using your saved teams, with Mega Evolution and an on-device AI that can play either side. |
| **RNG Tools** | Timer, seed finder, wild and static encounters, eggs, TID/SID, GameCube (Colosseum/XD), IV calculator, IV→PID and Hidden Power, for Gen 3–5, plus Sword/Shield raid dens. |
| **Tournaments** | Tournaments, standings and team sheets from Limitless, with one-tap import of any team. |
| **Team Search** | Describe a team idea in plain words and see the popular tournament teams that match it, grouped into compositions. |
| **Settings** | Appearance, accent color, type badge style, density, type-colored backgrounds, tab order and visibility, default tab and generation, active Champions regulation, data management, and acknowledgements and licenses. |

Every tab except Settings can be reordered, hidden or made the default tab. On iPad and
wide iPhone layouts, the list-based tabs switch to a split view with the list
and the detail side by side. On the Mac, the tabs are in a sidebar (⌘1–⌘9
switch between the first nine), the list-based tabs show the list beside the
detail, and Settings is its own window (⌘,).

---

## The tabs in detail

### Mon Index

- **Generation filter:** All, Gen I–IX, or **Champions**. Each generation's
  list comes from the National Pokédex and PokeAPI's regional dexes, and each
  entry links to the matching Serebii page, shown in an in-app web view.
- **Champions filters:** narrow the Champions roster by type, ability or move.
  The pickers are built from the active regulation's learnset data, so they
  always match the current format.
- **Champions detail page** (`ChampionsPokemonDetailView`): parsed data
  rather than a web page. It has:
  - base stats, abilities and a defensive type chart
  - a searchable movepool
  - a form picker for base, Mega and alternate forms
  - "Compare With…", for comparing two Pokémon side by side
  - a pinned **Build a Set** button that opens the Set Builder

### Move Index and Ability Index

Searchable lists of every move and ability, synced from PokeAPI. Move rows
show type, category and power. Tapping an entry opens its Serebii page in an
in-app web view: the Attackdex for the selected generation (including the
Champions Attackdex) or the Abilitydex.

### Damage Calc

The calculator has two symmetric sides, so either one can attack. You can set
each side's:

- **Pokémon:** species, level and nature, plus ability and held item.
- **Investment:** EVs and IVs. In **Champions mode**, EVs become stat points
  (0–32 per stat, 66 total) and IVs are fixed at 31.
- **State:** stat stages, current HP %, status, and Mega Evolution.
- **Moves:** four move slots, optionally limited to the Pokémon's legal moves.

Field and side conditions include weather, terrain, Reflect, Light Screen,
Aurora Veil, Helping Hand, Friend Guard, Protect, Tailwind, Stealth Rock,
critical hits, spread damage and a free-form multiplier.

**Engines.** There are two, behind one entry point (`CalcEngine.evaluate`):

1. **The Champions engine** is a faithful Swift port of Smogon's
   [`@smogon/calc`](https://github.com/smogon/damage-calc). It follows the
   upstream code line by line, including modifier order and rounding, and
   runs on data generated from the calc's own tables. The whole calc is
   ported, including Z-Moves, Dynamax and Tera, but only what Champions uses
   is switched on. See [`PKReference/ShowdownPort-NOTES.md`](PKReference/ShowdownPort-NOTES.md).
2. **The legacy engine** implements the Gen V+ damage formula directly. It
   handles anything the port can't represent, such as a side that isn't in
   Champions mode. [`PKReference/AbilityReference.md`](PKReference/AbilityReference.md)
   lists which abilities it models.

**Showdown paste import and export.** Paste any Showdown set to load it into
a side. The importer shows exactly what did and didn't match, and converts
between mainline EVs and Champions stat points. You can export the current
side as paste text.

**EV solver.** It answers three questions for a move row, and can write the
answer back to the calc:

- the cheapest HP and defensive investment for the defender to survive the hit
- the cheapest offensive investment for the attacker to OHKO
- the Speed each side needs to outspeed the other

It checks every possible value rather than searching, so abilities and
berries that make damage non-monotonic can't mislead it. Two-hit goals
("survive two hits", "guaranteed 2HKO") are played out in the battle
simulator, so effects between the hits count: Sitrus Berry, Multiscale,
Stamina, Leftovers and doubles spread damage.

### Sets

A library of saved spreads (`SavedSpread`). Each has a species, ability,
item, nature, level, EVs/IVs (mainline or Champions scale) and four moves.
The editor can limit moves to legal ones. **Predict Set** runs a small
on-device model: you give it a species and a style (Competitive, Defensive,
Offensive, Setup, Slow Attacker or Trick Room Setter), and it fills in a
complete, legal Champions set.

### Teams

Teams of up to six saved sets. Each team slot refers to a saved set by name,
so edits to the set show up in every team that uses it. The team page shows
**type coverage**: STAB and super-effective coverage across the whole team.
**Import Paste** turns a complete Showdown team paste into a team plus one
saved set per Pokémon, all with unique names.

### Speed Tiers

Enter a Pokémon, or load a saved set, and set its modifiers: nature, Speed
EVs or stat points, IV, stage, item, ability or status, level and Mega
Evolution. The tab then shows where its final Speed falls against a benchmark
list. That list can be limited to the Champions roster, with or without Mega
Evolutions. Speed values match the Showdown port for every combination of
modifiers.

### Problem Solver

Enter the set you need to beat, the same way as a side of the calc (or load a
saved set or paste one), and the tab lists every combination in the current
Champions regulation that knocks it out in one hit, or in two:

- **Guaranteed:** the lowest damage roll must KO, under doubles rules
  (spread moves do 0.75×) and after the set's own ability, including its
  Intimidate, which a switch can turn off. Sturdy and Focus Sash (from full
  HP) and Disguise take a hit, so against them only moves that hit more
  than once, or Mold Breaker, count; two hits shows the rest.
- **Every candidate is checked by the calc:** each legal Pokémon, form and
  Mega, with each of its abilities and legal damaging moves, holding the
  move's type-boosting item. The whole regulation takes a second or two.
- **The fewest points:** each answer's attack investment is scaled down to
  the least that still guarantees the KO, with the Speed to outspeed, trying
  an attacking and a Speed nature, and Choice Scarf when nothing else is
  faster.
- **The field:** weather, terrain, a partner's Helping Hand, Tailwind on
  your side, and Trick Room, under which the slower Pokémon moves first.
- **Two hits:** the same move on two turns running, from the lowest rolls,
  allowing for what happens between them: a Sitrus Berry or Leftovers,
  Multiscale, a resist berry, Knock Off taking the item, Draco Meteor's
  drop. When anything does, every answer is then played out in the battle
  simulator, and the answer says so.
- **Grouped:** outspeeds and OHKOs; OHKOs with priority; OHKOs but slower
  (Trick Room, Tailwind or a switch-in). Each Pokémon shows its best answer,
  with its other moves a tap away, and a filter finds answers by Pokémon,
  move or ability. Accuracy under 100% and drawbacks (must recharge, faints
  the user, charges first) are marked.
- **Usage:** each answer shows the share of tournament teams that bring its
  Pokémon, from Team Search's Limitless teams, and "Most used" puts the
  popular ones first.
- **Each answer** opens in the Damage Calc exactly as solved, or saves as a
  set.

### Battle Sim

A turn-based battle engine with these features:

- **Formats:** singles or doubles, with VGC-style team preview (bring 3 in
  singles, 4 in doubles).
- **Teams and legality:** battles use your saved teams, with optional
  Champions regulation legality.
- **Mechanics:** Mega Evolution, abilities and items, weather, terrain,
  hazards and screens, spread moves, Disable, Encore, Pressure and more.
- **AI opponent:** the on-device **Pokii** doubles model can control one side
  or both. With both sides under AI control, the battle plays itself.
- **Coverage notes:** the engine lists anything on your team that it doesn't
  fully model yet.
- **Demo teams:** a fresh install adds a few sample teams, so you can try a
  battle straight away.

### RNG Tools

A full RNG-manipulation toolkit with 11 sub-tabs. Its algorithms run on
PokéFinder's C++ core, which is compiled into the app and called through an
Objective-C++ bridge (`PFBridge.mm`).

| Sub-tab | What it does |
|---|---|
| **Timer** | Precise multi-phase timers for Gen 3/4/5 and custom setups, with calibration, console-specific frame rates, Gen 3's Variable Target, and a run of lead-in beeps on each target that plays with the silent switch on. Settings are saved. Ported from EonTimer. |
| **Finder** | Seed searching and generators, including Method 1 / 1R / 2 / 4, XD/Colo, Channel and Cute Charm. After an attempt it finds what you hit: in Gen 4 the seed and delay, from the Pokétch's coin flips or the roamers and Elm's or Irwin's calls, for the Timer's calibration; in Gen 3 the frame, from what you caught, and a seed learnt in game, from a new game's Trainer ID or a caught Pokémon. Also has Chatot pitches, and Gen 5 keypresses and SHA-1 seeds. For FireRed and LeafGreen (GBA, mGBA and Switch), it narrows a search to targets reachable from a seed you can hit, by your sound, button mode and held buttons and the advances you can wait, with each seed's time, Teachy TV, and Send to Timer. After an attempt, Calibrate works out the IVs from the caught Pokémon's stats and nature, finds which seed and frame you hit, and corrects the timer. Ported from Ten Lines, with the community's farmed seed lists bundled and updatable. |
| **Routes** | Wild encounter tables by game and location, with slot rates and levels. |
| **Statics** | Static and gift encounters. |
| **Eggs** | Egg generation with parents, Everstone, Destiny Knot, Power items and compatibility. |
| **TID/SID** | Trainer ID manipulation, and seed-to-time for DS clocks. |
| **GameCube** | Colosseum and XD: shadow templates, Poké Spot, Jirachi pattern and seed finding. |
| **IV Calc** | IVs from stats, with characteristic and Hidden Power filtering. |
| **IV→PID** | Reverses IVs to PIDs using LCRNG meet-in-the-middle techniques. |
| **HP** | Hidden Power type and power. |
| **Credits** | The sources the tools are ported from. |

Covered games include Ruby, Sapphire, Emerald, FireRed, LeafGreen, Colosseum,
XD, Diamond, Pearl, Platinum, HeartGold, SoulSilver, Black, White, Black 2
and White 2, plus Sword and Shield Max Raid dens. Profiles store console
details such as MAC address and DS type.

### Tournaments

Browse recent Limitless tournaments by game and format, including Champions
regulations M-A, M-B and M-C, and filter by minimum player count. Open an
event to see:

- **Standings,** filterable to the top 4, 8, 16 or 32. Players who dropped
  are listed after the ranked players.
- **Team sheets:** each player's six Pokémon with items, abilities and moves.
- **Saving:** save one Pokémon, or **Save Full Team** to create a team plus
  its saved sets.

Limitless sends species, item, ability, moves and nature, but no stat points.
Turning on **Predict Stats & Nature** lets an on-device model fill in the
stat points, and the nature too when an event didn't record one.

Imports go through a shared importer (`LimitlessTeamImport.swift`), which maps
Limitless names to Pokédex entries: "Hisuian Arcanine" becomes Arcanine-Hisui,
"Indeedee ♀" becomes Indeedee-Female, and "Maushold" becomes its default
form. If any Pokémon or move can't be matched, nothing is saved, and an alert
lists every name that failed.

### Team Search

Describe the team you're thinking of, such as *"Trick Room with Mega
Gardevoir, no Incineroar"*, and Team Search finds the teams that match in
recent Limitless events for the chosen Champions regulation.

- **What it understands:** Pokémon (with nicknames such as "Chomp", regional
  and gendered forms such as "Hisuian Arcanine" or "Indeedee ♀", and Megas
  such as "Mega Charizard Y" or "Charizardite Y"), moves such as "Fake Out"
  and "Follow Me", and team styles: Trick Room, Tailwind, sun, rain, sand,
  snow, the four terrains, redirection and Perish Trap. "No", "without" and
  similar words exclude things.
- **Chips:** what it understood shows as chips under the search field. Tap a
  chip to switch it between include and exclude, or tap × to remove it.
  Typo fixes ("incinaroar → Incineroar") and words it didn't understand show
  too.
- **Apple Intelligence:** when some words aren't understood ("the Hisuian
  fire dog", "a slow team") and Apple Intelligence is on, **Read with Apple
  Intelligence** asks Apple's on-device language model what each of those
  phrases means. Only names Team Search knows are kept, and a "no" before a
  phrase still applies, so "no big fire cat" can become "No Incineroar".
  What it adds is marked with the Apple Intelligence symbol. The on-device
  model is small and its Pokémon knowledge is patchy, so check those chips.
  It runs only when you tap the button, entirely on the device. On devices
  without Apple Intelligence the button doesn't appear, and search works as
  before.
- **Results:** matching teams are grouped into compositions. Teams sharing
  five of their six Pokémon count as variants of the same composition.
  Compositions are ranked by how well their teams placed and how recent the
  events were. Each shows its style tags, team and event counts, and best
  finish. With an empty search, the tab shows the most popular compositions.
- **Details:** a composition lists why it matched, its variants and its
  teams. Each team opens the same team sheet as the Tournaments tab, with
  the same save buttons.
- **Partial matches:** when fewer than 10 teams match everything, teams
  missing one of the requested Pokémon are shown too, marked "Partial match".
- **Often paired with:** once you name a Pokémon, Smogon's ladder usage
  statistics suggest teammates, with the share of ladder teams running them.
  With several Pokémon named, a suggestion must pair with all of them. Tap a
  suggestion to add it to the search. Composition details show each
  Pokémon's ladder usage too. Smogon publishes stats a month at a time, so
  until the selected regulation has its own, the newest earlier
  regulation's stats are used, and labelled as such.
- **Data:** each event's results are downloaded once and cached; pull to
  refresh for new events. If Limitless is limiting requests, the app waits
  and retries. Smogon's stats are cached per month. Settings → Clear Team
  Search Data frees both caches.

### Settings

- **Appearance:** system, light or dark mode, and one of 11 accent colors.
- **Tab bar:** choose which tabs are visible, and which one the app opens to.
- **Default generation:** the Mon Index list the app opens with.
- **Champions regulation:** the active format. New installs default to the
  newest regulation.
- **Data management:** re-download the Pokémon and move data, clear Team
  Search's cached tournament data, or reset all data.
- **Acknowledgements & Licenses:** the data sources and open-source
  components the app uses, with each license's full text.

---

## Pokémon Champions support

Each Champions ranked regulation is described by two bundled JSON files:

| Regulation | Legal period | Species |
|---|---|---|
| M-A | 2026-04-08 → 2026-06-16 | 186 |
| M-B | 2026-06-17 → 2026-09-02 | 208 |
| M-C | 2026-09-09 → 2026-12-02 | 231 |

- `champions-<id>.json`: format rules (stat point caps, species clause, which
  gimmicks are allowed) and the species, item, berry and Mega Stone lists.
- `champions-<id>-learnsets.json`: each species' abilities, base stats, legal
  moves, Megas and alternate forms.

`ChampionsRegulation` is the single source of truth. By default it uses the
newest regulation, and the one in use can be changed in Settings. The Mon
Index, set and team builders, validator, battle simulator, set predictor and
Tournaments tab all read from it. Adding a new regulation takes two JSON
files and one enum case; [`tools/README.md`](tools/README.md) walks through
it step by step.

Champions-specific mechanics that are modelled include:

- the 0–32 stat point system with a 66-point total, and IVs fixed at 31
- Champions stat formulas, taken from the Showdown port
- every Mega Evolution in the regulations, including the new Champions Megas

---

## Siri, Spotlight and Shortcuts

These actions work from Siri, Spotlight (including running them straight
from Spotlight on the Mac) and the Shortcuts app. Each answers in place,
with a button that opens the page in the app:

- **Look Up Pokémon**: its types, what it's weak to and resists by type, and
  its base stat total. "What is Garchomp weak to in PK Reference?"
- **Calculate Damage**: one Pokémon's move against another, as the calc
  would run it. Each side's stats are asked for (no investment, full
  investment, full investment and a boosting nature, or a saved set of that
  Pokémon), never assumed; "max def" and the like are understood.
  "PK Reference, how much will Incineroar do?"
- **Search Teams**: the top tournament compositions for a description, as
  in Team Search. "Search teams in PK Reference."
- **Compare Speed**: which of two Pokémon is faster, with each one's Speed.
  Each one's investment is asked for, as in the calc; a saved set brings its
  Choice Scarf and its Mega. "PK Reference, how fast is Dragapult?"
- **Check Legality**: whether a Pokémon, form or Mega is allowed in a
  Champions regulation (the one in Settings unless another is named), and
  why not when it isn't. "PK Reference, is Incineroar legal?"
- **Find Counters**: what beats a Pokémon, from the Problem Solver: how
  many Pokémon knock it out in one hit, and the best three (moving first,
  fewest points). Its investment is asked for (no investment, full HP and
  Defense, full HP and Sp. Def, or a saved set of that Pokémon); without a
  set it gets the ability tournament teams run most, and the answer says
  which. "PK Reference, what beats Incineroar?"
- **Show Saved Set** and **Show Saved Team**: a set's Pokémon, ability,
  item, nature and moves; a team's Pokémon and, for a Champions team, the
  Battle Sim's legality check. "PK Reference, show my team Sand Offense."
- **Load Set into Damage Calc**: opens the calc with a saved set as the
  attacker. "PK Reference, load Scarf Koko into the calc."
- **Search**: the system's in-app search, which Siri and Spotlight can use
  for requests they send to the app. It reads the words: two Pokémon and a
  move open the damage calc on that matchup, with any investment said
  ("mega gardevoir hyper voice vs max investment rillaboom"); a Pokémon
  opens its page, on the form or Mega named; a move or ability opens its
  index. Anything else filters the Mon Index. "Garchomp PK Reference."

Saved sets and teams also show up in Spotlight by name; choosing one opens
it in the app.

## On-device machine learning

All inference runs on the device.

| Model | Files | Used by | Runtime |
|---|---|---|---|
| **Set predictor**: species + style → complete set | `name_qual_weights.npz`, `name_qual_vocab.json` | Sets → Predict Set | `PokiiLite` (Accelerate) |
| **Stat & nature predictor**: species, item, ability and moves → stat points + nature | `stat_nature_model.npz`, `stat_nature_vocab.json` | Tournaments → Predict Stats & Nature | `PokiiLite` |
| **Pokii doubles policy**: battle state → action, and whether to Mega Evolve | `pokii_battler.safetensors`, `feature_config.json` | Battle Sim AI | `PokiiBattler` (Accelerate) |

All three are small multilayer perceptrons (MLPs), bundled with the app and
run in plain Swift on Accelerate.

Team Search can also use Apple's on-device language model, through the
FoundationModels framework, to read words its parser doesn't know. That model
is part of Apple Intelligence rather than the app, and runs only on devices
that have it turned on (see [Team Search](#team-search)). Decoding respects the rules: predicted
abilities and moves are limited to the species' legal options, and stat
points are rebalanced to the 66-point budget. `pokii_parity_samples.json`
lets the tests check the Swift inference against the training outputs.

The set predictor replaced an earlier on-device LLM set builder, which ran a
4-bit "Pokii" model with MLX Swift. That code has been removed; it's still in
the git history.

---

## Architecture

- **UI:** SwiftUI, with split-view layouts for regular width.
- **Persistence:** SwiftData models:
  - `PKMN`: Pokédex entries and Serebii links
  - `Gen8Pokemon` / `Gen9Pokemon`: which Pokémon are in the Gen 8 and 9 regional dexes
  - `PKMNStats`: species, forms, stats, abilities and learnsets
  - `MoveData`: moves
  - `SavedSpread`: saved sets
  - `SavedTeam`: saved teams
- **Data at startup:** on first launch, the app syncs the Pokédex from PokeAPI's
  REST API and the calculator data (species, forms, moves and learnsets) from
  PokeAPI's GraphQL API. Regulation data, Showdown calc data and the ML models
  ship in the app bundle.
- **Concurrency:** the module uses main-actor default isolation. Pure
  computational types, such as the damage port, calc snapshots, EV solver,
  paste parser and tournament data store, are explicitly `nonisolated`, so
  solvers and network work run off the main thread. See
  [`HANDOFF.md`](HANDOFF.md#conventions).
- **C++ core:** PokéFinder's generators and searchers live in `PKReference/Core`,
  and `PFBridge.h/.mm` wraps them. `PFBridgeSwift.swift` gives the RNG
  views a Swift interface to them.
- **Networking:** `LimitlessAPIService` (an actor with a short in-memory cache)
  and `TeamCorpusStore` (a disk cache of tournament standings for Team Search,
  which retries after rate limits and server errors).

More internal documentation:
[`HANDOFF.md`](HANDOFF.md) (where the code lives, conventions, known
limitations and what's next),
[`PKReference/CompartmentalizationPlan.md`](PKReference/CompartmentalizationPlan.md)
(moving game data into JSON), and
[`PKReference/ShowdownPort-NOTES.md`](PKReference/ShowdownPort-NOTES.md).

---

## Building, running and testing

**Requirements:** Xcode 27, with the iOS 26.4 and macOS 26.4 SDKs or later.
The deployment targets are iOS 26.4 and macOS 26.4; the device families are
iPhone, iPad and Apple Vision, and the same target builds the Mac app. The
project has no Swift package dependencies.

1. Open `PKReference.xcodeproj` and select the **PKReference** scheme.
2. Run on a simulator, a device or **My Mac**. The first launch downloads
   Pokémon and move data from PokeAPI, so it needs a network connection;
   later launches work offline, except for Tournaments. The Mac app is
   sandboxed, with outgoing network access.

**Tests:** 1,218 tests written with Swift Testing. They cover the damage engines
and the port, the battle engine by mechanic tier, the EV and two-hit solvers,
speed tiers, paste parsing and import, Champions filters and legality, RNG
tools, ML parity, the tournament import and data store, Team Search's parser,
engine, Smogon suggestions and Apple Intelligence reading (with canned
answers), and the bundled license files. None of them need the network or a
SwiftData store.

```bash
xcodebuild test -project PKReference.xcodeproj -scheme PKReference -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

**Developer tools** (not shipped in the app):

- `tools/gen_mc.py` and `tools/scrape_mc.py` build a new regulation's JSON
  files from Serebii's Champions pages. See [`tools/README.md`](tools/README.md).
- `tools/gen_showdown_data.ts` regenerates
  `PKReference/showdown-champions-data.json` from the vendored `@smogon/calc` data:

  ```bash
  npx tsx tools/gen_showdown_data.ts
  ```

- `tools/vendor/` holds the upstream `damage-calc` and `pokemon-showdown`
  sources that the port and data are based on.

---

## Repository layout

| Path | Contents |
|---|---|
| `PKReference/` | App sources (a synced folder: new files are added to the target automatically) |
| `PKReference/Core/` | PokéFinder's C++ RNG core, plus its vendored libraries (`External/`) and encounter resources. `MODIFICATIONS.md` lists the changes made to it |
| `PKReference/Show*.swift` | The `@smogon/calc` port (`ShowdownCalc`, `ShowdownRuntime`, `ShowdownMechanics`, `ShowdownChampions`, `ShowdownItems`, `ShowdownData`) and Showdown paste parsing and import |
| `PKReference/showdown-champions-data.json` | Species, move and type data generated from `@smogon/calc` |
| `PKReferenceTests/` | Swift Testing suites |
| `champions-m-*.json` | Regulation definitions and learnsets |
| `move_categories.json` | Move damage classes (physical, special, status) |
| `*.npz`, `*_vocab.json`, `pokii_battler.safetensors`, `feature_config.json` | On-device model weights and vocabularies |
| `zstd/` | Zstandard sources, compiled into the app for PokéFinder's compressed resources |
| `PKReference/Licenses/` | License and notice texts for the app and the bundled third-party code, shipped in the app |
| `LICENSE` | The GNU General Public License, version 3 |
| `THIRD_PARTY_NOTICES.md` | Every third-party component, its copyright and its license |
| `HANDOFF.md` | Notes for contributors: where the code lives, conventions, known limitations and what's next |
| `tools/` | Regulation scrapers, the Showdown data generator, and vendored upstream sources |

---

## Data sources and credits

PK Reference is built on the work of many people and projects. Thank you all.

### Game data

| Source | What it provides | Where it's used |
|---|---|---|
| [**PokeAPI**](https://pokeapi.co): REST (`pokeapi.co/api/v2`) and GraphQL (`graphql.pokeapi.co/v1beta2`) | National and regional Pokédex, species and forms, base stats, types, abilities, learnsets, and every move's data | Mon Index, Move Index, Ability Index, Damage Calc, Sets, Teams, Battle Sim, Speed Tiers |
| [**Serebii.net**](https://www.serebii.net) | Pokédex, Attackdex and Abilitydex pages, plus the Champions Pokédex and regulation pages | In-app detail pages and links; the developer scripts that build each regulation's JSON files |
| [**Limitless**](https://play.limitlesstcg.com) (`play.limitlesstcg.com/api`) | Tournament listings, standings and published team sheets | Tournaments tab and Team Search |
| [**Smogon**](https://www.smogon.com) | `@smogon/calc` and its data (below), and monthly ladder usage statistics ([smogon.com/stats](https://www.smogon.com/stats/)) | Damage Calc, EV solver, Speed Tiers, Battle Sim damage; Team Search's "often paired with" suggestions and ladder usage |

### Ported and vendored code

| Project | Authors | License | Used for |
|---|---|---|---|
| [**@smogon/calc** (damage-calc)](https://github.com/smogon/damage-calc) | Created by Honko; maintained by Austin, Kris and the damage-calc contributors | MIT | The Champions damage engine (a line-by-line Swift port), stat formulas, and the bundled species, move and type data |
| [**Pokémon Showdown**](https://github.com/smogon/pokemon-showdown) | Guangcong Luo and contributors | MIT | Vendored under `tools/vendor` as the reference for Champions mechanics and data |
| [**PokéFinder**](https://github.com/Admiral-Fish/PokeFinder) | Admiral_Fish, bumba and EzPzStreamz | **GPL-3.0-or-later** | The RNG core in `PKReference/Core` (generators, searchers, encounter data), and the algorithms behind the IV calculator, IV→PID and seed recovery |
| [**EonTimer**](https://github.com/DasAmpharos/EonTimer) | DasAmpharos | MIT | The RNG timer: phase calculations, calibration, console frame rates and rounding |
| [**Ten Lines**](https://github.com/Lincoln-LM/ten-lines) | Lincoln-LM | GPL-3.0 | FireRed and LeafGreen initial seeds and calibration: the seed lists' layouts, held-button offsets, timing, Teachy TV, and the calibration search with its IV calculator |
| [**nlohmann/json**](https://github.com/nlohmann/json) 3.12.0 | Niels Lohmann | MIT | JSON parsing in the C++ core (bundled with PokéFinder) |
| [**Flash Perfect Hash Table**](https://github.com/renzibei/fph-table) (fph) | renzibei (includes code derived from robin-hood-hashing and Abseil) | Apache-2.0 | Perfect hash maps in the C++ core (bundled with PokéFinder) |
| [**Zstandard**](https://github.com/facebook/zstd) | Meta Platforms, Inc. and affiliates | BSD (dual-licensed BSD / GPLv2; used under BSD) | Decompressing PokéFinder's embedded resources |

The RNG tools also build on research from the Pokémon RNG community, including
RNG Reporter, PPRNG and 3DSRNG Tool, and the FireRed and LeafGreen seed lists
the community farms and shares as public sheets. The LCRNG reversal techniques
(meet-in-the-middle and Euclidean-divisor methods) follow discussions on
crypto.stackexchange.com.

### Models

The on-device models were trained in a separate training repository by the
author of this app.

### Pokémon

Pokémon, Pokémon Champions, and all related names, characters and imagery are
trademarks and © of Nintendo, The Pokémon Company, Creatures Inc. and GAME
FREAK inc. This project is not affiliated with or endorsed by them.

---

## License

PK Reference is free software: you can redistribute it and/or modify it under
the terms of the [GNU General Public License](LICENSE) as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version. It is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of merchantability or
fitness for a particular purpose. © 2026 rra013.

The app is under the GPL because it includes PokéFinder's RNG core, which is
GPL-3.0-or-later. Until 2026-09-25, the app's own code was released under the
MIT License; versions from then on are GPL-3.0-or-later.

Third-party components keep their own licenses, all compatible with the GPL.
They're listed with their copyright holders in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md), and the license texts ship
with the app, shown under Settings → Acknowledgements & Licenses. The changes
made to PokéFinder's files are listed in
[`PKReference/Core/MODIFICATIONS.md`](PKReference/Core/MODIFICATIONS.md).

**The App Store:** Apple's App Store terms add restrictions that the GPL
doesn't allow, so distributing the app there needs permission from every
copyright holder, including PokéFinder's authors.
[`RNGRewrite-PLAN.md`](RNGRewrite-PLAN.md) describes the alternative, an
independent rewrite of the RNG core. It's on hold.
