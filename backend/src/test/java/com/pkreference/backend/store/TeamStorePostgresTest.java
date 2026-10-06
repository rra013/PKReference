package com.pkreference.backend.store;

import com.pkreference.backend.ingest.EventFetchRepository;
import com.pkreference.backend.model.Events.Tournament;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.jdbc.JdbcTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Import;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** The store's tests, and the fetch table's, on Postgres 17 as docker-compose.yml runs it. Skipped without Docker. */
@JdbcTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers(disabledWithoutDocker = true)
@Import({TeamStore.class, EventFetchRepository.class})
class TeamStorePostgresTest extends TeamStoreTestBase {
    @Container
    @ServiceConnection
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:17-alpine");

    @Autowired EventFetchRepository fetches;

    @Test
    void tracksFetches() {
        var t = new Tournament("e1", "Event", "VGC", "M-C", "2026-10-05T18:00:00.000Z", 40);
        var asked = Instant.parse("2026-10-06T00:00:00Z");
        fetches.markRequested(t, asked);
        fetches.markRequested(t, asked.plusSeconds(60));
        fetches.markFetched(t, asked.plusSeconds(120), true);
        var found = fetches.find(List.of("e1", "e2"));
        assertThat(found).containsOnlyKeys("e1");
        assertThat(found.get("e1").requestedAt()).isEqualTo(asked.plusSeconds(60));
        assertThat(found.get("e1").fetchedAt()).isEqualTo(asked.plusSeconds(120));
        assertThat(found.get("e1").standingsFinal()).isTrue();
    }
}
