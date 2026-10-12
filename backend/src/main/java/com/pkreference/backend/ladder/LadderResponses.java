package com.pkreference.backend.ladder;

import com.pkreference.backend.model.Ladder.Share;
import io.swagger.v3.oas.annotations.media.Schema;

import java.time.Instant;
import java.util.List;

/** The /v1/ladder responses. Shares are 0 to 1. */
public final class LadderResponses {
    private LadderResponses() {}

    @Schema(description = "One stored month of a format at a rating.")
    public record Entry(
            @Schema(description = "Smogon's format id.", example = "gen9championsvgc2026regmc") String format,
            @Schema(description = "The regulation, as Limitless names it.", example = "M-C") String regulation,
            @Schema(description = "doubles or singles.") String mode,
            @Schema(description = "1 or 3.") int bestOf,
            @Schema(example = "2026-09") String month,
            @Schema(description = "Smogon's rating cutoff: 0 is every player.") int rating,
            long battles,
            Instant fetchedAt) {}

    public record Index(@Schema(description = "By format, then newest month first, then rating.") List<Entry> stats) {}

    /** One Pokémon's usage at one rating cutoff. */
    public record RatingUsage(int rating, double usage) {}

    @Schema(description = "One Pokémon's month, as Ladder.Pokemon has it, with what the other stored files add.")
    public record Pokemon(
            @Schema(description = "Smogon's name, unique in the record. A Pokémon holding its Mega Stone is its own entry.",
                    example = "Salamence-Mega") String name,
            @Schema(description = "The app's species key; null when the regulation's data doesn't know the Pokémon.",
                    example = "salamence") String key,
            @Schema(description = "The Mega Stone, when the entry is a Mega; otherwise null.", example = "Salamencite")
            String megaStone,
            @Schema(description = "Share of teams with it on the team of six, weighted for the rating.") double usage,
            @Schema(description = "Usage less the month before's, same format and rating; null when that month isn't stored.")
            Double trend,
            @Schema(description = "Its usage at each stored rating of the month it's listed at.")
            List<RatingUsage> usageByRating,
            @Schema(description = "Its share of all leads; null when Smogon's leads file doesn't list it.")
            Double leadShare,
            List<Share> abilities,
            List<Share> items,
            @Schema(description = "Shares add to 4: each team has four moves.") List<Share> moves,
            @Schema(description = "The spreads' shares added up by nature.") List<Share> natures,
            @Schema(description = "Nature, then stat points for HP/Atk/Def/SpA/SpD/Spe.") List<Share> spreads,
            @Schema(description = "Other entries of the record, by their names.") List<Share> teammates) {}

    /**
     * GET /v1/ladder/{format}: a stored record's fields, when it was fetched, and what the other
     * stored files add.
     */
    public record Stats(
            @Schema(description = "The version of the rule that reduced Smogon's file.") int reduction,
            String format, String regulation, String mode, int bestOf, String month, int rating, long battles,
            @Schema(description = "When the server fetched Smogon's file.") Instant fetchedAt,
            @Schema(description = "The month trends are measured from; null when it isn't stored.", example = "2026-08")
            String previousMonth,
            @Schema(description = "The ratings stored for the month.") List<Integer> ratings,
            @Schema(description = "Most used first.") List<Pokemon> pokemon) {}
}
