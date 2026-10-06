package com.pkreference.backend.ingest;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Keeps requests under a limit of `limit` in each `window`, as Limitless's keyless API allows
 * (50 in 5 minutes): a sliding window of the requests sent, plus what Limitless says is left.
 * The app shares the address when it runs on the same machine, so its requests count too, and
 * only Limitless's `ratelimit` header sees them.
 */
public class RequestThrottle {
    /** Sleeps, or in tests moves a clock on. */
    public interface Sleeper {
        void sleep(Duration duration) throws InterruptedException;
    }

    private static final Pattern REMAINING = Pattern.compile("(?:^|;)\\s*r=(\\d+)");
    private static final Pattern RESET = Pattern.compile("(?:^|;)\\s*t=(\\d+)");

    private final int limit;
    private final Duration window;
    private final Clock clock;
    private final Sleeper sleeper;
    private final Deque<Instant> sent = new ArrayDeque<>();
    private Instant blockedUntil = Instant.MIN;

    public RequestThrottle(int limit, Duration window, Clock clock, Sleeper sleeper) {
        if (limit < 1) throw new IllegalArgumentException("limit must be at least 1");
        this.limit = limit;
        this.window = window;
        this.clock = clock;
        this.sleeper = sleeper;
    }

    /** Waits until a request may go, and counts it. */
    public void acquire() throws InterruptedException {
        while (true) {
            Duration wait;
            synchronized (this) {
                Instant now = clock.instant();
                while (!sent.isEmpty() && !sent.peekFirst().plus(window).isAfter(now)) sent.pollFirst();
                Instant next = blockedUntil.isAfter(now) ? blockedUntil
                        : sent.size() >= limit ? sent.peekFirst().plus(window) : now;
                if (!next.isAfter(now)) {
                    sent.addLast(now);
                    return;
                }
                wait = Duration.between(now, next);
            }
            // Outside the lock, so other threads can still report headers.
            sleeper.sleep(wait);
        }
    }

    /**
     * Reads a response's `ratelimit` header, such as `"50-in-5min"; r=0; t=212`: with nothing
     * left, no request goes until the reset.
     */
    public synchronized void observe(String header) {
        if (header == null) return;
        Integer remaining = number(REMAINING.matcher(header));
        Integer reset = number(RESET.matcher(header));
        if (remaining != null && remaining == 0 && reset != null) {
            Instant until = clock.instant().plusSeconds(reset);
            if (until.isAfter(blockedUntil)) blockedUntil = until;
        }
    }

    private static Integer number(Matcher m) {
        return m.find() ? Integer.valueOf(m.group(1)) : null;
    }
}
