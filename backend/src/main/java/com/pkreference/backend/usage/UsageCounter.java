package com.pkreference.backend.usage;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

/**
 * One counter row. category is TEAMS (species = "*", the format's team total), SPECIES (teams
 * running the species), or ITEM / ABILITY / MOVE / TERA / NATURE (value = what they ran).
 *
 * <p>A JPA entity: {@code @Entity} tells Hibernate that objects of this class are rows of a table
 * (named after the class, usage_counter), {@code @Id} marks the primary key and {@code @Column}
 * names a column that differs from its field. Hibernate needs the no-argument constructor to build
 * objects from rows. The table itself is made by Flyway (V1); with {@code ddl-auto: validate},
 * Hibernate only checks at start-up that the two agree.
 *
 * <p>This and ProcessedTournament are the only JPA entities. Everything newer uses JdbcTemplate and
 * plain SQL, which reads more directly for bulk replaces and reporting queries.
 */
@Entity
@Table(indexes = @Index(columnList = "fmt, category, species"))
public class UsageCounter {
    public static final String TEAMS = "TEAMS";
    public static final String SPECIES = "SPECIES";
    public static final String TOTAL_SPECIES = "*";

    @Id
    private String id;
    @Column(name = "fmt")
    private String format;
    private String category;
    private String species;
    @Column(name = "val")
    private String value;
    @Column(name = "n")
    private long count;

    protected UsageCounter() {}

    /** A new counter at zero, with its key made from the four parts. */
    public UsageCounter(String format, String category, String species, String value) {
        this.id = key(format, category, species, value);
        this.format = format;
        this.category = category;
        this.species = species;
        this.value = value;
    }

    /** The row's primary key: the four parts joined, so a counter can be fetched by what it counts. */
    public static String key(String format, String category, String species, String value) {
        return format + "|" + category + "|" + species + "|" + value;
    }

    /** Adds to the count. Hibernate notices the change and writes it when the transaction commits. */
    public void add(long n) {
        count += n;
    }

    /**
     * Accessors, for Hibernate and the controller. Entities are ordinary mutable classes, not
     * records: Hibernate fills and tracks their fields.
     */
    public String getId() { return id; }
    public String getFormat() { return format; }
    public String getCategory() { return category; }
    public String getSpecies() { return species; }
    public String getValue() { return value; }
    public long getCount() { return count; }
}
