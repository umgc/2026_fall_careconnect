package com.careconnect.service.conditiondetection;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.careconnect.dto.conditiondetection.ConditionFlagsResponse;
import com.careconnect.model.CallSession;
import com.careconnect.model.User;
import com.careconnect.model.conditiondetection.ConditionDetectionRun;
import com.careconnect.model.conditiondetection.ConditionFlag;
import com.careconnect.model.conditiondetection.ConditionInputKind;
import com.careconnect.model.conditiondetection.ConditionName;
import com.careconnect.model.conditiondetection.ConditionRunState;
import com.careconnect.model.conditiondetection.ConditionSkipReason;
import com.careconnect.repository.conditiondetection.ConditionDetectionRunRepository;
import com.careconnect.repository.conditiondetection.ConditionFlagRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.CallSessionService;
import com.careconnect.testsupport.fixtures.ConditionDetectionFixtures;
import java.lang.reflect.RecordComponent;
import java.time.LocalDateTime;
import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.EnumSource;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * Unit tests for {@link ConditionFlagQueryService}: access rules, status mapping and what is
 * (and is not) exposed to clients. Repositories and authorization are mocked.
 */
@ExtendWith(MockitoExtension.class)
class ConditionFlagQueryServiceTest {

    private static final String CALL_ID = "call-1";
    private static final Long PATIENT_USER_ID = 70L;
    private static final String MODEL = "kintsugi-dam-3.1";

    @Mock
    private ConditionDetectionRunRepository runRepository;
    @Mock
    private ConditionFlagRepository flagRepository;
    @Mock
    private ConditionDetectionService detectionService;
    @Mock
    private CallSessionService callSessionService;
    @Mock
    private AuthorizationService authorizationService;

    private ConditionFlagQueryService service;
    private User caregiver;

    @BeforeEach
    void setUp() {
        service = new ConditionFlagQueryService(
                runRepository, flagRepository, detectionService, callSessionService, authorizationService);
        caregiver = user(500L, Role.CAREGIVER);
    }

    private static User user(final Long id, final Role role) {
        return ConditionDetectionFixtures.user(id, role);
    }

    private ConditionModelAdapter adapter(final String modelId, final String displayName) {
        final ConditionModelAdapter adapter = Mockito.mock(ConditionModelAdapter.class);
        Mockito.lenient().when(adapter.modelId()).thenReturn(modelId);
        Mockito.lenient().when(adapter.displayName()).thenReturn(displayName);
        Mockito.lenient().when(adapter.inputKind()).thenReturn(ConditionInputKind.PATIENT_AUDIO);
        return adapter;
    }

    private void stubAccess() throws Exception {
        final CallSession session = ConditionDetectionFixtures.session();
        when(callSessionService.requireSession(CALL_ID)).thenReturn(session);
        when(callSessionService.requirePatientUserId(session)).thenReturn(PATIENT_USER_ID);
    }

    private void stubDetection(final boolean enabled, final ConditionModelAdapter... adapters) {
        when(detectionService.isEnabled()).thenReturn(enabled);
        if (enabled) {
            when(detectionService.adapters()).thenReturn(List.of(adapters));
        }
    }

    private static ConditionDetectionRun run(
            final long id, final String modelId, final ConditionRunState state) {
        return ConditionDetectionFixtures.run(id, modelId, state);
    }

    private static ConditionFlag flag(
            final long runId, final ConditionName name, final int level, final String label,
            final Double raw) {
        return ConditionDetectionFixtures.flag(runId, name, level, label, raw);
    }

    // ----------------------------------------------------------------- access

    /** Scenario: no authenticated user. */
    @Test
    void getFlags_nullUser_isUnauthorized() {
        assertThatThrownBy(() -> service.getFlags(null, CALL_ID))
                .isInstanceOf(UnauthorizedException.class);
        verifyNoInteractions(callSessionService, authorizationService, runRepository);
    }

    /** Scenario: the patient's id equals the call's patient; the role alone must refuse, before any lookup. */
    @Test
    void getFlags_patientIsRefusedEvenForOwnCall_withoutLookingUpTheSession() {
        // The patient's user id equals the call's patient; the role alone must refuse.
        final User patient = user(PATIENT_USER_ID, Role.PATIENT);

        assertThatThrownBy(() -> service.getFlags(patient, CALL_ID))
                .isInstanceOf(UnauthorizedException.class);

        verify(callSessionService, never()).requireSession(CALL_ID);
        verifyNoInteractions(authorizationService, runRepository, flagRepository);
    }

    /** Scenario: a caregiver without an active link; the authorization failure propagates and no data is read. */
    @Test
    void getFlags_patientAccessCheckFails_propagates() throws Exception {
        stubAccess();
        Mockito.doThrow(new UnauthorizedException("no link"))
                .when(authorizationService).requirePatientAccess(caregiver, PATIENT_USER_ID);

        assertThatThrownBy(() -> service.getFlags(caregiver, CALL_ID))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("no link");
        verifyNoInteractions(runRepository, flagRepository);
    }

    // ------------------------------------------------------------------- data

    /** Scenario: a COMPLETE run with two flags; completedAt is rendered as ISO-8601 UTC and the raw score is not exposed. */
    @Test
    void getFlags_caregiverHappyPath_mapsRunAndFlagsWithoutRawScore() throws Exception {
        stubAccess();
        stubDetection(true, adapter(MODEL, "Voice screening"));
        final ConditionDetectionRun complete = run(1L, MODEL, ConditionRunState.COMPLETE);
        complete.setCompletedAt(LocalDateTime.of(2026, 10, 7, 12, 30, 15));
        when(runRepository.findByCallIdOrderByIdAsc(CALL_ID)).thenReturn(List.of(complete));
        when(flagRepository.findByCallIdOrderByIdAsc(CALL_ID)).thenReturn(List.of(
                flag(1L, ConditionName.DEPRESSION, 1, "MILD_TO_MODERATE", 0.31),
                flag(1L, ConditionName.ANXIETY, 3, "SEVERE", 0.77)));

        final ConditionFlagsResponse response = service.getFlags(caregiver, CALL_ID);

        verify(authorizationService).requirePatientAccess(caregiver, PATIENT_USER_ID);
        assertThat(response.disclaimer()).isEqualTo(ConditionScreeningCopy.DISCLAIMER_EN);
        assertThat(response.runs()).hasSize(1);
        final ConditionFlagsResponse.ModelRun modelRun = response.runs().get(0);
        assertThat(modelRun.modelId()).isEqualTo(MODEL);
        assertThat(modelRun.displayName()).isEqualTo("Voice screening");
        assertThat(modelRun.inputKind()).isEqualTo("PATIENT_AUDIO");
        assertThat(modelRun.status()).isEqualTo("COMPLETE");
        assertThat(modelRun.skipReason()).isNull();
        assertThat(modelRun.completedAt()).isEqualTo("2026-10-07T12:30:15Z");
        assertThat(modelRun.flags()).containsExactly(
                new ConditionFlagsResponse.Flag("DEPRESSION", 1, "MILD_TO_MODERATE", null),
                new ConditionFlagsResponse.Flag("ANXIETY", 3, "SEVERE", null));
    }

    /** Scenario: structural guard that the response record has no raw score component. */
    @Test
    void flagResponseType_doesNotExposeRawScore() {
        final List<String> components = Arrays.stream(ConditionFlagsResponse.Flag.class.getRecordComponents())
                .map(RecordComponent::getName).toList();

        assertThat(components).doesNotContain("rawScore", "raw", "score");
        assertThat(components)
                .containsExactly("condition", "severityLevel", "severityLabel", "evidenceSummary");
    }

    /** Scenario: internal states collapse to the five public statuses. */
    @ParameterizedTest
    @CsvSource({
        "READY,PENDING",
        "CLAIMED,PROCESSING",
        "RUNNING,PROCESSING",
        "RETRYABLE,PROCESSING",
        "COMPLETE,COMPLETE",
        "SKIPPED,SKIPPED",
        "FAILED,FAILED"
    })
    void publicStatus_mapsEveryRunState(final ConditionRunState state, final String expected) {
        assertThat(ConditionFlagQueryService.publicStatus(state)).isEqualTo(expected);
    }

    /** Scenario: a flag exists for the run in every state, but only COMPLETE runs may expose it. */
    @ParameterizedTest
    @EnumSource(ConditionRunState.class)
    void getFlags_everyRunState_isMappedAndOnlyCompleteCarriesFlags(final ConditionRunState state)
            throws Exception {
        stubAccess();
        stubDetection(true, adapter(MODEL, "Voice screening"));
        when(runRepository.findByCallIdOrderByIdAsc(CALL_ID)).thenReturn(List.of(run(1L, MODEL, state)));
        when(flagRepository.findByCallIdOrderByIdAsc(CALL_ID))
                .thenReturn(List.of(flag(1L, ConditionName.DEPRESSION, 2, "SEVERE", 0.9)));

        final ConditionFlagsResponse.ModelRun modelRun =
                service.getFlags(caregiver, CALL_ID).runs().get(0);

        assertThat(modelRun.status()).isEqualTo(ConditionFlagQueryService.publicStatus(state));
        if (state == ConditionRunState.COMPLETE) {
            assertThat(modelRun.flags()).hasSize(1);
        } else {
            assertThat(modelRun.flags()).isEmpty();
        }
    }

    /** Scenario: a SKIPPED run shows its skip reason name and no completion time when unset. */
    @Test
    void getFlags_skippedRun_exposesSkipReasonName() throws Exception {
        stubAccess();
        stubDetection(true, adapter(MODEL, "Voice screening"));
        final ConditionDetectionRun skipped = run(1L, MODEL, ConditionRunState.SKIPPED);
        skipped.setSkipReason(ConditionSkipReason.CALL_TOO_SHORT);
        when(runRepository.findByCallIdOrderByIdAsc(CALL_ID)).thenReturn(List.of(skipped));
        when(flagRepository.findByCallIdOrderByIdAsc(CALL_ID)).thenReturn(List.of());

        final ConditionFlagsResponse.ModelRun modelRun =
                service.getFlags(caregiver, CALL_ID).runs().get(0);

        assertThat(modelRun.status()).isEqualTo("SKIPPED");
        assertThat(modelRun.skipReason()).isEqualTo("CALL_TOO_SHORT");
        assertThat(modelRun.completedAt()).isNull();
    }

    /** Scenario: a run for a retired model still displays using its model id. */
    @Test
    void getFlags_runWithoutMatchingAdapter_fallsBackToModelIdAsDisplayName() throws Exception {
        stubAccess();
        stubDetection(true);
        when(runRepository.findByCallIdOrderByIdAsc(CALL_ID))
                .thenReturn(List.of(run(1L, "retired-model", ConditionRunState.COMPLETE)));
        when(flagRepository.findByCallIdOrderByIdAsc(CALL_ID)).thenReturn(List.of());

        assertThat(service.getFlags(caregiver, CALL_ID).runs().get(0).displayName())
                .isEqualTo("retired-model");
    }

    /** Scenario: the call just ended and the second model has no run yet, so a PENDING entry is added after existing runs. */
    @Test
    void getFlags_enabledAdapterWithoutRun_getsSynthesizedPendingEntry() throws Exception {
        stubAccess();
        stubDetection(true, adapter(MODEL, "Voice screening"), adapter("second-model", "Second"));
        when(runRepository.findByCallIdOrderByIdAsc(CALL_ID))
                .thenReturn(List.of(run(1L, MODEL, ConditionRunState.RUNNING)));
        when(flagRepository.findByCallIdOrderByIdAsc(CALL_ID)).thenReturn(List.of());

        final List<ConditionFlagsResponse.ModelRun> runs = service.getFlags(caregiver, CALL_ID).runs();

        assertThat(runs).hasSize(2);
        assertThat(runs.get(0).modelId()).isEqualTo(MODEL);
        assertThat(runs.get(0).status()).isEqualTo("PROCESSING");
        assertThat(runs.get(1)).isEqualTo(new ConditionFlagsResponse.ModelRun(
                "second-model", "Second", "PATIENT_AUDIO", "PENDING", null, null, List.of()));
    }

    /** Scenario: detection was switched off; history stays visible but nothing new is promised. */
    @Test
    void getFlags_detectionDisabled_noSynthesizedEntriesButExistingRunsStillReturned() throws Exception {
        stubAccess();
        stubDetection(false);
        when(runRepository.findByCallIdOrderByIdAsc(CALL_ID))
                .thenReturn(List.of(run(1L, MODEL, ConditionRunState.FAILED)));
        when(flagRepository.findByCallIdOrderByIdAsc(CALL_ID)).thenReturn(List.of());

        final List<ConditionFlagsResponse.ModelRun> runs = service.getFlags(caregiver, CALL_ID).runs();

        verify(detectionService, never()).adapters();
        assertThat(runs).hasSize(1);
        assertThat(runs.get(0).status()).isEqualTo("FAILED");
        assertThat(runs.get(0).displayName()).isEqualTo(MODEL);
    }

    /** Scenario: disabled with no history still carries the mandatory disclaimer. */
    @Test
    void getFlags_detectionDisabledAndNoRuns_returnsEmptyRunsWithDisclaimer() throws Exception {
        stubAccess();
        stubDetection(false);
        when(runRepository.findByCallIdOrderByIdAsc(CALL_ID)).thenReturn(List.of());
        when(flagRepository.findByCallIdOrderByIdAsc(CALL_ID)).thenReturn(List.of());

        final ConditionFlagsResponse response = service.getFlags(caregiver, CALL_ID);

        assertThat(response.runs()).isEmpty();
        assertThat(response.disclaimer()).isEqualTo(ConditionScreeningCopy.DISCLAIMER_EN);
    }

    /** Scenario: admins pass through the same authorization call, which grants them access. */
    @Test
    void getFlags_adminIsAllowedThroughAuthorizationService() throws Exception {
        final User admin = user(1L, Role.ADMIN);
        stubAccess();
        stubDetection(false);
        when(runRepository.findByCallIdOrderByIdAsc(CALL_ID)).thenReturn(List.of());
        when(flagRepository.findByCallIdOrderByIdAsc(CALL_ID)).thenReturn(List.of());

        service.getFlags(admin, CALL_ID);

        verify(authorizationService).requirePatientAccess(admin, PATIENT_USER_ID);
    }
}
