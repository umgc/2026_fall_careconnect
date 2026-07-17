package com.careconnect.dto.ai;

import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.UUID;

/**
 * Request body for {@code POST /api/ai/ask} (Task 5.3).
 *
 * <p>Caller identity comes from JWT — do not send {@code userId}.
 */
public record AiAskRequest(
        @NotBlank @Size(max = 2000) String query,
        @NotNull Long patientId,
        UUID sessionId,
        UUID conversationId,
        InputModality inputModality,
        @Size(max = 16) String locale,
        List<RetrievalRecordType> sourceTypes,
        @Size(max = 64) String clientRequestId,
        Boolean includeDebugRetrieval
) {
}
