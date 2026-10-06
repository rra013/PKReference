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
        mvc.perform(get("/v1/formats/M-C/events?limit=0")).andExpect(status().isBadRequest());
        mvc.perform(get("/v1/formats/M-C/events?limit=51")).andExpect(status().isBadRequest());
    }

    @Test
    void eventsAndAnArchetype() throws Exception {
        when(meta.events("M-C", 10)).thenReturn(new MetaResponses.Events("M-C", NOW, List.of(
                new MetaResponses.EventSummary("e1", "Test Event", NOW, 83, true, 16,
                        new MetaResponses.EventWinner("Player 01", 8, 2, 0, List.of("grimmsnarl"))))));
        mvc.perform(get("/v1/formats/M-C/events"))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "max-age=900, public"))
                .andExpect(jsonPath("$.events[0].topCutPlayers").value(16))
                .andExpect(jsonPath("$.events[0].winner.team[0]").value("grimmsnarl"));

        // The id's + and : come through the path as they are.
        when(meta.archetype(eq("M-C"), eq("arcanine:hisui+gholdengo+raichu+staraptor"), eq(MetaWindow.DAYS_30)))
                .thenThrow(new NoSuchElementException("No archetype arcanine:hisui+gholdengo+raichu+staraptor in the window"));
        mvc.perform(get("/v1/formats/M-C/archetypes/arcanine:hisui+gholdengo+raichu+staraptor"))
                .andExpect(status().isNotFound());
    }
}
