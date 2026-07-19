package com.careconnect.indexing;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.DeserializationContext;
import com.fasterxml.jackson.databind.JsonDeserializer;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
import java.io.IOException;

/**
 * Body of the {@code TRANSCRIPT_INDEXED} event's {@code payload}
 * field. Emitted after a batch of transcript segments is persisted
 * for a call (WBS 3.11.1, #186).
 *
 * <p>Contract from Ravichandra Vasireddy's 2026-07-03 Transcript
 * Ingest and SUMMARY_CREATED Indexing Contract, section 2.7.
 *
 * <p>Legacy outbox rows may still carry {@code segmentCount}/{@code source}.
 * Deserialization prefers canonical {@code totalSegmentCount}/{@code snapshotVersion}
 * when both canonical and legacy keys are present, so dual-key payloads remain ingestible.
 *
 * @param callId       call identifier the segments belong to
 * @param patientId    patient the call is associated with; nullable
 *                     until the call telemetry lookup lands or the
 *                     caller can supply it directly
 * @param totalSegmentCount number of segments in the complete authoritative snapshot
 * @param snapshotVersion deterministic version of that complete snapshot
 */
@JsonIgnoreProperties(ignoreUnknown = true)
@JsonDeserialize(using = TranscriptIndexedPayload.Deserializer.class)
public record TranscriptIndexedPayload(
        String callId,
        Long patientId,
        @JsonProperty("totalSegmentCount")
        int totalSegmentCount,
        @JsonProperty("snapshotVersion")
        String snapshotVersion
) {

    /**
     * Prefers canonical field names over legacy aliases when both appear in JSON.
     */
    static final class Deserializer extends JsonDeserializer<TranscriptIndexedPayload> {
        @Override
        public TranscriptIndexedPayload deserialize(
                final JsonParser parser,
                final DeserializationContext context) throws IOException {
            final JsonNode node = parser.getCodec().readTree(parser);
            final String callId = textOrNull(node.get("callId"));
            final Long patientId = longOrNull(node.get("patientId"));
            final int totalSegmentCount = firstInt(
                    node.get("totalSegmentCount"),
                    node.get("segmentCount"),
                    0);
            final String snapshotVersion = firstText(
                    node.get("snapshotVersion"),
                    node.get("source"));
            return new TranscriptIndexedPayload(
                    callId, patientId, totalSegmentCount, snapshotVersion);
        }

        private static String textOrNull(final JsonNode node) {
            return node == null || node.isNull() ? null : node.asText();
        }

        private static Long longOrNull(final JsonNode node) {
            if (node == null || node.isNull() || !node.isNumber()) {
                return null;
            }
            return node.longValue();
        }

        private static int firstInt(
                final JsonNode preferred,
                final JsonNode fallback,
                final int defaultValue) {
            if (preferred != null && preferred.isNumber()) {
                return preferred.intValue();
            }
            if (fallback != null && fallback.isNumber()) {
                return fallback.intValue();
            }
            return defaultValue;
        }

        private static String firstText(final JsonNode preferred, final JsonNode fallback) {
            if (preferred != null && !preferred.isNull()) {
                return preferred.asText();
            }
            if (fallback != null && !fallback.isNull()) {
                return fallback.asText();
            }
            return null;
        }
    }
}
