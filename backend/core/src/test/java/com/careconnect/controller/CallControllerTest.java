package com.careconnect.controller;

import com.careconnect.config.CareconnectTestConfig;
import com.careconnect.exception.AppException;
import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.BedrockSentimentService;
import com.careconnect.service.BedrockSentimentService.SentimentResult;
import com.careconnect.service.CallRecordingService;
import com.careconnect.service.CallSummaryService;
import com.careconnect.service.CallTelemetryService;
import com.careconnect.service.CallTranscriptService;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.ChimeService;
import com.careconnect.service.FamilyMemberService;
import com.careconnect.dto.FamilyMemberLinkResponse;
import com.careconnect.notifications.SnsService;
import com.careconnect.websocket.CallNotificationHandler;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.security.oauth2.client.servlet.OAuth2ClientAutoConfiguration;
import org.springframework.boot.autoconfigure.security.oauth2.resource.servlet.OAuth2ResourceServerAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(
        controllers = CallController.class,
        excludeAutoConfiguration = {
                OAuth2ClientAutoConfiguration.class,
                OAuth2ResourceServerAutoConfiguration.class
        }
)
@Import(CareconnectTestConfig.class)
@org.springframework.test.context.ActiveProfiles("test")
@DisplayName("CallController Tests")
class CallControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean private ChimeService chimeService;
    @MockitoBean private BedrockSentimentService sentimentService;
    @MockitoBean private CallTelemetryService callTelemetryService;
    @MockitoBean private CallTranscriptService callTranscriptService;
    @MockitoBean private CallSummaryService callSummaryService;
    @MockitoBean private CallRecordingService callRecordingService;
    @MockitoBean private CaregiverPatientLinkService caregiverPatientLinkService;
    @MockitoBean private FamilyMemberService familyMemberService;
    @MockitoBean private UserRepository userRepository;
    @MockitoBean private CallNotificationHandler callNotificationHandler;
    @MockitoBean private SnsService snsService;

    private ObjectMapper objectMapper;
    private User patientUser;
    private User caregiverUser;
    private User adminUser;

    private static final String CALL_ID = "call-123";
    private static final String BASE_URL = "/api/v3/calls";

    @BeforeEach
    void setUp() {
        objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());

        patientUser = buildUser(1L, "patient@test.com", Role.PATIENT);
        caregiverUser = buildUser(2L, "caregiver@test.com", Role.CAREGIVER);
        adminUser = buildUser(3L, "admin@test.com", Role.ADMIN);

        // Default Chime stubs
        Map<String, Object> chimeCreds = Map.of(
                "meetingId", "mtg-123",
                "attendeeId", "att-456",
                "joinToken", "token-abc",
                "mediaRegion", "us-east-1"
        );
        when(chimeService.joinMeeting(anyString(), anyString(), anyString(), anyString())).thenReturn(chimeCreds);
        when(chimeService.isMeetingActive(anyString())).thenReturn(true);

        // Default sentiment stub
        SentimentResult positiveResult = new SentimentResult(
                0.75, "POSITIVE", "Good", "TEXT", CALL_ID, 123456L, false);
        when(sentimentService.analyzeText(anyString(), anyString())).thenReturn(positiveResult);
        when(sentimentService.analyzeVoiceFromChimeMetrics(anyString(), any(), any(), any()))
                .thenReturn(SentimentResult.neutral("VOICE", CALL_ID, "No voice sample"));
        when(sentimentService.analyzeVideoFrame(anyString(), anyString(), anyString()))
                .thenReturn(SentimentResult.neutral("VIDEO", CALL_ID, "Bedrock disabled"));
        when(sentimentService.buildCombinedSentiment(any(), any(), any(), anyString()))
                .thenReturn(Map.of("overall", Map.of("score", 0.5, "label", "ANXIOUS"),
                        "callId", CALL_ID, "timestamp", 123456L));
        when(sentimentService.analyzeFinalOverallSentiment(anyString(), any()))
                .thenReturn(SentimentResult.neutral("COMBINED", CALL_ID, "Final"));

        // Default telemetry stubs
        doNothing().when(callTelemetryService).recordCallEvent(
                anyString(), anyString(), any(), any(), anyString(), any(), any());
        doNothing().when(callTelemetryService).recordSentimentEvent(
                anyString(), anyString(), anyString(), any(), any(), any(), any(), any(), anyString(), any());
        when(callTelemetryService.getTelemetryForCall(anyString())).thenReturn(Collections.emptyList());
        when(callTelemetryService.getTelemetryForUser(anyLong())).thenReturn(Collections.emptyList());
        when(callTelemetryService.getLatestSentimentByChannel(anyString())).thenReturn(Collections.emptyMap());
        when(callTelemetryService.getSentimentHistoryForUser(anyLong())).thenReturn(Collections.emptyList());

        // Default summary / recording / transcript stubs
        when(callSummaryService.getLatestSummaryEntity(anyString())).thenReturn(Optional.empty());
        when(callSummaryService.getLatestSummary(anyString())).thenReturn(Optional.empty());
        when(callRecordingService.startRecording(anyString(), anyLong()))
                .thenReturn(Map.of("status", "STARTED"));
        when(callRecordingService.stopRecording(anyString()))
                .thenReturn(Map.of("status", "STOPPED"));
        when(callTranscriptService.hasTranscriptAccess(anyString(), anyLong())).thenReturn(false);
        when(callTranscriptService.countSegments(anyString())).thenReturn(0L);
        when(callTranscriptService.getSegmentsForCall(anyString())).thenReturn(Collections.emptyList());
    }

    // Helpers

    private User buildUser(Long id, String email, Role role) {
        User u = new User();
        u.setId(id);
        u.setEmail(email);
        u.setRole(role);
        return u;
    }

    private void mockCurrentPatient() {
        when(userRepository.findByEmail("patient@test.com")).thenReturn(Optional.of(patientUser));
    }

    private void mockCurrentCaregiver() {
        when(userRepository.findByEmail("caregiver@test.com")).thenReturn(Optional.of(caregiverUser));
    }

    private void mockCurrentAdmin() {
        when(userRepository.findByEmail("admin@test.com")).thenReturn(Optional.of(adminUser));
    }

    private CallTelemetryEvent callEvent(String eventType, Long actorUserId, LocalDateTime occurredAt) {
        CallTelemetryEvent event = new CallTelemetryEvent();
        event.setCallId(CALL_ID);
        event.setEventType(eventType);
        event.setActorUserId(actorUserId);
        event.setOccurredAt(occurredAt);
        return event;
    }

    private CallTelemetryEvent conferenceInviteEvent(
            Long actorUserId, Long targetUserId, LocalDateTime occurredAt) {
        CallTelemetryEvent event = new CallTelemetryEvent();
        event.setCallId(CALL_ID);
        event.setEventType("CONFERENCE_INVITE");
        event.setActorUserId(actorUserId);
        event.setTargetUserId(targetUserId);
        event.setOccurredAt(occurredAt);
        return event;
    }

    // 
    //  CHIME TESTS
    // 

    @Nested
    @DisplayName("Chime Meeting Join/End")
    class ChimeMeetingTests {

        @Test
        @DisplayName("CHIME-001: POST /join invokes chimeService.joinMeeting with callId and userId")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void chime001_joinInvokesChimeService() throws Exception {
            mockCurrentCaregiver();

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/join")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            verify(chimeService).joinMeeting(eq(CALL_ID), eq("2"), anyString(), anyString());
        }

        @Test
        @DisplayName("CHIME-002: POST /join response contains meetingId, attendeeId, joinToken")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void chime002_joinResponseContainsCredentials() throws Exception {
            mockCurrentCaregiver();

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/join")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.meetingId").value("mtg-123"))
                    .andExpect(jsonPath("$.attendeeId").value("att-456"))
                    .andExpect(jsonPath("$.joinToken").value("token-abc"));
        }

        @Test
        @DisplayName("CHIME-003: POST /join without authentication redirects to login (form-login security config)")
        void chime003_joinWithoutAuthRedirectsToLogin() throws Exception {
            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/join")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isUnauthorized());
        }

        @Test
        @DisplayName("CHIME-004: POST /join with valid CAREGIVER auth returns 200 and credentials")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void chime004_joinAsCaregiverReturns200WithCredentials() throws Exception {
            mockCurrentCaregiver();

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/join")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.meetingId").exists())
                    .andExpect(jsonPath("$.attendeeId").exists());
        }

        @Test
        @DisplayName("CHIME-005: chimeService.joinMeeting throws RuntimeException  500")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void chime005_joinMeetingRuntimeExceptionReturns500() throws Exception {
            mockCurrentCaregiver();
            when(chimeService.joinMeeting(anyString(), anyString(), anyString(), anyString()))
                    .thenThrow(new RuntimeException("AWS connection failure"));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/join")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isInternalServerError());
        }

        @Test
        @DisplayName("CHIME-006: POST /end returns 200 with status=ended and callId")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void chime006_endCallReturns200WithStatus() throws Exception {
            mockCurrentCaregiver();

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/end")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("ended"))
                    .andExpect(jsonPath("$.callId").value(CALL_ID));
        }

        @Test
        @DisplayName("CHIME-008: chimeService.endMeeting throws AppException  re-throws 4xx")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void chime008_endMeetingAppExceptionRethrown() throws Exception {
            mockCurrentCaregiver();
            doThrow(new AppException(HttpStatus.NOT_FOUND, "Meeting not found"))
                    .when(chimeService).endMeeting(anyString());

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/end")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isNotFound());
        }

        @Test
        @DisplayName("CHIME-009: Two users join same callId - second join returns 200 (idempotent)")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void chime009_secondJoinIdempotentReturns200() throws Exception {
            mockCurrentPatient();
            // Simulate already-active meeting still returns credentials
            when(chimeService.joinMeeting(eq(CALL_ID), eq("1"), anyString(), anyString()))
                    .thenReturn(Map.of(
                            "meetingId", "mtg-123",
                            "attendeeId", "att-789",
                            "joinToken", "token-xyz",
                            "mediaRegion", "us-east-1"
                    ));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/join")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.meetingId").exists());
        }
        @Test
        @DisplayName("CHIME-010: conference eligible invitees exclude only active participants, not users who already left")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void chime010_eligibleInviteesAllowsReinviteAfterLeave() throws Exception {
            mockCurrentCaregiver();

            User familyUser = buildUser(4L, "family@test.com", Role.FAMILY_MEMBER);
            when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
            when(userRepository.findById(2L)).thenReturn(Optional.of(caregiverUser));
            when(userRepository.findById(4L)).thenReturn(Optional.of(familyUser));

            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(
                    callEvent("CALL_JOIN", 1L, LocalDateTime.of(2026, 3, 23, 10, 0, 0)),
                    callEvent("CALL_JOIN", 2L, LocalDateTime.of(2026, 3, 23, 10, 0, 5)),
                    callEvent("CALL_JOIN", 4L, LocalDateTime.of(2026, 3, 23, 10, 0, 10)),
                    callEvent("CALL_LEAVE", 4L, LocalDateTime.of(2026, 3, 23, 10, 5, 0))
            ));
            when(caregiverPatientLinkService.getCaregiversByPatient(1L)).thenReturn(Collections.emptyList());
            when(familyMemberService.getFamilyMembersByPatient(1L)).thenReturn(List.of(
                    new FamilyMemberLinkResponse(
                            10L,
                            4L,
                            "Maria Family",
                            "family@test.com",
                            1L,
                            "Patient",
                            "Daughter",
                            "ACTIVE",
                            LocalDateTime.of(2026, 3, 23, 9, 0, 0),
                            "Caregiver")
            ));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/eligible-invitees"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].userId").value(4))
                    .andExpect(jsonPath("$[0].role").value("FAMILY_MEMBER"));
        }

        @Test
        @DisplayName("CHIME-011: POST /end leaves conference active when two participants remain")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void chime011_endCallReturnsLeftWhenConferenceParticipantsRemain() throws Exception {
            mockCurrentCaregiver();

            User patient = buildUser(1L, "patient@test.com", Role.PATIENT);
            User invitee = buildUser(4L, "family@test.com", Role.FAMILY_MEMBER);
            when(userRepository.findById(1L)).thenReturn(Optional.of(patient));
            when(userRepository.findById(2L)).thenReturn(Optional.of(caregiverUser));
            when(userRepository.findById(4L)).thenReturn(Optional.of(invitee));

            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(
                    callEvent("CALL_JOIN", 1L, LocalDateTime.of(2026, 3, 23, 10, 0, 0)),
                    callEvent("CALL_JOIN", 2L, LocalDateTime.of(2026, 3, 23, 10, 0, 5)),
                    callEvent("CALL_JOIN", 4L, LocalDateTime.of(2026, 3, 23, 10, 0, 10))
            ));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/end")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"otherPartyId\":\"1\"}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("left"));

            verify(chimeService, never()).endMeeting(CALL_ID);
            verify(callNotificationHandler).sendNotificationToUser(eq("1"), any());
            verify(callNotificationHandler).sendNotificationToUser(eq("4"), any());
        }

        @Test
        @DisplayName("CHIME-012: POST /invite does not create Chime attendee but records CONFERENCE_INVITE")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void chime012_inviteParticipant_notifyOnlyNoCreateAttendee() throws Exception {
            mockCurrentCaregiver();

            User familyUser = buildUser(4L, "family@test.com", Role.FAMILY_MEMBER);
            familyUser.setName("Maria Family");
            when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
            when(userRepository.findById(4L)).thenReturn(Optional.of(familyUser));
            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(
                    callEvent("CALL_JOIN", 1L, LocalDateTime.of(2026, 3, 23, 10, 0, 0)),
                    callEvent("CALL_JOIN", 2L, LocalDateTime.of(2026, 3, 23, 10, 0, 5))
            ));
            when(familyMemberService.hasAccessToPatient(4L, 1L)).thenReturn(true);
            when(callNotificationHandler.isUserOnline("4")).thenReturn(true);

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/invite")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"targetUserId\":4}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("invited"))
                    .andExpect(jsonPath("$.targetUserId").value(4));

            verify(chimeService, never()).createAttendee(anyString(), anyString(), anyString(), anyString());
            verify(callTelemetryService).recordCallEvent(
                    eq(CALL_ID),
                    eq("CONFERENCE_INVITE"),
                    eq(2L),
                    eq(4L),
                    eq("SUCCESS"),
                    any(),
                    isNull());
            verify(callNotificationHandler).sendNotificationToUser(eq("4"), any());
        }

        @Test
        @DisplayName("CHIME-016: POST /invite offline with phone sends SMS (L1a)")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void inviteParticipant_offlineWithPhone_sendsSms() throws Exception {
            mockCurrentCaregiver();

            User familyUser = buildUser(4L, "family@test.com", Role.FAMILY_MEMBER);
            familyUser.setName("Maria Family");
            familyUser.setPhone("+15559876543");
            when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
            when(userRepository.findById(4L)).thenReturn(Optional.of(familyUser));
            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(
                    callEvent("CALL_JOIN", 1L, LocalDateTime.of(2026, 3, 23, 10, 0, 0)),
                    callEvent("CALL_JOIN", 2L, LocalDateTime.of(2026, 3, 23, 10, 0, 5))
            ));
            when(familyMemberService.hasAccessToPatient(4L, 1L)).thenReturn(true);
            when(callNotificationHandler.isUserOnline("4")).thenReturn(false);
            when(snsService.publishSms(eq("+15559876543"), anyString())).thenReturn("sms-msg-id");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/invite")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"targetUserId\":4}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("offline"))
                    .andExpect(jsonPath("$.targetUserId").value(4));

            verify(callNotificationHandler, never()).sendNotificationToUser(eq("4"), any());
            verify(snsService).publishSms(
                    eq("+15559876543"),
                    argThat(msg -> msg.contains(CALL_ID) && msg.contains("Caregiver")));
            verify(callTelemetryService).recordCallEvent(
                    eq(CALL_ID),
                    eq("CONFERENCE_INVITE"),
                    eq(2L),
                    eq(4L),
                    eq("OFFLINE"),
                    any(),
                    isNull());
        }

        @Test
        @DisplayName("CHIME-016b: POST /invite offline without phone skips SMS")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void inviteParticipant_offlineWithoutPhone_skipsSms() throws Exception {
            mockCurrentCaregiver();

            User familyUser = buildUser(4L, "family@test.com", Role.FAMILY_MEMBER);
            when(userRepository.findById(1L)).thenReturn(Optional.of(patientUser));
            when(userRepository.findById(4L)).thenReturn(Optional.of(familyUser));
            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(
                    callEvent("CALL_JOIN", 1L, LocalDateTime.of(2026, 3, 23, 10, 0, 0)),
                    callEvent("CALL_JOIN", 2L, LocalDateTime.of(2026, 3, 23, 10, 0, 5))
            ));
            when(familyMemberService.hasAccessToPatient(4L, 1L)).thenReturn(true);
            when(callNotificationHandler.isUserOnline("4")).thenReturn(false);

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/invite")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"targetUserId\":4}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("offline"));

            verify(snsService, never()).publishSms(anyString(), anyString());
        }

        @Test
        @DisplayName("CHIME-013: POST /end notifies pending conference invitee who never joined")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void endCall_notifiesPendingConferenceInvitee() throws Exception {
            mockCurrentCaregiver();

            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(
                    callEvent("CALL_JOIN", 1L, LocalDateTime.of(2026, 3, 23, 10, 0, 0)),
                    callEvent("CALL_JOIN", 2L, LocalDateTime.of(2026, 3, 23, 10, 0, 5)),
                    conferenceInviteEvent(2L, 4L, LocalDateTime.of(2026, 3, 23, 10, 1, 0))
            ));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/end")
                            .param("otherPartyId", "1")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("ended"));

            verify(callNotificationHandler).sendNotificationToUser(
                    eq("1"), argThat(m -> "call-ended".equals(m.get("type"))));
            verify(callNotificationHandler).sendNotificationToUser(
                    eq("4"), argThat(m -> "call-ended".equals(m.get("type"))));
            verify(callNotificationHandler, never()).sendNotificationToUser(eq("2"), any());
            verify(callRecordingService).stopRecording(CALL_ID);
            verify(chimeService).endMeeting(CALL_ID);
        }

        @Test
        @DisplayName("CHIME-014: partial leave does not notify pending conference invitee")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void endCall_partialLeaveDoesNotNotifyPendingInvitee() throws Exception {
            mockCurrentCaregiver();

            User joinedFamily = buildUser(5L, "joined-family@test.com", Role.FAMILY_MEMBER);
            when(userRepository.findById(5L)).thenReturn(Optional.of(joinedFamily));

            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(
                    callEvent("CALL_JOIN", 1L, LocalDateTime.of(2026, 3, 23, 10, 0, 0)),
                    callEvent("CALL_JOIN", 2L, LocalDateTime.of(2026, 3, 23, 10, 0, 5)),
                    callEvent("CALL_JOIN", 5L, LocalDateTime.of(2026, 3, 23, 10, 0, 10)),
                    conferenceInviteEvent(2L, 4L, LocalDateTime.of(2026, 3, 23, 10, 1, 0))
            ));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/end")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"otherPartyId\":\"1\"}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("left"));

            verify(callNotificationHandler).sendNotificationToUser(eq("1"), any());
            verify(callNotificationHandler).sendNotificationToUser(eq("5"), any());
            verify(callNotificationHandler, never()).sendNotificationToUser(eq("4"), any());
        }

        @Test
        @DisplayName("CHIME-015: three-party end notifies all remaining active participants")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void endCall_threePartyEndNotifiesAllRemaining() throws Exception {
            mockCurrentPatient();

            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(
                    callEvent("CALL_JOIN", 1L, LocalDateTime.of(2026, 3, 23, 10, 0, 0)),
                    callEvent("CALL_JOIN", 2L, LocalDateTime.of(2026, 3, 23, 10, 0, 5)),
                    callEvent("CALL_JOIN", 4L, LocalDateTime.of(2026, 3, 23, 10, 0, 10)),
                    callEvent("CALL_LEAVE", 2L, LocalDateTime.of(2026, 3, 23, 10, 5, 0))
            ));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/end")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("ended"));

            verify(callNotificationHandler).sendNotificationToUser(
                    eq("4"), argThat(m -> "call-ended".equals(m.get("type"))));
            verify(callNotificationHandler, never()).sendNotificationToUser(eq("1"), any());
            verify(callNotificationHandler, never()).sendNotificationToUser(eq("2"), any());
            verify(callRecordingService).stopRecording(CALL_ID);
            verify(chimeService).endMeeting(CALL_ID);
        }

        @Test
        @DisplayName("CHIME-017: POST /end merges participantUserIds from body into notify set (L8a)")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void endCall_mergesParticipantUserIdsFromBody() throws Exception {
            mockCurrentCaregiver();

            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(
                    callEvent("CALL_JOIN", 1L, LocalDateTime.of(2026, 3, 23, 10, 0, 0)),
                    callEvent("CALL_JOIN", 2L, LocalDateTime.of(2026, 3, 23, 10, 0, 5))
            ));

            Map<String, Object> body = new HashMap<>();
            body.put("otherPartyId", "1");
            body.put("participantUserIds", List.of("4"));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/end")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("left"));

            verify(callNotificationHandler).sendNotificationToUser(
                    eq("1"), argThat(m -> "participant-left".equals(m.get("type"))));
            verify(callNotificationHandler).sendNotificationToUser(
                    eq("4"), argThat(m -> "participant-left".equals(m.get("type"))));
        }

    }

    // 
    //  CALL PERMISSION TESTS
    // 

    @Nested
    @DisplayName("Call Permission Tests")
    class CallPermissionTests {

        @Test
        @DisplayName("CALL-001: POST /join as CAREGIVER returns 200")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void call001_joinAsCaregiverReturns200() throws Exception {
            mockCurrentCaregiver();

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/join")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("CALL-018: POST /join as PATIENT returns 200")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void call018_joinAsPatientReturns200() throws Exception {
            mockCurrentPatient();

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/join")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());
        }
    }

    // 
    //  SENTIMENT TESTS
    // 

    @Nested
    @DisplayName("Sentiment Analysis Tests")
    class SentimentTests {

        @Test
        @DisplayName("SENT-001: POST /sentiment/text as PATIENT with valid text returns 200 and SentimentResult")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void sent001_textSentimentAsPatientReturns200() throws Exception {
            mockCurrentPatient();
            // captureMode must be non-null to avoid Map.of NPE in controller telemetry payload
            Map<String, String> body = Map.of("text", "I feel great today", "captureMode", "realtime");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/text")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.score").value(0.75))
                    .andExpect(jsonPath("$.label").value("POSITIVE"));
        }

        @Test
        @DisplayName("SENT-004: POST /end triggers maybeRecordFinalOverallSentiment (telemetry service called)")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void sent004_endCallTriggersFinalSentimentRecord() throws Exception {
            mockCurrentCaregiver();
            // Provide sentiment data so that maybeRecordFinalOverallSentiment has something to process
            CallTelemetryEvent voiceEvent = new CallTelemetryEvent();
            voiceEvent.setChannel("VOICE");
            voiceEvent.setSentimentScore(0.7);
            voiceEvent.setSentimentLabel("CALM");
            when(callTelemetryService.getLatestSentimentByChannel(CALL_ID))
                    .thenReturn(Map.of("VOICE", voiceEvent));
            when(sentimentService.analyzeFinalOverallSentiment(anyString(), any()))
                    .thenReturn(new SentimentResult(0.7, "CALM", "Good", "COMBINED", CALL_ID, 123L, false));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/end")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            // Verify that a sentiment event was recorded as part of end-call processing
            verify(callTelemetryService, times(1)).recordSentimentEvent(
                    anyString(), anyString(), anyString(), any(), any(), any(), any(), any(), anyString(), any());
        }

        @Test
        @DisplayName("SENT-005: GET /{callId}/telemetry returns 200; getLatestSentimentByChannel is accessible via telemetry data")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void sent005_getTelemetryReturnsLatestSentimentData() throws Exception {
            mockCurrentCaregiver();
            // Participant access: caregiver (id=2) is in the events as actor
            CallTelemetryEvent textEvent = new CallTelemetryEvent();
            textEvent.setChannel("TEXT");
            textEvent.setSentimentScore(0.75);
            textEvent.setSentimentLabel("POSITIVE");
            textEvent.setActorUserId(2L);
            when(callTelemetryService.getTelemetryForCall(CALL_ID))
                    .thenReturn(List.of(textEvent));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/telemetry")
                            .with(csrf()))
                    .andExpect(status().isOk());

            verify(callTelemetryService).getTelemetryForCall(CALL_ID);
        }

        @Test
        @DisplayName("SENT-006: POST /sentiment/text as CAREGIVER returns 403")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void sent006_textSentimentAsCaregiverReturns403() throws Exception {
            mockCurrentCaregiver();
            Map<String, String> body = Map.of("text", "Patient doing well");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/text")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("SENT-006b: POST /sentiment/voice as CAREGIVER returns 403")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void sent006b_voiceSentimentAsCaregiverReturns403() throws Exception {
            mockCurrentCaregiver();
            Map<String, String> body = Map.of(
                    "averageLevel", "0.7",
                    "speechRatio", "0.8",
                    "variability", "0.1"
            );

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/voice")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("SENT-006c: POST /sentiment/video as CAREGIVER returns 403")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void sent006c_videoSentimentAsCaregiverReturns403() throws Exception {
            mockCurrentCaregiver();
            Map<String, String> body = Map.of(
                    "imageBase64", "base64encodedimage==",
                    "imageFormat", "jpeg"
            );

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/video")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("SENT-TEXT-PATIENT: POST /sentiment/text as PATIENT returns 200")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void sentTextPatientReturns200() throws Exception {
            mockCurrentPatient();
            // captureMode must be non-null to avoid Map.of NPE in controller telemetry payload
            Map<String, String> body = Map.of("text", "I am feeling better", "captureMode", "balanced");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/text")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("SENT-TEXT-MISSING: POST /sentiment/text with missing text field returns 400")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void sentTextMissingFieldReturns400() throws Exception {
            mockCurrentPatient();
            Map<String, String> body = new HashMap<>();
            // no "text" key

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/text")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isBadRequest());
        }
    }

    // 
    //  TELEMETRY / SENTIMENT HISTORY TESTS
    // 

    @Nested
    @DisplayName("Telemetry and Sentiment History Tests")
    class TelemetryTests {

        @Test
        @DisplayName("GET /telemetry/my returns 200 with telemetry list")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void getMyTelemetryReturns200() throws Exception {
            mockCurrentPatient();

            mockMvc.perform(get(BASE_URL + "/telemetry/my")
                            .with(csrf()))
                    .andExpect(status().isOk());

            verify(callTelemetryService).getTelemetryForUser(1L);
        }

        @Test
        @DisplayName("GET /sentiment-history?userId=1 returns 200 when requesting own history as PATIENT")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void getSentimentHistorySelfReturns200() throws Exception {
            mockCurrentPatient();

            mockMvc.perform(get(BASE_URL + "/sentiment-history")
                            .param("userId", "1")
                            .with(csrf()))
                    .andExpect(status().isOk());

            verify(callTelemetryService).getSentimentHistoryForUser(1L);
        }

        @Test
        @DisplayName("GET /sentiment-history?userId=42 as CAREGIVER with link access returns 200")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void getSentimentHistoryOtherUserAsCaregiverReturns200() throws Exception {
            mockCurrentCaregiver();
            when(caregiverPatientLinkService.hasAccessToPatient(2L, 42L)).thenReturn(true);

            mockMvc.perform(get(BASE_URL + "/sentiment-history")
                            .param("userId", "42")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("GET /sentiment-history?userId=42 as PATIENT (not own) returns 403")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void getSentimentHistoryOtherUserAsPatientReturns403() throws Exception {
            mockCurrentPatient();

            mockMvc.perform(get(BASE_URL + "/sentiment-history")
                            .param("userId", "42")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }
    }

    // 
    //  RECORDING TESTS
    // 

    @Nested
    @DisplayName("Recording Tests")
    class RecordingTests {

        @Test
        @DisplayName("POST /{callId}/recording/start as authenticated user returns 200")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void startRecordingReturns200() throws Exception {
            mockCurrentCaregiver();
            when(callRecordingService.startRecording(CALL_ID, 2L))
                    .thenReturn(Map.of("status", "STARTED", "callId", CALL_ID));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/recording/start")
                            .with(csrf()))
                    .andExpect(status().isOk());

            verify(callRecordingService).startRecording(CALL_ID, 2L);
        }

        @Test
        @DisplayName("POST /{callId}/recording/stop as authenticated user returns 200")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void stopRecordingReturns200() throws Exception {
            mockCurrentCaregiver();
            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/recording/stop")
                            .with(csrf()))
                    .andExpect(status().isOk());

            verify(callRecordingService).stopRecording(CALL_ID);
        }

        @Test
        @DisplayName("GET /{callId}/recording as ADMIN returns 200")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void getRecordingStatusAsAdminReturns200() throws Exception {
            mockCurrentAdmin();
            when(callRecordingService.getRecordingStatus(CALL_ID))
                    .thenReturn(Map.of("status", "COMPLETED", "callId", CALL_ID));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/recording")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("COMPLETED"));
        }

        @Test
        @DisplayName("GET /{callId}/recording as PATIENT non-participant returns 403")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void getRecordingStatusAsNonParticipantPatientReturns403() throws Exception {
            mockCurrentPatient();

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/recording")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("GET /{callId}/recording as CAREGIVER returns 200")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void getRecordingStatusAsCaregiverReturns200() throws Exception {
            mockCurrentCaregiver();
            when(callRecordingService.getRecordingStatus(CALL_ID))
                    .thenReturn(Map.of("status", "IN_PROGRESS"));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/recording")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("GET /{callId}/recording/playback-url as ADMIN returns 200")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void getPlaybackUrlAsAdminReturns200() throws Exception {
            mockCurrentAdmin();
            when(callRecordingService.generatePlaybackUrl(CALL_ID))
                    .thenReturn(Map.of("url", "https://s3.example.com/recording.mp4"));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/recording/playback-url")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.url").exists());
        }

        @Test
        @DisplayName("GET /{callId}/recording/playback-url as PATIENT non-participant returns 403")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void getPlaybackUrlAsNonParticipantReturns403() throws Exception {
            mockCurrentPatient();

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/recording/playback-url")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("GET /recordings as ADMIN returns all recordings")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void listRecordingsAsAdminReturnsAll() throws Exception {
            mockCurrentAdmin();
            when(callRecordingService.getAllRecordings())
                    .thenReturn(List.of(Map.of("callId", CALL_ID)));

            mockMvc.perform(get(BASE_URL + "/recordings")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].callId").value(CALL_ID));
        }

        @Test
        @DisplayName("GET /recordings?userId=5 as ADMIN filters by user")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void listRecordingsWithUserIdFilterReturnsFiltered() throws Exception {
            mockCurrentAdmin();
            when(callRecordingService.getRecordingsByUser(5L))
                    .thenReturn(List.of(Map.of("callId", "call-user5")));

            mockMvc.perform(get(BASE_URL + "/recordings")
                            .param("userId", "5")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].callId").value("call-user5"));
        }

        @Test
        @DisplayName("GET /recordings as CAREGIVER returns only own recordings")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void listRecordingsAsCaregiverReturnsOwn() throws Exception {
            mockCurrentCaregiver();
            when(callRecordingService.getRecordingsByUser(2L))
                    .thenReturn(List.of(Map.of("callId", CALL_ID)));

            mockMvc.perform(get(BASE_URL + "/recordings")
                            .with(csrf()))
                    .andExpect(status().isOk());

            verify(callRecordingService).getRecordingsByUser(2L);
        }

        @Test
        @DisplayName("GET /recordings as PATIENT returns 403")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void listRecordingsAsPatientReturns403() throws Exception {
            mockCurrentPatient();

            mockMvc.perform(get(BASE_URL + "/recordings")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("POST /{callId}/recording/cleanup-raw returns 200 in test profile")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void cleanupRawArtifactsReturns200() throws Exception {
            mockCurrentAdmin();
            when(callRecordingService.cleanupRawArtifactsForCall(CALL_ID))
                    .thenReturn(Map.of("status", "cleaned"));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/recording/cleanup-raw")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("cleaned"));
        }

        @Test
        @DisplayName("DELETE /recordings purges all recordings in test profile")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void purgeAllRecordingsReturns200() throws Exception {
            mockCurrentAdmin();
            when(callRecordingService.purgeAllRecordings())
                    .thenReturn(Map.of("status", "purged", "deletedCount", 5));

            mockMvc.perform(delete(BASE_URL + "/recordings")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("purged"));
        }
    }

    // 
    //  VOICE SENTIMENT (PATIENT) TESTS
    // 

    @Nested
    @DisplayName("Voice Sentiment as Patient Tests")
    class VoiceSentimentPatientTests {

        @Test
        @DisplayName("POST /sentiment/voice as PATIENT with valid metrics returns 200")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void voiceSentimentAsPatientReturns200() throws Exception {
            mockCurrentPatient();
            Map<String, String> body = new HashMap<>();
            body.put("averageLevel", "0.5");
            body.put("speechRatio", "0.6");
            body.put("variability", "0.3");
            body.put("captureMode", "realtime");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/voice")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("POST /sentiment/voice with silence window returns 202 ACCEPTED")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void voiceSentimentSilenceWindowReturns202() throws Exception {
            mockCurrentPatient();
            Map<String, String> body = new HashMap<>();
            body.put("averageLevel", "0.01");
            body.put("speechRatio", "0.02");
            body.put("variability", "0.05");
            body.put("captureMode", "realtime");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/voice")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isAccepted());
        }

        @Test
        @DisplayName("POST /sentiment/voice with missing metrics returns 400")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void voiceSentimentMissingMetricsReturns400() throws Exception {
            mockCurrentPatient();
            Map<String, String> body = new HashMap<>();
            body.put("averageLevel", "0.5");
            // missing speechRatio and variability

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/voice")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @DisplayName("POST /sentiment/voice service exception returns 500")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void voiceSentimentServiceExceptionReturns500() throws Exception {
            mockCurrentPatient();
            Map<String, String> body = new HashMap<>();
            body.put("averageLevel", "0.5");
            body.put("speechRatio", "0.6");
            body.put("variability", "0.3");

            when(sentimentService.analyzeVoiceFromChimeMetrics(anyString(), any(), any(), any()))
                    .thenThrow(new RuntimeException("Bedrock timeout"));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/voice")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isInternalServerError());
        }
    }

    // 
    //  VIDEO SENTIMENT (PATIENT) TESTS
    // 

    @Nested
    @DisplayName("Video Sentiment as Patient Tests")
    class VideoSentimentPatientTests {

        @Test
        @DisplayName("POST /sentiment/video as PATIENT with valid image returns 200")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void videoSentimentAsPatientReturns200() throws Exception {
            mockCurrentPatient();
            Map<String, String> body = Map.of(
                    "imageBase64", "base64encodedimage==",
                    "imageFormat", "jpeg",
                    "captureMode", "realtime"
            );

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/video")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("POST /sentiment/video with missing imageBase64 returns 400")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void videoSentimentMissingImageReturns400() throws Exception {
            mockCurrentPatient();
            Map<String, String> body = new HashMap<>();
            body.put("imageFormat", "jpeg");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/video")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @DisplayName("POST /sentiment/video service exception returns 500")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void videoSentimentServiceExceptionReturns500() throws Exception {
            mockCurrentPatient();
            Map<String, String> body = Map.of(
                    "imageBase64", "base64data",
                    "imageFormat", "png"
            );
            when(sentimentService.analyzeVideoFrame(anyString(), anyString(), anyString()))
                    .thenThrow(new RuntimeException("Bedrock error"));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/video")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isInternalServerError());
        }
    }

    // 
    //  COMBINED SENTIMENT TESTS
    // 

    @Nested
    @DisplayName("Combined Sentiment Tests")
    class CombinedSentimentTests {

        @Test
        @DisplayName("POST /sentiment/combined as PATIENT returns 200 with combined result")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void combinedSentimentReturns200() throws Exception {
            mockCurrentPatient();
            Map<String, String> body = new HashMap<>();
            body.put("text", "I feel great");
            body.put("imageBase64", "base64img==");
            body.put("imageFormat", "jpeg");
            body.put("averageLevel", "0.5");
            body.put("speechRatio", "0.6");
            body.put("variability", "0.3");
            body.put("captureMode", "balanced");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/combined")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.overall.score").value(0.5))
                    .andExpect(jsonPath("$.overall.label").value("ANXIOUS"));
        }

        @Test
        @DisplayName("POST /sentiment/combined as CAREGIVER returns 403")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void combinedSentimentAsCaregiverReturns403() throws Exception {
            mockCurrentCaregiver();
            Map<String, String> body = Map.of("text", "Patient data");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/combined")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("POST /sentiment/combined with empty inputs still returns 200")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void combinedSentimentEmptyInputsReturns200() throws Exception {
            mockCurrentPatient();
            Map<String, String> body = new HashMap<>();

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/combined")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("POST /sentiment/combined service exception returns 500")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void combinedSentimentServiceExceptionReturns500() throws Exception {
            mockCurrentPatient();
            Map<String, String> body = new HashMap<>();
            body.put("text", "Test");

            when(sentimentService.analyzeText(anyString(), anyString()))
                    .thenThrow(new RuntimeException("Service down"));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/combined")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isInternalServerError());
        }
    }

    // 
    //  TRANSCRIPTION DEBUG TESTS
    // 

    @Nested
    @DisplayName("Transcription Debug Tests")
    class TranscriptionDebugTests {

        @Test
        @DisplayName("GET /{callId}/transcription/debug returns 200 with debug info")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void getTranscriptionDebugReturns200() throws Exception {
            mockCurrentCaregiver();
            Map<String, Object> debugStatus = new HashMap<>();
            debugStatus.put("transcriptionActive", true);
            debugStatus.put("engineType", "medical");
            when(chimeService.getTranscriptionDebugStatus(CALL_ID)).thenReturn(debugStatus);

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/transcription/debug")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.transcriptionActive").value(true))
                    .andExpect(jsonPath("$.requestedByUserId").value(2))
                    .andExpect(jsonPath("$.requestedByRole").value("CAREGIVER"));
        }
    }

    // 
    //  TRANSCRIPT SEGMENT TESTS
    // 

    @Nested
    @DisplayName("Transcript Segment Tests")
    class TranscriptSegmentTests {

        @Test
        @DisplayName("POST /{callId}/transcript/segments saves segments for participant")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void saveTranscriptSegmentsAsParticipantReturns200() throws Exception {
            mockCurrentCaregiver();
            // Make caregiver a participant
            CallTelemetryEvent event = new CallTelemetryEvent();
            event.setActorUserId(2L);
            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(event));
            when(callTranscriptService.recordSegments(anyString(), anyLong(), any())).thenReturn(2);

            Map<String, Object> body = new HashMap<>();
            List<Map<String, Object>> segments = new ArrayList<>();
            Map<String, Object> seg1 = new HashMap<>();
            seg1.put("speakerLabel", "Speaker 1");
            seg1.put("text", "Hello");
            seg1.put("startMs", 0);
            seg1.put("endMs", 1000);
            seg1.put("source", "chime");
            segments.add(seg1);
            body.put("segments", segments);

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/transcript/segments")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.savedSegments").value(2))
                    .andExpect(jsonPath("$.status").value("saved"));
        }

        @Test
        @DisplayName("POST /{callId}/transcript/segments as ADMIN (non-participant) returns 200")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void saveTranscriptSegmentsAsAdminReturns200() throws Exception {
            mockCurrentAdmin();
            when(callTranscriptService.recordSegments(anyString(), anyLong(), any())).thenReturn(1);

            Map<String, Object> body = new HashMap<>();
            body.put("speakerLabel", "Speaker 1");
            body.put("text", "Single segment");
            body.put("startMs", 0);
            body.put("endMs", 500);
            body.put("source", "manual");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/transcript/segments")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("POST /{callId}/transcript/segments as non-participant non-admin returns 403")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void saveTranscriptSegmentsAsNonParticipantReturns403() throws Exception {
            mockCurrentPatient();
            // Empty telemetry - not a participant
            Map<String, Object> body = Map.of("text", "test");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/transcript/segments")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("GET /{callId}/transcript/segments as participant returns 200")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void getTranscriptSegmentsAsParticipantReturns200() throws Exception {
            mockCurrentCaregiver();
            CallTelemetryEvent event = new CallTelemetryEvent();
            event.setActorUserId(2L);
            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(event));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/transcript/segments")
                            .with(csrf()))
                    .andExpect(status().isOk());

            verify(callTranscriptService).getSegmentsForCall(CALL_ID);
        }

        @Test
        @DisplayName("GET /{callId}/transcript/segments as non-participant non-admin returns 403")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void getTranscriptSegmentsAsNonParticipantReturns403() throws Exception {
            mockCurrentPatient();

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/transcript/segments")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("GET /{callId}/transcript/segments as user with transcript access returns 200")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void getTranscriptSegmentsWithTranscriptAccessReturns200() throws Exception {
            mockCurrentPatient();
            when(callTranscriptService.hasTranscriptAccess(CALL_ID, 1L)).thenReturn(true);

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/transcript/segments")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }
    }

    // 
    //  CALL SUMMARY TESTS
    // 

    @Nested
    @DisplayName("Call Summary Tests")
    class CallSummaryTests {

        @Test
        @DisplayName("GET /{callId}/summary returns 404 when no summary exists")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void getSummaryNotFoundReturns404() throws Exception {
            mockCurrentAdmin();

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/summary")
                            .with(csrf()))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.status").value("NOT_FOUND"));
        }

        @Test
        @DisplayName("GET /{callId}/summary returns 200 when summary exists for admin")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void getSummaryAsAdminReturns200() throws Exception {
            mockCurrentAdmin();
            when(callSummaryService.getLatestSummary(CALL_ID))
                    .thenReturn(Optional.of(Map.of("callId", CALL_ID, "summary", "Patient was calm")));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/summary")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.summary").value("Patient was calm"));
        }

        @Test
        @DisplayName("GET /{callId}/summary regenerates when status=NO_TRANSCRIPT but segments exist")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void getSummaryRegeneratesWhenNoTranscriptButSegmentsExist() throws Exception {
            mockCurrentAdmin();
            com.careconnect.model.CallSummary summaryEntity = new com.careconnect.model.CallSummary();
            summaryEntity.setStatus("NO_TRANSCRIPT");
            summaryEntity.setGeneratedByUserId(3L);
            when(callSummaryService.getLatestSummaryEntity(CALL_ID))
                    .thenReturn(Optional.of(summaryEntity));
            when(callTranscriptService.countSegments(CALL_ID)).thenReturn(5L);
            when(callSummaryService.getLatestSummary(CALL_ID))
                    .thenReturn(Optional.of(Map.of("status", "GENERATED")));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/summary")
                            .with(csrf()))
                    .andExpect(status().isOk());

            verify(callSummaryService).generateAndStoreSummary(eq(CALL_ID), eq(3L), any());
        }

        @Test
        @DisplayName("GET /{callId}/summary as non-participant non-admin returns 403")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void getSummaryAsNonParticipantReturns403() throws Exception {
            mockCurrentPatient();

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/summary")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("GET /{callId}/summary as summary owner returns 200")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void getSummaryAsSummaryOwnerReturns200() throws Exception {
            mockCurrentPatient();
            com.careconnect.model.CallSummary summaryEntity = new com.careconnect.model.CallSummary();
            summaryEntity.setStatus("GENERATED");
            summaryEntity.setGeneratedByUserId(1L);
            when(callSummaryService.getLatestSummaryEntity(CALL_ID))
                    .thenReturn(Optional.of(summaryEntity));
            when(callSummaryService.getLatestSummary(CALL_ID))
                    .thenReturn(Optional.of(Map.of("status", "GENERATED")));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/summary")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }
    }

    // 
    //  TELEMETRY DELETION TESTS
    // 

    @Nested
    @DisplayName("Telemetry Deletion Tests")
    class TelemetryDeletionTests {

        @Test
        @DisplayName("DELETE /{callId}/telemetry returns 200 with deletion counts")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void deleteCallTelemetryReturns200() throws Exception {
            mockCurrentAdmin();
            when(callTelemetryService.deleteTelemetryForCall(CALL_ID)).thenReturn(3L);
            when(callSummaryService.deleteSummariesForCall(CALL_ID)).thenReturn(1L);
            when(callTranscriptService.purgeForCall(CALL_ID))
                    .thenReturn(Map.of("deletedTranscriptSegments", 5L, "deletedTranscriptArchives", 1L));
            when(callRecordingService.purgeRecordingsForCall(CALL_ID))
                    .thenReturn(Map.of("deletedDbRows", 2, "deletedS3Objects", 2));

            mockMvc.perform(delete(BASE_URL + "/" + CALL_ID + "/telemetry")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.callId").value(CALL_ID))
                    .andExpect(jsonPath("$.deletedEvents").value(3))
                    .andExpect(jsonPath("$.deletedSummaries").value(1))
                    .andExpect(jsonPath("$.status").value("deleted"));
        }

        @Test
        @DisplayName("DELETE /patients/{patientUserId}/telemetry returns 200")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void deletePatientCallHistoryReturns200() throws Exception {
            mockCurrentAdmin();
            CallTelemetryService.PatientCallHistoryMatch match =
                    new CallTelemetryService.PatientCallHistoryMatch(
                            List.of(new CallTelemetryEvent()),
                            Set.of("call-a", "call-b")
                    );
            when(callTelemetryService.findCallHistoryForPatient(42L)).thenReturn(match);
            when(callTelemetryService.deleteTelemetryEvents(any())).thenReturn(2L);
            when(callSummaryService.deleteSummariesForCall(anyString())).thenReturn(0L);
            when(callTranscriptService.purgeForCall(anyString())).thenReturn(Map.of());
            when(callRecordingService.purgeRecordingsForCall(anyString())).thenReturn(Map.of());

            mockMvc.perform(delete(BASE_URL + "/patients/42/telemetry")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.patientUserId").value(42))
                    .andExpect(jsonPath("$.deletedEvents").value(2))
                    .andExpect(jsonPath("$.status").value("deleted"));
        }
    }

    // 
    //  END CALL WITH OTHER PARTY TESTS
    // 

    @Nested
    @DisplayName("End Call With OtherPartyId Tests")
    class EndCallOtherPartyTests {

        @Test
        @DisplayName("POST /end with otherPartyId query param notifies other party")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void endCallWithOtherPartyIdNotifiesOtherParty() throws Exception {
            mockCurrentCaregiver();

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/end")
                            .param("otherPartyId", "1")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("ended"));

            verify(callNotificationHandler).sendNotificationToUser(eq("1"), any());
        }

        @Test
        @DisplayName("POST /end with otherPartyId in body notifies other party")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void endCallWithOtherPartyIdInBodyNotifiesOtherParty() throws Exception {
            mockCurrentCaregiver();
            Map<String, Object> body = new HashMap<>();
            body.put("otherPartyId", "1");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/end")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk());

            verify(callNotificationHandler).sendNotificationToUser(eq("1"), any());
        }

        @Test
        @DisplayName("POST /end RuntimeException returns 500")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void endCallRuntimeExceptionReturns500() throws Exception {
            mockCurrentCaregiver();
            doThrow(new RuntimeException("Chime unavailable"))
                    .when(chimeService).endMeeting(anyString());

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/end")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isInternalServerError());
        }
    }

    // 
    //  TELEMETRY ACCESS CONTROL TESTS
    // 

    @Nested
    @DisplayName("Telemetry Access Control Tests")
    class TelemetryAccessControlTests {

        @Test
        @DisplayName("GET /{callId}/telemetry as non-participant non-admin returns 403")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void getTelemetryAsNonParticipantReturns403() throws Exception {
            mockCurrentPatient();
            // Return events that don't include the patient
            CallTelemetryEvent event = new CallTelemetryEvent();
            event.setActorUserId(99L);
            event.setTargetUserId(98L);
            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(event));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/telemetry")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("GET /{callId}/telemetry as ADMIN returns 200 regardless of participation")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void getTelemetryAsAdminReturns200() throws Exception {
            mockCurrentAdmin();
            CallTelemetryEvent event = new CallTelemetryEvent();
            event.setActorUserId(99L);
            when(callTelemetryService.getTelemetryForCall(CALL_ID)).thenReturn(List.of(event));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/telemetry")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("GET /{callId}/telemetry returns empty list for no events")
        @WithMockUser(username = "patient@test.com", roles = {"PATIENT"})
        void getTelemetryEmptyEventsReturns200() throws Exception {
            mockCurrentPatient();

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/telemetry")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("GET /sentiment-history as ADMIN for any user returns 200")
        @WithMockUser(username = "admin@test.com", roles = {"ADMIN"})
        void getSentimentHistoryAsAdminReturns200() throws Exception {
            mockCurrentAdmin();

            mockMvc.perform(get(BASE_URL + "/sentiment-history")
                            .param("userId", "99")
                            .with(csrf()))
                    .andExpect(status().isOk());

            verify(callTelemetryService).getSentimentHistoryForUser(99L);
        }

        @Test
        @DisplayName("GET /sentiment-history as CAREGIVER without link returns 403")
        @WithMockUser(username = "caregiver@test.com", roles = {"CAREGIVER"})
        void getSentimentHistoryAsCaregiverWithoutLinkReturns403() throws Exception {
            mockCurrentCaregiver();
            when(caregiverPatientLinkService.hasAccessToPatient(2L, 42L)).thenReturn(false);

            mockMvc.perform(get(BASE_URL + "/sentiment-history")
                            .param("userId", "42")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }
    }
}
