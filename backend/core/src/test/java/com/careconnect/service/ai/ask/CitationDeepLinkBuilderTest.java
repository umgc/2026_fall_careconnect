package com.careconnect.service.ai.ask;

import com.careconnect.service.ai.retrieval.RankedChunk;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.service.ai.indexing.SummarySourceKey;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class CitationDeepLinkBuilderTest {

    private final CitationDeepLinkBuilder builder = new CitationDeepLinkBuilder();

    @Test
    @DisplayName("generic feature pages are not emitted as citation destinations")
    void build_genericFeaturePages_areOmitted() {
        assertThat(build(RetrievalRecordType.CALL_SUMMARY, "summary-1"))
                .isNull();
        assertThat(build(RetrievalRecordType.UPLOADED_DOCUMENT, "file-1"))
                .isNull();
        assertThat(build(RetrievalRecordType.USPS_MAIL, "mail-1"))
                .isNull();
        assertThat(build(RetrievalRecordType.MEDICATION, "med-1"))
                .isNull();
        assertThat(build(RetrievalRecordType.TASK, "task-1"))
                .isNull();
        assertThat(build(RetrievalRecordType.EVV_RECORD, "evv-1"))
                .isNull();
        assertThat(build(RetrievalRecordType.VITAL_SIGN, "vital-1"))
                .isNull();
    }

    @Test
    @DisplayName("routes requiring transient Flutter state are omitted")
    void build_sourceSpecificRoutes_areOmitted() {
        assertThat(build(RetrievalRecordType.CLINICAL_NOTE, "note-1_2.3")).isNull();
        assertThat(build(RetrievalRecordType.CLINICAL_NOTE, "note/1")).isNull();
        assertThat(build(RetrievalRecordType.CLINICAL_NOTE, "#fragment")).isNull();
        assertThat(build(RetrievalRecordType.CLINICAL_NOTE, "..")).isNull();
        assertThat(build(RetrievalRecordType.VISIT_SUMMARY, "visit-1")).isNull();
    }

    @Test
    @DisplayName("shared summary child routes depend on source ownership")
    void build_sharedSummaryType_routesOnlyCallOwnedRows() {
        assertThat(build(
                RetrievalRecordType.SUMMARY_APPOINTMENT,
                SummarySourceKey.CALL_KIND,
                "call-summary:1")).isNull();
        assertThat(build(
                RetrievalRecordType.SUMMARY_APPOINTMENT,
                SummarySourceKey.VISIT_KIND,
                "visit-summary:1")).isNull();
    }

    private String build(final RetrievalRecordType type, final String sourceId) {
        return build(type, null, sourceId);
    }

    private String build(
            final RetrievalRecordType type,
            final String sourceKind,
            final String sourceId) {
        return builder.build(new RankedChunk(
                        UUID.randomUUID(),
                        42L,
                        type,
                        sourceKind,
                        sourceId,
                        "text",
                        null,
                        "auto",
                        0.1d,
                        1,
                        null,
                        "C1"));
    }
}
