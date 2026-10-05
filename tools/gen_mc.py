#!/usr/bin/env python3
"""Generate the Regulation M-C data files from M-B + Serebii Champions dex.

>>> This is the reusable template for ingesting a new regulation. Copy it to
    gen_<id>.py and edit the tables below. Full workflow: tools/README.md <<<


Read-only network scrape of https://www.serebii.net/pokedex-champions/<slug>/.
Writes:
  champions-m-c.json            (M-B config + M-C additions)
  champions-m-c-learnsets.json  (all M-B species + 23 new + Z-megas)

The 208 M-B species are copied verbatim; only the additions are scraped.
Alternate-form abilities/stats use canonical mainline values (per product
decision) since the Champions dex lists all forms' abilities in one block;
form-specific move lists are parsed from the page's per-form move sections
when present, otherwise they inherit the base learnset.
"""
import urllib.request, re, json, html as H, datetime, sys

UA = {"User-Agent": "Mozilla/5.0"}
STAT_KEYS = ["hp", "atk", "def", "spa", "spd", "spe"]

# species-key (must equal PKMN.name = PokeAPI slug `.capitalized`, since the
# Mon Index / validator / learnset store all key on that) -> Serebii fetch slug.
# For punctuation names the two differ: PKMN.name is "Farfetchd"/"Mr-Mime"/
# "Sirfetchd" (Swift `.capitalized` strips no punctuation but PokeAPI's slug has
# none), while Serebii's page slug keeps the apostrophe/dot.
SLUGS = {
    "Wigglytuff": "wigglytuff", "Persian": "persian", "Farfetchd": "farfetch'd",
    "Mr-Mime": "mr.mime", "Swalot": "swalot", "Salamence": "salamence",
    "Gogoat": "gogoat", "Golisopod": "golisopod", "Rillaboom": "rillaboom",
    "Cinderace": "cinderace", "Inteleon": "inteleon", "Thievul": "thievul",
    "Toxtricity": "toxtricity", "Grapploct": "grapploct", "Perrserker": "perrserker",
    "Sirfetchd": "sirfetch'd", "Pincurchin": "pincurchin", "Indeedee": "indeedee",
    "Pawmot": "pawmot", "Arboliva": "arboliva", "Squawkabilly": "squawkabilly",
    "Mabosstiff": "mabosstiff", "Baxcalibur": "baxcalibur",
}

# Canonical mainline base abilities per new species (used to strip the combined
# ability block down to the *base* form; alt-form abilities handled below).
BASE_ABILITIES = {
    "Wigglytuff": ["Cute Charm", "Competitive", "Frisk"],
    "Persian": ["Limber", "Technician", "Unnerve"],
    "Farfetchd": ["Keen Eye", "Inner Focus", "Defiant"],
    "Mr-Mime": ["Soundproof", "Filter", "Technician"],
    "Swalot": ["Liquid Ooze", "Sticky Hold", "Gluttony"],
    "Salamence": ["Intimidate", "Moxie"],
    "Gogoat": ["Sap Sipper", "Grass Pelt"],
    "Golisopod": ["Emergency Exit"],
    "Rillaboom": ["Overgrow", "Grassy Surge"],
    "Cinderace": ["Blaze", "Libero"],
    "Inteleon": ["Torrent", "Sniper"],
    "Thievul": ["Run Away", "Unburden", "Stakeout"],
    "Toxtricity": ["Punk Rock", "Plus", "Technician"],
    "Grapploct": ["Limber", "Technician"],
    "Perrserker": ["Battle Armor", "Tough Claws", "Steely Spirit"],
    "Sirfetchd": ["Steadfast", "Scrappy"],
    "Pincurchin": ["Lightning Rod", "Electric Surge"],
    "Indeedee": ["Inner Focus", "Synchronize", "Psychic Surge"],
    "Pawmot": ["Volt Absorb", "Natural Cure", "Iron Fist"],
    "Arboliva": ["Seed Sower", "Harvest"],
    "Squawkabilly": ["Intimidate", "Hustle", "Guts"],
    "Mabosstiff": ["Intimidate", "Guard Dog", "Stakeout"],
    "Baxcalibur": ["Thermal Exchange", "Ice Body"],
}

# Alternate forms: canonical mainline abilities + stats. `move_section` is the
# caption prefix of the form's move table on the Serebii page (None => inherits
# the base learnset). `regional` flags entries that also belong in
# regional_forms_allowed.
ALT_FORMS = {
    "Persian": [{
        "name": "Alola Form", "regional": ("Persian", "Alola"),
        "abilities": ["Fur Coat", "Technician", "Rattled"],
        "stats": {"hp": 65, "atk": 60, "def": 65, "spa": 75, "spd": 65, "spe": 115},
        "move_section": "Alola Form",
    }],
    "Toxtricity": [{
        "name": "Low Key Form", "regional": None,
        "abilities": ["Punk Rock", "Minus", "Technician"],
        "stats": {"hp": 75, "atk": 98, "def": 70, "spa": 114, "spd": 70, "spe": 75},
        "move_section": None,
    }],
    "Indeedee": [{
        "name": "Female Form", "regional": None,
        "abilities": ["Own Tempo", "Synchronize", "Psychic Surge"],
        "stats": {"hp": 70, "atk": 55, "def": 65, "spa": 95, "spd": 105, "spe": 85},
        "move_section": None,
    }],
    "Squawkabilly": [{
        "name": "White/Blue Plumage", "regional": None,
        "abilities": ["Intimidate", "Hustle", "Sheer Force"],
        "stats": {"hp": 82, "atk": 96, "def": 51, "spa": 45, "spd": 51, "spe": 92},
        "move_section": None,
    }],
}

# Second ("Z") Megas added to species already present in M-B.
Z_MEGAS = {
    "Garchomp": {"slug": "garchomp", "mega": "Mega Garchomp Z"},
    "Lucario":  {"slug": "lucario",  "mega": "Mega Lucario Z"},
    "Absol":    {"slug": "absol",    "mega": "Mega Absol Z"},
}

NEW_ITEMS = [
    "Leek", "Rocky Helmet", "Air Balloon", "Red Card", "Binding Band",
    "Eject Button", "Normal Gem", "Terrain Extender", "Electric Seed",
    "Psychic Seed", "Misty Seed", "Grassy Seed",
]

NEW_MEGA_STONES = {
    "Salamence": "Salamencite",
    "Golisopod": "Golisopite",
    "Baxcalibur": "Baxcalibrite",
    "Garchomp-Z": "Garchompite Z",
    "Lucario-Z": "Lucarionite Z",
    "Absol-Z": "Absolite Z",
}

MC_SOURCE = "https://www.serebii.net/pokemonchampions/rankedbattle/regulationm-c.shtml"


def fetch(slug):
    url = f"https://www.serebii.net/pokedex-champions/{slug}/"
    return urllib.request.urlopen(
        urllib.request.Request(url, headers=UA), timeout=30
    ).read().decode("utf-8", "replace")


def parse_stats_at(h, idx):
    cells = re.findall(r'class="fooinfo">(\d+)</td>', h[idx: idx + 700])
    if len(cells) < 6:
        return None
    return dict(zip(STAT_KEYS, (int(x) for x in cells[:6])))


def parse_ability_block(h, idx):
    m = re.search(r"<b>Abilities</b>:(.*?)</td>", h[idx: idx + 1200], re.S)
    if not m:
        return []
    return [H.unescape(n).strip() for n in
            re.findall(r'/abilitydex/[a-z0-9\-]+\.shtml"><b>([^<]+)</b>', m.group(1))]


def move_sections(h):
    """Return list of (caption, start_pos) for every move table on the page."""
    out = []
    for m in re.finditer(r">([^<>]{0,40}?Moves)<", h):
        cap = m.group(1).strip()
        if "Anchor" in cap:
            continue
        out.append((cap, m.start()))
    return out


FORM_KEYWORDS = ("Alola", "Alolan", "Galar", "Galarian", "Hisui", "Hisuian",
                 "Paldea", "Paldean", "Low Key", "Female", "Plumage", "Midnight",
                 "Dusk")


def parse_moves(h, section_prefix=None):
    """Moves in the given form's sections. section_prefix=None => base sections
    (captions with no form keyword). Otherwise sections whose caption starts
    with section_prefix."""
    secs = move_sections(h)
    # Boundary after the last move table = start of the stats area.
    stats_idx = h.find("<h2>Stats")
    if stats_idx < 0:
        stats_idx = len(h)
    picked = []
    for i, (cap, pos) in enumerate(secs):
        end = secs[i + 1][1] if i + 1 < len(secs) else stats_idx
        is_form = any(k in cap for k in FORM_KEYWORDS)
        if section_prefix is None:
            if is_form:
                continue
        else:
            if not cap.startswith(section_prefix):
                continue
        seg = h[pos:end]
        for mv in re.findall(r'/attackdex-[a-z]+/[a-z0-9\-]+\.shtml"[^>]*>([^<]+)</a>', seg):
            picked.append(H.unescape(mv).strip())
    return sorted(set(picked))


def parse_megas(h):
    megas = []
    seen = set()
    for m in re.finditer(r'<td class="fooevo"[^>]*><h3>(Mega [^<]+)</h3>', h):
        name = H.unescape(m.group(1)).strip()
        if name in seen:
            continue
        seen.add(name)
        s = m.end()
        ab_i = h.find("<b>Abilities</b>", s)
        bs_i = h.find("Base Stats - Total", s)
        megas.append({
            "name": name,
            "abilities": parse_ability_block(h, ab_i) if ab_i >= 0 else [],
            "stats": parse_stats_at(h, bs_i) if bs_i >= 0 else None,
        })
    return megas


def scrape_species(display, slug):
    h = fetch(slug)
    ab_i = h.find("<b>Abilities</b>")
    bs_i = h.find("Base Stats - Total")
    entry = {
        "name": display,
        "abilities": BASE_ABILITIES.get(display) or (
            parse_ability_block(h, ab_i) if ab_i >= 0 else []),
        "stats": parse_stats_at(h, bs_i) if bs_i >= 0 else None,
        "moves": parse_moves(h, None),
        "megas": [{"name": mg["name"], "abilities": mg["abilities"],
                   "stats": mg["stats"]} for mg in parse_megas(h)],
        "alternate_forms": [],
    }
    for af in ALT_FORMS.get(display, []):
        moves = (parse_moves(h, af["move_section"]) if af["move_section"]
                 else entry["moves"])
        entry["alternate_forms"].append({
            "name": af["name"], "abilities": af["abilities"],
            "stats": af["stats"], "moves": moves,
        })
    return h, entry


def main():
    mb_cfg = json.load(open("champions-m-b.json"))
    mb_learn = json.load(open("champions-m-b-learnsets.json"))

    # ---- validate scraper against a known M-B answer (Ninetales) ----
    hn = fetch("ninetales")
    base_n = parse_moves(hn, None)
    alt_n = parse_moves(hn, "Alola Form")
    mbn = mb_learn["species"]["Ninetales"]
    exp_base = set(mbn["moves"])
    exp_alt = set(m for af in mbn["alternate_forms"] for m in af["moves"])
    print(f"[validate] Ninetales base {len(base_n)} vs M-B {len(exp_base)} "
          f"| Alola {len(alt_n)} vs {len(exp_alt)}", file=sys.stderr)
    if set(base_n) != exp_base or set(alt_n) != exp_alt:
        print("  base diff+:", sorted(set(base_n) - exp_base), file=sys.stderr)
        print("  base diff-:", sorted(exp_base - set(base_n)), file=sys.stderr)
        print("  alt  diff+:", sorted(set(alt_n) - exp_alt), file=sys.stderr)
        print("  alt  diff-:", sorted(exp_alt - set(alt_n)), file=sys.stderr)

    # ---- scrape new species ----
    new_entries = {}
    for display, slug in SLUGS.items():
        _, entry = scrape_species(display, slug)
        new_entries[display] = entry
        print(f"[ok] {display:12} stats={entry['stats']} #moves={len(entry['moves'])}"
              f" megas={[m['name'] for m in entry['megas']]}"
              f" alt={[a['name'] for a in entry['alternate_forms']]}", file=sys.stderr)

    # ---- Z-megas appended to existing species ----
    z_entries = {}
    for host, info in Z_MEGAS.items():
        h = fetch(info["slug"])
        for mg in parse_megas(h):
            if mg["name"] == info["mega"]:
                z_entries[host] = mg
                print(f"[z]  {host}: {mg['name']} ab={mg['abilities']} stats={mg['stats']}",
                      file=sys.stderr)

    # ---- assemble learnsets ----
    learn = {
        "format_id": "champions-m-c",
        "source": "https://www.serebii.net/pokedex-champions",
        "scraped_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "species": dict(mb_learn["species"]),  # all 208 verbatim
        "move_details": mb_learn.get("move_details", {}),
    }
    for name, entry in new_entries.items():
        learn["species"][name] = entry
    for host, mega in z_entries.items():
        sp = learn["species"][host]
        if all(m["name"] != mega["name"] for m in sp.get("megas", [])):
            sp.setdefault("megas", []).append(mega)

    with open("champions-m-c-learnsets.json", "w") as f:
        json.dump(learn, f, indent=2, ensure_ascii=False)

    # ---- assemble config ----
    cfg = dict(mb_cfg)
    cfg["format_id"] = "champions-m-c"
    cfg["format_name"] = "Pokemon Champions Regulation M-C"
    cfg["valid_from"] = "2026-09-09"
    cfg["valid_until"] = "2026-12-02"
    cfg["source"] = MC_SOURCE
    cfg["species_whitelist"] = sorted(set(mb_cfg["species_whitelist"]) | set(SLUGS.keys()))
    cfg["items_whitelist"] = sorted(set(mb_cfg["items_whitelist"]) | set(NEW_ITEMS))
    cfg["mega_stones"] = {**mb_cfg["mega_stones"], **NEW_MEGA_STONES}
    reg = list(mb_cfg.get("regional_forms_allowed", []))
    for af_list in ALT_FORMS.values():
        for af in af_list:
            if af.get("regional"):
                b, fm = af["regional"]
                if not any(r["base"] == b and r["form"] == fm for r in reg):
                    reg.append({"base": b, "form": fm})
    cfg["regional_forms_allowed"] = reg

    with open("champions-m-c.json", "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)

    print(f"\n[done] whitelist {len(mb_cfg['species_whitelist'])} -> "
          f"{len(cfg['species_whitelist'])}; items -> {len(cfg['items_whitelist'])}; "
          f"stones -> {len(cfg['mega_stones'])}", file=sys.stderr)


if __name__ == "__main__":
    main()
