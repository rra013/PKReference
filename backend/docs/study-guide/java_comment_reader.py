"""Reads the backend's Java sources into a plain structure for the study guide: each file's
types, and each type's members with their signatures, annotations and Javadoc.

A small scanner, not a Java parser: it tracks strings, comments and braces, which is enough for
this code's style. build_study_guide.py turns the result into HTML."""
import html
import re

TYPE = re.compile(r"\b(class|interface|enum|record)\s+(\w+)")


def _tokens(src):
    """Yields (kind, text) for 'code', 'string', 'javadoc' and 'comment' pieces, in order."""
    i, n, start = 0, len(src), 0
    while i < n:
        if src.startswith('"""', i):
            j = src.index('"""', i + 3)
            while src[j - 1] == "\\":
                j = src.index('"""', j + 3)
            end = j + 3
            kind = "string"
        elif src[i] in "\"'":
            j = i + 1
            while src[j] != src[i]:
                j += 2 if src[j] == "\\" else 1
            end = j + 1
            kind = "string"
        elif src.startswith("//", i):
            j = src.find("\n", i)
            end = n if j < 0 else j
            kind = "comment"
        elif src.startswith("/*", i):
            end = src.index("*/", i) + 2
            kind = "javadoc" if src.startswith("/**", i) else "comment"
        else:
            i += 1
            continue
        if start < i:
            yield "code", src[start:i]
        yield kind, src[i:end]
        i = start = end
    if start < n:
        yield "code", src[start:]


def _javadoc_html(raw):
    """A Javadoc comment as HTML: {@code x} becomes <code>, the few tags it uses are kept."""
    body = raw.strip()[3:-2]
    lines = [re.sub(r"^\s*\* ?", "", l) for l in body.split("\n")]
    text = "\n".join(lines).strip()
    codes = []

    def keep(m):
        codes.append(m.group(1))
        return "\x00%d\x00" % (len(codes) - 1)

    text = re.sub(r"\{@(?:code|link|literal) ([^}]*)\}", keep, text)
    text = html.escape(text, quote=False)
    text = re.sub(r"&lt;(/?(?:p|ul|li|b|i|em|pre|code))&gt;", r"<\1>", text)
    text = re.sub(r"\x00(\d+)\x00", lambda m: "<code>%s</code>" % html.escape(codes[int(m.group(1))], quote=False), text)
    # Paragraphs: the first has no <p>; give every paragraph one, and close them.
    parts = re.split(r"\n\s*\n", text)
    out = []
    for part in parts:
        part = part.strip()
        if not part:
            continue
        if part.startswith("<ul>") or part.startswith("<pre>"):
            out.append(part)
        else:
            out.append("<p>" + re.sub(r"^<p>", "", part) + "</p>")
    return "\n".join(out)


def _signature(code):
    """Annotations and the declaration from the code before a '{' or ';'."""
    code = re.sub(r"\s+", " ", code).strip()
    annotations = []
    while code.startswith("@"):
        m = re.match(r"@[\w.]+", code)
        end = m.end()
        if end < len(code) and code[end] == "(":
            depth, j = 0, end
            while True:
                if code[j] == "(":
                    depth += 1
                elif code[j] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            end = j + 1
        annotations.append(code[:end])
        code = code[end:].strip()
    return annotations, code


def parse(path):
    """One file: {'package', 'types': [{'signature', 'annotations', 'doc', 'kind', 'members'}]}."""
    src = open(path, encoding="utf-8").read()
    package = re.search(r"^package ([\w.]+);", src, re.M).group(1)
    # Work on the text after the imports: the top-level type, with its Javadoc.
    start = max((m.end() for m in re.finditer(r"^import .*;$", src, re.M)), default=src.index(";") + 1)
    top = _types(src[start:])
    return {"package": package, "types": top}


def _types(src):
    """Type declarations at this level, each with its members (nested types included, one level)."""
    found = []
    for item, body in _split(src):
        if item["kind"] == "type" and body is not None:
            item["members"] = []
            for sub, sub_body in _split(body):
                if sub["kind"] == "type" and sub_body is not None:
                    sub["members"] = [m for m, _ in _split(sub_body)]
                item["members"].append(sub)
        found.append(item)
    return found


def _split(src):
    """(item, body text) for each declaration directly in src."""
    out, depth, paren, chunk, doc, body, i = [], 0, 0, [], None, None, 0
    for kind, text in _tokens(src):
        if kind in ("javadoc", "comment"):
            # A declaration's Javadoc comes before it; one inside it (on a record's component) isn't its own.
            if depth == 0 and kind == "javadoc" and not "".join(chunk).strip():
                doc = text
            elif depth > 0:
                body.append(text)
            continue
        if kind == "string":
            (chunk if depth == 0 else body).append(text)
            continue
        for ch in text:
            if depth == 0:
                if ch == "(":
                    paren += 1
                    chunk.append(ch)
                elif ch == ")":
                    paren -= 1
                    chunk.append(ch)
                elif ch == "{" and paren == 0:
                    depth, body = 1, []
                elif ch == ";" and paren == 0:
                    out.append(("".join(chunk), doc, None))
                    chunk, doc = [], None
                else:
                    chunk.append(ch)
            else:
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0:
                        out.append(("".join(chunk), doc, "".join(body)))
                        chunk, doc, body = [], None, None
                        continue
                body.append(ch)
    items = []
    for code, doc, body in out:
        annotations, sig = _signature(code)
        head = sig.split("(")[0]
        if not sig or sig == "static":
            continue
        is_type = bool(TYPE.search(head))
        if is_type:
            kind = "type"
        elif re.match(r"^[A-Z_0-9]+(\(.*\))?(, ?[A-Z_0-9]+(\(.*\))?)*$", sig):
            kind = "constants"                                  # an enum's constants
        elif "(" in sig.split("=")[0]:
            kind = "method"
        else:
            kind = "field"
        items.append(({"signature": sig, "annotations": annotations, "doc": _javadoc_html(doc) if doc else "",
                       "kind": kind}, body))
    return items
