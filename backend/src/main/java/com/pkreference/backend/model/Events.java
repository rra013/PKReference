package com.pkreference.backend.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Instant;
import java.util.List;

/** Wire types. Mirrors PKReference/LimitlessAPI.swift; fields the API omits are nullable. */
public final class Events {
    private Events() {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Tournament(String id, String name, String game, String format, String date, int players) {}

    /** GET /tournaments/{id}/details. */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record TournamentDetails(Organizer organizer, String platform, Boolean decklists, Boolean isOnline,
                                    List<Phase> phases) {
        @JsonIgnoreProperties(ignoreUnknown = true)
        public record Organizer(Integer id, String name) {}

        /** type is SWISS, SINGLE_BRACKET and so on; mode is BO1, BO3 or BO5. */
        @JsonIgnoreProperties(ignoreUnknown = true)
        public record Phase(int phase, String type, Integer rounds, String mode) {}
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Standing(String player, String name, String country, Integer placing,
                           Record record, Deck deck, List<TeamMember> decklist, Integer drop) {
        @JsonIgnoreProperties(ignoreUnknown = true)
        public record Record(int wins, int losses, int ties) {}

        @JsonIgnoreProperties(ignoreUnknown = true)
        public record Deck(String id, String name, List<String> icons) {}
    }

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
