package com.careconnect.repository.ai.ask;

import com.careconnect.model.ai.ask.AiAskConfirmationDecision;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface AiAskConfirmationDecisionRepository
        extends JpaRepository<AiAskConfirmationDecision, UUID> {

    Optional<AiAskConfirmationDecision>
            findFirstBySessionIdAndPatientIdAndCallerUserIdAndDecisionOrderByCreatedAtDesc(
                    UUID sessionId,
                    Long patientId,
                    Long callerUserId,
                    String decision);

    boolean existsByRequestIdAndCallerUserIdAndDecision(
            UUID requestId, Long callerUserId, String decision);

    Optional<AiAskConfirmationDecision>
            findFirstByRequestIdAndCallerUserIdAndDecisionOrderByCreatedAtDesc(
                    UUID requestId, Long callerUserId, String decision);
}
