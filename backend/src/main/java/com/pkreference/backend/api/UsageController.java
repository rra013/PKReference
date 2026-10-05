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

@RestController
@RequestMapping("/api/usage")
public class UsageController {
    private final UsageCounterRepository counters;

    public UsageController(UsageCounterRepository counters) {
        this.counters = counters;
    }

    public record SpeciesUsage(String species, long teams, double usagePercent) {}

    public record SpeciesDetail(String species, long teams, double usagePercent,
                                Map<String, List<ValueCount>> breakdown) {}

    public record ValueCount(String value, long count) {}

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

    private long totalTeams(String format) {
        return counters.findById(UsageCounter.key(format, UsageCounter.TEAMS, UsageCounter.TOTAL_SPECIES, ""))
                .map(UsageCounter::getCount).orElse(0L);
    }

    private static double percent(long n, long total) {
        return total == 0 ? 0 : Math.round(10000.0 * n / total) / 100.0;
    }
}
