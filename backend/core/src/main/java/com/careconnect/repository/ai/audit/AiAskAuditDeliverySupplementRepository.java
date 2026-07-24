package com.careconnect.repository.ai.audit;

import com.careconnect.model.ai.audit.AiAskAuditDeliverySupplement;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface AiAskAuditDeliverySupplementRepository
        extends JpaRepository<AiAskAuditDeliverySupplement, UUID> {
}
