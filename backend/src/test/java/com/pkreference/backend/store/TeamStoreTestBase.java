package com.pkreference.backend.store;

import com.pkreference.backend.model.Events.PairingsFetched;
import com.pkreference.backend.model.Events.StandingsFetched;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import static com.pkreference.backend.LimitlessFixtures.details;
import static com.pkreference.backend.LimitlessFixtures.pairings;
import static com.pkreference.backend.LimitlessFixtures.standings;
import static com.pkreference.backend.LimitlessFixtures.tournament;
import static org.assertj.core.api.Assertions.assertThat;

/**
 * The real fixture event through the store, on the migrations. Runs on H2 (TeamStoreTest) and on
 * Postgres (TeamStorePostgresTest), whose SQL H2 doesn't always check: it took a column named
 * "placing", a reserved word in Postgres.
 */
abstract class TeamStoreTestBase {
    private static final String START = "2026-10-05T18:00:00.000Z";
    private static final Instant FINAL = Instant.parse("2026-10-08T00:00:00Z");

    @Autowired TeamStore store;
    @Autowired JdbcTemplate jdbc;

    private int count(String sql, Object... args) {
        return jdbc.queryForObject(sql, Integer.class, args);
    }

    private StandingsFetched fetched(Instant at, boolean isFinal) {
        return new StandingsFetched(tournament(START), standings(), details(), at, isFinal);
    }

    @Test
    void storesTheWholeEvent() {
        store.putStandings(fetched(FINAL, true));

        Map<String, Object> event = jdbc.queryForMap("select * from event where id = 'event-83'");
        assertThat(event).containsEntry("FORMAT", "M-C").containsEntry("PLAYERS", 83)
                .containsEntry("ORGANIZER", "Test Organizer").containsEntry("PLATFORM", "SWITCH")
                .containsEntry("ONLINE", true).containsEntry("DECKLISTS", true).containsEntry("STANDINGS_FINAL", true);
        assertThat(jdbc.queryForList("select type, rounds, mode from event_phase order by phase"))
                .extracting(r -> r.get("TYPE") + " " + r.get("ROUNDS") + " " + r.get("MODE"))
                .containsExactly("SWISS 6 BO3", "SINGLE_BRACKET 1 BO3");
        assertThat(count("select count(*) from team")).isEqualTo(83);
        assertThat(count("select count(*) from team_member")).isEqualTo(498);
        assertThat(count("select count(*) from team_member_move")).isEqualTo(1992);

        var winner = jdbc.queryForMap("select * from team where player = 'player-01'");
        assertThat(winner).containsEntry("PLACEMENT", 1).containsEntry("WINS", 8).containsEntry("LOSSES", 2);
        assertThat(jdbc.queryForList("""
                select move from team_member_move where player = 'player-01' and slot = 0 order by move_slot""",
                String.class)).containsExactly("Reflect", "Light Screen", "Spirit Break", "Parting Shot");
        assertThat(jdbc.queryForMap("select name, item, ability, nature from team_member where player = 'player-01' and slot = 0"))
                .containsEntry("NAME", "Grimmsnarl").containsEntry("ITEM", "Light Clay")
                .containsEntry("ABILITY", "Prankster").containsEntry("NATURE", "Careful");
    }

    @Test
    void aNewerFetchReplacesTheEventAndAnOlderOneDoesnt() {
        var early = new StandingsFetched(tournament(START), standings().subList(0, 10), details(),
                Instant.parse("2026-10-05T20:00:00Z"), false);
        store.putStandings(early);
        assertThat(count("select count(*) from team")).isEqualTo(10);
        assertThat(count("select count(*) from event where standings_final")).isZero();

        store.putStandings(fetched(FINAL, true));
        assertThat(count("select count(*) from team")).isEqualTo(83);
        assertThat(count("select count(*) from team_member")).isEqualTo(498);
        assertThat(count("select count(*) from event where standings_final")).isEqualTo(1);

        store.putStandings(early); // arriving late, from a replay
        assertThat(count("select count(*) from team")).isEqualTo(83);

        store.putStandings(fetched(FINAL, true)); // the same fetch again
        assertThat(count("select count(*) from team_member_move")).isEqualTo(1992);
    }

    /** Records from before Phase 1 have no details or fetch time; they count as final. */
    @Test
    void oldRecords() {
        store.putStandings(new StandingsFetched(tournament(START), standings()));
        assertThat(count("select count(*) from event where standings_final and fetched_at is null")).isEqualTo(1);
        assertThat(count("select count(*) from event_phase")).isZero();
        store.putStandings(fetched(FINAL, true));
        assertThat(count("select count(*) from event_phase")).isEqualTo(2);
    }

    @Test
    void storesTheMatches() {
        store.putStandings(fetched(FINAL, true));
        store.putPairings(new PairingsFetched(tournament(START), pairings(), FINAL));
        store.putPairings(new PairingsFetched(tournament(START), pairings(), FINAL)); // again: replaced

        assertThat(count("select count(*) from pairing")).isEqualTo(188);
        assertThat(jdbc.queryForList("select result, count(*) n from pairing group by result order by result"))
                .extracting(r -> r.get("RESULT") + " " + r.get("N"))
                .containsExactly("BYE 1", "DOUBLE_LOSS 3", "NO_SHOW 6", "P1 90", "P2 88");
        assertThat(jdbc.queryForList("select label from pairing where phase = 2 and label like 'T2-%'", String.class))
                .hasSize(1);

        // The top cut is who played in the bracket: here, placings 1 to 16.
        List<Integer> placings = jdbc.queryForList("""
                select placement from team where event_id = 'event-83' and player in (
                    select player1 from pairing where event_id = 'event-83' and phase = 2
                    union select player2 from pairing where event_id = 'event-83' and phase = 2)
                order by placement""", Integer.class);
        assertThat(placings).hasSize(16).first().isEqualTo(1);
        assertThat(placings).last().isEqualTo(16);

        store.putPairings(new PairingsFetched(tournament(START), List.of(), Instant.parse("2026-10-06T00:00:00Z")));
        assertThat(count("select count(*) from pairing")).as("an older fetch").isEqualTo(188);
    }
}
