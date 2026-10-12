package com.pkreference.backend.ladder;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.pkreference.backend.model.Ladder.Pokemon;
import com.pkreference.backend.model.Ladder.Stats;
import com.pkreference.backend.model.Ladder.StatsFetched;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;

import java.time.Instant;
import java.util.List;

/** What the store's tests need that a @JdbcTest doesn't bring, and records to store. */
@TestConfiguration
public class LadderTestConfig {
    public static final Instant FETCHED = Instant.parse("2026-10-12T08:00:00Z");

    @Bean
    ObjectMapper objectMapper() {
        return new ObjectMapper().registerModule(new JavaTimeModule());
    }

    /** The fixture's record as another format, month or rating's, with every usage scaled. */
    public static StatsFetched fetched(String format, String month, int rating, double scale, Instant at) {
        Stats s = LadderFixtures.stats();
        List<Pokemon> pokemon = s.pokemon().stream().map(p -> new Pokemon(p.name(), p.key(), p.megaStone(),
                p.usage() * scale, p.leadShare(), p.abilities(), p.items(), p.moves(), p.natures(), p.spreads(),
                p.teammates())).toList();
        var format1 = LadderFormat.parse(format, List.of("m-b", "m-c"));
        return new StatsFetched(new Stats(s.reduction(), format, format1.regulation(), format1.mode(), format1.bestOf(),
                month, rating, s.battles(), pokemon), at);
    }

    public static StatsFetched fetched(String month, int rating, double scale) {
        return fetched(LadderFixtures.FORMAT_ID, month, rating, scale, FETCHED);
    }
}
