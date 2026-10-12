package com.pkreference.backend.standardize;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Canonicalizes the free-text names players type into decklists (items, abilities, moves,
 * natures, Tera types), so "MIRACLE SEED", "Miracle seed" and "miracle seed" count as one.
 *
 * <p>Item spellings also come from {@code reference/champions-items.json}, a snapshot of Serebii's
 * Champions item page (every Champions item, not per regulation).
 *
 * <p>Names come from the repo-root regulation files ({@code champions-m-*.json} and their
 * learnsets) plus {@code showdown-champions-data.json}, copied onto the classpath under
 * {@code regulations/} at build time. Those lists are used to fix spelling and casing only, never
 * to drop a value: decklists come from formats with no regulation file (fan formats, older or
 * newer regulations), so a name that matches nothing is kept, title-cased.
 */
@Component
public class NameStandardizer {
    private static final Logger log = LoggerFactory.getLogger(NameStandardizer.class);
    private static final String DIR = "classpath:regulations/";
    public static final String NO_ITEM = "No Item";

    private static final List<String> NATURES = List.of(
            "Hardy", "Lonely", "Brave", "Adamant", "Naughty", "Bold", "Docile", "Relaxed", "Impish", "Lax",
            "Timid", "Hasty", "Serious", "Jolly", "Naive", "Modest", "Mild", "Quiet", "Bashful", "Rash",
            "Calm", "Gentle", "Sassy", "Careful", "Quirky");
    private static final List<String> TERA_TYPES = List.of(
            "Normal", "Fire", "Water", "Electric", "Grass", "Ice", "Fighting", "Poison", "Ground", "Flying",
            "Psychic", "Bug", "Rock", "Ghost", "Dragon", "Dark", "Steel", "Fairy", "Stellar");

    /** Names for one regulation, keyed by regulation id ("m-c"); the union is the fallback. */
    private record Names(NameDictionary items, NameDictionary abilities, NameDictionary moves) {}

    private final Map<String, Names> byRegulation = new HashMap<>();
    private final Names union;
    private final NameDictionary natures = new NameDictionary(NATURES);
    private final NameDictionary teraTypes = new NameDictionary(TERA_TYPES);

    /**
     * Loads every name list once, at start-up. {@code ObjectMapper} is Jackson's JSON reader, a
     * bean Spring Boot provides.
     */
    public NameStandardizer(ObjectMapper mapper) {
        var resolver = new PathMatchingResourcePatternResolver();
        var allItems = new NameDictionary.Builder();
        var allAbilities = new NameDictionary.Builder();
        var allMoves = new NameDictionary.Builder();
        try {
            // Showdown data: every move, plus abilities of every species (megas included).
            var showdown = read(mapper, resolver.getResource(DIR + "showdown-champions-data.json"));
            showdown.path("moves").fieldNames().forEachRemaining(m -> {
                if (!m.startsWith("(")) allMoves.add(m);
            });
            showdown.path("species").forEach(s -> s.path("abilities").forEach(a -> allAbilities.add(a.asText())));

            // Serebii's Champions item page: every Champions item (not per regulation).
            var serebii = read(mapper, resolver.getResource("classpath:reference/champions-items.json"));
            serebii.path("items").forEach(n -> allItems.add(n.asText()));

            for (Resource r : resolver.getResources(DIR + "champions-*.json")) {
                String file = r.getFilename();
                if (file == null || file.endsWith("-learnsets.json")) continue;
                JsonNode reg = read(mapper, r);
                String regId = reg.path("format_id").asText().replaceFirst("^champions-", "").toLowerCase(Locale.ROOT);

                var items = new NameDictionary.Builder();
                reg.path("items_whitelist").forEach(n -> items.add(n.asText()));
                reg.path("berries_whitelist").forEach(n -> items.add(n.asText()));
                reg.path("mega_stones").forEach(n -> items.add(n.asText()));

                var abilities = new NameDictionary.Builder();
                var moves = new NameDictionary.Builder();
                Resource learnsets = resolver.getResource(DIR + file.replace(".json", "-learnsets.json"));
                if (learnsets.exists()) {
                    JsonNode l = read(mapper, learnsets);
                    l.path("species").forEach(s -> {
                        s.path("abilities").forEach(a -> abilities.add(a.asText()));
                        s.path("moves").forEach(m -> moves.add(m.asText()));
                    });
                }
                allItems.addAll(items);
                allAbilities.addAll(abilities);
                allMoves.addAll(moves);
                byRegulation.put(regId, new Names(items.build(), abilities.build(), moves.build()));
            }
        } catch (IOException e) {
            throw new UncheckedIOException("Could not load regulation name data from " + DIR, e);
        }
        union = new Names(allItems.build(), allAbilities.build(), allMoves.build());
        log.info("Name standardizer loaded regulations {}", byRegulation.keySet());
    }

    /** Blank and "none"-style values become {@link #NO_ITEM}; null stays null (no item given). */
    public String item(String format, String raw) {
        if (raw == null) return null;
        String key = NameDictionary.key(raw);
        if (key.isEmpty() || key.equals("none") || key.equals("noitem") || key.equals("noitems")) return NO_ITEM;
        return resolve(format, raw, Names::items);
    }

    /** An ability's canonical name; null for null or blank. */
    public String ability(String format, String raw) {
        return resolve(format, raw, Names::abilities);
    }

    /** A move's canonical name; null for null or blank. */
    public String move(String format, String raw) {
        return resolve(format, raw, Names::moves);
    }

    /**
     * A Showdown ID from Smogon's stats ("choicescarf") as the item's name ("Choice Scarf"); the ID
     * itself when no item has it. Smogon's "nothing" is {@link #NO_ITEM}. Exact matches only: an
     * ID is never misspelled, so a near-miss would be another item.
     */
    public String itemById(String format, String id) {
        if (id.equals("nothing")) return NO_ITEM;
        return byId(format, id, Names::items);
    }

    /** An ability's Showdown ID as its name; the ID itself when nothing has it. */
    public String abilityById(String format, String id) {
        return byId(format, id, Names::abilities);
    }

    /** A move's Showdown ID as its name; the ID itself when nothing has it. */
    public String moveById(String format, String id) {
        return byId(format, id, Names::moves);
    }

    /** An exact lookup in the format's own lists, then in every regulation's. */
    private String byId(String format, String id, java.util.function.Function<Names, NameDictionary> pick) {
        Names reg = format == null ? null : byRegulation.get(format.toLowerCase(Locale.ROOT));
        String hit = reg == null ? null : pick.apply(reg).exact(id);
        if (hit == null) hit = pick.apply(union).exact(id);
        return hit != null ? hit : id;
    }

    /** A nature's canonical name. Natures and Tera types are the same in every regulation. */
    public String nature(String raw) {
        return raw == null ? null : natures.resolve(raw, null);
    }

    /** A Tera type's canonical name. */
    public String tera(String raw) {
        return raw == null ? null : teraTypes.resolve(raw, null);
    }

    /** Looks a name up in the format's own lists, then in every regulation's. */
    private String resolve(String format, String raw, java.util.function.Function<Names, NameDictionary> pick) {
        if (raw == null || raw.isBlank()) return null;
        Names reg = format == null ? null : byRegulation.get(format.toLowerCase(Locale.ROOT));
        return pick.apply(reg == null ? union : reg).resolve(raw, pick.apply(union));
    }

    /** Parses one bundled JSON file, closing it afterwards. */
    private static JsonNode read(ObjectMapper mapper, Resource r) throws IOException {
        try (var in = r.getInputStream()) {
            return mapper.readTree(in);
        }
    }
}
