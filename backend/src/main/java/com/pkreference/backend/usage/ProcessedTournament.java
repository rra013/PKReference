package com.pkreference.backend.usage;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;

/** Marker written in the same transaction as the counters, so replays never double-count. */
@Entity
public class ProcessedTournament {
    @Id
    private String id;

    /** For Hibernate, which builds entities through a no-argument constructor. */
    protected ProcessedTournament() {}

    /** Marks the event with this id as counted. */
    public ProcessedTournament(String id) {
        this.id = id;
    }

    public String getId() {
        return id;
    }
}
