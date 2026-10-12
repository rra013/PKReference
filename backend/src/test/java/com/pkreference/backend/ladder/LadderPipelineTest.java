package com.pkreference.backend.ladder;

import com.pkreference.backend.config.SmogonProperties;
import com.pkreference.backend.config.Topics;
import com.pkreference.backend.model.Ladder.Stats;
import com.pkreference.backend.standardize.SpeciesVocabularies;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.test.context.EmbeddedKafka;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.time.Clock;
import java.time.Duration;
import java.util.List;

import static com.pkreference.backend.ladder.LadderFixtures.FORMAT_ID;
import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.when;

/**
 * Discovery (Smogon mocked with the fixture) -> ladder.stats -> the ladder store -> what /v1/ladder
 * serves, on an in-JVM broker: the record comes through the topic whole.
 */
@SpringBootTest
@EmbeddedKafka(partitions = 1, topics = Topics.LADDER_STATS)
@TestPropertySource(properties = {
        "spring.kafka.bootstrap-servers=${spring.embedded.kafka.brokers}",
        "spring.datasource.url=jdbc:h2:mem:ladder;DB_CLOSE_DELAY=-1",
        "pkref.limitless.ingest-enabled=false"})
class LadderPipelineTest {
    @MockitoBean SmogonClient smogon;
    @Autowired LadderReducer reducer;
    @Autowired LadderStore store;
    @Autowired LadderService service;
    @Autowired SpeciesVocabularies vocabularies;
    @Autowired KafkaTemplate<String, Object> kafka;
    @Autowired ObjectProvider<LadderDiscovery> scheduled;

    @Test
    @SuppressWarnings("unchecked")
    void aMonthIsFetchedReducedAndServed() {
        when(smogon.months()).thenReturn(List.of("2026-09"));
        when(smogon.chaosFiles("2026-09")).thenReturn(List.of(LadderFixtures.FILE, FORMAT_ID + "-0.json"));
        when(smogon.leads(anyString(), anyString())).thenReturn(LadderFixtures.leads());
        doAnswer(call -> {
            try (var in = LadderFixtures.chaos()) {
                return ((SmogonClient.BodyReader<Stats>) call.getArgument(2)).read(in);
            }
        }).when(smogon).chaos(anyString(), anyString(), any());

        // Tests never poll Smogon by themselves (config/application.yml), so this one is made here.
        assertThat(scheduled.getIfAvailable()).isNull();
        var discovery = new LadderDiscovery(smogon, reducer, store, vocabularies, kafka, SmogonProperties.defaults(),
                Clock.systemUTC());
        assertThat(discovery.discover()).containsExactly(FORMAT_ID + "|2026-09|1760", FORMAT_ID + "|2026-09|0");

        await().atMost(Duration.ofSeconds(30)).untilAsserted(() ->
                assertThat(service.index().stats()).extracting(e -> e.rating()).containsExactly(0, 1760));
        var served = service.stats(FORMAT_ID, null, null);
        assertThat(served.month()).isEqualTo("2026-09");
        assertThat(served.ratings()).containsExactly(0, 1760);
        assertThat(served.previousMonth()).isNull();
        // Through the topic and the table, the record is the reducer's, number for number.
        Stats reduced = LadderFixtures.stats();
        assertThat(served.pokemon()).hasSize(27);
        for (int i = 0; i < reduced.pokemon().size(); i++) {
            var expected = reduced.pokemon().get(i);
            var actual = served.pokemon().get(i);
            assertThat(actual.name()).isEqualTo(expected.name());
            assertThat(actual.key()).isEqualTo(expected.key());
            assertThat(actual.megaStone()).isEqualTo(expected.megaStone());
            assertThat(actual.usage()).isEqualTo(expected.usage());
            assertThat(actual.leadShare()).isEqualTo(expected.leadShare());
            assertThat(actual.abilities()).isEqualTo(expected.abilities());
            assertThat(actual.items()).isEqualTo(expected.items());
            assertThat(actual.moves()).isEqualTo(expected.moves());
            assertThat(actual.natures()).isEqualTo(expected.natures());
            assertThat(actual.spreads()).isEqualTo(expected.spreads());
            assertThat(actual.teammates()).isEqualTo(expected.teammates());
        }

        // Stored now, so the next poll has nothing to fetch.
        assertThat(discovery.discover()).isEmpty();
    }
}
