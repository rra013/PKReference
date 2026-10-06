package com.pkreference.backend.standardize;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Each bundled regulation's SpeciesVocabulary, by Limitless format ("M-C" is champions-m-c.json).
 * Maven bundles the app's files into regulations/, so a new regulation needs nothing here.
 */
@Component
public class SpeciesVocabularies {
    private static final Logger log = LoggerFactory.getLogger(SpeciesVocabularies.class);
    private static final String DIR = "classpath:regulations/";

    /** A member's species key and, when its item is one of its Mega Stones, the stone's ID. */
    public record SpeciesKey(String key, String megaStone) {}

    private final Map<String, SpeciesVocabulary> byFormat = new HashMap<>();

    public SpeciesVocabularies() {
        var mapper = new ObjectMapper();
        var resolver = new PathMatchingResourcePatternResolver();
        try {
            JsonNode vocabulary = read(mapper, resolver.getResource(DIR + "team_search_vocab.json"));
            for (Resource r : resolver.getResources(DIR + "champions-*.json")) {
                String file = r.getFilename();
                if (file == null || file.endsWith("-learnsets.json")) continue;
                String id = file.substring("champions-".length(), file.length() - ".json".length());
                Resource learnsets = resolver.getResource(DIR + "champions-" + id + "-learnsets.json");
                if (!learnsets.exists()) continue;
                byFormat.put(id.toLowerCase(Locale.ROOT),
                        new SpeciesVocabulary(read(mapper, r), read(mapper, learnsets), vocabulary));
            }
        } catch (IOException e) {
            throw new UncheckedIOException("Could not read the bundled regulations", e);
        }
        log.info("Species vocabularies for {}", byFormat.keySet());
    }

    /**
     * A member's species key the app's way. Outside a bundled regulation (a Scarlet and Violet
     * format, a fan format) it's the slug, or the name when there's no slug, as a Showdown ID.
     */
    public SpeciesKey identify(String format, String name, String slug, String item) {
        var vocabulary = format == null ? null : byFormat.get(format.toLowerCase(Locale.ROOT));
        if (vocabulary == null) {
            String raw = slug != null && !slug.isEmpty() ? slug : name == null ? "" : name;
            return new SpeciesKey(SpeciesNames.toId(raw), null);
        }
        var identity = vocabulary.identity(name, slug);
        return new SpeciesKey(identity.key(), vocabulary.megaStone(item, identity.speciesId()));
    }

    private static JsonNode read(ObjectMapper mapper, Resource resource) throws IOException {
        try (InputStream in = resource.getInputStream()) {
            return mapper.readTree(in);
        }
    }
}
