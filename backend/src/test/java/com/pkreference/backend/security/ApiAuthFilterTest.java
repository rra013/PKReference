package com.pkreference.backend.security;

import com.jayway.jsonpath.JsonPath;
import com.pkreference.backend.insight.MetaController;
import com.pkreference.backend.insight.MetaResponses.Formats;
import com.pkreference.backend.insight.MetaService;
import com.pkreference.backend.insight.MetaWebConfig;
import com.pkreference.backend.ladder.LadderController;
import com.pkreference.backend.ladder.LadderResponses;
import com.pkreference.backend.ladder.LadderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Clock;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.hamcrest.Matchers.startsWith;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Signing in, through the web layer: a key is traded for a token, the token opens the API until it
 * runs out, and nothing else does. Off with no keys configured.
 */
class ApiAuthFilterTest {
    static final String KEY = "pkr_test-key-only-for-tests";
    /** SHA-256 of KEY. */
    static final String HASH = "8ae51c9be26d1d687654c9b0df641b4f0b3d9dac9fae23c46e773ed7b764e36e";

    private static ApiAuthFilter filter(List<String> hashes) {
        var properties = ApiAuthProperties.ofKeys(hashes);
        return new ApiAuthFilter(properties, new TokenService(properties, Clock.systemUTC()));
    }

    @Test
    void hashes() {
        assertThat(HexFormat.of().formatHex(ApiAuthFilter.sha256(KEY))).isEqualTo(HASH);
        var filter = filter(List.of("0".repeat(64), HASH.toUpperCase()));
        assertThat(filter.keyId(KEY)).isEqualTo("8ae51c9b");
        assertThat(filter.keyId(KEY + "x")).isNull();
        assertThat(filter.keyId("")).isNull();
        assertThat(filter.keyId(HASH)).as("the hash isn't a key").isNull();
    }

    @Test
    void onlyHashesAreConfigured() {
        assertThatThrownBy(() -> ApiAuthProperties.ofKeys(List.of(KEY))).isInstanceOf(IllegalArgumentException.class);
        assertThat(ApiAuthProperties.ofKeys(List.of(" ", "")).required()).isFalse();
        assertThat(ApiAuthProperties.ofKeys(null).required()).isFalse();
    }

    /** Swagger UI's page, assets and document hold no data, and a browser can't send a credential. */
    @Test
    void documentationIsOpen() {
        for (String path : List.of("/swagger-ui.html", "/swagger-ui/index.html", "/v3/api-docs", "/v3/api-docs/swagger-config")) {
            assertThat(ApiAuthFilter.isDocumentation(new MockHttpServletRequest("GET", path))).as(path).isTrue();
        }
        for (String path : List.of("/v1/formats", "/api/usage", "/swagger-uix", "/v3", ApiAuthFilter.TOKEN_PATH,
                "/swagger-ui/../v1/formats", "/swagger-ui/%2e%2e/v1/formats", "/v3/api-docs/..%2fv1/formats",
                "/swagger-ui/;/../v1/formats", "/swagger-ui//../v1/formats")) {
            assertThat(ApiAuthFilter.isDocumentation(new MockHttpServletRequest("GET", path))).as(path).isFalse();
        }
    }

    /** A request the filter didn't match a key for gets no token, however it reached the controller. */
    @Test
    void noTokenWithoutAKey() {
        var properties = ApiAuthProperties.ofKeys(List.of(HASH));
        var controller = new AuthController(new TokenService(properties, Clock.systemUTC()), properties);
        assertThat(controller.token(new MockHttpServletRequest("POST", ApiAuthFilter.TOKEN_PATH)).getStatusCode().value())
                .isEqualTo(401);
    }

    @TestConfiguration
    static class Clocks {
        static final TokenServiceTest.TestClock CLOCK = new TokenServiceTest.TestClock();

        /** In place of the application's clock, so a test can let a token run out. */
        @Bean
        @Primary
        Clock testClock() {
            return CLOCK;
        }
    }

    abstract static class WebLayer {
        @Autowired MockMvc mvc;
        @MockitoBean MetaService meta;
        @MockitoBean LadderService ladder;

        @BeforeEach
        void answer() {
            Clocks.CLOCK.now = TokenServiceTest.NOW;
            when(meta.formats()).thenReturn(new Formats(Instant.parse("2026-10-06T12:00:00Z"), List.of()));
            when(ladder.index()).thenReturn(new LadderResponses.Index(List.of()));
        }

        /** Trades `key` for a token. */
        String token(String key) throws Exception {
            String body = mvc.perform(post(ApiAuthFilter.TOKEN_PATH).header("Authorization", "Bearer " + key))
                    .andExpect(status().isOk())
                    .andReturn().getResponse().getContentAsString();
            return JsonPath.read(body, "$.token");
        }
    }

    // This package's tests start from ApiAuthTomcatTest.Web, which imports its controllers by name,
    // so the ladder's is imported here.
    @Nested
    @WebMvcTest({MetaController.class, AuthController.class})
    @Import({MetaWebConfig.class, SecurityConfig.class, Clocks.class, LadderController.class})
    @EnableConfigurationProperties(ApiAuthProperties.class)
    @TestPropertySource(properties = "pkref.api.key-hashes=" + HASH)
    class WithKeys extends WebLayer {
        @Test
        void aKeyIsTradedForAToken() throws Exception {
            mvc.perform(post(ApiAuthFilter.TOKEN_PATH).header("Authorization", "Bearer " + KEY))
                    .andExpect(status().isOk())
                    .andExpect(header().string("Cache-Control", "no-store"))
                    .andExpect(jsonPath("$.tokenType").value("Bearer"))
                    .andExpect(jsonPath("$.expiresIn").value(900))
                    .andExpect(jsonPath("$.expiresAt").value("2026-10-11T12:15:00Z"))
                    .andExpect(jsonPath("$.token").isString());
            mvc.perform(post(ApiAuthFilter.TOKEN_PATH).header("Authorization", "bearer  " + KEY)).andExpect(status().isOk());
        }

        @Test
        void aWrongKeyGetsNoToken() throws Exception {
            mvc.perform(post(ApiAuthFilter.TOKEN_PATH).header("Authorization", "Bearer pkr_wrong"))
                    .andExpect(status().isUnauthorized())
                    .andExpect(header().string("Cache-Control", "no-store"))
                    .andExpect(jsonPath("$.code").value("invalid_key"));
            mvc.perform(post(ApiAuthFilter.TOKEN_PATH))
                    .andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("$.code").value("missing_credentials"));
            mvc.perform(post(ApiAuthFilter.TOKEN_PATH + "?key=" + KEY)).andExpect(status().isUnauthorized());
            mvc.perform(post(ApiAuthFilter.TOKEN_PATH).header("X-API-Key", KEY)).andExpect(status().isUnauthorized());
            // A token can't be traded for another: only the key can.
            mvc.perform(post(ApiAuthFilter.TOKEN_PATH).header("Authorization", "Bearer " + token(KEY)))
                    .andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("$.code").value("invalid_key"));
        }

        @Test
        void theTokenOpensTheApiWithPrivateCaching() throws Exception {
            mvc.perform(get("/v1/formats").header("Authorization", "Bearer " + token(KEY)))
                    .andExpect(status().isOk())
                    .andExpect(header().string("Cache-Control", "max-age=900, private"))
                    .andExpect(header().exists("ETag"));
            mvc.perform(get("/v1/ladder").header("Authorization", "Bearer " + token(KEY)))
                    .andExpect(status().isOk())
                    .andExpect(header().string("Cache-Control", "max-age=900, private"));
        }

        @Test
        void nothingElseOpensIt() throws Exception {
            mvc.perform(get("/v1/formats"))
                    .andExpect(status().isUnauthorized())
                    .andExpect(header().string("WWW-Authenticate", startsWith("Bearer ")))
                    .andExpect(jsonPath("$.code").value("missing_credentials"));
            // The key itself, which the data endpoints no longer take.
            mvc.perform(get("/v1/formats").header("Authorization", "Bearer " + KEY))
                    .andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("$.code").value("invalid_token"));
            String token = token(KEY);
            mvc.perform(get("/v1/formats").header("Authorization", token)).andExpect(status().isUnauthorized());
            mvc.perform(get("/v1/formats?token=" + token)).andExpect(status().isUnauthorized());
            mvc.perform(get("/v1/formats").header("Authorization", "Bearer " + token + "x"))
                    .andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("$.code").value("invalid_token"));
            mvc.perform(get("/api/usage?format=M-C")).andExpect(status().isUnauthorized());
            mvc.perform(get("/v1/ladder")).andExpect(status().isUnauthorized());
            mvc.perform(get("/v1/ladder/gen9championsvgc2026regmc").header("Authorization", "Bearer " + KEY))
                    .andExpect(status().isUnauthorized());
            mvc.perform(get("/v1/../swagger-ui.html/../v1/formats")).andExpect(status().isUnauthorized());
        }

        /** After its 15 minutes the token is refused, saying so, and the key gets a new one. */
        @Test
        void aTokenRunsOut() throws Exception {
            String token = token(KEY);
            Clocks.CLOCK.now = TokenServiceTest.NOW.plusSeconds(14 * 60);
            mvc.perform(get("/v1/formats").header("Authorization", "Bearer " + token)).andExpect(status().isOk());

            Clocks.CLOCK.now = TokenServiceTest.NOW.plusSeconds(15 * 60);
            mvc.perform(get("/v1/formats").header("Authorization", "Bearer " + token))
                    .andExpect(status().isUnauthorized())
                    .andExpect(header().string("WWW-Authenticate",
                            "Bearer error=\"invalid_token\", error_description=\"token_expired\""))
                    .andExpect(jsonPath("$.code").value("token_expired"));

            mvc.perform(get("/v1/formats").header("Authorization", "Bearer " + token(KEY))).andExpect(status().isOk());
        }
    }

    @Nested
    @WebMvcTest({MetaController.class, AuthController.class})
    @Import({MetaWebConfig.class, SecurityConfig.class, LadderController.class})
    @EnableConfigurationProperties(ApiAuthProperties.class)
    @TestPropertySource(properties = "pkref.api.key-hashes=")
    class WithoutKeys extends WebLayer {
        @Test
        void letsEverythingIn() throws Exception {
            mvc.perform(get("/v1/formats"))
                    .andExpect(status().isOk())
                    .andExpect(header().string("Cache-Control", "max-age=900, public"));
            // A client with a key saved can still ask for a token, and use it.
            mvc.perform(get("/v1/formats").header("Authorization", "Bearer " + token("pkr_anything")))
                    .andExpect(status().isOk());
        }
    }
}
