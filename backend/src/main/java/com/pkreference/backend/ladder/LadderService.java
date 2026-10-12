package com.pkreference.backend.ladder;

import com.pkreference.backend.ladder.LadderResponses.Entry;
import com.pkreference.backend.ladder.LadderResponses.Index;
import com.pkreference.backend.ladder.LadderResponses.Pokemon;
import com.pkreference.backend.ladder.LadderResponses.RatingUsage;
import com.pkreference.backend.ladder.LadderResponses.Stats;
import org.springframework.stereotype.Service;

import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;

/**
 * The ladder stats, as /v1/ladder serves them: a stored record, with what the other stored files
 * add to it (each Pokémon's change since the month before, and its usage at the other ratings).
 * Nothing is kept in memory: a record is one row, read when it's asked for.
 */
@Service
public class LadderService {
    public static final int DEFAULT_RATING = 1760;

    private final LadderStore store;

    /** Spring passes in the store. */
    public LadderService(LadderStore store) {
        this.store = store;
    }

    /** GET /v1/ladder: every stored format, month and rating, without the Pokémon. */
    public Index index() {
        return new Index(store.index().stream().map(e -> new Entry(e.format(), e.regulation(), e.mode(), e.bestOf(),
                e.month(), e.rating(), e.battles(), e.fetchedAt())).toList());
    }

    /** A format's month at a rating: 1760 and the newest stored month when they aren't given. */
    public Stats stats(String format, Integer rating, String month) {
        int cutoff = rating == null ? DEFAULT_RATING : rating;
        String chosen = month != null ? month : store.newestMonth(format, cutoff).orElseThrow(() ->
                new NoSuchElementException("No ladder stats stored for " + format + " at " + cutoff));
        var stored = store.find(format, chosen, cutoff).orElseThrow(() ->
                new NoSuchElementException("No ladder stats stored for " + format + " at " + cutoff + " in " + chosen));
        var s = stored.stats();

        Map<Integer, Map<String, Double>> byRating = store.usage(format, chosen);
        // "2026-09" less a month is "2026-08"; January's is the December before.
        String previous = YearMonth.parse(chosen).minusMonths(1).toString();
        Map<String, Double> before = store.usage(format, previous).get(cutoff);

        List<Pokemon> pokemon = new ArrayList<>(s.pokemon().size());
        for (var p : s.pokemon()) {
            List<RatingUsage> usages = new ArrayList<>();
            byRating.forEach((r, usage) -> {
                Double at = usage.get(p.name());
                if (at != null) usages.add(new RatingUsage(r, at));
            });
            // Smogon lists every Pokémon used at all, so one missing last month wasn't used.
            Double trend = before == null ? null : p.usage() - before.getOrDefault(p.name(), 0.0);
            pokemon.add(new Pokemon(p.name(), p.key(), p.megaStone(), p.usage(), trend, usages, p.leadShare(),
                    p.abilities(), p.items(), p.moves(), p.natures(), p.spreads(), p.teammates()));
        }
        return new Stats(s.reduction(), s.format(), s.regulation(), s.mode(), s.bestOf(), s.month(), s.rating(),
                s.battles(), stored.fetchedAt(), before == null ? null : previous, List.copyOf(byRating.keySet()),
                pokemon);
    }
}
