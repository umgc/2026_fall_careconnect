package com.careconnect.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import com.careconnect.dto.CaregiverPatientLinkResponse;
import com.careconnect.dto.FamilyMemberLinkResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.CallParticipant;
import com.careconnect.model.CallSession;
import com.careconnect.model.CallSummary;
import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.model.User;
import com.careconnect.notifications.SnsService;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.BedrockSentimentService;
import com.careconnect.service.BedrockSentimentService.SentimentResult;
import com.careconnect.service.CallAttendeeService;
import com.careconnect.service.CallRecordingService;
import com.careconnect.service.CallSessionService;
import com.careconnect.service.CallSummaryItemConfirmService;
import com.careconnect.service.CallSummaryService;
import com.careconnect.service.CallTelemetryService;
import com.careconnect.service.CallTerminationExecutor;
import com.careconnect.service.CallTranscriptService;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.ChimeService;
import com.careconnect.service.FamilyMemberService;
import com.careconnect.service.RecordingStartResult;
import com.careconnect.service.consent.CaregiverVisibilityCheck;
import com.careconnect.service.consent.CaregiverVisibilityService;
import com.careconnect.service.consent.CaregiverVisibilityStatus;
import com.careconnect.websocket.CallNotificationHandler;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.slf4j.LoggerFactory;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

/**
 * Pure Mockito unit tests for {@link CallController} branches not reached by the WebMvc tests:
 * join failure handling, conference invites, end/leave notifications, sentiment error paths,
 * durable-access fallbacks, dev-only deletions and recording ownership checks. The controller
 * methods are invoked directly with a mocked {@link SecurityContextHolder} principal.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("CallController branch coverage")
class CallControllerBranchTest {

    private static final String CALL_ID = "call-123";

    @Mock private ChimeService chimeService;
    @Mock private BedrockSentimentService sentimentService;
    @Mock private CallNotificationHandler callNotificationHandler;
    @Mock private CallTelemetryService callTelemetryService;
    @Mock private CallTranscriptService callTranscriptService;
    @Mock private CallSummaryService callSummaryService;
    @Mock private CallSummaryItemConfirmService callSummaryItemConfirmService;
    @Mock private CallRecordingService callRecordingService;
    @Mock private CallAttendeeService callAttendeeService;
    @Mock private CaregiverPatientLinkService caregiverPatientLinkService;
    @Mock private CaregiverVisibilityService caregiverVisibilityService;
    @Mock private FamilyMemberService familyMemberService;
    @Mock private UserRepository userRepository;
    @Mock private SnsService snsService;
    @Mock private Environment environment;
    @Mock private CallSessionService callSessionService;
    @Mock private CallTerminationExecutor callTerminationExecutor;

    @InjectMocks private CallController controller;

    private final Logger controllerLogger = (Logger) LoggerFactory.getLogger(CallController.class);
    private Level originalLevel;

    private final User patient = user(1L, "patient@test.com", Role.PATIENT, "Pat");
    private final User caregiver = user(2L, "caregiver@test.com", Role.CAREGIVER, " ");
    private final User admin = user(3L, "admin@test.com", Role.ADMIN, null);
    private final User family = user(4L, "family@test.com", Role.FAMILY_MEMBER, "Fam");
    private CallSession session;

    private static User user(final Long id, final String email, final Role role, final String name) {
        final User user = new User();
        user.setId(id);
        user.setEmail(email);
        user.setRole(role);
        user.setName(name);
        return user;
    }

    private void signIn(final User user) {
        SecurityContextHolder.getContext()
                .setAuthentication(new UsernamePasswordAuthenticationToken(user.getEmail(), null, List.of()));
    }

    private static CallParticipant joined(final Long userId) {
        final CallParticipant participant = new CallParticipant();
        participant.setUserId(userId);
        participant.setStatus(CallSessionService.PARTICIPANT_JOINED);
        return participant;
    }

    private static AppException app(final HttpStatus status) {
        return new AppException(status, status.name());
    }

    @BeforeEach
    void setUp() {
        originalLevel = controllerLogger.getLevel();
        controllerLogger.setLevel(Level.TRACE);
        for (final User u : List.of(patient, caregiver, admin, family)) {
            when(userRepository.findByEmail(u.getEmail())).thenReturn(Optional.of(u));
            when(userRepository.findById(u.getId())).thenReturn(Optional.of(u));
        }
        session = new CallSession();
        session.setId(10L);
        session.setCallId(CALL_ID);
        session.setPatientId(42L);
        session.setStatus(CallSessionService.SESSION_ACTIVE);
        when(callSessionService.requireSession(anyString())).thenReturn(session);
        when(callSessionService.requirePatientUserId(any())).thenReturn(1L);
        when(callSessionService.getJoinedParticipants(anyString()))
                .thenReturn(List.of(joined(1L), joined(2L)));
        when(chimeService.isMeetingActive(anyString())).thenReturn(true);
        when(environment.getActiveProfiles()).thenReturn(new String[] {"test"});
        when(callSummaryService.getLatestSummaryEntity(anyString())).thenReturn(Optional.empty());
        when(callSummaryService.getLatestSummary(anyString())).thenReturn(Optional.empty());
    }

    @AfterEach
    void tearDown() {
        controllerLogger.setLevel(originalLevel);
        SecurityContextHolder.clearContext();
    }

    @Nested
    @DisplayName("session creation and join")
    class Join {

        @Test
        @DisplayName("createSession echoes the scheduled visit id when present")
        void createSession_includesScheduledVisit() {
            signIn(caregiver);
            session.setScheduledVisitId(5L);
            when(callSessionService.createSession(eq(CALL_ID), eq(1L), eq(4L), eq(5L), eq(caregiver)))
                    .thenReturn(session);

            final ResponseEntity<Map<String, Object>> response =
                    controller.createSession(
                            Map.of("callId", CALL_ID, "patientUserId", 1, "inviteeUserId", "4", "scheduledVisitId", 5L));

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
            assertThat(response.getBody()).containsEntry("scheduledVisitId", 5L);
        }

        @Test
        @DisplayName("an elected joiner with system transcription survives an auto-recording failure")
        void join_autoRecordingFailure() {
            signIn(patient);
            when(callSessionService.ensureJoinAuthorized(eq(CALL_ID), eq(patient), any(), any(), any()))
                    .thenReturn(session);
            when(callSessionService.recordJoin(session, 1L, null)).thenReturn(true);
            when(chimeService.joinMeeting(eq(CALL_ID), eq("1"), eq("PATIENT"), eq("Pat")))
                    .thenReturn(Map.of("attendeeId", " "));
            when(environment.getProperty("careconnect.recording.system-transcription-enabled", Boolean.class, false))
                    .thenReturn(true);
            when(callRecordingService.startRecordingTyped(CALL_ID, null, true))
                    .thenThrow(new RuntimeException("aws down"));

            final Map<String, Object> body = new HashMap<>();
            body.put("callKind", "care");
            body.put("contextPatientUserIds", List.of(1, "1", "x", -2));
            assertThat(controller.joinCall(CALL_ID, body).getStatusCode()).isEqualTo(HttpStatus.OK);

            verify(callRecordingService).startKvsPipelineAsync(CALL_ID);
            verify(callAttendeeService, never()).recordJoin(anyString(), anyString(), anyLong(), anyString());
        }

        @Test
        @DisplayName("a Chime failure after the durable join is reverted and reported as 500")
        void join_chimeFailure_reverts() {
            signIn(caregiver);
            when(callSessionService.ensureJoinAuthorized(eq(CALL_ID), eq(caregiver), any(), any(), any()))
                    .thenReturn(session);
            when(chimeService.joinMeeting(anyString(), anyString(), anyString(), anyString()))
                    .thenThrow(new RuntimeException("chime down"));

            assertThatThrownBy(() -> controller.joinCall(CALL_ID, null))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("Failed to join call");
            verify(callSessionService).revertJoinAfterChimeFailure(CALL_ID, 2L);
        }

        @Test
        @DisplayName("a join that returns no attendee id skips the attendee record")
        void join_noAttendeeId() {
            signIn(family);
            when(callSessionService.ensureJoinAuthorized(eq(CALL_ID), eq(family), any(), any(), any()))
                    .thenReturn(session);
            when(chimeService.joinMeeting(anyString(), anyString(), anyString(), anyString())).thenReturn(Map.of());

            controller.joinCall(CALL_ID, Map.of("contextPatientUserId", 1));

            verify(callRecordingService).refreshKvsAttendeeStreamsAsync(CALL_ID);
        }
    }

    @Nested
    @DisplayName("conference invites")
    class Invites {

        @Test
        @DisplayName("eligible invitees require a caregiver, a live meeting and a patient")
        void eligibleInvitees_guards() {
            signIn(patient);
            assertThatThrownBy(() -> controller.getEligibleInvitees(CALL_ID)).isInstanceOf(AppException.class);

            signIn(caregiver);
            when(chimeService.isMeetingActive(CALL_ID)).thenReturn(false);
            assertThatThrownBy(() -> controller.getEligibleInvitees(CALL_ID))
                    .hasMessageContaining("no longer active");

            when(chimeService.isMeetingActive(CALL_ID)).thenReturn(true);
            when(callSessionService.requirePatientUserId(any())).thenReturn(null);
            assertThatThrownBy(() -> controller.getEligibleInvitees(CALL_ID))
                    .hasMessageContaining("No patient found");
        }

        @Test
        @DisplayName("eligible invitees include unlinked caregivers and family members not on the call")
        void eligibleInvitees_listsCareCircle() {
            signIn(caregiver);
            when(caregiverPatientLinkService.getCaregiversByPatient(1L))
                    .thenReturn(
                            List.of(
                                    new CaregiverPatientLinkResponse(1L, 7L, null, "c7@test.com", 1L, null, null,
                                            null, null, false, false, null, null, null, null, true, false)));
            when(familyMemberService.getFamilyMembersByPatient(1L))
                    .thenReturn(
                            List.of(
                                    new FamilyMemberLinkResponse(1L, 8L, null, "f8@test.com", 1L, null, "SON",
                                            null, null, null),
                                    new FamilyMemberLinkResponse(2L, 9L, "Nine", "f9@test.com", 1L, null, "DAUGHTER",
                                            null, null, null)));

            final List<Map<String, Object>> eligible = controller.getEligibleInvitees(CALL_ID).getBody();

            assertThat(eligible).extracting(m -> m.get("name")).containsExactly("c7@test.com", "f8@test.com", "Nine");
        }

        @Test
        @DisplayName("invites validate role, meeting, target and care-circle membership")
        void invite_guards() {
            signIn(family);
            assertThatThrownBy(() -> controller.inviteParticipant(CALL_ID, Map.of("targetUserId", "4")))
                    .isInstanceOf(AppException.class);

            signIn(caregiver);
            when(chimeService.isMeetingActive(CALL_ID)).thenReturn(false);
            assertThatThrownBy(() -> controller.inviteParticipant(CALL_ID, Map.of("targetUserId", "4")))
                    .hasMessageContaining("no longer active");
            when(chimeService.isMeetingActive(CALL_ID)).thenReturn(true);

            assertThatThrownBy(() -> controller.inviteParticipant(CALL_ID, new HashMap<>()))
                    .hasMessageContaining("targetUserId is required");
            assertThatThrownBy(() -> controller.inviteParticipant(CALL_ID, Map.of("targetUserId", "99")))
                    .hasMessageContaining("User not found");
            assertThatThrownBy(() -> controller.inviteParticipant(CALL_ID, Map.of("targetUserId", "1")))
                    .hasMessageContaining("Cannot add a patient");

            when(callSessionService.requirePatientUserId(any())).thenReturn(null);
            assertThatThrownBy(() -> controller.inviteParticipant(CALL_ID, Map.of("targetUserId", "4")))
                    .hasMessageContaining("No patient found");

            when(callSessionService.requirePatientUserId(any())).thenReturn(1L);
            assertThatThrownBy(() -> controller.inviteParticipant(CALL_ID, Map.of("targetUserId", "3")))
                    .hasMessageContaining("care circle");
        }

        @Test
        @DisplayName("an offline family invitee gets a truncated SMS; SMS failures are tolerated")
        void invite_offlineSms() {
            signIn(caregiver);
            family.setPhone(" +15555550100 ");
            caregiver.setName("C".repeat(120));
            when(familyMemberService.hasAccessToPatient(4L, 1L)).thenReturn(true);
            when(callNotificationHandler.isUserOnline("4")).thenReturn(false);
            when(snsService.publishSms(anyString(), anyString())).thenThrow(new RuntimeException("sns down")).thenReturn("msg-1");

            assertThat(controller.inviteParticipant(CALL_ID, Map.of("targetUserId", 4)).getBody())
                    .containsEntry("status", "offline");
            assertThat(controller.inviteParticipant(CALL_ID, Map.of("targetUserId", 4)).getBody())
                    .containsEntry("status", "offline");
            verify(snsService, org.mockito.Mockito.times(2))
                    .publishSms(eq("+15555550100"), org.mockito.ArgumentMatchers.argThat(m -> m.length() == 160));
        }

        @Test
        @DisplayName("an offline invitee without a phone gets no SMS")
        void invite_offlineNoPhone() {
            signIn(caregiver);
            family.setPhone(" ");
            when(familyMemberService.hasAccessToPatient(4L, 1L)).thenReturn(true);

            controller.inviteParticipant(CALL_ID, Map.of("targetUserId", "4"));

            verify(snsService, never()).publishSms(anyString(), anyString());
        }
    }

    @Nested
    @DisplayName("end and reconcile")
    class End {

        @Test
        @DisplayName("an owning end that finishes processing later returns 202 and notifies peers")
        void end_ownerProcessing() {
            signIn(caregiver);
            final UUID claim = UUID.randomUUID();
            when(callSessionService.leaveOrBeginTermination(CALL_ID, 2L))
                    .thenReturn(new CallSessionService.LeaveResult(true, false, 0, claim, List.of(1L)));
            when(callTerminationExecutor.execute(CALL_ID, 2L, claim)).thenReturn(false);

            final ResponseEntity<Map<String, String>> response = controller.endCall(CALL_ID, null, null);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.ACCEPTED);
            verify(callNotificationHandler).sendNotificationToUser(eq("1"), any());
            verify(callAttendeeService).recordCallEnded(CALL_ID);
        }

        @Test
        @DisplayName("an unexpected failure ending a call is reported as 500; AppExceptions pass through")
        void end_failures() {
            signIn(caregiver);
            when(callSessionService.leaveOrBeginTermination(CALL_ID, 2L))
                    .thenThrow(new RuntimeException("db down"))
                    .thenThrow(app(HttpStatus.FORBIDDEN));

            assertThatThrownBy(() -> controller.endCall(CALL_ID, null, null)).hasMessageContaining("Failed to end call");
            assertThatThrownBy(() -> controller.endCall(CALL_ID, null, null)).hasMessage("FORBIDDEN");
        }

        @Test
        @DisplayName("reconcile reports ended, still processing, and completed terminations")
        void reconcile_variants() {
            signIn(caregiver);
            final UUID claim = UUID.randomUUID();
            when(callSessionService.claimTerminationRetry(CALL_ID, 2L))
                    .thenReturn(new CallSessionService.LeaveResult(false, true, 0))
                    .thenReturn(new CallSessionService.LeaveResult(false, false, 0))
                    .thenReturn(new CallSessionService.LeaveResult(true, false, 0, claim, List.of(1L)))
                    .thenReturn(new CallSessionService.LeaveResult(true, false, 0, claim, List.of(1L)));
            when(callTerminationExecutor.execute(CALL_ID, 2L, claim)).thenReturn(false).thenReturn(true);

            assertThat(controller.reconcileTermination(CALL_ID).getBody()).containsEntry("status", "ended");
            assertThat(controller.reconcileTermination(CALL_ID).getStatusCode()).isEqualTo(HttpStatus.ACCEPTED);
            assertThat(controller.reconcileTermination(CALL_ID).getStatusCode()).isEqualTo(HttpStatus.ACCEPTED);
            assertThat(controller.reconcileTermination(CALL_ID).getBody()).containsEntry("status", "ended");
            verify(callNotificationHandler).sendNotificationToUser(eq("1"), any());
        }
    }

    @Nested
    @DisplayName("sentiment endpoints")
    class Sentiment {

        private final SentimentResult result = new SentimentResult(0.5, "CALM", "ok", "TEXT", CALL_ID, 1L, false);

        @Test
        @DisplayName("text sentiment rejects blank text and records failures")
        void text_blankAndFailure() {
            signIn(patient);
            assertThatThrownBy(() -> controller.analyzeTextSentiment(CALL_ID, Map.of("text", " ")))
                    .hasMessageContaining("text field is required");

            when(sentimentService.analyzeText("hi", CALL_ID)).thenThrow(new RuntimeException("bedrock down"));
            assertThatThrownBy(() -> controller.analyzeTextSentiment(CALL_ID, Map.of("text", "hi", "otherPartyId", "x")))
                    .hasMessageContaining("Sentiment analysis failed");
        }

        @Test
        @DisplayName("voice sentiment records failures; non-numeric metrics are rejected")
        void voice_failure() {
            signIn(patient);
            assertThatThrownBy(() -> controller.analyzeVoiceSentiment(CALL_ID,
                    Map.of("averageLevel", "abc", "speechRatio", "0.5", "variability", "0.5")))
                    .hasMessageContaining("Provide Chime metrics");

            when(sentimentService.analyzeVoiceFromChimeMetrics(eq(CALL_ID), any(), any(), any()))
                    .thenThrow(new RuntimeException("bedrock down"));
            assertThatThrownBy(() -> controller.analyzeVoiceSentiment(CALL_ID,
                    Map.of("averageLevel", "0.5", "speechRatio", "0.5", "variability", "0.5")))
                    .hasMessageContaining("Voice sentiment analysis failed");
        }

        @Test
        @DisplayName("video and combined sentiment record failures")
        void videoAndCombined_failures() {
            signIn(patient);
            when(sentimentService.analyzeVideoFrame(anyString(), anyString(), eq(CALL_ID)))
                    .thenThrow(new RuntimeException("rekognition down"));
            assertThatThrownBy(() -> controller.analyzeVideoSentiment(CALL_ID, Map.of("imageBase64", "AAA")))
                    .hasMessageContaining("Video sentiment analysis failed");
            assertThatThrownBy(() -> controller.analyzeVideoSentiment(CALL_ID, Map.of("imageBase64", " ")))
                    .hasMessageContaining("imageBase64 field is required");

            when(sentimentService.buildCombinedSentiment(any(), any(), any(), eq(CALL_ID)))
                    .thenThrow(new RuntimeException("combine failed"));
            assertThatThrownBy(() -> controller.getCombinedSentiment(CALL_ID, Map.of("text", "")))
                    .hasMessageContaining("Combined sentiment failed");
        }

        @Test
        @DisplayName("combined sentiment sanitizes overall score, label, timestamp and debug keys")
        void combined_sanitizesTelemetry() {
            signIn(patient);
            when(sentimentService.analyzeText("hi", CALL_ID)).thenReturn(result);
            final Map<String, Object> combined = new HashMap<>();
            combined.put("overall", Map.of("score", 0.4, "label", "CALM"));
            combined.put("timestamp", 5L);
            combined.put("dbgTs", 0.1);
            when(sentimentService.buildCombinedSentiment(any(), any(), any(), eq(CALL_ID)))
                    .thenReturn(combined)
                    .thenReturn(Map.of("overall", "not-a-map"))
                    .thenReturn(Map.of());

            controller.getCombinedSentiment(CALL_ID, Map.of("text", "hi"));
            controller.getCombinedSentiment(CALL_ID, Map.of("text", "hi"));
            controller.getCombinedSentiment(CALL_ID, Map.of("text", "hi"));

            verify(callTelemetryService)
                    .recordSentimentEvent(eq(CALL_ID), eq("SENTIMENT_COMBINED"), eq("COMBINED"), eq(1L), any(), any(),
                            any(), eq(Map.of("overallScore", 0.4, "overallLabel", "CALM", "timestamp", 5L, "dbgTs", 0.1)),
                            eq("SUCCESS"), any());
        }

        @Test
        @DisplayName("sentiment broadcasts skip non-caregiver recipients")
        void broadcast_onlyCaregivers() {
            signIn(patient);
            when(sentimentService.analyzeText("hi", CALL_ID)).thenReturn(result);
            final CallParticipant missing = joined(77L);
            when(callSessionService.getJoinedParticipants(CALL_ID))
                    .thenReturn(List.of(joined(1L), joined(2L), missing));

            controller.analyzeTextSentiment(CALL_ID, Map.of("text", "hi", "captureMode", " live "));

            verify(callNotificationHandler).sendNotificationToUser(eq("2"), any());
            verify(callNotificationHandler, never()).sendNotificationToUser(eq("1"), any());
        }
    }

    @Nested
    @DisplayName("durable access and summaries")
    class DurableAccess {

        @Test
        @DisplayName("admins may read legacy calls without a session; other admin errors propagate")
        void admin_missingSession() {
            signIn(admin);
            when(callSessionService.requireSession(CALL_ID))
                    .thenThrow(app(HttpStatus.NOT_FOUND))
                    .thenThrow(app(HttpStatus.GONE));

            assertThat(controller.getCallTelemetry(CALL_ID).getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThatThrownBy(() -> controller.getCallTelemetry(CALL_ID)).hasMessage("GONE");
        }

        @Test
        @DisplayName("non-participants fall back to summary patient, then legacy telemetry patient")
        void nonParticipant_fallbacks() {
            signIn(caregiver);
            when(callSessionService.requireHistoricalParticipant(CALL_ID, 2L))
                    .thenThrow(app(HttpStatus.GONE))
                    .thenThrow(app(HttpStatus.FORBIDDEN))
                    .thenThrow(app(HttpStatus.FORBIDDEN))
                    .thenThrow(app(HttpStatus.NOT_FOUND))
                    .thenThrow(app(HttpStatus.NOT_FOUND))
                    .thenThrow(app(HttpStatus.NOT_FOUND));
            assertThatThrownBy(() -> controller.getTranscriptSegments(CALL_ID)).hasMessage("GONE");

            final CallSummary summary = new CallSummary();
            summary.setPatientId(42L);
            when(callSummaryService.getLatestSummaryEntity(CALL_ID))
                    .thenReturn(Optional.of(summary))
                    .thenReturn(Optional.empty());
            controller.getTranscriptSegments(CALL_ID);
            verify(callSessionService).requirePatientEntityAccess(caregiver, 42L);

            assertThatThrownBy(() -> controller.getTranscriptSegments(CALL_ID)).hasMessage("FORBIDDEN");

            final CallTelemetryEvent actorEvent = new CallTelemetryEvent();
            actorEvent.setActorUserId(2L);
            actorEvent.setTargetUserId(1L);
            when(callTelemetryService.getTelemetryForCall(CALL_ID))
                    .thenReturn(List.of(actorEvent))
                    .thenReturn(List.of(contextEvent("{\"contextPatientUserIds\":[2,1]}"),
                            contextEvent(null), contextEvent("not json")))
                    .thenReturn(List.of(contextEvent("{\"contextPatientUserId\":2}")));
            controller.getTranscriptSegments(CALL_ID);
            controller.getTranscriptSegments(CALL_ID);
            verify(callSessionService, org.mockito.Mockito.times(2)).requirePatientUserAccess(caregiver, 1L);
            assertThatThrownBy(() -> controller.getTranscriptSegments(CALL_ID)).hasMessage("Call not found");
        }

        private CallTelemetryEvent contextEvent(final String json) {
            final CallTelemetryEvent event = new CallTelemetryEvent();
            event.setMetadataJson(json);
            return event;
        }

        @Test
        @DisplayName("on-consent summaries are blocked for caregivers without summary consent")
        void summary_onConsentBlocked() {
            signIn(caregiver);
            final CallSummary summary = new CallSummary();
            summary.setPatientId(42L);
            summary.setCaregiverVisibility("on_consent");
            summary.setStatus("NO_TRANSCRIPT");
            when(callSummaryService.getLatestSummaryEntity(CALL_ID)).thenReturn(Optional.of(summary));
            when(caregiverVisibilityService.getStatus(2L, 42L))
                    .thenReturn(new CaregiverVisibilityCheck(CaregiverVisibilityStatus.PENDING_REVIEW, false))
                    .thenReturn(new CaregiverVisibilityCheck(CaregiverVisibilityStatus.GRANTED, true));
            when(callTranscriptService.countSegments(CALL_ID)).thenReturn(2L);

            assertThatThrownBy(() -> controller.getCallSummary(CALL_ID)).hasMessage("Access denied");
            assertThat(controller.getCallSummary(CALL_ID).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
            verify(callSummaryService).generateAndStoreSummary(eq(CALL_ID), eq(2L), any());
        }

        @Test
        @DisplayName("summary item confirmation maps illegal arguments and states to 400")
        void confirmSummaryItem_mapsErrors() {
            signIn(admin);
            when(callSummaryItemConfirmService.confirm(eq(CALL_ID), anyString(), eq(admin), any()))
                    .thenThrow(new IllegalArgumentException("bad item"))
                    .thenThrow(new IllegalStateException("no patient"));

            assertThatThrownBy(() -> controller.confirmSummaryItem(CALL_ID, "i1", null)).hasMessage("bad item");
            assertThatThrownBy(() -> controller.confirmSummaryItem(CALL_ID, "i1", null)).hasMessage("no patient");
        }

        @Test
        @DisplayName("transcript upload validates call id and segment count")
        void saveTranscriptSegments_validation() {
            signIn(patient);
            assertThatThrownBy(() -> controller.saveTranscriptSegments(" ", Map.of())).hasMessage("Invalid callId");

            final List<Map<String, Object>> segments = new ArrayList<>();
            for (int i = 0; i < 201; i++) {
                segments.add(Map.of("clientSegmentId", UUID.randomUUID().toString(), "text", "t"));
            }
            final Map<String, Object> body = new HashMap<>();
            body.put("segments", segments);
            assertThatThrownBy(() -> controller.saveTranscriptSegments(CALL_ID, body))
                    .hasMessageContaining("Too many transcript segments");

            final Map<String, Object> single = Map.of("clientSegmentId", "not-a-uuid");
            assertThatThrownBy(() -> controller.saveTranscriptSegments(CALL_ID, single))
                    .hasMessageContaining("canonical UUID");
            final List<Object> mixed = new ArrayList<>();
            mixed.add("skip me");
            mixed.add(Map.of("text", "no id"));
            assertThatThrownBy(() -> controller.saveTranscriptSegments(CALL_ID, Map.of("segments", mixed)))
                    .hasMessageContaining("clientSegmentId is required");
            final Map<String, Object> upper = Map.of("clientSegmentId",
                    "123E4567-E89B-12D3-A456-426614174000", "startMs", "x");
            when(callTranscriptService.recordSegments(eq(CALL_ID), eq(1L), any())).thenReturn(1);
            assertThat(controller.saveTranscriptSegments(CALL_ID, upper).getBody()).containsEntry("savedSegments", 1);
        }
    }

    @Nested
    @DisplayName("dev-only deletion and recordings")
    class DevAndRecordings {

        @Test
        @DisplayName("telemetry deletion is refused outside dev profiles, falling back to default profiles")
        void deleteTelemetry_profileGuard() {
            signIn(admin);
            when(environment.getActiveProfiles()).thenReturn(new String[0]);
            when(environment.getDefaultProfiles()).thenReturn(new String[] {"prod", null});

            assertThatThrownBy(() -> controller.deleteCallTelemetry(CALL_ID))
                    .hasMessageContaining("only available in local/dev mode");
        }

        @Test
        @DisplayName("call telemetry deletion tolerates missing purge counters")
        void deleteTelemetry_missingCounters() {
            signIn(admin);
            when(callTranscriptService.purgeForCall(CALL_ID)).thenReturn(Map.of());
            when(callRecordingService.purgeRecordingsForCall(CALL_ID)).thenReturn(Map.of("deletedDbRows", "n/a"));

            assertThat(controller.deleteCallTelemetry(CALL_ID).getBody())
                    .containsEntry("deletedTranscriptSegments", 0L)
                    .containsEntry("deletedRecordingRows", 0L);
        }

        @Test
        @DisplayName("patient history deletion is forbidden for unrelated users and sums per-call purges")
        void deletePatientHistory() {
            signIn(family);
            assertThatThrownBy(() -> controller.deletePatientCallHistory(1L)).hasMessage("Access denied");

            signIn(caregiver);
            when(caregiverPatientLinkService.hasAccessToPatient(2L, 1L)).thenReturn(true);
            when(callTelemetryService.findCallHistoryForPatient(1L))
                    .thenReturn(new CallTelemetryService.PatientCallHistoryMatch(List.of(), Set.of("c1")));
            when(callTranscriptService.purgeForCall("c1")).thenReturn(Map.of("deletedTranscriptSegments", 2L));
            when(callRecordingService.purgeRecordingsForCall("c1"))
                    .thenReturn(Map.of("deletedDbRows", 1L, "deletedS3Objects", 3));

            assertThat(controller.deletePatientCallHistory(1L).getBody())
                    .containsEntry("deletedRecordingS3Objects", 3L)
                    .containsEntry("deletedTranscriptSegments", 2L);
            assertThatThrownBy(() -> controller.getSentimentHistory(null)).hasMessage("Access denied");
        }

        @Test
        @DisplayName("recording start falls back to the legacy map API and only KVS-starts on success")
        void startRecording_fallbackAndKvs() {
            signIn(caregiver);
            when(callRecordingService.startRecordingTyped(CALL_ID, 2L, true)).thenReturn(null);
            when(callRecordingService.startRecording(CALL_ID, 2L))
                    .thenReturn(Map.of("status", "DISABLED", "message", "off"))
                    .thenReturn(Map.of("status", "ALREADY_RECORDING"));

            controller.startRecording(CALL_ID, true);
            controller.startRecording(CALL_ID);

            verify(callRecordingService, org.mockito.Mockito.times(1)).startKvsPipelineAsync(CALL_ID);
        }

        @Test
        @DisplayName("typed recording start results are returned as maps")
        void startRecording_typed() {
            signIn(caregiver);
            when(callRecordingService.startRecordingTyped(CALL_ID, 2L, false))
                    .thenReturn(new RecordingStartResult(RecordingStartResult.Status.POLICY_BLOCKED, CALL_ID, null, 0L,
                            null, null, null, null, "consent"));

            assertThat(controller.startRecording(CALL_ID, false).getBody()).containsEntry("status", "POLICY_BLOCKED");
            verify(callRecordingService, never()).startKvsPipelineAsync(CALL_ID);
        }

        @Test
        @DisplayName("only the recording owner or an admin may stop a recording")
        void stopRecording_ownership() {
            signIn(caregiver);
            when(callRecordingService.getRecordingStatus(CALL_ID))
                    .thenReturn(Map.of("status", "RECORDING"))
                    .thenReturn(null);
            when(callRecordingService.stopRecording(CALL_ID)).thenReturn(Map.of("status", "STOPPED"));

            assertThatThrownBy(() -> controller.stopRecording(CALL_ID)).hasMessageContaining("recording owner");
            assertThat(controller.stopRecording(CALL_ID).getBody()).containsEntry("status", "STOPPED");
        }

        @Test
        @DisplayName("listing recordings covers role restrictions and the caregiver default")
        void listRecordings_roles() {
            signIn(patient);
            assertThatThrownBy(() -> controller.listRecordings(null)).hasMessageContaining("Only admins and caregivers");

            signIn(caregiver);
            assertThatThrownBy(() -> controller.listRecordings(9L)).hasMessageContaining("only list recordings");
            when(callRecordingService.getRecordingsByUser(2L)).thenReturn(List.of(Map.of("callId", "c")));
            assertThat(controller.listRecordings(null).getBody()).hasSize(1);
        }

        @Test
        @DisplayName("global purge requires an admin with explicit enablement")
        void purgeAll_guards() {
            when(environment.getProperty("careconnect.recording.global-purge-enabled", Boolean.class, false))
                    .thenReturn(true);
            signIn(caregiver);
            assertThatThrownBy(() -> controller.purgeAllRecordings()).hasMessageContaining("Only administrators");

            when(environment.getActiveProfiles()).thenReturn(new String[] {null, "prod"});
            assertThatThrownBy(() -> controller.purgeAllRecordings()).hasMessageContaining("explicit enablement");
        }

        @Test
        @DisplayName("raw cleanup checks recording access")
        void cleanupRaw() {
            signIn(admin);
            when(callRecordingService.cleanupRawArtifactsForCall(CALL_ID)).thenReturn(Map.of("status", "CLEANED"));

            assertThat(controller.cleanupRawRecordingArtifacts(CALL_ID).getBody()).containsEntry("status", "CLEANED");
            verify(callSessionService).requireRecordingAccess(CALL_ID, admin);
        }
    }
}
