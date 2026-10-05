# Adding a Pokémon Champions Regulation

This directory holds the dev-only tooling used to ingest a new Champions
ranked-battle regulation into PK Reference. None of it ships in the app bundle — it
just generates the two JSON data files the app *does* bundle.

Follow this guide the next time a regulation (e.g. **M-D**) drops. Worked
example throughout: how **M-C** was built on top of **M-B**.

- `scrape_mc.py` — minimal per-species scraper (diagnostic; prints what it finds).
- `gen_mc.py` — **the real generator**. Copy + edit this per regulation.
- `mc_scrape.json` — cached scrape output from an `scrape_mc.py` run (disposable).

---

## Mental model

A regulation is fully described by **two bundled JSONs** plus a bit of Swift:

| Artifact | Role |
|----------|------|
| `champions-<id>.json` | Format config: legal window, rules, `species_whitelist`, `items_whitelist`, `berries_whitelist`, `mega_stones`, `regional_forms_allowed`, `banned_*`. |
| `champions-<id>-learnsets.json` | Per-species `abilities` / `stats` / `moves` / `megas[]` / `alternate_forms[]`, plus archival `move_details`. |
| `ChampionsRegulation` enum | One `case` per regulation. Everything downstream is derived from `rawValue` + the JSON. |
| `MegaForms` / `HeldItem` | Battle-engine wiring for any *new* Mega Evolutions the regulation introduces. |

A new regulation is almost always a **superset of the previous one**: same 200+
species, plus a handful of new Pokémon / items / Megas. So the generator starts
from the previous regulation's files and layers the additions on top. The
`ChampionsRegulation.current` getter picks the regulation with the newest
`valid_from` automatically, so a fresh install opens on the new format the
moment its JSON ships — no callsite changes.

**Data source:** Serebii's Champions Pokédex,
`https://www.serebii.net/pokedex-champions/<slug>/`, and the regulation page
`https://www.serebii.net/pokemonchampions/rankedbattle/regulation<id>.shtml`.

---

## Step 1 — Gather the additions from Serebii

From the regulation page, note:
- **Legal window** (`valid_from` / `valid_until`, `YYYY-MM-DD`).
- **Newly available Pokémon** (base species, regional/alt forms, new Megas).
- **Newly added items** (the page's "Newly Added Items" table). Every item a
  regulation adds stays legal in the later ones. M-B's fifteen (Life Orb, Light
  Clay, Wide Lens, …) were missed until 2026-10-05, when M-B and M-C were
  checked against Serebii's [item list](https://www.serebii.net/pokemonchampions/items.shtml);
  the newest regulation's items should match that list.

Then confirm each new species' Serebii **slug** resolves (punctuation names are
fiddly — `farfetch'd`, `mr.mime`, `sirfetch'd` worked; `farfetchd` 404s). A quick
probe:

```bash
python3 - <<'PY'
import urllib.request
UA={'User-Agent':'Mozilla/5.0'}
def ok(s):
    try:
        urllib.request.urlopen(urllib.request.Request(
            f'https://www.serebii.net/pokedex-champions/{s}/',headers=UA),timeout=15).read(); return 'OK'
    except Exception as e: return str(e).split(':')[0]
for s in ["farfetch'd","mr.mime","sirfetch'd","rillaboom"]:
    print(f'{s:14}', ok(s))
PY
```

New Mega **stone names**: check Serebii itemdex (`/itemdex/<slug>.shtml`, e.g.
`garchompitez` → "Garchompite Z"). If a stone isn't listed there, fall back to
the `<Name>ite` convention, flag it as best-effort, and recheck it once Serebii
lists it. `Golisopodite` / `Baxcaliburite` were such guesses; the game's names are
`Golisopite` / `Baxcalibrite` (fixed 2026-10-05). When a stone or item is renamed,
add the old name to `HeldItem.renamed` so sets saved under it still load.

---

## Step 2 — Configure and run the generator

Copy the template and edit the tables at the top:

```bash
cp tools/gen_mc.py tools/gen_md.py   # next reg
```

Edit these constants in the new file (all are keyed by the app's canonical
species name — **see the naming rule below**):

| Constant | What to set |
|----------|-------------|
| `main()` reads | Point `champions-m-b*.json` → the **previous** regulation's files. |
| `SLUGS` | `canonical_name -> serebii_fetch_slug` for each **new base species**. |
| `BASE_ABILITIES` | Canonical mainline base abilities per new species (also used to strip the combined ability block down to the base form). |
| `ALT_FORMS` | Regional/alt forms: `name`, canonical `abilities`, `stats`, `regional` tuple (or `None`), and `move_section` (the Serebii per-form move-table caption prefix, or `None` to inherit the base learnset). |
| `Z_MEGAS` | Second/extra Megas added to species already present in the prior reg. |
| `NEW_ITEMS`, `NEW_MEGA_STONES` | The item and `species→stone` additions. Dual/extra Megas use a `-X`/`-Y`/`-Z` key suffix (e.g. `"Garchomp-Z": "Garchompite Z"`). |
| `MC_SOURCE`, `valid_from`, `valid_until`, `format_id`, `format_name` | Update in `main()`. |

Then run it:

```bash
python3 tools/gen_md.py     # writes champions-m-d.json + champions-m-d-learnsets.json at repo root
```

The generator:
- copies **all** prior-reg species verbatim, then adds the new ones;
- appends extra Megas to existing species' `megas[]`;
- **self-validates** against a known answer (Ninetales base 67 / Alola 64 moves
  for the SV-era dexes) before doing anything — if that diff isn't empty, the
  move-section parser needs adjusting before you trust the output.

### How the scraper extracts data (so you can fix it if Serebii's HTML shifts)
- **Base stats:** the 6 `class="fooinfo">N` cells after `Base Stats - Total`.
- **Abilities:** links inside the `<b>Abilities</b>: … </td>` cell.
- **Moves:** `/attackdex-XX/<move>.shtml` links, grouped by move-table caption
  (`"Standard Moves"`, `"Egg Moves"`, and per-form `"<Form> Standard Moves"`).
  Base = captions with no form keyword; a form = captions starting with its name.
- **Megas:** each `<td class="fooevo"><h3>Mega …</h3>` block, followed by its own
  Abilities + Base Stats. Handles multiple Megas per species (incl. novel "Z" Megas).

---

## Step 3 — ⚠️ The species-naming rule (easy to get wrong)

The Mon Index roster filter, `ChampionsLearnsetStore`, and `ChampionsValidator`
all key species by **`PKMN.name`**, which `pokedbPopulator` sets to
`pokemon_species.name.capitalized` — i.e. Swift's `.capitalized` of the
lowercase-hyphenated PokeAPI slug. **The whitelist and learnset keys must match
that exact string**, not the pretty Serebii form:

| PokeAPI slug | `PKMN.name` (use this) | ❌ pretty form (never matches) |
|--------------|------------------------|-------------------------------|
| `mr-mime`    | `Mr-Mime`              | `Mr. Mime` |
| `farfetchd`  | `Farfetchd`            | `Farfetch'd` |
| `sirfetchd`  | `Sirfetchd`            | `Sirfetch'd` |
| `kommo-o`    | `Kommo-O`              | `Kommo-o` |

M-A/M-B use the pretty forms for `Mr. Rime`/`Kommo-o` and those species silently
**don't appear** in the Mon Index — a latent bug; don't copy that pattern.
Verify with `RunCodeSnippet`: `"mr-mime".capitalized` → `Mr-Mime`. The pretty
slug (e.g. `mr.mime`) is only the Serebii fetch slug, kept in `SLUGS`'s value.

---

## Step 4 — Register the enum

In `PKReference/ChampionsRegulation.swift`:
- add `case mD = "m-d"` to the enum;
- add `case .mD: return "Regulation M-D"` in `displayName`.

In `PKReference/IntentEntities.swift`, so Siri's Check Legality can name it:
- add `case mD = "m-d"` to `RegulationChoice`, and `.mD: "Regulation M-D"`
  to its `caseDisplayRepresentations`. App Intents needs these written out;
  `AppIntentsTests` fails until they match the enum.

Nothing else — bundle names, legal-period parsing, `latest`/`current`, the
whitelist cache, and the Settings picker are all derived automatically.

---

## Step 5 — Wire any new Mega Evolutions into the battle engine

Only if the regulation introduces Megas not already in `MegaForms.all`.

- `PKReference/mega_forms.json` — add an entry per new Mega (the file's
  `about` explains each key) with the scraped type / stats / ability.
  `species_key` is `BattleSimSeed.normalize(species)` (lowercase). Its `stone`
  becomes a held item from that entry; there's no Swift to add. Extra Megas on
  an existing species (X/Y/Z) are just additional entries with the same
  `species_key` and a different `stone`. A stone named like a built-in item
  fails the file.

Novel abilities (e.g. `aura-guard`) get an identifier but have **no engine
effect** until `computeAbilityModifiers` ports them — this is expected and
already true for the M-B/M-C Champions Megas.

---

## Step 6 — Add the JSONs to the app bundle (manual — Xcode)

The champions JSONs are referenced **individually** in `project.pbxproj` (not a
synced folder), and that file **must not be edited by tooling while Xcode is
open**. In Xcode:

1. **File ▸ Add Files to "PKReference"…**, pick the two new files at the repo root.
2. Uncheck **Copy items if needed**; check the **PKReference** app target.
3. Confirm they sit in the same group as `champions-m-b.json` and appear under
   **Build Phases ▸ Copy Bundle Resources**.

---

## Step 7 — Verify

**JSON integrity** (adapt the filenames):

```bash
python3 - <<'PY'
import json
cfg=json.load(open('champions-m-d.json')); ln=json.load(open('champions-m-d-learnsets.json'))
wl=set(cfg['species_whitelist']); sp=ln['species']
assert not [s for s in wl if s not in sp], 'whitelisted species missing a learnset'
vals=list(cfg['mega_stones'].values()); assert len(vals)==len(set(vals)), 'duplicate stone name'
# Every Mega the learnsets list needs its stone in mega_stones: the validator's
# legal items and Team Search's Megas both come from it (Dragoninite was missing
# from M-A to M-C). RegulationRulesTests checks this too.
stone={f['display_name']:f.get('stone') for f in json.load(open('PKReference/mega_forms.json'))['forms']}
megas=[m['name'] for e in sp.values() for m in e.get('megas') or []]
print('Megas without their stone (should be []):', sorted(m for m in megas if stone.get(m) not in set(vals)))
prev=set(json.load(open('champions-m-c.json'))['species_whitelist'])
print('dropped from prior reg (should be []):', sorted(prev-wl))
print('counts — species', len(sp), 'whitelist', len(wl), 'items', len(cfg['items_whitelist']))
PY
```

**Build:** `BuildProject` (xcode-tools MCP) — catches any exhaustive `switch`
over `HeldItem` that the new cases break.

**Runtime load test:** `RunCodeSnippet` against `PKReference/ChampionsRegulation.swift`:

```swift
let reg = ChampionsRegulation.mD
print(ChampionsRegulation.current.rawValue)              // expect m-d
print(reg.speciesWhitelist().count)
print(ChampionsLearnsetStore.store(for: reg).data(for: "SomeNewMon") != nil)
print(ChampionsValidator(regulation: reg) != nil)
print(MegaForms.form(forSpecies: "somemon", heldItem: .someNewStone, moveNames: [])?.displayName ?? "nil")
```

**Manual:** launch the app — Settings shows the new regulation as the default;
the Mon Index lists the new species; a filter finds one of them.

---

## Notes & gotchas
- `move_details` in the learnsets JSON is **archival only** — no Swift code reads
  it (comment reference in `03_ChampionsValidator.swift`). Carrying the prior
  reg's map forward is fine.
- Regional forms (Alola/Galar/Hisui/Paldea) also go in `regional_forms_allowed`;
  non-regional formes (Low Key, Female, plumages) live only in `alternate_forms`.
- Serebii lists all forms' abilities in one combined block, so alt-form abilities
  are taken from canonical mainline data (product decision), not scraped-split.
- Assume additive (no species removed) unless the regulation page says otherwise;
  the integrity check above prints anything dropped so you can eyeball it.
- Keep these `tools/` scripts out of the app target.
