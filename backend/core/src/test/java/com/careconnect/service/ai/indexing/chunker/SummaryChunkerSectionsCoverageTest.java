package com.careconnect.service.ai.indexing.chunker;

import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class SummaryChunkerSectionsCoverageTest {

    private final SummaryChunker chunker = new SummaryChunker(new ObjectMapper());

    @Test
    void chunksConcernsObservationsTimelineAndSkipsEmptyItems() {
        String json = """
                {
                  "headline": "Follow-up call",
                  "overallAssessment": "Improving",
                  "keyConcerns": ["Dizziness", null, "", "Poor sleep"],
                  "soap": {"subjective": "Tired", "plan": "Rest"},
                  "clinicalObservations": {
                    "acuteRedFlags": ["Chest pain", {"text": "Shortness of breath"}, {"other": 1}, null, ""],
                    "symptomCharacterization": [],
                    "functionalStatus": "not-an-array",
                    "medicationRelated": [{"text": ""}],
                    "caregiverSignals": ["Stressed"]
                  },
                  "actionItems": [null, {"text": ""}, "Call pharmacy", {"description": "Book lab", "confidence": 0.8}],
                  "appointments": [null, {}, {"title": "Cardiology", "date": "2026-11-02"}],
                  "careInstructions": [
                    null,
                    {"type": "diet", "text": "Low salt"},
                    {"type": "medication"},
                    {"type": "medication", "medicationName": "Lisinopril", "status": "changed",
                     "effectiveDate": "2026-10-01", "doseFrom": "10mg", "doseTo": "20mg", "confidence": 2.0},
                    {"type": "Medication", "name": "Metformin"}
                  ],
                  "conditions": [{"text": "Hypertension"}]
                }
                """;
        List<IndexingChunkDraft> drafts = chunker.chunk("call", json, "sha256:x", "on_consent", "engine",
                "call-1", "2026-10-30T10:00:00Z");
        assertThat(drafts.stream().map(IndexingChunkDraft::recordType))
                .contains(RetrievalRecordType.SUMMARY_CLINICAL_OBSERVATION,
                        RetrievalRecordType.MEDICATION_TIMELINE_EVENT);
        assertThat(drafts.stream().filter(d -> d.chunkText().contains("from 10mg to 20mg"))).hasSize(1);
        assertThat(drafts.stream().filter(d -> d.chunkText().contains("Key concerns"))).isNotEmpty();
    }
}
