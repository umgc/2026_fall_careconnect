package com.careconnect.service.ai.ask;

import com.careconnect.service.ai.retrieval.RankedChunk;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class CitationDeepLinkBuilderTest {

    private final CitationDeepLinkBuilder builder = new CitationDeepLinkBuilder();

    @Test
    @DisplayName("builder emits only routes registered by the current Flutter router")
    void build_supportedTypes_useRegisteredRoutes() {
        assertThat(build(RetrievalRecordType.CALL_SUMMARY, "summary-1"))
                .isEqualTo("/chatandcalls");
        assertThat(build(RetrievalRecordType.UPLOADED_DOCUMENT, "file-1"))
                .isEqualTo("/file-management");
        assertThat(build(RetrievalRecordType.USPS_MAIL, "mail-1"))
                .isEqualTo("/informed-delivery");
        assertThat(build(RetrievalRecordType.MEDICATION, "med-1"))
                .isEqualTo("/medication");
        assertThat(build(RetrievalRecordType.TASK, "task-1"))
                .isEqualTo("/tasks");
        assertThat(build(RetrievalRecordType.EVV_RECORD, "evv-1"))
                .isEqualTo("/evv/visit-history");
        assertThat(build(RetrievalRecordType.VITAL_SIGN, "vital-1"))
                .isEqualTo("/wearables");
    }

    @Test
    @DisplayName("clinical-note identifiers are encoded and unsupported visit links stay null")
    void build_sourceSpecificRoutes_areSafeOrOmitted() {
        assertThat(build(RetrievalRecordType.CLINICAL_NOTE, "note/1"))
                .isEqualTo("/notetaker/detail/note%2F1");
        assertThat(build(RetrievalRecordType.VISIT_SUMMARY, "visit-1")).isNull();
    }

    private String build(final RetrievalRecordType type, final String sourceId) {
        return builder.build(
                new RankedChunk(
                        UUID.randomUUID(),
                        42L,
                        type,
                        sourceId,
                        "text",
                        null,
                        "auto",
                        0.1d,
                        1,
                        null,
                        "C1"),
                sourceId);
    }
}
