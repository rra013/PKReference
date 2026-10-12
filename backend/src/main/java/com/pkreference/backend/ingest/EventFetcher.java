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
 *
 * <p>This is the pipeline's slow worker. Under the throttle a request can wait minutes for its turn,
 * which is why application.yml gives consumers few records a poll and a long
 * {@code max.poll.interval.ms}: a consumer that goes too long between polls is assumed dead, and
 * its records are handed out again.
 */
@Component
public class EventFetcher {
    private static final Logger log = LoggerFactory.getLogger(EventFetcher.class);

    private final LimitlessClient client;
    private final EventFetchRepository fetches;
    private final KafkaTemplate<String, Object> kafka;
    private final LimitlessProperties props;
    private final Clock clock;

    /** Constructor injection: Spring supplies each parameter from the beans it has made. */
    public EventFetcher(LimitlessClient client, EventFetchRepository fetches, KafkaTemplate<String, Object> kafka,
                        LimitlessProperties props, Clock clock) {
        this.client = client;
        this.fetches = fetches;
        this.kafka = kafka;
        this.props = props;
        this.clock = clock;
    }

    /**
     * Called by Spring Kafka for each record on tournaments.discovered. {@code @KafkaListener}
     * makes Spring start a consumer thread that polls the topic, turns each record's JSON back into
     * a {@code TournamentDiscovered} and calls this method with it.
     *
     * <p>{@code groupId} names the consumer group. Kafka remembers, per group, how far each partition
     * has been read (the "offset"), so after a restart this listener resumes where it stopped. The
     * offset moves on only when this method returns normally: if it throws, the record is retried
     * (KafkaErrorHandling).
     *
     * <p>The order matters: publish both results, waiting for the broker to confirm each, and only
     * then mark the event fetched. If anything fails part-way, nothing is marked, and the retry
     * does the whole event again; the stores downstream accept a repeat.
     */
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
