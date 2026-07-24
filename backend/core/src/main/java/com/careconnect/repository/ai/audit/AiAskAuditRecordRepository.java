package com.careconnect.repository.ai.audit;

import com.careconnect.model.ai.audit.AiAskAuditRecord;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface AiAskAuditRecordRepository extends JpaRepository<AiAskAuditRecord, UUID> {

    Optional<AiAskAuditRecord> findByRequestId(UUID requestId);
}
