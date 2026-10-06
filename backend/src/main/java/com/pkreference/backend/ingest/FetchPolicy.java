package com.pkreference.backend.ingest;

import com.pkreference.backend.config.LimitlessProperties;
import com.pkreference.backend.model.Events.Tournament;

import java.time.Duration;
import java.time.Instant;
import java.time.format.DateTimeParseException;

/**
 * Which listed events to fetch: the app's rules (TeamCorpusStore). Events of at least minPlayers
 * that have started, within the lookback. Each is fetched once its standings are final (fetched
 * settleAfter after it started) and again every refetchAfter until then.
 */
public final class FetchPolicy {
    private FetchPolicy() {}

    /** What's been asked for and fetched of one event (EventFetchRepository). */
    public record EventFetch(String eventId, Instant requestedAt, Instant fetchedAt, boolean standingsFinal) {
        /** Asked for, and not fetched since. */
        boolean isPending() {
            return fetchedAt == null || fetchedAt.isBefore(requestedAt);
        }
    }

    public static boolean shouldRequest(Tournament t, EventFetch state, Instant now, LimitlessProperties p) {
        if (t.players() < p.minPlayers()) return false;
        Instant date = startOf(t);
        if (date == null || date.isAfter(now) || date.isBefore(now.minus(p.lookback()))) return false;
        if (state == null) return true;
        if (state.standingsFinal()) return false;
        // Waiting in the queue, which can be long while a backfill runs; asked again only if lost.
        if (state.isPending()) return state.requestedAt().isBefore(now.minus(p.pendingTimeout()));
        return state.fetchedAt().isBefore(now.minus(p.refetchAfter()));
    }

    /** Standings fetched settleAfter after the event started won't change. */
    public static boolean isFinal(Tournament t, Instant fetchedAt, Duration settleAfter) {
        Instant date = startOf(t);
        return date != null && !fetchedAt.isBefore(date.plus(settleAfter));
    }

    /** The event's start, or null when Limitless's date doesn't read. */
    public static Instant startOf(Tournament t) {
        if (t.date() == null || t.date().isBlank()) return null;
        try {
            return Instant.parse(t.date());
        } catch (DateTimeParseException e) {
            return null;
        }
    }
}
