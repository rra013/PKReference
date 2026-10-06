package com.pkreference.backend.ingest;

import com.pkreference.backend.ingest.FetchPolicy.EventFetch;
import com.pkreference.backend.model.Events.Tournament;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;

/** The event_fetch table: what discovery has asked for, and when the fetcher got it. */
@Repository
public class EventFetchRepository {
    private final NamedParameterJdbcTemplate jdbc;

    public EventFetchRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Map<String, EventFetch> find(Collection<String> ids) {
        Map<String, EventFetch> found = new HashMap<>();
        if (ids.isEmpty()) return found;
        jdbc.query("select event_id, requested_at, fetched_at, standings_final from event_fetch where event_id in (:ids)",
                new MapSqlParameterSource("ids", ids), rs -> {
                    found.put(rs.getString(1), new EventFetch(rs.getString(1), instant(rs, 2), instant(rs, 3),
                            rs.getBoolean(4)));
                });
        return found;
    }

    public void markRequested(Tournament t, Instant at) {
        var params = new MapSqlParameterSource("id", t.id()).addValue("at", timestamp(at))
                .addValue("format", t.format()).addValue("date", timestamp(FetchPolicy.startOf(t)));
        int updated = jdbc.update("update event_fetch set requested_at = :at where event_id = :id", params);
        if (updated == 0) {
            jdbc.update("""
                    insert into event_fetch (event_id, format, event_date, requested_at, standings_final)
                    values (:id, :format, :date, :at, false)""", params);
        }
    }

    public void markFetched(Tournament t, Instant at, boolean standingsFinal) {
        var params = new MapSqlParameterSource("id", t.id()).addValue("at", timestamp(at))
                .addValue("final", standingsFinal).addValue("format", t.format())
                .addValue("date", timestamp(FetchPolicy.startOf(t)));
        int updated = jdbc.update("update event_fetch set fetched_at = :at, standings_final = :final where event_id = :id",
                params);
        if (updated == 0) {
            // Fetched without discovery asking (a record sent by hand, or one from before Phase 1).
            jdbc.update("""
                    insert into event_fetch (event_id, format, event_date, requested_at, fetched_at, standings_final)
                    values (:id, :format, :date, :at, :at, :final)""", params);
        }
    }

    private static Instant instant(ResultSet rs, int column) throws SQLException {
        var value = rs.getObject(column, OffsetDateTime.class);
        return value == null ? null : value.toInstant();
    }

    private static OffsetDateTime timestamp(Instant instant) {
        return instant == null ? null : OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
    }
}
