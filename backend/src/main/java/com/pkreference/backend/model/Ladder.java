package com.pkreference.backend.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import io.swagger.v3.oas.annotations.media.Schema;

import java.time.Instant;
import java.util.List;

/**
 * Ladder stats, reduced from one of Smogon's monthly files to what the app shows
 * (BackendIntegration-PHASE5.md §3). The app's SmogonLadder.reduce makes the same record from the
 * same files; golden/ladder-fixture.json keeps the two equal.
 *
 * <p>As Events' records are, these are wire types: {@code Stats} is both the value of a
 * {@code ladder.stats} Kafka record (inside {@code StatsFetched}) and what ladder_stats stores as
 * JSON text. The {@code @Schema} annotations change nothing at run time: springdoc reads them to
 * describe each field in Swagger UI.
 */
public final class Ladder {
    private Ladder() {}

    @Schema(description = "A value, and the share of the Pokémon's teams with it, 0 to 1.")
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Share(String value, double share) {}

    /**
     * One Pokémon's month. {@code Double leadShare} is the boxed type because it can be absent
     * (null); {@code double usage} can't.
     */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Pokemon(
            @Schema(description = "Smogon's name, unique in the record. A Pokémon holding its Mega Stone is its own entry.",
                    example = "Salamence-Mega") String name,
            @Schema(description = "The app's species key; null when the regulation's data doesn't know the Pokémon.",
                    example = "salamence") String key,
            @Schema(description = "The Mega Stone, when the entry is a Mega; otherwise null.", example = "Salamencite")
            String megaStone,
            @Schema(description = "Share of teams with it on the team of six, weighted for the rating.") double usage,
            @Schema(description = "Its share of all leads; null when Smogon's leads file doesn't list it.")
            Double leadShare,
            List<Share> abilities,
            List<Share> items,
            @Schema(description = "Shares add to 4: each team has four moves.") List<Share> moves,
            @Schema(description = "The spreads' shares added up by nature.") List<Share> natures,
            @Schema(description = "Nature, then stat points for HP/Atk/Def/SpA/SpD/Spe.",
                    example = "[{\"value\": \"Adamant:2/32/0/0/0/32\", \"share\": 0.29624}]") List<Share> spreads,
            @Schema(description = "Other entries of the record, by their names.") List<Share> teammates) {}

    /** One of Smogon's files, reduced: a format's month at one rating. */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Stats(
            @Schema(description = "The version of the rule that reduced Smogon's file.") int reduction,
            @Schema(description = "Smogon's format id.", example = "gen9championsvgc2026regmc") String format,
            @Schema(description = "The regulation, as Limitless names it.", example = "M-C") String regulation,
            @Schema(description = "doubles or singles.") String mode,
            @Schema(description = "1 or 3.") int bestOf,
            @Schema(example = "2026-09") String month,
            @Schema(description = "Smogon's rating cutoff: 0 (every player), 1500, 1630 or 1760.") int rating,
            long battles,
            @Schema(description = "Most used first.") List<Pokemon> pokemon) {}

    /** Topic ladder.stats, key = "format|month|rating". */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record StatsFetched(Stats stats, Instant fetchedAt) {
        /**
         * The Kafka record's key: one key per file, so the compacted topic keeps the newest record
         * of each.
         */
        public String key() {
            return key(stats.format(), stats.month(), stats.rating());
        }

        /** "format|month|rating". */
        public static String key(String format, String month, int rating) {
            return format + "|" + month + "|" + rating;
        }
    }
}
