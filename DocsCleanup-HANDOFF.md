# Planning docs cleanup: handoff

For a new session that tidies the project's planning documents into a few
current ones. Written 2026-10-05, at the end of the RNG fixes' PR 8. Delete
this file when the cleanup is done; the last time finished plans were
retired (2026-09-27: `CalcCore-HANDOFF.md`, `TeamSearch-PLAN.md`,
`PKDex/ProjectDocumentation.md`) is the model.

---

## 1. The goal

Someone opening the repository should find:

- **`README.md`**: the app, for people using or building it.
- **`HANDOFF.md`**: the state of `main`, where things live, recipes,
  conventions, building and testing, known limitations, and *only the open*
  next steps, with an index of the other documents.
- **Plans only for work that's still going.** A finished plan goes, with
  whatever is still true and useful (open items, decisions that still bind,
  gotchas) moved into `HANDOFF.md` first. The history is in git and in each
  PR's description; don't copy it.
- **Reference notes** that code points to, kept where they are.

Nothing about the app changes. The only code edits are comments that name a
document that moves or goes (§5).

## 2. Before starting

- **Start after the RNG fixes' PR 8 is merged.** It's on branch
  `rng-fixes-finder-results` and edits `RNGFixes-PLAN.md`, `HANDOFF.md` and
  `README.md`. Check with `gh pr list --state all --head rng-fixes-finder-results`,
  then branch from an up-to-date `main` (e.g. `docs-cleanup`).
- **The RNG fixes carry on in parallel** (PR 9 next). Before editing
  `RNGFixes-PLAN.md`, check `gh pr list` for an open RNG PR. If one is open,
  leave that file for last and keep the change to it in its own commit, so
  it's easy to rebase.
- **The owner's working rules** (from earlier sessions):
  - Ask before committing, pushing or opening a PR, unless the message says to.
  - The owner merges fast: check `gh pr view <n> --json state` before adding
    commits, and open a follow-up PR if it's merged.
  - Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  - PR descriptions end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
  - Never commit `RNGRuns/` (untracked screen recordings).
- **Write like the existing docs**: plain, short sentences, dates as dates
  (not "recently"), say what was checked and what wasn't.

## 3. The documents today

Outside the vendored code (`tools/vendor/**` is upstream's; leave it), there
are twelve:

| File | Lines | Last changed | Status | Proposed |
|---|---|---|---|---|
| `README.md` | 595 | 2026-10-05 | Current; the app's description | Keep. Only check it against the end state (counts, links). |
| `HANDOFF.md` | 496 | 2026-10-05 | Partly stale (§4) | Refresh; it absorbs the retired plans' leftovers |
| `RNGFixes-PLAN.md` | 728 | 2026-10-05 | **Active**: PRs 1–7, 11, 11b merged, 8 built, 9, 10, 12 planned | Keep; shrink the merged PRs' sections (§4) |
| `RNGRewrite-PLAN.md` | 344 | 2026-09-30 | On hold (licensing) | Keep as it is |
| `AppIntents-PLAN.md` | 215 | 2026-10-02 | Phases 1–2 built; Phase 3's rest needs the owner's devices | Retire into `HANDOFF.md` |
| `ProblemSolver-PLAN.md` | 403 | 2026-10-02 | Every phase built | Retire into `HANDOFF.md` / `README.md` |
| `PKReference/CompartmentalizationPlan.md` | 509 | 2026-09-30 | Every priority done; its line numbers date from June | Retire into `HANDOFF.md` / `tools/README.md` |
| `PKReference/ShowdownPort-NOTES.md` | 105 | 2026-09-30 | Reference; ten code comments point to it | Keep; check its "Still TODO" |
| `PKReference/AbilityReference.md` | 287 | 2026-09-30 | Reference for the legacy engine (`computeAbilityModifiers`, still called from `CalcEngine.swift:135`) | Check it's still accurate (§4), then keep or retire |
| `tools/README.md` | 237 | 2026-10-02 | Current; how to add a Champions regulation | Keep |
| `THIRD_PARTY_NOTICES.md` | 56 | 2026-10-03 | Required (licenses) | Keep, untouched |
| `PKReference/Core/MODIFICATIONS.md` | 85 | 2026-09-30 | Required by PokéFinder's GPL. Core hasn't changed since; the bridge is outside Core | Keep, untouched |

## 4. What to do with each

**`HANDOFF.md`**

- The opening says "State of `main` as of 2026-09-30". Update the date.
- **Recent work** stops at #56. Twenty-six PRs have merged since (list in
  §6), plus PR 8. Summarize them by area rather than one row each:
  Siri Phase 2 (#57–#59), the Problem Solver (#60–#67, #69), Champions data
  (#68), and the RNG tools (#70–#82 and PR 8). For the RNG tools, point to
  `RNGFixes-PLAN.md`.
- **What's next** mixes finished work with open work. Items 1 (data
  compartmentalization), 3 (Siri), 4 (Problem Solver) and 7 (FireRed and
  LeafGreen initial seeds) are mostly done. Keep only what's open in each:
  - compartmentalization's parts of P5 and P7 that wait on features;
  - Siri's Phase 3, the ten-App-Shortcut limit, `RegulationChoice` for a new
    regulation, and the Shortcuts tile bug (an Apple bug; don't chase it);
  - FRLG's open items: wild calibration, Teachy TV on Switch, the
    unfarmed Switch settings, and Mew;
  - Team Search's open risks (the memory note `team-search-feature` points here).
- **Other documents** table: update it to the end state, and add the
  retired files to the "Removed on" note, with the date.
- Keep the rest (where things live, recipes, conventions, building and
  testing, known limitations). Check the test count there against the
  latest run (1,237 at PR 8).

**`RNGFixes-PLAN.md`** (while PRs 9, 10 and 12 remain)

- §2–§5 and §7.1–§7.4 and §7.7 are long write-ups of merged PRs, which
  duplicate their PR descriptions. Replace them with a short table:
  PR link, findings, one line on what it did, and anything a later PR
  depends on. Examples of what to keep:
  - `searchResultLimit`;
  - `LiveIntField`;
  - `generateInChunks`;
  - `Gen3TargetStart`;
  - the Gen 4 seed check;
  - the plan deviations each PR recorded ("Changed from the plan").
- Keep §7.5 (PR 9), §7.6 (PR 10), §7.8 (PR 12), §7.9 (findings found since)
  and the owner's decisions in §8 and §9 as they are. Don't change what's
  planned.
- Keep the findings numbering (1–55): PR descriptions and later sections
  cite it. A compact index of findings to PRs would help.
- When PR 12 merges, the whole file retires into `HANDOFF.md`. That's not
  this cleanup's job, but say so in the file's status line.

**`AppIntents-PLAN.md`** → retire.

- Move into `HANDOFF.md`'s Siri item:
  - what's left of Phase 3;
  - the decisions in §7 that still bind;
  - how to check it (§6: `-debugSnippets`, `-debugNavigate`).
- The README already describes the actions for users.
- Update the comment at `PKReference/AppIntents.swift:12`.

**`ProblemSolver-PLAN.md`** → retire.

- Its design reasoning is worth a paragraph in `HANDOFF.md` (or the
  README's Problem Solver section, if it's about behavior):
  - brute force through the calc, with a heuristic to prune (§2–§3);
  - guarantees under doubles rules;
  - what building it showed (§9).
- The owner's decisions in §8 that still constrain changes go too.
- Update the comments at `PKReference/ProblemSolver.swift:7`,
  `PKReference/ProblemSolverView.swift:9` and
  `PKReferenceTests/ProblemSolverTests.swift:5`.

**`PKReference/CompartmentalizationPlan.md`** → retire.

- `HANDOFF.md` item 1 already summarizes it.
- Move §4's litmus test ("Add Regulation M-B with Tera on") to
  `tools/README.md`, if `tools/README.md` doesn't already cover those steps.
- Move what P5 and P7 left (§2) to `HANDOFF.md`.
- §5 (out of scope) can go.

**`PKReference/ShowdownPort-NOTES.md`** → keep in place.

- Eight comments in `PKReference/Showdown*.swift`, and two in
  `tools/gen_showdown_data.ts`, cite this path.
- Its "Still TODO for Phase 1" (Gen 9 isn't ported) is still true:
  `ShowdownChampions.swift:27` stops with a `preconditionFailure` for other
  generations.

**`PKReference/AbilityReference.md`**

- Before deciding, check where the legacy engine (`CalcEngine.swift`) is
  still used. Is it mainline mode, the Battle Sim, or anything else, now
  that the Champions calc is the Showdown port?
- If it's still used, keep the file and say at its top which features it
  covers. If not, retire it.

**`RNGRewrite-PLAN.md`** → keep.

- It's the only App Store path without PokéFinder's authors' permission.
- The memory note `gpl-licensing-decision` names it.

## 5. References to update

Code comments that name a document. Change them only for documents that
move or go:

- `PKReference/AppIntents.swift:12` (AppIntents-PLAN.md)
- `PKReference/ProblemSolver.swift:7`, `PKReference/ProblemSolverView.swift:9`, `PKReferenceTests/ProblemSolverTests.swift:5` (ProblemSolver-PLAN.md)
- `PKReference/EVSolverSheet.swift:16` (HANDOFF.md's conventions; fine unless that section is renamed)
- ShowdownPort-NOTES.md: `ShowdownMechanics.swift:6`, `ShowdownChampions.swift:7,18`, `ShowdownItems.swift:7`, `ShowdownRuntime.swift:7,149`, `ShowdownCalc.swift:16`, `ShowdownData.swift:8`, `tools/gen_showdown_data.ts:5,79` (all under `PKReference/` except the last; keep the file where it is)
- `PKReference/PokiiFeaturizer.swift:396` cites a `pokii_xcode_integration_guide`, which isn't in the repository. Ask the owner whether it lives elsewhere, rather than guessing.

Docs that link to others: `README.md`, `HANDOFF.md` and `AppIntents-PLAN.md`.

Memory notes (in `~/.claude/projects/-Users-rra-Documents-YukiSoft-PKDex/memory/`):
- `team-search-feature.md` points at `HANDOFF.md` → "What's next";
- `gpl-licensing-decision.md` at `RNGRewrite-PLAN.md`.

Update either one if what it points at moves.

## 6. Facts gathered on 2026-10-05

PRs merged after #56:

| PR | Merged | Title |
|---|---|---|
| #57 | 2026-09-30 | Siri Phase 2: speed, legality, saved sets and teams, and Spotlight |
| #58 | 2026-09-30 | In-app search for Siri and Spotlight, and Mon Index requests at launch |
| #59 | 2026-09-30 | Read search sentences into a damage calc, and open forms from search |
| #60 | 2026-09-30 | Plan the Problem Solver, and note the Shortcuts tile bug |
| #61 | 2026-09-30 | Problem Solver, Phase 1: the solver |
| #62 | 2026-09-30 | Problem Solver, Phase 2: the tab |
| #63 | 2026-09-30 | Problem Solver: field options and grouping by Pokémon (Phase 3) |
| #64 | 2026-09-30 | Problem Solver: two-hit mode (Phase 3) |
| #65 | 2026-09-30 | Problem Solver: filter answers by ability |
| #66 | 2026-10-02 | Problem Solver: rank answers by tournament usage (Phase 3) |
| #67 | 2026-10-02 | Problem Solver: Find Counters, Siri's "what beats X?" (Phase 3) |
| #68 | 2026-10-03 | Add Dragoninite to every regulation's Mega Stones |
| #69 | 2026-10-03 | Let Sturdy, Focus Sash and Disguise take a hit in the calc and Problem Solver |
| #70 | 2026-10-03 | RNG Finder: FireRed/LeafGreen initial seeds by required advances (from Ten Lines) |
| #71 | 2026-10-03 | Calibrate FireRed/LeafGreen attempts, and name natures in the game's order |
| #72 | 2026-10-03 | Stream the Finder's Gen 3 static search, with the encounter's gender |
| #73 | 2026-10-03 | Fix the Mac app crashing when Calibrate opens, and three build warnings |
| #74 | 2026-10-04 | Stop the RNG tools' crashes and freezes (RNG fixes, PR 1) |
| #75 | 2026-10-04 | Make the RNG tools' filters and leads do what they say (RNG fixes, PR 2) |
| #76 | 2026-10-04 | Take the RNG tools' static encounters from PokéFinder's tables |
| #77 | 2026-10-04 | Stream the GameCube searchers, and stop searches at 100,000 results |
| #78 | 2026-10-04 | Make the Finder's leads, methods and modes follow PokéFinder |
| #79 | 2026-10-04 | Make the RNG Timer keep time, beep ahead and keep its settings |
| #80 | 2026-10-05 | Find what you hit: Gen 4's seed check, Gen 3's frame and seed |
| #81 | 2026-10-05 | IV Calc with each game's base stats; number fields that keep up |
| #82 | 2026-10-05 | Gen 3 targets count from the seed the game boots on |

In `RNGFixes-PLAN.md`'s numbering, #74–#79 are the RNG fixes' PRs 1–6,
#80 is PR 11, #81 PR 11b and #82 PR 7.

- No relative link in the twelve documents was broken on 2026-10-05 (§7's
  check).
- The full suite at PR 8 was 1,237 tests, all passing.

## 7. Checking it

- **Links:** run this from the repo root after the edits. It prints
  nothing when every relative link resolves:

  ```bash
  python3 -c "
  import re,os,subprocess
  docs=[d for d in subprocess.check_output(['git','ls-files','*.md']).decode().split() if not d.startswith(('tools/vendor','PKReference/Core/'))]+['PKReference/Core/MODIFICATIONS.md']
  for d in docs:
      for m in re.finditer(r'\]\(([^)#\s]+)', open(d).read()):
          t=m.group(1)
          if not t.startswith('http') and not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(d),t))): print(d,'->',t)
  "
  ```

- **No references to retired files:**
  `git grep -n -e AppIntents-PLAN -e ProblemSolver-PLAN -e CompartmentalizationPlan`
  should find only the "Removed on" note in `HANDOFF.md`.
- **The build:** the comment edits touch Swift files. Build iOS and the Mac
  each into a scratch `-derivedDataPath`, and grep for `warning:` as well as
  errors. Tests aren't needed for comment-only changes.
- **Read the result as a newcomer:** from `README.md` and `HANDOFF.md`
  alone, can you tell what's done, what's open, and where each open item's
  details are?

## 8. Ask the owner

- Whether to delete the finished plans outright (git history keeps them, as
  on 2026-09-27) or move them to a `docs/archive/` folder. Deleting is the
  precedent.
- Whether `AbilityReference.md` should stay, once §4's check shows how much
  the legacy engine is still used.
- Where the `pokii_xcode_integration_guide` lives (§5).
- Then propose the edits, and ask before committing and opening the PR.
