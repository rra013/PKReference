package com.pkreference.backend.insight;

import com.pkreference.backend.insight.MetaResponses.PokemonList;
import com.pkreference.backend.insight.MetaResponses.PokemonUsage;
import com.pkreference.backend.insight.MetaResponses.Sample;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;
import java.util.List;
import java.util.NoSuchElementException;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** The /v1 web layer: JSON shape, caching headers, ETags, and errors. */
@WebMvcTest(MetaController.class)
@Import(MetaWebConfig.class)
class MetaControllerTest {
    @Autowired MockMvc mvc;
    @MockitoBean MetaService meta;

    private static final Instant NOW = Instant.parse("2026-10-06T12:00:00Z");

    @Test
    void listsWithCachingAndAnEtag() throws Exception {
        when(meta.pokemon(eq("M-C"), eq(MetaWindow.DAYS_14))).thenReturn(new PokemonList("M-C", "14d",
                NOW.minusSeconds(14 * 86400), NOW, NOW, new Sample(1, 83, 16),
                List.of(new PokemonUsage("rillaboom", 44, 0.5301, 9, 0.5625, null,
                        new MetaResponses.WinRecord(46, 51, 0, 97, 0.4742, 0.3777, 0.5727)))));

        var first = mvc.perform(get("/v1/formats/M-C/pokemon?window=14d"))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "max-age=900, public"))
                .andExpect(header().string("ETag", org.hamcrest.Matchers.startsWith("W/")))
                .andExpect(jsonPath("$.sample.teams").value(83))
                .andExpect(jsonPath("$.pokemon[0].key").value("rillaboom"))
                .andExpect(jsonPath("$.pokemon[0].topCutUsage").value(0.5625))
                .andExpect(jsonPath("$.pokemon[0].record.winRateLow").value(0.3777))
                .andReturn();
        String etag = first.getResponse().getHeader("ETag");

        mvc.perform(get("/v1/formats/M-C/pokemon?window=14d").header("If-None-Match", etag))
                .andExpect(status().isNotModified());
    }

    @Test
    void errors() throws Exception {
        mvc.perform(get("/v1/formats/M-C/pokemon?window=week"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("window must be 14d, 30d or regulation"));
        when(meta.pokemon(eq("M-C"), eq("pikachu"), any())).thenThrow(new NoSuchElementException("No team in the window has pikachu"));
        mvc.perform(get("/v1/formats/M-C/pokemon/pikachu"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("No team in the window has pikachu"));
    }
}
