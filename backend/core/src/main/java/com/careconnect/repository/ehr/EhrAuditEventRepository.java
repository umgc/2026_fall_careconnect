package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrAuditEvent;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * Append-only persistence for {@link EhrAuditEvent} (Findings R6).
 */
public interface EhrAuditEventRepository extends JpaRepository<EhrAuditEvent, Long> {
}
