package com.careconnect.repository.ai.ask;

import com.careconnect.model.ai.ask.AskAiOcrOutbox;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AskAiOcrOutboxRepository extends JpaRepository<AskAiOcrOutbox, Long> {

    Optional<AskAiOcrOutbox> findByFileId(Long fileId);

    @Query("""
            SELECT o FROM AskAiOcrOutbox o
            WHERE o.status IN ('PENDING', 'FAILED')
              AND o.attempts < :maxAttempts
              AND o.updatedAt <= :staleBefore
            ORDER BY o.updatedAt ASC
            """)
    List<AskAiOcrOutbox> findRetryable(
            @Param("maxAttempts") int maxAttempts,
            @Param("staleBefore") Instant staleBefore,
            Pageable pageable);
}
