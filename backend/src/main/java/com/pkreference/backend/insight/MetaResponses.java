package com.pkreference.backend.insight;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

/**
 * The /v1 responses. Shares are 0 to 1, as the app's are. Every response says what it's from:
 * the window it covers, when it was worked out, and how many events and teams.
 */
public final class MetaResponses {
    private MetaResponses() {}

    /** How much the numbers rest on. topCutTeams: teams that played in a top cut, at events that had one. */
    public record Sample(int events, int teams, int topCutTeams) {}

    public record Format(String format, int events, int teams, Instant firstEvent, Instant lastEvent,
                         Instant lastFetched) {}

    public record Formats(Instant generatedAt, List<Format> formats) {}

    /**
     * One Pokémon's usage. topCutUsage: its share of top-cut teams, null when the window has no top
     * cut. trend: its usage over the last 14 days less the 14 before, null when either has fewer
     * than 50 teams.
     */
    public record PokemonUsage(String key, int teams, double usage, int topCutTeams, Double topCutUsage,
                               Double trend) {}

    public record PokemonList(String format, String window, Instant from, Instant to, Instant generatedAt,
                              Sample sample, List<PokemonUsage> pokemon) {}

    /** A value and how many of the Pokémon's members ran it. */
    public record Share(String value, int count, double share) {}

    /** A whole set, counted as one: item, ability, nature and its four moves. */
    public record PokemonSet(String item, String ability, String nature, List<String> moves, int count,
                             double share) {}

    /** Usage in one week (Monday to Sunday, UTC) of the window. */
    public record WeekUsage(LocalDate week, int teams, int withPokemon, double usage) {}

    public record PokemonDetail(String format, String key, String window, Instant from, Instant to,
                                Instant generatedAt, Sample sample, PokemonUsage usage, List<Share> items,
                                List<Share> abilities, List<Share> natures, List<Share> moves,
                                List<Share> megaStones, List<Share> teammates, List<PokemonSet> sets,
                                List<WeekUsage> weekly) {}
}
