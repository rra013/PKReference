package com.pkreference.backend.ladder;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * golden/ladder-fixture.json: the fixture (LadderFixtures) as LadderReducer reduces it. The app's
 * SmogonLadder.reduce must make the same record from the same two files, number for number, so the
 * ladder reads the same from the server and from the device's own download
 * (BackendIntegration-PHASE5.md §3).
 *
 * <p>Record it again after a deliberate change to the rule, with a new LadderReducer.REDUCTION,
 * and check the app against it: {@code mvn test -Dtest=LadderGoldenFileTest -Dgolden.record=true}.
 */
class LadderGoldenFileTest {
    static final String FILE = "golden/ladder-fixture.json";

    @Test
    void matchesTheGoldenFile() throws IOException {
        Map<String, Object> golden = new LinkedHashMap<>();
        golden.put("about", """
                Ladder stats reduced from the fixture under smogon/2026-09 (Smogon's real M-C doubles files at \
                1760, cut down to 27 Pokémon; LadderFixtures has the details). Recorded by the backend's \
                LadderGoldenFileTest, which checks it; the app's SmogonLadder.reduce checks against it too, so \
                both make the same record from Smogon's files. Shares are 0 to 1, of the Pokémon's own weight \
                (the sum of its ability counts), rounded half to even at five places; usage and leadShare are \
                as Smogon publishes them.""");
        golden.put("stats", LadderFixtures.stats());

        ObjectMapper json = new ObjectMapper().enable(SerializationFeature.INDENT_OUTPUT);
        // Written and read back, so numbers are the kinds a file's are (battles is a long here).
        JsonNode actual = json.readTree(json.writeValueAsString(golden));
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
}
