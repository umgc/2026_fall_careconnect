package com.careconnect.service.conditiondetection;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

/**
 * Unit tests for {@link ConditionScreeningCopy}. The disclaimer must appear on every surface
 * that shows a screening flag, and the Flutter app keeps its own copy in the ARB file, so this
 * reads that file (relative to {@code backend/core}, as Maven runs it) and fails if they drift.
 */
class ConditionScreeningCopyTest {

    private static final Path ARB = Path.of("..", "..", "frontend", "lib", "l10n", "app_en.arb");

    /** Scenario: someone edits the disclaimer in one place only. */
    @Test
    void disclaimer_matchesTheFlutterArbString() throws IOException {
        // Arrange
        final JsonNode arb = new ObjectMapper().readTree(Files.readString(ARB));

        // Act
        final String appCopy = arb.path("conditionFlags_disclaimer").asText(null);

        // Assert
        assertThat(appCopy).isEqualTo(ConditionScreeningCopy.DISCLAIMER_EN);
    }

    /** Scenario: the wording keeps the two statements the handoff guide requires. */
    @Test
    void disclaimer_saysItIsAScreeningFlagAndNotADiagnosis() {
        assertThat(ConditionScreeningCopy.DISCLAIMER_EN)
                .contains("screening flag")
                .contains("not a clinical diagnosis");
    }
}
