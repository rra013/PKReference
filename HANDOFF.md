# PK Reference: handoff

State of `main` as of 2026-09-30, how the codebase fits together for the
next change, and what's worth doing next. The [README](README.md) describes
the app itself; this file is for whoever works on it.

## Contents

1. [Recent work](#recent-work)
2. [Where things live](#where-things-live)
3. [Recipes](#recipes)
4. [Conventions](#conventions)
5. [Building and testing](#building-and-testing)
6. [Known limitations](#known-limitations)
7. [What's next](#whats-next)
8. [Other documents](#other-documents)

---

## Recent work

Since the UI work (#23–#35), the PRs moved game data into JSON, fixed
iPad layouts, and built the Mac app. Each one's description says what changed
and what was checked.

| PR | Change |
|---|---|
| [#36](https://github.com/rra013/PKReference/pull/36) | Matchup colors for Pokémon 1 and 2 (`MatchupColors`) |
| [#37](https://github.com/rra013/PKReference/pull/37), [#38](https://github.com/rra013/PKReference/pull/38) | iPad layout fixes |
| [#39](https://github.com/rra013/PKReference/pull/39) | The remaining hard-coded colors |
| [#40](https://github.com/rra013/PKReference/pull/40)–[#46](https://github.com/rra013/PKReference/pull/46) | Game data into JSON: regulation rules, Mega forms, Tera type, Battle Sim move tables, held items, setup moves, the type chart (and Poison resisting Bug) |
| [#47](https://github.com/rra013/PKReference/pull/47) | PokéFinder's generator scripts and inputs left out of the bundle |
| [#48](https://github.com/rra013/PKReference/pull/48) | The item picker shows the held item; mainline mode offers Choice items again |
| [#49](https://github.com/rra013/PKReference/pull/49), [#50](https://github.com/rra013/PKReference/pull/50), [#53](https://github.com/rra013/PKReference/pull/53) | The Mac app: builds and runs, sidebar and Settings window, screen pass |
| [#51](https://github.com/rra013/PKReference/pull/51) | A fresh detail page for each selection in split views |
| [#52](https://github.com/rra013/PKReference/pull/52) | No build warnings |
| [#54](https://github.com/rra013/PKReference/pull/54) | The Mac app merged into `main` |
| [#55](https://github.com/rra013/PKReference/pull/55) | Siri, Spotlight and Shortcuts, Phase 1; the app is named PK Reference |
| [#56](https://github.com/rra013/PKReference/pull/56) | The Xcode project, targets, module and folders renamed to PKReference |

Full suite with the RNG fixes' PR 11b: 1226 tests, all passing.

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

The Mac app builds from the same target.
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
  Tournaments, Team Search) is under More *and* set as Open To, its large
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

Roughly in order of value for effort.

1. **Data compartmentalization.** [`PKReference/CompartmentalizationPlan.md`](PKReference/CompartmentalizationPlan.md)
   lists seven migrations of game data into JSON, all done: each
   regulation's `rules` block (P1), the Battle Sim's move tables (P2), the
   type chart (P3), the Mega forms (P4), Mega stones as held items (P5), the
   validator's setup moves and Choice items (P6) and a set's Tera type (P7).
   See the plan for what each covers and leaves; what's left are the parts
   of P5 and P7 that need features first (items, Tera, Dynamax).
2. **Mac app, distributed outside the App Store.** Steps 1–3 were built on
   `mac-main` and merged into `main` on 2026-09-30; the Mac app is now just
   another destination of `main`, and `mac-main` is retired.
   1. Builds and runs. Done: iOS-only APIs guarded, Mac entitlements.
   2. App shell. Done: the tabs in a sidebar (`.sidebarAdaptable`), with no
      More list; Settings as the ⌘, window; a 1280×820 default window, at
      least 900×600. The sidebar itself hasn't been seen in a snapshot,
      since snapshots can't draw glass.
   3. Screen pass. Done: list/detail tabs in `ListDetailSplit`; form text
      fields and segmented pickers without stray labels; a right-click
      Delete where rows only swiped (Sets, Teams, Load Spread); every sheet
      sized with `sheetSize()` (all 17 already had Done or Cancel); Edit ›
      Find (⌘F) and the tabs in the View menu (⌘1–⌘9), which the owner
      checked on the Mac along with right-click Delete. Left out: a
      paste-import command, since the calc has two sides to paste into.
   4. Developer ID signing, the hardened runtime, notarization, and releases
      on GitHub, with the tagged source for the GPL. Optionally Sparkle for
      updates.
3. **Siri, Spotlight and Shortcuts.** [`AppIntents-PLAN.md`](AppIntents-PLAN.md):
   App Intents for iPhone, iPad and the Mac. Phases 1 and 2 are built: Look
   Up Pokémon, Calculate Damage, Search Teams, Compare Speed, Check
   Legality, Find Counters (the Problem Solver's), Show Saved Set, Show
   Saved Team and Load Set into Damage Calc, answering in place with an
   Open button. That's ten App Shortcuts, the most an app can have, so a
   new one has to replace one; the system's in-app search
   (`.system.search`, which the new Siri looks for); and saved sets and
   teams in Spotlight (`AppIntents.swift`, `SavedIntents.swift`,
   `IntentEntities.swift`, `IntentAnswers.swift`, `IntentSnippets.swift`;
   `AppNavigator` opens the page). Left: trying the phrases with the
   conversational Siri on the owner's devices and tuning descriptions to
   what it picks (Phase 3). `-debugSnippets YES` renders the snippets on the
   Mac, and `-debugNavigate` makes an Open button's request. On the
   owner's Mac (2026-09-30), Spotlight refused every third-party app's
   items, this app's sets and teams included, from Xcode's build folder or
   from Applications ("Failed to request donation": the connection to
   `com.apple.SetStoreUpdateService` is invalidated; Chrome and Claude
   failed the same way). That's macOS, not the app: on the simulator the
   sets and teams are indexed and open from Spotlight. Recheck after a
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
   - **A new regulation** also needs a case in `RegulationChoice`
     (`IntentEntities.swift`); `AppIntentsTests` fails until it has one.
4. **Problem Solver.** [`ProblemSolver-PLAN.md`](ProblemSolver-PLAN.md):
   pick a set that's a problem, get the Pokémon, move and investment
   combinations that OHKO or 2HKO it (guaranteed, Champions doubles),
   grouped by whether they move first. Brute force through the calc engine,
   pruned by a heuristic. Phases 1 and 2 are built: the solver
   (`ProblemSolver.swift`) and the tab (`ProblemSolverView.swift`, under
   More on the iPhone), with `ProblemSolverTests`. The whole of M-C, 25,922 candidates, solves in about
   2 s in a debug build. Phase 3 is built too, one PR per feature: field
   options, grouping by Pokémon, the two-hit mode (fast check, then the
   battle simulator), usage ranking (Limitless teams) and Siri's "what
   beats X" (Find Counters). Decisions in the plan's §8.
5. **Team Search open risks.**
   - Confirm Limitless's rate limits and terms before corpus builds grow.
   - Early in a regulation there's little data. An "include last
     regulation's teams" option (keeping only teams legal now) was planned
     but not built.
   - Names Limitless writes that the alias table doesn't know still search,
     but saving a team reports them; a log of them would show the gaps.
6. **Gen 9 in the Showdown port.** Only Champions is ported; other
   generations use the legacy engine, and `calculateShowdown` stops with a
   clear error for them. See [`PKReference/ShowdownPort-NOTES.md`](PKReference/ShowdownPort-NOTES.md).
7. **FireRed and LeafGreen initial seeds** (built 2026-10-03), ported from
   [Ten Lines](https://github.com/Lincoln-LM/ten-lines) (GPL-3.0, no "or
   later"; see `THIRD_PARTY_NOTICES.md`). In the Finder's Gen 3 FireRed or
   LeafGreen search, Initial Seed narrows the targets to those a seed you
   can hit reaches in your advance range, for every version Ten Lines knows
   (GBA ENG/EU/JPN, mGBA, Switch ENG/EU and JPN), by sound, button mode,
   seed button and held button, with Teachy TV on GBA. The options start on
   the game's own (Mono, Help, A, nothing held), which every list farms;
   settings a version's list hasn't farmed are marked "(not farmed)", the
   card says what the list covers, and warns when the choices find nothing.
   A target's page lists
   its seeds with seed times per console, and Send to Timer sets the Gen 3
   timer's pre-timer and target frame. `FRLGSeeds.swift` is the engine,
   `FRLGSeedsView.swift` the screens; the farmed lists are bundled
   (`PKReference/frlg-seeds-*.csv`, refreshed by `tools/update_frlg_seeds.sh`)
   and Update Seed Lists downloads newer ones in the app. On Switch the
   overworld advances twice a frame, so the timer's target is the continue
   screen's frame (advances less twice the Overworld Frames). Calibrate, on
   each seed of a static target, is Ten Lines' calibration form: shininess,
   nature (Any turns the IV calculation off and searches every nature) and
   gender, then the stats from the summary screen, a line per level, which
   PokéFinder's IV checker turns into editable IV ranges with the
   encounter's own template's base stats (`pf_calcIVsStatic3`). The search
   (`FRLGCalibration`, generating from that template with
   `pf_staticTemplateGenerate3`) lists the presses and frames that make it,
   nearest first, and Calibrate from This corrects the seed press and final
   press, saved for every seed after. The Finder's Gen 3 static search
   streams: PokéFinder's searcher runs on its own thread
   (`pf_staticSearch3_start`), read every tenth of a second for results and
   progress, and Stop cancels it. It and the Generator use the chosen
   encounter's template, so gender follows the species; with no Pokémon
   chosen every result is genderless, and the gender filter says so. The
   reachable list (`FRLGMatchCache`) checks each new result once. Still
   open: wild calibration (Ten Lines' check_seeds_wild), Teachy TV on
   Switch, which Ten Lines hasn't worked out either, and the Switch lists'
   settings nobody has farmed yet (Ten Lines leaves those columns out, and
   so does the app). Gen 4's static search still runs all at once with a
   stand-in template. The Finder's FireRed and LeafGreen Mew event has no
   PokéFinder template (it has Mew only on Emerald), so it can't be
   calibrated yet.
8. **App Store.** Blocked on the GPL until PokéFinder's authors give
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
| [`PKReference/AbilityReference.md`](PKReference/AbilityReference.md) | Which abilities the legacy damage engine models |
| [`PKReference/CompartmentalizationPlan.md`](PKReference/CompartmentalizationPlan.md) | Plan for moving game data into JSON (done) |
| [`AppIntents-PLAN.md`](AppIntents-PLAN.md) | Plan for Siri, Spotlight and Shortcuts actions (Phases 1 and 2 built) |
| [`ProblemSolver-PLAN.md`](ProblemSolver-PLAN.md) | Plan for the Problem Solver: counters that OHKO a chosen set |
| [`RNGRewrite-PLAN.md`](RNGRewrite-PLAN.md) | Plan for an independent RNG core (on hold) |
| [`RNGFixes-PLAN.md`](RNGFixes-PLAN.md) | Fixes from the 2026-10-03 RNG tools audit: four PRs for the worst ten findings (merged), then the rest (PRs 5, 6 and 11 merged, 11b built, the others planned; the owner's choices in §9) |
| [`tools/README.md`](tools/README.md) | Scripts that regenerate the bundled data |

Removed on 2026-09-27, all in git history: `CalcCore-HANDOFF.md` (the EV
solver work, finished; its conventions are above; it was also being copied
into the app),
`TeamSearch-PLAN.md` (finished; its open risks are above) and
`PKDex/ProjectDocumentation.md` (an April file-by-file reference, replaced by
the README's architecture section).
