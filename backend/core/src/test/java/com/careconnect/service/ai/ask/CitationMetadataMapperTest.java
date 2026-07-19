package com.careconnect.service.ai.ask;

import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

class CitationMetadataMapperTest {

    private final CitationMetadataMapper mapper =
            new CitationMetadataMapper(new ObjectMapper());

    @Test
    void map_legacyOffsetFreeTranscriptTimestamp_isInterpretedAsUtc() {
        final CitationMetadataMapper.CitationMetadata metadata = mapper.map(
                RetrievalRecordType.TRANSCRIPT_SEGMENT,
                "{\"occurredAt\":\"2026-07-10T12:30:45\"}");

        assertThat(metadata.occurredAt()).isEqualTo(Instant.parse("2026-07-10T12:30:45Z"));
    }

    @Test
    void map_explicitOffsetTimestamp_preservesInstant() {
        final CitationMetadataMapper.CitationMetadata metadata = mapper.map(
                RetrievalRecordType.TRANSCRIPT_SEGMENT,
                "{\"occurredAt\":\"2026-07-10T08:30:45-04:00\"}");

        assertThat(metadata.occurredAt()).isEqualTo(Instant.parse("2026-07-10T12:30:45Z"));
    }
}
