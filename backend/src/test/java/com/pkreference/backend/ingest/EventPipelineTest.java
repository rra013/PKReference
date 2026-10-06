package com.pkreference.backend.ingest;

import com.pkreference.backend.config.Topics;
import com.pkreference.backend.model.Events.Tournament;
import com.pkreference.backend.model.Events.TournamentDiscovered;
import com.pkreference.backend.usage.UsageCounter;
import com.pkreference.backend.usage.UsageCounterRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.test.context.EmbeddedKafka;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.time.Duration;
import java.time.Instant;

import static com.pkreference.backend.LimitlessFixtures.details;
import static com.pkreference.backend.LimitlessFixtures.pairings;
import static com.pkreference.backend.LimitlessFixtures.standings;
import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

/**
 * tournaments.discovered -> the fetcher (Limitless mocked with the fixture event) -> both topics ->
 * the team store and the usage counters, on an in-JVM broker.
 */
@SpringBootTest
@EmbeddedKafka(partitions = 1, topics = {Topics.TOURNAMENTS_DISCOVERED, Topics.STANDINGS_FETCHED, Topics.PAIRINGS_FETCHED})
@TestPropertySource(properties = {
        "spring.kafka.bootstrap-servers=${spring.embedded.kafka.brokers}",
        "spring.datasource.url=jdbc:h2:mem:events;DB_CLOSE_DELAY=-1",
        "pkref.limitless.ingest-enabled=false"})
class EventPipelineTest {
    @MockitoBean LimitlessClient limitless;
    @Autowired KafkaTemplate<String, Object> kafka;
    @Autowired JdbcTemplate jdbc;
    @Autowired UsageCounterRepository counters;

    private int count(String sql, Object... args) {
        return jdbc.queryForObject(sql, Integer.class, args);
    }

    private void discover(Tournament t) {
        when(limitless.details(anyString())).thenReturn(details());
        when(limitless.standings(anyString())).thenReturn(standings());
        when(limitless.pairings(anyString())).thenReturn(pairings());
        kafka.send(Topics.TOURNAMENTS_DISCOVERED, t.id(), new TournamentDiscovered(t));
    }

    @Test
    void aSettledEventIsFetchedStoredAndCounted() {
        var t = new Tournament("settled", "Settled", "VGC", "SETTLED", Instant.now().minus(Duration.ofDays(10)).toString(), 83);
        discover(t);

        await().atMost(Duration.ofSeconds(30)).untilAsserted(() -> {
            assertThat(count("select count(*) from team where event_id = 'settled'")).isEqualTo(83);
            assertThat(count("select count(*) from pairing where event_id = 'settled'")).isEqualTo(188);
            assertThat(count("select count(*) from event_fetch where event_id = 'settled' and standings_final and fetched_at is not null"))
                    .isEqualTo(1);
            assertThat(counters.findById(UsageCounter.key("SETTLED", UsageCounter.TEAMS, UsageCounter.TOTAL_SPECIES, "")))
                    .get().extracting(UsageCounter::getCount).isEqualTo(83L);
        });
        assertThat(count("select count(*) from event_phase where event_id = 'settled'")).isEqualTo(2);
    }

    /** Stored so the app can see it, but not counted until its standings settle. */
    @Test
    void anUnsettledEventIsStoredButNotCounted() {
        var t = new Tournament("running", "Running", "VGC", "RUNNING", Instant.now().minus(Duration.ofHours(3)).toString(), 83);
        discover(t);

        await().atMost(Duration.ofSeconds(30)).untilAsserted(() ->
                assertThat(count("select count(*) from event_fetch where event_id = 'running' and fetched_at is not null"))
                        .isEqualTo(1));
        await().atMost(Duration.ofSeconds(10)).untilAsserted(() ->
                assertThat(count("select count(*) from team where event_id = 'running'")).isEqualTo(83));
        assertThat(count("select count(*) from event where id = 'running' and not standings_final")).isEqualTo(1);
        assertThat(count("select count(*) from event_fetch where event_id = 'running' and not standings_final")).isEqualTo(1);
        assertThat(counters.findById(UsageCounter.key("RUNNING", UsageCounter.TEAMS, UsageCounter.TOTAL_SPECIES, "")))
                .isEmpty();
    }
}
