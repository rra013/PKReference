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

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

/**
 * The key check in a real Tomcat, with raw requests: paths Tomcat rewrites before routing them (dot
 * segments, encoded characters, ";" parameters) must not reach /v1 without the key by starting like
 * Swagger UI's. Only the web layer runs: no Kafka or database.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        classes = ApiKeyTomcatTest.Web.class,
        properties = "pkref.api.key-hashes=" + ApiKeyFilterTest.HASH)
class ApiKeyTomcatTest {
    @SpringBootConfiguration
    @EnableAutoConfiguration(exclude = {DataSourceAutoConfiguration.class, FlywayAutoConfiguration.class,
            HibernateJpaAutoConfiguration.class, KafkaAutoConfiguration.class})
    @EnableConfigurationProperties(ApiKeyProperties.class)
    @Import({MetaController.class, MetaWebConfig.class, SecurityConfig.class})
    static class Web {}

    @LocalServerPort int port;
    @MockitoBean MetaService meta;

    @BeforeEach
    void answer() {
        when(meta.formats()).thenReturn(new Formats(Instant.parse("2026-10-06T12:00:00Z"), List.of()));
    }

    /** The status line of a GET for `path`, sent exactly as written. */
    private String status(String path, String authorization) throws Exception {
        try (Socket socket = new Socket("127.0.0.1", port)) {
            String request = "GET " + path + " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"
                    + (authorization == null ? "" : "Authorization: " + authorization + "\r\n") + "\r\n";
            OutputStream out = socket.getOutputStream();
            out.write(request.getBytes(StandardCharsets.US_ASCII));
            out.flush();
            return new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.US_ASCII))
                    .readLine();
        }
    }

    @Test
    void theKeyGuardsV1() throws Exception {
        assertThat(status("/v1/formats", null)).contains(" 401");
        assertThat(status("/v1/formats", "Bearer " + ApiKeyFilterTest.KEY)).contains(" 200");
    }

    @Test
    void rewrittenPathsDontSlipPast() throws Exception {
        for (String path : List.of("/swagger-ui/../v1/formats", "/swagger-ui/%2e%2e/v1/formats",
                "/swagger-ui/.%2e/v1/formats", "/v3/api-docs/../../v1/formats", "/swagger-ui/;x=1/../v1/formats",
                "/swagger-ui.html/../v1/formats", "/swagger-ui//../v1/formats")) {
            assertThat(status(path, null)).as(path).doesNotContain(" 200");
        }
    }
}
