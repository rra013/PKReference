package com.pkreference.backend.standardize;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

/**
 * One regulation's species, as the app's TeamSearchVocabulary knows them: what species a Limitless
 * member is (with the form words the regulation lists) and which Mega its held stone makes. Built
 * from the same files: champions-<reg>.json, its learnsets, and team_search_vocab.json's form noise.
 */
public final class SpeciesVocabulary {
    /** A member's species: "arcanine", or "arcanine:hisui" with its form words sorted. */
    public record Identity(String speciesId, Set<String> formWords) {
        public String key() {
            return formWords.isEmpty() ? speciesId : speciesId + ":" + String.join("-", new TreeSet<>(formWords));
        }
    }

    private record Species(String id, String name, List<String> words, Set<String> formWords) {}

    private final Map<String, List<Species>> byFirstWord = new HashMap<>();
    /** Stone ID to the species ID it's for. */
    private final Map<String, String> megaStones = new HashMap<>();

    public SpeciesVocabulary(JsonNode regulation, JsonNode learnsets, JsonNode vocabulary) {
        Set<String> noise = new HashSet<>();
        vocabulary.path("form_noise").forEach(n -> noise.add(n.asText()));

        // Form words, from the learnsets' alternate forms ("Hisuian Form") and the regulation's
        // allowed regional forms ("Paldea-Combat").
        Map<String, Set<String>> formWords = new HashMap<>();
        learnsets.path("species").fields().forEachRemaining(e ->
                e.getValue().path("alternate_forms").forEach(form ->
                        formWords.computeIfAbsent(e.getKey(), k -> new HashSet<>())
                                .addAll(SpeciesNames.words(form.path("name").asText()))));
        regulation.path("regional_forms_allowed").forEach(r ->
                formWords.computeIfAbsent(r.path("base").asText(), k -> new HashSet<>())
                        .addAll(SpeciesNames.words(r.path("form").asText())));

        // Megas by base species name, from the stones ("Charizard-Y": "Charizardite Y").
        Map<String, List<String>> stonesByBase = new HashMap<>();
        regulation.path("mega_stones").fields().forEachRemaining(e -> {
            List<String> parts = new ArrayList<>(List.of(e.getKey().split("-")));
            if (parts.size() > 1 && List.of("x", "y", "z").contains(parts.get(parts.size() - 1).toLowerCase(java.util.Locale.ROOT))) {
                parts.remove(parts.size() - 1);
            }
            stonesByBase.computeIfAbsent(String.join("-", parts), k -> new ArrayList<>())
                    .add(SpeciesNames.toId(e.getValue().asText()));
        });

        // Every species the regulation or its learnsets name, in the app's (sorted) order: the
        // first of two equally long matches wins, as in the app.
        Set<String> names = new TreeSet<>();
        regulation.path("species_whitelist").forEach(n -> names.add(n.asText()));
        learnsets.path("species").fieldNames().forEachRemaining(names::add);
        Map<String, Species> byId = new LinkedHashMap<>();
        for (String name : names) {
            Set<String> forms = new HashSet<>(formWords.getOrDefault(name, Set.of()));
            forms.removeAll(noise);
            var species = new Species(SpeciesNames.toId(name), name, SpeciesNames.tokens(name), forms);
            byId.putIfAbsent(species.id(), species);
            if (!species.words().isEmpty()) {
                byFirstWord.computeIfAbsent(species.words().get(0), k -> new ArrayList<>()).add(species);
            }
            for (String stone : stonesByBase.getOrDefault(name, List.of())) {
                megaStones.putIfAbsent(stone, species.id());
            }
        }
    }

    /**
     * A Limitless member's species, from its slug ("arcanine-hisui") when there is one, otherwise
     * its display name ("Hisuian Arcanine"). A species outside the regulation keeps its slug or
     * name as its ID.
     */
    public Identity identity(String name, String slug) {
        if (slug != null && !slug.isEmpty()) {
            var hit = match(SpeciesNames.words(slug), true);
            if (hit != null) return hit;
        }
        var hit = match(SpeciesNames.words(name == null ? "" : name), false);
        if (hit != null) return hit;
        return new Identity(SpeciesNames.toId(slug != null && !slug.isEmpty() ? slug : name == null ? "" : name), Set.of());
    }

    /** The stone ID when the held item is one of the species' own Mega Stones, else null. */
    public String megaStone(String heldItem, String speciesId) {
        if (heldItem == null) return null;
        String stone = SpeciesNames.toId(heldItem);
        return speciesId.equals(megaStones.get(stone)) ? stone : null;
    }

    /** The longest species whose words appear: at the start for a slug, anywhere for a name. */
    private Identity match(List<String> words, boolean prefixOnly) {
        Species best = null;
        int bestStart = 0;
        for (int start = 0; start < words.size(); start++) {
            if (prefixOnly && start > 0) break;
            for (Species candidate : byFirstWord.getOrDefault(words.get(start), List.of())) {
                int end = start + candidate.words().size();
                if (end > words.size() || !words.subList(start, end).equals(candidate.words())) continue;
                if (best == null || candidate.words().size() > best.words().size()) {
                    best = candidate;
                    bestStart = start;
                }
            }
        }
        if (best == null) return null;
        Set<String> forms = new HashSet<>();
        for (int i = 0; i < words.size(); i++) {
            boolean inMatch = i >= bestStart && i < bestStart + best.words().size();
            if (!inMatch && best.formWords().contains(words.get(i))) forms.add(words.get(i));
        }
        return new Identity(best.id(), forms);
    }
}
