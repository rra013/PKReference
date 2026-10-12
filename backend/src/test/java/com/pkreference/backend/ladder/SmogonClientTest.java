package com.pkreference.backend.ladder;

import com.pkreference.backend.config.SmogonProperties;
import com.pkreference.backend.ingest.RequestThrottle;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/** Smogon's listings and files, as its pages were on 2026-10-12, and the wait between requests. */
class SmogonClientTest {
    /** A clock that only moves when the throttle sleeps. */
    private static final class FakeClock extends Clock {
        Instant now = Instant.parse("2026-10-12T00:00:00Z");
        Duration slept = Duration.ZERO;

        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }

        void sleep(Duration d) {
            slept = slept.plus(d);
            now = now.plus(d);
        }
    }

    private static final String BASE = "https://www.smogon.com/stats";
    private static final String INDEX = """
            <html><head><title>Index of /stats/</title></head><body><h1>Index of /stats/</h1><hr><pre><a href="../">../</a>
            <a href="2014-11/">2014-11/</a>                                           01-Dec-2014 08:00       -
            <a href="2026-08/">2026-08/</a>                                           01-Sep-2026 23:16       -
            <a href="2026-09/">2026-09/</a>                                           01-Oct-2026 14:40       -
            <a href="2026-07/">2026-07/</a>                                           01-Aug-2026 20:01       -
            <a href="readme.txt">readme.txt</a>                                       01-Jan-2020 00:00     100
            </pre><hr></body></html>""";
    private static final String CHAOS = """
            <html><body><pre><a href="../">../</a>
            <a href="gen9championsbssregmc-0.json">gen9championsbssregmc-0.json</a>     01-Oct-2026 14:40    612931
            <a href="gen9championsvgc2026regmc-1760.json">gen9championsvgc2026regmc-1760.json</a>  01-Oct-2026 14:40   5850354
            <a href="gen9ou-1825.json">gen9ou-1825.json</a>                             01-Oct-2026 14:40  12345678
            <a href="notes.txt">notes.txt</a>                                           01-Oct-2026 14:40        12
            <a href="../../etc/passwd.json">odd</a>
            <a href="Weird%20Name-0.json">odd</a>
            </pre></body></html>""";

    private final FakeClock clock = new FakeClock();
    private final RestClient.Builder builder = RestClient.builder();
    private final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    private final SmogonClient client = new SmogonClient(builder, SmogonProperties.defaults(),
            new RequestThrottle(1, Duration.ofSeconds(2), clock, clock::sleep));

    @Test
    void listsMonthsNewestFirstAndAMonthsFiles() {
        server.expect(requestTo(BASE + "/")).andExpect(header("User-Agent", "PKReference-backend"))
                .andRespond(withSuccess(INDEX, MediaType.TEXT_HTML));
        server.expect(requestTo(BASE + "/2026-09/chaos/")).andRespond(withSuccess(CHAOS, MediaType.TEXT_HTML));

        assertThat(client.months()).containsExactly("2026-09", "2026-08", "2026-07", "2014-11");
        // Only names that are plainly stats files: nothing with a path or an escape in it.
        assertThat(client.chaosFiles("2026-09")).containsExactly(
                "gen9championsbssregmc-0.json", "gen9championsvgc2026regmc-1760.json", "gen9ou-1825.json");
        server.verify();
    }

    @Test
    void readsFilesOneAtATime() {
        server.expect(requestTo(BASE + "/2026-09/chaos/gen9championsbssregmc-0.json"))
                .andRespond(withSuccess("{\"data\": {}}", MediaType.APPLICATION_JSON));
        server.expect(requestTo(BASE + "/2026-09/leads/gen9championsbssregmc-0.txt"))
                .andRespond(withSuccess(" Total leads: 2\n", MediaType.TEXT_PLAIN));
        server.expect(requestTo(BASE + "/2026-09/leads/gen9championsbssregmc-1500.txt"))
                .andRespond(withStatus(HttpStatus.NOT_FOUND));

        String body = client.chaos("2026-09", "gen9championsbssregmc-0.json",
                in -> new String(in.readAllBytes(), StandardCharsets.UTF_8));
        assertThat(body).isEqualTo("{\"data\": {}}");
        assertThat(clock.slept).isZero();
        assertThat(client.leads("2026-09", "gen9championsbssregmc-0.txt")).isEqualTo(" Total leads: 2\n");
        assertThat(clock.slept).as("two seconds after the request before").isEqualTo(Duration.ofSeconds(2));
        assertThat(client.leads("2026-09", "gen9championsbssregmc-1500.txt")).as("no leads file").isNull();
        assertThat(clock.slept).isEqualTo(Duration.ofSeconds(4));
        server.verify();
    }

    @Test
    void aFailureIsAnError() {
        server.expect(requestTo(BASE + "/2026-09/chaos/gen9championsbssregmc-0.json"))
                .andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));
        server.expect(requestTo(BASE + "/")).andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));
        assertThatThrownBy(() -> client.chaos("2026-09", "gen9championsbssregmc-0.json", in -> "read"))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("503");
        assertThatThrownBy(client::months).isInstanceOf(RestClientException.class);
    }

    /** Names go into the request's path, so only a month and a stats file's name are let through. */
    @Test
    void onlyStatsNamesGoIntoAPath() {
        assertThatThrownBy(() -> client.chaosFiles("../admin")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> client.chaos("2026-09", "../../secret.json", in -> "read"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> client.leads("2026-09", "a/b-0.txt")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> client.leads(null, "gen9championsbssregmc-0.txt")).isInstanceOf(IllegalArgumentException.class);
        server.verify();
    }
}
