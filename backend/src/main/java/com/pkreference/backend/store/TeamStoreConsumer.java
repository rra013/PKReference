package com.pkreference.backend.store;

import com.pkreference.backend.config.Topics;
import com.pkreference.backend.model.Events.PairingsFetched;
import com.pkreference.backend.model.Events.StandingsFetched;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

/**
 * standings.fetched and pairings.fetched -> the team store. Its own consumer groups: resetting them
 * to the start rebuilds the tables from the topics.
 *
 * <p>The same topics are also read by UsageConsumer, under a different {@code groupId}. That's the
 * point of consumer groups: each group gets every record and keeps its own place, so two
 * independent readers of one topic don't take records from each other.
 *
 * <p>This class is deliberately thin. The listener methods only hand the record to TeamStore, which
 * holds the logic and the transaction and can be tested without Kafka.
 */
@Component
public class TeamStoreConsumer {
    private final TeamStore store;

    /** Constructor injection: Spring supplies each parameter from the beans it has made. */
    public TeamStoreConsumer(TeamStore store) {
        this.store = store;
    }

    /**
     * One event's standings. If the store throws, the record is retried and then sent to
     * standings.fetched.DLT.
     */
    @KafkaListener(topics = Topics.STANDINGS_FETCHED, groupId = "team-store-standings")
    public void onStandings(StandingsFetched event) {
        store.putStandings(event);
    }

    /**
     * One event's matches. They can arrive before or after its standings: the tables don't depend
     * on the order.
     */
    @KafkaListener(topics = Topics.PAIRINGS_FETCHED, groupId = "team-store-pairings")
    public void onPairings(PairingsFetched event) {
        store.putPairings(event);
    }
}
