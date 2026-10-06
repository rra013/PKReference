package com.pkreference.backend.config;

import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.config.TopicConfig;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;

@Configuration
public class Topics {
    public static final String TOURNAMENTS_DISCOVERED = "tournaments.discovered";
    public static final String STANDINGS_FETCHED = "standings.fetched";
    public static final String PAIRINGS_FETCHED = "pairings.fetched";
    public static final String POKEMON_USAGE = "pokemon.usage";

    private static final int PARTITIONS = 3;

    /**
     * The largest record a fetched-data topic takes, as the producer's max.request.size. The
     * broker's default is about 1 MB, which a large event's standings (about 1.2 KB a player,
     * before compression) can pass.
     */
    static final String MAX_MESSAGE_BYTES = "5242880";

    @Bean
    NewTopic tournamentsDiscovered() {
        return TopicBuilder.name(TOURNAMENTS_DISCOVERED).partitions(PARTITIONS).replicas(1).build();
    }

    /**
     * The record of every event fetched, kept for good: compacted to the latest standings per
     * tournament id and never deleted, so any count can be rebuilt by reading it again.
     */
    @Bean
    NewTopic standingsFetched() {
        return TopicBuilder.name(STANDINGS_FETCHED).partitions(PARTITIONS).replicas(1)
                .config(TopicConfig.CLEANUP_POLICY_CONFIG, TopicConfig.CLEANUP_POLICY_COMPACT)
                .config(TopicConfig.RETENTION_MS_CONFIG, "-1")
                .config(TopicConfig.MAX_MESSAGE_BYTES_CONFIG, MAX_MESSAGE_BYTES)
                .build();
    }

    @Bean
    NewTopic tournamentsDiscoveredDlt() {
        return TopicBuilder.name(TOURNAMENTS_DISCOVERED + ".DLT").partitions(PARTITIONS).replicas(1).build();
    }

    /** Every event's matches, kept for good as standings.fetched is. */
    @Bean
    NewTopic pairingsFetched() {
        return TopicBuilder.name(PAIRINGS_FETCHED).partitions(PARTITIONS).replicas(1)
                .config(TopicConfig.CLEANUP_POLICY_CONFIG, TopicConfig.CLEANUP_POLICY_COMPACT)
                .config(TopicConfig.RETENTION_MS_CONFIG, "-1")
                .config(TopicConfig.MAX_MESSAGE_BYTES_CONFIG, MAX_MESSAGE_BYTES)
                .build();
    }

    @Bean
    NewTopic pairingsFetchedDlt() {
        return TopicBuilder.name(PAIRINGS_FETCHED + ".DLT").partitions(PARTITIONS).replicas(1)
                .config(TopicConfig.MAX_MESSAGE_BYTES_CONFIG, MAX_MESSAGE_BYTES)
                .build();
    }

    /** Takes the same records as standings.fetched, with the failure in their headers. */
    @Bean
    NewTopic standingsFetchedDlt() {
        return TopicBuilder.name(STANDINGS_FETCHED + ".DLT").partitions(PARTITIONS).replicas(1)
                .config(TopicConfig.MAX_MESSAGE_BYTES_CONFIG, MAX_MESSAGE_BYTES)
                .build();
    }

    /** Latest usage row per key (format|species) survives compaction. */
    @Bean
    NewTopic pokemonUsage() {
        return TopicBuilder.name(POKEMON_USAGE).partitions(PARTITIONS).replicas(1)
                .config(TopicConfig.CLEANUP_POLICY_CONFIG, TopicConfig.CLEANUP_POLICY_COMPACT)
                .build();
    }
}
