package com.pkreference.backend.usage;

import com.pkreference.backend.config.Topics;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.test.context.EmbeddedKafka;
import org.springframework.test.context.TestPropertySource;

import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

/** standings.fetched -> aggregator -> DB -> REST, against an in-JVM Kafka broker. */
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@EmbeddedKafka(partitions = 1, topics = {Topics.STANDINGS_FETCHED, Topics.POKEMON_USAGE})
@TestPropertySource(properties = {
        "spring.kafka.bootstrap-servers=${spring.embedded.kafka.brokers}",
        "spring.datasource.url=jdbc:h2:mem:it;DB_CLOSE_DELAY=-1",
        "pkref.limitless.ingest-enabled=false"})
class UsagePipelineTest {
    @Autowired KafkaTemplate<String, Object> kafka;
    @Autowired UsageCounterRepository counters;
    @Autowired TestRestTemplate rest;

    @Test
    void standingsEventEndsUpInTheUsageApi() {
        var event = Fixtures.tournament("it-1");
        kafka.send(Topics.STANDINGS_FETCHED, "it-1", event);
        kafka.send(Topics.STANDINGS_FETCHED, "it-1", event); // duplicate delivery

        await().atMost(Duration.ofSeconds(30)).untilAsserted(() ->
                assertThat(counters.findById("reg-m-a|SPECIES|incineroar|")).isPresent());
        // Give the duplicate time to be (not) applied.
        await().pollDelay(Duration.ofSeconds(2)).atMost(Duration.ofSeconds(10)).untilAsserted(() ->
                assertThat(counters.findById("reg-m-a|SPECIES|incineroar|").orElseThrow().getCount()).isEqualTo(4));

        var body = rest.getForObject("/api/usage?format=reg-m-a", String.class);
        assertThat(body).contains("incineroar").contains("100.0");
    }
}
