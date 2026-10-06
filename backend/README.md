# PK Reference backend (Kafka + Spring Boot)

Companion service for the PK Reference app. It pulls Limitless tournament data, streams it
through Kafka, keeps every event's teams and matches, and serves team usage stats over REST.
[`BackendIntegration-PLAN.md`](../BackendIntegration-PLAN.md) is where it's going.

```
Limitless --poll--> EventDiscovery    --> tournaments.discovered
                    EventFetcher      --> standings.fetched + pairings.fetched (details, standings, matches)
                    TeamStoreConsumer --> Postgres: event, event_phase, team, team_member(_move), pairing
                    UsageConsumer     --> Postgres counters + pokemon.usage (compacted)
                    MetaController    --> GET /v1/... (insights from the team store)
                    UsageController   --> GET /api/usage?format=... (the older all-time counts)
```

## Run
```sh
cd backend
docker compose up -d                 # Kafka on :9092, Kafka UI on :8081, Postgres on :5432
mvn spring-boot:run                  # API on :8080, Swagger UI at /swagger-ui.html
curl 'localhost:8080/api/usage?format=<format>&limit=20'
curl 'localhost:8080/api/usage/incineroar?format=<format>'
```
Set `LIMITLESS_GAME` and `LIMITLESS_FORMATS` (comma-separated, such as `M-C,M-B`; empty for every format)
to pick the circuit (see `GET /games` on the Limitless API). `LIMITLESS_FORMAT`, the old single format,
still works.
`DATABASE_URL`, `DATABASE_USER` and `DATABASE_PASSWORD` point it at another Postgres, and
`KAFKA_BOOTSTRAP_SERVERS` at another broker.

Kafka and Postgres keep their data in Docker volumes (`pkref-kafka`, `pkref-postgres`), so it survives
restarts and `docker compose down`; `docker compose down -v` deletes it. Flyway creates and upgrades the
tables (`src/main/resources/db/migration`).

### Upgrading from the H2 version
The counters used to be in an H2 file under `backend/data/`. They move to Postgres and start empty, so
delete `backend/data/`. The first `docker compose up -d` after this change recreates the Kafka container
with its volume; the topics it held inside the container are lost, as on any recreate before.

### API v1
Read-only and the same for everyone. Responses may be reused for 15 minutes (`Cache-Control`), carry a
weak ETag (a matching `If-None-Match` gets a 304), and are gzipped. Each says what it covers: the window,
when it was worked out, and how many events, teams and top-cut teams it rests on.
```sh
curl 'localhost:8080/v1/formats'
curl 'localhost:8080/v1/formats/M-C/pokemon?window=30d'                # 14d, 30d or regulation
curl 'localhost:8080/v1/formats/M-C/pokemon/arcanine:hisui?window=30d'
curl 'localhost:8080/v1/formats/M-C/cores?window=30d'
curl 'localhost:8080/v1/formats/M-C/archetypes?window=30d'
```
**Full reference:** with the backend running, Swagger UI at
[localhost:8080/swagger-ui.html](http://localhost:8080/swagger-ui.html) describes every endpoint, parameter
and field, and lets you try them; the OpenAPI document is at `/v3/api-docs`. Both come from the
annotations in `MetaController` and `MetaResponses`.
- The list: each Pokémon's `usage` (share of teams), `topCutUsage` (share of top-cut teams, null when the
  window had no top cut), `trend` (usage in the last 14 days less the 14 before; null when either
  period has under 50 teams) and `record`: wins, losses and ties from the pairings, leaving out mirror
  matches, with a win rate (a tie is half a win) and its 95% range, null under 30 matches.
- A Pokémon's page: its items, abilities, natures, moves, Mega Stones and teammates, its 10 most common
  whole sets, and its usage week by week.
- Cores: the 20 most common pairs and trios (on 4 teams or more), with `lift`, their share over what
  chance would give.
- Archetypes: teams grouped by a core of four. Cores are the most common sets of four that share at most
  two Pokémon with any more common core (on at least 4 teams and 2% of them); each team belongs to the
  first core it contains. Each archetype has its usage, top-cut rate, record, and record against each
  other archetype.

`MetaService` works these out from the team store when asked, and keeps each result until the store
changes (`store_version`, which every write bumps in its transaction) or the hour does. Shares are 0 to 1.
Definitions are in [the plan](../BackendIntegration-PLAN.md) (§4.2).

### Finding events, and backfilling
Every 30 minutes `EventDiscovery` walks each format's tournament list back through the lookback
(`LIMITLESS_LOOKBACK`, 7 days) and asks for the events to fetch, by the app's rules
(`TeamCorpusConfiguration`): 16 players or more, and started. Standings are final 48 hours after an
event starts; until then it's fetched again every 6 hours. `event_fetch` records what's been asked for,
so an event waiting in the queue isn't asked for twice.

To backfill, start it once with a longer lookback, then go back to the default:
```sh
LIMITLESS_FORMATS=M-C,M-B LIMITLESS_LOOKBACK=120d mvn spring-boot:run
```
Each event takes three requests (details, standings, pairings), so under the throttle a backfill fetches
about 13 events every 5 minutes, and several hundred take hours. It picks up where it was after a
restart.

### The team store
`TeamStoreConsumer` writes every fetched event into Postgres: `event` and its `event_phase`s (Swiss, top
cut), each player's `team` (placement, record) with its `team_member`s and their moves, and every match in
`pairing` with its `result` (`P1`, `P2`, `TIE`, `DOUBLE_LOSS`, `BYE`, `NO_SHOW`). Each member also gets
its `species_key` the app's way ("arcanine:hisui": the species and the form words its regulation lists)
and its `mega_stone` when it holds one of its own Mega Stones (`SpeciesVocabularies`, a port of the app's
`TeamSearchVocabulary`, built from the same bundled files). Rows stored before that came in get keys
when the store is rebuilt (below). A newer fetch of an event
replaces its rows, and an older one is ignored. The top cut is who played in a bracket phase (`phase > 1`).
Events are stored before their standings are final (`standings_final`), so they can be seen early; the
usage counters wait until they are.

### Rebuilding the counters and the store
`standings.fetched` and `pairings.fetched` keep every event fetched, so anything built from them can be
rebuilt, after a fix to `NameStandardizer` for example. With the backend stopped:
```sh
# The usage counters
docker compose exec postgres psql -U pkref -c 'truncate usage_counter, processed_tournament'
docker compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka:19092 \
  --group usage-aggregator --reset-offsets --to-earliest --all-topics --execute
# The team store (each fetch replaces its event, so no truncate is needed)
for g in team-store-standings team-store-pairings; do
  docker compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka:19092 \
    --group $g --reset-offsets --to-earliest --all-topics --execute
done
```

## Test
`mvn verify` runs the unit tests and the embedded-Kafka pipeline tests, on an in-memory database (H2) with
the same migrations. The store's tests also run on Postgres 17 in Docker (Testcontainers), because H2 lets
through SQL Postgres rejects; without Docker they're skipped. The fixtures in
`src/test/resources/limitless/` are one real event's API responses, with the players' names replaced.
`golden/species-identity.json` holds species keys recorded from the app: the app's
`SpeciesIdentityGoldenTests` and the backend's `SpeciesVocabularyGoldenTest` both check against it, so a
change to either side's naming fails a test until the other matches.
GitHub Actions runs it for changes to the backend (`.github/workflows/backend.yml`).

## Name standardization
Players type items, abilities and moves by hand, so `NameStandardizer` canonicalizes them before counting
("MIRACLE SEED" / "Fake-out" / "Darkest Larient" -> "Miracle Seed" / "Fake Out" / "Darkest Lariat").
It reads the repo-root `champions-*.json` regulation files, their learnsets,
`PKReference/showdown-champions-data.json` (bundled onto the classpath at build time) and
`reference/champions-items.json`, a snapshot of Serebii's Champions item page (every Champions item, not
per regulation). It fixes spelling and casing and never drops a value, since decklists also come from formats
with no regulation file (fan formats, older or newer regulations); names matching nothing are kept, title-cased.
After changing it, rebuild the counters (above) so they use the new spellings.

## Notes
- Limitless allows 50 requests in 5 minutes without a key. `LimitlessClient` keeps to 40
  (`pkref.limitless.requests-per-window` and `window`), leaving room for the app on the same machine, and
  waits whenever Limitless's `ratelimit` header says none are left.
- `standings.fetched` is compacted to the latest standings per tournament and never deleted. Its records
  can be up to 5 MB, and the producer compresses them (zstd): standings are about 1.2 KB of JSON a player,
  over the broker's default 1 MB limit at about 850 players. Starting the backend applies these settings to
  topics that already exist.
- `pairings.fetched` is kept the same way.
- Every send is waited for, so a failed one throws: the event's fetch retries and then goes to the DLT,
  instead of being dropped.
- Aggregation is idempotent per tournament id: replays and duplicate deliveries are no-ops.
- Failed records retry 3 times, then go to `<topic>.DLT`.
- The usage consumer is deliberately single-threaded (shared counters).
