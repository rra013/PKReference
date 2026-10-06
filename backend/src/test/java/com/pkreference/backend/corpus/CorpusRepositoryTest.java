package com.pkreference.backend.corpus;

import com.pkreference.backend.model.Events.Standing;
import com.pkreference.backend.model.Events.StandingsFetched;
import com.pkreference.backend.model.Events.Tournament;
import com.pkreference.backend.standardize.SpeciesVocabularies;
import com.pkreference.backend.store.TeamStore;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.JdbcTest;
import org.springframework.context.annotation.Import;

import java.time.Instant;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

import static com.pkreference.backend.LimitlessFixtures.details;
import static com.pkreference.backend.LimitlessFixtures.standings;
import static org.assertj.core.api.Assertions.assertThat;

/**
 * The store read back in Limitless's shapes is what Limitless sent: the contract that lets the app
 * build its Team Search corpus from the server with its Limitless code.
 */
@JdbcTest
@Import({TeamStore.class, SpeciesVocabularies.class, CorpusRepository.class})
class CorpusRepositoryTest {
    @Autowired TeamStore store;
    @Autowired CorpusRepository corpus;

    private void put(String id, String date) {
        var t = new Tournament(id, "Test Event " + id, "VGC", "M-C", date, 83);
        store.putStandings(new StandingsFetched(t, standings(), details(), Instant.parse("2026-10-08T00:00:00Z"), true));
    }

    @Test
    void standingsComeBackAsLimitlessSentThem() {
        put("event-83", "2026-10-05T18:00:00.000Z");
        Map<String, Standing> sent = standings().stream().collect(Collectors.toMap(Standing::player, Function.identity()));
        var back = corpus.standings("event-83");

        assertThat(back).hasSize(83);
        for (Standing s : back) {
            Standing original = sent.get(s.player());
            // Limitless's deck (its own archetype label) isn't kept.
            assertThat(s).usingRecursiveComparison().ignoringFields("deck").isEqualTo(original);
        }
        assertThat(corpus.standings("missing")).isNull();
    }

    @Test
    void tournamentsNewestFirst() {
        put("older", "2026-09-01T18:00:00.000Z");
        put("event-83", "2026-10-05T18:00:00.000Z");
        put("newest", "2026-10-06T09:30:00.000Z");

        var page = corpus.tournaments("m-c", 1, 2);
        assertThat(page).extracting(Tournament::id).containsExactly("newest", "event-83");
        assertThat(page.get(1)).isEqualTo(new Tournament("event-83", "Test Event event-83", "VGC", "M-C",
                "2026-10-05T18:00:00.000Z", 83));
        assertThat(corpus.tournaments("M-C", 2, 2)).extracting(Tournament::id).containsExactly("older");
        assertThat(corpus.tournaments("M-B", 1, 50)).isEmpty();
    }
}
