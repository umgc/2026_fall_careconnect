package com.careconnect.service.ai.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class ReciprocalRankFusionTest {

    @Test
    @DisplayName("RRF scores chunks that appear in both lists higher")
    void merge_prefersIntersection() {
        final UUID both = UUID.randomUUID();
        final UUID ftsOnly = UUID.randomUUID();
        final UUID vectorOnly = UUID.randomUUID();

        final List<RetrievalIndexChunk> fts = List.of(chunk(both), chunk(ftsOnly));
        final List<RetrievalIndexChunk> vector = List.of(chunk(both), chunk(vectorOnly));

        final List<ReciprocalRankFusion.MergedHit> merged =
                ReciprocalRankFusion.merge(fts, vector, 60, 10);

        assertThat(merged).hasSize(3);
        assertThat(merged.get(0).chunk().getId()).isEqualTo(both);
        assertThat(merged.get(0).ftsRank()).isEqualTo(1);
        assertThat(merged.get(0).vectorRank()).isEqualTo(1);
        // 1/(60+1) + 1/(60+1)
        assertThat(merged.get(0).rrfScore()).isEqualTo(2.0d / 61.0d, org.assertj.core.data.Offset.offset(1e-9));
    }

    @Test
    @DisplayName("RRF respects finalTopK")
    void merge_respectsFinalTopK() {
        final List<RetrievalIndexChunk> fts = List.of(
                chunk(UUID.randomUUID()),
                chunk(UUID.randomUUID()),
                chunk(UUID.randomUUID()));

        final List<ReciprocalRankFusion.MergedHit> merged =
                ReciprocalRankFusion.merge(fts, List.of(), 60, 2);

        assertThat(merged).hasSize(2);
        assertThat(merged.get(0).ftsRank()).isEqualTo(1);
        assertThat(merged.get(1).ftsRank()).isEqualTo(2);
    }

    @Test
    @DisplayName("RRF handles empty arms")
    void merge_emptyArms() {
        assertThat(ReciprocalRankFusion.merge(List.of(), List.of(), 60, 10)).isEmpty();
    }

    @Test
    @DisplayName("RRF caps chunks per source before applying final top-k")
    void merge_capsChunksPerSource() {
        final RetrievalIndexChunk sourceA1 = chunk(UUID.randomUUID(), "source-a");
        final RetrievalIndexChunk sourceA2 = chunk(UUID.randomUUID(), "source-a");
        final RetrievalIndexChunk sourceB = chunk(UUID.randomUUID(), "source-b");

        final List<ReciprocalRankFusion.MergedHit> merged = ReciprocalRankFusion.merge(
                List.of(sourceA1, sourceA2, sourceB), List.of(), 60, 2, 1);

        assertThat(merged).hasSize(2);
        assertThat(merged)
                .extracting(hit -> hit.chunk().getSourceRecordId())
                .containsExactly("source-a", "source-b");
    }

    private static RetrievalIndexChunk chunk(final UUID id) {
        return chunk(id, "s1");
    }

    private static RetrievalIndexChunk chunk(final UUID id, final String sourceRecordId) {
        return RetrievalIndexChunk.builder()
                .id(id)
                .patientId(1L)
                .recordType("CALL_SUMMARY")
                .sourceRecordId(sourceRecordId)
                .chunkText("text")
                .build();
    }
}
