# RNG tools fixes: plan

Status: **PRs 1–6 and 11 merged** (2026-10-03 to 05); PR 11b built, PRs
7–10 and 12 planned (§7). From
the RNG audit's 45 findings, and seven found since (46–52). Findings 1–10
are §2–§5, as four PRs; the rest are §7, as eight more. The owner took
every recommendation in §8, and in §9 for PRs 5–12.

The audit checked the RNG tools against independent maths (Gen 3 Methods
1/2/4, Gen 4 seed-to-time, MT19937, Ruby/Sapphire clock seeds), round-tripped
every Searcher through its Generator, diffed the app's encounter data against
PokéFinder's tables, walked the workflows on the iPhone simulator, and
snapshotted every tool on the Mac. PokéFinder's own maths held up wherever
it was checked; almost every problem is in the app's glue: the bridge's
filters, the values it passes, and the data and screens around it.

---

## 1. Order

| PR | Findings | What |
|---|---|---|
| 1 | 1–4 (and 18) | Stop the crashes and freezes |
| 2 | 6–8 (and 41) | Make the filters and leads do what they say |
| 3 | 9, 10, the Gen 4 part of 5 (and 22, 23) | Static encounters from PokéFinder's tables |
| 4 | the GameCube part of 5 (and 47) | Stream the GameCube searchers |

PRs 5–12, for the rest, are in §7.

PR 1 is small and stops data loss and crashes, so it goes first. PR 2 is
the biggest correctness win for the least code. PR 3 is the largest: it
replaces the hand-coded static encounter lists, which fixes 9 and 10 at the
source and most of the data problems with them. PR 4 reuses the streaming
pattern from Gen 3 (#72).

None of these edits PokéFinder's code (`PKReference/Core`): every fix is in
the bridge (`PFBridge.mm`/`.h`, `PFBridgeSwift.swift`) or the app.

---

## 2. PR 1: crashes and freezes

### 2.1 Eggs crash (1) and the Gen 5/8 tabs (18)

- `pf_eggGenerate3`/`pf_eggGenerate4` take the game as `uint8_t`, and the
  Eggs tool converts with `UInt8(gameVal.rawValue)`, which traps for Pearl
  (256), Platinum (512) and HeartGold/SoulSilver (1024/2048). Make the
  parameter `uint32_t` in the header, the bridge and the Swift wrappers, and
  pass `rawValue` straight through.
- The Eggs tool offers Gen 5 and Gen 8, and runs the Gen 4 generator for
  both. Offer only Gen 3 and Gen 4 (§8: Gen 8 eggs are already the Finder's
  Egg mode; Gen 5 eggs need the SHA-1 profile, §7).
- **Found while building it:** PokéFinder pairs every held egg with every
  pickup advance and keeps them all, so the old defaults (10,000 by 10,000)
  made 100 million Gen 4 eggs (about 18 million Gen 3), and the app ran out
  of memory on any Gen 4 game. The tool now estimates the count (held ×
  pickup, Gen 3's egg chance and Emerald's redraws, less the nature and
  shiny filters) and turns Generate off above 1,000,000, saying why; the
  defaults are held 0–5,000 and pickup 0–100.
- **Tests:** `eggGenerate4` for every Gen 4 game, and `eggGenerate3` for
  every Gen 3 one, returns results; the estimate matches Gen 4's count and
  keeps the old defaults out.

### 2.2 Searchers that freeze the app (2, 3)

The Gen 4 TID/SID searcher and the Colosseum, XD and Channel seed searchers
have the same two faults: PokéFinder's searcher never sets a progress
total, so progress reads over 100% at once and the poll loop stops; then
the app frees the handle on the main actor, which waits for the search
thread to finish.

- The bridge sets each total before starting, as `pf_staticSearch3_start`
  does:
  - Gen 4 ID: (max − min + 1) × 256 × 24, with max `0xE8FFFF` for Infinite.
  - Colosseum and XD: `0x10000`.
  - Channel: `0xBFFFFFFE`.
- Each handle gets a `done` flag, set when the search thread returns, and a
  `done` query.
- The Swift loops poll until `done` (not until 100%), show progress clamped
  to 0–100, and free the handle off the main actor once done or cancelled.
- **Tests:** a Gen 4 ID search with a TID filter finishes at 100% with as
  many results as an independent MT19937 count over the same delays (all
  256 × 24 date/time bytes); Cancel ends an Infinite search at once; the
  Colosseum searcher reports 0–100% while it runs and Cancel ends it. (A
  whole Channel search takes minutes, so it isn't run.) On the simulator:
  an ID search stays scrollable and keeps adding results, and Cancel stops
  it; the XD seed search counts up and cancels.

### 2.3 Number fields that crash (4)

33 places convert a free-entry `Int` with `UInt32(…)`, `UInt16(…)` or
`UInt8(…)`, which traps on a negative or oversized entry.

- `RNGIntField` takes an allowed range (`RNGFieldRange`: advances 0 to
  UInt32.max, bytes, 16-bit words), and plain number fields a `.clamping`
  modifier (month 1–12, year 2000–2099 and so on); the value clamps when it
  commits, so the field shows what's used.
- Every conversion of a field's value becomes `UInt32(clamping:)` and the
  like (42 of them), as a backstop.
- **Tests:** the clamping helper; on the simulator, −5 in Min Advance and
  300 in VCount search without crashing.

---

## 3. PR 2: filters and leads

### 3.1 Wild filters switched off (6)

`makeWildFilter` turns on PokéFinder's `skip` ("disable filters") whenever
gender, ability and shiny are Any and every slot is allowed, so IV ranges,
natures and Hidden Powers are ignored in every wild Generator and Searcher
(Gen 3/4/5/8) and in BDSP Underground.

- Compute `skip` the way the static `makeFilter` does: only when nothing at
  all is filtered (IVs, natures, Hidden Powers, slots, gender, ability,
  shiny). All three filter builders share `filtersNothing` now.
- Treat an all-false nature or Hidden Power list as "any", as `makeFilter`
  does (`allowedOrAll`).
- The same for the Underground filter. **Found while building it:** that
  filter also checks the species against a list the bridge left empty, so
  any filter (a gender or shiny one, before) rejected every result. It gets
  every species the areas hold.
- **Also found:** a Gen 3 or 4 wild Generator result showed "Seed:
  00000000", PokéFinder's wild states having no seed, and its Seed to Time
  was for seed 0. It takes the Generator's seed now.
- **Tests:** Emerald Route 101 with a nature filter, or an HP 31 filter,
  returns only those (it gave all 1,001 advances); Platinum Method J
  likewise; a wild Searcher with nature and IV filters returns only those;
  Underground with a nature or gender filter returns only those.

### 3.2 Shiny Only misses squares (8)

- One helper, `pfShinyFilter(_:)`, returning 3 (star or square) instead of
  1 (star), used at all 18 call sites (Finder Gen 3/4/5/8, GameCube, Eggs).
- **Tests:** all 57 square shinies in seed 0's first 3M advances (TID/SID 0)
  are found, as well as the 344 stars.

### 3.3 Synchronize's nature (7) and Gen 3 static leads (41)

PokéFinder's generators read Synchronize as `Lead(nature)` (0–24), and its
searchers read `Lead::Synchronize` (0) as "any Synchronize nature".

- `PFLead` was an enum with cases only for leads 0 and 24, so it couldn't
  carry a nature; it's a struct now, with `.synchronize(nature:)`.
- Generators get `FinderLead.pfGeneratorLead(syncNature:)`. `syncNature` is
  threaded to the Gen 3/4/5/8 wild generators, the Gen 4/5/8 static
  generators and BDSP Underground. Gen 5's searches run PokéFinder's
  generators on each seed, so they take it too.
- Gen 3 and 4's searchers keep sending 0 (any nature). There the Sync
  Nature picker gives way to a note to choose natures in the Nature Filter.
- Gen 3 static has no lead (PokéFinder ignores it), so its Lead picker goes.
- **Tests:** Gen 4 Method J with Synchronize Timid gives over a third Timid
  (it gave 41 of 2,001); Emerald wild likewise; BDSP static is all Timid.

---

## 4. PR 3: static encounters from PokéFinder

The hand-coded `StaticEncounterData` is the root of 9, 10, 22 and 23: Gen 5
and BDSP have no entries, Gen 4 legends say Method 1, HeartGold/SoulSilver
swap Kyogre and Groudon, many levels are off, and searches find the
template by species, or not at all.

- **Bridge:** `PFStaticTemplate` gains each template's method (Gen 4) and
  fixed IV count, alongside species, form, level, shiny lock and games.
  Every generation's list was already bridged (`pf_getStaticEncounters3/4/5/8`);
  form names come from PokéFinder's translator (`pf_getFormName`).
- **Model:** a static encounter becomes a reference into PokéFinder's
  tables (generation, type, index) with what the template says. Categories
  follow each generation's table order (Gen 5 adds Mythics, Curtis and
  Yancy; Gen 8 adds Ramanas Park and orders gifts before fossils). Names
  come from PokéFinder's translator. The Finder and the Statics browser show
  the same list.
- **Every static search and generate gets the template:**
  - Gen 3: by reference, replacing #72's species lookup.
  - Gen 4: a streaming searcher with the template (`pf_staticSearch4_start`,
    as Gen 3's), and the generator with the template. This takes in the
    queued "Stream the Gen 4 static search" task. The searcher also takes
    the lead now (Synchronize or Cute Charm searches were ignored).
  - Gen 5: the generator and searcher already took `staticType` and
    `staticIndex`; they're passed now.
  - Gen 8: the generator already took them; they're passed now.
  - Gen 5 and 8 look the template up without bounds checks, so they need
    the Pokémon chosen; Search stays off until it is. Sword and Shield have
    no PokéFinder statics, and say so.
- **Found while building it:** PokéFinder's Gen 5 static and wild
  generators pair each PID advance with each IV advance, and the bridge
  passed the PID range as the IV range too: (n + 1)² results, 100 million
  at the default 0–10,000. Both take their own IV range now
  (`ivInitialAdvances`, `ivMaxAdvances`), from the IV Advance fields, which
  Generator mode shows for Gen 5 as well.
- **Method:** choosing an encounter sets the Method picker to its method
  (Method J for Diamond/Pearl/Platinum legends, Method K for
  HeartGold/SoulSilver ones). You can still change it. Gen 5 and BDSP
  encounters carry no method (BDSP's Xorshift has none).
- **FireRed/LeafGreen calibration** keeps working: it takes the template
  from the encounter. The FireRed/LeafGreen Mew event is generated from
  Emerald's Mew template (§8).
- **The Statics browser** lists the same encounters, for Gen 3, 4, 5 and 8,
  with shiny locks marked.
- **Tests:**
  - Every PokéFinder template appears, and nothing else does (but §8's Mew).
  - Gen 4 legends carry J or K.
  - HeartGold has Kyogre and SoulSilver Groudon.
  - Reshiram (shiny-locked) gives no shiny results.
  - BDSP Dialga has three 31s in every result.
  - Gender follows the species in Gen 4.
  - The Gen 4 searcher streams, filters gender by the template, and cancels.
  - The Gen 5 generator gives PID advances × IV advances.

---

## 5. PR 4: GameCube searchers

The shadow, non-shadow and Channel searchers (`GameCubeSearcher`) blocked
until done, with no progress or cancel, as Gen 3's did before #72. A full
Channel search tries 2^32 seeds.

- **Bridge:** one handle for all three (`pf_gamecubeSearchShadow_start`,
  `pf_gamecubeSearchStatic_start`, then `_progress`, `_done`, `_getResults`,
  `_cancel`, `_free`), with PokéFinder's searcher on its own thread. The
  progress total is the IV combinations, or for Channel the seeds it tries
  (2^27 per Sp. Def IV). PokéFinder's `getShadowTeam` and
  `getStaticEncounter` don't check the index, so the starts do, and give no
  handle for one that isn't a template. The blocking searchers are gone.
- **View:** the search runs off the main actor and streams its results
  every tenth of a second, with progress and Stop, as the Finder's do. The
  search stops when the tab closes or the RNG tool changes.
- **Found while building it, so 47 is in this PR:** an XD shadow Pokémon
  with no locks (Ledyba) finds about 270,000 results a second with every
  IV, and the app grew by about 110 MB a second, past 1.5 GB in under a
  minute. The blocking searcher had the same fault, unseen. The GameCube
  searcher and every Finder search and generate now keep at most 100,000
  results (`searchResultLimit`, about 17 MB): the search stops there and
  says so under the button. Generators still build all theirs first (48).
- **Tests:** shadow and non-shadow searches stream the same results as one
  read at the end, reach 100% in order, stay in the IV range, and each
  result's seed generates it; a whole Channel search reads under 100% while
  it runs and Cancel ends it; cancelling the task stops and frees the
  search; indices that aren't templates give no handle; the limit fills to
  100,000 and no further. On the simulator: Ledyba stops at 100,000 with
  the note; a shiny Channel search counts up to 100% (7,320 results);
  leaving the tab drops the CPU to 0; a BDSP generate of 1,000,000
  advances stops at 100,000.

---

## 6. Checking each PR

- The audit's probes become unit tests (each section's **Tests**).
- Full suite on the iPhone 17 Pro Max simulator.
- Clean Mac and iOS builds, checked for warnings, not just errors.
- Simulator walkthroughs of the screens touched.
- Mac snapshots through debug launch arguments, as Calibrate's
  (`-debugOpenSheet frlgCalibration`).

---

## 7. PRs 5–12: the rest

Every remaining finding, checked again against the code on 2026-10-04, as
eight PRs. 18, 41, 45 and 47 are done (PRs 1, 2 and 4). The audit's own
write-up numbers its notes differently; the numbers here are the ones
reported to the owner.

| PR | Findings | What |
|---|---|---|
| 5 | 11, 15, 16, 46 | Leads, methods and modes follow PokéFinder |
| 6 | 27–30, 32, 33 | The Timer keeps time and settings |
| 7 | 12, 13, 31, 39 | Gen 3 targets: Ruby/Sapphire days, Emerald, Dead Battery |
| 8 | 36, 37, 48 | Finder results: generators in chunks, empty and stale results |
| 9 | 19, 20, 24, 25, 44, 49 | Wild areas from PokéFinder's tables |
| 10 | 17 (Gen 8), 35, 40 | Gen 4 tools: years, delays, TSV |
| 11 | 14 (and 38) | What you hit: Gen 4's seed check, Gen 3's frame and seed |
| 11b | 21, 42, 43, 50–52 | IV Calc with each game's base stats, IV fields, number fields |
| 12 | 17 (Gen 5), 26, 34 | Gen 5 profiles, calibrator, IDs and Timer |

PR 5 is small and fixes results that are wrong today, so it goes first.
The Timer comes next: every RNG ends there, and today it loses its
settings and drifts. PRs 7–10 are correctness and data in the Finder and
its tools. PRs 11 and 12 are the largest and need the owner's choices
(§9).

**Order changed (2026-10-04):** PR 11 goes next, after PR 6. A simulated
run from search to calibration showed the gap: nothing in the app tells
you which seed or delay you hit, so the Timer's Delay Hit and Frame Hit,
and Variable Target's seed, have to come from somewhere else. The owner
asked for a searcher for them, which is PR 11's "What You Hit" with a
Gen 3 Trainer ID lookup (§7.7). PRs 7–10 and 12 follow.

### 7.1 PR 5: leads, methods and modes (11, 15, 16, 46)

- **Sword/Shield (11):** PokéFinder's Gen 8 static, wild, egg and ID
  generators are BDSP's, and `getEncounters8` gives BDSP areas under
  Sword/Shield names (Giant's Cap has Oreburgh Mine's Geodude and Zubat).
  `EncounterMode.modes` offers only Raid for Sword/Shield; a stored mode
  that isn't offered falls back to Raid. PR 3's "no static encounters for
  Sword" note becomes unreachable and goes.
- **Gen 3 static methods (15):** PokéFinder's `StaticGenerator3` handles
  Method 4 and treats Method 2 as Method 1; its `StaticSearcher3` handles
  both. Gen 3 static offers Method 1 and Method 4, in both modes, so every
  Searcher result opens in the Generator (§9). Wild keeps 1, 2 and 4. The
  test that pins "Method 2 == Method 1" goes.
- **Leads (16):** each list is what that generation's PokéFinder generator
  reads; the others are ignored today.
  - Gen 3 wild: Emerald only (Ruby, Sapphire, FireRed and LeafGreen get
    none): Synchronize, Cute Charm ♀/♂, Magnet Pull, Static, Pressure.
    Drops Compound Eyes, Suction Cups and Arena Trap; adds Cute Charm.
    Only Emerald has these field effects. PokéFinder's generator applies a
    lead in any game, but its Gen 3 wild screen (`Form/Gen3/Wild3.cpp`)
    shows the lead pickers for Emerald alone, and clears them otherwise.
  - Gen 4 wild: Synchronize, Cute Charm, Magnet Pull, Static, Pressure,
    Suction Cups, Compound Eyes, Arena Trap. Drops Flash Fire, Harvest and
    Storm Drain.
  - Gen 5 wild: Gen 4's list without Arena Trap, so it drops Flash Fire,
    Harvest, Storm Drain and Arena Trap.
  - BDSP wild: Synchronize, Cute Charm, Magnet Pull, Static, Harvest, Flash
    Fire, Storm Drain, Pressure, Compound Eyes. Drops Suction Cups and
    Arena Trap.
  - Statics: Gen 4, 5 and BDSP add Cute Charm (their static generators and
    Gen 4's searcher read it). Gen 3 static has no lead (PR 2).
  - Leads that share an effect in every game the Finder covers are named
    together: "Pressure / Hustle / Vital Spirit", "Suction Cups / Sticky
    Hold".
  - BDSP's Underground reads Synchronize, Cute Charm, Pressure and Compound
    Eyes. BDSP eggs and Sword/Shield raids read none, and lose the picker.
- **BDSP Underground story (46):** PokéFinder reads stages 1–6
  (`flagRates[storyFlag - 1]`); the Finder sends 0 or 1. Offer the six
  stages, named as PokéFinder's Underground screen names them (from its
  GUI source; the Core has no names): Underground Unlocked, Strength
  Obtained, Defog Obtained, 7 Badges, Waterfall Obtained, National Dex.
  Stored 0 becomes 1, stored 1 ("Post-National Dex") becomes 6, and the
  bridge clamps to 1–6. Found while building it: the same screen's level
  flag (0/1 Badges … 8 Badges, National Dex, 0–8), which sets the
  Pokémon's levels, was always 0; it's a picker now.
- **Tests:** each lead list equals the leads its generator reads; Ruby wild
  offers no lead; Sword/Shield offers only Raid; a Gen 3 static Method 4
  Searcher result regenerates in the Generator; every Underground stage
  gives non-negative slot rates, and stage 1 differs from 6.

### 7.2 PR 6: the Timer (27–30, 32, 33)

- **Settings are saved (27):** the generation, console, framerate,
  precision calibration, every generation's mode, targets, calibrations and
  pre-timer, the Custom timer's phases, the beep settings and the last
  Finder handoff's reminder are stored (`@AppStorage`), so switching tools
  keeps them. The hit fields stay per visit.
- **No drift (28):** each phase ends at the original start plus the phases
  before it, as EonTimer times them, on the host's monotonic clock (the one
  audio is scheduled on). Before, each phase began when a 16 ms tick
  noticed the last had ended, so the lateness added up. The display ticks
  60 times a second in the common run-loop modes, so it keeps going while
  you scroll, and the screen stays awake while it runs (as EonTimer's Keep
  Awake).
- **Lead-in beeps (29):** EonTimer's actions: 6 beeps 500 ms apart, the last
  on each phase's end (`src/store/index.ts`'s defaults), adjustable in a
  Beeps card with a Test Beep. Each phase's beeps are scheduled ahead when
  it starts, not fired by the tick.
- **A real sound (30):** a generated 60 ms, 1 kHz tone (no asset to
  license) through `AVAudioEngine` (`RNGTimerSound.swift`), scheduled at
  host times less the output's latency, with a `.playback` session on iOS,
  so it plays with the silent switch on. The audio engine starts with the
  timer, so the first beep isn't late, and reschedules if the output
  changes. Before, it was iOS system sound 1057, fired late by the tick.
- **Variable Target (32):** checked against a video of the process it's for
  (JP Maddox, "FireRed/LeafGreen RNG Manipulation / Prediction") and a 2019
  Smogon post (LeafGreen Mewtwo). It's for a seed you only learn in game:
  you start the timer on the A press that sets the seed (pre-timer 0), or
  let the pre-timer end on it; the timer counts from there while you find
  your seed from your Trainer ID (or a Pokémon's IVs) and look up a target
  frame; you enter the frame and press Set Target Frame (EonTimer's Update),
  and it counts down to that frame, measured from the seed. While waiting it
  shows the time since the seed (EonTimer shows the same). Each mode's use
  is said under the Mode picker. Before, the open phase had no way to set
  the frame, so it was a stopwatch, and a 0 pre-timer wouldn't start.
- **The countdown stays in view (33):** while running, the countdown, Stop
  and Variable Target's frame entry are pinned above the settings (a
  safe-area inset), and the settings are locked, as in EonTimer.
- **Found in the simulated runs:** the Timer stopped when you left it, as
  RNG Tools rebuilds the selected tool, so Variable Target couldn't
  survive the trip to the Finder to look up the frame. There's now one
  timer for the app (`RNGTimerEngine.shared`), which only Stop ends, and a
  bar above the other RNG tools shows it and goes back to it. A new target
  from the Finder replaces a running timer. And Set Target Frame read the
  old frame: a number field commits only when it loses focus, which
  tapping a button doesn't do, so a frame typed and set straight away ran
  as the old one (0 ms, so the timer just ended). The frame is now text,
  read when you tap, and one that has already passed is refused with a
  note, not run.
- **Tests:** the engine takes a clock and a beeper, and with fakes ten
  phases end at their sums despite late ticks; a tick inside a phase
  doesn't report a phase change; the beeps land where
  EonTimer's do; Variable Target resolves (with and without a pre-timer,
  and when the frame has already passed); the Custom phases survive saving.
  On the simulator, two recorded runs: Gen 4 Dialga from the Finder's
  search through Seed to Time and the Timer to a simulated miss and its
  calibration (Calibrated Delay 600 → 603 for a 750 hit on 746); and a
  FireRed Squirtle by Variable Target, with the timer running through the
  Finder's lookup of seed 2DA6 and then counting down to frame 9,591.
  Also: settings survive Finder → Timer; the countdown keeps going during
  a drag; a passed frame shows its note. The beep can't be heard from here
  (simulator or the owner's Mac): the owner listens.

### 7.3 PR 7: Gen 3 targets (12, 13, 31, 39)

- **Ruby/Sapphire Day N (12):** count real calendar days from 1 January
  2000 (a leap year), not `(month - 1) * 31 + day - 1`. PokéFinder's
  dates are already right.
- **Emerald (13):** the target page learns the game. Emerald boots from
  seed 0, so it shows the advances from 0 (`LCRNG::distance`, bridged)
  and sends them to the Timer, in place of Ruby/Sapphire clock times.
- **Dead Battery (39):** PokéFinder's Core only stores the flag, and the
  app passes it only for Emerald. With a dead battery, Ruby and Sapphire
  boot from seed 0x5A0 (PokéFinder's Gen 3 wild screen sets its seed to
  5a0 for a dead-battery profile), so the page shows the advances from
  0x5A0, as for Emerald. The toggle shows for Ruby and Sapphire only.
- **Handoff on GBA (31):** Ruby, Sapphire and Emerald's Send to Timer sets
  the GBA console, as FireRed/LeafGreen's does; today it stays on NDS
  Slot 1, about 17 frames off per 10,000.
- **Tests:** every Day N, hour and minute rebuilds its seed by the
  audit's independent Ruby/Sapphire clock formula; Emerald's count of N
  gives the target seed from 0, and the dead battery's from 0x5A0; the
  handoffs set GBA.

### 7.4 PR 8: Finder results (36, 37, 48)

- **Generators in chunks (48):** PokéFinder's generators return one
  vector, so a Max Advance in the hundreds of millions runs out of memory
  in the bridge. The streaming functions (Finder and GameCube) call the
  generator a chunk of advances at a time (say 10,000; its jump-ahead start
  is cheap), send each chunk, report progress (advances done of the
  total), and stop at `searchResultLimit` or on Stop. Memory is one chunk.
  Gen 5's generators chunk the PID advances. Eggs keep PR 1's estimate.
- **Empty results (36):** a finished search or generate with nothing says
  so, and suggests the filters to loosen (Finder, GameCube, TID/SID,
  Eggs).
- **Stale results (37):** changing the generation, game, mode or encounter
  stops a running search and clears its results. Each result carries the
  generation and game it was found with, so its page uses those.
- **Tests:** chunked results equal one call's over a small range, for
  every generator; progress climbs to 100; a 100-million-advance generate
  stops at the limit with memory flat; results keep their generation.

### 7.5 PR 9: wild areas from PokéFinder (19, 20, 24, 25, 44, 49)

As PR 3 did for statics, a wild area becomes a reference into PokéFinder's
tables: generation, encounter type, location ID and settings.

- **By ID, not name (19):** the location picker lists areas by ID, with
  names told apart where they repeat (HeartGold/SoulSilver's two National
  Parks) and "Location N" where PokéFinder has none. The ID goes to the
  search; no name lookup, and no silent fall back to location 0.
- **Gen 5 seasons (20):** areas and slots come from the chosen season, so
  winter Route 7 shows (and filters) Cubchoo, and areas a season lacks
  aren't offered.
- **Gen 4 settings (24):** time of day and swarm; Poké Radar, the
  dual-slot game and the Great Marsh and Trophy Garden daily Pokémon
  (Diamond/Pearl/Platinum); radio and the Safari Zone's blocks
  (HeartGold/SoulSilver). The bridge's encounter list already takes them;
  the search and generator fix time 0 and nothing on, so they get
  `EncounterSettings4` too, and the Finder shows each where its game has
  it.
- **Slot rates (25):** labels per generation and encounter type, from the
  thresholds PokéFinder's slot code uses, so they match its slots; today
  every game shows Gen 3's rod rates (and "?").
- **Underground areas (49):** a location picker, so each search is one
  area's, as in PokéFinder.
- **Dead code (44):** `WildEncounterData.swift` (about 640 lines) goes.
- **Tests:** every PokéFinder area is offered once, by ID; the two National
  Parks search different tables; winter Route 7 has Cubchoo; a Gen 4
  night route differs from morning; every label set sums to 100.

### 7.6 PR 10: Gen 4 tools (17 Gen 8, 35, 40)

- **Seed to Time year (35):** a year choice (default 2000) with a note to
  set the DS to it. PokéFinder takes the year; a later one shortens the
  delays, which makes some seeds practical.
- **TID/SID delays and TSV (40):** PokéFinder's ID generator loops the
  seed's low 16 bits and reports `efgh + 2000 - year`, so the bridge turns
  the entered delays into those bits for the year; the Generator's Filter
  TSV is passed (today only the Searcher's is).
- **Coin flips and calls (38):** done in PR 11 (its seed check tries
  neighbouring seconds).
- **TID/SID's Gen 8 tab (17):** removed; the Finder's Gen 8 TID/SID mode is
  the same BDSP generator (§9). Gen 5's tab hides until PR 12.
- **Tests:** for 2010, the delays shown are the ones entered; the TSV
  filter keeps only matches; a coin flip one second off is found; a 2010
  delay is the 2000 one less 10.

### 7.7 PR 11: what you hit (14), and PR 11b: IV Calc (21, 42, 43, 50–52)

PR 11 is split, so the part the owner asked for comes first.

**PR 11, built (2026-10-04): what you hit.** A simulated run showed nothing
in the app tells you which seed, delay or frame you hit, so the Timer's
Delay Hit and Frame Hit had to come from elsewhere.

- **Gen 4: Check Your Seed.** The owner's point: Gen 4 calibrates by
  checking the seed right after loading, by the Pokétch's coin flips
  (Diamond, Pearl and Platinum), or the roamers and Elm's or Irwin's calls
  (HeartGold and SoulSilver). This is what PokéFinder's and RNG Reporter's
  Seed to Time calibration does (`SeedToTimeCalculator4::calibrate`, and
  Smogon's DPP/HGSS guide part 2, "Delay / Seed Verification").
  - It lists the seeds some delays (default ±20) and seconds (±1) either
    side of the target, with each one's flips, roamer routes and calls.
    You enter what the game shows, and they narrow to the seed you hit.
    "Use Delay N as Delay Hit" sets the Timer's, ready for Update
    Calibration.
  - The Finder's Seed to Time now hands the Timer the target's whole
    clock time (not just its delay and second), so the check knows the
    seeds around it. The roamers come from PokéFinder's `HGSSRoamer`,
    bridged (`pf_hgssRoamer`: their PRNG skips and new routes).
  - When you hit an odd delay for an even target, or the reverse, it says
    so, with the guide's fix: change the DS year by 1, or put a GBA game in
    Slot 2.
  - The Finder's Gen 4 Generator opens the same check around its seed,
    replacing the old Coin Flip and Elm/Irwin finders. Those scanned seeds
    numerically, so a second off was never found (finding 38, done here).
- **Gen 3: What You Hit.** On a Gen 3 static target's page (not FireRed
  and LeafGreen's farmed seeds, which have Calibrate), you enter what you
  caught: nature, gender, shininess, and IVs from its stats. It lists the
  frames near the target, from the game's initial seed, that make it.
  - The initial seed is Emerald's 0000, a dead battery's 05A0, otherwise
    the seed before the target's, and editable.
  - A Searcher's target frame is the PRNG distance from the initial seed
    (`pf_lcrngDistance`).
  - "Use as Frame Hit" gives the Timer the frames you were off by, added to
    its own target frame.
- **Gen 3: your seed (Variable Target).** The Generator gets "From
  Trainer ID" (a new game's seed is the Trainer ID: 11686 is 2DA6) and
  "From a Pokémon You Caught". The second walks IV→PID's matches back to
  the 16-bit seed and frame; it tries up to 64 IV combinations, so narrow
  ones work.
- **Verify Catch (14)** is gone. Its "Delay Delta" compared the low bits of
  the wrong seeds.
- **Also:** a DS target handed to the Timer moves its console off GBA.
- **Tests:** the coin flips and calls are PokéFinder's; every Seed to Time
  clock time gives back its seed; the clock rolls over (31 December, a leap
  day); ten flips find a seed 4 delays and a second late among 123; the
  roamers take their skips, land on routes they roam, and with the calls
  find the seed; a bare seed's neighbours move by the second and the
  delay; a Searcher target's frame from seed 0 generates it; a Squirtle
  caught 4 frames late is found 4 late; a caught Pokémon leads back to a
  seed and frame that make it; a Trainer ID gives its seed.
- **On the simulator, recorded:** Gen 4 Dialga's target through Seed to
  Time to the Timer; Check Your Seed with ten flips finds delay 750 (+4)
  alone among 123 seeds, and calibrates 600 → 603. Then FireRed's Trainer
  ID 11686 gives seed 2DA6; a HP 19 / Attack 31 Docile is frame 9,613,
  4 late; Frame Hit 9,595 calibrates 0 → −67 ms.

**PR 11b, built: IV Calc and the IV fields (21, 42, 43, 50–52).**

- **IV Calc (21):** a game choice, as PokéFinder's IV calculator offers
  them: Ruby/Sapphire/Emerald/FireRed/LeafGreen, Diamond/Pearl/Platinum,
  HeartGold/SoulSilver, Black/White/Black 2/White 2, BDSP and Sword/Shield,
  each with PokéFinder's base stats and checker (a fresh catch, no EVs),
  or Today's Games, with the current stats and EVs (§9).
  - The species are those the game's table has (386 in Gen 3, 493 in Gen
    4), with a form picker where it has forms (Deoxys, Rotom, …).
  - Nature, characteristic (not Gen 3) and Hidden Power narrow the IVs;
    stats at more levels narrow them further.
  - Each stat says the level at which it next narrows (PokéFinder's
    `IVChecker::nextLevel`).
  - Bridge: `pf_formCount`, `pf_presentSpecies`, `pf_nextLevel`,
    `pf_getCharacteristic`.
- **IV→PID's nature (42):** a picker with names in PokéFinder's order
  (pid % 25), not "Nature (0-24)". It now says when nothing fits: its
  "No results found" could never show.
- **IV fields (43):** the Eggs parent IVs' blank capsules were sliders in
  a three-column grid with no room for a track. Every IV slider is now a
  0–31 number field with the number pad. Tapping or scrolling off a field
  puts the keyboard away, as the number pad has no Return key.
- **Nature order (50):** the old IV Calc listed natures in `allNatures`'
  order but calculated in PokéFinder's, so most natures were wrong
  (Modest calculated as Jolly). Both pickers now use PokéFinder's order,
  with each nature's effect.
- **Today's EVs (51):** the old IV Calc had EV fields but never used them.
- **Number fields (52):** SwiftUI's `TextField(value:format:)` only takes
  its number when the field loses focus. A button tapped straight after
  typing used the number from before: on the simulator, Find IVs said
  "Enter its Speed." with the Speed typed. The Timer's Update Calibration
  and Start read their fields the same way.
  `LiveIntField` takes the number as you type. The shared fields
  (`RNGIntField`, `RNGOptIntField`, `IVField`) and the other number fields
  in the RNG tools use it, and select their number on focus, so typing
  replaces a 31. Fields that can't go negative get the number pad.
- **Smaller fixes:** Hidden Power's Grass preset was Fire's IVs; its base
  power was labelled Gen 5–6 (it's Gen 3–5; Gen 6 made it 60 always).
- **Tests:** Pikachu's IVs differ between Emerald and Sword; Modest is
  PokéFinder's 15; a characteristic, Hidden Power and a Lv 100 line narrow
  a Platinum catch to one spread; Gen 3 has 386 species and Deoxys four
  forms; today's EVs count; the Hidden Power presets give their types; the
  number fields keep digits and a leading minus only.
- **On the simulator:** Deoxys-Attack in Gen 3 (form picker, no
  characteristic); Garchomp in Platinum, with Find IVs tapped while Speed
  was still being typed; the Timer's Gen 5 Second Hit used as typed
  (calibration −95 → −125) and its Calibration field's minus; IV→PID's
  Modest spread from seed 12345678 finds PID 84EA0B71; the Eggs fields and
  the Hidden Power presets.

### 7.8 PR 12: Gen 5 profiles (17 Gen 5, 26, 34)

- **Profiles (26):** a Gen 5 profile (MAC, DS type, language, game, Timer0
  range, VCount, GxStat, VFrame, keypress options), saved like the Trainer
  profiles, several of them. Today there's one set of values, all 0, which
  no DS uses.
- **Calibrator (26):** PokéFinder's `ProfileSearcher5` (from the IVs you
  got, `ProfileIVSearcher5`, or a known seed), as a streaming handle; "Find
  My Parameters" fills the profile. Defaults per console are §9.
- **Gen 5 IDs (17):** PokéFinder's `IDSearcher5` in the TID/SID tool's Gen 5
  tab, searching dates and times with the profile. (`pf_idGenerate5` is
  bridged but unused.)
- **Send to Timer (34):** Gen 5 results set the Gen 5 Timer (Standard's
  delay and second; C-Gear and Entralink's from the method). BDSP has no
  timer step (its RNG is advanced in game), so none.
- **Tests:** the calibrator finds the parameters a seed was made with; the
  ID searcher's results regenerate in `IDGenerator5`; the handoff fills
  the Gen 5 Timer.

### 7.9 Found since

- 46: BDSP Underground's Story Progress (PR 5).
- 47: done in PR 4 (§5).
- 48: generators build every result first (PR 8).
- 49: BDSP Underground mixes every area's results. The bridge generates
  each area of the Grand Underground and returns them together, without
  saying which; PokéFinder's screen picks a location. Found while
  building PR 5; it goes with the wild areas (PR 9), as a location picker.
- 50: the old IV Calc's natures were in the wrong order (PR 11b).
- 51: the old IV Calc ignored its EVs (PR 11b).
- 52: number fields used the number from before when a button was tapped
  straight after typing (PR 11b).

---

## 8. Decisions

The owner's choices (2026-10-03): the recommendation in each.

1. **FireRed/LeafGreen Mew.** PokéFinder has no FRLG Mew template. Keep it
   as the one app-only entry, generated from Emerald's Mew template (same
   Gen 3 base stats, genderless, can be shiny) so it can be searched and
   calibrated (recommended), or leave it unsearchable as now.
2. **Eggs' Gen 5 and Gen 8 tabs.** Remove them (recommended: Gen 8 eggs are
   in the Finder; Gen 5 eggs can come with the Gen 5 profile work), or build
   Gen 5 eggs now.
3. **Shiny Only.** Star or square (recommended, what "shiny" means in game),
   or Ten Lines' Star / Square / Either choice.
4. **PR size.** Four PRs as in §1 (recommended), or one per finding.

---

## 9. Decisions for PRs 5–12

The owner's choices (2026-10-04): the recommendation in each.

1. **Verify Catch (14).** Rework it as "What You Hit": Gen 4's delay and
   advance hit and Emerald's advance hit, feeding the Timer's calibration
   (recommended: it's the step after every catch that misses); or remove
   it.
2. **IV Calc (21).** A game choice: PokéFinder's checker and base stats for
   Gen 3–5 and BDSP, today's stats with EVs for current games
   (recommended); or PokéFinder's for everything, which drops the EVs.
3. **Gen 3 static methods (15).** Method 1 and Method 4, which PokéFinder
   implements in both modes (recommended); or Method 1 only.
4. **TID/SID's Gen 8 tab (17).** Remove it, since the Finder's Gen 8 TID/SID
   mode is the same generator (recommended, as with Eggs); or wire it to
   `IDGenerator8`.
5. **Gen 5 defaults (26).** The calibrator only, with a prompt to run it
   (recommended, unless there's a source for per-console Timer0 and VCount
   values to cite); or ship a table of them.
6. **Order.** As §7 (recommended), or another.
