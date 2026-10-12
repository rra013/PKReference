package com.pkreference.backend.ladder;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonToken;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.pkreference.backend.model.Ladder.Pokemon;
import com.pkreference.backend.model.Ladder.Share;
import com.pkreference.backend.model.Ladder.Stats;
import com.pkreference.backend.standardize.NameStandardizer;
import com.pkreference.backend.standardize.SpeciesVocabularies;
import com.pkreference.backend.standardize.SpeciesVocabulary;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.function.Function;

/**
 * Cuts one of Smogon's chaos files, and its leads file, down to a Ladder.Stats
 * (BackendIntegration-PHASE5.md §3). The app's SmogonLadder.reduce does the same, rule for rule,
 * and both must produce golden/ladder-fixture.json from the fixture, so a change here is a change
 * there, a new {@link #REDUCTION} and the golden file recorded again.
 *
 * <p>To get the same bits in Java and Swift: sums are taken in the order of the keys, as bytes;
 * equal counts are ordered by key, as bytes; shares are rounded half to even at five places, and
 * usage and lead shares at nine. Smogon writes some numbers to more digits than a double holds
 * ("0.0032668000000000003"), and JSON parsers don't all read those to the same double (Foundation's
 * JSONSerialization lands a few units in the last place away), so nothing goes out unrounded.
 */
@Component
public class LadderReducer {
    /** The version of this rule. Stats stored at an older one are fetched and reduced again. */
    public static final int REDUCTION = 1;

    static final int ABILITIES = 6;
    static final int ITEMS = 12;
    static final int MOVES = 24;
    static final int NATURES = 6;
    static final int SPREADS = 10;
    static final int TEAMMATES = 24;
    /** Abilities, items, moves and natures on under 0.5% of the Pokémon's teams are left out. */
    static final double FLOOR = 0.005;

    /** Strings by their UTF-8 bytes: the same order in Java and in Swift, whatever the letters. */
    static final Comparator<String> BYTES =
            (a, b) -> Arrays.compareUnsigned(a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8));

    private record Count(String id, double count) {}

    private final ObjectMapper mapper;
    private final SpeciesVocabularies vocabularies;
    private final NameStandardizer names;

    public LadderReducer(ObjectMapper mapper, SpeciesVocabularies vocabularies, NameStandardizer names) {
        this.mapper = mapper;
        this.vocabularies = vocabularies;
        this.names = names;
    }

    /**
     * Reads the chaos file as a stream, one Pokémon at a time: the biggest files are over 7 MB,
     * and one Pokémon's part is a small tree. `leads` is the leads file's text, or null.
     */
    public Stats reduce(InputStream chaos, String leads, LadderFormat format, String month, int rating)
            throws IOException {
        Map<String, Double> leadShares = leadShares(leads);
        SpeciesVocabulary vocabulary = vocabularies.vocabulary(format.regulation());
        List<Pokemon> pokemon = new ArrayList<>();
        long battles = 0;
        boolean sawData = false;
        try (JsonParser parser = mapper.getFactory().createParser(chaos)) {
            if (parser.nextToken() != JsonToken.START_OBJECT) throw new IOException("Not Smogon's stats: no object");
            while (parser.nextToken() == JsonToken.FIELD_NAME) {
                String field = parser.currentName();
                parser.nextToken();
                if (field.equals("info")) {
                    JsonNode info = mapper.readTree(parser);
                    battles = info.path("number of battles").asLong(0);
                } else if (field.equals("data") && parser.currentToken() == JsonToken.START_OBJECT) {
                    sawData = true;
                    while (parser.nextToken() == JsonToken.FIELD_NAME) {
                        String name = parser.currentName();
                        parser.nextToken();
                        JsonNode entry = mapper.readTree(parser);
                        Pokemon reduced = pokemon(name, entry, format, vocabulary, leadShares.get(name));
                        if (reduced != null) pokemon.add(reduced);
                    }
                } else {
                    parser.skipChildren();
                }
            }
        }
        if (!sawData) throw new IOException("Not Smogon's stats: no data");
        pokemon.sort(Comparator.comparingDouble(Pokemon::usage).reversed().thenComparing(Pokemon::name, BYTES));
        return new Stats(REDUCTION, format.id(), format.regulation(), format.mode(), format.bestOf(), month, rating,
                battles, pokemon);
    }

    /** One Pokémon's entry, or null when it has no usage or no weight to take shares of. */
    private Pokemon pokemon(String name, JsonNode entry, LadderFormat format, SpeciesVocabulary vocabulary,
                            Double leadShare) {
        double usage = roundUsage(entry.path("usage").asDouble(0));
        List<Count> abilities = counts(entry.path("Abilities"));
        // The Pokémon's own weight: what Smogon's moveset files divide by.
        double weight = sum(abilities);
        if (!(usage > 0) || !(weight > 0)) return null;

        String regulation = format.regulation();
        List<Count> items = counts(entry.path("Items"));
        List<Count> spreads = counts(entry.path("Spreads"));

        String key = null;
        String megaStone = null;
        var species = vocabulary == null ? null : vocabulary.showdown(name);
        if (species != null) {
            key = species.identity().key();
            if (species.mega()) {
                // A Mega's entry is the Pokémon holding its stone: the stone is its commonest item.
                for (Count item : ranked(items)) {
                    String stone = vocabulary.megaStone(item.id(), species.identity().speciesId());
                    if (stone != null) {
                        megaStone = names.itemById(regulation, stone);
                        break;
                    }
                }
            }
        }

        return new Pokemon(name, key, megaStone, usage, leadShare,
                shares(abilities, weight, ABILITIES, FLOOR, id -> names.abilityById(regulation, id)),
                shares(items, weight, ITEMS, FLOOR, id -> names.itemById(regulation, id)),
                // An empty move slot is "".
                shares(counts(entry.path("Moves")), weight, MOVES, FLOOR,
                        id -> id.isEmpty() ? null : names.moveById(regulation, id)),
                shares(natures(spreads), weight, NATURES, FLOOR, Function.identity()),
                shares(spreads, weight, SPREADS, 0, Function.identity()),
                shares(counts(entry.path("Teammates")), weight, TEAMMATES, 0, Function.identity()));
    }

    /** An object of counts, in the order of its keys. */
    private static List<Count> counts(JsonNode object) {
        List<Count> counts = new ArrayList<>();
        object.fields().forEachRemaining(e -> {
            if (e.getValue().isNumber()) counts.add(new Count(e.getKey(), e.getValue().asDouble()));
        });
        counts.sort(Comparator.comparing(Count::id, BYTES));
        return counts;
    }

    private static double sum(List<Count> counts) {
        double sum = 0;
        for (Count c : counts) sum += c.count();
        return sum;
    }

    /** Biggest first; equal counts by key. */
    private static List<Count> ranked(List<Count> counts) {
        List<Count> ranked = new ArrayList<>(counts);
        ranked.sort(Comparator.comparingDouble(Count::count).reversed().thenComparing(Count::id, BYTES));
        return ranked;
    }

    /**
     * The `limit` biggest as shares of `weight`, leaving out those under `floor`, those of nothing,
     * and those `name` has no name for.
     */
    private static List<Share> shares(List<Count> counts, double weight, int limit, double floor,
                                      Function<String, String> name) {
        List<Share> shares = new ArrayList<>();
        for (Count c : ranked(counts)) {
            if (shares.size() == limit) break;
            double share = c.count() / weight;
            if (!(share > 0) || share < floor) continue;
            String value = name.apply(c.id());
            if (value != null) shares.add(new Share(value, round(share)));
        }
        return shares;
    }

    /** The spreads' counts added up by nature: a spread is "Adamant:2/32/0/0/0/32". */
    private static List<Count> natures(List<Count> spreads) {
        Map<String, Double> byNature = new HashMap<>();
        // In the spreads' order, so each nature's sum is taken the same way everywhere.
        for (Count spread : spreads) {
            int colon = spread.id().indexOf(':');
            if (colon <= 0) continue;
            byNature.merge(spread.id().substring(0, colon), spread.count(), Double::sum);
        }
        List<Count> natures = new ArrayList<>();
        byNature.forEach((nature, count) -> natures.add(new Count(nature, count)));
        natures.sort(Comparator.comparing(Count::id, BYTES));
        return natures;
    }

    /**
     * Each Pokémon's share of all leads, from the leads file's table:
     * {@code | 1    | Sneasler           |  6.59479% | 204684 |  6.271% |}.
     */
    static Map<String, Double> leadShares(String leads) {
        Map<String, Double> shares = new TreeMap<>();
        if (leads == null) return shares;
        for (String line : leads.split("\n")) {
            String[] cells = line.split("\\|");
            if (cells.length < 4 || !cells[1].trim().matches("\\d+")) continue;
            String percent = cells[3].trim();
            if (!percent.endsWith("%")) continue;
            try {
                shares.put(cells[2].trim(),
                        roundUsage(Double.parseDouble(percent.substring(0, percent.length() - 1)) / 100));
            } catch (NumberFormatException e) {
                // A row that isn't a number is left out.
            }
        }
        return shares;
    }

    /** To five places, half to even: Swift's rounded(.toNearestOrEven). */
    static double round(double share) {
        return Math.rint(share * 100_000) / 100_000;
    }

    /** Usage and lead shares, which Smogon publishes to seven places: to nine, half to even. */
    static double roundUsage(double usage) {
        return Math.rint(usage * 1_000_000_000) / 1_000_000_000;
    }
}
