package com.pkreference.backend.ingest;

import com.pkreference.backend.config.LimitlessProperties;
import com.pkreference.backend.model.Events.Pairing;
import com.pkreference.backend.model.Events.Standing;
import com.pkreference.backend.model.Events.Tournament;
import com.pkreference.backend.model.Events.TournamentDetails;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.client.ClientHttpRequestInterceptor;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

import java.io.InterruptedIOException;
import java.time.Clock;
import java.util.List;

/** Thin client for the Limitless play API, same endpoints as the app's LimitlessAPI actor. */
@Component
public class LimitlessClient {
    private static final Logger log = LoggerFactory.getLogger(LimitlessClient.class);
    private static final int MAX_ATTEMPTS = 3;

    private final RestClient http;
    private final LimitlessProperties props;

    @Autowired
    public LimitlessClient(RestClient.Builder builder, LimitlessProperties props) {
        this(builder, props, new RequestThrottle(props.requestsPerWindow(), props.window(),
                Clock.systemUTC(), d -> Thread.sleep(d.toMillis())));
    }

    LimitlessClient(RestClient.Builder builder, LimitlessProperties props, RequestThrottle throttle) {
        this.props = props;
        // Every request, retries included, waits its turn and reports Limitless's count back.
        ClientHttpRequestInterceptor throttled = (request, body, execution) -> {
            try {
                throttle.acquire();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new InterruptedIOException("Interrupted waiting to call Limitless");
            }
            var response = execution.execute(request, body);
            throttle.observe(response.getHeaders().getFirst("ratelimit"));
            return response;
        };
        this.http = builder.baseUrl(props.baseUrl()).requestInterceptor(throttled).build();
    }

    /** One page of the game's tournaments, newest first: all formats when format is null. */
    public List<Tournament> tournaments(String format, int page) {
        return withRetry(() -> http.get().uri(uri -> {
            var b = uri.path("/tournaments").queryParam("limit", props.pageSize()).queryParam("page", page);
            if (props.game() != null && !props.game().isBlank()) b.queryParam("game", props.game());
            if (format != null && !format.isBlank()) b.queryParam("format", format);
            return b.build();
        }).retrieve().body(new ParameterizedTypeReference<List<Tournament>>() {}));
    }

    public TournamentDetails details(String tournamentId) {
        return withRetry(() -> http.get().uri("/tournaments/{id}/details", tournamentId)
                .retrieve().body(TournamentDetails.class));
    }

    public List<Standing> standings(String tournamentId) {
        return withRetry(() -> http.get().uri("/tournaments/{id}/standings", tournamentId)
                .retrieve().body(new ParameterizedTypeReference<List<Standing>>() {}));
    }

    /** The event's matches; none for an event Limitless has no pairings for (HTTP 404). */
    public List<Pairing> pairings(String tournamentId) {
        try {
            return withRetry(() -> http.get().uri("/tournaments/{id}/pairings", tournamentId)
                    .retrieve().body(new ParameterizedTypeReference<List<Pairing>>() {}));
        } catch (HttpClientErrorException.NotFound e) {
            return List.of();
        }
    }

    /** Honors 429 + Retry-After (capped at 30s), like LimitlessAPI.swift. */
    private <T> T withRetry(java.util.function.Supplier<T> call) {
        for (int attempt = 1; ; attempt++) {
            try {
                return call.get();
            } catch (HttpClientErrorException.TooManyRequests e) {
                if (attempt >= MAX_ATTEMPTS) throw e;
                long waitSeconds = retryAfterSeconds(e);
                log.warn("Limitless rate limited; retrying in {}s (attempt {})", waitSeconds, attempt);
                try {
                    Thread.sleep(waitSeconds * 1000);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw e;
                }
            }
        }
    }

    private static long retryAfterSeconds(HttpClientErrorException e) {
        var header = e.getResponseHeaders() == null ? null : e.getResponseHeaders().getFirst("Retry-After");
        try {
            return Math.min(30, Math.max(1, Long.parseLong(header)));
        } catch (NumberFormatException ex) {
            return 5;
        }
    }
}
