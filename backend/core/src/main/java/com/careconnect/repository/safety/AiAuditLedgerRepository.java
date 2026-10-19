package com.careconnect.repository.safety;

import com.careconnect.model.safety.AiAuditLedger;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * WBS 3.15.6
 * read-only queries for the audit ledger.
 * <p>
 * Each finder has an unbounded version (for callers that need the
 * full history, like the compliance export) and an overload that
 * creates a bound for the result. The paged overload is good for for UI / API reads,
 * where an actor or patient can create a lot of events.
 */
@Repository
public interface AiAuditLedgerRepository extends JpaRepository<AiAuditLedger, Long> {

    List<AiAuditLedger> findByActorUserIdOrderByOccurredAtDesc(Long actorUserId);

    Page<AiAuditLedger> findByActorUserIdOrderByOccurredAtDesc(Long actorUserId, Pageable pageable);

    List<AiAuditLedger> findByPatientIdOrderByOccurredAtDesc(Long patientId);

    Page<AiAuditLedger> findByPatientIdOrderByOccurredAtDesc(Long patientId, Pageable pageable);

    List<AiAuditLedger> findBySessionIdOrderByOccurredAtAsc(String sessionId);

    List<AiAuditLedger> findByEventTypeAndSourceFeatureOrderByOccurredAtDesc(
            String eventType, String sourceFeature);

    Page<AiAuditLedger> findByEventTypeAndSourceFeatureOrderByOccurredAtDesc(
            String eventType, String sourceFeature, Pageable pageable);
}
