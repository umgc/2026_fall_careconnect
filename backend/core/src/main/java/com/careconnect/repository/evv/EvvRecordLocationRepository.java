package com.careconnect.repository.evv;

import com.careconnect.model.evv.EvvRecordLocation;
import com.careconnect.model.evv.EvvLocationRole;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface EvvRecordLocationRepository extends JpaRepository<EvvRecordLocation, UUID> {

    /**
     * Find a specific location by EVV record ID and role (CHECK_IN or CHECK_OUT)
     */
    Optional<EvvRecordLocation> findByEvvRecordIdAndRole(Long evvRecordId, EvvLocationRole role);

    /**
     * Find all locations for a specific EVV record
     */
    List<EvvRecordLocation> findByEvvRecordId(Long evvRecordId);

    /**
     * Delete a specific location by EVV record ID and role
     */
    void deleteByEvvRecordIdAndRole(Long evvRecordId, EvvLocationRole role);

    /**
     * Check if a location exists for a specific EVV record and role
     */
    boolean existsByEvvRecordIdAndRole(Long evvRecordId, EvvLocationRole role);
}

