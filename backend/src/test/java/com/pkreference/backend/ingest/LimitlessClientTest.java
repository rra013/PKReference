package com.pkreference.backend.ingest;

import com.pkreference.backend.config.LimitlessProperties;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.startsWith;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/** Every request goes through the throttle, which hears Limitless's own count. */
class LimitlessClientTest {
    @Test
    void waitsWhenLimitlessSaysNoneAreLeft() {
        var clock = new RequestThrottleTest.FakeClock();
        var throttle = new RequestThrottle(40, Duration.ofMinutes(5), clock, clock::sleep);
        var builder = RestClient.builder();
        var server = MockRestServiceServer.bindTo(builder).build();
        var props = new LimitlessProperties(null, "VGC", "M-C", 0, false, null, 0, null);
        var client = new LimitlessClient(builder, props, throttle);

        var spent = new HttpHeaders();
        spent.add("ratelimit", "\"50-in-5min\"; r=0; t=90");
        server.expect(requestTo(startsWith("https://play.limitlesstcg.com/api/tournaments?")))
                .andRespond(withSuccess("[]", MediaType.APPLICATION_JSON).headers(spent));
        server.expect(requestTo("https://play.limitlesstcg.com/api/tournaments/abc/standings"))
                .andRespond(withSuccess("[]", MediaType.APPLICATION_JSON));

        assertThat(client.tournaments(1)).isEmpty();
        assertThat(clock.slept).isZero();
        assertThat(client.standings("abc")).isEmpty();
        assertThat(clock.slept).isEqualTo(Duration.ofSeconds(90));
        server.verify();
    }
}
