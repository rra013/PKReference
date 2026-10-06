package com.pkreference.backend.insight;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.pkreference.backend.insight.MetaResponses.PokemonSet;
import com.pkreference.backend.insight.MetaResponses.PokemonUsage;
import com.pkreference.backend.insight.MetaResponses.Share;
import com.pkreference.backend.model.Events.PairingsFetched;
import com.pkreference.backend.model.Events.StandingsFetched;
import com.pkreference.backend.model.Events.Tournament;
import com.pkreference.backend.standardize.NameStandardizer;
import com.pkreference.backend.standardize.SpeciesVocabularies;
import com.pkreference.backend.store.TeamStore;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.JdbcTest;
import org.springframework.context.annotation.Import;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static com.pkreference.backend.LimitlessFixtures.details;
import static com.pkreference.backend.LimitlessFixtures.pairings;
import static com.pkreference.backend.LimitlessFixtures.standings;
import static org.assertj.core.api.Assertions.assertThat;

/**
 * golden/meta-fixture.json: the insights MetaService works out from the fixture event, for the app's
 * version worked out on the device (BackendIntegration-PHASE4.md §6) to match. Only what the device
 * can work out from standings is in it: usage, trends, sets and their parts, teammates, cores and
 * archetypes, not top cuts or win records, which need the event's phases and pairings.
 *
 * <p>Record it again after a deliberate change to the insights, and check the app against it:
 * {@code mvn test -Dtest=MetaGoldenFileTest -Dgolden.record=true}.
 */
@JdbcTest
@Import({TeamStore.class, SpeciesVocabularies.class, MetaRepository.class, MetaService.class,
        NameStandardizer.class, MetaServiceTest.Config.class})
class MetaGoldenFileTest {
    static final String FILE = "golden/meta-fixture.json";
    /** Pages for the most-used Pokémon only, to keep the file readable. */
    static final int PAGES = 12;

    @Autowired TeamStore store;
    @Autowired MetaService meta;

    private void put(String id, String date, int teams) {
        var t = new Tournament(id, "Test Event", "VGC", "M-C", date, 83);
        store.putStandings(new StandingsFetched(t, standings().subList(0, teams), details(), MetaServiceTest.NOW, true));
        store.putPairings(new PairingsFetched(t, pairings(), MetaServiceTest.NOW));
    }

    @Test
    void matchesTheGoldenFile() throws IOException {
        meta.forget();
        Map<String, Object> golden = new LinkedHashMap<>();
        golden.put("about", """
                The PK Reference server's insights for the fixture event (limitless/event-83: M-C, 83 players, \
                2026-10-05), as MetaService works them out at 2026-10-06T12:00:00Z in the 30-day window. \
                Recorded by the backend's MetaGoldenFileTest, which checks it; the app's version worked out on \
                the device checks against it too, so the two give the same numbers. "event" has the event \
                alone. "trends" adds a copy of its first 60 teams dated 2026-09-15 (three weeks earlier), so \
                both fortnights have 50 teams or more. Items, abilities, natures and moves are standardized by \
                NameStandardizer; species keys are the app's (golden/species-identity.json). Shares are 0 to \
                1, rounded to 4 places; lists are cut to the server's lengths (12 values, 10 sets, 20 cores).""");

        put("event-83", "2026-10-05T18:00:00.000Z", 83);
        golden.put("event", scenario(true));
        put("three-weeks-ago", "2026-09-15T18:00:00.000Z", 60);
        meta.forget();
        Map<String, Object> trends = new LinkedHashMap<>();
        for (PokemonUsage p : meta.pokemon("M-C", MetaWindow.DAYS_30).pokemon()) trends.put(p.key(), p.trend());
        golden.put("trends", trends);

        ObjectMapper json = new ObjectMapper().enable(SerializationFeature.INDENT_OUTPUT);
        JsonNode actual = json.valueToTree(golden);
        if (Boolean.getBoolean("golden.record")) {
            // The classpath still has the old copy until the next build, so there's nothing to compare.
            Files.writeString(Path.of("src/test/resources", FILE), json.writeValueAsString(actual) + "\n");
            return;
        }
        JsonNode expected;
        try (InputStream in = getClass().getResourceAsStream("/" + FILE)) {
            assertThat(in).as(FILE + " (record it with -Dgolden.record=true)").isNotNull();
            expected = json.readTree(in);
        }
        assertThat(actual).isEqualTo(expected);
    }

    private Map<String, Object> scenario(boolean pages) {
        Map<String, Object> out = new LinkedHashMap<>();
        var list = meta.pokemon("M-C", MetaWindow.DAYS_30);
        out.put("sample", row("events", list.sample().events(), "teams", list.sample().teams()));
        out.put("pokemon", list.pokemon().stream()
                .map(p -> row("key", p.key(), "teams", p.teams(), "usage", p.usage())).toList());
        if (pages) {
            Map<String, Object> details = new LinkedHashMap<>();
            for (PokemonUsage p : list.pokemon().subList(0, Math.min(PAGES, list.pokemon().size()))) {
                var d = meta.pokemon("M-C", p.key(), MetaWindow.DAYS_30);
                Map<String, Object> page = new LinkedHashMap<>();
                page.put("items", shares(d.items()));
                page.put("abilities", shares(d.abilities()));
                page.put("natures", shares(d.natures()));
                page.put("moves", shares(d.moves()));
                page.put("megaStones", shares(d.megaStones()));
                page.put("teammates", shares(d.teammates()));
                page.put("sets", d.sets().stream().map(MetaGoldenFileTest::set).toList());
                details.put(p.key(), page);
            }
            out.put("pages", details);
        }
        var cores = meta.cores("M-C", MetaWindow.DAYS_30);
        out.put("pairs", cores.pairs().stream()
                .map(c -> row("members", c.members(), "teams", c.teams(), "share", c.share(), "lift", c.lift())).toList());
        out.put("trios", cores.trios().stream()
                .map(c -> row("members", c.members(), "teams", c.teams(), "share", c.share(), "lift", c.lift())).toList());
        var archetypes = meta.archetypes("M-C", MetaWindow.DAYS_30);
        out.put("other", archetypes.other());
        out.put("archetypes", archetypes.archetypes().stream()
                .map(a -> row("id", a.id(), "name", a.name(), "core", a.core(), "teams", a.teams(), "usage", a.usage()))
                .toList());
        return out;
    }

    private static List<Map<String, Object>> shares(List<Share> shares) {
        return shares.stream().map(s -> row("value", s.value(), "count", s.count(), "share", s.share())).toList();
    }

    private static Map<String, Object> set(PokemonSet s) {
        return row("item", s.item(), "ability", s.ability(), "nature", s.nature(), "moves", s.moves(),
                "count", s.count(), "share", s.share());
    }

    /** An ordered map from key, value pairs; null values are kept. */
    private static Map<String, Object> row(Object... pairs) {
        Map<String, Object> out = new LinkedHashMap<>();
        for (int i = 0; i < pairs.length; i += 2) out.put((String) pairs[i], pairs[i + 1]);
        return out;
    }
}
