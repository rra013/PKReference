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
 *
 * <p>This and the classes beside it are the first version of the backend: all-time counts served at
 * /api/usage. The team store and MetaService replaced them for the app; they still run, and are the
 * simplest whole example here of consume, transact, produce.
 */
@Component
public class UsageConsumer {
    private static final Logger log = LoggerFactory.getLogger(UsageConsumer.class);

    private final UsageAggregationService service;
    private final KafkaTemplate<String, Object> kafka;

    /** Constructor injection: Spring supplies each parameter from the beans it has made. */
    public UsageConsumer(UsageAggregationService service, KafkaTemplate<String, Object> kafka) {
        this.service = service;
        this.kafka = kafka;
    }

    /**
     * Counts one event, then publishes each changed Pokémon's new total. Its own consumer group
     * ("usage-aggregator"), so it reads standings.fetched independently of the team store.
     */
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
