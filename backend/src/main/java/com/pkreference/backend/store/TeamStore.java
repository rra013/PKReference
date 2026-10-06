package com.pkreference.backend.store;

import com.pkreference.backend.model.Events.Pairing;
import com.pkreference.backend.model.Events.PairingsFetched;
import com.pkreference.backend.model.Events.Standing;
import com.pkreference.backend.model.Events.StandingsFetched;
import com.pkreference.backend.model.Events.TeamMember;
import com.pkreference.backend.model.Events.TournamentDetails;
import com.pkreference.backend.standardize.SpeciesVocabularies;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Every event's teams and matches, as fetched: the tables Phase 2's insights read. Each member
 * gets its species key the app's way (SpeciesVocabularies). Each fetch of
 * an event replaces its rows, so reading the topics again from the start rebuilds them, and a
 * fetch older than the one stored is ignored.
 */
@Repository
public class TeamStore {
    private final JdbcTemplate jdbc;
    private final SpeciesVocabularies species;

    public TeamStore(JdbcTemplate jdbc, SpeciesVocabularies species) {
        this.jdbc = jdbc;
        this.species = species;
    }

    @Transactional
    public void putStandings(StandingsFetched fetched) {
        var t = fetched.tournament();
        if (isStale(fetched.fetchedAt(), "select fetched_at from event where id = ?", t.id())) return;

        // Cascades to its phases, teams, members and moves.
        jdbc.update("delete from event where id = ?", t.id());
        bumpVersion();
        TournamentDetails d = fetched.details();
        jdbc.update("""
                insert into event (id, game, format, name, event_date, players, organizer, platform, online,
                                   decklists, fetched_at, standings_final)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                t.id(), cut(t.game(), 32), cut(t.format() == null || t.format().isBlank() ? "unknown" : t.format(), 32),
                cut(t.name(), 512), timestamp(parseDate(t.date())), t.players(),
                d == null || d.organizer() == null ? null : cut(d.organizer().name(), 255),
                d == null ? null : cut(d.platform(), 32), d == null ? null : d.isOnline(),
                d == null ? null : d.decklists(), timestamp(fetched.fetchedAt()), fetched.isFinal());

        if (d != null && d.phases() != null) {
            jdbc.batchUpdate("insert into event_phase (event_id, phase, type, rounds, mode) values (?, ?, ?, ?, ?)",
                    d.phases().stream().map(ph -> new Object[] {
                            t.id(), ph.phase(), cut(ph.type(), 32), ph.rounds(), cut(ph.mode(), 16)}).toList());
        }

        List<Object[]> teams = new ArrayList<>();
        List<Object[]> members = new ArrayList<>();
        List<Object[]> moves = new ArrayList<>();
        Set<String> players = new HashSet<>();
        for (Standing s : fetched.standings() == null ? List.<Standing>of() : fetched.standings()) {
            // Usernames are unique in an event; keep the first if Limitless ever repeats one.
            if (s.player() == null || !players.add(s.player())) continue;
            var r = s.record();
            teams.add(new Object[] {t.id(), cut(s.player(), 255), cut(s.name(), 255), cut(s.country(), 8), s.placing(),
                    r == null ? null : r.wins(), r == null ? null : r.losses(), r == null ? null : r.ties(), s.drop()});
            List<TeamMember> list = s.decklist() == null ? List.of() : s.decklist();
            for (int slot = 0; slot < list.size(); slot++) {
                TeamMember m = list.get(slot);
                var key = species.identify(t.format(), m.name(), m.limitlessId(), m.item());
                members.add(new Object[] {t.id(), cut(s.player(), 255), slot, cut(m.name(), 255),
                        cut(m.limitlessId(), 255), cut(m.item(), 255), cut(m.ability(), 255), cut(m.nature(), 64),
                        cut(m.tera(), 64), cut(key.key(), 255), cut(key.megaStone(), 64)});
                List<String> attacks = m.attacks() == null ? List.of() : m.attacks();
                for (int i = 0; i < attacks.size(); i++) {
                    if (attacks.get(i) == null || attacks.get(i).isBlank()) continue;
                    moves.add(new Object[] {t.id(), cut(s.player(), 255), slot, i, cut(attacks.get(i), 255)});
                }
            }
        }
        jdbc.batchUpdate("""
                insert into team (event_id, player, name, country, placement, wins, losses, ties, dropped)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?)""", teams);
        jdbc.batchUpdate("""
                insert into team_member (event_id, player, slot, name, limitless_id, item, ability, nature, tera,
                                         species_key, mega_stone)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", members);
        jdbc.batchUpdate("insert into team_member_move (event_id, player, slot, move_slot, move) values (?, ?, ?, ?, ?)",
                moves);
    }

    @Transactional
    public void putPairings(PairingsFetched fetched) {
        String id = fetched.tournament().id();
        if (isStale(fetched.fetchedAt(), "select fetched_at from pairing_fetch where event_id = ?", id)) return;

        jdbc.update("delete from pairing where event_id = ?", id);
        bumpVersion();
        jdbc.update("delete from pairing_fetch where event_id = ?", id);
        jdbc.update("insert into pairing_fetch (event_id, fetched_at) values (?, ?)", id, timestamp(fetched.fetchedAt()));
        List<Pairing> pairings = fetched.pairings() == null ? List.of() : fetched.pairings();
        List<Object[]> rows = new ArrayList<>();
        for (int i = 0; i < pairings.size(); i++) {
            Pairing p = pairings.get(i);
            rows.add(new Object[] {id, i, p.round(), p.phase(), p.table(), cut(p.match(), 32), cut(p.player1(), 255),
                    cut(p.player2(), 255), cut(p.winner(), 255), PairingResult.of(p).name()});
        }
        jdbc.batchUpdate("""
                insert into pairing (event_id, ordinal, round, phase, table_no, label, player1, player2, winner, result)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", rows);
    }

    /** Committed with the write, so readers see a new version exactly when they see new rows. */
    private void bumpVersion() {
        jdbc.update("update store_version set version = version + 1 where id = 1");
    }

    /** Whether a fetch is older than the one already stored. Records from before fetchedAt existed never are. */
    private boolean isStale(Instant fetchedAt, String storedQuery, String id) {
        if (fetchedAt == null) return false;
        var stored = jdbc.query(storedQuery, (rs, n) -> rs.getObject(1, OffsetDateTime.class), id);
        return !stored.isEmpty() && stored.get(0) != null && stored.get(0).toInstant().isAfter(fetchedAt);
    }

    static Instant parseDate(String date) {
        if (date == null || date.isBlank()) return null;
        try {
            return Instant.parse(date);
        } catch (DateTimeParseException e) {
            return null;
        }
    }

    private static OffsetDateTime timestamp(Instant instant) {
        return instant == null ? null : OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
    }

    /** Hand-typed fields are trimmed to their column, rather than failing the whole event. */
    private static String cut(String s, int max) {
        return s == null || s.length() <= max ? s : s.substring(0, max);
    }
}
