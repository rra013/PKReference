#!/usr/bin/env python3
"""Builds the backend's study guide, backend/docs/PKReference-backend-guide.pdf, and the diagram
beside it, backend/docs/architecture.svg.

    python3 backend/docs/study-guide/build_study_guide.py

What is rebuilt from the code on every run, so it can't drift from it:

- Part 8, the file-by-file reference: every class, annotation and method, with its explanation,
  read out of the Java sources' own comments (java_comment_reader.py). Change a comment or add a
  method, run this again, and the guide follows.
- "Where each file sits" in Part 1, the table of test classes in Part 9, and the counts quoted in
  the text.

What is written by hand, and changes only when someone edits it:

- The chapters (chapters/*.html): the walkthroughs, Spring, Kafka, the database, signing in, the
  API and the questions. There is no 08: Part 8 is the generated reference.
- The architecture diagram (architecture_diagram.py): a new class, topic or table needs adding
  there, and usually a line in a chapter too.

The PDF is made with macOS's WebKit (html_to_pdf.swift, compiled on first use); no browser is
launched. Without Swift, as on Linux, it stops after writing the HTML into build/, which any
browser can print.
"""
import datetime
import glob
import html
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(BACKEND, "src/main/java/com/pkreference/backend")
TESTS = os.path.join(BACKEND, "src/test/java/com/pkreference/backend")
OUT = os.path.join(HERE, "build")
PDF = os.path.join(os.path.dirname(HERE), "PKReference-backend-guide.pdf")

sys.path.insert(0, HERE)
import architecture_diagram as diagram   # noqa: E402
import java_comment_reader as javaref   # noqa: E402

# The packages, in the order the data flows through them, each with a few words of introduction.
PACKAGES = [
    ("", "The application", "One class: where the program starts and what Spring builds from."),
    ("config", "config: set-up shared by everything",
     "The Kafka topics, what happens when a listener fails, the helper that makes sends throw, and the two "
     "settings records for the sources."),
    ("model", "model: the shapes of the data",
     "Records only. They define the JSON read from Limitless, carried on the Kafka topics and, for the ladder, "
     "stored and served."),
    ("ingest", "ingest: from Limitless to Kafka",
     "The first half of the write path for tournaments: decide what to fetch, fetch it without breaking the "
     "rate limit, publish it."),
    ("store", "store: from Kafka to Postgres",
     "The second half: the listeners that read the fetched topics and the repository that writes events, teams "
     "and matches."),
    ("standardize", "standardize: one spelling for every name",
     "Players type their teams by hand. These classes turn what they typed into canonical item, ability and "
     "move names, and into the app's species keys. Ported from the app, and checked against it by golden files."),
    ("insight", "insight: the tournament API",
     "The read path for tournament data: SQL in the repository, counting in the service, HTTP in the controller, "
     "and the records that define the answers."),
    ("corpus", "corpus: stored events in Limitless's own shape",
     "Two endpoints that let the app build its Team Search data from the server with the code it uses for "
     "Limitless."),
    ("ladder", "ladder: Smogon's monthly stats",
     "A second, smaller pipeline with the same parts as the first: a client, a scheduled discovery, a reducer, "
     "a topic, a store, a service and a controller."),
    ("security", "security: signing in",
     "A servlet filter that checks every request, a service that issues and verifies tokens, the endpoint that "
     "trades a key for a token, and the configuration that wires them."),
    ("usage", "usage: the first version's counters",
     "All-time counts kept with JPA. Superseded by the team store and the insights, still running, and the "
     "plainest example here of consume, transact, produce."),
    ("api", "api: the first version's endpoint", "Serves the counters at /api/usage."),
]

OTHER_FILES = [
    ("pom.xml", "The Maven build: the Spring Boot parent (which manages versions), the dependencies, and a "
     "resources section that copies the app's data files (champions-*.json, showdown-champions-data.json, "
     "team_search_vocab.json) from the repository into the jar under regulations/, so the server and the app "
     "read the same lists."),
    ("src/main/resources/application.yml", "Every setting: the data source, JPA, the scheduler's pool, the Kafka "
     "producer and consumer, and the project's own blocks (pkref.limitless, pkref.smogon, pkref.api). Part 4.5 "
     "and Part 10.2 explain the values."),
    ("src/main/resources/db/migration/V1__usage_counters.sql", "The first version's two tables: usage_counter and "
     "processed_tournament."),
    ("src/main/resources/db/migration/V2__events_teams_pairings.sql", "event_fetch and the team store: event, "
     "event_phase, team, team_member, team_member_move, pairing, pairing_fetch."),
    ("src/main/resources/db/migration/V3__team_member_species.sql", "Adds species_key and mega_stone to team_member, "
     "with an index on the key."),
    ("src/main/resources/db/migration/V4__store_version.sql", "The one-row store_version table the insights' cache "
     "is keyed on."),
    ("src/main/resources/db/migration/V5__ladder_stats.sql", "ladder_stats: one row per format, month and rating."),
    ("src/main/resources/reference/champions-items.json", "A snapshot of every Champions item's name, for "
     "NameStandardizer."),
    ("docker-compose.yml", "Local development: Kafka (one KRaft node), Kafka UI and Postgres, each published on "
     "127.0.0.1 only, with named volumes so data survives a restart."),
    ("docker-compose.server.yml", "Layered on top for a server: adds the API as a container, memory limits, "
     "restart policies, a health check for Postgres, and requires a real password and at least one API key hash."),
    ("Dockerfile", "A two-stage build: Maven and a JDK build the jar; a JRE image runs it as a non-root user."),
    ("scripts/new-api-key.sh", "Prints a new API key and its SHA-256 hash. The key goes into the app, the hash "
     "into the server's settings."),
    ("scripts/backup.sh", "A compressed pg_dump of the database, kept 14 days, for a daily cron job."),
    ("../.github/workflows/backend.yml", "CI: runs mvn verify on every push and pull request that touches the "
     "backend or the data files it bundles."),
]


def esc(text):
    return html.escape(text, quote=False)


def strip_annotations(sig):
    """A signature without the annotations inside it (@Schema(...) on a record's components)."""
    out, i = [], 0
    while i < len(sig):
        if sig[i] == "@" and re.match(r"@\w+", sig[i:]):
            j = i + re.match(r"@[\w.]+", sig[i:]).end()
            if j < len(sig) and sig[j] == "(":
                depth = 0
                while True:
                    if sig[j] == "(":
                        depth += 1
                    elif sig[j] == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                j += 1
            i = j
            while i < len(sig) and sig[i] == " ":
                i += 1
        else:
            out.append(sig[i])
            i += 1
    return re.sub(r"\s+", " ", "".join(out)).replace("( ", "(").strip()


def schema_description(annotations):
    """The text of an @Schema(description = ...) annotation, for records documented that way."""
    for a in annotations:
        if not a.startswith("@Schema"):
            continue
        m = re.search(r'description\s*=\s*"""(.*?)"""', a, re.S)
        if m:
            return re.sub(r"\\\s*", " ", m.group(1)).strip()
        parts = re.findall(r'"((?:[^"\\]|\\.)*)"', a.split("example")[0])
        if parts:
            return "".join(parts).replace('\\"', '"').strip()
    return ""


def short_annotation(a):
    """Annotations as shown beside a signature: the long documentation-only ones are left out."""
    name = re.match(r"@[\w.]+", a).group(0)
    if name in ("@Tag", "@Operation", "@Schema", "@Parameter", "@SuppressWarnings", "@Override", "@JsonIgnore"):
        return None if name != "@Override" else "@Override"
    return a if len(a) <= 170 else name + "(…)"


def member_html(item, level=0):
    kind = item["kind"]
    sig = strip_annotations(item["signature"])
    annotations = [x for x in (short_annotation(a) for a in item["annotations"]) if x]
    doc = item["doc"]
    if not doc:
        described = schema_description(item["annotations"])
        if described:
            doc = "<p>" + esc(described) + "</p>"
    if kind == "field":
        if not doc:
            return ""
        sig = sig.split(" = ")[0] if len(sig) > 110 else sig
    if kind == "constants":
        return f'<div class="member"><div class="sig">{esc(sig)}</div><p class="small">The enum\'s values.</p></div>'
    if kind == "method" and not doc:
        if re.match(r"^(private|protected) \w+\(\)$", sig):
            return ""                                     # a namespace class's private constructor
        if re.match(r"^public \w[\w<>\[\], ]* (get|is)\w+\(\)$", sig):
            doc = '<p class="small">Returns the field.</p>'
    ann = "".join(f'<span class="ann">{esc(a)}</span> ' for a in annotations)
    out = [f'<div class="member level{level}"><div class="sig">{ann}{esc(sig)}</div>{doc}']
    for sub in item.get("members", []):
        out.append(member_html(sub, level + 1))
    out.append("</div>")
    return "".join(out)


def file_html(path):
    parsed = javaref.parse(path)
    name = os.path.basename(path)
    rel = os.path.relpath(path, BACKEND)
    out = [f'<section class="file"><h3 id="{name}">{esc(name)}</h3><p class="path">{esc(rel)}</p>']
    for t in parsed["types"]:
        annotations = [x for x in (short_annotation(a) for a in t["annotations"]) if x]
        ann = "".join(f'<span class="ann">{esc(a)}</span> ' for a in annotations)
        out.append(f'<div class="type"><div class="sig typesig">{ann}{esc(strip_annotations(t["signature"]))}</div>')
        out.append(t["doc"] or "")
        fields = [m for m in t.get("members", []) if m["kind"] == "field" and m["doc"]]
        others = [m for m in t.get("members", []) if m["kind"] != "field"]
        if fields:
            out.append('<h4>Fields and constants</h4>')
            out += [member_html(m) for m in fields]
        if others:
            out.append('<h4>Members</h4>')
            out += [member_html(m) for m in others]
        out.append("</div>")
    out.append("</section>")
    return "".join(out)


def first_sentence(doc_html):
    text = re.sub(r"<[^>]+>", "", doc_html)
    text = html.unescape(re.sub(r"\s+", " ", text)).strip()
    m = re.match(r"(.+?\.)(\s|$)", text)
    sentence = m.group(1) if m else text
    return sentence if len(sentence) <= 190 else sentence[:187].rsplit(" ", 1)[0] + "…"


def java_files(package):
    folder = os.path.join(SRC, package) if package else SRC
    return sorted(p for p in glob.glob(os.path.join(folder, "*.java")))


def reference_html():
    out = ['<h1 id="part8">Part 8. File by file</h1>',
           '<p>Every source file, in the order the data flows through them. For each: what the class is, its '
           'annotations, and every method with what it does. This part is generated from the comments in the '
           'code itself, so what you read here is what you will see when the file is open in front of you.</p>']
    for package, title, intro in PACKAGES:
        files = java_files(package)
        out.append(f'<h2 class="package">{esc(title)}</h2><p>{esc(intro)}</p>')
        for path in files:
            out.append(file_html(path))
    out.append('<h2 class="package">The files that aren\'t Java</h2><table class="tight"><tr><th>File</th><th>What it is</th></tr>')
    for path, text in OTHER_FILES:
        out.append(f'<tr><td><code>{esc(path)}</code></td><td>{esc(text)}</td></tr>')
    out.append("</table>")
    return "".join(out)


def tree_html():
    """Where each file sits: the source tree, each class with the first sentence of its comment."""
    out = ['<h2>Where each file sits</h2>',
           '<p>The source tree, with one line for each class. The packages are listed in the order data flows '
           'through them, not alphabetically.</p>',
           '<p class="path">backend/src/main/java/com/pkreference/backend/</p><table class="tree">']
    for package, title, _ in PACKAGES:
        files = java_files(package)
        out.append(f'<tr class="pkg"><td colspan="2">{esc(package + "/" if package else "(the root package)")}</td></tr>')
        for path in files:
            parsed = javaref.parse(path)
            doc = parsed["types"][0]["doc"] if parsed["types"] else ""
            out.append(f'<tr><td><code>{esc(os.path.basename(path)[:-5])}</code></td><td>{esc(first_sentence(doc))}</td></tr>')
    out.append("</table>")
    return "".join(out)


def tests():
    """The table of test classes, how many tests run in all, and in how many classes. A class that
    extends a shared base (the same tests on H2 and on Postgres) runs the base's tests too."""
    found = {}
    for path in sorted(glob.glob(os.path.join(TESTS, "**", "*.java"), recursive=True)):
        src = open(path, encoding="utf-8").read()
        name = os.path.basename(path)[:-5]
        parsed = javaref.parse(path)
        top = parsed["types"][0] if parsed["types"] else {"doc": "", "signature": ""}
        parent = re.search(r"\bextends (\w+)", top["signature"])
        found[name] = {"rel": os.path.relpath(path, TESTS)[:-5], "own": len(re.findall(r"^\s*@Test\b", src, re.M)),
                       "doc": first_sentence(top["doc"]), "abstract": "abstract " in top["signature"],
                       "parent": parent.group(1) if parent else None}
    rows, total, classes = [], 0, 0
    for name, t in found.items():
        inherited = found[t["parent"]]["own"] if t["parent"] in found else 0
        runs = 0 if t["abstract"] else t["own"] + inherited
        if t["abstract"]:
            note = f'{t["own"]}, run by its subclasses'
        elif runs:
            note = str(runs)
        else:
            note = "helpers"
        rows.append((t["rel"], note, t["doc"]))
        total += runs
        classes += 1 if runs else 0
    table = ['<table class="tight"><tr><th>Class</th><th>Tests</th><th>What it covers</th></tr>']
    for rel, note, sentence in rows:
        table.append(f'<tr><td><code>{esc(rel)}</code></td><td>{esc(note)}</td><td>{esc(sentence)}</td></tr>')
    table.append("</table>")
    return "".join(table), total, classes


def stats():
    files = glob.glob(os.path.join(SRC, "**", "*.java"), recursive=True)
    lines = sum(len(open(p, encoding="utf-8").read().split("\n")) for p in files)
    return len(files), lines


CSS = """
body { font: 10.2pt/1.45 -apple-system, "Helvetica Neue", Arial, sans-serif; color: #212529; margin: 0; }
h1 { font-size: 21pt; margin: 0 0 10pt; padding-bottom: 5pt; border-bottom: 2px solid #3b5bdb; break-before: page; }
h1.first { break-before: auto; }
h2 { font-size: 14pt; margin: 18pt 0 6pt; color: #1c3faa; break-after: avoid; }
h2.package { font-size: 15pt; margin-top: 22pt; padding: 5pt 8pt; background: #e7f1ff; border-left: 4px solid #3b5bdb; color: #1c3faa; }
h3 { font-size: 12.5pt; margin: 16pt 0 1pt; break-after: avoid; }
h4 { font-size: 9pt; text-transform: uppercase; letter-spacing: .06em; color: #868e96; margin: 9pt 0 3pt; break-after: avoid; }
p { margin: 0 0 6pt; }
ul, ol { margin: 0 0 7pt; padding-left: 18pt; }
li { margin-bottom: 2.5pt; }
code, pre, .sig { font-family: "SF Mono", Menlo, Consolas, monospace; font-size: 8.6pt; }
code { background: #f1f3f5; padding: 0 2.5pt; border-radius: 3px; }
pre { background: #f8f9fa; border: 1px solid #dee2e6; border-radius: 5px; padding: 7pt 9pt; white-space: pre-wrap; margin: 0 0 8pt; break-inside: avoid; }
table { border-collapse: collapse; width: 100%; margin: 4pt 0 10pt; font-size: 9.3pt; }
th, td { border: 1px solid #ced4da; padding: 3.5pt 6pt; vertical-align: top; text-align: left; }
th { background: #f1f3f5; }
tr { break-inside: avoid; }
table.tight { font-size: 8.8pt; }
table.tree td { border: none; border-bottom: 1px solid #e9ecef; padding: 2.5pt 6pt; font-size: 8.9pt; }
table.tree tr.pkg td { background: #e7f1ff; font-weight: 700; color: #1c3faa; font-family: "SF Mono", Menlo, monospace; font-size: 8.8pt; }
table.tree td:first-child { white-space: nowrap; width: 1%; }
dl { margin: 0 0 8pt; }
dt { font-weight: 700; margin-top: 5pt; }
dd { margin: 0 0 0 14pt; }
.why { background: #fff9db; border-left: 3px solid #f08c00; padding: 5pt 8pt; }
.path { font-family: "SF Mono", Menlo, monospace; font-size: 8pt; color: #868e96; margin: 0 0 4pt; }
.small { font-size: 8.8pt; color: #868e96; margin: 0; }
ol.steps > li { margin-bottom: 5pt; }
.qa .q { font-weight: 700; margin: 10pt 0 2pt; color: #1c3faa; break-after: avoid; }
section.file { margin-bottom: 6pt; }
.type { margin-bottom: 4pt; }
.sig { background: #f8f9fa; border: 1px solid #dee2e6; border-left: 3px solid #868e96; border-radius: 3px; padding: 3pt 6pt; margin: 6pt 0 3pt; white-space: pre-wrap; word-break: break-word; break-after: avoid; }
.typesig { border-left-color: #3b5bdb; background: #edf2ff; font-weight: 600; }
.ann { color: #c2255c; }
.member { margin-left: 0; break-inside: avoid; }
.member p, .type > p { margin-left: 2pt; }
.member ul, .type > ul { margin-left: 2pt; }
.member.level1 { margin-left: 14pt; }
.member.level2 { margin-left: 28pt; }
.cover { text-align: left; padding-top: 150pt; }
.cover .title { font-size: 34pt; font-weight: 800; line-height: 1.1; }
.cover .subtitle { font-size: 15pt; color: #495057; margin-top: 12pt; }
.cover .meta { margin-top: 60pt; color: #868e96; font-size: 10pt; }
.toc { break-before: page; }
.toc ol { list-style: none; padding: 0; }
.toc li { padding: 4pt 0; border-bottom: 1px solid #e9ecef; }
.toc .n { display: inline-block; width: 46pt; color: #3b5bdb; font-weight: 700; }
.toc .d { color: #868e96; font-size: 9pt; margin-left: 46pt; display: block; }
"""

TOC = [
    ("Part 1", "The system in ten minutes", "What it does, the stack, the architecture diagram, and where each file sits."),
    ("Part 2", "Follow the data", "An event, a ladder month and an API request, step by step with class and method names. What happens on failure."),
    ("Part 3", "Spring, as this project uses it", "Beans, @Bean and @Component, settings, timers, Kafka listeners, the web and database layers."),
    ("Part 4", "Kafka, as this project uses it", "Topics, keys, groups, compaction, delivery guarantees, the settings and why."),
    ("Part 5", "The database", "Every table, Flyway, JdbcTemplate against JPA, transactions and the version counter."),
    ("Part 6", "Signing in", "API keys, access tokens, what a JWT holds and how it is verified."),
    ("Part 7", "The API", "Every endpoint and the method behind it."),
    ("Part 8", "File by file", "Every class, annotation and method, read from the code's own comments."),
    ("Part 9", "The tests", "The five kinds of test, golden files, and every test class."),
    ("Part 10", "Running it", "Commands, settings, the server set-up, rebuilding from the topics."),
    ("Part 11", "Design decisions, and questions to expect", "Answers to say aloud, including the system's limits."),
]


def page(body, extra_css=""):
    return ('<!doctype html><html lang="en"><head><meta charset="utf-8"><title>PK Reference backend: a study guide</title>'
            f"<style>{CSS}{extra_css}</style></head><body>{body}</body></html>")


def chapter(name):
    return open(os.path.join(HERE, "chapters", name), encoding="utf-8").read()


def main():
    os.makedirs(OUT, exist_ok=True)
    tests_table, tests_total, test_classes = tests()
    main_files, main_lines = stats()
    today = datetime.date.today().strftime("%-d %B %Y")

    def fill(text):
        return (text.replace("{{TESTS_TOTAL}}", str(tests_total)).replace("{{TEST_CLASSES}}", str(test_classes))
                .replace("{{MAIN_FILES}}", str(main_files)).replace("{{MAIN_LINES}}", f"{main_lines:,}")
                .replace("{{TESTS_TABLE}}", tests_table))

    cover = ('<div class="cover"><div class="title">PK Reference backend</div>'
             '<div class="subtitle">A study guide to the Kafka, Spring Boot and PostgreSQL service:<br>'
             'every file, every method, and how they fit together.</div>'
             f'<div class="meta">Built on {esc(today)} by backend/docs/study-guide/build_study_guide.py.<br>'
             'The file-by-file part is read from the comments in the source, so it matches what the files say.</div></div>')
    toc = '<div class="toc"><h1 class="first">Contents</h1><ol>' + "".join(
        f'<li><span class="n">{n}</span><b>{esc(t)}</b><span class="d">{esc(d)}</span></li>' for n, t, d in TOC) + "</ol></div>"

    overview = fill(chapter("01-overview.html")).replace('<h1 id="part1">', '<h1 id="part1">')
    part_a = page(cover + toc + overview + '<p style="margin-top:14pt"><b>Next page:</b> the architecture diagram. '
                  'Every box is a class; the arrows show where data goes.</p>')
    diagram_page = page('<div class="dtitle">The architecture: where each class sits, and what flows between them</div>'
                        + diagram.architecture(),
                        # Sizes in px: WebKit prints a CSS pixel as a point, so pt would overflow the page.
                        "body{margin:0} .dtitle{font-size:15px;font-weight:700;margin:0 0 4px} "
                        "svg{display:block;width:100%;height:auto;max-height:655px}")
    rest = [tree_html().replace("<h2>", '<h2 style="margin-top:0">', 1)]
    for name in ("02-flows.html", "03-spring.html", "04-kafka.html", "05-database.html", "06-security.html",
                 "07-api.html"):
        rest.append(fill(chapter(name)))
    rest.append(reference_html())
    for name in ("09-tests.html", "10-running.html", "11-questions.html"):
        rest.append(fill(chapter(name)))
    part_b = page("".join(rest))

    # The diagram by itself too, for the README.
    open(os.path.join(os.path.dirname(HERE), "architecture.svg"), "w", encoding="utf-8").write(diagram.architecture() + "\n")
    files = {"a.html": part_a, "diagram.html": diagram_page, "b.html": part_b}
    for name, text in files.items():
        open(os.path.join(OUT, name), "w", encoding="utf-8").write(text)
    print("wrote", ", ".join(files), "to", OUT)

    renderer = os.path.join(OUT, "html_to_pdf")
    if not os.path.exists(renderer) or os.path.getmtime(renderer) < os.path.getmtime(os.path.join(HERE, "html_to_pdf.swift")):
        built = subprocess.run(["swiftc", "-O", os.path.join(HERE, "html_to_pdf.swift"), "-o", renderer],
                               capture_output=True, text=True)
        if built.returncode != 0:
            print("No PDF: couldn't compile html_to_pdf.swift (needs macOS with Swift). Open build/*.html and print them.")
            return
    parts = []
    for name, orientation in (("a.html", "portrait"), ("diagram.html", "landscape"), ("b.html", "portrait")):
        part = os.path.join(OUT, name.replace(".html", ".pdf"))
        subprocess.run([renderer, "page", orientation, os.path.join(OUT, name), part], check=True)
        parts.append(part)
    subprocess.run([renderer, "join", PDF] + parts, check=True)


if __name__ == "__main__":
    main()
