package com.pkreference.backend.ladder;

import java.util.Collection;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * One of Smogon's Champions ladder formats, read from its id: "gen9championsvgc2026regmc" is M-C
 * doubles, with "bo3" on the end best of three; "gen9championsbssregmc" is M-C singles (Battle
 * Stadium Singles). The doubles id has the year in it, so formats are found by this pattern in
 * Smogon's listing, never built from a regulation.
 */
public record LadderFormat(String id, String regulation, String mode, int bestOf) {
    public static final String DOUBLES = "doubles";
    public static final String SINGLES = "singles";

    /**
     * "gen", digits, "champions", then "vgc" and a year or "bss", then "reg" and the regulation's
     * letters, then optionally "bo3". The regulation's group is reluctant ({@code +?}) so that a
     * trailing "bo3" is matched as best-of-three rather than as part of the regulation.
     */
    private static final Pattern ID = Pattern.compile("^gen\\d+champions(vgc\\d{4}|bss)reg([a-z0-9]+?)(bo3)?$");

    /**
     * Null when the id isn't a Champions doubles or singles ladder, or its regulation isn't one of
     * `regulations` (Limitless ids such as "m-c", in any case).
     */
    public static LadderFormat parse(String id, Collection<String> regulations) {
        Matcher m = ID.matcher(id);
        if (!m.matches()) return null;
        // Smogon writes the regulation without its hyphen: "mc".
        String regulation = regulations.stream()
                .filter(r -> r.replace("-", "").equalsIgnoreCase(m.group(2)))
                .findFirst().orElse(null);
        if (regulation == null) return null;
        return new LadderFormat(id, regulation.toUpperCase(Locale.ROOT),
                m.group(1).equals("bss") ? SINGLES : DOUBLES, m.group(3) == null ? 1 : 3);
    }
}
