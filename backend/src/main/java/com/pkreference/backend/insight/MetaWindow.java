package com.pkreference.backend.insight;

import java.time.Duration;
import java.time.Instant;
import java.util.Locale;

/** The time a response covers: the last 14 or 30 days, or the whole regulation (every stored event). */
public enum MetaWindow {
    DAYS_14("14d", Duration.ofDays(14)),
    DAYS_30("30d", Duration.ofDays(30)),
    REGULATION("regulation", null);

    private final String id;
    private final Duration length;

    MetaWindow(String id, Duration length) {
        this.id = id;
        this.length = length;
    }

    public String id() {
        return id;
    }

    /** The window's start, or null for the whole regulation. */
    public Instant from(Instant now) {
        return length == null ? null : now.minus(length);
    }

    /** "14d", "30d" or "regulation"; anything else is an error the caller reports. */
    public static MetaWindow parse(String text) {
        String t = text == null ? "30d" : text.toLowerCase(Locale.ROOT);
        for (MetaWindow w : values()) if (w.id.equals(t)) return w;
        throw new IllegalArgumentException("window must be 14d, 30d or regulation");
    }
}
