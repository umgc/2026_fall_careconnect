package com.careconnect.service.ai.indexing;

import com.careconnect.indexing.ClinicalNoteIndexedPayload;
import com.careconnect.indexing.DocumentIndexedPayload;
import com.careconnect.indexing.MailpieceIndexedPayload;
import com.careconnect.indexing.SummaryCreatedPayload;
import com.careconnect.indexing.TranscriptIndexedPayload;
import com.careconnect.model.CallSummary;
import com.careconnect.model.CallSession;
import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.model.PatientNote;
import com.careconnect.model.UserFile;
import com.careconnect.model.UspsMailpiece;
import com.careconnect.model.VisitSummary;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.model.retrieval.RetrievalIndexSchema;
import com.careconnect.repository.CallSummaryRepository;
import com.careconnect.repository.CallSessionRepository;
import com.careconnect.repository.PatientNoteRepository;
import com.careconnect.repository.UserFileRepository;
import com.careconnect.repository.UspsMailpieceRepository;
import com.careconnect.repository.VisitSummaryRepository;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.service.CallTranscriptService;
import com.careconnect.service.FileManagementService;
import com.careconnect.service.ai.indexing.chunker.ClinicalNoteChunker;
import com.careconnect.service.ai.indexing.chunker.DocumentChunker;
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

import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

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
    private final VisitSummaryRepository visitSummaryRepository;
    private final CallSessionRepository callSessionRepository;
    private final CallTranscriptService callTranscriptService;
    private final UspsMailpieceRepository uspsMailpieceRepository;
    private final PatientNoteRepository patientNoteRepository;
    private final UserFileRepository userFileRepository;
    private final RetrievalIndexChunkRepository chunkRepository;
    private final SummaryChunker summaryChunker;
    private final TranscriptSegmentChunker transcriptSegmentChunker;
    private final MailpieceChunker mailpieceChunker;
    private final ClinicalNoteChunker clinicalNoteChunker;
    private final DocumentChunker documentChunker;
    private final ObjectMapper objectMapper;
    private final ChunkEmbeddingService chunkEmbeddingService;

    public RetrievalIndexService(
            final CallSummaryRepository callSummaryRepository,
            final VisitSummaryRepository visitSummaryRepository,
            final CallSessionRepository callSessionRepository,
            final CallTranscriptService callTranscriptService,
            final UspsMailpieceRepository uspsMailpieceRepository,
            final PatientNoteRepository patientNoteRepository,
            final UserFileRepository userFileRepository,
            final RetrievalIndexChunkRepository chunkRepository,
            final SummaryChunker summaryChunker,
            final TranscriptSegmentChunker transcriptSegmentChunker,
            final MailpieceChunker mailpieceChunker,
            final ClinicalNoteChunker clinicalNoteChunker,
            final DocumentChunker documentChunker,
            final ObjectMapper objectMapper,
            final ChunkEmbeddingService chunkEmbeddingService) {
        this.callSummaryRepository = callSummaryRepository;
        this.visitSummaryRepository = visitSummaryRepository;
        this.callSessionRepository = callSessionRepository;
        this.callTranscriptService = callTranscriptService;
        this.uspsMailpieceRepository = uspsMailpieceRepository;
        this.patientNoteRepository = patientNoteRepository;
        this.userFileRepository = userFileRepository;
        this.chunkRepository = chunkRepository;
        this.summaryChunker = summaryChunker;
        this.transcriptSegmentChunker = transcriptSegmentChunker;
        this.mailpieceChunker = mailpieceChunker;
        this.clinicalNoteChunker = clinicalNoteChunker;
        this.documentChunker = documentChunker;
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
            return ingestVisitSummaryCreated(payload);
        }

        final String sourceRecordId = SummarySourceKey.call(payload.summaryId());
        final String legacySourceRecordId = SummarySourceKey.legacy(payload.summaryId());
        final List<String> sourceRecordIds = List.of(sourceRecordId);
        final CallSummary summary = callSummaryRepository.findByIdForUpdate(payload.summaryId())
                .orElseThrow(() -> new IllegalArgumentException(
                        "CallSummary not found for summaryId=" + payload.summaryId()));

        if (!"SUCCESS".equalsIgnoreCase(
                java.util.Objects.toString(summary.getStatus(), "").trim())) {
            throw new IndexingDeferredException(
                    "Authoritative CallSummary is not successful");
        }
        final Long patientId = summary.getPatientId();
        if (patientId == null) {
            throw new IndexingDeferredException(
                    "Cannot index summaryId=" + payload.summaryId()
                            + " — authoritative patientId is required");
        }
        if (payload.patientId() != null && !payload.patientId().equals(patientId)) {
            throw new IndexingDeferredException(
                    "SUMMARY_CREATED patient scope does not match authoritative summary row");
        }
        final String contentHash = ContentHashUtil.sha256(summary.getSummaryJson());
        if (payload.contentHash() != null
                && !payload.contentHash().isBlank()
                && !payload.contentHash().equals(contentHash)) {
            throw new IndexingDeferredException(
                    "SUMMARY_CREATED content hash does not match authoritative summary");
        }

        final String episodeType = "call";
        if (summary.getSummarizationEngine() != null
                && !summary.getSummarizationEngine().isBlank()
                && payload.summarizationEngine() != null
                && !payload.summarizationEngine().isBlank()
                && !Objects.equals(payload.summarizationEngine(), summary.getSummarizationEngine())) {
            throw new IndexingDeferredException(
                    "SUMMARY_CREATED engine does not match authoritative summary");
        }
        final String caregiverVisibility = summary.getCaregiverVisibility();
        final String engine = summary.getSummarizationEngine();

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

        chunkRepository.quarantineLegacySummarySourceAcrossPatients(
                legacySourceRecordId,
                RetrievalRecordType.summaryTypeNames());
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
     * Task 1.4 / 3.5 — indexes a successful visit summary using the shared SummaryChunker.
     */
    @Transactional
    public int ingestVisitSummaryCreated(final SummaryCreatedPayload payload) {
        if (payload == null || payload.summaryId() == null) {
            throw new IllegalArgumentException("SUMMARY_CREATED payload requires summaryId");
        }
        final String sourceRecordId = SummarySourceKey.visit(payload.summaryId());
        final List<String> sourceRecordIds = List.of(sourceRecordId);
        final VisitSummary summary = visitSummaryRepository.findByIdForUpdate(payload.summaryId())
                .orElseThrow(() -> new IndexingDeferredException(
                        "VisitSummary not found for summaryId=" + payload.summaryId(),
                        false));

        if (!"SUCCESS".equalsIgnoreCase(
                java.util.Objects.toString(summary.getStatus(), "").trim())) {
            throw new IndexingDeferredException(
                    "Authoritative VisitSummary is not successful");
        }
        final Long patientId = summary.getPatientId();
        if (patientId == null) {
            throw new IndexingDeferredException(
                    "Cannot index visit summaryId=" + payload.summaryId()
                            + " — authoritative patientId is required");
        }
        if (payload.patientId() != null && !payload.patientId().equals(patientId)) {
            throw new IndexingDeferredException(
                    "SUMMARY_CREATED patient scope does not match authoritative visit summary row");
        }
        final String contentHash = ContentHashUtil.sha256(summary.getSummaryJson());
        if (payload.contentHash() != null
                && !payload.contentHash().isBlank()
                && !payload.contentHash().equals(contentHash)) {
            throw new IndexingDeferredException(
                    "SUMMARY_CREATED content hash does not match authoritative visit summary");
        }
        if (summary.getSummarizationEngine() != null
                && !summary.getSummarizationEngine().isBlank()
                && payload.summarizationEngine() != null
                && !payload.summarizationEngine().isBlank()
                && !Objects.equals(payload.summarizationEngine(), summary.getSummarizationEngine())) {
            throw new IndexingDeferredException(
                    "SUMMARY_CREATED engine does not match authoritative visit summary");
        }

        final List<IndexingChunkDraft> drafts = summaryChunker.chunk(
                "visit",
                summary.getSummaryJson(),
                contentHash,
                summary.getCaregiverVisibility(),
                summary.getSummarizationEngine(),
                summary.getVisitId(),
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
                        sourceRecordId,
                        SummarySourceKey.VISIT_KIND,
                        RetrievalRecordType.summaryTypeNames());

        if (drafts.isEmpty()) {
            log.warn(
                    "VISIT SUMMARY_CREATED produced no drafts for summaryId={}; leaving existing chunks unchanged",
                    payload.summaryId());
            return retryMissingEmbeddingsOrSkip(
                    patientId,
                    sourceRecordIds,
                    payload.summaryId(),
                    "no drafts; existing visit chunks left unchanged");
        }

        if (contentHash != null
                && chunksMatchExpected(existing, drafts, contentHash, sourceRecordId)) {
            return retryMissingEmbeddingsOrSkip(
                    patientId,
                    sourceRecordIds,
                    payload.summaryId(),
                    "visit contentHash and citation metadata unchanged");
        }

        chunkRepository.deleteCallSummaryChunksForReplacement(
                patientId,
                sourceRecordId,
                sourceRecordId,
                SummarySourceKey.VISIT_KIND,
                RetrievalRecordType.summaryTypeNames());
        return persistDrafts(
                patientId, sourceRecordId, drafts, SummarySourceKey.VISIT_KIND);
    }

    /**
     * Replays one call summary using authoritative entity data for citation metadata backfill.
     * The row lock serializes this operation with normal outbox ingestion. Claim tokens are
     * renewed and verified immediately before replacement so stale owners mutate nothing.
     */
    @Transactional
    public SummaryCitationReplayOutcome replaySummaryCitationMetadata(
            final Long summaryId,
            final Long candidatePatientId,
            final UUID claimToken,
            final long claimLeaseMs) {
        if (summaryId == null) {
            throw new IllegalArgumentException("summaryId is required");
        }
        if (candidatePatientId == null || claimToken == null) {
            return SummaryCitationReplayOutcome.TERMINAL_QUARANTINED;
        }
        final String sourceRecordId = SummarySourceKey.call(summaryId);
        if (!renewReplayClaim(candidatePatientId, sourceRecordId, claimToken, claimLeaseMs)) {
            return SummaryCitationReplayOutcome.BUSY;
        }
        final String lockKey = "summary-citation:"
                + candidatePatientId + ":" + summaryId;
        if (!chunkRepository.tryAcquireSummaryReplayLock(lockKey)) {
            return SummaryCitationReplayOutcome.BUSY;
        }
        if (!renewReplayClaim(candidatePatientId, sourceRecordId, claimToken, claimLeaseMs)) {
            return SummaryCitationReplayOutcome.BUSY;
        }
        final CallSummary summary = callSummaryRepository.findByIdForUpdate(summaryId)
                .orElse(null);
        if (summary == null
                || summary.getPatientId() == null
                || !candidatePatientId.equals(summary.getPatientId())) {
            return SummaryCitationReplayOutcome.TERMINAL_QUARANTINED;
        }
        if (summary.getStatus() == null
                || !"SUCCESS".equalsIgnoreCase(summary.getStatus().trim())) {
            return SummaryCitationReplayOutcome.TERMINAL_QUARANTINED;
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
        if (expectedDrafts.isEmpty()) {
            return SummaryCitationReplayOutcome.RETRYABLE;
        }
        if (!renewReplayClaim(candidatePatientId, sourceRecordId, claimToken, claimLeaseMs)) {
            return SummaryCitationReplayOutcome.BUSY;
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
        if (!chunkRepository.hasActiveSummaryCitationReplayClaim(
                candidatePatientId, sourceRecordId, claimToken)) {
            return SummaryCitationReplayOutcome.BUSY;
        }
        final int written = ingestSummaryCreated(replay);
        return written > 0
                ? SummaryCitationReplayOutcome.UPDATED
                : SummaryCitationReplayOutcome.CURRENT;
    }

    private boolean renewReplayClaim(
            final Long patientId,
            final String sourceRecordId,
            final UUID claimToken,
            final long claimLeaseMs) {
        final long leaseMs = Math.min(
                Duration.ofHours(1).toMillis(),
                Math.max(10_000L, claimLeaseMs));
        return chunkRepository.renewSummaryCitationReplayClaim(
                patientId,
                sourceRecordId,
                claimToken,
                OffsetDateTime.now(ZoneOffset.UTC).plus(Duration.ofMillis(leaseMs))) > 0;
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
     * Patient ownership comes only from the authoritative {@code CallSession}.
     * A payload patient is an integrity assertion, never an ownership source.
     *
     * @return number of chunks written
     */
    @Transactional
    public int ingestTranscriptIndexed(final TranscriptIndexedPayload payload) {
        if (payload == null || payload.callId() == null || payload.callId().isBlank()) {
            throw new IllegalArgumentException("TRANSCRIPT_INDEXED payload requires callId");
        }
        final String callId = payload.callId().trim();
        final CallSession session = callSessionRepository.findByCallIdForIndexing(callId)
                .orElseThrow(() -> new IndexingDeferredException(
                        "Cannot index transcript for callId=" + callId
                                + " — authoritative CallSession is not available",
                        false));
        final Long patientId = session.getPatientId();
        if (patientId == null) {
            throw new IndexingDeferredException(
                    "Cannot index transcript for callId=" + callId
                            + " — authoritative CallSession patientId is required",
                    false);
        }
        if (payload.patientId() != null && !payload.patientId().equals(patientId)) {
            throw new IndexingDeferredException(
                    "TRANSCRIPT_INDEXED patient scope does not match authoritative CallSession");
        }
        if (payload.totalSegmentCount() < 0) {
            throw new IllegalArgumentException(
                    "TRANSCRIPT_INDEXED totalSegmentCount cannot be negative");
        }

        chunkRepository.acquireSourceReplacementLock(
                patientId, RetrievalRecordType.TRANSCRIPT_SEGMENT.name(), callId);
        final CallTranscriptService.IndexingSnapshot snapshot =
                callTranscriptService.captureIndexingSnapshot(callId);
        final List<CallTranscriptSegment> segments = snapshot.segments();
        if (segments.size() > payload.totalSegmentCount()) {
            log.info(
                    "TRANSCRIPT_INDEXED snapshot superseded for callId={} expectedCount={} currentCount={}",
                    callId, payload.totalSegmentCount(), segments.size());
            return 0;
        }
        if (segments.size() < payload.totalSegmentCount()
                || payload.snapshotVersion() == null
                || !payload.snapshotVersion().equals(snapshot.version())) {
            throw new IndexingDeferredException(
                    "Transcript snapshot is incomplete or not yet authoritative for callId="
                            + callId + " (expected count/version "
                            + payload.totalSegmentCount() + "/" + payload.snapshotVersion()
                            + ", found " + segments.size() + "/" + snapshot.version() + ")",
                    false);
        }
        final List<IndexingChunkDraft> drafts =
                transcriptSegmentChunker.chunk(callId, null, segments);

        if (drafts.isEmpty()) {
            log.warn(
                    "TRANSCRIPT_INDEXED produced no drafts for callId={}; leaving existing chunks unchanged",
                    callId);
            return 0;
        }

        chunkRepository.deleteByPatientIdAndSourceRecordIdAndRecordType(
                patientId, callId, RetrievalRecordType.TRANSCRIPT_SEGMENT.name());
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
        final String sourceRecordId = String.valueOf(payload.mailpieceId());
        final UspsMailpiece mailpiece = uspsMailpieceRepository.findByIdForUpdate(payload.mailpieceId())
                .orElseThrow(() -> new IllegalArgumentException(
                        "UspsMailpiece not found for mailpieceId=" + payload.mailpieceId()));
        final Long patientId = mailpiece.getPatientId();
        if (patientId == null) {
            throw new IndexingDeferredException(
                    "Cannot index mailpieceId=" + payload.mailpieceId()
                            + " — authoritative patientId is required");
        }
        assertMailpieceEventMatches(payload, mailpiece);
        chunkRepository.acquireSourceReplacementLock(
                patientId, RetrievalRecordType.USPS_MAIL.name(), sourceRecordId);

        final String contentHash = mailpiece.getContentHash();
        if (contentHash != null
                && !contentHash.isBlank()
                && shouldSkipUspsMailReindex(patientId, sourceRecordId, contentHash, mailpiece)) {
            log.info("Skipping MAILPIECE_INDEXED for mailpieceId={} — contentHash+importance unchanged",
                    payload.mailpieceId());
            return 0;
        }

        final List<IndexingChunkDraft> drafts = mailpieceChunker.chunk(
                mailpiece.getSender(),
                mailpiece.getSummary(),
                mailpiece.getOcrText(),
                contentHash,
                mailpiece.getSourceKey(),
                mailpiece.getDigestDate(),
                mailpiece.getConsentScope(),
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

        chunkRepository.deleteByPatientIdAndSourceRecordIdAndRecordType(
                patientId, sourceRecordId, RetrievalRecordType.USPS_MAIL.name());
        return persistDrafts(patientId, sourceRecordId, drafts);
    }

    /**
     * Indexes a persisted patient note into {@code retrieval_index_chunk} with
     * {@link RetrievalRecordType#CLINICAL_NOTE} (Task 4.1). Mirrors
     * {@link #ingestMailpieceIndexed} — loads the authoritative entity, chunks it, and
     * replaces prior chunks for the same {@code source_record_id}.
     *
     * @return number of chunks written (0 when skipped)
     */
    @Transactional
    public int ingestClinicalNoteIndexed(final ClinicalNoteIndexedPayload payload) {
        if (payload == null || payload.noteId() == null) {
            throw new IllegalArgumentException("CLINICAL_NOTE_INDEXED payload requires noteId");
        }
        final String sourceRecordId = String.valueOf(payload.noteId());
        final PatientNote note = patientNoteRepository.findById(payload.noteId())
                .orElseThrow(() -> new IllegalArgumentException(
                        "PatientNote not found for noteId=" + payload.noteId()));
        final Long patientId = note.getPatientId();
        if (patientId == null) {
            throw new IndexingDeferredException(
                    "Cannot index noteId=" + payload.noteId()
                            + " — authoritative patientId is required");
        }
        if (payload.patientId() != null && !payload.patientId().equals(patientId)) {
            throw new IndexingDeferredException(
                    "CLINICAL_NOTE_INDEXED patient scope does not match authoritative PatientNote");
        }
        final String contentHash = ContentHashUtil.clinicalNoteContentHash(
                note.getNote(), note.getAiSummary());
        if (payload.contentHash() != null
                && !payload.contentHash().isBlank()
                && !payload.contentHash().equals(contentHash)) {
            throw new IndexingDeferredException(
                    "CLINICAL_NOTE_INDEXED content hash does not match authoritative PatientNote");
        }
        chunkRepository.acquireSourceReplacementLock(
                patientId, RetrievalRecordType.CLINICAL_NOTE.name(), sourceRecordId);

        if (chunkContentUnchanged(
                patientId, sourceRecordId, RetrievalRecordType.CLINICAL_NOTE, contentHash)) {
            log.info("Skipping CLINICAL_NOTE_INDEXED for noteId={} — contentHash unchanged",
                    payload.noteId());
            return 0;
        }

        final List<IndexingChunkDraft> drafts = clinicalNoteChunker.chunk(
                note.getNote(), note.getAiSummary(), contentHash, payload.consentScope());

        if (drafts.isEmpty()) {
            log.warn(
                    "CLINICAL_NOTE_INDEXED produced no drafts for noteId={}; "
                            + "leaving existing chunks unchanged",
                    payload.noteId());
            return 0;
        }

        chunkRepository.deleteByPatientIdAndSourceRecordIdAndRecordType(
                patientId, sourceRecordId, RetrievalRecordType.CLINICAL_NOTE.name());
        return persistDrafts(patientId, sourceRecordId, drafts);
    }

    /**
     * Removes all retrieval chunks for a source (note, document, etc.) so deleted
     * records are no longer returned by Ask AI. Call before or as part of soft/hard delete.
     */
    @Transactional
    public void removeIndexedSource(
            final Long patientId,
            final String sourceRecordId,
            final RetrievalRecordType recordType) {
        if (patientId == null
                || sourceRecordId == null
                || sourceRecordId.isBlank()
                || recordType == null) {
            throw new IllegalArgumentException(
                    "patientId, sourceRecordId, and recordType are required to de-index");
        }
        chunkRepository.acquireSourceReplacementLock(
                patientId, recordType.name(), sourceRecordId);
        chunkRepository.deleteByPatientIdAndSourceRecordIdAndRecordType(
                patientId, sourceRecordId, recordType.name());
    }

    /**
     * Indexes an uploaded document's description and/or extracted plain text into
     * {@code retrieval_index_chunk} with {@link RetrievalRecordType#UPLOADED_DOCUMENT}.
     * Long excerpts are window-chunked by {@link DocumentChunker}. Scanned images without
     * OCR still fall back to description/caption only.
     * Mirrors {@link #ingestMailpieceIndexed} — loads the authoritative {@link UserFile},
     * chunks it, and replaces prior chunks for the same {@code source_record_id}.
     *
     * @return number of chunks written (0 when skipped)
     */
    @Transactional
    public int ingestDocumentIndexed(final DocumentIndexedPayload payload) {
        if (payload == null || payload.fileId() == null) {
            throw new IllegalArgumentException("DOCUMENT_INDEXED payload requires fileId");
        }
        final String sourceRecordId = String.valueOf(payload.fileId());
        final UserFile file = userFileRepository.findById(payload.fileId())
                .orElseThrow(() -> new IllegalArgumentException(
                        "UserFile not found for fileId=" + payload.fileId()));
        final Long patientId = file.getPatientId();
        if (patientId == null) {
            throw new IndexingDeferredException(
                    "Cannot index fileId=" + payload.fileId()
                            + " — authoritative patientId is required");
        }
        if (payload.patientId() != null && !payload.patientId().equals(patientId)) {
            throw new IndexingDeferredException(
                    "DOCUMENT_INDEXED patient scope does not match authoritative UserFile");
        }

        // Soft-deleted files must leave the retrieval index (late outbox events included).
        if (Boolean.FALSE.equals(file.getIsActive())) {
            removeIndexedSource(
                    patientId, sourceRecordId, RetrievalRecordType.UPLOADED_DOCUMENT);
            log.info("De-indexed soft-deleted DOCUMENT for fileId={}", payload.fileId());
            return 0;
        }

        chunkRepository.acquireSourceReplacementLock(
                patientId, RetrievalRecordType.UPLOADED_DOCUMENT.name(), sourceRecordId);

        // Re-load after lock to close soft-delete TOCTOU with concurrent deleteFile.
        final UserFile locked = userFileRepository.findById(payload.fileId())
                .orElseThrow(() -> new IllegalArgumentException(
                        "UserFile not found for fileId=" + payload.fileId()));
        if (Boolean.FALSE.equals(locked.getIsActive())) {
            chunkRepository.deleteByPatientIdAndSourceRecordIdAndRecordType(
                    patientId, sourceRecordId, RetrievalRecordType.UPLOADED_DOCUMENT.name());
            log.info("De-indexed soft-deleted DOCUMENT after lock for fileId={}", payload.fileId());
            return 0;
        }

        // Authoritative description + extracted text (not stale outbox excerpt).
        final String textExcerpt = FileManagementService.indexableDocumentText(locked);
        if (textExcerpt == null || textExcerpt.isBlank()) {
            chunkRepository.deleteByPatientIdAndSourceRecordIdAndRecordType(
                    patientId, sourceRecordId, RetrievalRecordType.UPLOADED_DOCUMENT.name());
            log.info(
                    "DOCUMENT_INDEXED skipped blank text for fileId={}; chunks cleared",
                    payload.fileId());
            return 0;
        }

        final String contentHash = ContentHashUtil.sha256(textExcerpt);
        if (payload.contentHash() != null
                && !payload.contentHash().isBlank()
                && !payload.contentHash().equals(contentHash)) {
            throw new IndexingDeferredException(
                    "DOCUMENT_INDEXED content hash does not match authoritative UserFile");
        }

        if (chunkContentUnchanged(
                patientId, sourceRecordId, RetrievalRecordType.UPLOADED_DOCUMENT, contentHash)) {
            log.info("Skipping DOCUMENT_INDEXED for fileId={} — contentHash unchanged",
                    payload.fileId());
            return 0;
        }

        final String fileCategory = firstNonBlank(
                payload.fileCategory(),
                locked.getFileCategory() == null ? null : locked.getFileCategory().name());
        final List<IndexingChunkDraft> drafts = documentChunker.chunk(
                textExcerpt, fileCategory, contentHash, payload.consentScope());

        if (drafts.isEmpty()) {
            log.warn(
                    "DOCUMENT_INDEXED produced no drafts for fileId={}; "
                            + "leaving existing chunks unchanged",
                    payload.fileId());
            return 0;
        }

        chunkRepository.deleteByPatientIdAndSourceRecordIdAndRecordType(
                patientId, sourceRecordId, RetrievalRecordType.UPLOADED_DOCUMENT.name());
        return persistDrafts(patientId, sourceRecordId, drafts);
    }

    private boolean chunkContentUnchanged(
            final Long patientId,
            final String sourceRecordId,
            final RetrievalRecordType recordType,
            final String contentHash) {
        if (contentHash == null || contentHash.isBlank()) {
            return false;
        }
        final List<RetrievalIndexChunk> existing =
                chunkRepository.findByPatientIdAndSourceRecordIdAndRecordType(
                        patientId, sourceRecordId, recordType.name());
        if (existing == null || existing.isEmpty()) {
            return false;
        }
        for (final RetrievalIndexChunk chunk : existing) {
            if (!contentHashEquals(chunk.getChunkMetadata(), contentHash)) {
                return false;
            }
        }
        return true;
    }

    private static String firstNonBlank(final String a, final String b) {
        return a != null && !a.isBlank() ? a : b;
    }

    private static void assertMailpieceEventMatches(
            final MailpieceIndexedPayload payload,
            final UspsMailpiece mailpiece) {
        if (!Objects.equals(payload.patientId(), mailpiece.getPatientId())
                || !Objects.equals(payload.sourceKey(), mailpiece.getSourceKey())
                || !Objects.equals(payload.contentHash(), mailpiece.getContentHash())
                || !Objects.equals(payload.sender(), mailpiece.getSender())
                || !Objects.equals(payload.summary(), mailpiece.getSummary())
                || !Objects.equals(payload.digestDate(), mailpiece.getDigestDate())
                || !Objects.equals(payload.consentScope(), mailpiece.getConsentScope())) {
            throw new IndexingDeferredException(
                    "MAILPIECE_INDEXED event does not match authoritative UspsMailpiece");
        }
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
        if (SummarySourceKey.CALL_KIND.equals(sourceKind)) {
            chunkRepository.registerSummaryCitationReplaySource(
                    patientId, sourceKind, truncateSourceId(sourceRecordId));
        }
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
            final Long patientId,
            final String sourceRecordId,
            final String contentHash,
            final UspsMailpiece mailpiece) {
        final List<RetrievalIndexChunk> existing =
                chunkRepository.findByPatientIdAndSourceRecordIdAndRecordType(
                        patientId, sourceRecordId, RetrievalRecordType.USPS_MAIL.name());
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

}
