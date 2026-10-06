package com.pkreference.backend.insight;

import com.pkreference.backend.insight.MetaRepository.EventRow;
import com.pkreference.backend.insight.MetaRepository.MemberRow;
import com.pkreference.backend.insight.MetaRepository.PairingRow;
import com.pkreference.backend.insight.MetaRepository.PlacingRow;
import com.pkreference.backend.insight.MetaRepository.TeamMemberRow;
import com.pkreference.backend.insight.MetaResponses.Archetype;
import com.pkreference.backend.insight.MetaResponses.ArchetypeDetail;
import com.pkreference.backend.insight.MetaResponses.Archetypes;
import com.pkreference.backend.insight.MetaResponses.Core;
import com.pkreference.backend.insight.MetaResponses.Cores;
import com.pkreference.backend.insight.MetaResponses.EventSummary;
import com.pkreference.backend.insight.MetaResponses.EventWinner;
import com.pkreference.backend.insight.MetaResponses.Events;
import com.pkreference.backend.insight.MetaResponses.ExampleMember;
import com.pkreference.backend.insight.MetaResponses.ExampleTeam;
import com.pkreference.backend.insight.MetaResponses.Matchup;
import com.pkreference.backend.insight.MetaResponses.Format;
import com.pkreference.backend.insight.MetaResponses.Formats;
import com.pkreference.backend.insight.MetaResponses.PokemonDetail;
import com.pkreference.backend.insight.MetaResponses.PokemonList;
import com.pkreference.backend.insight.MetaResponses.PokemonSet;
import com.pkreference.backend.insight.MetaResponses.PokemonUsage;
import com.pkreference.backend.insight.MetaResponses.Sample;
import com.pkreference.backend.insight.MetaResponses.Share;
import com.pkreference.backend.insight.MetaResponses.WeekUsage;
import com.pkreference.backend.insight.MetaResponses.WinRecord;
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
    /** Fewer matches than this, and there's no win rate. */
    static final int MIN_MATCHES = 30;
    static final int TOP_CORES = 20;
    /** A core or archetype needs at least this many teams, and at least ARCHETYPE_SHARE of them. */
    static final int MIN_CORE_TEAMS = 4;
    static final double ARCHETYPE_SHARE = 0.02;
    /** An archetype page's example teams. */
    static final int EXAMPLE_TEAMS = 5;

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
            Map<String, int[]> records = records(teams, repository.pairings(format, from, now));

            List<PokemonUsage> pokemon = teams.teamsByKey.entrySet().stream()
                    .map(e -> usage(e.getKey(), e.getValue(), teams.count(), topCutTeams, trends.get(e.getKey()),
                            records.get(e.getKey())))
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
            PokemonUsage usage = usage(key, withIt, teams.count(), topCutTeams, trends(format, now).get(key),
                    records(teams, repository.pairings(format, from, now)).get(key));

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

    /** The pairs and trios most often on teams together, with how much more often than chance. */
    public Cores cores(String format, MetaWindow window) {
        Instant now = clock.instant();
        return memoize("cores|" + format + "|" + window.id(), now, () -> {
            Instant from = window.from(now);
            Teams teams = Teams.of(repository.members(format, from, now));
            var topCut = repository.topCut(format, from, now);
            int topCutTeams = intersect(topCut.teams(), teams.keysByTeam.keySet()).size();
            return new Cores(format, window.id(), from, now, now, new Sample(teams.events(), teams.count(), topCutTeams),
                    topCores(teams, 2), topCores(teams, 3));
        });
    }

    private static List<Core> topCores(Teams teams, int size) {
        Map<List<String>, Integer> counts = new HashMap<>();
        for (Set<String> keys : teams.keysByTeam.values()) {
            for (List<String> combo : combinations(keys, size)) counts.merge(combo, 1, Integer::sum);
        }
        int n = teams.count();
        return counts.entrySet().stream()
                .filter(e -> e.getValue() >= MIN_CORE_TEAMS)
                .sorted(Map.Entry.<List<String>, Integer>comparingByValue().reversed()
                        .thenComparing(e -> String.join("+", e.getKey())))
                .limit(TOP_CORES)
                .map(e -> {
                    double share = (double) e.getValue() / n;
                    double chance = 1;
                    for (String key : e.getKey()) chance *= (double) teams.teamsByKey.get(key).size() / n;
                    return new Core(e.getKey(), e.getValue(), round(share), round(share / chance));
                })
                .toList();
    }

    /**
     * Archetypes: cores of four, the most common first, each differing from every more common core
     * by at least two Pokémon (sharing at most two), with at least MIN_CORE_TEAMS teams and
     * ARCHETYPE_SHARE of them. Each team belongs to the first core it contains. Each is named by its
     * two most-used members, and by more of its core when an archetype with more teams has that name.
     */
    public Archetypes archetypes(String format, MetaWindow window) {
        Instant now = clock.instant();
        return memoize("archetypes|" + format + "|" + window.id(), now, () -> {
            Grouping g = grouping(format, window, now);
            Teams teams = g.teams();
            int n = teams.count();

            // Records: overall, and against each other archetype.
            Map<String, int[]> overall = new HashMap<>();
            Map<String, Map<String, int[]>> against = new HashMap<>();
            for (PairingRow p : repository.pairings(format, g.from(), now)) {
                String a = g.archetypeOf().get(p.team1());
                String b = g.archetypeOf().get(p.team2());
                if (!teams.keysByTeam.containsKey(p.team1()) || !teams.keysByTeam.containsKey(p.team2())) continue;
                if (a != null && !a.equals(b)) {
                    int o = outcome(p.result(), true);
                    overall.computeIfAbsent(a, k -> new int[3])[o]++;
                    if (b != null) against.computeIfAbsent(a, k -> new HashMap<>()).computeIfAbsent(b, k -> new int[3])[o]++;
                }
                if (b != null && !b.equals(a)) {
                    int o = outcome(p.result(), false);
                    overall.computeIfAbsent(b, k -> new int[3])[o]++;
                    if (a != null) against.computeIfAbsent(b, k -> new HashMap<>()).computeIfAbsent(a, k -> new int[3])[o]++;
                }
            }

            List<Archetype> archetypes = new ArrayList<>();
            for (List<String> core : g.cores()) {
                String id = String.join("+", core);
                Set<String> inIt = g.members().getOrDefault(id, Set.of());
                if (inIt.isEmpty()) continue;
                List<String> byUsage = core.stream()
                        .sorted(Comparator.comparingInt((String k) -> -teams.teamsByKey.get(k).size()).thenComparing(k -> k))
                        .toList();
                int inTopCut = (int) inIt.stream().filter(g.topCutTeams()::contains).count();
                List<Matchup> matchups = against.getOrDefault(id, Map.of()).entrySet().stream()
                        .map(e -> new Matchup(e.getKey(), winRecord(e.getValue())))
                        .sorted(Comparator.comparingInt((Matchup m) -> -m.record().matches()).thenComparing(Matchup::against))
                        .toList();
                archetypes.add(new Archetype(id, null, byUsage, inIt.size(),
                        ratio(inIt.size(), n), inTopCut,
                        g.topCutTeams().isEmpty() ? null : ratio(inTopCut, g.topCutTeams().size()),
                        winRecord(overall.get(id)), matchups));
            }
            archetypes.sort(Comparator.comparingInt((Archetype a) -> -a.teams()).thenComparing(Archetype::id));
            return new Archetypes(format, window.id(), g.from(), now, now,
                    new Sample(teams.events(), n, g.topCutTeams().size()), n - g.archetypeOf().size(),
                    named(archetypes));
        });
    }

    /**
     * Names in order (most teams first): the two most-used members, or as many more as it takes to
     * differ from every name before it.
     */
    static List<Archetype> named(List<Archetype> archetypes) {
        Set<String> used = new HashSet<>();
        List<Archetype> out = new ArrayList<>();
        for (Archetype a : archetypes) {
            int size = 2;
            String name = String.join("+", a.core().subList(0, size));
            while (used.contains(name) && size < a.core().size()) name = String.join("+", a.core().subList(0, ++size));
            used.add(name);
            out.add(new Archetype(a.id(), name, a.core(), a.teams(), a.usage(), a.topCutTeams(), a.topCutUsage(),
                    a.record(), a.matchups()));
        }
        return out;
    }

    /** One archetype, with its best-placed teams. Throws NoSuchElementException for an id not in the window. */
    public ArchetypeDetail archetype(String format, String id, MetaWindow window) {
        Instant now = clock.instant();
        return memoize("archetype|" + format + "|" + id + "|" + window.id(), now, () -> {
            Archetypes all = archetypes(format, window);
            Archetype archetype = all.archetypes().stream().filter(a -> a.id().equals(id)).findFirst()
                    .orElseThrow(() -> new NoSuchElementException("No archetype " + id + " in the window"));
            Set<String> inIt = grouping(format, window, now).members().getOrDefault(id, Set.of());
            List<PlacingRow> best = repository.placings(format, all.from(), now).stream()
                    .filter(p -> p.placing() != null && inIt.contains(p.team()))
                    .sorted(Comparator.comparingInt(PlacingRow::placing)
                            .thenComparing(Comparator.comparingInt(PlacingRow::players).reversed())
                            .thenComparing(PlacingRow::eventDate, Comparator.nullsLast(Comparator.reverseOrder()))
                            .thenComparing(PlacingRow::team))
                    .limit(EXAMPLE_TEAMS)
                    .toList();
            Map<String, List<ExampleMember>> members = new HashMap<>();
            for (TeamMemberRow m : repository.teamMembers(best.stream().map(PlacingRow::team).collect(Collectors.toSet()))) {
                List<String> moves = m.moves().stream().map(mv -> names.move(format, mv)).filter(Objects::nonNull).toList();
                members.computeIfAbsent(m.team(), k -> new ArrayList<>()).add(new ExampleMember(m.speciesKey(), m.name(),
                        names.item(format, m.item()), names.ability(format, m.ability()), names.nature(m.nature()), moves));
            }
            List<ExampleTeam> examples = best.stream()
                    .map(p -> new ExampleTeam(p.eventId(), p.eventName(), p.eventDate(), p.players(), p.name(), p.placing(),
                            p.wins(), p.losses(), p.ties(), members.getOrDefault(p.team(), List.of())))
                    .toList();
            return new ArchetypeDetail(format, window.id(), all.from(), now, now, all.sample(), archetype, examples);
        });
    }

    /** The format's newest stored events, with their top cuts and winners. */
    public Events events(String format, int limit) {
        Instant now = clock.instant();
        return memoize("events|" + format + "|" + limit, now, () -> {
            List<EventRow> rows = repository.events(format, limit);
            List<String> ids = rows.stream().map(EventRow::id).toList();
            Map<String, Integer> topCuts = repository.topCutPlayers(ids);
            Map<String, PlacingRow> winners = new HashMap<>();
            for (PlacingRow w : repository.winners(ids)) winners.putIfAbsent(w.eventId(), w);
            Map<String, List<String>> teams = new HashMap<>();
            for (TeamMemberRow m : repository.teamMembers(winners.values().stream().map(PlacingRow::team)
                    .collect(Collectors.toSet()))) {
                if (m.speciesKey() != null) teams.computeIfAbsent(m.team(), k -> new ArrayList<>()).add(m.speciesKey());
            }
            return new Events(format, now, rows.stream().map(e -> {
                PlacingRow w = winners.get(e.id());
                EventWinner winner = w == null ? null : new EventWinner(w.name(), w.wins(), w.losses(), w.ties(),
                        teams.getOrDefault(w.team(), List.of()));
                return new EventSummary(e.id(), e.name(), e.date(), e.players(), e.standingsFinal(),
                        topCuts.get(e.id()), winner);
            }).toList());
        });
    }

    /** Teams grouped into archetypes, before anything is counted: what the list and each page share. */
    private record Grouping(Instant from, Teams teams, Set<String> topCutTeams, List<List<String>> cores,
                            Map<String, String> archetypeOf, Map<String, Set<String>> members) {}

    private Grouping grouping(String format, MetaWindow window, Instant now) {
        return memoize("grouping|" + format + "|" + window.id(), now, () -> {
            Instant from = window.from(now);
            Teams teams = Teams.of(repository.members(format, from, now));
            var topCut = repository.topCut(format, from, now);
            Set<String> topCutTeams = intersect(topCut.teams(), teams.keysByTeam.keySet());
            int n = teams.count();
            int minTeams = Math.max(MIN_CORE_TEAMS, (int) Math.ceil(ARCHETYPE_SHARE * n));

            Map<List<String>, Integer> quads = new HashMap<>();
            for (Set<String> keys : teams.keysByTeam.values()) {
                for (List<String> combo : combinations(keys, 4)) quads.merge(combo, 1, Integer::sum);
            }
            List<List<String>> cores = new ArrayList<>();
            quads.entrySet().stream()
                    .filter(e -> e.getValue() >= minTeams)
                    .sorted(Map.Entry.<List<String>, Integer>comparingByValue().reversed()
                            .thenComparing(e -> String.join("+", e.getKey())))
                    .forEach(e -> {
                        boolean distinct = cores.stream().allMatch(c -> c.stream().filter(e.getKey()::contains).count() <= 2);
                        if (distinct) cores.add(e.getKey());
                    });

            Map<String, String> archetypeOf = new HashMap<>();
            Map<String, Set<String>> members = new HashMap<>();
            for (var team : teams.keysByTeam.entrySet()) {
                for (List<String> core : cores) {
                    if (team.getValue().containsAll(core)) {
                        String id = String.join("+", core);
                        archetypeOf.put(team.getKey(), id);
                        members.computeIfAbsent(id, k -> new HashSet<>()).add(team.getKey());
                        break;
                    }
                }
            }
            return new Grouping(from, teams, topCutTeams, cores, archetypeOf, members);
        });
    }

    /** Every sorted combination of `size` keys. */
    static List<List<String>> combinations(Set<String> keys, int size) {
        List<String> sorted = keys.stream().sorted().toList();
        List<List<String>> out = new ArrayList<>();
        combine(sorted, size, 0, new ArrayList<>(), out);
        return out;
    }

    private static void combine(List<String> keys, int size, int start, List<String> current, List<List<String>> out) {
        if (current.size() == size) {
            out.add(List.copyOf(current));
            return;
        }
        for (int i = start; i < keys.size(); i++) {
            current.add(keys.get(i));
            combine(keys, size, i + 1, current, out);
            current.remove(current.size() - 1);
        }
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

    private static PokemonUsage usage(String key, Set<String> withIt, int teams, Set<String> topCutTeams, Double trend,
                                      int[] record) {
        int inTopCut = (int) withIt.stream().filter(topCutTeams::contains).count();
        return new PokemonUsage(key, withIt.size(), ratio(withIt.size(), teams), inTopCut,
                topCutTeams.isEmpty() ? null : ratio(inTopCut, topCutTeams.size()), trend, winRecord(record));
    }

    /**
     * Each Pokémon's wins, losses and ties ([w, l, t]) in matches between two teams with published
     * lists, leaving out mirror matches: a Pokémon on both teams says nothing about itself.
     */
    static Map<String, int[]> records(Teams teams, List<PairingRow> pairings) {
        Map<String, int[]> records = new HashMap<>();
        for (PairingRow p : pairings) {
            Set<String> one = teams.keysByTeam.get(p.team1());
            Set<String> two = teams.keysByTeam.get(p.team2());
            if (one == null || two == null) continue;
            tally(records, one, two, outcome(p.result(), true));
            tally(records, two, one, outcome(p.result(), false));
        }
        return records;
    }

    /** 0 win, 1 loss, 2 tie, for player 1 or player 2. A double loss is a loss for both. */
    private static int outcome(String result, boolean player1) {
        return switch (result) {
            case "P1" -> player1 ? 0 : 1;
            case "P2" -> player1 ? 1 : 0;
            case "TIE" -> 2;
            default -> 1;
        };
    }

    private static void tally(Map<String, int[]> records, Set<String> mine, Set<String> theirs, int outcome) {
        for (String key : mine) {
            if (!theirs.contains(key)) records.computeIfAbsent(key, k -> new int[3])[outcome]++;
        }
    }

    /** Win rate (a tie is half a win) with its 95% Wilson range; both null under MIN_MATCHES. */
    static WinRecord winRecord(int[] r) {
        if (r == null) return new WinRecord(0, 0, 0, 0, null, null, null);
        int n = r[0] + r[1] + r[2];
        if (n < MIN_MATCHES) return new WinRecord(r[0], r[1], r[2], n, null, null, null);
        double p = (r[0] + r[2] / 2.0) / n;
        double z = 1.96;
        double denominator = 1 + z * z / n;
        double centre = (p + z * z / (2 * n)) / denominator;
        double half = z * Math.sqrt(p * (1 - p) / n + z * z / (4.0 * n * n)) / denominator;
        return new WinRecord(r[0], r[1], r[2], n, round(p), round(centre - half), round(centre + half));
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

    /**
     * Not computeIfAbsent: one result can be worked out from another (an archetype page from the
     * grouping), and a ConcurrentHashMap can't be changed from inside its own computeIfAbsent. Two
     * requests at once may both compute a result; the answers are the same.
     */
    @SuppressWarnings("unchecked")
    private <T> T memoize(String key, Instant now, Supplier<T> compute) {
        String full = key + "|" + repository.version() + "|" + now.truncatedTo(ChronoUnit.HOURS);
        Object known = memo.get(full);
        if (known != null) return (T) known;
        T value = compute.get();
        if (memo.size() > 500) memo.clear();
        memo.put(full, value);
        return value;
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
    record Teams(Map<String, Set<String>> keysByTeam, Map<String, Set<String>> teamsByKey,
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
