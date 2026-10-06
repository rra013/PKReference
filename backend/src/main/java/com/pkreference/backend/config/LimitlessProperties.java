package com.pkreference.backend.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.time.Duration;
import java.util.List;

/**
 * Limitless and how events are found. minPlayers, settleAfter and refetchAfter match the app's
 * TeamCorpusConfiguration, so the server keeps the events Team Search would.
 */
@ConfigurationProperties(prefix = "pkref.limitless")
public record LimitlessProperties(
        String baseUrl,
        String game,
        /** Limitless format ids ("M-C"); none lists every format of the game. */
        List<String> formats,
        int pageSize,
        boolean ingestEnabled,
        Duration pollInterval,
        /** Requests allowed in each `window`. Limitless allows 50 in 5 minutes without a key. */
        int requestsPerWindow,
        Duration window,
        /** Smaller events say little about what's popular. */
        int minPlayers,
        /** How far back each poll walks the list. Longer once to backfill. */
        Duration lookback,
        /** Stops the walk even if Limitless keeps returning events in range. */
        int maxPages,
        /** Standings fetched this long after an event's start are final. */
        Duration settleAfter,
        /** Standings that aren't final are fetched again this often. */
        Duration refetchAfter,
        /** A requested event not fetched in this long (the request was lost) is requested again. */
        Duration pendingTimeout) {

    /** Every default, for one game and its formats. */
    public static LimitlessProperties defaults(String game, List<String> formats) {
        return new LimitlessProperties(null, game, formats, 0, true, null, 0, null, 0, null, 0, null, null, null);
    }

    public LimitlessProperties {
        if (baseUrl == null) baseUrl = "https://play.limitlesstcg.com/api";
        formats = formats == null ? List.of() : formats.stream().map(String::trim).filter(f -> !f.isEmpty()).toList();
        if (pageSize <= 0) pageSize = 50;
        if (pollInterval == null) pollInterval = Duration.ofMinutes(30);
        if (requestsPerWindow <= 0) requestsPerWindow = 40;
        if (window == null) window = Duration.ofMinutes(5);
        if (minPlayers <= 0) minPlayers = 16;
        if (lookback == null) lookback = Duration.ofDays(7);
        if (maxPages <= 0) maxPages = 40;
        if (settleAfter == null) settleAfter = Duration.ofHours(48);
        if (refetchAfter == null) refetchAfter = Duration.ofHours(6);
        if (pendingTimeout == null) pendingTimeout = Duration.ofHours(24);
    }
}
