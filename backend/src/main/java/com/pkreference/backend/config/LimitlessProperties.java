package com.pkreference.backend.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.time.Duration;

@ConfigurationProperties(prefix = "pkref.limitless")
public record LimitlessProperties(
        String baseUrl,
        String game,
        String format,
        int pageSize,
        boolean ingestEnabled,
        Duration pollInterval,
        /** Requests allowed in each `window`. Limitless allows 50 in 5 minutes without a key. */
        int requestsPerWindow,
        Duration window) {

    public LimitlessProperties {
        if (baseUrl == null) baseUrl = "https://play.limitlesstcg.com/api";
        if (pageSize <= 0) pageSize = 50;
        if (pollInterval == null) pollInterval = Duration.ofMinutes(30);
        if (requestsPerWindow <= 0) requestsPerWindow = 40;
        if (window == null) window = Duration.ofMinutes(5);
    }
}
