package com.pkreference.backend.store;

import com.pkreference.backend.config.Topics;
import com.pkreference.backend.model.Events.PairingsFetched;
import com.pkreference.backend.model.Events.StandingsFetched;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

/**
 * standings.fetched and pairings.fetched -> the team store. Its own consumer groups: resetting
 * them to the start rebuilds the tables from the topics.
 */
@Component
public class TeamStoreConsumer {
    private final TeamStore store;

    public TeamStoreConsumer(TeamStore store) {
        this.store = store;
    }

    @KafkaListener(topics = Topics.STANDINGS_FETCHED, groupId = "team-store-standings")
    public void onStandings(StandingsFetched event) {
        store.putStandings(event);
    }

    @KafkaListener(topics = Topics.PAIRINGS_FETCHED, groupId = "team-store-pairings")
    public void onPairings(PairingsFetched event) {
        store.putPairings(event);
    }
}
