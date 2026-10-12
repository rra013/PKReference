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

    public LadderStoreConsumer(LadderStore store) {
        this.store = store;
    }

    @KafkaListener(topics = Topics.LADDER_STATS, groupId = "ladder-store")
    public void onStats(StatsFetched event) {
        store.put(event);
    }
}
