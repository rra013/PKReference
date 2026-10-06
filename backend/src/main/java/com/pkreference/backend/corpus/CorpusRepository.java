package com.pkreference.backend.corpus;

import com.pkreference.backend.model.Events.Standing;
import com.pkreference.backend.model.Events.TeamMember;
import com.pkreference.backend.model.Events.Tournament;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * The team store read back in Limitless's own shapes (Events.Tournament and Events.Standing), so the
 * app's Team Search corpus can be built from the server with the code that builds it from Limitless.
 */
@Repository
public class CorpusRepository {
    /** Limitless's date format: "2026-10-05T18:00:00.000Z". */
    static final DateTimeFormatter LIMITLESS_DATE = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");

    private final JdbcTemplate jdbc;

    public CorpusRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** One page (from 1) of the format's events, newest first, as Limitless lists them. */
    public List<Tournament> tournaments(String format, int page, int limit) {
        return jdbc.query("""
                select id, name, game, format, event_date, players from event
                where upper(format) = upper(?) and event_date is not null
                order by event_date desc, id
                limit ? offset ?""",
                (rs, n) -> new Tournament(rs.getString(1), orEmpty(rs.getString(2)), orEmpty(rs.getString(3)),
                        rs.getString(4), LIMITLESS_DATE.format(rs.getObject(5, OffsetDateTime.class)
                                .withOffsetSameInstant(ZoneOffset.UTC)), rs.getInt(6)),
                format, limit, (page - 1) * limit);
    }

    /** The event's standings with their teams, or null when the event isn't stored. */
    public List<Standing> standings(String eventId) {
        Integer events = jdbc.queryForObject("select count(*) from event where id = ?", Integer.class, eventId);
        if (events == null || events == 0) return null;

        Map<String, List<String>> moves = new HashMap<>();
        jdbc.query("select player, slot, move from team_member_move where event_id = ? order by player, slot, move_slot",
                rs -> {
                    moves.computeIfAbsent(rs.getString(1) + "|" + rs.getInt(2), k -> new ArrayList<>()).add(rs.getString(3));
                }, eventId);
        Map<String, List<TeamMember>> members = new LinkedHashMap<>();
        jdbc.query("""
                select player, slot, name, limitless_id, item, ability, nature, tera from team_member
                where event_id = ? order by player, slot""",
                rs -> {
                    String player = rs.getString(1);
                    members.computeIfAbsent(player, k -> new ArrayList<>()).add(new TeamMember(rs.getString(3),
                            rs.getString(4), rs.getString(5), rs.getString(6),
                            moves.getOrDefault(player + "|" + rs.getInt(2), List.of()), rs.getString(7), rs.getString(8)));
                }, eventId);
        // Limitless lists unranked (dropped) players first, then by placing; the app sorts either way.
        return jdbc.query("""
                select player, name, country, placement, wins, losses, ties, dropped from team where event_id = ?
                order by case when placement is null then 0 else 1 end, placement, player""",
                (rs, n) -> {
                    String player = rs.getString(1);
                    Integer wins = (Integer) rs.getObject(5);
                    Integer losses = (Integer) rs.getObject(6);
                    Integer ties = (Integer) rs.getObject(7);
                    var record = wins == null || losses == null || ties == null ? null
                            : new Standing.Record(wins, losses, ties);
                    return new Standing(player, rs.getString(2), rs.getString(3), (Integer) rs.getObject(4), record,
                            null, members.get(player), (Integer) rs.getObject(8));
                }, eventId);
    }

    private static String orEmpty(String s) {
        return s == null ? "" : s;
    }
}
