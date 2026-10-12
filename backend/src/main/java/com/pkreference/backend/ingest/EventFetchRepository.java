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

/**
 * The event_fetch table: what discovery has asked for, and when the fetcher got it. It's the
 * pipeline's memory between polls: without it every poll would ask for every listed event again.
 *
 * <p>{@code @Repository} marks a class that talks to the database. Besides making it a bean, Spring
 * turns the JDBC driver's exceptions into its own {@code DataAccessException} family here.
 * {@code NamedParameterJdbcTemplate} runs SQL with named placeholders ({@code :id}) filled from a
 * map, never by pasting values into the SQL text, so a value can't change the query (no SQL
 * injection).
 */
@Repository
public class EventFetchRepository {
    private final NamedParameterJdbcTemplate jdbc;

    /** Constructor injection: Spring supplies each parameter from the beans it has made. */
    public EventFetchRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * The fetch state of each of these events that has one, by event id. One query, with
     * {@code in (:ids)} expanded to the list.
     */
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

    /**
     * Records that discovery asked for the event at {@code at}: an update, or an insert the first
     * time. "Update, and insert if nothing was updated" is an upsert written portably, since H2
     * (the tests' database) and Postgres spell the one-statement form differently.
     */
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

    /** Records that the fetcher got the event at {@code at}, and whether its standings are final. */
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

    /** A {@code timestamp with time zone} column as an Instant, or null. */
    private static Instant instant(ResultSet rs, int column) throws SQLException {
        var value = rs.getObject(column, OffsetDateTime.class);
        return value == null ? null : value.toInstant();
    }

    /** An Instant as the type the JDBC drivers store in a {@code timestamp with time zone} column. */
    private static OffsetDateTime timestamp(Instant instant) {
        return instant == null ? null : OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
    }
}
