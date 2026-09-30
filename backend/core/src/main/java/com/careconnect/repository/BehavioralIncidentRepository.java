package com.careconnect.repository;

import com.careconnect.model.BehavioralIncident;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface BehavioralIncidentRepository extends JpaRepository<BehavioralIncident, Long> {
    List<BehavioralIncident> findByClientIdOrderByOccurredAtDesc(Long clientId);

    /**
     * For behavioral trends: incidents with occurred_at between start and end (inclusive), ascending.
     */
    List<BehavioralIncident> findByClientIdAndOccurredAtBetweenOrderByOccurredAtAsc(
            Long clientId, java.time.LocalDateTime start, java.time.LocalDateTime end);
}

