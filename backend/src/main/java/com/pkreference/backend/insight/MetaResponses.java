package com.pkreference.backend.insight;

import io.swagger.v3.oas.annotations.media.Schema;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

/**
 * The /v1 responses. Shares are 0 to 1, as the app's are. Every response says what it's from:
 * the window it covers, when it was worked out, and how many events and teams.
 */
public final class MetaResponses {
    private MetaResponses() {}

    @Schema(description = "What the numbers rest on.")
    public record Sample(
            @Schema(description = "Events in the window.") int events,
            @Schema(description = "Teams with a published team list.") int teams,
            @Schema(description = "Of those, teams that played in a top cut (a bracket phase).") int topCutTeams) {}

    public record Format(
            @Schema(description = "Limitless format id.", example = "M-C") String format,
            int events, int teams, Instant firstEvent, Instant lastEvent,
            @Schema(description = "When the newest data was fetched.") Instant lastFetched) {}

    public record Formats(Instant generatedAt, List<Format> formats) {}

    @Schema(description = """
            Match results for teams with it, from Limitless's pairings. Mirror matches (both teams have \
            it) don't count; a tie counts as half a win, and a double loss as a loss. winRate and its 95% \
            range (Wilson) are null under 30 matches.""")
    public record WinRecord(int wins, int losses, int ties, int matches, Double winRate, Double winRateLow,
                            Double winRateHigh) {}

    public record PokemonUsage(
            @Schema(description = "The app's species key: the species, and form words its regulation lists.",
                    example = "arcanine:hisui") String key,
            @Schema(description = "Teams with it.") int teams,
            @Schema(description = "Share of teams with it.") double usage,
            @Schema(description = "Top-cut teams with it.") int topCutTeams,
            @Schema(description = "Share of top-cut teams with it; null when the window had no top cut.")
            Double topCutUsage,
            @Schema(description = "Usage in the last 14 days less the 14 before; null when either has under 50 teams.")
            Double trend,
            WinRecord record) {}

    public record PokemonList(String format, String window, Instant from, Instant to, Instant generatedAt,
                              Sample sample, List<PokemonUsage> pokemon) {}

    @Schema(description = "A value, and how many of the Pokémon's members (or, for teammates, its teams) had it.")
    public record Share(String value, int count, double share) {}

    @Schema(description = "A whole set, counted as one: item, ability, nature and its moves.")
    public record PokemonSet(String item, String ability, String nature, List<String> moves, int count,
                             double share) {}

    @Schema(description = "Usage in one week (Monday to Sunday, UTC) of the window.")
    public record WeekUsage(LocalDate week, int teams, int withPokemon, double usage) {}

    public record PokemonDetail(String format, String key, String window, Instant from, Instant to,
                                Instant generatedAt, Sample sample, PokemonUsage usage, List<Share> items,
                                List<Share> abilities, List<Share> natures, List<Share> moves,
                                List<Share> megaStones, List<Share> teammates, List<PokemonSet> sets,
                                List<WeekUsage> weekly) {}

    @Schema(description = "Pokémon that are on teams together.")
    public record Core(
            @Schema(description = "Species keys, sorted.") List<String> members,
            @Schema(description = "Teams with all of them.") int teams,
            @Schema(description = "Share of teams with all of them.") double share,
            @Schema(description = "share over what chance would give (the product of their usages): above 1, "
                    + "they're chosen together.") double lift) {}

    public record Cores(String format, String window, Instant from, Instant to, Instant generatedAt,
                        Sample sample, List<Core> pairs, List<Core> trios) {}

    @Schema(description = "One archetype's record against another, from the matches between them.")
    public record Matchup(String against, WinRecord record) {}

    @Schema(description = """
            Teams built around a core of four Pokémon. Cores are the most common sets of four that differ \
            from each more common core by at least two Pokémon; each team belongs to the most common core \
            it contains, and teams with none are "other".""")
    public record Archetype(
            @Schema(description = "The core's species keys, sorted, joined with +.") String id,
            @Schema(description = "Its two most-used members, joined with +.") String name,
            @Schema(description = "The core, most used first.") List<String> core,
            int teams, double usage, int topCutTeams, Double topCutUsage, WinRecord record,
            @Schema(description = "Against each other archetype it has played.") List<Matchup> matchups) {}

    public record Archetypes(String format, String window, Instant from, Instant to, Instant generatedAt,
                             Sample sample, @Schema(description = "Teams in no archetype.") int other,
                             List<Archetype> archetypes) {}
}
