package com.pkreference.backend.security;

import com.pkreference.backend.insight.MetaController;
import com.pkreference.backend.insight.MetaResponses.Formats;
import com.pkreference.backend.insight.MetaService;
import com.pkreference.backend.insight.MetaWebConfig;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.autoconfigure.flyway.FlywayAutoConfiguration;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;
import org.springframework.boot.autoconfigure.kafka.KafkaAutoConfiguration;
import org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.io.OutputStream;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

/**
 * Signing in, in a real Tomcat, with raw requests: a key is traded for a token and the token opens
 * /v1; and paths Tomcat rewrites before routing them (dot segments, encoded characters, ";"
 * parameters) reach neither /v1 without a token nor the token request without the key. Only the web
 * layer runs: no Kafka or database.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        classes = ApiAuthTomcatTest.Web.class,
        properties = "pkref.api.key-hashes=" + ApiAuthFilterTest.HASH)
class ApiAuthTomcatTest {
    @SpringBootConfiguration
    @EnableAutoConfiguration(exclude = {DataSourceAutoConfiguration.class, FlywayAutoConfiguration.class,
            HibernateJpaAutoConfiguration.class, KafkaAutoConfiguration.class})
    @EnableConfigurationProperties(ApiAuthProperties.class)
    @Import({MetaController.class, AuthController.class, MetaWebConfig.class, SecurityConfig.class})
    static class Web {}

    @LocalServerPort int port;
    @MockitoBean MetaService meta;

    @BeforeEach
    void answer() {
        when(meta.formats()).thenReturn(new Formats(Instant.parse("2026-10-06T12:00:00Z"), List.of()));
    }

    /** The whole response to `method path`, sent exactly as written. */
    private String send(String method, String path, String authorization) throws Exception {
        try (Socket socket = new Socket("127.0.0.1", port)) {
            String request = method + " " + path + " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"
                    + "Content-Length: 0\r\n"
                    + (authorization == null ? "" : "Authorization: " + authorization + "\r\n") + "\r\n";
            OutputStream out = socket.getOutputStream();
            out.write(request.getBytes(StandardCharsets.US_ASCII));
            out.flush();
            return new String(socket.getInputStream().readAllBytes(), StandardCharsets.US_ASCII);
        }
    }

    private String status(String method, String path, String authorization) throws Exception {
        return send(method, path, authorization).lines().findFirst().orElse("");
    }

    private String token() throws Exception {
        String response = send("POST", ApiAuthFilter.TOKEN_PATH, "Bearer " + ApiAuthFilterTest.KEY);
        Matcher matcher = Pattern.compile("\"token\":\"([^\"]+)\"").matcher(response);
        assertThat(matcher.find()).as(response).isTrue();
        return matcher.group(1);
    }

    @Test
    void aKeyGetsATokenAndTheTokenOpensV1() throws Exception {
        assertThat(status("GET", "/v1/formats", null)).contains(" 401");
        assertThat(status("GET", "/v1/formats", "Bearer " + ApiAuthFilterTest.KEY)).as("the key itself").contains(" 401");
        assertThat(status("POST", ApiAuthFilter.TOKEN_PATH, "Bearer pkr_wrong")).contains(" 401");
        assertThat(status("GET", "/v1/formats", "Bearer " + token())).contains(" 200");
    }

    @Test
    void rewrittenPathsDontSlipPast() throws Exception {
        for (String path : List.of("/swagger-ui/../v1/formats", "/swagger-ui/%2e%2e/v1/formats",
                "/swagger-ui/.%2e/v1/formats", "/v3/api-docs/../../v1/formats", "/swagger-ui/;x=1/../v1/formats",
                "/swagger-ui.html/../v1/formats", "/swagger-ui//../v1/formats")) {
            assertThat(status("GET", path, null)).as(path).doesNotContain(" 200");
        }
    }

    /** No spelling of the token request gets a token without the key: not none, and not a token. */
    @Test
    void onlyTheKeyGetsAToken() throws Exception {
        String token = token();
        for (String path : List.of(ApiAuthFilter.TOKEN_PATH, ApiAuthFilter.TOKEN_PATH + "/", "/v1/auth/../auth/token",
                "/v1/auth/token;x=1", "/v1/auth/%74oken", "/v1//auth/token", "/swagger-ui/../v1/auth/token")) {
            assertThat(status("POST", path, null)).as(path).doesNotContain(" 200");
            assertThat(status("POST", path, "Bearer " + token)).as(path + " with a token").doesNotContain(" 200");
        }
    }
}
