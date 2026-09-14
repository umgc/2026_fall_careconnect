package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrAuditEvent;
import org.springframework.data.jpa.repository.JpaRepository;

public interface EhrAuditEventRepository extends JpaRepository<EhrAuditEvent, Long> {
}
