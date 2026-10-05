package com.pkreference.backend.usage;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pkreference.backend.standardize.NameStandardizer;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest
@Import({UsageAggregationService.class, NameStandardizer.class, UsageAggregationServiceTest.Config.class})
class UsageAggregationServiceTest {
    @TestConfiguration
    static class Config {
        @Bean
        ObjectMapper objectMapper() {
            return new ObjectMapper();
        }
    }

    @Autowired UsageAggregationService service;
    @Autowired UsageCounterRepository counters;

    private long count(String category, String species, String value) {
        return counters.findById(UsageCounter.key("reg-m-a", category, species, "")
                .replace("|" + category + "|" + species + "|", "|" + category + "|" + species + "|" + value))
                .map(UsageCounter::getCount).orElse(0L);
    }

    @Test
    void countsTeamsSpeciesAndDetails() {
        var updates = service.apply(Fixtures.tournament("t1"));

        assertThat(count(UsageCounter.TEAMS, "*", "")).isEqualTo(4); // dropped player has no team
        assertThat(count(UsageCounter.SPECIES, "incineroar", "")).isEqualTo(4);
        assertThat(count(UsageCounter.SPECIES, "rillaboom", "")).isEqualTo(1);
        assertThat(count("ITEM", "incineroar", "Sitrus Berry")).isEqualTo(2);
        assertThat(count("MOVE", "incineroar", "Fake Out")).isEqualTo(3);
        assertThat(count("NATURE", "incineroar", "Jolly")).isEqualTo(3); // casing normalized
        assertThat(updates).hasSize(2);
        assertThat(updates).allSatisfy(u -> assertThat(u.totalTeams()).isEqualTo(4));
    }

    @Test
    void messyNamesCollapseIntoOneRow() {
        service.apply(Fixtures.tournament("t1"));

        // "Fake Out" / "Fake out" / "FAKE OUT" are one move; "Sitrus Berry" / "sitrus berry" one item.
        assertThat(count("MOVE", "incineroar", "Fake Out")).isEqualTo(3);
        assertThat(count("MOVE", "incineroar", "Fake out")).isZero();
        assertThat(count("ITEM", "incineroar", "Sitrus Berry")).isEqualTo(2);
        assertThat(count("ABILITY", "incineroar", "Intimidate")).isEqualTo(4);
        assertThat(count("ITEM", "incineroar", "Life Orb")).isEqualTo(1);
        assertThat(count("MOVE", "incineroar", "Darkest Lariat")).isEqualTo(1); // from "Darkest Larient"
    }

    @Test
    void replayingATournamentDoesNotDoubleCount() {
        service.apply(Fixtures.tournament("t1"));
        var replay = service.apply(Fixtures.tournament("t1"));

        assertThat(replay).isEmpty();
        assertThat(count(UsageCounter.SPECIES, "incineroar", "")).isEqualTo(4);
    }

    @Test
    void secondTournamentAccumulates() {
        service.apply(Fixtures.tournament("t1"));
        service.apply(Fixtures.tournament("t2"));

        assertThat(count(UsageCounter.TEAMS, "*", "")).isEqualTo(8);
        assertThat(count(UsageCounter.SPECIES, "incineroar", "")).isEqualTo(8);
    }
}
