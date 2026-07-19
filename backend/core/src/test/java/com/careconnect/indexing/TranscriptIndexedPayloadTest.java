package com.careconnect.indexing;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class TranscriptIndexedPayloadTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void deserializesCanonicalFields() throws Exception {
        final String json = """
                {"callId":"call-1","patientId":42,"totalSegmentCount":3,"snapshotVersion":"sha256:v1"}
                """;

        final TranscriptIndexedPayload payload =
                objectMapper.readValue(json, TranscriptIndexedPayload.class);

        assertThat(payload.callId()).isEqualTo("call-1");
        assertThat(payload.patientId()).isEqualTo(42L);
        assertThat(payload.totalSegmentCount()).isEqualTo(3);
        assertThat(payload.snapshotVersion()).isEqualTo("sha256:v1");
    }

    @Test
    void deserializesLegacySegmentCountAndSourceAliases() throws Exception {
        final String json = """
                {"callId":"call-legacy","patientId":7,"segmentCount":5,"source":"CLIENT_TRANSCRIPT"}
                """;

        final TranscriptIndexedPayload payload =
                objectMapper.readValue(json, TranscriptIndexedPayload.class);

        assertThat(payload.callId()).isEqualTo("call-legacy");
        assertThat(payload.patientId()).isEqualTo(7L);
        assertThat(payload.totalSegmentCount()).isEqualTo(5);
        assertThat(payload.snapshotVersion()).isEqualTo("CLIENT_TRANSCRIPT");
    }

    @Test
    void prefersCanonicalFieldsWhenDualKeysPresent() throws Exception {
        final String json = """
                {"callId":"call-dual","patientId":9,"totalSegmentCount":4,"segmentCount":99,\
                "snapshotVersion":"sha256:canonical","source":"LEGACY_SOURCE","unknownField":true}
                """;

        final TranscriptIndexedPayload payload =
                objectMapper.readValue(json, TranscriptIndexedPayload.class);

        assertThat(payload.callId()).isEqualTo("call-dual");
        assertThat(payload.patientId()).isEqualTo(9L);
        assertThat(payload.totalSegmentCount()).isEqualTo(4);
        assertThat(payload.snapshotVersion()).isEqualTo("sha256:canonical");
    }

    @Test
    void serializesOnlyCanonicalFieldNames() throws Exception {
        final TranscriptIndexedPayload payload =
                new TranscriptIndexedPayload("call-out", 3L, 2, "sha256:out");

        final String json = objectMapper.writeValueAsString(payload);

        assertThat(json).contains("\"totalSegmentCount\":2");
        assertThat(json).contains("\"snapshotVersion\":\"sha256:out\"");
        assertThat(json).doesNotContain("segmentCount");
        assertThat(json).doesNotContain("\"source\"");
    }
}
