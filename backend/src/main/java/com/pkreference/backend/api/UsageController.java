package com.pkreference.backend.api;

import com.pkreference.backend.usage.UsageCounter;
import com.pkreference.backend.usage.UsageCounterRepository;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * The first version's API: all-time usage from the counters, at /api/usage. Nothing in the app
 * calls it now (the app reads /v1); it's kept until the plan's Phase 7.
 *
 * <p>{@code @RestController} makes this a bean whose methods answer HTTP requests, with whatever they
 * return written as JSON. {@code @RequestMapping("/api/usage")} is the path every method here
 * starts from.
 */
@RestController
@RequestMapping("/api/usage")
public class UsageController {
    private final UsageCounterRepository counters;

    /** Constructor injection: Spring supplies each parameter from the beans it has made. */
    public UsageController(UsageCounterRepository counters) {
        this.counters = counters;
    }

    /** One row of the list: a Pokémon, the teams running it and that as a percentage of all teams. */
    public record SpeciesUsage(String species, long teams, double usagePercent) {}

    /**
     * One Pokémon's page: its totals, then its counters grouped by category ("item", "move" and so
     * on).
     */
    public record SpeciesDetail(String species, long teams, double usagePercent,
                                Map<String, List<ValueCount>> breakdown) {}

    /** A value (an item, a move) and how many of the Pokémon's sets had it. */
    public record ValueCount(String value, long count) {}

    /**
     * GET /api/usage?format=M-C&limit=50: the most-used Pokémon. {@code @RequestParam} binds a
     * query parameter to an argument; one without a default is required, and leaving it out is a
     * 400. {@code limit} is kept between 1 and 500.
     */
    @GetMapping
    public List<SpeciesUsage> top(@RequestParam String format,
                                  @RequestParam(defaultValue = "50") int limit) {
        long total = totalTeams(format);
        return counters.findByFormatAndCategoryOrderByCountDesc(
                        format, UsageCounter.SPECIES, PageRequest.of(0, Math.min(Math.max(limit, 1), 500)))
                .stream()
                .map(c -> new SpeciesUsage(c.getSpecies(), c.getCount(), percent(c.getCount(), total)))
                .toList();
    }

    /**
     * GET /api/usage/{species}?format=M-C: one Pokémon's items, abilities, moves, Tera types and
     * natures. {@code @PathVariable} binds the {@code {species}} part of the path. Throwing
     * {@code ResponseStatusException} is the short way to answer with a status, here 404.
     */
    @GetMapping("/{species}")
    public SpeciesDetail detail(@PathVariable String species, @RequestParam String format) {
        var rows = counters.findByFormatAndSpeciesAndCategoryNotInOrderByCountDesc(
                format, species, List.of(UsageCounter.TEAMS));
        var self = rows.stream().filter(r -> UsageCounter.SPECIES.equals(r.getCategory())).findFirst()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No usage for " + species));
        Map<String, List<ValueCount>> breakdown = new LinkedHashMap<>();
        for (var r : rows) {
            if (UsageCounter.SPECIES.equals(r.getCategory())) continue;
            breakdown.computeIfAbsent(r.getCategory().toLowerCase(), k -> new java.util.ArrayList<>())
                    .add(new ValueCount(r.getValue(), r.getCount()));
        }
        return new SpeciesDetail(species, self.getCount(), percent(self.getCount(), totalTeams(format)), breakdown);
    }

    /** The format's team count, kept as a counter of its own (category TEAMS). */
    private long totalTeams(String format) {
        return counters.findById(UsageCounter.key(format, UsageCounter.TEAMS, UsageCounter.TOTAL_SPECIES, ""))
                .map(UsageCounter::getCount).orElse(0L);
    }

    /** A percentage to two places; 0 when there are no teams. */
    private static double percent(long n, long total) {
        return total == 0 ? 0 : Math.round(10000.0 * n / total) / 100.0;
    }
}
