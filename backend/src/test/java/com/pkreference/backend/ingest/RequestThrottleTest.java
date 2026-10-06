package com.pkreference.backend.ingest;

import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;

import static org.assertj.core.api.Assertions.assertThat;

class RequestThrottleTest {
    /** A clock that only moves when the throttle sleeps, or a test moves it. */
    static final class FakeClock extends Clock {
        Instant now = Instant.parse("2026-10-06T00:00:00Z");
        Duration slept = Duration.ZERO;

        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }

        void sleep(Duration d) {
            slept = slept.plus(d);
            now = now.plus(d);
        }
    }

    private final FakeClock clock = new FakeClock();

    private RequestThrottle throttle(int limit) {
        return new RequestThrottle(limit, Duration.ofMinutes(5), clock, clock::sleep);
    }

    @Test
    void waitsForTheOldestRequestToLeaveTheWindow() throws InterruptedException {
        var throttle = throttle(3);
        throttle.acquire();
        throttle.acquire();
        throttle.acquire();
        assertThat(clock.slept).isZero();

        clock.now = clock.now.plus(Duration.ofMinutes(1));
        throttle.acquire(); // the first went at 0:00, so this waits until 5:00
        assertThat(clock.slept).isEqualTo(Duration.ofMinutes(4));

        throttle.acquire(); // the second and third also went at 0:00
        assertThat(clock.slept).isEqualTo(Duration.ofMinutes(4));
    }

    @Test
    void waitsOutLimitlessReset() throws InterruptedException {
        var throttle = throttle(40);
        throttle.observe("\"50-in-5min\"; r=12; t=200");
        throttle.acquire();
        assertThat(clock.slept).isZero();

        // The app on the same machine spent the rest.
        throttle.observe("\"50-in-5min\"; r=0; t=120");
        throttle.acquire();
        assertThat(clock.slept).isEqualTo(Duration.ofSeconds(120));
    }

    @Test
    void ignoresMissingAndUnreadableHeaders() throws InterruptedException {
        var throttle = throttle(40);
        throttle.observe(null);
        throttle.observe("garbage");
        throttle.observe("\"50-in-5min\"; r=0"); // no reset time
        throttle.acquire();
        assertThat(clock.slept).isZero();
    }
}
