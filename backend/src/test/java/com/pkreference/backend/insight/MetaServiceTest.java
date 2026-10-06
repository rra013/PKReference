package com.pkreference.backend.insight;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pkreference.backend.insight.MetaResponses.PokemonUsage;
import com.pkreference.backend.insight.MetaResponses.Share;
import com.pkreference.backend.model.Events.PairingsFetched;
import com.pkreference.backend.model.Events.StandingsFetched;
import com.pkreference.backend.model.Events.Tournament;
import com.pkreference.backend.standardize.NameStandardizer;
import com.pkreference.backend.standardize.SpeciesVocabularies;
import com.pkreference.backend.store.TeamStore;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.JdbcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.NoSuchElementException;

import static com.pkreference.backend.LimitlessFixtures.details;
import static com.pkreference.backend.LimitlessFixtures.pairings;
import static com.pkreference.backend.LimitlessFixtures.standings;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The insights over the real fixture event, on the migrations. The expected numbers were worked out
 * separately, in Python, from the fixture and the species golden file.
 */
@JdbcTest
@Import({TeamStore.class, SpeciesVocabularies.class, MetaRepository.class, MetaService.class,
        NameStandardizer.class, MetaServiceTest.Config.class})
class MetaServiceTest {
    /** The day after the event. */
    static final Instant NOW = Instant.parse("2026-10-06T12:00:00Z");

    @TestConfiguration
    static class Config {
        /** In place of the application's clock. */
        @Bean
        @Primary
        Clock fixedClock() {
            return Clock.fixed(NOW, ZoneOffset.UTC);
        }

        @Bean
        ObjectMapper objectMapper() {
            return new ObjectMapper();
        }
    }

    @Autowired TeamStore store;
    @Autowired MetaService meta;

    private void put(String id, String date, int teams) {
        var t = new Tournament(id, "Test Event", "VGC", "M-C", date, 83);
        store.putStandings(new StandingsFetched(t, standings().subList(0, teams), details(), NOW, true));
        store.putPairings(new PairingsFetched(t, pairings(), NOW));
    }

    @BeforeEach
    void setUp() {
        meta.forget();
        put("event-83", "2026-10-05T18:00:00.000Z", 83);
    }

    private static PokemonUsage find(List<PokemonUsage> list, String key) {
        return list.stream().filter(p -> p.key().equals(key)).findFirst().orElseThrow();
    }

    @Test
    void usageAndTopCut() {
        var list = meta.pokemon("M-C", MetaWindow.DAYS_30);
        assertThat(list.sample().events()).isEqualTo(1);
        assertThat(list.sample().teams()).isEqualTo(83);
        assertThat(list.sample().topCutTeams()).isEqualTo(16);
        assertThat(list.pokemon()).extracting(PokemonUsage::key)
                .startsWith("rillaboom", "incineroar", "gholdengo", "raichu", "garchomp", "sneasler");
        assertThat(list.pokemon().get(0))
                .isEqualTo(new PokemonUsage("rillaboom", 44, 0.5301, 9, 0.5625, null));
        assertThat(find(list.pokemon(), "garchomp")).isEqualTo(new PokemonUsage("garchomp", 26, 0.3133, 3, 0.1875, null));
        // The format's case doesn't matter.
        assertThat(meta.pokemon("m-c", MetaWindow.DAYS_30).sample().teams()).isEqualTo(83);
    }

    @Test
    void aPokemonsPage() {
        var rillaboom = meta.pokemon("M-C", "rillaboom", MetaWindow.DAYS_30);
        assertThat(rillaboom.items()).startsWith(new Share("Miracle Seed", 38, 0.8636), new Share("Eject Button", 4, 0.0909));
        assertThat(rillaboom.abilities()).containsExactly(new Share("Grassy Surge", 44, 1.0));
        assertThat(rillaboom.moves()).startsWith(new Share("Fake Out", 44, 1.0), new Share("Grassy Glide", 44, 1.0),
                new Share("Wood Hammer", 39, 0.8864));
        assertThat(rillaboom.teammates()).startsWith(new Share("gholdengo", 24, 0.5455), new Share("raichu", 24, 0.5455),
                new Share("incineroar", 23, 0.5227));
        var top = rillaboom.sets().get(0);
        assertThat(top.item()).isEqualTo("Miracle Seed");
        assertThat(top.nature()).isEqualTo("Adamant");
        assertThat(top.moves()).containsExactly("Fake Out", "Grassy Glide", "High Horsepower", "Wood Hammer");
        assertThat(top.count()).isEqualTo(24);
        assertThat(rillaboom.megaStones()).isEmpty();
        assertThat(rillaboom.weekly()).hasSize(1).first()
                .satisfies(w -> {
                    assertThat(w.week()).isEqualTo(LocalDate.of(2026, 10, 5));
                    assertThat(w.teams()).isEqualTo(83);
                    assertThat(w.withPokemon()).isEqualTo(44);
                });

        assertThat(meta.pokemon("M-C", "raichu", MetaWindow.DAYS_30).megaStones())
                .startsWith(new Share("raichunitey", 26, 0.9286));
        assertThatThrownBy(() -> meta.pokemon("M-C", "missingno", MetaWindow.DAYS_30))
                .isInstanceOf(NoSuchElementException.class);
    }

    @Test
    void windows() {
        put("older", "2026-09-01T18:00:00.000Z", 83);
        assertThat(meta.pokemon("M-C", MetaWindow.DAYS_14).sample().teams()).isEqualTo(83);
        assertThat(meta.pokemon("M-C", MetaWindow.DAYS_30).sample().teams()).isEqualTo(83);
        var all = meta.pokemon("M-C", MetaWindow.REGULATION);
        assertThat(all.sample().teams()).isEqualTo(166);
        assertThat(all.sample().events()).isEqualTo(2);
        assertThat(all.from()).isNull();
        assertThat(meta.formats().formats()).singleElement()
                .satisfies(f -> assertThat(f.teams()).isEqualTo(166));
    }

    /** The last 14 days (83 teams) against the 14 before (the first 60 teams of a copy). */
    @Test
    void trends() {
        put("three-weeks-ago", "2026-09-15T18:00:00.000Z", 60);
        var list = meta.pokemon("M-C", MetaWindow.DAYS_30);
        assertThat(find(list.pokemon(), "rillaboom").trend()).isEqualTo(-0.0199);
        assertThat(find(list.pokemon(), "incineroar").trend()).isEqualTo(-0.0024);
    }

    @Test
    void noTrendFromThinData() {
        put("three-weeks-ago", "2026-09-15T18:00:00.000Z", 40);
        assertThat(find(meta.pokemon("M-C", MetaWindow.DAYS_30).pokemon(), "rillaboom").trend()).isNull();
    }
}
