# PK Reference backend (Kafka + Spring Boot)

Companion service for the PK Reference app. It pulls Limitless tournament data, streams it
through Kafka and serves team usage stats over REST.

```
Limitless --poll--> TournamentIngestor --> tournaments.discovered
                    StandingsFetcher   --> standings.fetched
                    UsageConsumer      --> DB counters + pokemon.usage (compacted)
                    UsageController    --> GET /api/usage?format=...
```

## Run
```sh
cd backend
docker compose up -d                 # Kafka on :9092, Kafka UI on :8081
mvn spring-boot:run                  # API on :8080, Swagger UI at /swagger-ui.html
curl 'localhost:8080/api/usage?format=<format>&limit=20'
curl 'localhost:8080/api/usage/incineroar?format=<format>'
```
Set `LIMITLESS_GAME` / `LIMITLESS_FORMAT` to pick the circuit (see `GET /games` on the Limitless API).

## Test
`mvn verify` runs the aggregation unit tests and an embedded-Kafka pipeline test.

## Name standardization
Players type items, abilities and moves by hand, so `NameStandardizer` canonicalizes them before counting
("MIRACLE SEED" / "Fake-out" / "Darkest Larient" -> "Miracle Seed" / "Fake Out" / "Darkest Lariat").
It reads the repo-root `champions-*.json` regulation files, their learnsets and
`PKReference/showdown-champions-data.json` (bundled onto the classpath at build time) to fix spelling and
casing. It never drops a value: the regulation item lists are incomplete (Life Orb, Wide Lens, Expert Belt
and some mega stones are missing but widely used), so unknown names are kept, title-cased.
After upgrading, delete `backend/data/` so counters are rebuilt with the new spellings.

## Notes
- Aggregation is idempotent per tournament id: replays and duplicate deliveries are no-ops.
- Failed records retry 3 times, then go to `<topic>.DLT`.
- The usage consumer is deliberately single-threaded (shared counters).
