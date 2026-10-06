package com.pkreference.backend.standardize;

import java.text.Normalizer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * The app's name helpers, ported rule for rule so species keys match it: toID (ShowdownCalc.swift),
 * LimitlessSpeciesResolver.words (LimitlessTeamImport.swift) and TeamQueryParser.tokens. The golden
 * file golden/species-identity.json checks the result against the app.
 */
public final class SpeciesNames {
    private SpeciesNames() {}

    static final Map<String, String> REGION_WORDS = Map.of(
            "alolan", "alola", "galarian", "galar", "hisuian", "hisui", "paldean", "paldea");

    /** Region adjectives, and Limitless's "f"/"m" for gender forms. */
    private static final Map<String, String> WORD_SUBSTITUTIONS;

    static {
        var subs = new HashMap<String, String>(Map.of("f", "female", "m", "male"));
        subs.putAll(REGION_WORDS);
        WORD_SUBSTITUTIONS = Map.copyOf(subs);
    }

    /** A Showdown-style form suffix after a hyphen: "arcanine-h", "indeedee-f". */
    private static final Map<String, String> FORM_SUFFIXES = Map.of(
            "h", "hisui", "a", "alola", "g", "galar", "p", "paldea", "f", "female", "m", "male");

    /** Lowercases and keeps only [a-z0-9], as Showdown's toID. */
    public static String toId(String text) {
        String lower = text.toLowerCase(Locale.ROOT);
        if (lower.equals("flabébé")) return "flabebe";
        var out = new StringBuilder(lower.length());
        for (int i = 0; i < lower.length(); i++) {
            char c = lower.charAt(i);
            if (isAsciiLetterOrDigit(c)) out.append(c);
        }
        return out.toString();
    }

    /** Lowercased ASCII words, accents folded, region adjectives and gender marks normalized. */
    public static List<String> words(String name) {
        String folded = fold(name).replace("♀", " female ").replace("♂", " male ");
        List<String> words = new ArrayList<>();
        var current = new StringBuilder();
        for (int i = 0; i <= folded.length(); i++) {
            char c = i < folded.length() ? folded.charAt(i) : ' ';
            if (isAsciiLetterOrDigit(c)) {
                current.append(c);
            } else if (!current.isEmpty()) {
                String word = current.toString();
                words.add(WORD_SUBSTITUTIONS.getOrDefault(word, word));
                current.setLength(0);
            }
        }
        return words;
    }

    /** The query parser's words, with a form suffix after a hyphen spelled out ("arcanine-h"). */
    public static List<String> tokens(String text) {
        String folded = fold(text).replace("♀", " female ").replace("♂", " male ");
        List<String> tokens = new ArrayList<>();
        var current = new StringBuilder();
        boolean afterHyphen = false;
        boolean currentFollowsHyphen = false;
        for (int i = 0; i <= folded.length(); i++) {
            boolean end = i == folded.length();
            char c = end ? ' ' : folded.charAt(i);
            if (!end && isAsciiLetterOrDigit(c)) {
                if (current.isEmpty()) currentFollowsHyphen = afterHyphen;
                current.append(c);
                afterHyphen = false;
            } else {
                boolean wordEnded = !current.isEmpty();
                if (wordEnded) {
                    String word = current.toString();
                    String expanded = currentFollowsHyphen ? FORM_SUFFIXES.get(word) : null;
                    tokens.add(expanded != null ? expanded : REGION_WORDS.getOrDefault(word, word));
                    current.setLength(0);
                }
                afterHyphen = c == '-' && wordEnded;
                if (c == ',') tokens.add(",");
            }
        }
        return tokens;
    }

    /** Accents removed and lowercased, as Swift's case- and diacritic-insensitive folding. */
    private static String fold(String s) {
        return Normalizer.normalize(s, Normalizer.Form.NFD).replaceAll("\\p{M}+", "").toLowerCase(Locale.ROOT);
    }

    private static boolean isAsciiLetterOrDigit(char c) {
        return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
    }
}
