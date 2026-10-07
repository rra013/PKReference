package com.pkreference.backend.security;

import com.pkreference.backend.insight.MetaController;
import com.pkreference.backend.insight.MetaResponses.Formats;
import com.pkreference.backend.insight.MetaService;
import com.pkreference.backend.insight.MetaWebConfig;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** The API key check: off with no keys configured, and with them, nothing gets in without one. */
class ApiKeyFilterTest {
    static final String KEY = "pkr_test-key-only-for-tests";
    /** SHA-256 of KEY. */
    static final String HASH = "8ae51c9be26d1d687654c9b0df641b4f0b3d9dac9fae23c46e773ed7b764e36e";

    @Test
    void hashes() {
        assertThat(java.util.HexFormat.of().formatHex(ApiKeyFilter.sha256(KEY))).isEqualTo(HASH);
        var filter = new ApiKeyFilter(new ApiKeyProperties(List.of(HASH.toUpperCase())));
        assertThat(filter.accepted(KEY)).isTrue();
        assertThat(filter.accepted(KEY + "x")).isFalse();
        assertThat(filter.accepted("")).isFalse();
        assertThat(filter.accepted(HASH)).as("the hash isn't a key").isFalse();
    }

    @Test
    void onlyHashesAreConfigured() {
        assertThatThrownBy(() -> new ApiKeyProperties(List.of(KEY))).isInstanceOf(IllegalArgumentException.class);
        assertThat(new ApiKeyProperties(List.of(" ", "")).required()).isFalse();
        assertThat(new ApiKeyProperties(null).required()).isFalse();
    }

    abstract static class WebLayer {
        @Autowired MockMvc mvc;
        @MockitoBean MetaService meta;

        @BeforeEach
        void answer() {
            when(meta.formats()).thenReturn(new Formats(Instant.parse("2026-10-06T12:00:00Z"), List.of()));
        }
    }

    @Nested
    @WebMvcTest(MetaController.class)
    @Import({MetaWebConfig.class, SecurityConfig.class})
    @EnableConfigurationProperties(ApiKeyProperties.class)
    @TestPropertySource(properties = "pkref.api.key-hashes=" + HASH)
    class WithKeys extends WebLayer {
        @Test
        void needsTheKey() throws Exception {
            mvc.perform(get("/v1/formats"))
                    .andExpect(status().isUnauthorized())
                    .andExpect(header().string("WWW-Authenticate", "Bearer"))
                    .andExpect(jsonPath("$.error").exists());
            mvc.perform(get("/v1/formats").header("Authorization", "Bearer wrong")).andExpect(status().isUnauthorized());
            mvc.perform(get("/v1/formats").header("Authorization", KEY)).andExpect(status().isUnauthorized());
            mvc.perform(get("/v1/formats?key=" + KEY)).andExpect(status().isUnauthorized());
            mvc.perform(get("/v1/formats").header("X-API-Key", KEY)).andExpect(status().isUnauthorized());
            mvc.perform(get("/api/usage?format=M-C")).andExpect(status().isUnauthorized());
            mvc.perform(get("/v1/../swagger-ui.html/../v1/formats")).andExpect(status().isUnauthorized());
        }

        /** Swagger UI's page, assets and document hold no data, and a browser can't send the key. */
        @Test
        void documentationIsOpen() {
            for (String path : List.of("/swagger-ui.html", "/swagger-ui/index.html", "/v3/api-docs", "/v3/api-docs/swagger-config")) {
                var request = new org.springframework.mock.web.MockHttpServletRequest("GET", path);
                assertThat(ApiKeyFilter.isDocumentation(request)).as(path).isTrue();
            }
            for (String path : List.of("/v1/formats", "/api/usage", "/swagger-uix", "/v3",
                    "/swagger-ui/../v1/formats", "/swagger-ui/%2e%2e/v1/formats", "/v3/api-docs/..%2fv1/formats",
                    "/swagger-ui/;/../v1/formats", "/swagger-ui//../v1/formats")) {
                var request = new org.springframework.mock.web.MockHttpServletRequest("GET", path);
                assertThat(ApiKeyFilter.isDocumentation(request)).as(path).isFalse();
            }
        }

        @Test
        void letsTheKeyInWithPrivateCaching() throws Exception {
            mvc.perform(get("/v1/formats").header("Authorization", "Bearer " + KEY))
                    .andExpect(status().isOk())
                    .andExpect(header().string("Cache-Control", "max-age=900, private"))
                    .andExpect(header().exists("ETag"));
            mvc.perform(get("/v1/formats").header("Authorization", "bearer  " + KEY)).andExpect(status().isOk());
        }
    }

    @Nested
    @WebMvcTest(MetaController.class)
    @Import({MetaWebConfig.class, SecurityConfig.class})
    @EnableConfigurationProperties(ApiKeyProperties.class)
    @TestPropertySource(properties = "pkref.api.key-hashes=")
    class WithoutKeys extends WebLayer {
        @Test
        void letsEverythingIn() throws Exception {
            mvc.perform(get("/v1/formats"))
                    .andExpect(status().isOk())
                    .andExpect(header().string("Cache-Control", "max-age=900, public"));
        }
    }
}
