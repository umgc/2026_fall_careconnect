package com.careconnect.service.ai.indexing.chunker;

import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class MailpieceChunkerTest {

    private final MailpieceChunker chunker = new MailpieceChunker();

    @Test
    @DisplayName("chunk produces one USPS_MAIL draft with sender, summary, and metadata")
    void chunk_producesUspsMailDraft() {
        final List<IndexingChunkDraft> drafts = chunker.chunk(
                "Acme Bank",
                "Monthly statement",
                null,
                "sha-1",
                "2025-03-03|m-1",
                LocalDate.of(2025, 3, 3),
                "on_consent");

        assertThat(drafts).hasSize(1);
        final IndexingChunkDraft draft = drafts.get(0);
        assertThat(draft.recordType()).isEqualTo(RetrievalRecordType.USPS_MAIL);
        assertThat(draft.chunkText()).isEqualTo("From: Acme Bank\nMonthly statement");
        assertThat(draft.consentScope()).isEqualTo("on_consent");
        assertThat(draft.metadata()).containsEntry("contentHash", "sha-1");
        assertThat(draft.metadata()).containsEntry("sourceKey", "2025-03-03|m-1");
        assertThat(draft.metadata()).containsEntry("digestDate", "2025-03-03");
    }

    @Test
    @DisplayName("chunk returns empty when there is no searchable text")
    void chunk_emptyWhenNoText() {
        assertThat(chunker.chunk(null, "  ", null, "h", "k", null, "on_consent")).isEmpty();
    }

    @Test
    @DisplayName("chunk appends ocr_text when present")
    void chunk_includesOcrText() {
        final List<IndexingChunkDraft> drafts = chunker.chunk(
                "Hospital", "Lab results", "Regional Medical Center",
                "h", "k", LocalDate.of(2025, 1, 1), "on_consent");

        assertThat(drafts.get(0).chunkText()).contains("Regional Medical Center");
    }
}
