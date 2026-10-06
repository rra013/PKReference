package com.pkreference.backend;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.pkreference.backend.model.Events.Pairing;
import com.pkreference.backend.model.Events.Standing;
import com.pkreference.backend.model.Events.Tournament;
import com.pkreference.backend.model.Events.TournamentDetails;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.util.List;

/**
 * One real Limitless event (M-C, 83 players, 2026-10-05), as its API answered, with the players'
 * names and usernames replaced (player-01 is first place) and the organizer renamed.
 */
public final class LimitlessFixtures {
    private static final ObjectMapper JSON = new ObjectMapper();

    private LimitlessFixtures() {}

    public static Tournament tournament(String date) {
        return new Tournament("event-83", "Test Event (M-C, 83 players)", "VGC", "M-C", date, 83);
    }

    public static TournamentDetails details() {
        return read("details.json", new TypeReference<>() {});
    }

    public static List<Standing> standings() {
        return read("standings.json", new TypeReference<>() {});
    }

    public static List<Pairing> pairings() {
        return read("pairings.json", new TypeReference<>() {});
    }

    private static <T> T read(String file, TypeReference<T> type) {
        try (InputStream in = LimitlessFixtures.class.getResourceAsStream("/limitless/event-83/" + file)) {
            return JSON.readValue(in, type);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
