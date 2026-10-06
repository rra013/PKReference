package com.pkreference.backend.ingest;

import com.pkreference.backend.config.KafkaSends;
import com.pkreference.backend.config.LimitlessProperties;
import com.pkreference.backend.config.Topics;
import com.pkreference.backend.model.Events.PairingsFetched;
import com.pkreference.backend.model.Events.StandingsFetched;
import com.pkreference.backend.model.Events.TournamentDiscovered;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import java.time.Clock;

/**
 * tournaments.discovered -> the event's details, standings and pairings -> standings.fetched and
 * pairings.fetched. Three Limitless requests an event, through the throttle. A failure throws, so
 * the record retries and then goes to the DLT. Same consumer group as the standings fetcher it
 * replaces, so a running backend carries on where it was.
 */
@Component
public class EventFetcher {
    private static final Logger log = LoggerFactory.getLogger(EventFetcher.class);

    private final LimitlessClient client;
    private final EventFetchRepository fetches;
    private final KafkaTemplate<String, Object> kafka;
    private final LimitlessProperties props;
    private final Clock clock;

    public EventFetcher(LimitlessClient client, EventFetchRepository fetches, KafkaTemplate<String, Object> kafka,
                        LimitlessProperties props, Clock clock) {
        this.client = client;
        this.fetches = fetches;
        this.kafka = kafka;
        this.props = props;
        this.clock = clock;
    }

    @KafkaListener(topics = Topics.TOURNAMENTS_DISCOVERED, groupId = "standings-fetcher")
    public void onDiscovered(TournamentDiscovered event) {
        var t = event.tournament();
        var details = client.details(t.id());
        var standings = client.standings(t.id());
        var pairings = client.pairings(t.id());
        var fetchedAt = clock.instant();
        boolean standingsFinal = FetchPolicy.isFinal(t, fetchedAt, props.settleAfter());
        log.info("Fetched {} ({}): {} standings, {} pairings{}", t.id(), t.format(), standings.size(), pairings.size(),
                standingsFinal ? "" : ", not final yet");

        KafkaSends.await(kafka.send(Topics.STANDINGS_FETCHED, t.id(),
                new StandingsFetched(t, standings, details, fetchedAt, standingsFinal)));
        KafkaSends.await(kafka.send(Topics.PAIRINGS_FETCHED, t.id(), new PairingsFetched(t, pairings, fetchedAt)));
        fetches.markFetched(t, fetchedAt, standingsFinal);
    }
}
