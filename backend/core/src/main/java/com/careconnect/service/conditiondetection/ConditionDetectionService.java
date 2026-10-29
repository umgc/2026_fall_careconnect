package com.careconnect.service.conditiondetection;

import com.careconnect.model.CallRecording;
import com.careconnect.model.CallSession;
import com.careconnect.model.conditiondetection.ConditionDetectionContext;
import com.careconnect.model.conditiondetection.ConditionDetectionRun;
import com.careconnect.model.conditiondetection.ConditionFinding;
import com.careconnect.model.conditiondetection.ConditionFlag;
import com.careconnect.model.conditiondetection.ConditionRunState;
import com.careconnect.model.conditiondetection.ConditionSkipReason;
import com.careconnect.repository.CallRecordingRepository;
import com.careconnect.repository.conditiondetection.ConditionDetectionRunRepository;
import com.careconnect.repository.conditiondetection.ConditionFlagRepository;
import com.careconnect.repository.projection.ConditionDueRunProjection;
import com.careconnect.service.CallSessionService;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.annotation.Lazy;
import org.springframework.context.event.EventListener;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Orchestrates post-call condition screening across every registered
 * {@link ConditionModelAdapter}.
 *
 * <p>{@link #enqueueForCall} creates one durable run per (call, adapter) as soon as the call's
 * recording is finalized. A scheduled worker leases runs with the same claim → work (no DB
 * transaction) → finish pattern as {@code PostCallTranscriptionService}, so slow CPU inference
 * or Bedrock calls never pin a pooled connection.</p>
 */
@Slf4j
@Service
public class ConditionDetectionService {

    /** Calls shorter than this are skipped by every model (DAM's speech minimum). */
    static final long MIN_CALL_SECONDS = 30L;

    /** Lease long enough for CPU-only DAM inference on a long call. */
    static final long LEASE_SECONDS = 1800L;

    static final long RETRY_DELAY_SECONDS = 120L;

    private static final int MAX_ERROR_LENGTH = 500;

    private final ObjectProvider<ConditionModelAdapter> adapterProvider;
    private final ConditionDetectionRunRepository runRepository;
    private final ConditionFlagRepository flagRepository;
    private final CallSessionService callSessionService;
    private final CallRecordingRepository recordingRepository;
    private final ConditionRunLanes lanes;

    @Value("${careconnect.condition-detection.enabled:true}")
    private boolean enabled;

    @Value("${careconnect.condition-detection.max-attempts:5}")
    private int maxAttempts;

    /** Past the voice audio limit (20 h): older calls would only be skipped as expired. */
    @Value("${careconnect.condition-detection.reconcile.lookback-hours:24}")
    private long reconcileLookbackHours;

    @Autowired
    @Lazy
    private ConditionDetectionService self;

    public ConditionDetectionService(
            final ObjectProvider<ConditionModelAdapter> adapterProvider,
            final ConditionDetectionRunRepository runRepository,
            final ConditionFlagRepository flagRepository,
            final CallSessionService callSessionService,
            final CallRecordingRepository recordingRepository,
            final ConditionRunLanes lanes) {
        this.adapterProvider = adapterProvider;
        this.runRepository = runRepository;
        this.flagRepository = flagRepository;
        this.callSessionService = callSessionService;
        this.recordingRepository = recordingRepository;
        this.lanes = lanes;
    }

    /** Every enabled adapter, in registration order. */
    public List<ConditionModelAdapter> adapters() {
        return adapterProvider.orderedStream().toList();
    }

    public boolean isEnabled() {
        return enabled;
    }

    /**
     * Creates one run per enabled adapter for an ended call. Idempotent: re-running termination
     * or {@link #reconcileMissingRuns} never duplicates runs. Short calls and calls without a recording get
     * their run created directly as SKIPPED so the UI can say why.
     *
     * <p>Deliberately not {@code @Transactional}: each run commits on its own, so a duplicate
     * key from a concurrent enqueue cannot roll back the other adapters' runs.</p>
     */
    public void enqueueForCall(final String callId) {
        if (!enabled || callId == null || callId.isBlank()) {
            return;
        }
        final List<ConditionModelAdapter> adapters = adapters();
        if (adapters.isEmpty()) {
            return;
        }
        final CallSession session = callSessionService.requireSession(callId);
        final Long patientUserId = callSessionService.requirePatientUserId(session);
        final CallRecording recording =
                recordingRepository.findTopByCallIdOrderByStartedAtDesc(callId).orElse(null);
        final ConditionSkipReason upfrontSkip = upfrontSkipReason(recording);

        for (final ConditionModelAdapter adapter : adapters) {
            if (runRepository.findByCallIdAndModelId(callId, adapter.modelId()).isPresent()) {
                continue;
            }
            final ConditionDetectionRun run = new ConditionDetectionRun();
            run.setCallId(callId);
            run.setPatientId(session.getPatientId());
            run.setPatientUserId(patientUserId);
            run.setModelId(adapter.modelId());
            run.setInputKind(adapter.inputKind());
            run.setConfigVersion(adapter.configVersion());
            if (upfrontSkip == null) {
                run.setState(ConditionRunState.READY);
            } else {
                run.setState(ConditionRunState.SKIPPED);
                run.setSkipReason(upfrontSkip);
                run.setCompletedAt(LocalDateTime.now(ZoneOffset.UTC));
            }
            try {
                runRepository.saveAndFlush(run);
                if (upfrontSkip == null) {
                    // Align due time to the DB clock (see markDueNow) so the worker sees it now.
                    runRepository.markDueNow(run.getId());
                }
            } catch (DataIntegrityViolationException duplicate) {
                // A concurrent termination attempt enqueued the same (call, model) first.
                if (log.isDebugEnabled()) {
                    log.debug("Condition run for call {} model {} already exists",
                            callId, adapter.modelId());
                }
            }
        }
    }

    private static ConditionSkipReason upfrontSkipReason(final CallRecording recording) {
        if (recording == null) {
            return ConditionSkipReason.NO_RECORDING;
        }
        final Long duration = recording.getDurationSeconds();
        if (duration != null && duration < MIN_CALL_SECONDS) {
            return ConditionSkipReason.CALL_TOO_SHORT;
        }
        return null;
    }

    /**
     * Hands due runs to their model's lane and returns at once. The analysis itself never runs
     * on the shared scheduler thread (see {@link ConditionRunLanes}). Due runs are fetched per
     * model, so a backlog in one model's lane never keeps another model's runs from being queued.
     */
    @Scheduled(fixedDelayString = "${careconnect.condition-detection.worker.interval-ms:30000}")
    public void runDueRuns() {
        if (!enabled) {
            return;
        }
        final ConditionDetectionService worker = self == null ? this : self;
        for (final String modelId : runRepository.findDueModelIds()) {
            for (final ConditionDueRunProjection due : runRepository.findDueRuns(modelId)) {
                final Long id = due.getId().longValue();
                lanes.submit(due.getModelId(), id, () -> worker.processRun(id));
            }
        }
    }

    /**
     * Creates runs that termination failed to create. Termination swallows enqueue failures so a
     * DB hiccup never blocks ending a call, and nothing else would revisit that call. Only fully
     * ended calls are considered, so the recording is final and never misread as missing.
     */
    @Scheduled(fixedDelayString = "${careconnect.condition-detection.reconcile.interval-ms:600000}")
    public void reconcileMissingRuns() {
        if (!enabled) {
            return;
        }
        final List<String> modelIds = adapters().stream().map(ConditionModelAdapter::modelId).toList();
        if (modelIds.isEmpty()) {
            return;
        }
        for (final String callId : runRepository.findEndedCallsMissingRuns(
                reconcileLookbackHours, modelIds, modelIds.size())) {
            try {
                enqueueForCall(callId);
            } catch (RuntimeException e) {
                // One bad call must not stop the batch; it is retried next pass until it ages out.
                if (log.isWarnEnabled()) {
                    log.warn("Could not reconcile condition runs for call {}: {}",
                            callId, e.getClass().getSimpleName());
                }
            }
        }
    }

    /** Drain any backlog as soon as the app is up. */
    @EventListener(ApplicationReadyEvent.class)
    public void processDueRunsOnStartup() {
        runDueRuns();
    }

    /** Claims a run, runs the adapter outside any DB transaction, then finishes it. */
    public void processRun(final Long id) {
        final UUID token = UUID.randomUUID();
        final ConditionDetectionService worker = self == null ? this : self;
        final ClaimedRun claimed = worker.claimRun(id, token);
        if (claimed == null) {
            return;
        }
        final Optional<ConditionModelAdapter> adapter = findAdapter(claimed.modelId());
        if (adapter.isEmpty()) {
            // The adapter was disabled after this run was enqueued.
            worker.finishRun(id, token, new AdapterOutcome.Skipped(ConditionSkipReason.MODEL_UNAVAILABLE));
            return;
        }
        final AdapterOutcome outcome;
        try {
            outcome = adapter.get().analyze(claimed.context());
        } catch (Exception failure) {
            if (log.isWarnEnabled()) {
                log.warn("Condition model {} failed for call {} (attempt {}): {}",
                        claimed.modelId(), claimed.context().callId(), claimed.attemptCount(),
                        failure.getClass().getSimpleName());
            }
            worker.failRun(id, token, claimed.attemptCount(), describe(failure));
            return;
        }
        if (outcome instanceof AdapterOutcome.Deferred deferred) {
            runRepository.defer(id, token, Math.max(deferred.delaySeconds(), 1L));
            return;
        }
        worker.finishRun(id, token, outcome);
    }

    @Transactional
    public ClaimedRun claimRun(final Long id, final UUID token) {
        if (runRepository.claim(id, token, LEASE_SECONDS) != 1) {
            return null;
        }
        final ConditionDetectionRun run = runRepository.findByIdAndClaimToken(id, token).orElse(null);
        if (run == null) {
            return null;
        }
        run.setState(ConditionRunState.RUNNING);
        runRepository.save(run);
        final Long recordingId = recordingRepository
                .findTopByCallIdOrderByStartedAtDesc(run.getCallId())
                .map(CallRecording::getId)
                .orElse(null);
        return new ClaimedRun(
                run.getModelId(),
                run.getAttemptCount(),
                new ConditionDetectionContext(
                        run.getCallId(),
                        run.getPatientId(),
                        run.getPatientUserId(),
                        recordingId,
                        run.getCreatedAt()));
    }

    /** Stores a COMPLETE or SKIPPED outcome. A lost lease (token mismatch) is a no-op. */
    @Transactional
    public void finishRun(final Long id, final UUID token, final AdapterOutcome outcome) {
        final ConditionDetectionRun run = runRepository.findByIdAndClaimToken(id, token).orElse(null);
        if (run == null) {
            return;
        }
        flagRepository.deleteByRunId(id);
        if (outcome instanceof AdapterOutcome.Completed completed) {
            for (final ConditionFinding finding : completed.findings()) {
                flagRepository.save(toFlag(run, finding));
            }
            run.setState(ConditionRunState.COMPLETE);
            run.setSkipReason(null);
            run.setSpeechSeconds(completed.speechSeconds());
        } else if (outcome instanceof AdapterOutcome.Skipped skipped) {
            run.setState(ConditionRunState.SKIPPED);
            run.setSkipReason(skipped.reason());
            run.setSpeechSeconds(skipped.speechSeconds());
        } else {
            throw new IllegalArgumentException("finishRun does not accept " + outcome);
        }
        run.setClaimToken(null);
        run.setClaimedUntil(null);
        run.setLastError(null);
        run.setCompletedAt(LocalDateTime.now(ZoneOffset.UTC));
        runRepository.save(run);
    }

    /** Re-queues after a failure, or marks the run FAILED once attempts are exhausted. */
    @Transactional
    public void failRun(final Long id, final UUID token, final int attemptCount, final String error) {
        if (attemptCount < maxAttempts) {
            runRepository.releaseForRetry(id, token, RETRY_DELAY_SECONDS, error);
            return;
        }
        final ConditionDetectionRun run = runRepository.findByIdAndClaimToken(id, token).orElse(null);
        if (run == null) {
            return;
        }
        run.setState(ConditionRunState.FAILED);
        run.setClaimToken(null);
        run.setClaimedUntil(null);
        run.setLastError(error);
        run.setCompletedAt(LocalDateTime.now(ZoneOffset.UTC));
        runRepository.save(run);
    }

    Optional<ConditionModelAdapter> findAdapter(final String modelId) {
        return adapters().stream().filter(a -> a.modelId().equals(modelId)).findFirst();
    }

    private static ConditionFlag toFlag(final ConditionDetectionRun run, final ConditionFinding finding) {
        final ConditionFlag flag = new ConditionFlag();
        flag.setRunId(run.getId());
        flag.setCallId(run.getCallId());
        flag.setPatientId(run.getPatientId());
        flag.setModelId(run.getModelId());
        flag.setConditionName(finding.condition());
        flag.setSeverityLevel(finding.severityLevel());
        flag.setSeverityLabel(finding.severityLabel());
        flag.setRawScore(finding.rawScore());
        flag.setEvidenceSummary(finding.evidenceSummary());
        return flag;
    }

    /**
     * Error text stored on the run. Adapters throw messages they wrote themselves (never model
     * or transcript content), but cap the length regardless.
     */
    static String describe(final Exception failure) {
        final String message = failure.getMessage();
        final String text = failure.getClass().getSimpleName()
                + (message == null || message.isBlank() ? "" : ": " + message);
        return text.length() <= MAX_ERROR_LENGTH ? text : text.substring(0, MAX_ERROR_LENGTH);
    }

    /** Claim snapshot used after the short claim transaction commits. */
    public record ClaimedRun(String modelId, int attemptCount, ConditionDetectionContext context) {
    }
}
