# RNG tools fixes: plan

Status: **PRs 1–8, 11 and 11b merged** (2026-10-04 and 05, #74–#83);
**PRs 9 and 10 built** (§5, §6); **PR 12 planned** (§7). From the RNG
audit's 45 findings, and twelve found since (46–57). The owner took every recommendation in §9, and in
§10 for PRs 5–12. When PR 12 merges, what's still true here moves into
`HANDOFF.md` and this file goes.

The audit checked the RNG tools against independent maths (Gen 3 Methods
1/2/4, Gen 4 seed-to-time, MT19937, Ruby/Sapphire clock seeds), round-tripped
every Searcher through its Generator, diffed the app's encounter data against
PokéFinder's tables, walked the workflows on the iPhone simulator, and
snapshotted every tool on the Mac. PokéFinder's own maths held up wherever
it was checked; almost every problem is in the app's glue: the bridge's
filters, the values it passes, and the data and screens around it.

None of the fixes edit PokéFinder's code (`PKReference/Core`): every fix is
in the bridge (`PFBridge.mm`/`.h`, `PFBridgeSwift.swift`) or the app.

The merged PRs' write-ups were cut to §2 on 2026-10-05, and the sections
renumbered. PR descriptions from before then cite the old numbers; git
history has that version.

---

## 1. Order and status

| PR | Findings | What | Status |
|---|---|---|---|
| 1 | 1–4, 18 | Stop the crashes and freezes | [#74](https://github.com/rra013/PKReference/pull/74), merged 2026-10-04 |
| 2 | 6–8, 41 | Make the filters and leads do what they say | [#75](https://github.com/rra013/PKReference/pull/75), merged 2026-10-04 |
| 3 | 9, 10, 22, 23, Gen 4 part of 5 | Static encounters from PokéFinder's tables | [#76](https://github.com/rra013/PKReference/pull/76), merged 2026-10-04 |
| 4 | GameCube part of 5, 47 | Stream the GameCube searchers | [#77](https://github.com/rra013/PKReference/pull/77), merged 2026-10-04 |
| 5 | 11, 15, 16, 46 | Leads, methods and modes follow PokéFinder | [#78](https://github.com/rra013/PKReference/pull/78), merged 2026-10-04 |
| 6 | 27–30, 32, 33 | The Timer keeps time and settings | [#79](https://github.com/rra013/PKReference/pull/79), merged 2026-10-04 |
| 11 | 14, 38 | What you hit: Gen 4's seed check, Gen 3's frame and seed | [#80](https://github.com/rra013/PKReference/pull/80), merged 2026-10-05 |
| 11b | 21, 42, 43, 50–52 | IV Calc with each game's base stats, IV fields, number fields | [#81](https://github.com/rra013/PKReference/pull/81), merged 2026-10-05 |
| 7 | 12, 13, 31, 39, 53, 54 | Gen 3 targets: Ruby/Sapphire days, Emerald, Dead Battery | [#82](https://github.com/rra013/PKReference/pull/82), merged 2026-10-05 |
| 8 | 36, 37, 48, 55 | Finder results: generators in chunks, empty and stale results | [#83](https://github.com/rra013/PKReference/pull/83), merged 2026-10-05 |
| 9 | 19, 20, 24, 25, 44, 49, 56, 57 | Wild areas from PokéFinder's tables | Built (§5) |
| 10 | 17 (Gen 8), 35, 40 | Gen 4 tools: years, delays, TSV | Built (§6) |
| 12 | 17 (Gen 5), 26, 34 | Gen 5 profiles, calibrator, IDs and Timer | Planned (§7) |

PRs 1–4 were the worst ten findings. PR 11 was moved up after PR 6
(2026-10-04): a simulated run from search to calibration showed that
nothing in the app told you which seed or delay you hit, so the owner asked
for it next. It was split, so that part came first (11) and the IV Calc
after (11b). PRs 9, 10 and 12 follow in that order. PR 12 is the largest.

---

## 2. The merged PRs

Each PR's description says what changed and what was checked, on the
simulator and the Mac. What's kept here is what later work needs: what each
PR left in the code, and where it went beyond the plan.

| PR | What it did | Changed from the plan, or found while building it |
|---|---|---|
| 1 | Eggs pass the game as `uint32_t` (Pearl and later trapped) and offer Gen 3 and 4 only. The Gen 4 ID, Colosseum, XD and Channel searchers set their progress totals in the bridge, have a `done` flag, and free their handles off the main actor. Number fields clamp (`RNGFieldRange`, `.clamping`), with `UInt32(clamping:)` and the like as a backstop. | Eggs estimate their count and turn Generate off above 1,000,000 (the old defaults made 100 million Gen 4 eggs); defaults are held 0–5,000 and pickup 0–100. |
| 2 | One `filtersNothing` for all three filter builders, so wild IV, nature and Hidden Power filters apply; an all-false list means any (`allowedOrAll`). Shiny Only is star or square (`pfShinyFilter`). `PFLead` is a struct with `.synchronize(nature:)`; generators take `syncNature` through `FinderLead.pfGeneratorLead(syncNature:)`. Gen 3 and 4 searchers send 0 (any nature). Gen 3 static has no lead. | The Underground filter gets every species its areas hold (it had none, so any filter rejected everything). Gen 3 and 4 wild Generator results carry the Generator's seed (they showed 00000000). |
| 3 | Static encounters are references into PokéFinder's tables (generation, type, index), with each template's method and fixed IVs (`PFStaticTemplate`). The Finder and the Statics browser share the list. Gen 4's static searcher streams (`pf_staticSearch4_start`) and takes the lead. Gen 5 and 8 need the Pokémon chosen. Choosing an encounter sets its method. FireRed/LeafGreen Mew uses Emerald's template (§9). | Gen 5's static and wild generators take their own IV range (`ivInitialAdvances`, `ivMaxAdvances`); the PID range was passed for both, giving (n + 1)² results. |
| 4 | One streaming handle for the shadow, non-shadow and Channel searchers (`pf_gamecubeSearchShadow_start`, `pf_gamecubeSearchStatic_start`, then `_progress`, `_done`, `_getResults`, `_cancel`, `_free`); the starts check the index. The search stops when the tab closes or the tool changes. | Finding 47 came in: an unlocked XD shadow Pokémon grew the app by about 110 MB a second. Every Finder and GameCube search and generate keeps at most 100,000 results (`searchResultLimit`). |
| 5 | Sword/Shield offers Raid only (PokéFinder's Gen 8 generators are BDSP's). Gen 3 static offers Methods 1 and 4. Each lead list is what that generation's generator reads; shared effects are named together ("Pressure / Hustle / Vital Spirit"). BDSP Underground offers the six story stages. | The Underground's level flag (badges) was always 0; it's a picker now. |
| 6 | The Timer's settings are stored; phases end at the start plus the phases before, on the host's monotonic clock; EonTimer's lead-in beeps; a generated tone through `AVAudioEngine` (`RNGTimerSound.swift`); Variable Target's Set Target Frame; the countdown pinned in view. | One timer for the app (`RNGTimerEngine.shared`), with a bar above the other tools, so Variable Target survives a trip to the Finder. Set Target Frame reads the field as text when tapped. |
| 11 | Gen 4 Check Your Seed (`Gen4SeedCheck.swift`): the seeds around the target with their coin flips, roamers (`pf_hgssRoamer`) and calls, narrowed by what the game shows, and Use as Delay Hit. The Finder hands the Timer the target's whole clock time. Gen 3 What You Hit (`Gen3WhatYouHit.swift`, with `pf_lcrngDistance`), and the Generator's "From Trainer ID" and "From a Pokémon You Caught". Verify Catch is gone. | The old Coin Flip and Elm/Irwin finders went too (finding 38: they missed a seed a second off). |
| 11b | IV Calc with a game choice: PokéFinder's checker and base stats per game, or Today's Games with EVs (`pf_formCount`, `pf_presentSpecies`, `pf_nextLevel`, `pf_getCharacteristic`). Natures in PokéFinder's order everywhere. IV inputs are 0–31 number fields. | `LiveIntField` takes a number as it's typed (a button tapped straight after typing used the old one); `RNGIntField`, `RNGOptIntField` and `IVField` use it. Hidden Power's Grass preset had Fire's IVs. |
| 7 | `Gen3TargetStart`: where a Gen 3 target's frames count from. Ruby/Sapphire use real days from 1 January 2000; Emerald counts from 0000; a dead battery from 05A0 (Ruby and Sapphire only, off by default, as PokéFinder). Send to Timer sets the GBA console. | Generator targets (53) and FireRed/LeafGreen without the seed list (54) were found while building it. |
| 8 | `generateInChunks` runs a generator 10,000 advances at a time (`generatorChunkSize`), with progress, Stop and the limit. Every Finder generator, the GameCube Generator and PokéSpot use it. A run that finds nothing says why (`noResultsText`). Changing what results were found for clears them. | Switching Searcher and Generator only stops a running search: each mode keeps its own list. The Gen 3/4 wild Generator passes 0–31 IVs (55). |

**What later PRs build on:**

- **A search that runs long** gets a streaming handle, as `pf_staticSearch3_start`,
  `pf_staticSearch4_start` and the GameCube searchers have: the bridge sets
  the progress total before starting, sets `done` when the thread returns,
  and Swift frees it off the main actor. PR 12's calibrator and ID searcher
  follow it.
- **A generator** runs through `generateInChunks`, and every search and
  generate stops at `searchResultLimit`.
- **A number field** is a `LiveIntField` (or `RNGIntField`, `RNGOptIntField`,
  `IVField`), with an `RNGFieldRange` or `.clamping`.
- **Leads** are `PFLead`, and each generation's list is what its generator
  reads; Shiny Only is `pfShinyFilter`.
- **Encounters** are references into PokéFinder's tables, as statics are
  since PR 3. PR 9 does the same for wild areas.
- **Handoffs to the Timer** go through `RNGTimerEngine.shared`. Gen 3 targets
  use `Gen3TargetStart`, and Gen 4 the whole clock time that Check Your Seed
  reads. PR 12 adds Gen 5's.
- **Results** clear when what they were found for changes, and an empty run
  says why (`noResultsText`).

---

## 3. Findings index

| Findings | PR |
|---|---|
| 1–4, 18 | 1 |
| 5 | 3 (Gen 4), 4 (GameCube) |
| 6–8, 41 | 2 |
| 9, 10, 22, 23 | 3 |
| 11, 15, 16, 46 | 5 |
| 12, 13, 31, 39, 53, 54 | 7 |
| 14, 38 | 11 |
| 17 | 10 (Gen 8), 12 (Gen 5) |
| 19, 20, 24, 25, 44, 49, 56, 57 | 9 |
| 21, 42, 43, 50–52 | 11b |
| 26, 34 | 12 |
| 27–30, 32, 33 | 6 |
| 35, 40 | 10 |
| 36, 37, 48, 55 | 8 |
| 45 | One of PRs 1, 2 and 4; the plan doesn't say which |
| 47 | 4 |

The audit's own write-up numbers its notes differently; the numbers here
are the ones reported to the owner.

---

## 4. Checking each PR

- The audit's probes become unit tests (each section's **Tests**).
- Full suite on the iPhone 17 Pro Max simulator.
- Clean Mac and iOS builds, checked for warnings, not just errors.
- Simulator walkthroughs of the screens touched.
- Mac snapshots through debug launch arguments, as Calibrate's
  (`-debugOpenSheet frlgCalibration`).

---

## 5. PR 9: wild areas from PokéFinder (19, 20, 24, 25, 44, 49; 56, 57)

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

**Built (2026-10-05).** `WildArea` and `WildAreaData` (`EncounterData.swift`)
list each game's areas from PokéFinder, by ID, with each slot's chance; the
Finder and the Routes browser both use them, and `WildEncounterData.swift`
is gone.

- **By ID (19):** no game's list repeats an ID (checked for every game,
  encounter type, time and season), so the bridge finds the area by ID and
  gives nothing when there's none, where it fell back to the list's first.
  Names that repeat get their number: "National Park (1)" and "(2)" in
  HeartGold/SoulSilver, "Turnback Cave (1)" to "(3)" in BDSP. Locations are
  listed by ID, which is each game's map order.
- **Settings (20, 24):** a `WildSettings` with what PokéFinder's Wild3, Wild4,
  Wild5 and Wild8 screens show, each where its game and encounter show it:
  Gen 5's season (moved from DS Parameters to the encounter); Gen 4 and
  BDSP's time of day and swarm; Diamond, Pearl and Platinum's dual slot,
  Poké Radar, Great Marsh and Trophy Garden daily Pokémon and Mt. Coronet's
  Feebas tile; HeartGold and SoulSilver's radio, Safari Zone blocks and
  fishing happiness bonus; Ruby, Sapphire and Emerald's Route 119 Feebas
  tile. The bridge takes Gen 4's as one struct (`PFEncounterSettings4`).
- **Slot rates (25):** from the thresholds of PokéFinder's `EncounterSlot.cpp`
  (hSlot, jSlot, kSlot, bwSlot, bdspSlot), the Safari Zone's ten even slots,
  and a Feebas tile's half. Diamond's Old Rod, for one, has five slots, and
  HeartGold's rods their own rates.
- **Underground (49):** an Area picker and a Pokémon picker; the bridge
  generates one area, with that area's species as the filter's
  (`pf_getUndergroundAreas8`).
- **Changed from the plan:**
  - The Poké Radar is PokéFinder's own method from one slot, not only the
    radar's slots: turning it on generates and searches by
    `Method::PokeRadar` from the chosen Radar Pokémon, with a Shiny Patch
    switch, and drops the leads that set the slot or level, as PokéFinder's
    screen does. The radar's slots alone with Method J would have been wrong.
  - BDSP's grass gets the same time, swarm, radar and daily Pokémon, which
    its generator already took and was never given.
  - The Safari Zone's Pokémon reroll until an IV is 31, so its Searcher needs
    one IV at 31; Search says so and stays off until there is, as
    PokéFinder's does.
  - Switching games keeps the location by name: IDs are each game's own.
  - The Routes browser lists by the same model, with BDSP, a time picker
    for Gen 4 and BDSP, and Gen 5's season.
  - The unused blocking Gen 3 and 4 wild searchers are gone from the bridge.

---

## 6. PR 10: Gen 4 tools (17 Gen 8, 35, 40)

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
  the same BDSP generator (§10). Gen 5's tab hides until PR 12.
- **Tests:** for 2010, the delays shown are the ones entered; the TSV
  filter keeps only matches; a coin flip one second off is found; a 2010
  delay is the 2000 one less 10.

**Built (2026-10-05).**

- **Seed to Time year (35):** a DS Year card on a Gen 4 target's Seed to
  Time (2000–2099, kept between visits). Each time's delay is for that
  year, with the year in the time handed to the Timer, so Check Your Seed
  rebuilds the seeds around it (`Gen4SeedTime` already took a year). A
  year that would make the delay negative says which years work.
- **TID/SID (40):** the bridge turns the entered delays into the seed's low
  bits for the year (`delayBitsForYear`), for the Generator and the
  Searcher, so the delays shown are the ones entered. The Generator's TSV
  filter is passed.
- **TID/SID's tabs (17):** Gen 3 and Gen 4 only (`IDRNGView.generations`).
- **Changed from the plan:** checking around a bare seed (the Finder's Gen 4
  Generator) gives delays for Seed to Time's year too. Its delays were the
  seed's low bits, so with a later year the hit and the Timer's target
  would have differed by the years since 2000.
- **Kept as PokéFinder:** the Finder's Gen 4 searchers take delays as the
  seed's low bits (a DS set to 2000), as PokéFinder's Static4 and Wild4
  do; only Seed to Time takes the year.

---

## 7. PR 12: Gen 5 profiles (17 Gen 5, 26, 34)

- **Profiles (26):** a Gen 5 profile (MAC, DS type, language, game, Timer0
  range, VCount, GxStat, VFrame, keypress options), saved like the Trainer
  profiles, several of them. Today there's one set of values, all 0, which
  no DS uses.
- **Calibrator (26):** PokéFinder's `ProfileSearcher5` (from the IVs you
  got, `ProfileIVSearcher5`, or a known seed), as a streaming handle; "Find
  My Parameters" fills the profile. Defaults per console are §10.
- **Gen 5 IDs (17):** PokéFinder's `IDSearcher5` in the TID/SID tool's Gen 5
  tab, searching dates and times with the profile. (`pf_idGenerate5` is
  bridged but unused.)
- **Send to Timer (34):** Gen 5 results set the Gen 5 Timer (Standard's
  delay and second; C-Gear and Entralink's from the method). BDSP has no
  timer step (its RNG is advanced in game), so none.
- **Tests:** the calibrator finds the parameters a seed was made with; the
  ID searcher's results regenerate in `IDGenerator5`; the handoff fills
  the Gen 5 Timer.

---

## 8. Found since

- 46: BDSP Underground's Story Progress (PR 5).
- 47: done in PR 4 (§2).
- 48: generators build every result first (PR 8).
- 49: BDSP Underground mixes every area's results. The bridge generates
  each area of the Grand Underground and returns them together, without
  saying which; PokéFinder's screen picks a location. Found while
  building PR 5; it goes with the wild areas (PR 9), as a location picker.
- 50: the old IV Calc's natures were in the wrong order (PR 11b).
- 51: the old IV Calc ignored its EVs (PR 11b).
- 52: number fields used the number from before when a button was tapped
  straight after typing (PR 11b).
- 53: Ruby/Sapphire Generator targets sent the Timer the frames to the
  Generator's seed, not the target's (PR 7).
- 54: FireRed/LeafGreen targets without the seed list showed Ruby/Sapphire
  clock times (PR 7).
- 55: the Gen 3/4 wild Generator filtered by the Searcher's hidden IV
  ranges (PR 8).
- 56: Gen 4 wild offered Method 1, which PokéFinder's wild generator and
  searcher don't have (they gave nothing), and each game the other's method
  (Method K for Diamond, Pearl and Platinum, J for HeartGold and
  SoulSilver). Wild offers its game's own (PR 9).
- 57: Gen 5 and BDSP wild searches ignored the Pokémon picker: the slots it
  allows were never passed (PR 9).

---

## 9. Decisions for PRs 1–4

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

## 10. Decisions for PRs 5–12

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
6. **Order.** As §1 (recommended), or another.
