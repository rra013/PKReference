package com.pkreference.backend.usage;

import com.pkreference.backend.config.Topics;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.common.config.ConfigResource;
import org.apache.kafka.common.config.TopicConfig;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.kafka.core.KafkaAdmin;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.test.context.EmbeddedKafka;
import org.springframework.test.context.TestPropertySource;

import java.time.Duration;
import java.util.List;

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
    @Autowired KafkaAdmin kafkaAdmin;

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

    /**
     * The embedded broker made standings.fetched with the defaults, as the local broker has it
     * from before; starting the app gives it Topics.java's settings.
     */
    @Test
    void standingsAreKeptForGood() throws Exception {
        var topic = new ConfigResource(ConfigResource.Type.TOPIC, Topics.STANDINGS_FETCHED);
        try (var admin = AdminClient.create(kafkaAdmin.getConfigurationProperties())) {
            var config = admin.describeConfigs(List.of(topic)).all().get().get(topic);
            assertThat(config.get(TopicConfig.CLEANUP_POLICY_CONFIG).value()).isEqualTo("compact");
            assertThat(config.get(TopicConfig.RETENTION_MS_CONFIG).value()).isEqualTo("-1");
            assertThat(config.get(TopicConfig.MAX_MESSAGE_BYTES_CONFIG).value()).isEqualTo("5242880");
        }
    }

    /** springdoc's OpenAPI document (Swagger UI's source) has /v1 and its descriptions. */
    @Test
    void theApiIsDocumented() {
        var docs = rest.getForObject("/v3/api-docs", String.class);
        assertThat(docs).contains("/v1/formats/{format}/archetypes").contains("Archetypes and their matchups")
                .contains("Mirror matches");
        assertThat(rest.getForEntity("/swagger-ui.html", String.class).getStatusCode().is2xxSuccessful()
                || rest.getForEntity("/swagger-ui/index.html", String.class).getStatusCode().is2xxSuccessful()).isTrue();
    }
}
