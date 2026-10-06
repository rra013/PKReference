package com.pkreference.backend.ingest;

import com.pkreference.backend.config.LimitlessProperties;
import com.pkreference.backend.ingest.FetchPolicy.EventFetch;
import com.pkreference.backend.model.Events.Tournament;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** The app's rules: 16 players or more, final 48 hours after the start, refetched every 6 hours. */
class FetchPolicyTest {
    private static final Instant NOW = Instant.parse("2026-10-06T12:00:00Z");
    private final LimitlessProperties props = LimitlessProperties.defaults("VGC", List.of("M-C"));

    private static Tournament event(Duration ago, int players) {
        return new Tournament("e", "Event", "VGC", "M-C", NOW.minus(ago).toString(), players);
    }

    private boolean asks(Tournament t, EventFetch state) {
        return FetchPolicy.shouldRequest(t, state, NOW, props);
    }

    @Test
    void newEvents() {
        assertThat(asks(event(Duration.ofHours(30), 40), null)).isTrue();
        assertThat(asks(event(Duration.ofHours(30), 16), null)).isTrue();
        assertThat(asks(event(Duration.ofHours(30), 15), null)).as("too small").isFalse();
        assertThat(asks(event(Duration.ofHours(-2), 40), null)).as("not started").isFalse();
        assertThat(asks(event(Duration.ofDays(8), 40), null)).as("before the lookback").isFalse();
        assertThat(asks(new Tournament("e", "Event", "VGC", "M-C", "soon", 40), null)).as("unreadable date").isFalse();
    }

    @Test
    void askedForAndFetched() {
        var t = event(Duration.ofHours(30), 40);
        assertThat(asks(t, new EventFetch("e", NOW.minus(Duration.ofHours(1)), null, false))).as("in the queue").isFalse();
        assertThat(asks(t, new EventFetch("e", NOW.minus(Duration.ofHours(25)), null, false))).as("lost").isTrue();
        assertThat(asks(t, new EventFetch("e", NOW.minus(Duration.ofHours(3)), NOW.minus(Duration.ofHours(2)), false)))
                .as("fetched lately, not final").isFalse();
        assertThat(asks(t, new EventFetch("e", NOW.minus(Duration.ofHours(8)), NOW.minus(Duration.ofHours(7)), false)))
                .as("due again").isTrue();
        assertThat(asks(t, new EventFetch("e", NOW.minus(Duration.ofHours(8)), NOW.minus(Duration.ofHours(7)), true)))
                .as("final").isFalse();
        // Asked again after it was fetched: waiting in the queue.
        assertThat(asks(t, new EventFetch("e", NOW.minus(Duration.ofHours(1)), NOW.minus(Duration.ofHours(7)), false)))
                .isFalse();
    }

    @Test
    void finalFortyEightHoursAfterTheStart() {
        var t = event(Duration.ZERO, 40);
        assertThat(FetchPolicy.isFinal(t, NOW.plus(Duration.ofHours(47)), props.settleAfter())).isFalse();
        assertThat(FetchPolicy.isFinal(t, NOW.plus(Duration.ofHours(48)), props.settleAfter())).isTrue();
    }
}
