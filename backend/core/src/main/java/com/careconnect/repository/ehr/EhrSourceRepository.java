package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrSource;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** Lookup for the registry of integrated EHR systems. */
public interface EhrSourceRepository extends JpaRepository<EhrSource, Long> {

    /** Finds a source by its stable machine code, for example {@code ATHENA}. */
    Optional<EhrSource> findByCode(String code);
}
