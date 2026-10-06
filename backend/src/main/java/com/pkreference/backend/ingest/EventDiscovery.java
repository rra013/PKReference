package com.pkreference.backend.ingest;

import com.pkreference.backend.config.KafkaSends;
import com.pkreference.backend.config.LimitlessProperties;
import com.pkreference.backend.config.Topics;
import com.pkreference.backend.model.Events.Tournament;
import com.pkreference.backend.model.Events.TournamentDiscovered;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Walks each format's tournament list back through the lookback and asks for the events to fetch
 * (FetchPolicy) on tournaments.discovered. A long lookback, set once, is the backfill.
 */
@Component
@ConditionalOnProperty(name = "pkref.limitless.ingest-enabled", havingValue = "true", matchIfMissing = true)
public class EventDiscovery {
    private static final Logger log = LoggerFactory.getLogger(EventDiscovery.class);

    private final LimitlessClient client;
    private final EventFetchRepository fetches;
    private final KafkaTemplate<String, Object> kafka;
    private final LimitlessProperties props;
    private final Clock clock;

    public EventDiscovery(LimitlessClient client, EventFetchRepository fetches, KafkaTemplate<String, Object> kafka,
                          LimitlessProperties props, Clock clock) {
        this.client = client;
        this.fetches = fetches;
        this.kafka = kafka;
        this.props = props;
        this.clock = clock;
    }

    @Scheduled(initialDelayString = "${pkref.limitless.initial-delay:5s}",
               fixedDelayString = "${pkref.limitless.poll-interval:30m}")
    public void poll() {
        // No formats: every format of the game, in one list.
        List<String> formats = props.formats().isEmpty() ? Arrays.asList((String) null) : props.formats();
        for (String format : formats) {
            discover(format);
        }
    }

    /** The events asked for, newest first. */
    List<String> discover(String format) {
        Instant now = clock.instant();
        Instant horizon = now.minus(props.lookback());
        List<String> requested = new ArrayList<>();
        int listed = 0;
        int page = 1;
        for (; page <= props.maxPages(); page++) {
            List<Tournament> list;
            try {
                list = client.tournaments(format, page);
            } catch (RuntimeException e) {
                log.error("Could not list Limitless tournaments ({}, page {})", label(format), page, e);
                break;
            }
            if (list == null || list.isEmpty()) break;
            listed += list.size();
            var states = fetches.find(list.stream().map(Tournament::id).toList());
            for (Tournament t : list) {
                if (!FetchPolicy.shouldRequest(t, states.get(t.id()), now, props)) continue;
                try {
                    KafkaSends.await(kafka.send(Topics.TOURNAMENTS_DISCOVERED, t.id(), new TournamentDiscovered(t)));
                    fetches.markRequested(t, now);
                    requested.add(t.id());
                } catch (RuntimeException e) {
                    // Not marked, so the next poll asks again.
                    log.error("Could not queue tournament {}", t.id(), e);
                }
            }
            // Newest first: once a whole page started before the horizon, the rest did too.
            boolean pastHorizon = list.stream().allMatch(t -> {
                Instant start = FetchPolicy.startOf(t);
                return start != null && start.isBefore(horizon);
            });
            if (pastHorizon || list.size() < props.pageSize()) break;
        }
        if (page > props.maxPages()) {
            log.warn("Discovery ({}) stopped at maxPages ({}) before the lookback ended", label(format), props.maxPages());
        }
        log.info("Discovery ({}): {} tournaments listed, {} asked for", label(format), listed, requested.size());
        return requested;
    }

    private static String label(String format) {
        return format == null ? "all formats" : format;
    }
}
