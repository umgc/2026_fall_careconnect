package com.careconnect.service.ai.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Reciprocal Rank Fusion merge for hybrid FTS + vector rank lists (Task 5.1).
 *
 * <p>{@code score(d) = Σ 1 / (k + rank)} over each list where {@code d} appears
 * (1-based ranks).
 */
final class ReciprocalRankFusion {

    private ReciprocalRankFusion() {
    }

    static List<MergedHit> merge(
            final List<RetrievalIndexChunk> ftsHits,
            final List<RetrievalIndexChunk> vectorHits,
            final int rrfK,
            final int finalTopK) {
        return merge(ftsHits, vectorHits, rrfK, finalTopK, Integer.MAX_VALUE);
    }

    static List<MergedHit> merge(
            final List<RetrievalIndexChunk> ftsHits,
            final List<RetrievalIndexChunk> vectorHits,
            final int rrfK,
            final int finalTopK,
            final int maxChunksPerSource) {
        final int k = Math.max(1, rrfK);
        final int topK = Math.max(1, finalTopK);
        final int sourceCap = Math.max(1, maxChunksPerSource);

        final Map<UUID, MergedHit> byId = new LinkedHashMap<>();
        accumulate(byId, ftsHits, true, k);
        accumulate(byId, vectorHits, false, k);

        final List<MergedHit> ranked = new ArrayList<>(byId.values());
        ranked.sort((a, b) -> {
            final int scoreCmp = Double.compare(b.rrfScore(), a.rrfScore());
            if (scoreCmp != 0) {
                return scoreCmp;
            }
            // Stable tie-break: prefer chunks that hit both arms, then FTS-only, then id.
            final int armsA = (a.ftsRank() != null ? 1 : 0) + (a.vectorRank() != null ? 1 : 0);
            final int armsB = (b.ftsRank() != null ? 1 : 0) + (b.vectorRank() != null ? 1 : 0);
            if (armsA != armsB) {
                return Integer.compare(armsB, armsA);
            }
            return a.chunk().getId().compareTo(b.chunk().getId());
        });

        final List<MergedHit> diverse = capChunksPerSource(ranked, sourceCap, topK);
        return List.copyOf(diverse);
    }

    private static List<MergedHit> capChunksPerSource(
            final List<MergedHit> ranked, final int sourceCap, final int topK) {
        final Map<String, Integer> countBySource = new LinkedHashMap<>();
        final List<MergedHit> diverse = new ArrayList<>(Math.min(ranked.size(), topK));
        for (final MergedHit hit : ranked) {
            final String sourceKey = sourceKey(hit.chunk());
            final int sourceCount = countBySource.merge(sourceKey, 1, Integer::sum);
            if (sourceCount <= sourceCap) {
                diverse.add(hit);
                if (diverse.size() == topK) {
                    break;
                }
            }
        }
        return diverse;
    }

    private static String sourceKey(final RetrievalIndexChunk chunk) {
        final String sourceRecordId = chunk.getSourceRecordId();
        if (sourceRecordId == null || sourceRecordId.isBlank()) {
            return "chunk:" + chunk.getId();
        }
        return "source:" + sourceRecordId;
    }

    private static void accumulate(
            final Map<UUID, MergedHit> byId,
            final List<RetrievalIndexChunk> hits,
            final boolean ftsArm,
            final int k) {
        if (hits == null || hits.isEmpty()) {
            return;
        }
        for (int i = 0; i < hits.size(); i++) {
            final RetrievalIndexChunk chunk = hits.get(i);
            if (chunk == null || chunk.getId() == null) {
                continue;
            }
            final int rank = i + 1;
            final double contribution = 1.0d / (k + rank);
            final MergedHit existing = byId.get(chunk.getId());
            if (existing == null) {
                byId.put(
                        chunk.getId(),
                        new MergedHit(
                                chunk,
                                contribution,
                                ftsArm ? rank : null,
                                ftsArm ? null : rank));
            } else {
                byId.put(
                        chunk.getId(),
                        new MergedHit(
                                existing.chunk(),
                                existing.rrfScore() + contribution,
                                ftsArm ? rank : existing.ftsRank(),
                                ftsArm ? existing.vectorRank() : rank));
            }
        }
    }

    /**
     * Intermediate RRF hit before citation refs are assigned.
     */
    record MergedHit(
            RetrievalIndexChunk chunk,
            double rrfScore,
            Integer ftsRank,
            Integer vectorRank) {
    }
}
