package com.pkreference.backend.insight;

import com.pkreference.backend.insight.MetaRepository.MemberRow;
import com.pkreference.backend.insight.MetaResponses.Format;
import com.pkreference.backend.insight.MetaResponses.Formats;
import com.pkreference.backend.insight.MetaResponses.PokemonDetail;
import com.pkreference.backend.insight.MetaResponses.PokemonList;
import com.pkreference.backend.insight.MetaResponses.PokemonSet;
import com.pkreference.backend.insight.MetaResponses.PokemonUsage;
import com.pkreference.backend.insight.MetaResponses.Sample;
import com.pkreference.backend.insight.MetaResponses.Share;
import com.pkreference.backend.insight.MetaResponses.WeekUsage;
import com.pkreference.backend.standardize.NameStandardizer;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.time.temporal.TemporalAdjusters;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Objects;
import java.util.Set;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;
import java.util.function.Supplier;
import java.util.stream.Collectors;

/**
 * The insights, worked out from the team store when asked: usage in a window, its share of top-cut
 * teams, its trend, and each Pokémon's sets, items, moves and teammates. Results are kept until
 * the store changes (or the hour does, which moves the windows), so a burst of requests is one
 * computation. Definitions are BackendIntegration-PLAN.md §4.2's.
 */
@Service
public class MetaService {
    /** Trend: the last 14 days against the 14 before. */
    static final Duration TREND_PERIOD = Duration.ofDays(14);
    /** Fewer teams than this in either period, and there's no trend. */
    static final int TREND_MIN_TEAMS = 50;
    static final int TOP_VALUES = 12;
    static final int TOP_SETS = 10;

    private final MetaRepository repository;
    private final NameStandardizer names;
    private final Clock clock;
    private final Map<String, Object> memo = new ConcurrentHashMap<>();

    public MetaService(MetaRepository repository, NameStandardizer names, Clock clock) {
        this.repository = repository;
        this.names = names;
        this.clock = clock;
    }

    public Formats formats() {
        Instant now = clock.instant();
        return memoize("formats", now, () -> new Formats(now, repository.formats().stream()
                .map(f -> new Format(f.format(), f.events(), f.teams(), f.firstEvent(), f.lastEvent(), f.lastFetched()))
                .toList()));
    }

    public PokemonList pokemon(String format, MetaWindow window) {
        Instant now = clock.instant();
        return memoize("pokemon|" + format + "|" + window.id(), now, () -> {
            Instant from = window.from(now);
            Teams teams = Teams.of(repository.members(format, from, now));
            var topCut = repository.topCut(format, from, now);
            Set<String> topCutTeams = intersect(topCut.teams(), teams.keysByTeam.keySet());
            Map<String, Double> trends = trends(format, now);

            List<PokemonUsage> pokemon = teams.teamsByKey.entrySet().stream()
                    .map(e -> usage(e.getKey(), e.getValue(), teams.count(), topCutTeams, trends.get(e.getKey())))
                    .sorted(Comparator.comparingInt(PokemonUsage::teams).reversed().thenComparing(PokemonUsage::key))
                    .toList();
            return new PokemonList(format, window.id(), from, now, now,
                    new Sample(teams.events(), teams.count(), topCutTeams.size()), pokemon);
        });
    }

    /** One Pokémon's page. Throws NoSuchElementException when no team in the window had it. */
    public PokemonDetail pokemon(String format, String key, MetaWindow window) {
        Instant now = clock.instant();
        return memoize("detail|" + format + "|" + key + "|" + window.id(), now, () -> {
            Instant from = window.from(now);
            List<MemberRow> rows = repository.members(format, from, now);
            Teams teams = Teams.of(rows);
            Set<String> withIt = teams.teamsByKey.get(key);
            if (withIt == null) throw new NoSuchElementException("No team in the window has " + key);
            var topCut = repository.topCut(format, from, now);
            Set<String> topCutTeams = intersect(topCut.teams(), teams.keysByTeam.keySet());
            PokemonUsage usage = usage(key, withIt, teams.count(), topCutTeams, trends(format, now).get(key));

            List<MemberRow> members = rows.stream().filter(r -> key.equals(r.speciesKey())).toList();
            int n = members.size();
            // Each member's moves, standardized, once each.
            Map<String, Set<String>> movesByMember = new HashMap<>();
            for (String[] m : repository.moves(format, key, from, now)) {
                String move = names.move(format, m[1]);
                if (move != null) movesByMember.computeIfAbsent(m[0], k -> new HashSet<>()).add(move);
            }

            Map<String, Integer> teammates = new HashMap<>();
            for (String team : withIt) {
                for (String other : teams.keysByTeam.get(team)) {
                    if (!other.equals(key)) teammates.merge(other, 1, Integer::sum);
                }
            }

            Map<List<Object>, Integer> sets = new HashMap<>();
            for (MemberRow m : members) {
                List<String> moves = new ArrayList<>(movesByMember.getOrDefault(memberId(m), Set.of()));
                moves.sort(null);
                sets.merge(List.of(Objects.toString(names.item(format, m.item()), ""),
                        Objects.toString(names.ability(format, m.ability()), ""),
                        Objects.toString(names.nature(m.nature()), ""), moves), 1, Integer::sum);
            }
            List<PokemonSet> topSets = sets.entrySet().stream()
                    .sorted(Map.Entry.<List<Object>, Integer>comparingByValue().reversed()
                            .thenComparing(e -> e.getKey().toString()))
                    .limit(TOP_SETS)
                    .map(e -> {
                        @SuppressWarnings("unchecked") List<String> moves = (List<String>) e.getKey().get(3);
                        return new PokemonSet(blankToNull(e.getKey().get(0)), blankToNull(e.getKey().get(1)),
                                blankToNull(e.getKey().get(2)), moves, e.getValue(), ratio(e.getValue(), n));
                    })
                    .toList();

            Map<String, Integer> moveCounts = new HashMap<>();
            movesByMember.values().forEach(ms -> ms.forEach(mv -> moveCounts.merge(mv, 1, Integer::sum)));

            return new PokemonDetail(format, key, window.id(), from, now, now,
                    new Sample(teams.events(), teams.count(), topCutTeams.size()), usage,
                    shares(members, m -> names.item(format, m.item()), n),
                    shares(members, m -> names.ability(format, m.ability()), n),
                    shares(members, m -> names.nature(m.nature()), n),
                    top(moveCounts, n), shares(members, MemberRow::megaStone, n),
                    top(teammates, withIt.size()), topSets, weekly(teams, withIt));
        });
    }

    /** Usage in the last 14 days less the 14 before, for each key; absent when either period is thin. */
    private Map<String, Double> trends(String format, Instant now) {
        Instant split = now.minus(TREND_PERIOD);
        List<MemberRow> rows = repository.members(format, split.minus(TREND_PERIOD), now);
        Teams recent = Teams.of(rows.stream().filter(r -> !r.eventDate().isBefore(split)).toList());
        Teams before = Teams.of(rows.stream().filter(r -> r.eventDate().isBefore(split)).toList());
        Map<String, Double> trends = new HashMap<>();
        if (recent.count() < TREND_MIN_TEAMS || before.count() < TREND_MIN_TEAMS) return trends;
        Set<String> keys = new HashSet<>(recent.teamsByKey.keySet());
        keys.addAll(before.teamsByKey.keySet());
        for (String key : keys) {
            double now_ = ratio(recent.teamsByKey.getOrDefault(key, Set.of()).size(), recent.count());
            double then = ratio(before.teamsByKey.getOrDefault(key, Set.of()).size(), before.count());
            trends.put(key, round(now_ - then));
        }
        return trends;
    }

    private static PokemonUsage usage(String key, Set<String> withIt, int teams, Set<String> topCutTeams, Double trend) {
        int inTopCut = (int) withIt.stream().filter(topCutTeams::contains).count();
        return new PokemonUsage(key, withIt.size(), ratio(withIt.size(), teams), inTopCut,
                topCutTeams.isEmpty() ? null : ratio(inTopCut, topCutTeams.size()), trend);
    }

    private static List<WeekUsage> weekly(Teams teams, Set<String> withIt) {
        Map<LocalDate, int[]> weeks = new TreeMap<>();
        teams.dateByTeam.forEach((team, date) -> {
            LocalDate week = date.atZone(ZoneOffset.UTC).toLocalDate()
                    .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
            int[] counts = weeks.computeIfAbsent(week, w -> new int[2]);
            counts[0]++;
            if (withIt.contains(team)) counts[1]++;
        });
        return weeks.entrySet().stream()
                .map(e -> new WeekUsage(e.getKey(), e.getValue()[0], e.getValue()[1], ratio(e.getValue()[1], e.getValue()[0])))
                .toList();
    }

    private static List<Share> shares(List<MemberRow> members, Function<MemberRow, String> value, int total) {
        Map<String, Integer> counts = new HashMap<>();
        for (MemberRow m : members) {
            String v = value.apply(m);
            if (v != null && !v.isBlank()) counts.merge(v, 1, Integer::sum);
        }
        return top(counts, total);
    }

    private static List<Share> top(Map<String, Integer> counts, int total) {
        return counts.entrySet().stream()
                .sorted(Map.Entry.<String, Integer>comparingByValue().reversed().thenComparing(Map.Entry::getKey))
                .limit(TOP_VALUES)
                .map(e -> new Share(e.getKey(), e.getValue(), ratio(e.getValue(), total)))
                .toList();
    }

    /** Drops every memoized result (tests, whose rolled-back writes reuse versions). */
    void forget() {
        memo.clear();
    }

    @SuppressWarnings("unchecked")
    private <T> T memoize(String key, Instant now, Supplier<T> compute) {
        String full = key + "|" + repository.version() + "|" + now.truncatedTo(ChronoUnit.HOURS);
        if (memo.size() > 500) memo.clear();
        return (T) memo.computeIfAbsent(full, k -> compute.get());
    }

    private static Set<String> intersect(Set<String> a, Set<String> b) {
        return a.stream().filter(b::contains).collect(Collectors.toSet());
    }

    private static String memberId(MemberRow m) {
        return m.eventId() + "|" + m.player() + "|" + m.slot();
    }

    private static String blankToNull(Object o) {
        String s = o.toString();
        return s.isEmpty() ? null : s;
    }

    private static double ratio(int part, int whole) {
        return whole == 0 ? 0 : round((double) part / whole);
    }

    private static double round(double x) {
        return Math.round(x * 10_000) / 10_000.0;
    }

    /** Teams with a published team: each one's Pokémon (once each) and its event's date. */
    private record Teams(Map<String, Set<String>> keysByTeam, Map<String, Set<String>> teamsByKey,
                         Map<String, Instant> dateByTeam, Set<String> eventIds) {
        static Teams of(List<MemberRow> rows) {
            Map<String, Set<String>> keysByTeam = new HashMap<>();
            Map<String, Set<String>> teamsByKey = new HashMap<>();
            Map<String, Instant> dateByTeam = new HashMap<>();
            Set<String> events = new HashSet<>();
            for (MemberRow r : rows) {
                if (r.speciesKey() == null) continue;
                keysByTeam.computeIfAbsent(r.team(), t -> new HashSet<>()).add(r.speciesKey());
                teamsByKey.computeIfAbsent(r.speciesKey(), k -> new HashSet<>()).add(r.team());
                dateByTeam.put(r.team(), r.eventDate());
                events.add(r.eventId());
            }
            return new Teams(keysByTeam, teamsByKey, dateByTeam, events);
        }

        int count() {
            return keysByTeam.size();
        }

        int events() {
            return eventIds.size();
        }
    }
}
