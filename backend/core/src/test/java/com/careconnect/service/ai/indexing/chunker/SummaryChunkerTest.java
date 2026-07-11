package com.careconnect.service.ai.indexing.chunker;

import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class SummaryChunkerTest {

    private final SummaryChunker chunker = new SummaryChunker(new ObjectMapper());

    @Test
    @DisplayName("summary JSON yields overview plus typed item chunks")
    void chunksOverviewAndTypedItems() {
        final String json = """
                {
                  "headline": "Medication change discussed",
                  "overallAssessment": "Patient started a new medication.",
                  "soap": {
                    "subjective": "Fatigue",
                    "objective": "Alert",
                    "assessment": "Possible side effect",
                    "plan": "Follow up in 1 week",
                    "riskLevel": "LOW"
                  },
                  "actionItems": [
                    { "text": "Call pharmacy", "sourceTurnId": "t1" }
                  ],
                  "appointments": [
                    { "date": "2026-07-20", "time": "10:00", "with": "Dr. Lee", "purpose": "Follow-up" }
                  ],
                  "careInstructions": [
                    { "type": "medication", "text": "Take metformin with food", "status": "started" }
                  ]
                }
                """;

        final List<IndexingChunkDraft> drafts = chunker.chunk(
                "call",
                json,
                "sha256:abc",
                "on_consent",
                "aws_bedrock:test");

        assertThat(drafts.stream().map(IndexingChunkDraft::recordType))
                .contains(
                        RetrievalRecordType.CALL_SUMMARY,
                        RetrievalRecordType.SUMMARY_ACTION_ITEM,
                        RetrievalRecordType.SUMMARY_APPOINTMENT,
                        RetrievalRecordType.SUMMARY_CARE_INSTRUCTION,
                        RetrievalRecordType.SUMMARY_SOAP);

        final IndexingChunkDraft overview = drafts.stream()
                .filter(d -> d.recordType() == RetrievalRecordType.CALL_SUMMARY)
                .findFirst()
                .orElseThrow();
        assertThat(overview.chunkText()).contains("Medication change discussed");
        assertThat(overview.chunkText()).doesNotContain("Fatigue");
        assertThat(overview.consentScope()).isEqualTo("on_consent");
        assertThat(overview.metadata()).containsEntry("contentHash", "sha256:abc");
    }

    @Test
    @DisplayName("visit episode type uses VISIT_SUMMARY overview")
    void visitUsesVisitSummaryType() {
        final List<IndexingChunkDraft> drafts = chunker.chunk(
                "visit",
                "{\"headline\":\"Clinic visit\"}",
                null,
                "auto",
                null);

        assertThat(drafts).hasSize(1);
        assertThat(drafts.get(0).recordType()).isEqualTo(RetrievalRecordType.VISIT_SUMMARY);
    }

    @Test
    @DisplayName("blank or invalid JSON returns no drafts")
    void blankOrInvalidReturnsEmpty() {
        assertThat(chunker.chunk("call", " ", null, null, null)).isEmpty();
        assertThat(chunker.chunk("call", "{not-json", null, null, null)).isEmpty();
    }
}
