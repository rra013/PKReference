package com.pkreference.backend.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Instant;
import java.util.List;

/**
 * Wire types: the shapes of the JSON that travels between Limitless, the Kafka topics and the app.
 * Mirrors PKReference/LimitlessAPI.swift; fields the API omits are nullable.
 *
 * <p>Each is a Java {@code record}: an immutable class whose constructor, accessors
 * ({@code tournament.id()}), {@code equals} and {@code toString} the compiler writes from the one
 * line of fields. Jackson, the JSON library Spring uses, reads and writes records by their field
 * names, so these one-liners are the whole definition of the JSON.
 *
 * <p>They're used three ways: to read Limitless's answers (LimitlessClient), as the values of the
 * Kafka records (the last four records below, serialized to JSON by the producer and back by each
 * listener), and to answer the app in Limitless's own shapes (CorpusController).
 *
 * <p>{@code @JsonIgnoreProperties(ignoreUnknown = true)}, on the records read from outside: a field in
 * the JSON that the record doesn't have is skipped instead of failing the read, so Limitless adding
 * a field, or a newer server having written a record with one, doesn't break this one.
 *
 * <p>The class itself is only a namespace: {@code final} with a private constructor, never created.
 */
public final class Events {
    private Events() {}

    /**
     * One event as Limitless lists it (GET /tournaments). {@code date} is an ISO-8601 instant kept
     * as the text Limitless sent ("2026-10-05T18:00:00.000Z"); FetchPolicy.startOf parses it.
     */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Tournament(String id, String name, String game, String format, String date, int players) {}

    /** GET /tournaments/{id}/details. */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record TournamentDetails(Organizer organizer, String platform, Boolean decklists, Boolean isOnline,
                                    List<Phase> phases) {
        /** Who ran the event. */
        @JsonIgnoreProperties(ignoreUnknown = true)
        public record Organizer(Integer id, String name) {}

        /** type is SWISS, SINGLE_BRACKET and so on; mode is BO1, BO3 or BO5. */
        @JsonIgnoreProperties(ignoreUnknown = true)
        public record Phase(int phase, String type, Integer rounds, String mode) {}
    }

    /**
     * GET /tournaments/{id}/standings: one player's entry. {@code player} is the username, unique
     * in an event; {@code decklist} is the team, null when the event didn't publish teams;
     * {@code drop} is the round the player dropped in, null when they didn't.
     */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Standing(String player, String name, String country, Integer placing,
                           Record record, Deck deck, List<TeamMember> decklist, Integer drop) {
        /** A player's wins, losses and ties. */
        @JsonIgnoreProperties(ignoreUnknown = true)
        public record Record(int wins, int losses, int ties) {}

        /** Limitless's label for a team; read, but not kept. */
        @JsonIgnoreProperties(ignoreUnknown = true)
        public record Deck(String id, String name, List<String> icons) {}
    }

    /**
     * One Pokémon on a team, as the player typed it: names here are free text, which is why
     * NameStandardizer and SpeciesVocabularies exist. {@code @JsonProperty("id")} maps Limitless's
     * JSON field "id" (its slug for the species, "arcanine-hisui") to a field with a clearer name.
     */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record TeamMember(String name, @JsonProperty("id") String limitlessId, String item,
                             String ability, List<String> attacks, String nature, String tera) {}

    /**
     * GET /tournaments/{id}/pairings: one match. winner is the winner's username, "0" for a tie or
     * "-1" for a double loss (Limitless sends the numbers as numbers). With no player2 it's a bye
     * (winner is player1) or a loss for not showing up (winner is -1). table is null in live
     * brackets, which label their matches instead ("T16-8").
     */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Pairing(int round, int phase, Integer table, String match, String player1, String player2,
                          String winner) {}

    /** Topic tournaments.discovered, key = tournament id: fetch this event. */
    public record TournamentDiscovered(Tournament tournament) {}

    /**
     * Topic standings.fetched, key = tournament id. details, fetchedAt and standingsFinal are
     * null in records from before they were added; those count as final.
     */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record StandingsFetched(Tournament tournament, List<Standing> standings, TournamentDetails details,
                                   Instant fetchedAt, Boolean standingsFinal) {
        /**
         * A second constructor, for tests and old callers: standings alone, with nothing known
         * about the details, the time or whether they're final.
         */
        public StandingsFetched(Tournament tournament, List<Standing> standings) {
            this(tournament, standings, null, null, null);
        }

        /** Whether these standings won't change: fetched long enough after the event started. */
        @JsonIgnore
        public boolean isFinal() {
            return standingsFinal == null || standingsFinal;
        }
    }

    /** Topic pairings.fetched, key = tournament id. */
    public record PairingsFetched(Tournament tournament, List<Pairing> pairings, Instant fetchedAt) {}

    /** Topic pokemon.usage, key = "format|species". */
    public record UsageUpdated(String format, String species, long teams, long totalTeams) {}
}
