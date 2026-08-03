package com.careconnect.service.ai.indexing.chunker;

import static org.assertj.core.api.Assertions.assertThat;

import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class DocumentChunkerTest {

    private final DocumentChunker chunker = new DocumentChunker();

    @Test
    @DisplayName("short excerpt stays a single chunk")
    void chunk_shortText_singleDraft() {
        final List<IndexingChunkDraft> drafts =
                chunker.chunk("Short lab note", "LAB", "hash", "care_circle");

        assertThat(drafts).hasSize(1);
        assertThat(drafts.get(0).recordType()).isEqualTo(RetrievalRecordType.UPLOADED_DOCUMENT);
        assertThat(drafts.get(0).chunkText()).isEqualTo("Short lab note");
        assertThat(drafts.get(0).metadata()).containsEntry("chunkIndex", 0);
    }

    @Test
    @DisplayName("long excerpt splits into overlapping windows")
    void chunk_longText_multipleWindows() {
        final String paragraph = "Paragraph about medications and follow-up care. ".repeat(40);
        final String text = paragraph + "\n\n" + paragraph + "\n\n" + paragraph;
        assertThat(text.length()).isGreaterThan(DocumentChunker.MAX_CHUNK_CHARS);

        final List<IndexingChunkDraft> drafts =
                chunker.chunk(text, "CLINICAL", "abc", "care_circle");

        assertThat(drafts.size()).isGreaterThan(1);
        for (final IndexingChunkDraft draft : drafts) {
            assertThat(draft.chunkText().length())
                    .isLessThanOrEqualTo(DocumentChunker.MAX_CHUNK_CHARS + 50);
        }
        assertThat(drafts.get(0).metadata()).containsEntry("chunkIndex", 0);
        assertThat(drafts.get(1).metadata()).containsEntry("chunkIndex", 1);
    }

    @Test
    @DisplayName("splitIntoWindows returns empty for blank input")
    void splitIntoWindows_blank() {
        assertThat(DocumentChunker.splitIntoWindows("   ", 100, 10)).isEmpty();
    }
}
