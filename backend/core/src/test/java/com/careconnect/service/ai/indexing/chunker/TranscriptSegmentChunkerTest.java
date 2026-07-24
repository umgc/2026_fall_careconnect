package com.careconnect.service.ai.indexing.chunker;

import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class TranscriptSegmentChunkerTest {

    private final TranscriptSegmentChunker chunker = new TranscriptSegmentChunker();

    @Test
    @DisplayName("one non-blank segment becomes one TRANSCRIPT_SEGMENT chunk")
    void chunksOneSegmentPerDraft() {
        final CallTranscriptSegment segment = new CallTranscriptSegment();
        segment.setId(11L);
        segment.setCallId("call-1");
        segment.setSpeakerLabel("Patient");
        segment.setText("I started metformin yesterday.");
        segment.setStartMs(1000L);
        segment.setEndMs(4000L);
        segment.setSource("CLIENT_TRANSCRIPT");
        segment.setOccurredAt(LocalDateTime.of(2026, 7, 10, 12, 0));

        final List<IndexingChunkDraft> drafts =
                chunker.chunk("call-1", "CLIENT_TRANSCRIPT", List.of(segment));

        assertThat(drafts).hasSize(1);
        assertThat(drafts.get(0).recordType()).isEqualTo(RetrievalRecordType.TRANSCRIPT_SEGMENT);
        assertThat(drafts.get(0).chunkText()).isEqualTo("Patient: I started metformin yesterday.");
        assertThat(drafts.get(0).metadata()).containsEntry("segmentId", 11L);
        assertThat(drafts.get(0).metadata()).containsEntry("chunkIndex", 0);
        assertThat(drafts.get(0).metadata())
                .containsEntry("occurredAt", "2026-07-10T12:00:00Z");
    }

    @Test
    @DisplayName("blank segments are skipped")
    void skipsBlankSegments() {
        final CallTranscriptSegment blank = new CallTranscriptSegment();
        blank.setText("   ");
        final CallTranscriptSegment ok = new CallTranscriptSegment();
        ok.setId(2L);
        ok.setText("Hello");

        final List<IndexingChunkDraft> drafts =
                chunker.chunk("call-1", "POST_CALL_TRANSCRIBE", List.of(blank, ok));

        assertThat(drafts).hasSize(1);
        assertThat(drafts.get(0).chunkText()).isEqualTo("Hello");
    }
}
