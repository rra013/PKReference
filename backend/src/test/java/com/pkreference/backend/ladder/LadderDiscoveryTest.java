package com.pkreference.backend.ladder;

import com.pkreference.backend.config.SmogonProperties;
import com.pkreference.backend.model.Ladder.Stats;
import com.pkreference.backend.model.Ladder.StatsFetched;
import com.pkreference.backend.standardize.SpeciesVocabularies;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.JdbcTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.kafka.core.KafkaTemplate;

import org.springframework.web.client.ResourceAccessException;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.time.Clock;
import java.time.ZoneOffset;
import java.util.List;
import java.util.concurrent.CompletableFuture;

import static com.pkreference.backend.ladder.LadderFixtures.FORMAT_ID;
import static com.pkreference.backend.ladder.LadderTestConfig.FETCHED;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeast;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Discovery against a canned Smogon, with the ladder_stats table on the real migrations: what it
 * fetches, what it leaves, and that a file is fetched once.
 */
@JdbcTest
@Import({LadderStore.class, LadderTestConfig.class})
class LadderDiscoveryTest {
    private static final String BSS = "gen9championsbssregmc";

    @Autowired LadderStore store;
    @Autowired JdbcTemplate jdbc;

    private final SmogonClient client = mock(SmogonClient.class);
    @SuppressWarnings("unchecked")
    private final KafkaTemplate<String, Object> kafka = mock(KafkaTemplate.class);
    private final LadderReducer reducer = LadderFixtures.reducer();
    private LadderDiscovery discovery;

    private LadderDiscovery discovery(SmogonProperties props) {
        return new LadderDiscovery(client, reducer, store, new SpeciesVocabularies(), kafka, props,
                Clock.fixed(FETCHED, ZoneOffset.UTC));
    }

    /** Every chaos file is the fixture's, whatever its name. */
    @SuppressWarnings("unchecked")
    private void serveTheFixture() {
        doAnswer(call -> {
            try (var in = LadderFixtures.chaos()) {
                return ((SmogonClient.BodyReader<Stats>) call.getArgument(2)).read(in);
            }
        }).when(client).chaos(anyString(), anyString(), any());
    }

    /** What a poll published, stored as the consumer would. */
    private void store(List<String> keys) {
        var sent = ArgumentCaptor.forClass(Object.class);
        verify(kafka, atLeast(0)).send(eq("ladder.stats"), anyString(), sent.capture());
        List<StatsFetched> published = sent.getAllValues().stream().map(StatsFetched.class::cast)
                .filter(f -> keys.contains(f.key())).toList();
        assertThat(published).extracting(StatsFetched::key).containsExactlyElementsOf(keys);
        published.forEach(store::put);
    }

    @BeforeEach
    void setUp() {
        jdbc.update("delete from ladder_stats");
        when(kafka.send(anyString(), anyString(), any())).thenReturn(CompletableFuture.completedFuture(null));
        when(client.months()).thenReturn(List.of("2026-09", "2026-08", "2026-07"));
        when(client.chaosFiles("2026-09")).thenReturn(List.of(
                FORMAT_ID + "-0.json", FORMAT_ID + "-1760.json", FORMAT_ID + "-1825.json",
                BSS + "-1760.json", "gen9championsvgc2026regmcbo3-1500.json",
                // Smogon's own tiers, another game's formats, a regulation the bundled data doesn't know.
                "gen9championsou-1760.json", "gen9ou-1825.json", "gen9vgc2026regi-1760.json",
                "gen9championsvgc2026regzz-1760.json", "odd.json"));
        when(client.chaosFiles("2026-08")).thenReturn(List.of("gen9championsbssregmb-1630.json"));
        when(client.leads(anyString(), anyString())).thenReturn(LadderFixtures.leads());
        serveTheFixture();
        discovery = discovery(SmogonProperties.defaults());
    }

    @Test
    void fetchesTheChampionsLaddersOfTheNewestMonths() {
        assertThat(discovery.discover()).containsExactly(
                FORMAT_ID + "|2026-09|0", FORMAT_ID + "|2026-09|1760", BSS + "|2026-09|1760",
                "gen9championsvgc2026regmcbo3|2026-09|1500", "gen9championsbssregmb|2026-08|1630");
        // Two months back is past the lookback.
        verify(client, never()).chaosFiles("2026-07");
        // The leads file is the chaos file's, by name.
        verify(client).leads("2026-09", BSS + "-1760.txt");
        verify(client).leads("2026-08", "gen9championsbssregmb-1630.txt");
        verify(client, times(5)).leads(anyString(), anyString());

        var sent = ArgumentCaptor.forClass(Object.class);
        verify(kafka).send(eq("ladder.stats"), eq(BSS + "|2026-09|1760"), sent.capture());
        var fetched = (StatsFetched) sent.getValue();
        assertThat(fetched.fetchedAt()).isEqualTo(FETCHED);
        assertThat(fetched.stats().format()).isEqualTo(BSS);
        assertThat(fetched.stats().mode()).isEqualTo("singles");
        assertThat(fetched.stats().regulation()).isEqualTo("M-C");
        assertThat(fetched.stats().month()).isEqualTo("2026-09");
        assertThat(fetched.stats().rating()).isEqualTo(1760);
        assertThat(fetched.stats().pokemon()).hasSize(27);
        assertThat(fetched.stats().pokemon().get(0).leadShare()).isEqualTo(0.0426031);
    }

    @Test
    void aFileIsFetchedOnce() {
        var first = discovery.discover();
        assertThat(first).hasSize(5);
        store(first);

        assertThat(discovery.discover()).as("everything is stored").isEmpty();
        verify(client, times(5)).chaos(anyString(), anyString(), any());
        verify(client, times(5)).leads(anyString(), anyString());
    }

    /** Stored by an older rule: fetched and reduced again. */
    @Test
    void aNewRuleFetchesAgain() {
        store(discovery.discover());
        jdbc.update("update ladder_stats set reduction = ? where rating = 1760", LadderReducer.REDUCTION - 1);
        assertThat(discovery.discover()).containsExactly(FORMAT_ID + "|2026-09|1760", BSS + "|2026-09|1760");
    }

    @Test
    void aLongerLookbackIsTheBackfill() {
        when(client.chaosFiles("2026-07")).thenReturn(List.of("gen9championsbssregmb-0.json"));
        var backfill = discovery(new SmogonProperties(null, true, null, 12, List.of(0), null, null));
        // Only the ratings asked for.
        assertThat(backfill.discover()).containsExactly(FORMAT_ID + "|2026-09|0", "gen9championsbssregmb|2026-07|0");
    }

    @Test
    void failuresDontStopIt() {
        doThrow(new IllegalStateException("Smogon returned 503")).when(client).chaos(eq("2026-09"), eq(FORMAT_ID + "-0.json"), any());
        when(client.leads("2026-09", BSS + "-1760.txt")).thenThrow(new IllegalStateException("timed out"));
        when(kafka.send(anyString(), eq("gen9championsvgc2026regmcbo3|2026-09|1500"), any()))
                .thenReturn(CompletableFuture.failedFuture(new IllegalStateException("broker down")));
        when(client.chaosFiles("2026-08")).thenThrow(new IllegalStateException("no listing"));

        var first = discovery.discover();
        assertThat(first).containsExactly(FORMAT_ID + "|2026-09|1760");
        store(first);

        // Nothing that failed was stored, so the next poll fetches it.
        reset(client, kafka);
        setUpAgain();
        assertThat(discovery.discover()).containsExactly(FORMAT_ID + "|2026-09|0", BSS + "|2026-09|1760",
                "gen9championsvgc2026regmcbo3|2026-09|1500", "gen9championsbssregmb|2026-08|1630");

        when(client.months()).thenThrow(new IllegalStateException("Smogon down"));
        assertThat(discovery.discover()).isEmpty();
    }

    /** A file that isn't Smogon's stats (an error page, a cut-off download) is left for the next poll. */
    @Test
    @SuppressWarnings("unchecked")
    void anUnreadableFileIsntPublished() {
        doAnswer(call -> {
            try {
                return ((SmogonClient.BodyReader<Stats>) call.getArgument(2))
                        .read(new ByteArrayInputStream("<html>Bad Gateway</html>".getBytes()));
            } catch (IOException e) {
                // As RestClient hands a reader's failure on.
                throw new ResourceAccessException("I/O error", e);
            }
        }).when(client).chaos(anyString(), anyString(), any());
        assertThat(discovery.discover()).isEmpty();
        verify(kafka, never()).send(anyString(), anyString(), any());
    }

    private void setUpAgain() {
        when(kafka.send(anyString(), anyString(), any())).thenReturn(CompletableFuture.completedFuture(null));
        when(client.months()).thenReturn(List.of("2026-09", "2026-08", "2026-07"));
        when(client.chaosFiles("2026-09")).thenReturn(List.of(
                FORMAT_ID + "-0.json", FORMAT_ID + "-1760.json", BSS + "-1760.json", "gen9championsvgc2026regmcbo3-1500.json"));
        when(client.chaosFiles("2026-08")).thenReturn(List.of("gen9championsbssregmb-1630.json"));
        when(client.leads(anyString(), anyString())).thenReturn(LadderFixtures.leads());
        serveTheFixture();
    }
}
