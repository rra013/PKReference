package com.pkreference.backend.usage;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest
@Import(UsageAggregationService.class)
class UsageAggregationServiceTest {
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

        assertThat(count(UsageCounter.TEAMS, "*", "")).isEqualTo(2); // dropped player has no team
        assertThat(count(UsageCounter.SPECIES, "incineroar", "")).isEqualTo(2);
        assertThat(count(UsageCounter.SPECIES, "rillaboom", "")).isEqualTo(1);
        assertThat(count("ITEM", "incineroar", "Sitrus Berry")).isEqualTo(1);
        assertThat(count("MOVE", "incineroar", "Fake Out")).isEqualTo(2);
        assertThat(count("NATURE", "incineroar", "jolly")).isEqualTo(2); // casing normalized
        assertThat(updates).hasSize(2);
        assertThat(updates).allSatisfy(u -> assertThat(u.totalTeams()).isEqualTo(2));
    }

    @Test
    void replayingATournamentDoesNotDoubleCount() {
        service.apply(Fixtures.tournament("t1"));
        var replay = service.apply(Fixtures.tournament("t1"));

        assertThat(replay).isEmpty();
        assertThat(count(UsageCounter.SPECIES, "incineroar", "")).isEqualTo(2);
    }

    @Test
    void secondTournamentAccumulates() {
        service.apply(Fixtures.tournament("t1"));
        service.apply(Fixtures.tournament("t2"));

        assertThat(count(UsageCounter.TEAMS, "*", "")).isEqualTo(4);
        assertThat(count(UsageCounter.SPECIES, "incineroar", "")).isEqualTo(4);
    }
}
