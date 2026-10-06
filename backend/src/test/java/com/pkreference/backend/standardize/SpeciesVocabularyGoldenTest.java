package com.pkreference.backend.standardize;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.io.InputStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.SoftAssertions.assertSoftly;

/**
 * Species keys match the app's. golden/species-identity.json was recorded from the app's
 * TeamSearchVocabulary, and the app's SpeciesIdentityGoldenTests checks the same file.
 */
class SpeciesVocabularyGoldenTest {
    private static final SpeciesVocabularies VOCABULARIES = new SpeciesVocabularies();

    @Test
    void matchesTheAppsKeys() throws Exception {
        JsonNode golden;
        try (InputStream in = getClass().getResourceAsStream("/golden/species-identity.json")) {
            golden = new ObjectMapper().readTree(in);
        }
        assertThat(golden.path("cases").size()).isGreaterThan(150);
        assertSoftly(soft -> golden.path("cases").forEach(c -> {
            var key = VOCABULARIES.identify(text(c, "format"), text(c, "name"), text(c, "slug"), text(c, "item"));
            String label = text(c, "format") + " " + text(c, "name") + " " + text(c, "slug") + " " + text(c, "item");
            soft.assertThat(key.key()).as(label).isEqualTo(text(c, "key"));
            soft.assertThat(key.megaStone()).as(label).isEqualTo(text(c, "mega"));
        }));
    }

    @Test
    void namesLikeTheApp() {
        assertThat(SpeciesNames.toId("Mr. Rime")).isEqualTo("mrrime");
        assertThat(SpeciesNames.toId("Flabébé")).isEqualTo("flabebe");
        assertThat(SpeciesNames.words("Hisuian Arcanine")).containsExactly("hisui", "arcanine");
        assertThat(SpeciesNames.words("Indeedee♀")).containsExactly("indeedee", "female");
        assertThat(SpeciesNames.tokens("arcanine-h, Pokémon")).containsExactly("arcanine", "hisui", ",", "pokemon");
        assertThat(SpeciesNames.tokens("Kommo-o")).containsExactly("kommo", "o");
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node.get(field);
        return value == null || value.isNull() ? null : value.asText();
    }
}
