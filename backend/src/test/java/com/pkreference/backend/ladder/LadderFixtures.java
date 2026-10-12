package com.pkreference.backend.ladder;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pkreference.backend.model.Ladder.Stats;
import com.pkreference.backend.standardize.NameStandardizer;
import com.pkreference.backend.standardize.SpeciesVocabularies;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.Set;

/**
 * Smogon's real 2026-09 stats for M-C doubles at 1760, saved once and cut down to 27 Pokémon, each
 * with its 25 biggest spreads and 30 biggest teammates; every count kept is as published. The
 * Pokémon are the most used, and ones whose names need care: Megas with and without a letter,
 * regional and other forms, "Mr. Rime", "Kommo-o", "Sirfetch'd", and Zoroark-Hisui, which the leads
 * file doesn't list. Tests never call Smogon.
 */
public final class LadderFixtures {
    private LadderFixtures() {}

    public static final String MONTH = "2026-09";
    public static final String FORMAT_ID = "gen9championsvgc2026regmc";
    public static final int RATING = 1760;
    public static final String FILE = FORMAT_ID + "-" + RATING + ".json";
    public static final LadderFormat FORMAT = LadderFormat.parse(FORMAT_ID, Set.of("m-c"));

    private static final String DIR = "/smogon/" + MONTH + "/";

    public static InputStream chaos() {
        return LadderFixtures.class.getResourceAsStream(DIR + "chaos/" + FILE);
    }

    public static String leads() {
        try (InputStream in = LadderFixtures.class.getResourceAsStream(DIR + "leads/" + FORMAT_ID + "-" + RATING + ".txt")) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public static LadderReducer reducer() {
        var mapper = new ObjectMapper();
        return new LadderReducer(mapper, new SpeciesVocabularies(), new NameStandardizer(mapper));
    }

    /** The fixture, reduced. */
    public static Stats stats() {
        try (InputStream in = chaos()) {
            return reducer().reduce(in, leads(), FORMAT, MONTH, RATING);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
