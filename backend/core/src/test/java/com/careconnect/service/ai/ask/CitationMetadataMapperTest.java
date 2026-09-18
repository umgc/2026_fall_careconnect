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

    @Test
    void map_blankOrInvalidJson_yieldsEmptyMetadata() {
        assertThat(mapper.map(RetrievalRecordType.MEDICATION, null).metadata()).isEmpty();
        assertThat(mapper.map(RetrievalRecordType.MEDICATION, "   ").metadata()).isEmpty();
        assertThat(mapper.map(RetrievalRecordType.MEDICATION, "not-json").metadata()).isEmpty();
        assertThat(mapper.map(RetrievalRecordType.MEDICATION, "[1,2]").metadata()).isEmpty();
    }

    @Test
    void map_visitSummary_whitelistsVisitFieldsAndDefaultTitle() {
        final CitationMetadataMapper.CitationMetadata metadata = mapper.map(
                RetrievalRecordType.VISIT_SUMMARY,
                """
                        {"visitId":"v-9","episodeType":"HOME","occurredAt":"2026-07-01",
                         "confidence":0.91,"title":""}
                        """);

        assertThat(metadata.title()).startsWith("Visit summary — 2026-07-01");
        assertThat(metadata.confidence()).isEqualTo(0.91d);
        assertThat(metadata.metadata())
                .containsEntry("visitId", "v-9")
                .containsEntry("episodeType", "HOME");
        assertThat(metadata.occurredAt()).isEqualTo(Instant.parse("2026-07-01T00:00:00Z"));
    }

    @Test
    void map_uspsMail_andSummaryTypes_useTypedTitles() {
        final CitationMetadataMapper.CitationMetadata mail = mapper.map(
                RetrievalRecordType.USPS_MAIL,
                """
                        {"digestDate":"2026-07-02","importanceLevel":"HIGH",
                         "importanceCategory":"MEDS","headline":"Pharmacy mail"}
                        """);
        assertThat(mail.title()).isEqualTo("Pharmacy mail");
        assertThat(mail.metadata())
                .containsEntry("digestDate", "2026-07-02")
                .containsEntry("importanceLevel", "HIGH");

        assertThat(mapper.map(RetrievalRecordType.UPLOADED_DOCUMENT, "{}").title())
                .isEqualTo("Uploaded document");
        assertThat(mapper.map(RetrievalRecordType.CLINICAL_NOTE, "{}").title())
                .isEqualTo("Clinical note");
        assertThat(mapper.map(RetrievalRecordType.SUMMARY_ACTION_ITEM, "{}").title())
                .isEqualTo("Summary action item");
        assertThat(mapper.map(RetrievalRecordType.SUMMARY_APPOINTMENT, "{}").title())
                .isEqualTo("Summary appointment");
        assertThat(mapper.map(RetrievalRecordType.SUMMARY_CARE_INSTRUCTION, "{}").title())
                .isEqualTo("Care instruction");
        assertThat(mapper.map(RetrievalRecordType.SUMMARY_CONDITION, "{}").title())
                .isEqualTo("Summary condition");
        assertThat(mapper.map(RetrievalRecordType.SUMMARY_SOAP, "{}").title())
                .isEqualTo("SOAP summary");
        assertThat(mapper.map(RetrievalRecordType.SUMMARY_CLINICAL_OBSERVATION, "{}").title())
                .isEqualTo("Clinical observation");
        assertThat(mapper.map(RetrievalRecordType.MEDICATION_TIMELINE_EVENT, "{}").title())
                .isEqualTo("Medication timeline");
        assertThat(mapper.map(RetrievalRecordType.TASK, "{}").title()).isEqualTo("Task");
        assertThat(mapper.map(RetrievalRecordType.EVV_RECORD, "{}").title())
                .isEqualTo("Visit record");
        assertThat(mapper.map(RetrievalRecordType.VITAL_SIGN, "{}").title())
                .isEqualTo("Vital sign");
        assertThat(mapper.map(RetrievalRecordType.CALL_SUMMARY, "{\"callId\":\"c1\"}").title())
                .isEqualTo("Call summary");
    }

    @Test
    void map_truncatesLongTitlesAndRejectsOutOfRangeConfidence() {
        final String longTitle = "T".repeat(200);
        final CitationMetadataMapper.CitationMetadata metadata = mapper.map(
                RetrievalRecordType.MEDICATION,
                "{\"title\":\"" + longTitle + "\",\"confidence\":1.5,\"summaryConfidence\":0.4}");

        assertThat(metadata.title()).endsWith("…");
        assertThat(metadata.title().codePointCount(0, metadata.title().length()))
                .isLessThanOrEqualTo(120);
        assertThat(metadata.confidence()).isNull();
    }

    @Test
    void map_usesSummaryConfidenceWhenConfidenceMissing() {
        final CitationMetadataMapper.CitationMetadata metadata = mapper.map(
                RetrievalRecordType.MEDICATION, "{\"summaryConfidence\":0.55}");
        assertThat(metadata.confidence()).isEqualTo(0.55d);
    }
}
