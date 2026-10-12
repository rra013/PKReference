package com.pkreference.backend.usage;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

/**
 * The counters' queries. There is no implementation in this project: Spring Data JPA writes one at
 * start-up. {@code JpaRepository<UsageCounter, String>} brings {@code findById},
 * {@code findAllById}, {@code saveAll} and the rest, and each method below is a query spelled as
 * its name: {@code findByFormatAndCategoryOrderByCountDesc} becomes
 * {@code where format = ? and category = ? order by count desc}.
 */
public interface UsageCounterRepository extends JpaRepository<UsageCounter, String> {
    /** A format's counters of one category, biggest first; {@code page} limits how many. */
    List<UsageCounter> findByFormatAndCategoryOrderByCountDesc(String format, String category, Pageable page);

    /** Everything counted about one Pokémon in a format, leaving out the categories given. */
    List<UsageCounter> findByFormatAndSpeciesAndCategoryNotInOrderByCountDesc(
            String format, String species, List<String> excluded);
}
