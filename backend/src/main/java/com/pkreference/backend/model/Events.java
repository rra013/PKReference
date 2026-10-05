package com.pkreference.backend.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.List;

/** Wire types. Mirrors PKReference/LimitlessAPI.swift; fields the API omits are nullable. */
public final class Events {
    private Events() {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Tournament(String id, String name, String game, String format, String date, int players) {}

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

    /** Topic tournaments.discovered, key = tournament id. */
    public record TournamentDiscovered(Tournament tournament) {}

    /** Topic standings.fetched, key = tournament id. */
    public record StandingsFetched(Tournament tournament, List<Standing> standings) {}

    /** Topic pokemon.usage, key = "format|species". */
    public record UsageUpdated(String format, String species, long teams, long totalTeams) {}
}
