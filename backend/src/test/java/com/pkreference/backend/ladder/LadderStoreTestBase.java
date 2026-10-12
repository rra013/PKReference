package com.pkreference.backend.ladder;

import com.pkreference.backend.model.Ladder.Pokemon;
import com.pkreference.backend.model.Ladder.Stats;
import com.pkreference.backend.model.Ladder.StatsFetched;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;
import java.util.NoSuchElementException;

import static com.pkreference.backend.ladder.LadderFixtures.FORMAT_ID;
import static com.pkreference.backend.ladder.LadderTestConfig.FETCHED;
import static com.pkreference.backend.ladder.LadderTestConfig.fetched;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;

/**
 * The ladder's store and what the service makes of it, on the migrations. Runs on H2
 * (LadderStoreTest) and on Postgres (LadderStorePostgresTest), as the team store's tests do.
 */
abstract class LadderStoreTestBase {
    private static final String BSS = "gen9championsbssregmc";

    @Autowired LadderStore store;
    @Autowired LadderService service;
    @Autowired JdbcTemplate jdbc;

    /** The store commits each put, so a test starts by emptying the table. */
    @BeforeEach
    void empty() {
        jdbc.update("delete from ladder_stats");
    }

    private static StatsFetched reducedBy(StatsFetched f, int reduction) {
        Stats s = f.stats();
        return new StatsFetched(new Stats(reduction, s.format(), s.regulation(), s.mode(), s.bestOf(), s.month(),
                s.rating(), s.battles(), s.pokemon()), f.fetchedAt());
    }

    @Test
    void keepsTheWholeRecord() {
        var fetched = fetched("2026-09", 1760, 1);
        assertThat(store.put(fetched)).isTrue();

        var stored = store.find(FORMAT_ID, "2026-09", 1760).orElseThrow();
        assertThat(stored.stats()).isEqualTo(fetched.stats());
        assertThat(stored.fetchedAt()).isEqualTo(FETCHED);
        assertThat(store.find(FORMAT_ID, "2026-09", 1500)).isEmpty();
        assertThat(store.find(FORMAT_ID, "2026-08", 1760)).isEmpty();
        assertThat(store.find(BSS, "2026-09", 1760)).isEmpty();
        assertThat(store.has(FORMAT_ID, "2026-09", 1760, LadderReducer.REDUCTION)).isTrue();
        assertThat(store.has(FORMAT_ID, "2026-09", 1760, LadderReducer.REDUCTION + 1)).as("made by an older rule").isFalse();
        assertThat(store.has(FORMAT_ID, "2026-09", 0, LadderReducer.REDUCTION)).isFalse();
    }

    @Test
    void aNewerRecordReplacesTheOldOne() {
        store.put(fetched("2026-09", 1760, 1));
        var later = fetched(FORMAT_ID, "2026-09", 1760, 0.5, FETCHED.plusSeconds(60));
        assertThat(store.put(later)).isTrue();
        assertThat(store.find(FORMAT_ID, "2026-09", 1760).orElseThrow().stats()).isEqualTo(later.stats());
        assertThat(jdbc.queryForObject("select count(*) from ladder_stats", Integer.class)).isEqualTo(1);

        // The topic read again from the start delivers the older record after the newer one.
        assertThat(store.put(fetched("2026-09", 1760, 1))).isFalse();
        assertThat(store.find(FORMAT_ID, "2026-09", 1760).orElseThrow().stats()).isEqualTo(later.stats());

        // A newer rule's record wins whenever it was fetched; an older rule's never does.
        var newRule = reducedBy(fetched(FORMAT_ID, "2026-09", 1760, 0.25, FETCHED.minusSeconds(60)), LadderReducer.REDUCTION + 1);
        assertThat(store.put(newRule)).isTrue();
        assertThat(store.put(fetched(FORMAT_ID, "2026-09", 1760, 1, FETCHED.plusSeconds(600)))).isFalse();
        assertThat(store.find(FORMAT_ID, "2026-09", 1760).orElseThrow().stats()).isEqualTo(newRule.stats());
    }

    @Test
    void listsWhatsStored() {
        store.put(fetched("2026-08", 1760, 1));
        store.put(fetched("2026-09", 1760, 1));
        store.put(fetched("2026-09", 0, 1));
        store.put(fetched(BSS, "2026-09", 1500, 1, FETCHED));

        var index = service.index().stats();
        assertThat(index).extracting(e -> e.format() + " " + e.month() + " " + e.rating()).containsExactly(
                BSS + " 2026-09 1500", FORMAT_ID + " 2026-09 0", FORMAT_ID + " 2026-09 1760", FORMAT_ID + " 2026-08 1760");
        assertThat(index.get(0).mode()).isEqualTo("singles");
        assertThat(index.get(1).regulation()).isEqualTo("M-C");
        assertThat(index.get(1).mode()).isEqualTo("doubles");
        assertThat(index.get(1).bestOf()).isEqualTo(1);
        assertThat(index.get(1).battles()).isEqualTo(1_631_943);
        assertThat(index.get(1).fetchedAt()).isEqualTo(FETCHED);
        assertThat(store.newestMonth(FORMAT_ID, 1760)).contains("2026-09");
        assertThat(store.newestMonth(FORMAT_ID, 1500)).isEmpty();
    }

    @Test
    void servesAMonthWithItsTrendAndTheOtherRatings() {
        // August at 80% of September's usage, and every player at half of 1760's.
        store.put(fetched("2026-08", 1760, 0.8));
        store.put(fetched("2026-09", 1760, 1));
        store.put(fetched("2026-09", 0, 0.5));
        // August without Rillaboom at every rating: only 1760's matters for the trend.
        store.put(fetched("2026-08", 0, 0.1));

        var stats = service.stats(FORMAT_ID, null, null);
        assertThat(stats.month()).as("the newest").isEqualTo("2026-09");
        assertThat(stats.rating()).as("1760 unless asked").isEqualTo(1760);
        assertThat(stats.previousMonth()).isEqualTo("2026-08");
        assertThat(stats.ratings()).containsExactly(0, 1760);
        assertThat(stats.fetchedAt()).isEqualTo(FETCHED);
        assertThat(stats.pokemon()).hasSize(27);

        var rillaboom = stats.pokemon().get(0);
        assertThat(rillaboom.name()).isEqualTo("Rillaboom");
        assertThat(rillaboom.usage()).isEqualTo(0.4659939);
        assertThat(rillaboom.trend()).isCloseTo(0.4659939 * 0.2, within(1e-12));
        assertThat(rillaboom.usageByRating()).containsExactly(
                new LadderResponses.RatingUsage(0, 0.4659939 * 0.5), new LadderResponses.RatingUsage(1760, 0.4659939));
        // The rest is the stored record's.
        Pokemon stored = LadderFixtures.stats().pokemon().get(0);
        assertThat(rillaboom.items()).isEqualTo(stored.items());
        assertThat(rillaboom.spreads()).isEqualTo(stored.spreads());
        assertThat(rillaboom.leadShare()).isEqualTo(stored.leadShare());

        var everyone = service.stats(FORMAT_ID, 0, "2026-09");
        assertThat(everyone.rating()).isEqualTo(0);
        assertThat(everyone.pokemon().get(0).usage()).isEqualTo(0.4659939 * 0.5);
        assertThat(everyone.pokemon().get(0).trend()).isCloseTo(0.4659939 * 0.4, within(1e-12));
    }

    @Test
    void noTrendWithoutTheMonthBefore() {
        store.put(fetched("2026-09", 1760, 1));
        // Two months back isn't the month before.
        store.put(fetched("2026-07", 1760, 0.5));
        // Nor is another rating's, or another format's.
        store.put(fetched("2026-08", 1500, 0.5));
        store.put(fetched(BSS, "2026-08", 1760, 0.5, FETCHED));

        var stats = service.stats(FORMAT_ID, 1760, "2026-09");
        assertThat(stats.previousMonth()).isNull();
        assertThat(stats.pokemon()).allSatisfy(p -> assertThat(p.trend()).isNull());
        assertThat(service.stats(FORMAT_ID, 1760, "2026-07").previousMonth()).as("January's is December").isNull();
    }

    /** A Pokémon Smogon didn't list the month before wasn't used: its trend is its whole usage. */
    @Test
    void aPokemonNewThisMonth() {
        var august = fetched("2026-08", 1760, 1);
        List<Pokemon> withoutRillaboom = august.stats().pokemon().subList(1, august.stats().pokemon().size());
        Stats s = august.stats();
        store.put(new StatsFetched(new Stats(s.reduction(), s.format(), s.regulation(), s.mode(), s.bestOf(), s.month(),
                s.rating(), s.battles(), withoutRillaboom), FETCHED));
        store.put(fetched("2026-09", 1760, 1));

        var stats = service.stats(FORMAT_ID, 1760, null);
        assertThat(stats.pokemon().get(0).trend()).isEqualTo(0.4659939);
        assertThat(stats.pokemon().get(1).trend()).isEqualTo(0.0);
    }

    @Test
    void whatIsntStoredIsntThere() {
        assertThatThrownBy(() -> service.stats(FORMAT_ID, null, null)).isInstanceOf(NoSuchElementException.class)
                .hasMessage("No ladder stats stored for " + FORMAT_ID + " at 1760");
        store.put(fetched("2026-09", 1760, 1));
        assertThatThrownBy(() -> service.stats(FORMAT_ID, 1500, null)).isInstanceOf(NoSuchElementException.class);
        assertThatThrownBy(() -> service.stats(FORMAT_ID, 1760, "2026-08")).isInstanceOf(NoSuchElementException.class)
                .hasMessage("No ladder stats stored for " + FORMAT_ID + " at 1760 in 2026-08");
        assertThatThrownBy(() -> service.stats("gen9ou", null, null)).isInstanceOf(NoSuchElementException.class);
        assertThat(service.index().stats()).hasSize(1);
    }
}
