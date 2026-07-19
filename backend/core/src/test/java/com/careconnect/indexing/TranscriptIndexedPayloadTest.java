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
}
