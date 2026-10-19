package com.careconnect.repository;

import com.careconnect.model.ActivityLog;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ActivityLogRepository extends JpaRepository<ActivityLog, Long> {
    java.util.List<ActivityLog> findByClientIdOrderByCreatedAtDesc(Long clientId, org.springframework.data.domain.Pageable pageable);

    /**
     * For competency trends: logs for client between start and end (inclusive), ascending.
     */
    java.util.List<ActivityLog> findByClientIdAndCreatedAtBetweenOrderByCreatedAtAsc(
            Long clientId, java.time.LocalDateTime start, java.time.LocalDateTime end);
}

