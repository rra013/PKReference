package com.pkreference.backend.usage;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface UsageCounterRepository extends JpaRepository<UsageCounter, String> {
    List<UsageCounter> findByFormatAndCategoryOrderByCountDesc(String format, String category, Pageable page);

    List<UsageCounter> findByFormatAndSpeciesAndCategoryNotInOrderByCountDesc(
            String format, String species, List<String> excluded);
}
