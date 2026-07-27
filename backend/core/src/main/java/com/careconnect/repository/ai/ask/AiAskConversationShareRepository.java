package com.careconnect.repository.ai.ask;

import com.careconnect.model.ai.ask.AiAskConversationShare;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AiAskConversationShareRepository extends JpaRepository<AiAskConversationShare, UUID> {

    Optional<AiAskConversationShare> findFirstByPatientIdAndSharedByUserIdAndTranscriptSha256OrderByCreatedAtDesc(
            Long patientId, Long sharedByUserId, String transcriptSha256);

    List<AiAskConversationShare> findByPatientIdOrderByCreatedAtDesc(Long patientId);
}
