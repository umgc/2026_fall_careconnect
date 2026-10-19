package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrSource;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface EhrSourceRepository extends JpaRepository<EhrSource, Long> {

    /**
     * Resolves a seeded source code such as ATHENAHEALTH to its row. Adapters call this once
     * and reuse the id; an unknown code returns empty rather than creating a source.
     */
    Optional<EhrSource> findByCode(String code);
}
