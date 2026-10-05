package com.pkreference.backend.standardize;

import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** Canonical spellings for one kind of name, with exact (normalized) and typo-tolerant lookup. */
final class NameDictionary {
    private final Map<String, String> byKey;

    NameDictionary(Collection<String> names) {
        byKey = new LinkedHashMap<>();
        names.forEach(n -> byKey.putIfAbsent(key(n), n));
    }

    /** Lowercase letters and digits only: "Fake-out", "FAKE OUT" and "Fake Out" all become "fakeout". */
    static String key(String raw) {
        var sb = new StringBuilder(raw.length());
        for (char c : raw.toLowerCase(Locale.ROOT).toCharArray()) {
            if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) sb.append(c);
        }
        return sb.toString();
    }

    /**
     * Exact match here, then exact in {@code fallback}, then a unique near-miss in this dictionary
     * and then in {@code fallback}; otherwise the input title-cased, so unknown names still merge
     * across casing.
     */
    String resolve(String raw, NameDictionary fallback) {
        String k = key(raw);
        String hit = byKey.get(k);
        if (hit == null && fallback != null) hit = fallback.byKey.get(k);
        if (hit == null) hit = nearest(k);
        if (hit == null && fallback != null) hit = fallback.nearest(k);
        return hit != null ? hit : titleCase(raw);
    }

    /**
     * A single candidate within a small edit distance sharing the first letter. A tie returns
     * null instead of guessing. Short names need an exact match.
     */
    private String nearest(String k) {
        int max = maxDistance(k.length());
        if (max == 0) return null;
        String best = null;
        int bestDistance = max + 1;
        boolean tie = false;
        for (var e : byKey.entrySet()) {
            String candidate = e.getKey();
            if (candidate.isEmpty() || candidate.charAt(0) != k.charAt(0)) continue;
            if (Math.abs(candidate.length() - k.length()) > max) continue;
            int d = distance(k, candidate, max);
            if (d > max) continue;
            if (d < bestDistance) {
                best = e.getValue();
                bestDistance = d;
                tie = false;
            } else if (d == bestDistance && !e.getValue().equals(best)) {
                tie = true;
            }
        }
        return tie ? null : best;
    }

    private static int maxDistance(int length) {
        if (length < 5) return 0;
        return length < 10 ? 1 : 2;
    }

    /** Optimal string alignment distance (edits, plus swapping two adjacent letters), capped. */
    static int distance(String a, String b, int cap) {
        int[][] d = new int[a.length() + 1][b.length() + 1];
        for (int i = 0; i <= a.length(); i++) d[i][0] = i;
        for (int j = 0; j <= b.length(); j++) d[0][j] = j;
        for (int i = 1; i <= a.length(); i++) {
            int rowMin = Integer.MAX_VALUE;
            for (int j = 1; j <= b.length(); j++) {
                int cost = a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1;
                d[i][j] = Math.min(Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + cost);
                if (i > 1 && j > 1 && a.charAt(i - 1) == b.charAt(j - 2) && a.charAt(i - 2) == b.charAt(j - 1)) {
                    d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
                }
                rowMin = Math.min(rowMin, d[i][j]);
            }
            if (rowMin > cap) return cap + 1;
        }
        return d[a.length()][b.length()];
    }

    /** "life  ORB" -> "Life Orb"; capitalizes after spaces and hyphens ("never-melt ice" -> "Never-Melt Ice"). */
    static String titleCase(String raw) {
        var sb = new StringBuilder();
        boolean upper = true;
        for (char c : raw.trim().toLowerCase(Locale.ROOT).toCharArray()) {
            if (Character.isWhitespace(c)) {
                if (sb.length() > 0 && sb.charAt(sb.length() - 1) != ' ') sb.append(' ');
                upper = true;
                continue;
            }
            sb.append(upper ? Character.toUpperCase(c) : c);
            upper = c == '-';
        }
        return sb.toString();
    }

    static final class Builder {
        private final List<String> names = new ArrayList<>();

        void add(String name) {
            if (name != null && !name.isBlank()) names.add(name.trim());
        }

        void addAll(Builder other) {
            names.addAll(other.names);
        }

        NameDictionary build() {
            return new NameDictionary(names);
        }
    }
}
