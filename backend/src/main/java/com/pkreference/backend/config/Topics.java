package com.pkreference.backend.config;

import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.config.TopicConfig;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;

/**
 * The Kafka topics, declared in code. Each {@code @Bean} method below returns a {@code NewTopic};
 * at start-up Spring's {@code KafkaAdmin} asks the broker for each one and creates those that don't
 * exist. With {@code spring.kafka.admin.modify-topic-configs} on (application.yml), a setting
 * changed here also reaches a topic that already exists.
 *
 * <p>A topic is an append-only log of records, each a key and a value. The pipeline, in topic order:
 *
 * <ul>
 * <li>{@code tournaments.discovered}: "fetch this event". Written by EventDiscovery, read by
 *     EventFetcher. A work queue: its records are only instructions, so it isn't kept for ever.
 * <li>{@code standings.fetched} and {@code pairings.fetched}: what Limitless answered. Written by
 *     EventFetcher, read by TeamStoreConsumer and UsageConsumer. These are the system's record of
 *     the truth: kept for good, so any table can be rebuilt by reading them again.
 * <li>{@code pokemon.usage}: the old counters' latest row per Pokémon, written by UsageConsumer.
 * <li>{@code ladder.stats}: Smogon's monthly stats, reduced. Written by LadderDiscovery, read by
 *     LadderStoreConsumer.
 * <li>The {@code .DLT} topics ("dead letter topics"): where a record goes after its listener has
 *     failed on it four times (KafkaErrorHandling), so one bad record doesn't block the rest.
 * </ul>
 *
 * <p>Three words used below. <b>Partitions</b>: a topic is split into this many logs; records with the
 * same key always land in the same one, so they keep their order. <b>Replicas</b>: copies of each
 * partition on other brokers; 1 here, because there is one broker. <b>Compaction</b>: instead of
 * deleting old records by age, the broker keeps at least the newest record of every key, which
 * turns a topic into a table of "latest value by key" that can still be read from the start.
 */
@Configuration
public class Topics {
    /**
     * The topics' names, as constants: producers and {@code @KafkaListener}s refer to these, so a
     * name can't be misspelled in one place.
     */
    public static final String TOURNAMENTS_DISCOVERED = "tournaments.discovered";
    public static final String STANDINGS_FETCHED = "standings.fetched";
    public static final String PAIRINGS_FETCHED = "pairings.fetched";
    public static final String POKEMON_USAGE = "pokemon.usage";
    public static final String LADDER_STATS = "ladder.stats";

    /**
     * Three partitions a topic. More partitions than one lets several consumers of one group share
     * the work; with one consumer a listener, as here, it reads all three.
     */
    private static final int PARTITIONS = 3;

    /**
     * The largest record a fetched-data topic takes, as the producer's max.request.size. The
     * broker's default is about 1 MB, which a large event's standings (about 1.2 KB a player,
     * before compression) can pass.
     */
    static final String MAX_MESSAGE_BYTES = "5242880";

    /**
     * The work queue between discovery and the fetcher. Default settings: records are deleted after
     * the broker's retention time (7 days), which is fine for instructions that are acted on in
     * minutes.
     */
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

    /**
     * Where a "fetch this event" record goes when the fetcher keeps failing on it (Limitless down,
     * say). Discovery asks for the event again later, so nothing has to read this topic; it's there
     * to be looked at.
     */
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

    /** Takes the same records as pairings.fetched, with the failure in their headers. */
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

    /**
     * Smogon's monthly ladder stats, reduced (Ladder.Stats, about 1 MB at most), kept for good: the
     * latest per format, month and rating. Smogon's own files, up to 7 MB, aren't kept; Smogon
     * keeps every month.
     */
    @Bean
    NewTopic ladderStats() {
        return TopicBuilder.name(LADDER_STATS).partitions(PARTITIONS).replicas(1)
                .config(TopicConfig.CLEANUP_POLICY_CONFIG, TopicConfig.CLEANUP_POLICY_COMPACT)
                .config(TopicConfig.RETENTION_MS_CONFIG, "-1")
                .config(TopicConfig.MAX_MESSAGE_BYTES_CONFIG, MAX_MESSAGE_BYTES)
                .build();
    }

    /** Takes the same records as ladder.stats, with the failure in their headers. */
    @Bean
    NewTopic ladderStatsDlt() {
        return TopicBuilder.name(LADDER_STATS + ".DLT").partitions(PARTITIONS).replicas(1)
                .config(TopicConfig.MAX_MESSAGE_BYTES_CONFIG, MAX_MESSAGE_BYTES)
                .build();
    }

    /**
     * Latest usage row per key (format|species) survives compaction, and a compacted topic doesn't
     * delete by age. The counters themselves are in Postgres; this topic is a feed of their
     * changes, for anything that wants to follow them.
     */
    @Bean
    NewTopic pokemonUsage() {
        return TopicBuilder.name(POKEMON_USAGE).partitions(PARTITIONS).replicas(1)
                .config(TopicConfig.CLEANUP_POLICY_CONFIG, TopicConfig.CLEANUP_POLICY_COMPACT)
                .build();
    }
}
