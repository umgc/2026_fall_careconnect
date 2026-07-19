package com.careconnect.service.ai.indexing;

import com.careconnect.indexing.MailpieceIndexedPayload;
import com.careconnect.indexing.SummaryCreatedPayload;
import com.careconnect.indexing.TranscriptIndexedPayload;
import com.careconnect.model.CallSummary;
import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.model.UspsMailpiece;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.model.retrieval.RetrievalIndexSchema;
import com.careconnect.repository.CallSummaryRepository;
import com.careconnect.repository.CallTranscriptSegmentRepository;
import com.careconnect.repository.UspsMailpieceRepository;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.service.ai.indexing.chunker.MailpieceChunker;
import com.careconnect.service.ai.embedding.ChunkEmbeddingService;
import com.careconnect.service.ai.indexing.chunker.SummaryChunker;
import com.careconnect.service.ai.indexing.chunker.TranscriptSegmentChunker;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.util.ContentHashUtil;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/**
 * Ingests Ask AI indexing events into {@code retrieval_index_chunk} (Task 4.1).
 *
 * <p>Called by {@link IndexWorker} after outbox events are dequeued. Does not publish
 * SNS/SQS itself — that remains a future transport upgrade. After chunk rows are saved,
 * {@link ChunkEmbeddingService} best-effort writes Bedrock Titan embeddings (Task 4.3)
 * <em>after</em> the ingest transaction commits so Bedrock I/O does not hold a JDBC connection.
 * FTS {@code search_vector} is maintained automatically by the PostgreSQL trigger on
 * {@code chunk_text} insert/update (Task 4.2) — this service does not set it in application code.
 */
@Service
public class RetrievalIndexService {

    private static final Logger log = LoggerFactory.getLogger(RetrievalIndexService.class);

    private final CallSummaryRepository callSummaryRepository;
    private final CallTranscriptSegmentRepository transcriptSegmentRepository;
    private final UspsMailpieceRepository uspsMailpieceRepository;
    private final RetrievalIndexChunkRepository chunkRepository;
    private final SummaryChunker summaryChunker;
    private final TranscriptSegmentChunker transcriptSegmentChunker;
    private final MailpieceChunker mailpieceChunker;
    private final ObjectMapper objectMapper;
    private final ChunkEmbeddingService chunkEmbeddingService;

    public RetrievalIndexService(
            final CallSummaryRepository callSummaryRepository,
            final CallTranscriptSegmentRepository transcriptSegmentRepository,
            final UspsMailpieceRepository uspsMailpieceRepository,
            final RetrievalIndexChunkRepository chunkRepository,
            final SummaryChunker summaryChunker,
            final TranscriptSegmentChunker transcriptSegmentChunker,
            final MailpieceChunker mailpieceChunker,
            final ObjectMapper objectMapper,
            final ChunkEmbeddingService chunkEmbeddingService) {
        this.callSummaryRepository = callSummaryRepository;
        this.transcriptSegmentRepository = transcriptSegmentRepository;
        this.uspsMailpieceRepository = uspsMailpieceRepository;
        this.chunkRepository = chunkRepository;
        this.summaryChunker = summaryChunker;
        this.transcriptSegmentChunker = transcriptSegmentChunker;
        this.mailpieceChunker = mailpieceChunker;
        this.objectMapper = objectMapper;
        this.chunkEmbeddingService = chunkEmbeddingService;
    }

    /**
     * Indexes a successful call summary. Replaces prior chunks for the same
     * {@code source_record_id} (summary id) only when new drafts are non-empty.
     *
     * <p><b>contentHash is the hard idempotency key</b> for re-ingest:
     * <ul>
     *   <li>Hash matches and all embeddings present → skip (no re-chunk, no embed).</li>
     *   <li>Hash matches but any embedding is NULL (prior Bedrock failure) →
     *       embed-only retry; chunk text/structure are left unchanged.</li>
     *   <li>Hash differs or is absent → full replace + after-commit embed.</li>
     * </ul>
     * Chunker or metadata-only changes that do <em>not</em> change {@code contentHash}
     * intentionally do not re-chunk. Operators who change chunk shape must bump the
     * publisher hash (or wait for Task 4.4 backfill for NULL vectors only).
     *
     * @return number of chunks written (0 when skipped or nothing to index)
     */
    @Transactional
    public int ingestSummaryCreated(final SummaryCreatedPayload payload) {
        if (payload == null || payload.summaryId() == null) {
            throw new IllegalArgumentException("SUMMARY_CREATED payload requires summaryId");
        }
        if (payload.status() != null && !"SUCCESS".equalsIgnoreCase(payload.status().trim())) {
            log.info("Skipping SUMMARY_CREATED for summaryId={} status={}",
                    payload.summaryId(), payload.status());
            return 0;
        }
        if (isVisitSummary(payload)) {
            // Leave outbox unprocessed until visit_summaries indexing lands (Task 1.4).
            // Do not burn attempt budget — otherwise the row dead-letters before 1.4 ships.
            throw new IndexingDeferredException(
                    "Visit summary indexing not implemented yet (Task 1.4) for summaryId="
                            + payload.summaryId(),
                    false);
        }

        final String sourceRecordId = SummarySourceKey.call(payload.summaryId());
        final String legacySourceRecordId = SummarySourceKey.legacy(payload.summaryId());
        final List<String> sourceRecordIds =
                List.of(sourceRecordId, legacySourceRecordId);
        final CallSummary summary = callSummaryRepository.findByIdForUpdate(payload.summaryId())
                .orElseThrow(() -> new IllegalArgumentException(
                        "CallSummary not found for summaryId=" + payload.summaryId()));

        if (payload.patientId() != null
                && summary.getPatientId() != null
                && !payload.patientId().equals(summary.getPatientId())) {
            throw new IndexingDeferredException(
                    "SUMMARY_CREATED patient scope does not match authoritative summary row");
        }
        final Long patientId = firstNonNull(summary.getPatientId(), payload.patientId());
        if (patientId == null) {
            throw new IndexingDeferredException(
                    "Cannot index summaryId=" + payload.summaryId()
                            + " — patientId is required on retrieval_index_chunk");
        }

        final String episodeType = "call";
        final String caregiverVisibility = firstNonBlank(
                summary.getCaregiverVisibility(), payload.caregiverVisibility());
        final String contentHash = firstNonBlank(payload.contentHash(), null);
        final String engine = firstNonBlank(
                payload.summarizationEngine(), summary.getSummarizationEngine());

        final List<IndexingChunkDraft> drafts = summaryChunker.chunk(
                episodeType,
                summary.getSummaryJson(),
                contentHash,
                caregiverVisibility,
                engine,
                summary.getCallId(),
                summary.getGeneratedAt() == null
                        ? null
                        : summary.getGeneratedAt()
                                .atZone(ZoneOffset.UTC)
                                .toInstant()
                                .toString());
        final List<RetrievalIndexChunk> existing =
                chunkRepository.findCallSummaryChunksForReplacement(
                        patientId,
                        sourceRecordId,
                        legacySourceRecordId,
                        SummarySourceKey.CALL_KIND,
                        RetrievalRecordType.summaryTypeNames());

        if (drafts.isEmpty()) {
            log.warn(
                    "SUMMARY_CREATED produced no drafts for summaryId={}; leaving existing chunks unchanged",
                    payload.summaryId());
            // Still recover NULL embeddings from a prior Bedrock failure if chunks remain.
            return retryMissingEmbeddingsOrSkip(
                    patientId,
                    sourceRecordIds,
                    payload.summaryId(),
                    "no drafts; existing chunks left unchanged");
        }

        if (contentHash != null
                && chunksMatchExpected(existing, drafts, contentHash, sourceRecordId)) {
            return retryMissingEmbeddingsOrSkip(
                    patientId,
                    sourceRecordIds,
                    payload.summaryId(),
                    "contentHash and citation metadata unchanged");
        }

        chunkRepository.deleteCallSummaryChunksForReplacement(
                patientId,
                sourceRecordId,
                legacySourceRecordId,
                SummarySourceKey.CALL_KIND,
                RetrievalRecordType.summaryTypeNames());
        return persistDrafts(
                patientId, sourceRecordId, drafts, SummarySourceKey.CALL_KIND);
    }

    /**
     * Replays one call summary using authoritative entity data for citation metadata backfill.
     * The row lock serializes this operation with normal outbox ingestion.
     */
    @Transactional
    public SummaryCitationReplayOutcome replaySummaryCitationMetadata(
            final Long summaryId,
            final Long candidatePatientId) {
        if (summaryId == null) {
            throw new IllegalArgumentException("summaryId is required");
        }
        final CallSummary summary = callSummaryRepository.findByIdForUpdate(summaryId)
                .orElseThrow(() -> new IllegalArgumentException(
                        "CallSummary not found for summaryId=" + summaryId));
        if (candidatePatientId == null
                || summary.getPatientId() == null
                || !candidatePatientId.equals(summary.getPatientId())) {
            return SummaryCitationReplayOutcome.QUARANTINED;
        }
        final String contentHash = ContentHashUtil.sha256(summary.getSummaryJson());
        final List<IndexingChunkDraft> expectedDrafts = summaryChunker.chunk(
                "call",
                summary.getSummaryJson(),
                contentHash,
                summary.getCaregiverVisibility(),
                summary.getSummarizationEngine(),
                summary.getCallId(),
                summary.getGeneratedAt() == null
                        ? null
                        : summary.getGeneratedAt()
                                .atZone(ZoneOffset.UTC)
                                .toInstant()
                                .toString());
        if (expectedDrafts.isEmpty()
                || (summary.getStatus() != null
                    && !"SUCCESS".equalsIgnoreCase(summary.getStatus().trim()))) {
            return SummaryCitationReplayOutcome.NO_DRAFTS;
        }
        final SummaryCreatedPayload replay = new SummaryCreatedPayload(
                "call",
                "call_summaries",
                summary.getId(),
                summary.getCallId(),
                summary.getPatientId(),
                summary.getStatus(),
                summary.getGeneratedAt(),
                summary.getTranscriptSegmentCount(),
                summary.getCaregiverVisibility(),
                summary.getSummarizationEngine(),
                contentHash);
        final int written = ingestSummaryCreated(replay);
        return written > 0
                ? SummaryCitationReplayOutcome.UPDATED
                : SummaryCitationReplayOutcome.CURRENT;
    }

    /**
     * Embed-only recovery when chunks already exist. Returns 0 (no new chunks written).
     */
    private int retryMissingEmbeddingsOrSkip(
            final Long patientId,
            final List<String> sourceRecordIds,
            final Long summaryId,
            final String skipReason) {
        if (chunkRepository.countMissingEmbeddingForSummarySources(
                patientId, sourceRecordIds, RetrievalRecordType.summaryTypeNames()) > 0) {
            log.info(
                    "SUMMARY_CREATED for summaryId={} — embeddings missing; retrying embed without re-chunk",
                    summaryId);
            scheduleEmbeddingAfterCommit(
                    chunkRepository.findMissingEmbeddingsForSummarySources(
                            patientId,
                            sourceRecordIds,
                            RetrievalRecordType.summaryTypeNames()));
        } else {
            log.info("Skipping SUMMARY_CREATED for summaryId={} — {}", summaryId, skipReason);
        }
        return 0;
    }

    /**
     * Indexes all transcript segments for a call. Uses {@code callId} as
     * {@code source_record_id} so re-delivery replaces the prior segment set.
     * Defers when patientId cannot be resolved. {@code IndexWorker} burns attempt
     * budget on {@link IndexingDeferredException} by default so deferred rows
     * eventually dead-letter.
     *
     * @return number of chunks written
     */
    @Transactional
    public int ingestTranscriptIndexed(final TranscriptIndexedPayload payload) {
        if (payload == null || payload.callId() == null || payload.callId().isBlank()) {
            throw new IllegalArgumentException("TRANSCRIPT_INDEXED payload requires callId");
        }
        final String callId = payload.callId().trim();
        final Long patientId = resolvePatientIdForCall(payload.patientId(), callId);
        if (patientId == null) {
            throw new IndexingDeferredException(
                    "Cannot index transcript for callId=" + callId
                            + " — patientId is required on retrieval_index_chunk");
        }

        final List<CallTranscriptSegment> segments =
                transcriptSegmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc(callId);
        final List<IndexingChunkDraft> drafts =
                transcriptSegmentChunker.chunk(callId, payload.source(), segments);

        if (drafts.isEmpty()) {
            log.warn(
                    "TRANSCRIPT_INDEXED produced no drafts for callId={}; leaving existing chunks unchanged",
                    callId);
            return 0;
        }

        chunkRepository.deleteBySourceRecordIdAndRecordType(
                callId, RetrievalRecordType.TRANSCRIPT_SEGMENT.name());
        return persistDrafts(patientId, callId, drafts);
    }

    /**
     * Indexes a persisted USPS mailpiece into {@code retrieval_index_chunk}
     * with {@link RetrievalRecordType#USPS_MAIL} (Task 3.14.5). Embedding
     * remains null until Task 4.3; FTS is maintained by the DB trigger.
     *
     * @return number of chunks written (0 when skipped)
     */
    @Transactional
    public int ingestMailpieceIndexed(final MailpieceIndexedPayload payload) {
        if (payload == null || payload.mailpieceId() == null) {
            throw new IllegalArgumentException("MAILPIECE_INDEXED payload requires mailpieceId");
        }
        if (payload.patientId() == null) {
            throw new IndexingDeferredException(
                    "Cannot index mailpieceId=" + payload.mailpieceId()
                            + " — patientId is required on retrieval_index_chunk");
        }

        final String sourceRecordId = String.valueOf(payload.mailpieceId());
        final UspsMailpiece mailpiece = uspsMailpieceRepository.findById(payload.mailpieceId())
                .orElseThrow(() -> new IllegalArgumentException(
                        "UspsMailpiece not found for mailpieceId=" + payload.mailpieceId()));

        final String contentHash = firstNonBlank(payload.contentHash(), mailpiece.getContentHash());
        if (contentHash != null
                && !contentHash.isBlank()
                && shouldSkipUspsMailReindex(sourceRecordId, contentHash, mailpiece)) {
            log.info("Skipping MAILPIECE_INDEXED for mailpieceId={} — contentHash+importance unchanged",
                    payload.mailpieceId());
            return 0;
        }

        final String sender = firstNonBlank(payload.sender(), mailpiece.getSender());
        final String summary = firstNonBlank(payload.summary(), mailpiece.getSummary());
        final String sourceKey = firstNonBlank(payload.sourceKey(), mailpiece.getSourceKey());
        final String consentScope = firstNonBlank(
                payload.consentScope(), mailpiece.getConsentScope());

        final List<IndexingChunkDraft> drafts = mailpieceChunker.chunk(
                sender,
                summary,
                mailpiece.getOcrText(),
                contentHash,
                sourceKey,
                payload.digestDate() != null ? payload.digestDate() : mailpiece.getDigestDate(),
                consentScope,
                mailpiece.getImportanceLevel(),
                mailpiece.getImportanceCategory(),
                mailpiece.getClassificationMethod(),
                mailpiece.getImportanceReasoning());

        if (drafts.isEmpty()) {
            log.warn(
                    "MAILPIECE_INDEXED produced no drafts for mailpieceId={}; leaving existing chunks unchanged",
                    payload.mailpieceId());
            return 0;
        }

        chunkRepository.deleteBySourceRecordIdAndRecordType(
                sourceRecordId, RetrievalRecordType.USPS_MAIL.name());
        return persistDrafts(payload.patientId(), sourceRecordId, drafts);
    }

    private int persistDrafts(
            final Long patientId,
            final String sourceRecordId,
            final List<IndexingChunkDraft> drafts) {
        return persistDrafts(patientId, sourceRecordId, drafts, null);
    }

    private int persistDrafts(
            final Long patientId,
            final String sourceRecordId,
            final List<IndexingChunkDraft> drafts,
            final String sourceKind) {
        final OffsetDateTime now = OffsetDateTime.now(ZoneOffset.UTC);
        final List<RetrievalIndexChunk> entities = new ArrayList<>(drafts.size());
        for (final IndexingChunkDraft draft : drafts) {
            if (draft == null || draft.chunkText() == null || draft.chunkText().isBlank()) {
                continue;
            }
            entities.add(RetrievalIndexChunk.builder()
                    .patientId(patientId)
                    .recordType(draft.recordType().name())
                    .sourceRecordId(truncateSourceId(sourceRecordId))
                    .sourceKind(sourceKind)
                    .citationReplayAttempts(0)
                    .migrationStatus(RetrievalMigrationStatus.ACTIVE.name())
                    .chunkText(draft.chunkText())
                    .chunkMetadata(toJson(draft.metadata()))
                    .consentScope(truncateConsent(draft.consentScope()))
                    .indexedAt(now)
                    .build());
        }
        if (entities.isEmpty()) {
            return 0;
        }
        final List<RetrievalIndexChunk> saved = chunkRepository.saveAll(entities);
        log.info("Indexed {} chunk(s) for sourceRecordId={} patientId={}",
                saved.size(), sourceRecordId, patientId);
        scheduleEmbeddingAfterCommit(saved);
        return saved.size();
    }

    /**
     * Runs Titan embedding after the current transaction commits so Bedrock latency
     * does not hold a JDBC connection or extend the ingest lock window. When no
     * synchronization is active (unit tests), embeds immediately.
     */
    private void scheduleEmbeddingAfterCommit(final List<RetrievalIndexChunk> chunks) {
        if (chunks == null || chunks.isEmpty()) {
            return;
        }
        final List<RetrievalIndexChunk> snapshot = List.copyOf(chunks);
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    chunkEmbeddingService.embedAndPersist(snapshot);
                }
            });
        } else {
            chunkEmbeddingService.embedAndPersist(snapshot);
        }
    }

    private boolean chunksMatchExpected(
            final List<RetrievalIndexChunk> existing,
            final List<IndexingChunkDraft> expectedDrafts,
            final String contentHash,
            final String expectedSourceRecordId) {
        if (existing == null
                || expectedDrafts == null
                || existing.size() != expectedDrafts.size()
                || existing.isEmpty()) {
            return false;
        }

        final Map<String, IndexingChunkDraft> expectedBySignature = new HashMap<>();
        for (final IndexingChunkDraft draft : expectedDrafts) {
            final String signature =
                    draft.recordType().name() + ":" + draft.metadata().get("chunkIndex");
            if (expectedBySignature.put(signature, draft) != null) {
                return false;
            }
        }

        for (final RetrievalIndexChunk chunk : existing) {
            final JsonNode metadata = parseChunkMetadata(chunk.getChunkMetadata());
            if (metadata == null
                    || !expectedSourceRecordId.equals(chunk.getSourceRecordId())
                    || !SummarySourceKey.CALL_KIND.equals(chunk.getSourceKind())
                    || !contentHash.equals(metadata.path("contentHash").asText(null))
                    || metadata.path("citationMetadataVersion").asInt(-1)
                            < SummaryChunker.CITATION_METADATA_VERSION
                    || !metadata.path("chunkIndex").isIntegralNumber()) {
                return false;
            }
            final String signature =
                    chunk.getRecordType() + ":" + metadata.path("chunkIndex").asInt();
            final IndexingChunkDraft expected = expectedBySignature.remove(signature);
            if (expected == null
                    || !Objects.equals(
                            truncateConsent(chunk.getConsentScope()),
                            truncateConsent(expected.consentScope()))
                    || !containsExpectedMetadata(metadata, expected.metadata())) {
                return false;
            }
        }
        return expectedBySignature.isEmpty();
    }

    private boolean containsExpectedMetadata(
            final JsonNode actual, final Map<String, Object> expectedMetadata) {
        final JsonNode expected = objectMapper.valueToTree(expectedMetadata);
        final Iterator<Map.Entry<String, JsonNode>> fields = expected.fields();
        while (fields.hasNext()) {
            final Map.Entry<String, JsonNode> field = fields.next();
            if (!Objects.equals(actual.get(field.getKey()), field.getValue())) {
                return false;
            }
        }
        return true;
    }

    private JsonNode parseChunkMetadata(final String chunkMetadataJson) {
        if (chunkMetadataJson == null || chunkMetadataJson.isBlank()) {
            return null;
        }
        try {
            final JsonNode metadata = objectMapper.readTree(chunkMetadataJson);
            return metadata != null && metadata.isObject() ? metadata : null;
        } catch (final Exception ex) {
            log.debug("Unable to parse retrieval chunk metadata: {}", ex.getMessage());
            return null;
        }
    }

    /**
     * Skip only when an existing USPS_MAIL chunk already has the same contentHash
     * <em>and</em> the same importance fingerprint. Classification-only backfills
     * (hash unchanged, importance newly present on the entity) must rebuild chunks.
     */
    private boolean shouldSkipUspsMailReindex(
            final String sourceRecordId,
            final String contentHash,
            final UspsMailpiece mailpiece) {
        final List<RetrievalIndexChunk> existing =
                chunkRepository.findBySourceRecordIdAndRecordType(
                        sourceRecordId, RetrievalRecordType.USPS_MAIL.name());
        if (existing == null || existing.isEmpty()) {
            return false;
        }
        final String expectedFingerprint = MailpieceChunker.importanceFingerprint(
                mailpiece.getImportanceLevel(),
                mailpiece.getImportanceCategory(),
                mailpiece.getClassificationMethod(),
                mailpiece.getImportanceReasoning());
        for (final RetrievalIndexChunk chunk : existing) {
            if (!contentHashEquals(chunk.getChunkMetadata(), contentHash)) {
                continue;
            }
            if (uspsMailNeedsClassificationRefresh(chunk.getChunkMetadata(), expectedFingerprint)) {
                return false;
            }
            return true;
        }
        return false;
    }

    /**
     * Force rebuild when the entity has classification but chunk metadata is missing
     * it (or the fingerprint differs).
     */
    private boolean uspsMailNeedsClassificationRefresh(
            final String chunkMetadataJson,
            final String expectedFingerprint) {
        if (expectedFingerprint == null || expectedFingerprint.isBlank()) {
            return false;
        }
        if (chunkMetadataJson == null || chunkMetadataJson.isBlank()) {
            return true;
        }
        try {
            final JsonNode meta = objectMapper.readTree(chunkMetadataJson);
            final String storedFingerprint = meta.path("importanceFingerprint").asText(null);
            if (storedFingerprint != null && !storedFingerprint.isBlank()) {
                return !expectedFingerprint.equals(storedFingerprint);
            }
            final String storedLevel = meta.path("importanceLevel").asText(null);
            return storedLevel == null || storedLevel.isBlank();
        } catch (final Exception ex) {
            log.debug("Unable to parse chunk metadata for importance compare: {}", ex.getMessage());
            return true;
        }
    }

    private boolean contentHashEquals(final String chunkMetadataJson, final String contentHash) {
        if (chunkMetadataJson == null || chunkMetadataJson.isBlank() || contentHash == null) {
            return false;
        }
        try {
            final JsonNode meta = objectMapper.readTree(chunkMetadataJson);
            final String stored = meta.path("contentHash").asText(null);
            return contentHash.equals(stored);
        } catch (final Exception ex) {
            log.debug("Unable to parse chunk metadata for contentHash compare: {}", ex.getMessage());
            return false;
        }
    }

    private Long resolvePatientIdForCall(final Long payloadPatientId, final String callId) {
        if (payloadPatientId != null) {
            return payloadPatientId;
        }
        final Optional<CallSummary> latest =
                callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc(callId);
        return latest.map(CallSummary::getPatientId).orElse(null);
    }

    private String toJson(final Object metadata) {
        if (metadata == null) {
            return null;
        }
        try {
            return objectMapper.writeValueAsString(metadata);
        } catch (final JsonProcessingException ex) {
            throw new IllegalStateException("Failed to serialize chunk metadata", ex);
        }
    }

    private static boolean isVisitSummary(final SummaryCreatedPayload payload) {
        final String sourceTable = payload.sourceTable();
        final String episodeType = payload.episodeType();
        return (sourceTable != null && sourceTable.trim().equalsIgnoreCase("visit_summaries"))
                || (episodeType != null && episodeType.trim().equalsIgnoreCase("visit"));
    }

    private static String truncateSourceId(final String sourceRecordId) {
        if (sourceRecordId == null) {
            return null;
        }
        if (sourceRecordId.length() <= RetrievalIndexSchema.SOURCE_RECORD_ID_MAX_LENGTH) {
            return sourceRecordId;
        }
        return sourceRecordId.substring(0, RetrievalIndexSchema.SOURCE_RECORD_ID_MAX_LENGTH);
    }

    private static String truncateConsent(final String consentScope) {
        if (consentScope == null || consentScope.isBlank()) {
            return null;
        }
        final String trimmed = consentScope.trim().toLowerCase(Locale.ROOT);
        if (trimmed.length() <= RetrievalIndexSchema.CONSENT_SCOPE_MAX_LENGTH) {
            return trimmed;
        }
        return trimmed.substring(0, RetrievalIndexSchema.CONSENT_SCOPE_MAX_LENGTH);
    }

    private static Long firstNonNull(final Long a, final Long b) {
        return a != null ? a : b;
    }

    private static String firstNonBlank(final String a, final String b) {
        if (a != null && !a.isBlank()) {
            return a;
        }
        if (b != null && !b.isBlank()) {
            return b;
        }
        return a;
    }
}
