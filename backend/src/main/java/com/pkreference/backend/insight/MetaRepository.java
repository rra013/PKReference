package com.pkreference.backend.insight;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Reads the team store for the insights. Plain rows only: the counting is MetaService's, in Java,
 * so the SQL stays the same on H2 and Postgres.
 */
@Repository
public class MetaRepository {
    private final JdbcTemplate jdbc;

    public MetaRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** One format's stored events. */
    public record FormatRow(String format, int events, int teams, Instant firstEvent, Instant lastEvent,
                            Instant lastFetched) {}

    /** One team member, with its event's date. */
    public record MemberRow(String eventId, String player, Instant eventDate, int slot, String speciesKey,
                            String megaStone, String item, String ability, String nature) {
        public String team() {
            return eventId + "|" + player;
        }
    }

    public List<FormatRow> formats() {
        return jdbc.query("""
                select e.format, count(distinct e.id), count(distinct t.event_id || '|' || t.player),
                       min(e.event_date), max(e.event_date), max(e.fetched_at)
                from event e left join team t on t.event_id = e.id
                    and exists (select 1 from team_member m where m.event_id = t.event_id and m.player = t.player)
                group by e.format order by max(e.event_date) desc""",
                (rs, n) -> new FormatRow(rs.getString(1), rs.getInt(2), rs.getInt(3), instant(rs, 4), instant(rs, 5),
                        instant(rs, 6)));
    }

    /** The team store's version, which each write bumps: what results are memoized on. */
    public long version() {
        return jdbc.queryForObject("select version from store_version where id = 1", Long.class);
    }

    /** Every member of a team with a published team, at events of the format in [from, to). */
    public List<MemberRow> members(String format, Instant from, Instant to) {
        var args = new ArrayList<Object>(List.of(format, timestamp(to)));
        String since = from == null ? "" : " and e.event_date >= ?";
        if (from != null) args.add(timestamp(from));
        return jdbc.query("""
                select m.event_id, m.player, e.event_date, m.slot, m.species_key, m.mega_stone, m.item, m.ability, m.nature
                from team_member m join event e on e.id = m.event_id
                where upper(e.format) = upper(?) and e.event_date < ?""" + since,
                (rs, n) -> new MemberRow(rs.getString(1), rs.getString(2), instant(rs, 3), rs.getInt(4),
                        rs.getString(5), rs.getString(6), rs.getString(7), rs.getString(8), rs.getString(9)),
                args.toArray());
    }

    /** The moves of one species' members in [from, to), as "event|player|slot" and the move. */
    public List<String[]> moves(String format, String speciesKey, Instant from, Instant to) {
        var args = new ArrayList<Object>(List.of(format, speciesKey, timestamp(to)));
        String since = from == null ? "" : " and e.event_date >= ?";
        if (from != null) args.add(timestamp(from));
        return jdbc.query("""
                select mv.event_id, mv.player, mv.slot, mv.move
                from team_member_move mv
                join team_member m on m.event_id = mv.event_id and m.player = mv.player and m.slot = mv.slot
                join event e on e.id = mv.event_id
                where upper(e.format) = upper(?) and m.species_key = ? and e.event_date < ?""" + since,
                (rs, n) -> new String[] {rs.getString(1) + "|" + rs.getString(2) + "|" + rs.getInt(3), rs.getString(4)},
                args.toArray());
    }

    /**
     * Teams that made a top cut ("event|player"): who played in a bracket phase (phase > 1). Events
     * with a bracket are in bracketEvents.
     */
    public record TopCut(Set<String> teams, Set<String> bracketEvents) {}

    public TopCut topCut(String format, Instant from, Instant to) {
        var args = new ArrayList<Object>(List.of(format, timestamp(to)));
        String since = from == null ? "" : " and e.event_date >= ?";
        if (from != null) args.add(timestamp(from));
        Set<String> teams = new HashSet<>();
        Set<String> events = new HashSet<>();
        jdbc.query("""
                select p.event_id, p.player1, p.player2 from pairing p join event e on e.id = p.event_id
                where p.phase > 1 and upper(e.format) = upper(?) and e.event_date < ?""" + since,
                rs -> {
                    events.add(rs.getString(1));
                    if (rs.getString(2) != null) teams.add(rs.getString(1) + "|" + rs.getString(2));
                    if (rs.getString(3) != null) teams.add(rs.getString(1) + "|" + rs.getString(3));
                }, args.toArray());
        return new TopCut(teams, events);
    }

    private static Instant instant(ResultSet rs, int column) throws SQLException {
        var value = rs.getObject(column, OffsetDateTime.class);
        return value == null ? null : value.toInstant();
    }

    private static OffsetDateTime timestamp(Instant instant) {
        return OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
    }
}
