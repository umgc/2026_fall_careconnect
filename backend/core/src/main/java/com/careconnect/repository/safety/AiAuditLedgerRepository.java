package com.careconnect.repository.safety;

import com.careconnect.model.safety.AiAuditLedger;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

/** WBS 3.15.6
 * read-only queries for the audit ledger */
@Repository
public interface AiAuditLedgerRepository extends JpaRepository<AiAuditLedger, Long> {

    // TODO: research if list is standard or if there are bounds on list results
    List<AiAuditLedger> findByActorUserIdOrderByOccurredAtDesc(Long actorUserId);

    List<AiAuditLedger> findByPatientIdOrderByOccurredAtDesc(Long patientId);

    List<AiAuditLedger> findBySessionIdOrderByOccurredAtAsc(String sessionId);

    List<AiAuditLedger> findByEventTypeAndSourceFeatureOrderByOccurredAtDesc(
            String eventType, String sourceFeature);
}
