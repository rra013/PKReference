package com.pkreference.backend.usage;

import com.pkreference.backend.config.KafkaSends;
import com.pkreference.backend.config.Topics;
import com.pkreference.backend.model.Events.StandingsFetched;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

/**
 * standings.fetched -> counters -> pokemon.usage. Runs single-threaded (default concurrency 1)
 * because counters are shared across tournaments of one format.
 */
@Component
public class UsageConsumer {
    private static final Logger log = LoggerFactory.getLogger(UsageConsumer.class);

    private final UsageAggregationService service;
    private final KafkaTemplate<String, Object> kafka;

    public UsageConsumer(UsageAggregationService service, KafkaTemplate<String, Object> kafka) {
        this.service = service;
        this.kafka = kafka;
    }

    @KafkaListener(topics = Topics.STANDINGS_FETCHED, groupId = "usage-aggregator")
    public void onStandings(StandingsFetched event) {
        // Transaction commits when apply() returns; publish only after that.
        for (var update : service.apply(event)) {
            try {
                KafkaSends.await(kafka.send(Topics.POKEMON_USAGE, update.format() + "|" + update.species(), update));
            } catch (RuntimeException e) {
                // The counters are committed, so a retry would apply nothing; the species'
                // next update replaces this one on the compacted topic.
                log.warn("Could not publish usage for {} in {}", update.species(), update.format(), e);
            }
        }
    }
}
