package com.pkreference.backend.ladder;

import com.pkreference.backend.config.Topics;
import com.pkreference.backend.model.Ladder.StatsFetched;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

/**
 * ladder.stats -> the ladder_stats table. Its own consumer group: resetting it to the start
 * rebuilds the table from the topic.
 */
@Component
public class LadderStoreConsumer {
    private final LadderStore store;

    /** Constructor injection: Spring supplies each parameter from the beans it has made. */
    public LadderStoreConsumer(LadderStore store) {
        this.store = store;
    }

    /**
     * Called for each record on ladder.stats, already turned from JSON back into a
     * {@code StatsFetched}. The store decides whether it's newer than what it has.
     */
    @KafkaListener(topics = Topics.LADDER_STATS, groupId = "ladder-store")
    public void onStats(StatsFetched event) {
        store.put(event);
    }
}
