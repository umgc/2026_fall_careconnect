package com.careconnect.repository.ai.hitl;

import com.careconnect.model.ai.hitl.AiSafetyAuditEvent;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface AiSafetyAuditEventRepository extends JpaRepository<AiSafetyAuditEvent, UUID> {
}
