package com.pkreference.backend.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.time.Duration;
import java.util.List;

/**
 * Smogon's monthly ladder stats and how they're fetched: the settings under {@code pkref.smogon} in
 * application.yml, bound into this record by Spring as LimitlessProperties is.
 */
@ConfigurationProperties(prefix = "pkref.smogon")
public record SmogonProperties(
        String baseUrl,
        boolean ingestEnabled,
        Duration pollInterval,
        /** How many of the newest months each poll looks at. More once to backfill. */
        int lookbackMonths,
        /** Smogon's rating cutoffs to keep. */
        List<Integer> ratings,
        /** The wait between two requests. */
        Duration requestGap,
        String userAgent) {

    /** Every default, with fetching on: what tests build a client or a discovery with. */
    public static SmogonProperties defaults() {
        return new SmogonProperties(null, true, null, 0, null, null, null);
    }

    /** Fills in a default for anything left out, as LimitlessProperties' compact constructor does. */
    public SmogonProperties {
        if (baseUrl == null) baseUrl = "https://www.smogon.com/stats";
        if (pollInterval == null) pollInterval = Duration.ofHours(12);
        if (lookbackMonths <= 0) lookbackMonths = 2;
        ratings = ratings == null || ratings.isEmpty() ? List.of(0, 1500, 1630, 1760) : List.copyOf(ratings);
        if (requestGap == null) requestGap = Duration.ofSeconds(2);
        if (userAgent == null || userAgent.isBlank()) userAgent = "PKReference-backend";
    }
}
