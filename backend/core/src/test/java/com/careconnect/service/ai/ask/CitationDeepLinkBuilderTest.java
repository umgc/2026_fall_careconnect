package com.careconnect.service.ai.ask;

import com.careconnect.service.ai.retrieval.RankedChunk;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.service.ai.indexing.SummarySourceKey;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class CitationDeepLinkBuilderTest {

    private final CitationDeepLinkBuilder builder =
            new CitationDeepLinkBuilder(new ObjectMapper());

    @Test
    @DisplayName("generic feature pages without source ids are omitted")
    void build_genericFeaturePages_areOmitted() {
        assertThat(build(RetrievalRecordType.MEDICATION, "med-1")).isNull();
        assertThat(build(RetrievalRecordType.TASK, "task-1")).isNull();
        assertThat(build(RetrievalRecordType.EVV_RECORD, "evv-1")).isNull();
        assertThat(build(RetrievalRecordType.VITAL_SIGN, "vital-1")).isNull();
    }

    @Test
    @DisplayName("unsafe clinical-note source ids are omitted")
    void build_unsafeClinicalNoteIds_areOmitted() {
        assertThat(build(RetrievalRecordType.CLINICAL_NOTE, "note-1_2.3")).isNull();
        assertThat(build(RetrievalRecordType.CLINICAL_NOTE, "note/1")).isNull();
        assertThat(build(RetrievalRecordType.CLINICAL_NOTE, "#fragment")).isNull();
        assertThat(build(RetrievalRecordType.CLINICAL_NOTE, "..")).isNull();
    }

    @Test
    @DisplayName("clinical notes and documents emit source-specific routes")
    void build_clinicalNoteAndDocument_emitRoutes() {
        assertThat(build(RetrievalRecordType.CLINICAL_NOTE, "42"))
                .isEqualTo("/notetaker/detail/42?patientId=42");
        assertThat(build(RetrievalRecordType.UPLOADED_DOCUMENT, "99"))
                .isEqualTo("/file-management?fileId=99");
        assertThat(build(RetrievalRecordType.USPS_MAIL, "7"))
                .isEqualTo("/mail/7");
    }

    @Test
    @DisplayName("clinical note links require patientId")
    void build_clinicalNote_requiresPatientId() {
        assertThat(builder.build(new RankedChunk(
                UUID.randomUUID(),
                null,
                RetrievalRecordType.CLINICAL_NOTE,
                null,
                "42",
                "text",
                null,
                "auto",
                0.1d,
                1,
                null,
                "C1")))
                .isNull();
    }

    @Test
    @DisplayName("call-owned summary rows emit call summary deep links")
    void build_sharedSummaryType_routesCallOwnedRows() {
        assertThat(build(
                RetrievalRecordType.SUMMARY_APPOINTMENT,
                SummarySourceKey.CALL_KIND,
                "call-summary:1",
                "{\"callId\":\"call-abc\",\"itemId\":\"item-9\"}"))
                .isEqualTo("/calls/call-abc/summary#item-item-9");
        assertThat(build(
                RetrievalRecordType.SUMMARY_APPOINTMENT,
                SummarySourceKey.VISIT_KIND,
                "visit-summary:1",
                "{\"visitId\":\"55\"}"))
                .isEqualTo("/visits/55/summary");
    }

    @Test
    @DisplayName("call summary and transcript segments require callId metadata")
    void build_callSummaryAndTranscript_requireCallId() {
        assertThat(build(RetrievalRecordType.CALL_SUMMARY, "call-summary:1")).isNull();
        assertThat(build(
                RetrievalRecordType.CALL_SUMMARY,
                null,
                "call-summary:1",
                "{\"callId\":\"call-42\"}"))
                .isEqualTo("/calls/call-42/summary");
        assertThat(build(
                RetrievalRecordType.TRANSCRIPT_SEGMENT,
                null,
                "seg-1",
                "{\"callId\":\"call-42\",\"startMs\":1500}"))
                .isEqualTo("/calls/call-42/summary?t=1500");
    }

    @Test
    void build_nullChunk_returnsNull() {
        assertThat(builder.build(null)).isNull();
    }

    @Test
    void build_visitSummary_usesSourceRecordIdWhenMetadataMissing() {
        assertThat(build(
                RetrievalRecordType.VISIT_SUMMARY,
                null,
                "visit-summary:77",
                "{}"))
                .isEqualTo("/visits/77/summary");
    }

    @Test
    void build_transcriptWithoutStartMs_omitsQueryParam() {
        assertThat(build(
                RetrievalRecordType.TRANSCRIPT_SEGMENT,
                null,
                "seg-1",
                "{\"callId\":\"call-42\"}"))
                .isEqualTo("/calls/call-42/summary");
    }

    @Test
    void build_summaryChildUnknownKind_returnsNull() {
        assertThat(build(
                RetrievalRecordType.SUMMARY_APPOINTMENT,
                "OTHER",
                "x",
                "{}"))
                .isNull();
    }

    @Test
    void build_uspsMail_nonDigitId_omitted() {
        assertThat(build(RetrievalRecordType.USPS_MAIL, "mail-abc")).isNull();
    }

    @Test
    void build_invalidMetadataJson_stillBuildsSafeLink() {
        assertThat(build(
                RetrievalRecordType.CALL_SUMMARY,
                null,
                "call-summary:1",
                "not-json"))
                .isNull();
    }

    private String build(final RetrievalRecordType type, final String sourceId) {
        return build(type, null, sourceId, null);
    }

    private String build(
            final RetrievalRecordType type,
            final String sourceKind,
            final String sourceId) {
        return build(type, sourceKind, sourceId, null);
    }

    private String build(
            final RetrievalRecordType type,
            final String sourceKind,
            final String sourceId,
            final String metadataJson) {
        return builder.build(new RankedChunk(
                UUID.randomUUID(),
                42L,
                type,
                sourceKind,
                sourceId,
                "text",
                metadataJson,
                "auto",
                0.1d,
                1,
                null,
                "C1"));
    }
}
