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
    public static final String POKEMON_USAGE = "pokemon.usage";

    private static final int PARTITIONS = 3;

    @Bean
    NewTopic tournamentsDiscovered() {
        return TopicBuilder.name(TOURNAMENTS_DISCOVERED).partitions(PARTITIONS).replicas(1).build();
    }

    @Bean
    NewTopic standingsFetched() {
        return TopicBuilder.name(STANDINGS_FETCHED).partitions(PARTITIONS).replicas(1).build();
    }

    @Bean
    NewTopic tournamentsDiscoveredDlt() {
        return TopicBuilder.name(TOURNAMENTS_DISCOVERED + ".DLT").partitions(PARTITIONS).replicas(1).build();
    }

    @Bean
    NewTopic standingsFetchedDlt() {
        return TopicBuilder.name(STANDINGS_FETCHED + ".DLT").partitions(PARTITIONS).replicas(1).build();
    }

    /** Latest usage row per key (format|species) survives compaction. */
    @Bean
    NewTopic pokemonUsage() {
        return TopicBuilder.name(POKEMON_USAGE).partitions(PARTITIONS).replicas(1)
                .config(TopicConfig.CLEANUP_POLICY_CONFIG, TopicConfig.CLEANUP_POLICY_COMPACT)
                .build();
    }
}
