package com.pkreference.backend.ladder;

import com.pkreference.backend.insight.MetaWebConfig;
import com.pkreference.backend.ladder.LadderResponses.Entry;
import com.pkreference.backend.ladder.LadderResponses.Index;
import com.pkreference.backend.ladder.LadderResponses.Pokemon;
import com.pkreference.backend.ladder.LadderResponses.RatingUsage;
import com.pkreference.backend.ladder.LadderResponses.Stats;
import com.pkreference.backend.model.Ladder.Share;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;
import java.util.List;
import java.util.NoSuchElementException;

import static org.hamcrest.Matchers.nullValue;
import static org.hamcrest.Matchers.startsWith;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** /v1/ladder's web layer: JSON shape, caching headers, ETags, parameters and errors. */
@WebMvcTest(LadderController.class)
@Import(MetaWebConfig.class)
class LadderControllerTest {
    private static final String FORMAT = "gen9championsvgc2026regmc";
    private static final Instant FETCHED = Instant.parse("2026-10-12T08:00:00Z");

    @Autowired MockMvc mvc;
    @MockitoBean LadderService ladder;

    private static Stats stats() {
        var salamence = new Pokemon("Salamence-Mega", "salamence", "Salamencite", 0.2806, 0.012,
                List.of(new RatingUsage(0, 0.21), new RatingUsage(1760, 0.2806)), 0.0479569,
                List.of(new Share("Aerilate", 1.0)), List.of(new Share("Salamencite", 1.0)),
                List.of(new Share("Hyper Voice", 0.91)), List.of(new Share("Timid", 0.6)),
                List.of(new Share("Timid:2/0/0/32/0/32", 0.31)), List.of(new Share("Incineroar", 0.4)));
        var unknown = new Pokemon("Newmon", null, null, 0.01, null, List.of(), null, List.of(), List.of(), List.of(),
                List.of(), List.of(), List.of());
        return new Stats(1, FORMAT, "M-C", "doubles", 1, "2026-09", 1760, 1_631_943, FETCHED, "2026-08",
                List.of(0, 1760), List.of(salamence, unknown));
    }

    @Test
    void theIndex() throws Exception {
        when(ladder.index()).thenReturn(new Index(List.of(
                new Entry(FORMAT, "M-C", "doubles", 1, "2026-09", 1760, 1_631_943, FETCHED))));
        mvc.perform(get("/v1/ladder"))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "max-age=900, public"))
                .andExpect(header().string("ETag", startsWith("W/")))
                .andExpect(jsonPath("$.stats[0].format").value(FORMAT))
                .andExpect(jsonPath("$.stats[0].regulation").value("M-C"))
                .andExpect(jsonPath("$.stats[0].mode").value("doubles"))
                .andExpect(jsonPath("$.stats[0].bestOf").value(1))
                .andExpect(jsonPath("$.stats[0].month").value("2026-09"))
                .andExpect(jsonPath("$.stats[0].rating").value(1760))
                .andExpect(jsonPath("$.stats[0].battles").value(1_631_943))
                .andExpect(jsonPath("$.stats[0].fetchedAt").value("2026-10-12T08:00:00Z"));
    }

    @Test
    void aMonthWithCachingAndAnEtag() throws Exception {
        when(ladder.stats(FORMAT, 1760, "2026-09")).thenReturn(stats());
        var first = mvc.perform(get("/v1/ladder/" + FORMAT + "?rating=1760&month=2026-09"))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "max-age=900, public"))
                .andExpect(header().string("ETag", startsWith("W/")))
                .andExpect(jsonPath("$.reduction").value(1))
                .andExpect(jsonPath("$.regulation").value("M-C"))
                .andExpect(jsonPath("$.battles").value(1_631_943))
                .andExpect(jsonPath("$.fetchedAt").value("2026-10-12T08:00:00Z"))
                .andExpect(jsonPath("$.previousMonth").value("2026-08"))
                .andExpect(jsonPath("$.ratings[1]").value(1760))
                .andExpect(jsonPath("$.pokemon[0].name").value("Salamence-Mega"))
                .andExpect(jsonPath("$.pokemon[0].key").value("salamence"))
                .andExpect(jsonPath("$.pokemon[0].megaStone").value("Salamencite"))
                .andExpect(jsonPath("$.pokemon[0].trend").value(0.012))
                .andExpect(jsonPath("$.pokemon[0].usageByRating[0].rating").value(0))
                .andExpect(jsonPath("$.pokemon[0].usageByRating[0].usage").value(0.21))
                .andExpect(jsonPath("$.pokemon[0].leadShare").value(0.0479569))
                .andExpect(jsonPath("$.pokemon[0].spreads[0].value").value("Timid:2/0/0/32/0/32"))
                .andExpect(jsonPath("$.pokemon[0].spreads[0].share").value(0.31))
                .andExpect(jsonPath("$.pokemon[1].key").value(nullValue()))
                .andExpect(jsonPath("$.pokemon[1].trend").value(nullValue()))
                .andReturn();
        String etag = first.getResponse().getHeader("ETag");
        // The answer doesn't say when it was made, so an unchanged month keeps its ETag.
        mvc.perform(get("/v1/ladder/" + FORMAT + "?rating=1760&month=2026-09").header("If-None-Match", etag))
                .andExpect(status().isNotModified());
    }

    @Test
    void theRatingAndMonthAreTheServicesToChoose() throws Exception {
        when(ladder.stats(eq(FORMAT), any(), any())).thenReturn(stats());
        mvc.perform(get("/v1/ladder/" + FORMAT)).andExpect(status().isOk());
        verify(ladder).stats(FORMAT, null, null);
        mvc.perform(get("/v1/ladder/" + FORMAT + "?rating=0")).andExpect(status().isOk());
        verify(ladder).stats(FORMAT, 0, null);
    }

    @Test
    void errors() throws Exception {
        when(ladder.stats(eq("gen9ou"), any(), any())).thenThrow(new NoSuchElementException("No ladder stats stored for gen9ou at 1760"));
        mvc.perform(get("/v1/ladder/gen9ou"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("No ladder stats stored for gen9ou at 1760"));
        for (String month : List.of("september", "2026-13", "2026-9", "2026-09-01", "")) {
            mvc.perform(get("/v1/ladder/" + FORMAT + "?month=" + month)).andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("month must be like 2026-09"));
        }
        mvc.perform(get("/v1/ladder/" + FORMAT + "?rating=high")).andExpect(status().isBadRequest());
    }
}
