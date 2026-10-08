package com.careconnect.service.ehr.athena;

import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.JSON;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Covers what {@link InlineBinary} removes and, as importantly, what it leaves alone: elements that
 * are also named {@code data} but are not Attachments.
 */
class InlineBinaryTest {

    @Test
    @DisplayName("nested Attachment data is removed and the rest of the Attachment kept")
    void nestedAttachmentDataIsRemoved() {
        // Arrange
        final ObjectNode observation = JSON.createObjectNode().put("resourceType", "Observation");
        observation.putArray("component").addObject().putObject("valueAttachment")
                .put("contentType", "application/pdf").put("data", "JVBERi0=").put("title", "ECG");

        // Act
        final InlineBinary.Stripped result = InlineBinary.strip(observation);

        // Assert
        assertTrue(result.stripped());
        final var attachment = result.body().path("component").path(0).path("valueAttachment");
        assertFalse(attachment.has("data"));
        assertEquals("ECG", attachment.path("title").asText());
    }

    @Test
    @DisplayName("SampledData.data has no contentType and is not mistaken for a file")
    void sampledDataIsKept() {
        // Arrange
        final ObjectNode observation = JSON.createObjectNode().put("resourceType", "Observation");
        observation.putObject("valueSampledData").put("data", "1 2 3").put("period", 10);

        // Act
        final InlineBinary.Stripped result = InlineBinary.strip(observation);

        // Assert
        assertFalse(result.stripped());
        assertEquals("1 2 3", result.body().path("valueSampledData").path("data").asText());
    }

    @Test
    @DisplayName("a resource with nothing to strip comes back equal and unflagged")
    void nothingToStrip() {
        final ObjectNode condition = JSON.createObjectNode().put("resourceType", "Condition").put("id", "c-1");
        final InlineBinary.Stripped result = InlineBinary.strip(condition);
        assertFalse(result.stripped());
        assertEquals(condition, result.body());
    }
}
