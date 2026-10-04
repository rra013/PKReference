# RNG tools fixes: plan

Status: **PRs 1–4 built** (2026-10-03/04). From
the RNG audit's 45 findings, and three found since (46–48). This plan covers findings 1–10 in detail (§2–§5), as four PRs,
and groups the rest for later (§7). The owner took every recommendation in
§8.

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

## 7. After 1–10

Grouped by area; each group could be a PR. Numbers are the audit's.

**Correctness**
- 11: Sword/Shield's Static, Wild, Egg and TID/SID modes run BDSP's RNG.
  Offer only Raid for Sword/Shield.
- 12: Ruby/Sapphire "Day N" counts 31-day months.
- 13: Emerald targets should count advances from seed 0.
- 14: Verify Catch: rework or remove.
- 15: Gen 3 static Generator's Method 2 is Method 1. Offer Method 1 only
  for static, as statics are.
- 16: Gen 3 leads should be Emerald-only, with Cute Charm.
- 17: TID/SID's Gen 5/8 tabs run Gen 4's generator (bridge IDGenerator5/8,
  or hide them).
- 19: Locations are found by name. Pass location IDs, not names, through.
- 20: Gen 5 season slots.
- 21: IV Calc should use each generation's base stats (PokéFinder's
  PersonalInfo).

**Data**
- 24: Gen 4 time of day, swarms, Poké Radar, radio and dual-slot.
- 25: Slot rate labels per generation.
- 26: Gen 5 profile defaults and PokéFinder's profile calibrator.

**Timer**
- 27: Save the Timer's settings.
- 28: Time phases from the original start, keep the timer running while
  scrolling, use a monotonic clock.
- 29: Lead-in beeps (EonTimer's count and interval).
- 30: A real sound player, so it plays on the Mac and with the silent
  switch on.
- 31: Ruby/Sapphire/Emerald handoff should set GBA.
- 32: Variable Target entry.
- 33: Keep the countdown in view.

**Smaller**
- 34–45, from the audit: Gen 5/8 Send to Timer, Gen 4 year choice, the
  empty-results message, stale results, second-tolerant coin flips, Dead
  Battery, TID/SID labels, IV→PID's nature picker, the Eggs IV controls,
  and dead code.

**Found since**
- 46: BDSP Underground's Story Progress. PokéFinder's story flag runs 1–6
  and indexes `flagRates[storyFlag - 1]`. The Finder offers 0
  ("Pre-National Dex"), which reads `flagRates[-1]` (the slot rates come
  out wrong), and 1 ("Post-National Dex"), which is the earliest stage.
  Offer PokéFinder's six stages, with their names.
- 47: The streaming searchers kept every result. They show the first 500,
  but a wide-open search (every IV, a long delay range) kept collecting:
  a Gen 4 static search gathers about 4,500 a second, and Gen 3's does the
  same, so a search left running grew without limit. Done in PR 4 (§5):
  searches stop at 100,000 results and say so.
- 48: Generators build every result before the app sees any. PokéFinder's
  generators return one vector, so a Finder or GameCube Generator with a
  Max Advance in the hundreds of millions runs out of memory in the bridge,
  before the 100,000 limit applies (after a BDSP generate of 1,000,000
  advances, the app sat at 625 MB). Have the bridge stop at the limit, or
  estimate first as the Eggs tool does.

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
