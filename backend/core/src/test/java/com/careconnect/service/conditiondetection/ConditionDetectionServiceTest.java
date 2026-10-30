package com.careconnect.service.conditiondetection;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.careconnect.model.CallRecording;
import com.careconnect.model.CallSession;
import com.careconnect.model.conditiondetection.ConditionDetectionContext;
import com.careconnect.model.conditiondetection.ConditionDetectionRun;
import com.careconnect.model.conditiondetection.ConditionFinding;
import com.careconnect.model.conditiondetection.ConditionFlag;
import com.careconnect.model.conditiondetection.ConditionInputKind;
import com.careconnect.model.conditiondetection.ConditionName;
import com.careconnect.model.conditiondetection.ConditionRunState;
import com.careconnect.model.conditiondetection.ConditionSkipReason;
import com.careconnect.repository.CallRecordingRepository;
import com.careconnect.repository.conditiondetection.ConditionDetectionRunRepository;
import com.careconnect.repository.conditiondetection.ConditionFlagRepository;
import com.careconnect.repository.projection.ConditionDueRunProjection;
import com.careconnect.service.CallSessionService;
import com.careconnect.testsupport.fixtures.ConditionDetectionFixtures;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Stream;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * Unit tests for {@link ConditionDetectionService}: enqueue rules, reconciliation of calls whose
 * runs were never created, the claim / work / finish lease cycle and error text handling.
 *
 * <p>Repositories, the session service and adapters are Mockito mocks because they are
 * database and network boundaries; the service's own branching is the thing under test. Entities
 * come from {@code ConditionDetectionFixtures}.</p>
 */
@ExtendWith(MockitoExtension.class)
class ConditionDetectionServiceTest {

    private static final String CALL_ID = ConditionDetectionFixtures.CALL_ID;
    private static final Long PATIENT_ID = ConditionDetectionFixtures.PATIENT_ID;
    private static final Long PATIENT_USER_ID = ConditionDetectionFixtures.PATIENT_USER_ID;
    private static final String MODEL_A = "model-a";
    private static final String MODEL_B = "model-b";

    @Mock
    private ObjectProvider<ConditionModelAdapter> adapterProvider;
    @Mock
    private ConditionDetectionRunRepository runRepository;
    @Mock
    private ConditionFlagRepository flagRepository;
    @Mock
    private CallSessionService callSessionService;
    @Mock
    private CallRecordingRepository recordingRepository;

    private ConditionDetectionService service;

    /** Lanes that run work inline, so a tick's runs finish before runDueRuns returns. */
    private final ConditionRunLanes inlineLanes = new ConditionRunLanes(modelId -> Runnable::run);

    @BeforeEach
    void setUp() {
        service = new ConditionDetectionService(
                adapterProvider, runRepository, flagRepository, callSessionService, recordingRepository,
                inlineLanes);
        ReflectionTestUtils.setField(service, "enabled", true);
        ReflectionTestUtils.setField(service, "maxAttempts", 5);
    }

    private ConditionModelAdapter adapter(final String modelId) {
        final ConditionModelAdapter adapter = Mockito.mock(ConditionModelAdapter.class);
        Mockito.lenient().when(adapter.modelId()).thenReturn(modelId);
        Mockito.lenient().when(adapter.inputKind()).thenReturn(ConditionInputKind.PATIENT_AUDIO);
        Mockito.lenient().when(adapter.configVersion()).thenReturn("cfg-" + modelId);
        return adapter;
    }

    private void registerAdapters(final ConditionModelAdapter... adapters) {
        when(adapterProvider.orderedStream()).thenAnswer(inv -> Stream.of(adapters));
    }

    private CallSession stubSession() {
        final CallSession session = ConditionDetectionFixtures.session();
        when(callSessionService.requireSession(CALL_ID)).thenReturn(session);
        when(callSessionService.requirePatientUserId(session)).thenReturn(PATIENT_USER_ID);
        return session;
    }

    private CallRecording recording(final Long durationSeconds) {
        return ConditionDetectionFixtures.recording(durationSeconds);
    }

    // ---------------------------------------------------------------- enqueue

    /** Scenario: the feature flag is off, so enqueue must not even resolve adapters. */
    @Test
    void enqueue_disabled_touchesNothing() {
        ReflectionTestUtils.setField(service, "enabled", false);

        service.enqueueForCall(CALL_ID);

        verifyNoInteractions(adapterProvider, runRepository, callSessionService, recordingRepository);
    }

    /** Scenario: a missing call id is ignored rather than throwing during call termination. */
    @Test
    void enqueue_blankOrNullCallId_isIgnored() {
        service.enqueueForCall(null);
        service.enqueueForCall("  ");

        verifyNoInteractions(adapterProvider, runRepository, callSessionService, recordingRepository);
    }

    /** Scenario: detection is on but every adapter is disabled, so no session lookup or run is made. */
    @Test
    void enqueue_noAdapters_createsNothing() {
        registerAdapters();

        service.enqueueForCall(CALL_ID);

        verifyNoInteractions(runRepository, callSessionService, recordingRepository);
    }

    /** Scenario: a 600 s call (well above the 30 s minimum) with two adapters gets one READY run each, carrying the session and adapter metadata. */
    @Test
    void enqueue_normalCall_createsOneReadyRunPerAdapter() {
        registerAdapters(adapter(MODEL_A), adapter(MODEL_B));
        stubSession();
        when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                .thenReturn(Optional.of(recording(600L)));
        when(runRepository.findByCallIdAndModelId(eq(CALL_ID), any())).thenReturn(Optional.empty());

        service.enqueueForCall(CALL_ID);

        final ArgumentCaptor<ConditionDetectionRun> captor =
                ArgumentCaptor.forClass(ConditionDetectionRun.class);
        verify(runRepository, Mockito.times(2)).saveAndFlush(captor.capture());
        assertThat(captor.getAllValues()).extracting(ConditionDetectionRun::getModelId)
                .containsExactly(MODEL_A, MODEL_B);
        assertThat(captor.getAllValues()).allSatisfy(run -> {
            assertThat(run.getCallId()).isEqualTo(CALL_ID);
            assertThat(run.getPatientId()).isEqualTo(PATIENT_ID);
            assertThat(run.getPatientUserId()).isEqualTo(PATIENT_USER_ID);
            assertThat(run.getInputKind()).isEqualTo(ConditionInputKind.PATIENT_AUDIO);
            assertThat(run.getState()).isEqualTo(ConditionRunState.READY);
            assertThat(run.getSkipReason()).isNull();
            assertThat(run.getCompletedAt()).isNull();
        });
        assertThat(captor.getAllValues().get(0).getConfigVersion()).isEqualTo("cfg-" + MODEL_A);
        assertThat(captor.getAllValues().get(1).getConfigVersion()).isEqualTo("cfg-" + MODEL_B);
        // Due time must come from the DB clock: a Java-written next_attempt_at is shifted by
        // hibernate.jdbc.time_zone=UTC on non-UTC hosts and would sit hours in the future.
        verify(runRepository, Mockito.times(2)).markDueNow(any());
    }

    /** Scenario: model A already has a run for this call (re-termination); only model B is created. */
    @Test
    void enqueue_existingRun_isNotResaved() {
        registerAdapters(adapter(MODEL_A), adapter(MODEL_B));
        stubSession();
        when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                .thenReturn(Optional.of(recording(600L)));
        when(runRepository.findByCallIdAndModelId(CALL_ID, MODEL_A))
                .thenReturn(Optional.of(new ConditionDetectionRun()));
        when(runRepository.findByCallIdAndModelId(CALL_ID, MODEL_B)).thenReturn(Optional.empty());

        service.enqueueForCall(CALL_ID);

        final ArgumentCaptor<ConditionDetectionRun> captor =
                ArgumentCaptor.forClass(ConditionDetectionRun.class);
        verify(runRepository).saveAndFlush(captor.capture());
        assertThat(captor.getValue().getModelId()).isEqualTo(MODEL_B);
    }

    /** Scenario: 29 s is one below the 30 s minimum, so the run is created already SKIPPED with a completion time. */
    @Test
    void enqueue_callUnderThirtySeconds_isSkippedCallTooShort() {
        registerAdapters(adapter(MODEL_A));
        stubSession();
        when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                .thenReturn(Optional.of(recording(29L)));
        when(runRepository.findByCallIdAndModelId(CALL_ID, MODEL_A)).thenReturn(Optional.empty());

        service.enqueueForCall(CALL_ID);

        final ArgumentCaptor<ConditionDetectionRun> captor =
                ArgumentCaptor.forClass(ConditionDetectionRun.class);
        verify(runRepository).saveAndFlush(captor.capture());
        assertThat(captor.getValue().getState()).isEqualTo(ConditionRunState.SKIPPED);
        assertThat(captor.getValue().getSkipReason()).isEqualTo(ConditionSkipReason.CALL_TOO_SHORT);
        assertThat(captor.getValue().getCompletedAt()).isNotNull();
        verify(runRepository, never()).markDueNow(any());
    }

    /** Scenario: exactly 30 s is the boundary and is long enough, so the run is READY. */
    @Test
    void enqueue_callExactlyThirtySeconds_isReady() {
        registerAdapters(adapter(MODEL_A));
        stubSession();
        when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                .thenReturn(Optional.of(recording(30L)));
        when(runRepository.findByCallIdAndModelId(CALL_ID, MODEL_A)).thenReturn(Optional.empty());

        service.enqueueForCall(CALL_ID);

        final ArgumentCaptor<ConditionDetectionRun> captor =
                ArgumentCaptor.forClass(ConditionDetectionRun.class);
        verify(runRepository).saveAndFlush(captor.capture());
        assertThat(captor.getValue().getState()).isEqualTo(ConditionRunState.READY);
    }

    /** Scenario: duration not yet populated (null) must not be treated as too short. */
    @Test
    void enqueue_unknownDuration_isReady() {
        registerAdapters(adapter(MODEL_A));
        stubSession();
        when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                .thenReturn(Optional.of(recording(null)));
        when(runRepository.findByCallIdAndModelId(CALL_ID, MODEL_A)).thenReturn(Optional.empty());

        service.enqueueForCall(CALL_ID);

        final ArgumentCaptor<ConditionDetectionRun> captor =
                ArgumentCaptor.forClass(ConditionDetectionRun.class);
        verify(runRepository).saveAndFlush(captor.capture());
        assertThat(captor.getValue().getState()).isEqualTo(ConditionRunState.READY);
    }

    /** Scenario: the call has no recording row, so the UI can say why with SKIPPED / NO_RECORDING. */
    @Test
    void enqueue_noRecording_isSkippedNoRecording() {
        registerAdapters(adapter(MODEL_A));
        stubSession();
        when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                .thenReturn(Optional.empty());
        when(runRepository.findByCallIdAndModelId(CALL_ID, MODEL_A)).thenReturn(Optional.empty());

        service.enqueueForCall(CALL_ID);

        final ArgumentCaptor<ConditionDetectionRun> captor =
                ArgumentCaptor.forClass(ConditionDetectionRun.class);
        verify(runRepository).saveAndFlush(captor.capture());
        assertThat(captor.getValue().getState()).isEqualTo(ConditionRunState.SKIPPED);
        assertThat(captor.getValue().getSkipReason()).isEqualTo(ConditionSkipReason.NO_RECORDING);
        assertThat(captor.getValue().getCompletedAt()).isNotNull();
    }

    /** Scenario: a concurrent enqueue wins the unique key for the first adapter; the second adapter must still be saved. */
    @Test
    void enqueue_duplicateKeyOnOneAdapter_doesNotStopTheNext() {
        registerAdapters(adapter(MODEL_A), adapter(MODEL_B));
        stubSession();
        when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                .thenReturn(Optional.of(recording(600L)));
        when(runRepository.findByCallIdAndModelId(eq(CALL_ID), any())).thenReturn(Optional.empty());
        when(runRepository.saveAndFlush(any(ConditionDetectionRun.class)))
                .thenThrow(new DataIntegrityViolationException("duplicate"))
                .thenAnswer(inv -> inv.getArgument(0));

        service.enqueueForCall(CALL_ID);

        final ArgumentCaptor<ConditionDetectionRun> captor =
                ArgumentCaptor.forClass(ConditionDetectionRun.class);
        verify(runRepository, Mockito.times(2)).saveAndFlush(captor.capture());
        assertThat(captor.getAllValues().get(1).getModelId()).isEqualTo(MODEL_B);
    }

    // ------------------------------------------------------------- processRun

    private ConditionDetectionRun claimedRun(final Long id, final String modelId) {
        final ConditionDetectionRun run =
                ConditionDetectionFixtures.run(id, modelId, ConditionRunState.CLAIMED);
        run.setClaimToken(UUID.randomUUID());
        run.setClaimedUntil(LocalDateTime.now(ZoneOffset.UTC).plusMinutes(30));
        run.setLastError("old");
        return run;
    }

    /** Stubs a successful claim, returning the run the claim loads. */
    private ConditionDetectionRun stubClaim(final Long id, final String modelId, final int attempts) {
        final ConditionDetectionRun run = claimedRun(id, modelId);
        run.setAttemptCount(attempts);
        when(runRepository.claim(eq(id), any(UUID.class), eq(ConditionDetectionService.LEASE_SECONDS)))
                .thenReturn(1);
        when(runRepository.findByIdAndClaimToken(eq(id), any(UUID.class))).thenReturn(Optional.of(run));
        when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                .thenReturn(Optional.of(recording(600L)));
        return run;
    }

    /** Scenario: another worker holds the lease (claim updates 0 rows), so nothing runs. */
    @Test
    void processRun_claimReturnsZero_adapterNeverCalled() throws Exception {
        final ConditionModelAdapter adapter = adapter(MODEL_A);
        when(runRepository.claim(eq(1L), any(UUID.class), anyLong())).thenReturn(0);

        service.processRun(1L);

        verify(adapter, never()).analyze(any());
        verify(runRepository, never()).save(any());
        verifyNoInteractions(flagRepository, adapterProvider);
    }

    /** Scenario: a successful claim flips the run to RUNNING and snapshots the context, using attempt count 2 so the copy is visible. */
    @Test
    void claimRun_marksRunningAndBuildsContext() {
        final ConditionDetectionRun run = stubClaim(1L, MODEL_A, 2);
        final ConditionDetectionService.ClaimedRun claimed = service.claimRun(1L, UUID.randomUUID());

        assertThat(run.getState()).isEqualTo(ConditionRunState.RUNNING);
        verify(runRepository).save(run);
        assertThat(claimed.modelId()).isEqualTo(MODEL_A);
        assertThat(claimed.attemptCount()).isEqualTo(2);
        assertThat(claimed.context()).isEqualTo(new ConditionDetectionContext(
                CALL_ID, PATIENT_ID, PATIENT_USER_ID, 55L, run.getCreatedAt()));
    }

    /** Scenario: the claim update succeeded but the token lookup finds nothing (row deleted); claim yields null. */
    @Test
    void claimRun_leaseRowVanishedAfterClaim_returnsNull() {
        final UUID token = UUID.randomUUID();
        when(runRepository.claim(1L, token, ConditionDetectionService.LEASE_SECONDS)).thenReturn(1);
        when(runRepository.findByIdAndClaimToken(1L, token)).thenReturn(Optional.empty());

        assertThat(service.claimRun(1L, token)).isNull();
        verify(runRepository, never()).save(any());
    }

    /** Scenario: the adapter returns two findings; flags replace any old ones and the run is COMPLETE with its lease cleared. */
    @Test
    void processRun_completed_savesFlagsAndCompletesRun() throws Exception {
        final ConditionModelAdapter adapter = adapter(MODEL_A);
        registerAdapters(adapter);
        final ConditionDetectionRun run = stubClaim(1L, MODEL_A, 1);
        when(adapter.analyze(any())).thenReturn(new AdapterOutcome.Completed(
                List.of(
                        new ConditionFinding(ConditionName.DEPRESSION, 1, "MILD_TO_MODERATE", 0.42, null),
                        new ConditionFinding(ConditionName.ANXIETY, 0, "NONE", 0.1, "note")),
                12.5));

        service.processRun(1L);

        final InOrder order = Mockito.inOrder(flagRepository);
        order.verify(flagRepository).deleteByRunId(1L);
        final ArgumentCaptor<ConditionFlag> flags = ArgumentCaptor.forClass(ConditionFlag.class);
        order.verify(flagRepository, Mockito.times(2)).save(flags.capture());
        final ConditionFlag depression = flags.getAllValues().get(0);
        assertThat(depression.getRunId()).isEqualTo(1L);
        assertThat(depression.getCallId()).isEqualTo(CALL_ID);
        assertThat(depression.getPatientId()).isEqualTo(PATIENT_ID);
        assertThat(depression.getModelId()).isEqualTo(MODEL_A);
        assertThat(depression.getConditionName()).isEqualTo(ConditionName.DEPRESSION);
        assertThat(depression.getSeverityLevel()).isEqualTo(1);
        assertThat(depression.getSeverityLabel()).isEqualTo("MILD_TO_MODERATE");
        assertThat(depression.getRawScore()).isEqualTo(0.42);
        assertThat(depression.getEvidenceSummary()).isNull();
        assertThat(flags.getAllValues().get(1).getEvidenceSummary()).isEqualTo("note");

        assertThat(run.getState()).isEqualTo(ConditionRunState.COMPLETE);
        assertThat(run.getSpeechSeconds()).isEqualTo(12.5);
        assertThat(run.getSkipReason()).isNull();
        assertThat(run.getClaimToken()).isNull();
        assertThat(run.getClaimedUntil()).isNull();
        assertThat(run.getLastError()).isNull();
        assertThat(run.getCompletedAt()).isNotNull();
        verify(runRepository, Mockito.times(2)).save(run); // once on claim (RUNNING), once on finish
    }

    /** Scenario: a permanent no-result (3 s of speech) records the reason and speech seconds and stores no flags. */
    @Test
    void processRun_skipped_recordsReasonAndSpeechWithoutFlags() throws Exception {
        final ConditionModelAdapter adapter = adapter(MODEL_A);
        registerAdapters(adapter);
        final ConditionDetectionRun run = stubClaim(1L, MODEL_A, 1);
        when(adapter.analyze(any())).thenReturn(
                new AdapterOutcome.Skipped(ConditionSkipReason.INSUFFICIENT_SPEECH, 3.0));

        service.processRun(1L);

        verify(flagRepository).deleteByRunId(1L);
        verify(flagRepository, never()).save(any());
        assertThat(run.getState()).isEqualTo(ConditionRunState.SKIPPED);
        assertThat(run.getSkipReason()).isEqualTo(ConditionSkipReason.INSUFFICIENT_SPEECH);
        assertThat(run.getSpeechSeconds()).isEqualTo(3.0);
        assertThat(run.getClaimToken()).isNull();
        assertThat(run.getCompletedAt()).isNotNull();
    }

    /** Scenario: attempt 2 of max 5 fails, so the run is released with the 120 s retry delay and the described error. */
    @Test
    void processRun_adapterThrowsBelowMaxAttempts_releasesForRetry() throws Exception {
        final ConditionModelAdapter adapter = adapter(MODEL_A);
        registerAdapters(adapter);
        stubClaim(1L, MODEL_A, 2);
        when(adapter.analyze(any())).thenThrow(new IllegalStateException("sidecar down"));

        service.processRun(1L);

        verify(runRepository).releaseForRetry(
                eq(1L), any(UUID.class), eq(120L), eq("IllegalStateException: sidecar down"));
        verify(runRepository, never()).save(argThatFailed());
    }

    private static ConditionDetectionRun argThatFailed() {
        return Mockito.argThat(r -> r != null && r.getState() == ConditionRunState.FAILED);
    }

    /** Scenario: attempt 5 of max 5 fails, so the run is FAILED with lastError and no retry is scheduled. */
    @Test
    void processRun_adapterThrowsAtMaxAttempts_marksFailed() throws Exception {
        final ConditionModelAdapter adapter = adapter(MODEL_A);
        registerAdapters(adapter);
        final ConditionDetectionRun run = stubClaim(1L, MODEL_A, 5);
        when(adapter.analyze(any())).thenThrow(new IllegalStateException("sidecar down"));

        service.processRun(1L);

        verify(runRepository, never()).releaseForRetry(any(), any(), anyLong(), any());
        assertThat(run.getState()).isEqualTo(ConditionRunState.FAILED);
        assertThat(run.getLastError()).isEqualTo("IllegalStateException: sidecar down");
        assertThat(run.getClaimToken()).isNull();
        assertThat(run.getClaimedUntil()).isNull();
        assertThat(run.getCompletedAt()).isNotNull();
        verify(runRepository, Mockito.times(2)).save(run); // once on claim (RUNNING), once on failure
    }

    /** Scenario: the lease was lost before the terminal failure could be written; nothing is saved. */
    @Test
    void failRun_lostLeaseAtMaxAttempts_isNoOp() {
        when(runRepository.findByIdAndClaimToken(eq(1L), any(UUID.class))).thenReturn(Optional.empty());

        service.failRun(1L, UUID.randomUUID(), 5, "boom");

        verify(runRepository, never()).save(any());
    }

    /** Scenario: input not ready (recording finalizing); the run is re-queued with the adapter's delay and never finished. */
    @Test
    void processRun_deferred_defersAndDoesNotFinish() throws Exception {
        final ConditionModelAdapter adapter = adapter(MODEL_A);
        registerAdapters(adapter);
        stubClaim(1L, MODEL_A, 1);
        when(adapter.analyze(any())).thenReturn(new AdapterOutcome.Deferred(60L));

        service.processRun(1L);

        verify(runRepository).defer(eq(1L), any(UUID.class), eq(60L));
        verify(flagRepository, never()).deleteByRunId(any());
        verify(runRepository, never()).save(Mockito.argThat(
                r -> r != null && r.getState() != ConditionRunState.RUNNING));
    }

    /** Scenario: a zero delay would busy-loop, so it is clamped to one second. */
    @Test
    void processRun_deferredWithZeroDelay_isClampedToOneSecond() throws Exception {
        final ConditionModelAdapter adapter = adapter(MODEL_A);
        registerAdapters(adapter);
        stubClaim(1L, MODEL_A, 1);
        when(adapter.analyze(any())).thenReturn(new AdapterOutcome.Deferred(0L));

        service.processRun(1L);

        verify(runRepository).defer(eq(1L), any(UUID.class), eq(1L));
    }

    /** Scenario: the adapter was disabled after enqueue; the run ends SKIPPED / MODEL_UNAVAILABLE instead of retrying forever. */
    @Test
    void processRun_noMatchingAdapter_isSkippedModelUnavailable() {
        registerAdapters(adapter("other-model"));
        final ConditionDetectionRun run = stubClaim(1L, MODEL_A, 1);

        service.processRun(1L);

        assertThat(run.getState()).isEqualTo(ConditionRunState.SKIPPED);
        assertThat(run.getSkipReason()).isEqualTo(ConditionSkipReason.MODEL_UNAVAILABLE);
        verify(flagRepository, never()).save(any());
    }

    /** Scenario: the token no longer matches (lease expired and was re-claimed), so the stale worker writes nothing. */
    @Test
    void finishRun_lostLease_savesNothing() {
        when(runRepository.findByIdAndClaimToken(eq(1L), any(UUID.class))).thenReturn(Optional.empty());

        service.finishRun(1L, UUID.randomUUID(), new AdapterOutcome.Completed(
                List.of(new ConditionFinding(ConditionName.DEPRESSION, 0, "NONE", 0.1, null)), 5.0));

        verifyNoInteractions(flagRepository);
        verify(runRepository, never()).save(any());
    }

    /** Scenario: finishRun only accepts Completed or Skipped; a Deferred is a programming error. */
    @Test
    void finishRun_rejectsDeferredOutcome() {
        final ConditionDetectionRun run = claimedRun(1L, MODEL_A);
        when(runRepository.findByIdAndClaimToken(eq(1L), any(UUID.class))).thenReturn(Optional.of(run));

        org.assertj.core.api.Assertions
                .assertThatThrownBy(() -> service.finishRun(1L, UUID.randomUUID(), new AdapterOutcome.Deferred(5)))
                .isInstanceOf(IllegalArgumentException.class);
    }

    // ---------------------------------------------------- reconcileMissingRuns

    /**
     * Scenario: termination swallowed two enqueue failures. The first call is still broken (its
     * session lookup throws); the second must get its runs anyway, and the query must ask about
     * exactly the enabled models within the configured lookback.
     */
    @Test
    void reconcile_enqueuesEachMissingCall_andOneFailureDoesNotStopTheBatch() {
        // Arrange
        ReflectionTestUtils.setField(service, "reconcileLookbackHours", 24L);
        registerAdapters(adapter(MODEL_A), adapter(MODEL_B));
        when(runRepository.findEndedCallsMissingRuns(24L, List.of(MODEL_A, MODEL_B), 2L))
                .thenReturn(List.of("broken-call", CALL_ID));
        when(callSessionService.requireSession("broken-call")).thenThrow(new IllegalStateException("db"));
        stubSession();
        when(recordingRepository.findTopByCallIdOrderByStartedAtDesc(CALL_ID))
                .thenReturn(Optional.of(recording(600L)));
        when(runRepository.findByCallIdAndModelId(eq(CALL_ID), any())).thenReturn(Optional.empty());

        // Act
        service.reconcileMissingRuns();

        // Assert: both of the healthy call's runs were created despite the earlier failure.
        final ArgumentCaptor<ConditionDetectionRun> captor = ArgumentCaptor.forClass(ConditionDetectionRun.class);
        verify(runRepository, Mockito.times(2)).saveAndFlush(captor.capture());
        assertThat(captor.getAllValues()).extracting(ConditionDetectionRun::getCallId).containsOnly(CALL_ID);
    }

    /** Scenario: the feature is off, so the reconciliation query is never run. */
    @Test
    void reconcile_disabled_neverQueries() {
        ReflectionTestUtils.setField(service, "enabled", false);

        service.reconcileMissingRuns();

        verifyNoInteractions(runRepository, adapterProvider);
    }

    /** Scenario: no adapter is enabled, so no call can be missing a run. */
    @Test
    void reconcile_noAdapters_neverQueries() {
        registerAdapters();

        service.reconcileMissingRuns();

        verifyNoInteractions(runRepository);
    }

    // -------------------------------------------------------------- runDueRuns

    /** A due-run row as the native query returns it (the id arrives as a generic Number). */
    private static ConditionDueRunProjection due(final long id, final String modelId) {
        return new ConditionDueRunProjection() {
            @Override
            public Number getId() {
                return id;
            }

            @Override
            public String getModelId() {
                return modelId;
            }
        };
    }

    /** Scenario: the worker is a no-op when the feature is off. */
    @Test
    void runDueRuns_disabled_neverQueriesDueRuns() {
        ReflectionTestUtils.setField(service, "enabled", false);

        service.runDueRuns();

        verify(runRepository, never()).findDueModelIds();
    }

    /** Scenario: the lazy self proxy is used so the transactional methods go through Spring. */
    @Test
    void runDueRuns_processesEveryDueRunUsingSelfWhenSet() {
        final ConditionDetectionService selfProxy = Mockito.mock(ConditionDetectionService.class);
        ReflectionTestUtils.setField(service, "self", selfProxy);
        when(runRepository.findDueModelIds()).thenReturn(List.of(MODEL_A, MODEL_B));
        when(runRepository.findDueRuns(MODEL_A)).thenReturn(List.of(due(1L, MODEL_A)));
        when(runRepository.findDueRuns(MODEL_B)).thenReturn(List.of(due(2L, MODEL_B)));

        service.runDueRuns();

        verify(selfProxy).processRun(1L);
        verify(selfProxy).processRun(2L);
    }

    /** Scenario: with no proxy injected (plain unit construction) the service calls itself. */
    @Test
    void runDueRuns_withoutSelf_fallsBackToThis() {
        when(runRepository.findDueModelIds()).thenReturn(List.of(MODEL_A));
        when(runRepository.findDueRuns(MODEL_A)).thenReturn(List.of(due(3L, MODEL_A)));
        when(runRepository.claim(eq(3L), any(UUID.class), anyLong())).thenReturn(0);

        service.runDueRuns();

        verify(runRepository).claim(eq(3L), any(UUID.class), eq(ConditionDetectionService.LEASE_SECONDS));
    }

    /**
     * Scenario: the scheduler tick only hands runs to their model's lane and returns; the slow
     * analysis happens later on the lane, never on Spring's shared scheduler thread.
     */
    @Test
    void runDueRuns_routesEachRunToItsModelLaneWithoutRunningIt() {
        // Arrange: lanes that queue work per model instead of running it
        final Map<String, List<Runnable>> queued = new HashMap<>();
        final ConditionRunLanes deferredLanes = new ConditionRunLanes(
                modelId -> work -> queued.computeIfAbsent(modelId, k -> new ArrayList<>()).add(work));
        service = new ConditionDetectionService(
                adapterProvider, runRepository, flagRepository, callSessionService, recordingRepository,
                deferredLanes);
        ReflectionTestUtils.setField(service, "enabled", true);
        final ConditionDetectionService selfProxy = Mockito.mock(ConditionDetectionService.class);
        ReflectionTestUtils.setField(service, "self", selfProxy);
        when(runRepository.findDueModelIds()).thenReturn(List.of(MODEL_A, MODEL_B));
        when(runRepository.findDueRuns(MODEL_A)).thenReturn(List.of(due(1L, MODEL_A), due(3L, MODEL_A)));
        when(runRepository.findDueRuns(MODEL_B)).thenReturn(List.of(due(2L, MODEL_B)));

        // Act
        service.runDueRuns();

        // Assert: nothing ran on the tick; runs sit in per-model lanes in due order
        verifyNoInteractions(selfProxy);
        assertThat(queued.get(MODEL_A)).hasSize(2);
        assertThat(queued.get(MODEL_B)).hasSize(1);
        queued.get(MODEL_B).get(0).run();
        verify(selfProxy).processRun(2L);
    }

    /**
     * Scenario: ten voice-analysis runs wait in their lane and stay due on every tick. A
     * transcript run enqueued after them still reaches its own idle lane, instead of being
     * crowded out of a shared ten-row due list.
     */
    @Test
    void runDueRuns_voiceBacklog_stillQueuesTranscriptRun() {
        // Arrange: lanes that hold work, so the voice runs stay queued (and due) across ticks
        final String voice = "voice-model";
        final String transcript = "transcript-model";
        final Map<String, List<Runnable>> queued = new HashMap<>();
        final ConditionRunLanes deferredLanes = new ConditionRunLanes(
                modelId -> work -> queued.computeIfAbsent(modelId, k -> new ArrayList<>()).add(work));
        service = new ConditionDetectionService(
                adapterProvider, runRepository, flagRepository, callSessionService, recordingRepository,
                deferredLanes);
        ReflectionTestUtils.setField(service, "enabled", true);
        final ConditionDetectionService selfProxy = Mockito.mock(ConditionDetectionService.class);
        ReflectionTestUtils.setField(service, "self", selfProxy);
        final List<ConditionDueRunProjection> voiceBacklog = new ArrayList<>();
        for (long id = 1; id <= 10; id++) {
            voiceBacklog.add(due(id, voice));
        }
        when(runRepository.findDueModelIds())
                .thenReturn(List.of(voice), List.of(transcript, voice));
        when(runRepository.findDueRuns(voice)).thenReturn(voiceBacklog);
        when(runRepository.findDueRuns(transcript)).thenReturn(List.of(due(11L, transcript)));

        // Act: the backlog is queued, then a transcript run becomes due behind it
        service.runDueRuns();
        service.runDueRuns();

        // Assert: the voice runs were queued once; the transcript run reached its lane and runs
        assertThat(queued.get(voice)).hasSize(10);
        assertThat(queued.get(transcript)).hasSize(1);
        queued.get(transcript).get(0).run();
        verify(selfProxy).processRun(11L);
        verify(selfProxy, never()).processRun(1L);
    }

    // ---------------------------------------------------------------- describe

    /** Scenario: an exception with no message is described by class name only. */
    @Test
    void describe_nullMessage_usesClassNameOnly() {
        assertThat(ConditionDetectionService.describe(new IllegalStateException()))
                .isEqualTo("IllegalStateException");
    }

    /** Scenario: whitespace-only messages are treated like null. */
    @Test
    void describe_blankMessage_usesClassNameOnly() {
        assertThat(ConditionDetectionService.describe(new IllegalStateException("   ")))
                .isEqualTo("IllegalStateException");
    }

    /** Scenario: a 2000 character message is cut to 500 so lastError stays bounded. */
    @Test
    void describe_longMessage_isTruncatedTo500() {
        final String described = ConditionDetectionService.describe(
                new IllegalStateException("x".repeat(2000)));

        assertThat(described).hasSize(500).startsWith("IllegalStateException: xxx");
    }

    /** Scenario: ordinary messages are kept as ClassName: message. */
    @Test
    void describe_shortMessage_isKeptVerbatim() {
        assertThat(ConditionDetectionService.describe(new RuntimeException("oops")))
                .isEqualTo("RuntimeException: oops");
    }

    /** Scenario: the accessors expose the provider's adapters and the enabled flag. */
    @Test
    void adapters_andIsEnabled_reflectCollaborators() {
        final ConditionModelAdapter adapter = adapter(MODEL_A);
        registerAdapters(adapter);

        assertThat(service.adapters()).containsExactly(adapter);
        assertThat(service.isEnabled()).isTrue();
    }
}
