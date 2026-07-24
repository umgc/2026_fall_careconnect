package com.careconnect.dto.ai;

import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.annotation.JsonAnySetter;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.UUID;

/**
 * Request body for {@code POST /api/ai/ask} (Task 5.3).
 *
 * <p>Caller identity comes from JWT — do not send {@code userId}.
 */
@JsonIgnoreProperties(ignoreUnknown = false)
public record AiAskRequest(
        @NotBlank @Size(max = 2000) String query,
        @NotNull @Positive Long patientId,
        UUID sessionId,
        UUID conversationId,
        InputModality inputModality,
        @Size(max = 16) String locale,
        @Size(max = 16) List<@NotNull RetrievalRecordType> sourceTypes
) {
    @JsonAnySetter
    public void rejectUnknownField(final String fieldName, final Object ignoredValue) {
        throw new IllegalArgumentException("Unknown Ask AI request field");
    }
}
