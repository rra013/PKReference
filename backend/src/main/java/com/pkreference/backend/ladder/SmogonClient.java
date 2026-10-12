package com.pkreference.backend.ladder;

import com.pkreference.backend.config.SmogonProperties;
import com.pkreference.backend.ingest.RequestThrottle;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.client.ClientHttpRequestInterceptor;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

import java.io.IOException;
import java.io.InputStream;
import java.io.InterruptedIOException;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Smogon's monthly stats (https://www.smogon.com/stats/): plain directory listings and files, the
 * ones the app's SmogonLiveFetcher reads. They're a courtesy, not an API, so requests go one at a
 * time with a gap between them.
 */
@Component
public class SmogonClient {
    /** Reads a response's body while it downloads. */
    public interface BodyReader<T> {
        T read(InputStream body) throws IOException;
    }

    private static final Pattern HREF = Pattern.compile("href=\"([^\"]+)\"");
    private static final Pattern MONTH_LINK = Pattern.compile("^(\\d{4}-\\d{2})/$");
    private static final Pattern MONTH = Pattern.compile("^\\d{4}-\\d{2}$");
    /** A stats file's name: only these go into a request's path. */
    private static final Pattern FILE = Pattern.compile("^[a-z0-9]+-\\d+\\.(json|txt)$");

    private final RestClient http;

    /**
     * The constructor Spring uses. It gives the client timeouts, and a throttle of one request per
     * {@code requestGap} (2 seconds) on the real clock.
     */
    @Autowired
    public SmogonClient(RestClient.Builder builder, SmogonProperties props) {
        this(builder.requestFactory(timeouts()), props,
                new RequestThrottle(1, props.requestGap(), Clock.systemUTC(), d -> Thread.sleep(d.toMillis())));
    }

    /**
     * For tests, which pass a throttle on a fake clock and a builder bound to a mock server. Every
     * request waits for its turn in the throttle first, and names the project in its User-Agent.
     */
    SmogonClient(RestClient.Builder builder, SmogonProperties props, RequestThrottle throttle) {
        ClientHttpRequestInterceptor throttled = (request, body, execution) -> {
            try {
                throttle.acquire();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new InterruptedIOException("Interrupted waiting to call Smogon");
            }
            return execution.execute(request, body);
        };
        this.http = builder.baseUrl(props.baseUrl())
                .defaultHeader(HttpHeaders.USER_AGENT, props.userAgent())
                .requestInterceptor(throttled).build();
    }

    /** A stuck connection would hold the scheduler's thread for good. */
    private static SimpleClientHttpRequestFactory timeouts() {
        var factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(10));
        factory.setReadTimeout(Duration.ofSeconds(60));
        return factory;
    }

    /** The months with stats, newest first: "2026-09". */
    public List<String> months() {
        List<String> months = new ArrayList<>();
        for (String link : links("/")) {
            Matcher m = MONTH_LINK.matcher(link);
            if (m.matches()) months.add(m.group(1));
        }
        months.sort(Comparator.reverseOrder());
        return months;
    }

    /** The files in a month's chaos directory: "gen9championsvgc2026regmc-1760.json". */
    public List<String> chaosFiles(String month) {
        return links("/" + checked(MONTH, month) + "/chaos/").stream()
                .filter(f -> f.endsWith(".json") && FILE.matcher(f).matches()).toList();
    }

    /** A chaos file, read as it downloads: the biggest are over 7 MB. */
    public <T> T chaos(String month, String file, BodyReader<T> reader) {
        return http.get().uri("/{month}/chaos/{file}", checked(MONTH, month), checked(FILE, file))
                .exchange((request, response) -> {
                    if (!response.getStatusCode().is2xxSuccessful()) {
                        throw new IllegalStateException("Smogon returned " + response.getStatusCode().value() + " for " + file);
                    }
                    return reader.read(response.getBody());
                });
    }

    /** A leads file ("gen9championsvgc2026regmc-1760.txt"), or null when Smogon has none (HTTP 404). */
    public String leads(String month, String file) {
        try {
            return text(http.get().uri("/{month}/leads/{file}", checked(MONTH, month), checked(FILE, file))
                    .retrieve().body(byte[].class));
        } catch (HttpClientErrorException.NotFound e) {
            return null;
        }
    }

    /** The link targets on a directory listing. */
    private List<String> links(String path) {
        String html = text(http.get().uri(path).retrieve().body(byte[].class));
        List<String> links = new ArrayList<>();
        Matcher m = HREF.matcher(html);
        while (m.find()) links.add(m.group(1));
        return links;
    }

    /**
     * A response's bytes as text. Read as bytes and decoded here, so the encoding is UTF-8 whatever
     * the server's headers say.
     */
    private static String text(byte[] body) {
        return body == null ? "" : new String(body, StandardCharsets.UTF_8);
    }

    /**
     * Returns {@code value} only when it matches {@code pattern}. Month and file names come from
     * Smogon's own listing page and go into the next request's path, so anything that isn't plainly
     * a month or a stats file's name ("../", a full URL) is refused here rather than requested.
     */
    private static String checked(Pattern pattern, String value) {
        if (value == null || !pattern.matcher(value).matches()) {
            throw new IllegalArgumentException("Not a Smogon stats name: " + value);
        }
        return value;
    }
}
