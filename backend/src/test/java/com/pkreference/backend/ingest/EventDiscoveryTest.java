package com.pkreference.backend.ingest;

import com.pkreference.backend.config.LimitlessProperties;
import com.pkreference.backend.model.Events.Tournament;
import com.pkreference.backend.model.Events.TournamentDiscovered;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.JdbcTest;
import org.springframework.context.annotation.Import;
import org.springframework.kafka.core.KafkaTemplate;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.CompletableFuture;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** Discovery against a canned list, with the event_fetch table on the real migrations. */
@JdbcTest
@Import(EventFetchRepository.class)
class EventDiscoveryTest {
    @Autowired EventFetchRepository fetches;

    private final LimitlessClient client = mock(LimitlessClient.class);
    @SuppressWarnings("unchecked")
    private final KafkaTemplate<String, Object> kafka = mock(KafkaTemplate.class);
    private final RequestThrottleTest.FakeClock clock = new RequestThrottleTest.FakeClock();
    /** Pages of 3, so the walk goes over pages. */
    private final LimitlessProperties props = new LimitlessProperties(null, "VGC", List.of("M-C"), 3, true, null,
            0, null, 0, null, 0, null, null, null);
    private EventDiscovery discovery;

    private Tournament event(String id, Duration ago, int players) {
        return new Tournament(id, id, "VGC", "M-C", clock.now.minus(ago).toString(), players);
    }

    @BeforeEach
    void setUp() {
        clock.now = Instant.parse("2026-10-06T12:00:00Z");
        when(kafka.send(anyString(), anyString(), any())).thenReturn(CompletableFuture.completedFuture(null));
        when(client.tournaments(eq("M-C"), eq(1))).thenReturn(List.of(
                event("tomorrow", Duration.ofHours(-20), 40), event("recent", Duration.ofDays(1), 40),
                event("small", Duration.ofDays(1), 8)));
        when(client.tournaments(eq("M-C"), eq(2))).thenReturn(List.of(
                event("three-days", Duration.ofDays(3), 30), event("six-days", Duration.ofDays(6), 20),
                event("nine-days", Duration.ofDays(9), 50)));
        when(client.tournaments(eq("M-C"), eq(3))).thenReturn(List.of(
                event("ten-days", Duration.ofDays(10), 30), event("eleven-days", Duration.ofDays(11), 30),
                event("twelve-days", Duration.ofDays(12), 30)));
        discovery = new EventDiscovery(client, fetches, kafka, props, clock);
    }

    @Test
    void walksBackThroughTheLookback() {
        assertThat(discovery.discover("M-C")).containsExactly("recent", "three-days", "six-days");
        verify(kafka).send(eq("tournaments.discovered"), eq("recent"), any(TournamentDiscovered.class));
        // Page 3 started before the lookback, so the walk stopped there.
        verify(client, never()).tournaments(anyString(), eq(4));
    }

    @Test
    void asksOnceUntilItsDue() {
        discovery.discover("M-C");
        assertThat(discovery.discover("M-C")).as("all waiting in the queue").isEmpty();

        // Fetched: "recent" started a day ago, so it isn't final; the others are.
        var now = clock.now;
        fetches.markFetched(event("recent", Duration.ofDays(1), 40), now, false);
        fetches.markFetched(event("three-days", Duration.ofDays(3), 30), now, true);
        fetches.markFetched(event("six-days", Duration.ofDays(6), 20), now, true);
        assertThat(discovery.discover("M-C")).isEmpty();

        clock.now = clock.now.plus(Duration.ofHours(7));
        // "recent" is due again, though still not final; "tomorrow" hasn't started.
        assertThat(discovery.discover("M-C")).containsExactly("recent");
    }

    @Test
    void aLostRequestIsAskedAgain() {
        discovery.discover("M-C");
        clock.now = clock.now.plus(Duration.ofHours(25));
        // A day on, "tomorrow" has started and "six-days" is past the lookback.
        assertThat(discovery.discover("M-C")).containsExactly("tomorrow", "recent", "three-days");
    }

    @Test
    void failuresDontStopIt() {
        when(kafka.send(anyString(), eq("recent"), any())).thenReturn(CompletableFuture.failedFuture(new IllegalStateException("broker down")));
        assertThat(discovery.discover("M-C")).containsExactly("three-days", "six-days");
        when(kafka.send(anyString(), eq("recent"), any())).thenReturn(CompletableFuture.completedFuture(null));
        assertThat(discovery.discover("M-C")).as("not marked, so asked again").containsExactly("recent");

        when(client.tournaments(anyString(), anyInt())).thenThrow(new IllegalStateException("Limitless down"));
        assertThat(discovery.discover("M-C")).isEmpty();
    }
}
