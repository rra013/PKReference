"""The guide's architecture diagram, as SVG: where each class sits and what flows between them."""
from html import escape

KINDS = {
    "source":   ("#f1f3f5", "#868e96"),
    "ingest":   ("#e7f1ff", "#3b5bdb"),
    "kafka":    ("#fff4e6", "#e8590c"),
    "topic":    ("#ffe8cc", "#e8590c"),
    "consumer": ("#ebfbee", "#2b8a3e"),
    "pg":       ("#f3f0ff", "#6741d9"),
    "table":    ("#e5dbff", "#6741d9"),
    "read":     ("#e6fcf5", "#087f5b"),
    "security": ("#fff0f6", "#c2255c"),
    "app":      ("#f8f9fa", "#343a40"),
    "note":     ("#ffffff", "#868e96"),
}


class Svg:
    def __init__(self, width, height):
        self.width, self.height, self.parts = width, height, []

    def box(self, x, y, w, h, kind, title, lines=(), dashed=False, title_size=13):
        fill, stroke = KINDS[kind]
        dash = ' stroke-dasharray="5 4"' if dashed else ""
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{fill}" '
                          f'stroke="{stroke}" stroke-width="1.3"{dash}/>')
        ty = y + (20 if lines else h / 2 + 4.5)
        self.parts.append(f'<text x="{x + 10}" y="{ty}" font-size="{title_size}" font-weight="700" '
                          f'fill="#212529">{escape(title)}</text>')
        for i, line in enumerate(lines):
            self.parts.append(f'<text x="{x + 10}" y="{ty + 15 + i * 13.5}" font-size="10.5" fill="#495057">'
                              f'{escape(line)}</text>')

    def frame(self, x, y, w, h, kind, label):
        fill, stroke = KINDS[kind]
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{fill}" '
                          f'stroke="{stroke}" stroke-width="1.6"/>')
        self.parts.append(f'<text x="{x + 10}" y="{y + 19}" font-size="12" font-weight="700" fill="{stroke}">'
                          f'{escape(label)}</text>')

    def arrow(self, points, label=None, dashed=False, both=False, color="#343a40", label_at=None, anchor="middle"):
        d = "M " + " L ".join(f"{x} {y}" for x, y in points)
        dash = ' stroke-dasharray="5 4"' if dashed else ""
        start = ' marker-start="url(#tail)"' if both else ""
        self.parts.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="1.4"{dash} '
                          f'marker-end="url(#head)"{start}/>')
        if label:
            lx, ly = label_at or ((points[0][0] + points[-1][0]) / 2, (points[0][1] + points[-1][1]) / 2 - 5)
            self.parts.append(f'<text x="{lx}" y="{ly}" font-size="10" fill="#495057" text-anchor="{anchor}" '
                              f'font-style="italic">{escape(label)}</text>')

    def text(self, x, y, text, size=12, weight="400", fill="#212529", anchor="start"):
        self.parts.append(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{fill}" '
                          f'text-anchor="{anchor}">{escape(text)}</text>')

    def render(self):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.width} {self.height}" '
                f'font-family="-apple-system, Helvetica Neue, Arial, sans-serif">'
                '<defs><marker id="head" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
                'orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#343a40"/></marker>'
                '<marker id="tail" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
                'orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#343a40"/></marker></defs>'
                # A white page behind it: readable where the image is shown on a dark background.
                + f'<rect width="{self.width}" height="{self.height}" fill="#ffffff"/>'
                + "".join(self.parts) + "</svg>")


def architecture():
    s = Svg(1400, 950)
    s.text(20, 24, "WRITE PATH", 14, "800", "#3b5bdb")
    s.text(118, 24, "runs on timers and Kafka records: discover, fetch, publish, store", 12, "400", "#495057")
    s.text(20, 604, "READ PATH", 14, "800", "#087f5b")
    s.text(108, 604, "runs on HTTP requests: check the caller, compute from the tables, answer as JSON", 12, "400", "#495057")

    # Sources
    s.box(20, 118, 170, 80, "source", "Limitless API", ["tournament lists, details,", "standings, pairings", "limit: 50 requests / 5 min"])
    s.box(20, 392, 170, 62, "source", "Smogon stats", ["monthly chaos + leads files", "one request every 2 s"])

    # Ingest
    s.box(240, 56, 250, 72, "ingest", "EventDiscovery", ["@Scheduled: every 30 minutes", "FetchPolicy decides what to ask for"])
    s.box(240, 142, 250, 58, "ingest", "LimitlessClient", ["RequestThrottle keeps to 40 / 5 min"])
    s.box(240, 214, 250, 72, "ingest", "EventFetcher", ["@KafkaListener  (group standings-fetcher)", "3 requests an event, then publishes"])
    s.box(240, 370, 250, 58, "ingest", "LadderDiscovery", ["@Scheduled: every 12 hours"])
    s.box(240, 442, 250, 58, "ingest", "SmogonClient → LadderReducer", ["streams a 7 MB file down to about 1 MB"])

    # Kafka
    s.frame(545, 44, 235, 480, "kafka", "Kafka: one broker (KRaft)")
    s.box(560, 76, 205, 46, "topic", "tournaments.discovered", ["work queue: \"fetch this event\""], title_size=12)
    s.box(560, 148, 205, 46, "topic", "standings.fetched", ["compacted, kept for good"], title_size=12)
    s.box(560, 220, 205, 46, "topic", "pairings.fetched", ["compacted, kept for good"], title_size=12)
    s.box(560, 300, 205, 46, "topic", "pokemon.usage", ["compacted: latest count per Pokémon"], title_size=12)
    s.box(560, 386, 205, 46, "topic", "ladder.stats", ["compacted, kept for good"], title_size=12)
    s.box(560, 462, 205, 46, "topic", "<topic>.DLT  (four)", ["records that kept failing"], dashed=True, title_size=12)

    # Consumers and stores
    s.box(822, 150, 275, 86, "consumer", "TeamStoreConsumer → TeamStore", ["@KafkaListener ×2  (team-store-standings,", "team-store-pairings)", "replaces an event's rows in one transaction"])
    s.box(822, 266, 275, 72, "consumer", "UsageConsumer → UsageAggregationService", ["@KafkaListener  (group usage-aggregator)", "all-time counters: the first version"], title_size=11.5)
    s.box(822, 378, 275, 58, "consumer", "LadderStoreConsumer → LadderStore", ["@KafkaListener  (group ladder-store)"], title_size=12)
    s.box(822, 458, 275, 54, "note", "KafkaErrorHandling", ["a listener throws: retry 3×, 2 s apart, then DLT"], dashed=True, title_size=12)

    # Postgres
    s.frame(1140, 44, 245, 890, "pg", "PostgreSQL  (schema: Flyway)")
    s.box(1155, 76, 215, 44, "table", "event_fetch", ["asked for / fetched, per event"], title_size=12)
    s.box(1155, 142, 215, 118, "table", "The team store", ["event · event_phase", "team · team_member", "team_member_move", "pairing · pairing_fetch", "store_version  (every write bumps it)"], title_size=12)
    s.box(1155, 274, 215, 58, "table", "usage_counter", ["processed_tournament"], title_size=12)
    s.box(1155, 384, 215, 46, "table", "ladder_stats", ["one row a file, as JSON text"], title_size=12)

    # Shared strip
    s.box(20, 540, 1100, 36, "note", "Used by both paths:  config/ Topics, KafkaSends, *Properties   |   model/ Events, Ladder (the JSON shapes)   |   standardize/ NameStandardizer, SpeciesVocabularies (consistent names)", title_size=11.5)

    # Read path: services, controllers, filters, app
    s.box(835, 624, 250, 62, "read", "MetaRepository → MetaService", ["computes on request; cached on", "store_version + the hour"])
    s.box(835, 698, 250, 44, "read", "CorpusRepository", ["the team store, in Limitless's shapes"], title_size=12)
    s.box(835, 754, 250, 50, "read", "LadderStore → LadderService", ["adds trend and usage by rating"], title_size=12)
    s.box(835, 816, 250, 44, "read", "UsageCounterRepository", ["Spring Data JPA"], title_size=12)
    s.box(835, 872, 250, 54, "security", "TokenService", ["issues and verifies JWTs (HS256, 15 min)"], title_size=12)

    s.box(545, 624, 235, 62, "read", "MetaController", ["/v1/formats, .../pokemon, cores,", "archetypes, events"])
    s.box(545, 698, 235, 44, "read", "CorpusController", ["/v1/.../tournaments, .../standings"], title_size=12)
    s.box(545, 754, 235, 50, "read", "LadderController", ["/v1/ladder, /v1/ladder/{format}"], title_size=12)
    s.box(545, 816, 235, 44, "read", "UsageController", ["/api/usage  (old)"], title_size=12)
    s.box(545, 872, 235, 54, "security", "AuthController", ["POST /v1/auth/token: key in, token out"], title_size=12)

    s.box(285, 636, 205, 104, "security", "ApiAuthFilter", ["runs first, on every path", "API key at the token path,", "access token everywhere else", "otherwise 401 with a reason"])
    s.box(285, 766, 205, 62, "read", "ETag filter", ["ShallowEtagHeaderFilter on /v1/*", "304 when the client's copy is current"], title_size=12)
    s.box(20, 676, 200, 92, "app", "PK Reference app", ["iPhone · iPad · Mac", "reads /v1 through its own cache;", "trades its API key for tokens"])

    # Arrows: write path
    s.arrow([(190, 158), (240, 170)], "JSON", label_at=(214, 152))
    s.arrow([(490, 84), (560, 92)], "publish", label_at=(524, 78))
    s.arrow([(560, 110), (520, 110), (520, 240), (490, 240)])
    s.arrow([(490, 256), (530, 256), (530, 171), (560, 171)])
    s.arrow([(490, 270), (535, 270), (535, 243), (560, 243)])
    s.arrow([(765, 163), (822, 180)])
    s.arrow([(765, 243), (795, 243), (795, 210), (822, 210)])
    s.arrow([(765, 182), (806, 182), (806, 290), (822, 290)])
    s.arrow([(822, 322), (765, 323)], "publish", label_at=(794, 337))
    s.arrow([(1097, 193), (1155, 197)])
    s.arrow([(1097, 302), (1155, 303)])
    s.arrow([(1097, 407), (1155, 407)])
    s.arrow([(190, 423), (215, 423), (215, 471), (240, 471)], "files", label_at=(212, 416), anchor="end")
    s.arrow([(490, 399), (560, 407)], "publish", label_at=(524, 393))
    s.arrow([(765, 409), (822, 407)])
    s.arrow([(822, 485), (765, 485)], dashed=True)
    # event_fetch: discovery and the fetcher remember what they've asked for, over the top.
    s.arrow([(365, 56), (365, 34), (1262, 34), (1262, 44)], "EventFetchRepository reads and writes event_fetch: what has been asked for, and fetched",
            both=True, label_at=(810, 29))

    # Arrows: read path (requests go right, answers come back left)
    for y in (655, 720, 779, 838):
        s.arrow([(1140, y), (1085, y)])
        s.arrow([(835, y), (780, y)])
    s.text(1112, 648, "SQL", 10, "400", "#495057", "middle")
    s.arrow([(835, 899), (780, 899)], both=True)
    s.arrow([(220, 705), (285, 692)], "request", both=True, label_at=(252, 686))
    s.arrow([(387, 740), (387, 766)], both=True)
    s.arrow([(490, 797), (517, 797), (517, 760), (545, 760)], both=True)
    s.text(517, 846, "→ request", 10, "400", "#495057", "middle")
    s.text(517, 859, "← JSON", 10, "400", "#495057", "middle")

    # Legend
    lx, ly = 20, 846
    s.text(lx, ly, "Legend", 12, "700")
    items = [("ingest", "fetches from a source"), ("topic", "Kafka topic"), ("consumer", "Kafka consumer and its store"),
             ("table", "PostgreSQL table"), ("read", "read path"), ("security", "signing in")]
    for i, (kind, label) in enumerate(items):
        fill, stroke = KINDS[kind]
        x = lx + (i % 2) * 215
        y = ly + 12 + (i // 2) * 22
        s.parts.append(f'<rect x="{x}" y="{y}" width="16" height="13" rx="3" fill="{fill}" stroke="{stroke}"/>')
        s.text(x + 23, y + 11, label, 11, "400", "#343a40")
    s.text(lx, ly + 90, "Solid arrows show where data goes. Each box is a class in backend/src/main/java/com/pkreference/backend/.", 10, "400", "#868e96")
    return s.render()


if __name__ == "__main__":
    print(architecture())
