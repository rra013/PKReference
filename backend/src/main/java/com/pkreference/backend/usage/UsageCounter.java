package com.pkreference.backend.usage;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

/**
 * One counter row. category is TEAMS (species = "*", the format's team total), SPECIES (teams
 * running the species), or ITEM / ABILITY / MOVE / TERA / NATURE (value = what they ran).
 */
@Entity
@Table(indexes = @Index(columnList = "format, category, species"))
public class UsageCounter {
    public static final String TEAMS = "TEAMS";
    public static final String SPECIES = "SPECIES";
    public static final String TOTAL_SPECIES = "*";

    @Id
    private String id;
    private String format;
    private String category;
    private String species;
    private String value;
    private long count;

    protected UsageCounter() {}

    public UsageCounter(String format, String category, String species, String value) {
        this.id = key(format, category, species, value);
        this.format = format;
        this.category = category;
        this.species = species;
        this.value = value;
    }

    public static String key(String format, String category, String species, String value) {
        return format + "|" + category + "|" + species + "|" + value;
    }

    public void add(long n) {
        count += n;
    }

    public String getId() { return id; }
    public String getFormat() { return format; }
    public String getCategory() { return category; }
    public String getSpecies() { return species; }
    public String getValue() { return value; }
    public long getCount() { return count; }
}
