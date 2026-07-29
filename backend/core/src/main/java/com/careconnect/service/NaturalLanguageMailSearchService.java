package com.careconnect.service;

import com.careconnect.dto.NaturalLanguageMailSearchMatch;
import com.careconnect.dto.NaturalLanguageMailSearchResponse;
import com.careconnect.model.UspsMailpiece;
import com.careconnect.model.User;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.repository.UspsMailpieceRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.embedding.ChunkEmbeddingService;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.service.ai.retrieval.FullTextSearchService;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.service.ai.retrieval.RetrievalScope;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import com.careconnect.service.ai.retrieval.VectorSimilaritySearchService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * Hybrid natural-language mail search (Task 3.14.7 / #124).
 *
 * <p>Combines:
 * <ul>
 *   <li>tokenized keyword search over durable {@code usps_mailpiece} rows</li>
 *   <li>Ask AI FTS over {@code retrieval_index_chunk} ({@code USPS_MAIL}) when
 *       the caller's retrieval scope permits it</li>
 * </ul>
 * Results are ranked with token coverage, importance boost, FTS, and vector
 * provenance when embeddings are available. The HTTP API shape is unchanged.
 */
@Service
public class NaturalLanguageMailSearchService {

    private static final Logger log = LoggerFactory.getLogger(NaturalLanguageMailSearchService.class);

    private static final int DEFAULT_LIMIT = 20;
    private static final int MAX_LIMIT = 50;
    private static final Set<String> STOP_WORDS = Set.of(
            "a", "an", "the", "of", "for", "my", "me", "is", "are", "was", "were",
            "about", "show", "find", "get", "any", "all", "from", "with", "that",
            "this", "these", "those", "and", "or", "to", "in", "on", "please",
            "can", "you", "i", "we", "our", "their", "mail", "mails", "mailpiece",
            "piece", "pieces", "letter", "letters", "usps");

    private static final Set<String> IMPORTANCE_HINTS = Set.of(
            "important", "urgent", "critical", "priority", "high");

    private final AuthorizationService authorizationService;
    private final RetrievalScopeService retrievalScopeService;
    private final FullTextSearchService fullTextSearchService;
    private final VectorSimilaritySearchService vectorSimilaritySearchService;
    private final ChunkEmbeddingService chunkEmbeddingService;
    private final UspsMailpieceRepository mailpieceRepository;

    public NaturalLanguageMailSearchService(
            final AuthorizationService authorizationService,
            final RetrievalScopeService retrievalScopeService,
            final FullTextSearchService fullTextSearchService,
            final VectorSimilaritySearchService vectorSimilaritySearchService,
            final ChunkEmbeddingService chunkEmbeddingService,
            final UspsMailpieceRepository mailpieceRepository) {
        this.authorizationService = authorizationService;
        this.retrievalScopeService = retrievalScopeService;
        this.fullTextSearchService = fullTextSearchService;
        this.vectorSimilaritySearchService = vectorSimilaritySearchService;
        this.chunkEmbeddingService = chunkEmbeddingService;
        this.mailpieceRepository = mailpieceRepository;
    }

    @Transactional(readOnly = true)
    public NaturalLanguageMailSearchResponse search(
            final User caller,
            final Long patientId,
            final String query,
            final int limit) throws UnauthorizedException, ForbiddenScopeException {
        authorizationService.requirePatientAccess(caller, patientId);
        final String normalizedQuery = query == null ? "" : query.trim();
        if (normalizedQuery.isBlank()) {
            return new NaturalLanguageMailSearchResponse(patientId, "", List.of(), 0, List.of());
        }

        final List<String> tokens = tokenize(normalizedQuery);
        final boolean preferImportant = tokens.stream().anyMatch(IMPORTANCE_HINTS::contains)
                || IMPORTANCE_HINTS.stream().anyMatch(h -> normalizedQuery.toLowerCase(Locale.ROOT).contains(h));

        final Map<Long, ScoredMatch> scored = new HashMap<>();

        searchDurableTable(patientId, tokens, preferImportant, scored);
        searchIndexedChunks(caller, patientId, normalizedQuery, limit, scored);
        searchVectorChunks(caller, patientId, normalizedQuery, limit, scored);

        final int effectiveLimit = clampLimit(limit);
        final List<NaturalLanguageMailSearchMatch> matches = scored.values().stream()
                .filter(s -> s.mailpiece() != null)
                .sorted(Comparator
                        .comparingDouble(ScoredMatch::score).reversed()
                        .thenComparing(s -> s.mailpiece().getDigestDate(),
                                Comparator.nullsLast(Comparator.reverseOrder())))
                .limit(effectiveLimit)
                .map(this::toDto)
                .toList();

        return new NaturalLanguageMailSearchResponse(
                patientId,
                normalizedQuery,
                tokens,
                matches.size(),
                matches);
    }

    private void searchDurableTable(
            final Long patientId,
            final List<String> tokens,
            final boolean preferImportant,
            final Map<Long, ScoredMatch> scored) {
        if (tokens.isEmpty()) {
            return;
        }
        final Map<Long, UspsMailpiece> found = new HashMap<>();
        final Map<Long, Integer> hitCounts = new HashMap<>();
        for (final String token : tokens) {
            if (IMPORTANCE_HINTS.contains(token)) {
                continue;
            }
            for (final UspsMailpiece piece : mailpieceRepository.searchByPatientIdAndTerm(patientId, token)) {
                if (piece == null || piece.getId() == null) {
                    continue;
                }
                found.put(piece.getId(), piece);
                hitCounts.merge(piece.getId(), 1, Integer::sum);
            }
        }
        if (preferImportant) {
            for (final UspsMailpiece piece : mailpieceRepository.searchByPatientIdAndTerm(patientId, "HIGH")) {
                if (piece != null && piece.getId() != null) {
                    found.putIfAbsent(piece.getId(), piece);
                    hitCounts.merge(piece.getId(), 1, Integer::sum);
                }
            }
            for (final UspsMailpiece piece : mailpieceRepository.searchByPatientIdAndTerm(patientId, "MODERATE")) {
                if (piece != null && piece.getId() != null) {
                    found.putIfAbsent(piece.getId(), piece);
                    hitCounts.merge(piece.getId(), 1, Integer::sum);
                }
            }
        }

        final int searchableTokenCount = (int) tokens.stream()
                .filter(t -> !IMPORTANCE_HINTS.contains(t))
                .count();
        final int denom = Math.max(1, searchableTokenCount);

        for (final Map.Entry<Long, UspsMailpiece> entry : found.entrySet()) {
            final UspsMailpiece piece = entry.getValue();
            final int hits = hitCounts.getOrDefault(entry.getKey(), 0);
            double score = 0.35d + (0.45d * hits / denom);
            score += importanceBoost(piece.getImportanceLevel());
            if (preferImportant && isElevated(piece.getImportanceLevel())) {
                score += 0.15d;
            }
            score = Math.min(1.0d, score);
            scored.merge(entry.getKey(), new ScoredMatch(piece, score, Set.of("TABLE"),
                            buildSnippet(piece, null)),
                    NaturalLanguageMailSearchService::mergeScores);
        }
    }

    private void searchIndexedChunks(
            final User caller,
            final Long patientId,
            final String query,
            final int limit,
            final Map<Long, ScoredMatch> scored) {
        try {
            final RetrievalScope scope = retrievalScopeService.resolveRetrievalScope(
                    caller, patientId, Set.of(RetrievalRecordType.USPS_MAIL));
            if (!scope.allowedSourceTypes().contains(RetrievalRecordType.USPS_MAIL)) {
                return;
            }
        } catch (final ForbiddenScopeException | UnauthorizedException ex) {
            log.debug("Skipping FTS USPS_MAIL leg for patientId={}: {}", patientId, ex.getMessage());
            return;
        } catch (final Exception ex) {
            log.debug("Skipping FTS USPS_MAIL leg for patientId={}: {}", patientId, ex.getMessage());
            return;
        }

        final List<RetrievalIndexChunk> chunks = fullTextSearchService.search(
                patientId, query, Set.of(RetrievalRecordType.USPS_MAIL.name()), clampLimit(limit));
        if (chunks == null || chunks.isEmpty()) {
            return;
        }

        final List<Long> ids = new ArrayList<>();
        final Map<Long, RetrievalIndexChunk> chunkById = new HashMap<>();
        int rank = 0;
        for (final RetrievalIndexChunk chunk : chunks) {
            rank++;
            final Long mailpieceId = parseLong(chunk.getSourceRecordId());
            if (mailpieceId == null) {
                continue;
            }
            ids.add(mailpieceId);
            chunkById.put(mailpieceId, chunk);
            // provisional score from FTS rank until we load the durable row
            final double ftsScore = Math.max(0.40d, 0.95d - (0.04d * (rank - 1)));
            scored.merge(mailpieceId,
                    new ScoredMatch(null, ftsScore, Set.of("FTS"), trimSnippet(chunk.getChunkText())),
                    NaturalLanguageMailSearchService::mergeScores);
        }

        if (ids.isEmpty()) {
            return;
        }
        for (final UspsMailpiece piece : mailpieceRepository.findByPatientIdAndIdIn(patientId, ids)) {
            if (piece == null || piece.getId() == null) {
                continue;
            }
            final RetrievalIndexChunk chunk = chunkById.get(piece.getId());
            final double ftsScore = scored.containsKey(piece.getId())
                    ? scored.get(piece.getId()).score()
                    : 0.70d;
            double score = Math.min(1.0d, ftsScore + importanceBoost(piece.getImportanceLevel()));
            scored.put(piece.getId(), new ScoredMatch(
                    piece,
                    score,
                    Set.of("FTS", "TABLE"),
                    buildSnippet(piece, chunk == null ? null : chunk.getChunkText())));
        }
    }

    private void searchVectorChunks(
            final User caller,
            final Long patientId,
            final String query,
            final int limit,
            final Map<Long, ScoredMatch> scored) {
        try {
            final RetrievalScope scope = retrievalScopeService.resolveRetrievalScope(
                    caller, patientId, Set.of(RetrievalRecordType.USPS_MAIL));
            if (!scope.allowedSourceTypes().contains(RetrievalRecordType.USPS_MAIL)) {
                return;
            }
        } catch (final ForbiddenScopeException | UnauthorizedException ex) {
            log.debug("Skipping vector USPS_MAIL leg for patientId={}: {}", patientId, ex.getMessage());
            return;
        } catch (final Exception ex) {
            log.debug("Skipping vector USPS_MAIL leg for patientId={}: {}", patientId, ex.getMessage());
            return;
        }

        try {
            final var embedding = chunkEmbeddingService.embedQuery(query);
            if (embedding.isEmpty()) {
                return;
            }
            final List<RetrievalIndexChunk> chunks = vectorSimilaritySearchService.search(
                    patientId,
                    embedding.get(),
                    Set.of(RetrievalRecordType.USPS_MAIL.name()),
                    clampLimit(limit));
            if (chunks == null || chunks.isEmpty()) {
                return;
            }

            final List<Long> ids = new ArrayList<>();
            final Map<Long, RetrievalIndexChunk> chunkById = new HashMap<>();
            int rank = 0;
            for (final RetrievalIndexChunk chunk : chunks) {
                rank++;
                final Long mailpieceId = parseLong(chunk.getSourceRecordId());
                if (mailpieceId == null) {
                    continue;
                }
                ids.add(mailpieceId);
                chunkById.put(mailpieceId, chunk);
                final double vectorScore = vectorScore(rank, null);
                scored.merge(
                        mailpieceId,
                        new ScoredMatch(
                                null, vectorScore, Set.of("VECTOR"), trimSnippet(chunk.getChunkText())),
                        NaturalLanguageMailSearchService::mergeScores);
            }
            if (ids.isEmpty()) {
                return;
            }
            for (final UspsMailpiece piece : mailpieceRepository.findByPatientIdAndIdIn(patientId, ids)) {
                if (piece == null || piece.getId() == null) {
                    continue;
                }
                final RetrievalIndexChunk chunk = chunkById.get(piece.getId());
                final double prior = scored.containsKey(piece.getId())
                        ? scored.get(piece.getId()).score()
                        : 0.55d;
                final double score = Math.min(1.0d, prior + importanceBoost(piece.getImportanceLevel()));
                final Set<String> sources = new LinkedHashSet<>();
                if (scored.containsKey(piece.getId())) {
                    sources.addAll(scored.get(piece.getId()).sources());
                }
                sources.add("VECTOR");
                sources.add("TABLE");
                scored.put(piece.getId(), new ScoredMatch(
                        piece,
                        score,
                        sources,
                        buildSnippet(piece, chunk == null ? null : chunk.getChunkText())));
            }
        } catch (final Exception ex) {
            log.warn(
                    "NL mail vector leg failed for patientId={}; continuing without VECTOR: {}",
                    patientId,
                    ex.getMessage());
        }
    }

    /**
     * Prefers a real cosine similarity when the vector API projects one; otherwise a
     * conservative rank prior so weak hits do not dominate TABLE/FTS merges.
     */
    static double vectorScore(final int rank, final Double cosineSimilarity) {
        if (cosineSimilarity != null && !cosineSimilarity.isNaN()) {
            return Math.max(0.0d, Math.min(1.0d, cosineSimilarity));
        }
        return rankBasedVectorScore(rank);
    }

    /**
     * Conservative prior when the vector API returns ordered chunks without similarity.
     */
    static double rankBasedVectorScore(final int rank) {
        if (rank <= 0) {
            return 0.35d;
        }
        return Math.max(0.30d, 0.72d - (0.05d * (rank - 1)));
    }

    private NaturalLanguageMailSearchMatch toDto(final ScoredMatch scored) {
        final UspsMailpiece piece = scored.mailpiece();
        if (piece == null) {
            return new NaturalLanguageMailSearchMatch(
                    null, null, null, null, null, null, null, null, null,
                    round(scored.score()), scored.snippet(), List.copyOf(scored.sources()));
        }
        return new NaturalLanguageMailSearchMatch(
                piece.getId(),
                piece.getSender(),
                piece.getSummary(),
                piece.getImageRef(),
                piece.getDigestDate(),
                piece.getReceivedAt(),
                piece.getImportanceLevel(),
                piece.getImportanceCategory(),
                piece.getImportanceReasoning(),
                round(scored.score()),
                scored.snippet(),
                List.copyOf(scored.sources()));
    }

    static List<String> tokenize(final String query) {
        if (query == null || query.isBlank()) {
            return List.of();
        }
        final String[] parts = query.toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9\\s%.-]", " ")
                .split("\\s+");
        final Set<String> tokens = new LinkedHashSet<>();
        for (final String part : parts) {
            if (part == null || part.isBlank() || part.length() < 2) {
                continue;
            }
            if (STOP_WORDS.contains(part)) {
                continue;
            }
            tokens.add(part);
        }
        return List.copyOf(tokens);
    }

    private static ScoredMatch mergeScores(final ScoredMatch a, final ScoredMatch b) {
        final UspsMailpiece piece = a.mailpiece() != null ? a.mailpiece() : b.mailpiece();
        final Set<String> sources = new HashSet<>();
        sources.addAll(a.sources());
        sources.addAll(b.sources());
        final double score = Math.min(1.0d, Math.max(a.score(), b.score()) + 0.08d);
        final String snippet = a.snippet() != null && !a.snippet().isBlank() ? a.snippet() : b.snippet();
        return new ScoredMatch(piece, score, sources, snippet);
    }

    private static double importanceBoost(final String level) {
        if (level == null) {
            return 0.0d;
        }
        return switch (level.trim().toUpperCase(Locale.ROOT)) {
            case "HIGH" -> 0.20d;
            case "MODERATE" -> 0.10d;
            case "LOW" -> -0.02d;
            default -> 0.0d;
        };
    }

    private static boolean isElevated(final String level) {
        if (level == null) {
            return false;
        }
        final String value = level.trim().toUpperCase(Locale.ROOT);
        return "HIGH".equals(value) || "MODERATE".equals(value);
    }

    private static String buildSnippet(final UspsMailpiece piece, final String chunkText) {
        if (chunkText != null && !chunkText.isBlank()) {
            return trimSnippet(chunkText);
        }
        final StringBuilder sb = new StringBuilder();
        if (piece.getSender() != null && !piece.getSender().isBlank()) {
            sb.append("From: ").append(piece.getSender().trim());
        }
        if (piece.getSummary() != null && !piece.getSummary().isBlank()) {
            if (!sb.isEmpty()) {
                sb.append(" — ");
            }
            sb.append(piece.getSummary().trim());
        }
        if (piece.getImportanceReasoning() != null && !piece.getImportanceReasoning().isBlank()) {
            if (!sb.isEmpty()) {
                sb.append(" | ");
            }
            sb.append(piece.getImportanceReasoning().trim());
        }
        return trimSnippet(sb.toString());
    }

    private static String trimSnippet(final String value) {
        if (value == null) {
            return "";
        }
        final String trimmed = value.trim().replaceAll("\\s+", " ");
        return trimmed.length() <= 280 ? trimmed : trimmed.substring(0, 277) + "...";
    }

    private static Long parseLong(final String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return Long.parseLong(value.trim());
        } catch (final NumberFormatException ex) {
            return null;
        }
    }

    private static int clampLimit(final int limit) {
        if (limit <= 0) {
            return DEFAULT_LIMIT;
        }
        return Math.min(limit, MAX_LIMIT);
    }

    private static double round(final double value) {
        return Math.round(value * 1000.0d) / 1000.0d;
    }

    private record ScoredMatch(
            UspsMailpiece mailpiece,
            double score,
            Set<String> sources,
            String snippet) {
        private ScoredMatch {
            sources = sources == null ? Set.of() : Set.copyOf(sources);
            snippet = snippet == null ? "" : snippet;
        }
    }
}
