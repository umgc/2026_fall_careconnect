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
        return merge(ftsHits, vectorHits, List.of(), rrfK, finalTopK, maxChunksPerSource, 1.0d);
    }

    /**
     * RRF over FTS, vector, and an optional structured arm (e.g. medication timeline prefilter).
     *
     * @param structuredWeight multiplier applied to structured-arm contributions (design default 1.5)
     */
    static List<MergedHit> merge(
            final List<RetrievalIndexChunk> ftsHits,
            final List<RetrievalIndexChunk> vectorHits,
            final List<RetrievalIndexChunk> structuredHits,
            final int rrfK,
            final int finalTopK,
            final int maxChunksPerSource,
            final double structuredWeight) {
        final int k = Math.max(1, rrfK);
        final int topK = Math.max(1, finalTopK);
        final int sourceCap = Math.max(1, maxChunksPerSource);
        final double weight = structuredWeight <= 0.0d ? 1.0d : structuredWeight;

        final Map<UUID, MergedHit> byId = new LinkedHashMap<>();
        accumulate(byId, ftsHits, Arm.FTS, k, 1.0d);
        accumulate(byId, vectorHits, Arm.VECTOR, k, 1.0d);
        accumulate(byId, structuredHits, Arm.STRUCTURED, k, weight);

        final List<MergedHit> ranked = new ArrayList<>(byId.values());
        ranked.sort((a, b) -> {
            final int scoreCmp = Double.compare(b.rrfScore(), a.rrfScore());
            if (scoreCmp != 0) {
                return scoreCmp;
            }
            final int armsA = armCount(a);
            final int armsB = armCount(b);
            if (armsA != armsB) {
                return Integer.compare(armsB, armsA);
            }
            return a.chunk().getId().compareTo(b.chunk().getId());
        });

        final List<MergedHit> diverse = capChunksPerSource(ranked, sourceCap, topK);
        return List.copyOf(diverse);
    }

    private static int armCount(final MergedHit hit) {
        int count = 0;
        if (hit.ftsRank() != null) {
            count++;
        }
        if (hit.vectorRank() != null) {
            count++;
        }
        if (hit.structuredRank() != null) {
            count++;
        }
        return count;
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
            final Arm arm,
            final int k,
            final double weight) {
        if (hits == null || hits.isEmpty()) {
            return;
        }
        for (int i = 0; i < hits.size(); i++) {
            final RetrievalIndexChunk chunk = hits.get(i);
            if (chunk == null || chunk.getId() == null) {
                continue;
            }
            final int rank = i + 1;
            final double contribution = weight / (k + rank);
            final MergedHit existing = byId.get(chunk.getId());
            if (existing == null) {
                byId.put(
                        chunk.getId(),
                        new MergedHit(
                                chunk,
                                contribution,
                                arm == Arm.FTS ? Integer.valueOf(rank) : null,
                                arm == Arm.VECTOR ? Integer.valueOf(rank) : null,
                                arm == Arm.STRUCTURED ? Integer.valueOf(rank) : null));
            } else {
                byId.put(
                        chunk.getId(),
                        new MergedHit(
                                existing.chunk(),
                                existing.rrfScore() + contribution,
                                arm == Arm.FTS ? Integer.valueOf(rank) : existing.ftsRank(),
                                arm == Arm.VECTOR ? Integer.valueOf(rank) : existing.vectorRank(),
                                arm == Arm.STRUCTURED
                                        ? Integer.valueOf(rank)
                                        : existing.structuredRank()));
            }
        }
    }

    private enum Arm {
        FTS,
        VECTOR,
        STRUCTURED
    }

    /**
     * Intermediate RRF hit before citation refs are assigned.
     */
    record MergedHit(
            RetrievalIndexChunk chunk,
            double rrfScore,
            Integer ftsRank,
            Integer vectorRank,
            Integer structuredRank) {

        MergedHit(
                final RetrievalIndexChunk chunk,
                final double rrfScore,
                final Integer ftsRank,
                final Integer vectorRank) {
            this(chunk, rrfScore, ftsRank, vectorRank, null);
        }
    }
}
