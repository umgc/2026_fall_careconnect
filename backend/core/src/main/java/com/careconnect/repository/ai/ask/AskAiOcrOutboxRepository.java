package com.careconnect.repository.ai.ask;

import com.careconnect.model.ai.ask.AskAiOcrOutbox;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AskAiOcrOutboxRepository extends JpaRepository<AskAiOcrOutbox, Long> {

    Optional<AskAiOcrOutbox> findByFileId(Long fileId);

    @Query("""
            SELECT o FROM AskAiOcrOutbox o
            WHERE o.status IN ('PENDING', 'FAILED', 'IN_PROGRESS')
              AND o.attempts < :maxAttempts
              AND o.updatedAt <= :staleBefore
            ORDER BY o.updatedAt ASC
            """)
    List<AskAiOcrOutbox> findRetryable(
            @Param("maxAttempts") int maxAttempts,
            @Param("staleBefore") Instant staleBefore,
            Pageable pageable);

    /**
     * Claims a row for processing (PENDING/FAILED/stale IN_PROGRESS → IN_PROGRESS).
     * Returns 1 when this caller won the claim.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE AskAiOcrOutbox o
            SET o.status = 'IN_PROGRESS',
                o.updatedAt = :now,
                o.attempts = o.attempts + 1,
                o.lastError = NULL
            WHERE o.id = :id
              AND o.attempts < :maxAttempts
              AND (
                    o.status IN ('PENDING', 'FAILED')
                 OR (o.status = 'IN_PROGRESS' AND o.updatedAt <= :staleBefore)
              )
            """)
    int claimForProcessing(
            @Param("id") Long id,
            @Param("maxAttempts") int maxAttempts,
            @Param("staleBefore") Instant staleBefore,
            @Param("now") Instant now);
}
