package com.pkreference.backend.ladder;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.pkreference.backend.model.Ladder.Pokemon;
import com.pkreference.backend.model.Ladder.Stats;
import com.pkreference.backend.model.Ladder.StatsFetched;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.TreeMap;

/**
 * The ladder_stats table: each reduced month of Smogon's stats, as ladder.stats delivered it. A
 * newer record of a format, month and rating replaces the stored one.
 */
@Repository
public class LadderStore {
    /** One stored record, without its Pokémon. */
    public record Entry(String format, String regulation, String mode, int bestOf, String month, int rating,
                        long battles, int reduction, Instant fetchedAt) {}

    /** A stored record, and when it was fetched. */
    public record Stored(Stats stats, Instant fetchedAt) {}

    private static final TypeReference<LinkedHashMap<String, Double>> USAGE = new TypeReference<>() {};

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;

    public LadderStore(JdbcTemplate jdbc, ObjectMapper mapper) {
        this.jdbc = jdbc;
        this.mapper = mapper;
    }

    /**
     * Stores a record, unless the one stored was made by a newer rule, or by the same rule from a
     * newer fetch. False when it was left out.
     */
    @Transactional
    public boolean put(StatsFetched fetched) {
        Stats s = fetched.stats();
        var stored = jdbc.query("""
                select reduction, fetched_at from ladder_stats where format = ? and stats_month = ? and rating = ?""",
                (rs, n) -> Map.entry(rs.getInt(1), rs.getObject(2, OffsetDateTime.class).toInstant()),
                s.format(), s.month(), s.rating());
        if (!stored.isEmpty()) {
            int reduction = stored.get(0).getKey();
            if (reduction > s.reduction()) return false;
            if (reduction == s.reduction() && stored.get(0).getValue().isAfter(fetched.fetchedAt())) return false;
            jdbc.update("delete from ladder_stats where format = ? and stats_month = ? and rating = ?",
                    s.format(), s.month(), s.rating());
        }
        Map<String, Double> usage = new LinkedHashMap<>();
        for (Pokemon p : s.pokemon()) usage.put(p.name(), p.usage());
        jdbc.update("""
                insert into ladder_stats (format, stats_month, rating, regulation, mode, best_of, battles, reduction,
                                          fetched_at, usage_by_name, stats)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                s.format(), s.month(), s.rating(), s.regulation(), s.mode(), s.bestOf(), s.battles(), s.reduction(),
                OffsetDateTime.ofInstant(fetched.fetchedAt(), ZoneOffset.UTC), write(usage), write(s));
        return true;
    }

    /** Whether a record is stored, made by this rule or a newer one. */
    public boolean has(String format, String month, int rating, int reduction) {
        Integer count = jdbc.queryForObject("""
                select count(*) from ladder_stats
                where format = ? and stats_month = ? and rating = ? and reduction >= ?""",
                Integer.class, format, month, rating, reduction);
        return count != null && count > 0;
    }

    /** Everything stored: by format, then newest month first, then rating. */
    public List<Entry> index() {
        return jdbc.query("""
                select format, regulation, mode, best_of, stats_month, rating, battles, reduction, fetched_at
                from ladder_stats order by format, stats_month desc, rating""",
                (rs, n) -> new Entry(rs.getString(1), rs.getString(2), rs.getString(3), rs.getInt(4), rs.getString(5),
                        rs.getInt(6), rs.getLong(7), rs.getInt(8), rs.getObject(9, OffsetDateTime.class).toInstant()));
    }

    /** The newest month stored for a format at a rating. */
    public Optional<String> newestMonth(String format, int rating) {
        return jdbc.queryForList("select max(stats_month) from ladder_stats where format = ? and rating = ?",
                String.class, format, rating).stream().filter(m -> m != null).findFirst();
    }

    public Optional<Stored> find(String format, String month, int rating) {
        return jdbc.query("""
                select stats, fetched_at from ladder_stats where format = ? and stats_month = ? and rating = ?""",
                (rs, n) -> new Stored(read(rs.getString(1), Stats.class),
                        rs.getObject(2, OffsetDateTime.class).toInstant()),
                format, month, rating).stream().findFirst();
    }

    /** Each Pokémon's usage in a format's month, by rating and then by its name. */
    public Map<Integer, Map<String, Double>> usage(String format, String month) {
        Map<Integer, Map<String, Double>> byRating = new TreeMap<>();
        jdbc.query("select rating, usage_by_name from ladder_stats where format = ? and stats_month = ?", rs -> {
            try {
                byRating.put(rs.getInt(1), mapper.readValue(rs.getString(2), USAGE));
            } catch (JsonProcessingException e) {
                throw new IllegalStateException("Stored ladder usage doesn't read", e);
            }
        }, format, month);
        return byRating;
    }

    private String write(Object value) {
        try {
            return mapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Ladder stats don't write as JSON", e);
        }
    }

    private <T> T read(String json, Class<T> type) {
        try {
            return mapper.readValue(json, type);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Stored ladder stats don't read", e);
        }
    }
}
