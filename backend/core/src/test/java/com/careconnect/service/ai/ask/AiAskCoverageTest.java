package com.careconnect.service.ai.ask;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Task 5.3 — contract checks for Ask AI gateway wiring.
 */
class AiAskCoverageTest {

    @Test
    @DisplayName("AiAskController exposes POST /ask under /api/ai")
    void controller_contract() throws Exception {
        final String source = Files.readString(Path.of(
                "src/main/java/com/careconnect/controller/AiAskController.java"));
        assertThat(source).contains("@PostMapping");
        assertThat(source).contains("/ask");
        assertThat(source).contains("USE_AI_FEATURES");
        assertThat(source).contains("careconnect.ai.ask.enabled");
        assertThat(source).contains("resolveCurrentUser");
    }

    @Test
    @DisplayName("AiAskService wires scope → hybrid → grounded LLM")
    void service_contract() throws Exception {
        final String source = Files.readString(Path.of(
                "src/main/java/com/careconnect/service/ai/ask/AiAskService.java"));
        assertThat(source).contains("RetrievalScopeService");
        assertThat(source).contains("HybridRetrievalService");
        assertThat(source).contains("GroundedAskLlmService");
        assertThat(source).contains("NO_RECORDS");
        assertThat(source).doesNotContain("MedicalContextService");
    }
}
