package com.careconnect.repository.ai.audit;

import com.careconnect.model.ai.audit.AiAskAuditEvent;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

public interface AiAskAuditEventRepository extends JpaRepository<AiAskAuditEvent, UUID> {

    List<AiAskAuditEvent> findByAuditIdOrderByEventSequenceAsc(UUID auditId);

    @Query("select coalesce(max(e.eventSequence), 0) from AiAskAuditEvent e where e.auditId = :auditId")
    int findMaxSequence(@Param("auditId") UUID auditId);
}
