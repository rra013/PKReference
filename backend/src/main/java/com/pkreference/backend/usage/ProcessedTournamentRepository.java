package com.pkreference.backend.usage;

import org.springframework.data.jpa.repository.JpaRepository;

/**
 * Which events have been counted. Spring Data writes the implementation; {@code existsById} and
 * {@code save} are all that's used.
 */
public interface ProcessedTournamentRepository extends JpaRepository<ProcessedTournament, String> {}
