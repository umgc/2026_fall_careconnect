package com.careconnect.repository.evv;

import com.careconnect.model.evv.EvvAuditEvent;
import org.springframework.data.jpa.repository.JpaRepository;


public interface EvvAuditEventRepository extends JpaRepository<EvvAuditEvent, Long> {
}
