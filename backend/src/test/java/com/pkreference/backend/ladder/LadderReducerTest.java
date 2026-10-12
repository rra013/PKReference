package com.pkreference.backend.ladder;

import com.pkreference.backend.model.Ladder.Pokemon;
import com.pkreference.backend.model.Ladder.Share;
import com.pkreference.backend.model.Ladder.Stats;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;

/** The reducer's rules, on the fixture and on input made to be awkward. The golden file has the numbers. */
class LadderReducerTest {
    private final LadderReducer reducer = LadderFixtures.reducer();

    private Stats reduce(String chaos, String leads) throws IOException {
        return reducer.reduce(new ByteArrayInputStream(chaos.getBytes(StandardCharsets.UTF_8)), leads,
                LadderFixtures.FORMAT, "2026-09", 1760);
    }

    private static Pokemon named(Stats stats, String name) {
        return stats.pokemon().stream().filter(p -> p.name().equals(name)).findFirst().orElseThrow();
    }

    @Test
    void theFixture() {
        Stats stats = LadderFixtures.stats();
        assertThat(stats.reduction()).isEqualTo(LadderReducer.REDUCTION);
        assertThat(stats.format()).isEqualTo("gen9championsvgc2026regmc");
        assertThat(stats.regulation()).isEqualTo("M-C");
        assertThat(stats.mode()).isEqualTo("doubles");
        assertThat(stats.bestOf()).isEqualTo(1);
        assertThat(stats.battles()).isEqualTo(1_631_943);
        assertThat(stats.pokemon()).hasSize(27);
        assertThat(stats.pokemon()).extracting(Pokemon::usage).isSortedAccordingTo((a, b) -> Double.compare(b, a));

        Pokemon rillaboom = stats.pokemon().get(0);
        assertThat(rillaboom.name()).isEqualTo("Rillaboom");
        assertThat(rillaboom.usage()).isEqualTo(0.4659939);
        assertThat(rillaboom.leadShare()).isEqualTo(0.0426031);
        assertThat(rillaboom.items().get(0)).isEqualTo(new Share("Miracle Seed", 0.62503));
        // Four moves a team: the moves kept come to nearly 4.
        assertThat(rillaboom.moves().stream().mapToDouble(Share::share).sum()).isCloseTo(4.0, within(0.02));
        // Overgrow, on 0.24% of Rillaboom, is under the floor.
        assertThat(rillaboom.abilities()).extracting(Share::value).containsExactly("Grassy Surge");
        assertThat(rillaboom.spreads().get(0).value()).isEqualTo("Adamant:32/32/0/0/2/0");
        assertThat(rillaboom.teammates()).hasSize(LadderReducer.TEAMMATES);
        assertThat(rillaboom.teammates().get(0).value()).isEqualTo("Incineroar");
    }

    @Test
    void speciesKeysAndMegas() {
        Stats stats = LadderFixtures.stats();
        Map<String, String> keys = Map.of(
                "Salamence-Mega", "salamence", "Salamence", "salamence", "Indeedee-F", "indeedee:female",
                "Arcanine-Hisui", "arcanine:hisui", "Ninetales-Alola", "ninetales:alola", "Kommo-o", "kommoo",
                "Mr. Rime", "mrrime", "Sirfetch'd", "sirfetchd", "Tauros-Paldea-Aqua", "tauros:aqua-paldea",
                "Zoroark-Hisui", "zoroark:hisui");
        keys.forEach((name, key) -> assertThat(named(stats, name).key()).as(name).isEqualTo(key));

        // A Mega is the Pokémon holding its stone; one with two Megas has an entry for each.
        Map<String, String> stones = Map.of(
                "Salamence-Mega", "Salamencite", "Charizard-Mega-Y", "Charizardite Y", "Raichu-Mega-Y", "Raichunite Y",
                "Garchomp-Mega-Z", "Garchompite Z", "Lucario-Mega", "Lucarionite", "Lucario-Mega-Z", "Lucarionite Z",
                "Golisopod-Mega", "Golisopite");
        stones.forEach((name, stone) -> assertThat(named(stats, name).megaStone()).as(name).isEqualTo(stone));
        assertThat(named(stats, "Salamence").megaStone()).isNull();
        assertThat(named(stats, "Garchomp").megaStone()).isNull();
        assertThat(stats.pokemon()).extracting(Pokemon::name).doesNotHaveDuplicates();
    }

    /** Zoroark leads as something else (Illusion), so Smogon's leads file doesn't list it. */
    @Test
    void aPokemonWithoutALeadsRow() throws IOException {
        assertThat(named(LadderFixtures.stats(), "Zoroark-Hisui").leadShare()).isNull();
        try (var in = LadderFixtures.chaos()) {
            Stats noLeads = reducer.reduce(in, null, LadderFixtures.FORMAT, "2026-09", 1760);
            assertThat(noLeads.pokemon()).hasSize(27).allSatisfy(p -> assertThat(p.leadShare()).isNull());
        }
    }

    @Test
    void readsTheLeadsTable() {
        var shares = LadderReducer.leadShares("""
                 Total leads: 3263886
                 + ---- + ------------------ + --------- + ------ + ------- +
                 | Rank | Pokemon            | Usage %   | Raw    | %       |
                 + ---- + ------------------ + --------- + ------ + ------- +
                 | 1    | Sneasler           |  6.59479% | 204684 |  6.271% |\r
                 | 2    | Mr. Rime           |  0.01127% | 4      |  0.000% |
                 | x    | Not A Row          |  1.00000% | 4      |  0.000% |
                 | 3    | Broken             |  lots     | 4      |  0.000% |
                """);
        assertThat(shares).containsOnlyKeys("Sneasler", "Mr. Rime");
        assertThat(shares.get("Sneasler")).isEqualTo(0.0659479);
        assertThat(LadderReducer.leadShares(null)).isEmpty();
    }

    @Test
    void awkwardInput() throws IOException {
        Stats stats = reduce("""
                {"data": {
                  "Nobodymon": {"usage": 0.5, "Abilities": {"madeupability": 10}, "Items": {"nothing": 6, "madeupitem": 4},
                                "Moves": {"": 3, "protect": 10, "madeupmove": 10}, "Spreads": {"Jolly:0/32/0/0/2/32": 4,
                                "Jolly:2/32/0/0/0/32": 4, "Timid:0/0/0/32/2/32": 2, "broken": 1},
                                "Teammates": {"Rillaboom": 5, "Gone": 0, "Minus": -1}},
                  "Unused": {"usage": 0, "Abilities": {"overgrow": 10}},
                  "Weightless": {"usage": 0.1, "Abilities": {}},
                  "Bare": {"usage": 0.25, "Abilities": {"overgrow": 2}},
                  "Rillaboom": {"usage": 0.5, "Abilities": {"overgrow": 1, "grassysurge": 1}, "Items": 7}
                 },
                 "extra": [1, {"a": 2}],
                 "info": {"number of battles": 12}}""", null);

        assertThat(stats.battles()).as("info after data").isEqualTo(12);
        // Equal usage: by name. No usage, or no weight: left out.
        assertThat(stats.pokemon()).extracting(Pokemon::name).containsExactly("Nobodymon", "Rillaboom", "Bare");

        Pokemon nobody = stats.pokemon().get(0);
        assertThat(nobody.key()).as("not in the regulation").isNull();
        assertThat(nobody.megaStone()).isNull();
        // IDs nothing matches stay as they are; they're never guessed at.
        assertThat(nobody.abilities()).containsExactly(new Share("madeupability", 1.0));
        assertThat(nobody.items()).containsExactly(new Share("No Item", 0.6), new Share("madeupitem", 0.4));
        // The empty move slot isn't a move. Equal counts: by ID.
        assertThat(nobody.moves()).containsExactly(new Share("madeupmove", 1.0), new Share("Protect", 1.0));
        assertThat(nobody.natures()).containsExactly(new Share("Jolly", 0.8), new Share("Timid", 0.2));
        assertThat(nobody.spreads()).extracting(Share::value).containsExactly(
                "Jolly:0/32/0/0/2/32", "Jolly:2/32/0/0/0/32", "Timid:0/0/0/32/2/32", "broken");
        assertThat(nobody.teammates()).containsExactly(new Share("Rillaboom", 0.5));

        Pokemon bare = stats.pokemon().get(2);
        assertThat(bare.items()).isEmpty();
        assertThat(bare.moves()).isEmpty();
        assertThat(bare.spreads()).isEmpty();
        assertThat(stats.pokemon().get(1).abilities()).as("equal counts, by ID")
                .containsExactly(new Share("Grassy Surge", 0.5), new Share("Overgrow", 0.5));
        assertThat(stats.pokemon().get(1).items()).as("not an object").isEmpty();
    }

    @Test
    void cutsAndRounds() throws IOException {
        var abilities = new StringBuilder();
        for (int i = 0; i < 8; i++) abilities.append(i == 0 ? "" : ", ").append("\"ability").append(i).append("\": ").append(8 - i);
        Stats stats = reduce("{\"data\": {\"Rillaboom\": {\"usage\": 0.5, \"Abilities\": {" + abilities + "},"
                + " \"Items\": {\"leftovers\": 12, \"lifeorb\": 24, \"sitrusberry\": 0.1}}}}", null);
        Pokemon p = stats.pokemon().get(0);
        assertThat(p.abilities()).hasSize(LadderReducer.ABILITIES);
        assertThat(p.abilities().get(0)).isEqualTo(new Share("ability0", 0.22222));
        // 0.1 of 36 is under half a percent.
        assertThat(p.items()).containsExactly(new Share("Life Orb", 0.66667), new Share("Leftovers", 0.33333));
        assertThat(LadderReducer.round(0.000005)).as("half to even").isEqualTo(0.0);
        assertThat(LadderReducer.round(0.000015)).isEqualTo(0.00002);
        // As Smogon wrote Salamence's usage, and as Foundation's JSONSerialization reads it.
        assertThat(LadderReducer.roundUsage(0.0032668000000000003)).isEqualTo(0.0032668);
        assertThat(LadderReducer.roundUsage(0.0032668000000000016)).isEqualTo(0.0032668);
    }

    @Test
    void notSmogonsStats() {
        assertThatThrownBy(() -> reduce("[]", null)).isInstanceOf(IOException.class);
        assertThatThrownBy(() -> reduce("{\"info\": {}}", null)).isInstanceOf(IOException.class);
        assertThatThrownBy(() -> reduce("<html>404</html>", null)).isInstanceOf(IOException.class);
        assertThatThrownBy(() -> reduce("{\"data\": {\"Rillaboom\": {\"usage\": 0.5", null)).isInstanceOf(IOException.class);
    }

    @Test
    void byteOrder() {
        assertThat(List.of("b", "a", "Z", "é", "a-b", "ab").stream().sorted(LadderReducer.BYTES).toList())
                .containsExactly("Z", "a", "a-b", "ab", "b", "é");
    }
}
