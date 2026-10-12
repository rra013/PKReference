package com.pkreference.backend.usage;

import com.pkreference.backend.model.Events.StandingsFetched;
import com.pkreference.backend.model.Events.TeamMember;
import com.pkreference.backend.model.Events.UsageUpdated;
import com.pkreference.backend.standardize.NameStandardizer;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Turns one event's standings into counter changes: how many teams ran each Pokémon, and for each
 * Pokémon how many ran each item, ability, move, Tera type and nature.
 *
 * <p>{@code @Service} is {@code @Component} under another name: it makes the class a bean, and says to
 * the reader that it holds business logic rather than talking to the web or the database. The
 * database work goes through the two repositories it's given.
 */
@Service
public class UsageAggregationService {
    private final UsageCounterRepository counters;
    private final ProcessedTournamentRepository processed;
    private final NameStandardizer names;

    /** Constructor injection: Spring supplies each parameter from the beans it has made. */
    public UsageAggregationService(UsageCounterRepository counters, ProcessedTournamentRepository processed,
                                   NameStandardizer names) {
        this.counters = counters;
        this.processed = processed;
        this.names = names;
    }

    /**
     * Folds one tournament into the counters and records it as processed in the same transaction.
     * Replaying the same tournament is a no-op (returns an empty list).
     */
    @Transactional
    public List<UsageUpdated> apply(StandingsFetched event) {
        // Counted once, so only once its standings won't change; the fetcher fetches it again until then.
        if (!event.isFinal()) return List.of();
        var tournament = event.tournament();
        if (processed.existsById(tournament.id())) return List.of();

        String format = tournament.format() == null || tournament.format().isBlank()
                ? "unknown" : tournament.format();

        // Every counter this event changes, by its key, and by how much: built in memory first,
        // written once.
        Map<String, Long> deltas = new LinkedHashMap<>();
        Set<String> touchedSpecies = new HashSet<>();
        long teams = 0;

        for (var standing : event.standings()) {
            var decklist = standing.decklist();
            if (decklist == null || decklist.isEmpty()) continue;
            teams++;
            Set<String> seenOnThisTeam = new HashSet<>();
            for (TeamMember m : decklist) {
                String species = speciesKey(m);
                if (species == null) continue;
                if (seenOnThisTeam.add(species)) {
                    bump(deltas, format, UsageCounter.SPECIES, species, "");
                    touchedSpecies.add(species);
                }
                bump(deltas, format, "ITEM", species, names.item(format, m.item()));
                bump(deltas, format, "ABILITY", species, names.ability(format, m.ability()));
                bump(deltas, format, "TERA", species, names.tera(m.tera()));
                bump(deltas, format, "NATURE", species, names.nature(m.nature()));
                if (m.attacks() != null) {
                    // A move listed twice on one set (typo or duplicate) still counts once.
                    m.attacks().stream().map(a -> names.move(format, a)).filter(a -> a != null)
                            .distinct().forEach(a -> bump(deltas, format, "MOVE", species, a));
                }
            }
        }
        if (teams > 0) {
            deltas.merge(UsageCounter.key(format, UsageCounter.TEAMS, UsageCounter.TOTAL_SPECIES, ""), teams, Long::sum);
        }

        // Load the counters that exist, create the ones that don't, add the changes, save them all.
        Map<String, UsageCounter> existing = counters.findAllById(deltas.keySet()).stream()
                .collect(Collectors.toMap(UsageCounter::getId, Function.identity()));
        for (var e : deltas.entrySet()) {
            var counter = existing.computeIfAbsent(e.getKey(), k -> newCounter(k));
            counter.add(e.getValue());
        }
        counters.saveAll(existing.values());
        processed.save(new ProcessedTournament(tournament.id()));

        long total = existing.get(UsageCounter.key(format, UsageCounter.TEAMS, UsageCounter.TOTAL_SPECIES, ""))
                == null ? 0 : existing.get(UsageCounter.key(format, UsageCounter.TEAMS, UsageCounter.TOTAL_SPECIES, "")).getCount();
        List<UsageUpdated> updates = new ArrayList<>();
        for (String species : touchedSpecies) {
            long n = existing.get(UsageCounter.key(format, UsageCounter.SPECIES, species, "")).getCount();
            updates.add(new UsageUpdated(format, species, n, total));
        }
        return updates;
    }

    /**
     * A zeroed counter for a key, "format|category|species|value"; the value may itself contain
     * "|", hence the limit of 4.
     */
    private static UsageCounter newCounter(String key) {
        String[] p = key.split("\\|", 4);
        return new UsageCounter(p[0], p[1], p[2], p.length > 3 ? p[3] : "");
    }

    /** Adds one to a counter's pending change. Nothing to count when the value is missing. */
    private static void bump(Map<String, Long> deltas, String format, String category, String species, String value) {
        if (value == null) return;
        if (!UsageCounter.SPECIES.equals(category) && value.isBlank()) return;
        deltas.merge(UsageCounter.key(format, category, species, value), 1L, Long::sum);
    }

    /**
     * The Pokémon's key for these counters: Limitless's slug, or its name lowercased. (The team
     * store uses the app's species key instead.)
     */
    private static String speciesKey(TeamMember m) {
        if (m.limitlessId() != null && !m.limitlessId().isBlank()) return m.limitlessId();
        return m.name() == null || m.name().isBlank() ? null : lower(m.name());
    }

    /** Lowercased the same way in every locale. */
    private static String lower(String s) {
        return s == null ? null : s.toLowerCase(Locale.ROOT);
    }
}
