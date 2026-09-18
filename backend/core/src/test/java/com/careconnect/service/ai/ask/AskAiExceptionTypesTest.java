package com.careconnect.service.ai.ask;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

class AskAiExceptionTypesTest {

    @Test
    @DisplayName("AskAiUnavailableException defaults error code and 503")
    void unavailable_defaults() {
        final AskAiUnavailableException ex = new AskAiUnavailableException("bedrock down");
        assertThat(ex.getErrorCode()).isEqualTo("RETRIEVAL_UNAVAILABLE");
        assertThat(ex.getStatus()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        assertThat(ex.getMessage()).contains("bedrock down");
    }

    @Test
    @DisplayName("AskAiUnavailableException accepts custom code and null-code fallback")
    void unavailable_customAndNullCode() {
        final AskAiUnavailableException custom =
                new AskAiUnavailableException("CUSTOM_DOWN", "gone");
        assertThat(custom.getErrorCode()).isEqualTo("CUSTOM_DOWN");

        final UUID requestId = UUID.randomUUID();
        final AskAiUnavailableException withNullCode = new AskAiUnavailableException(
                requestId, null, null, null, "still down", new RuntimeException("cause"));
        assertThat(withNullCode.getErrorCode()).isEqualTo("RETRIEVAL_UNAVAILABLE");
        assertThat(withNullCode.getRequestId()).isEqualTo(requestId);
        assertThat(withNullCode.getCause()).isInstanceOf(RuntimeException.class);
    }

    @Test
    @DisplayName("AskAiGroundingException uses UNGROUNDED_RESPONSE and 502")
    void grounding_defaults() {
        final AskAiGroundingException simple = new AskAiGroundingException("bad citations");
        assertThat(simple.getErrorCode()).isEqualTo(AskAiGroundingException.ERROR_CODE);
        assertThat(simple.getStatus()).isEqualTo(HttpStatus.BAD_GATEWAY);

        final UUID auditId = UUID.randomUUID();
        final AskAiGroundingException full =
                new AskAiGroundingException(null, auditId, null, "ungrounded");
        assertThat(full.getAuditId()).isEqualTo(auditId);
        assertThat(full.getMessage()).contains("ungrounded");
    }
}
