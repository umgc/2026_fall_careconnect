package com.careconnect.controller;

import com.careconnect.config.CareconnectTestConfig;
import com.careconnect.exception.AppException;
import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.model.CallSession;
import com.careconnect.model.User;
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
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
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
@TestPropertySource(properties = "careconnect.recording.global-purge-enabled=true")
@DisplayName("CallController Extended Tests")
class CallControllerExtendedTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean private ChimeService chimeService;
    @MockitoBean private BedrockSentimentService sentimentService;
    @MockitoBean private CallTelemetryService callTelemetryService;
    @MockitoBean private CallTranscriptService callTranscriptService;
    @MockitoBean private CallSummaryService callSummaryService;
    @MockitoBean private CallRecordingService callRecordingService;
    @MockitoBean private CaregiverPatientLinkService caregiverPatientLinkService;
    @MockitoBean private com.careconnect.service.consent.CaregiverVisibilityService caregiverVisibilityService;
    @MockitoBean private com.careconnect.service.CallAttendeeService callAttendeeService;
    @MockitoBean private FamilyMemberService familyMemberService;
    @MockitoBean private UserRepository userRepository;
    @MockitoBean private CallNotificationHandler callNotificationHandler;
    @MockitoBean private SnsService snsService;
    @MockitoBean private CallSessionService callSessionService;
    @MockitoBean private CallTerminationExecutor callTerminationExecutor;
    @MockitoBean private CallSummaryItemConfirmService callSummaryItemConfirmService;
    @MockitoBean private CallAttendeeService callAttendeeService;

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
        CallSession durableSession = new CallSession();
        durableSession.setId(10L);
        durableSession.setCallId(CALL_ID);
        durableSession.setPatientId(42L);
        durableSession.setCreatedByUserId(2L);
        durableSession.setStatus(CallSessionService.SESSION_CREATED);
        when(callSessionService.requireJoinAuthorized(anyString(), anyLong()))
                .thenReturn(durableSession);
        when(callSessionService.requireSession(anyString())).thenReturn(durableSession);
        when(callSessionService.requirePatientUserId(any())).thenReturn(1L);
        when(callSessionService.recordJoin(any(), anyLong(), any())).thenReturn(false);
        doNothing().when(callSessionService).attachChimeMeetingId(anyString(), anyString());
        doNothing().when(callSessionService).revertJoinAfterChimeFailure(anyString(), anyLong());

        // User repository stubs
        when(userRepository.findByEmail("patient@test.com")).thenReturn(Optional.of(patientUser));
        when(userRepository.findByEmail("caregiver@test.com")).thenReturn(Optional.of(caregiverUser));
        when(userRepository.findByEmail("admin@test.com")).thenReturn(Optional.of(adminUser));

        // Telemetry void stubs
        doNothing().when(callTelemetryService).recordCallEvent(
                anyString(), anyString(), any(), any(), anyString(), any(), any());
        doNothing().when(callTelemetryService).recordSentimentEvent(
                anyString(), anyString(), anyString(), any(), any(), any(), any(), any(), anyString(), any());

        // Default telemetry
        when(callTelemetryService.getTelemetryForCall(anyString())).thenReturn(Collections.emptyList());
        when(callTelemetryService.getTelemetryForUser(anyLong())).thenReturn(Collections.emptyList());
        when(callTelemetryService.getLatestSentimentByChannel(anyString())).thenReturn(Collections.emptyMap());
        when(callTelemetryService.getSentimentHistoryForUser(anyLong())).thenReturn(Collections.emptyList());

        // Default summary stubs
        when(callSummaryService.getLatestSummaryEntity(anyString())).thenReturn(Optional.empty());
        when(callSummaryService.getLatestSummary(anyString())).thenReturn(Optional.empty());
        when(callSummaryService.deleteSummariesForCall(anyString())).thenReturn(0L);

        // Default recording stubs
        when(callRecordingService.startRecording(anyString(), anyLong()))
                .thenReturn(Map.of("status", "STARTED", "pipelineId", "pipe-123"));
        when(callRecordingService.stopRecording(anyString()))
                .thenReturn(Map.of("status", "STOPPED"));
        when(callRecordingService.getRecordingStatus(anyString()))
                .thenReturn(Map.of("status", "RECORDING", "ownerUserId", "2"));
        when(callRecordingService.generatePlaybackUrl(anyString()))
                .thenReturn(Map.of("url", "https://s3.example.com/recording.mp4"));
        when(callRecordingService.getAllRecordings())
                .thenReturn(List.of(Map.of("callId", "call-123")));
        when(callRecordingService.getRecordingsByUser(anyLong()))
                .thenReturn(List.of());
        when(callRecordingService.cleanupRawArtifactsForCall(anyString()))
                .thenReturn(Map.of("status", "CLEANED"));
        when(callRecordingService.purgeAllRecordings())
                .thenReturn(Map.of("deletedDbRows", 5, "deletedS3Objects", 10));
        when(callRecordingService.purgeRecordingsForCall(anyString()))
                .thenReturn(Map.of("deletedDbRows", 1L, "deletedS3Objects", 2L));

        // Default telemetry delete stubs
        when(callTelemetryService.deleteTelemetryForCall(anyString())).thenReturn(3L);
        when(callTelemetryService.deleteTelemetryEvents(any())).thenReturn(5L);

        // Default transcript stubs
        when(callTranscriptService.hasTranscriptAccess(anyString(), anyLong())).thenReturn(false);
        when(callTranscriptService.countSegments(anyString())).thenReturn(0L);
        when(callTranscriptService.getSegmentsForCall(anyString())).thenReturn(Collections.emptyList());
        when(callTranscriptService.recordSegments(anyString(), anyLong(), any())).thenReturn(1);
        when(callTranscriptService.purgeForCall(anyString()))
                .thenReturn(Map.of("deletedTranscriptSegments", 2L, "deletedTranscriptArchives", 0L));

        // Default Chime stubs
        when(chimeService.getTranscriptionDebugStatus(anyString()))
                .thenReturn(Map.of("status", "STARTED"));
        when(chimeService.isMeetingActive(anyString())).thenReturn(true);

        // Default patient call history stub
        when(callTelemetryService.findCallHistoryForPatient(anyLong()))
                .thenReturn(new CallTelemetryService.PatientCallHistoryMatch(List.of(), Set.of("call-123")));
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private User buildUser(Long id, String email, Role role) {
        User u = new User();
        u.setId(id);
        u.setEmail(email);
        u.setRoles(Set.of(role));
        return u;
    }

    private SentimentResult mockSentimentResult() {
        return new SentimentResult(0.8, "POSITIVE", "", "TEXT", CALL_ID, System.currentTimeMillis(), false);
    }

    /** Returns a telemetry event list where patient (id=1) is the actor — grants participant access. */
    private List<CallTelemetryEvent> patientParticipantEvents() {
        CallTelemetryEvent event = new CallTelemetryEvent();
        event.setActorUserId(1L);
        return List.of(event);
    }

    /** Returns a telemetry event list where admin (id=3) is the actor. */
    private List<CallTelemetryEvent> adminParticipantEvents() {
        CallTelemetryEvent event = new CallTelemetryEvent();
        event.setActorUserId(3L);
        return List.of(event);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  COMBINED SENTIMENT TESTS
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Combined Sentiment Tests")
    class CombinedSentimentTests {

        @Test
        @DisplayName("POST /{callId}/sentiment/combined as PATIENT returns 200 with combined map")
        @WithMockUser(username = "patient@test.com")
        void combinedSentiment_patientSubmits_returns200() throws Exception {
            SentimentResult result = mockSentimentResult();
            when(sentimentService.analyzeText(anyString(), anyString())).thenReturn(result);
            when(sentimentService.buildCombinedSentiment(any(), any(), any(), anyString()))
                    .thenReturn(Map.of(
                            "overall", Map.of("score", 0.8, "label", "POSITIVE"),
                            "timestamp", System.currentTimeMillis()));

            Map<String, String> body = Map.of("text", "I am feeling better today", "captureMode", "realtime");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/combined")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("POST /{callId}/sentiment/combined as CAREGIVER returns 403 (ensurePatientSource fails)")
        @WithMockUser(username = "caregiver@test.com")
        void combinedSentiment_caregiverSubmits_returns403() throws Exception {
            Map<String, String> body = Map.of("text", "Patient seems calm");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/combined")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("POST /{callId}/sentiment/combined as PATIENT with text only (no voice/video) returns 200")
        @WithMockUser(username = "patient@test.com")
        void combinedSentiment_textOnly_returns200() throws Exception {
            SentimentResult result = mockSentimentResult();
            when(sentimentService.analyzeText(anyString(), anyString())).thenReturn(result);
            when(sentimentService.buildCombinedSentiment(any(), any(), any(), anyString()))
                    .thenReturn(Map.of(
                            "overall", Map.of("score", 0.8, "label", "POSITIVE"),
                            "timestamp", System.currentTimeMillis()));

            // Only provide text — no voice metrics, no imageBase64
            Map<String, String> body = Map.of("text", "Feeling okay");

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/sentiment/combined")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk());
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  CALL SUMMARY TESTS
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Call Summary Tests")
    class CallSummaryTests {

        @Test
        @DisplayName("GET /{callId}/summary as ADMIN returns 200 with summary present")
        @WithMockUser(username = "admin@test.com")
        void getCallSummary_adminAccess_returns200() throws Exception {
            when(callSummaryService.getLatestSummary(anyString()))
                    .thenReturn(Optional.of(Map.of("callId", "call-123", "status", "COMPLETE")));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/summary")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.callId").value("call-123"))
                    .andExpect(jsonPath("$.status").value("COMPLETE"));
        }

        @Test
        @DisplayName("GET /{callId}/summary as non-participant returns 403")
        @WithMockUser(username = "patient@test.com")
        void getCallSummary_nonParticipant_returns403() throws Exception {
            // No telemetry events → patient is not a participant → 403
            when(callTelemetryService.getTelemetryForCall(anyString())).thenReturn(Collections.emptyList());
            when(callTranscriptService.hasTranscriptAccess(anyString(), anyLong())).thenReturn(false);
            when(callSummaryService.getLatestSummaryEntity(anyString())).thenReturn(Optional.empty());
            doThrow(new AppException(HttpStatus.FORBIDDEN, "User is not authorized for this call"))
                    .when(callSessionService)
                    .requireHistoricalParticipant(CALL_ID, patientUser.getId());

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/summary")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("GET /{callId}/summary when no summary found returns 404 with status=NOT_FOUND")
        @WithMockUser(username = "admin@test.com")
        void getCallSummary_notFound_returns404() throws Exception {
            when(callSummaryService.getLatestSummary(anyString())).thenReturn(Optional.empty());
            when(callSummaryService.getLatestSummaryEntity(anyString())).thenReturn(Optional.empty());

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/summary")
                            .with(csrf()))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.status").value("NOT_FOUND"));
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  TRANSCRIPT SEGMENT TESTS
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Transcript Segment Tests")
    class TranscriptSegmentTests {

        @Test
        @DisplayName("GET /{callId}/transcript/segments as ADMIN returns 200 with list")
        @WithMockUser(username = "admin@test.com")
        void getTranscriptSegments_admin_returns200() throws Exception {
            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/transcript/segments")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("GET /{callId}/transcript/segments as non-participant returns 403")
        @WithMockUser(username = "patient@test.com")
        void getTranscriptSegments_nonParticipant_returns403() throws Exception {
            when(callTelemetryService.getTelemetryForCall(anyString())).thenReturn(Collections.emptyList());
            when(callTranscriptService.hasTranscriptAccess(anyString(), anyLong())).thenReturn(false);
            doThrow(new AppException(HttpStatus.FORBIDDEN, "User is not authorized for this call"))
                    .when(callSessionService)
                    .requireHistoricalParticipant(CALL_ID, patientUser.getId());

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/transcript/segments")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("POST /{callId}/transcript/segments as ADMIN saves segments and returns 200")
        @WithMockUser(username = "admin@test.com")
        void saveTranscriptSegments_admin_returns200() throws Exception {
            Map<String, Object> body = Map.of(
                    "clientSegmentId", "b6814f33-12e0-4f6e-80b7-ec71197da642",
                    "speakerLabel", "patient",
                    "text", "I have been feeling better",
                    "startMs", 1000,
                    "endMs", 3000,
                    "source", "chime"
            );

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/transcript/segments")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("saved"));
        }

        @Test
        @DisplayName("POST /{callId}/transcript/segments as non-participant returns 403")
        @WithMockUser(username = "patient@test.com")
        void saveTranscriptSegments_nonParticipant_returns403() throws Exception {
            when(callTelemetryService.getTelemetryForCall(anyString())).thenReturn(Collections.emptyList());
            doThrow(new AppException(HttpStatus.FORBIDDEN, "User must join the call"))
                    .when(callSessionService).requireTranscriptUploadParticipant(CALL_ID, patientUser.getId());

            Map<String, Object> body = Map.of(
                    "clientSegmentId", "efee89b3-8700-4677-b8a8-d2666cb58de5",
                    "speakerLabel", "patient",
                    "text", "Hello",
                    "startMs", 0,
                    "endMs", 1000,
                    "source", "chime"
            );

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/transcript/segments")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isForbidden());
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  DELETE TELEMETRY TESTS (dev mode)
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Delete Call Telemetry Tests (dev/local mode)")
    class DeleteCallTelemetryTests {

        @Test
        @DisplayName("DELETE /{callId}/telemetry in test profile returns 200 with deletedEvents")
        @WithMockUser(username = "admin@test.com")
        void deleteCallTelemetry_testProfile_returns200() throws Exception {
            when(callTelemetryService.deleteTelemetryForCall(anyString())).thenReturn(3L);
            when(callSummaryService.deleteSummariesForCall(anyString())).thenReturn(1L);
            when(callTranscriptService.purgeForCall(anyString()))
                    .thenReturn(Map.of("deletedTranscriptSegments", 2L, "deletedTranscriptArchives", 0L));

            mockMvc.perform(delete(BASE_URL + "/" + CALL_ID + "/telemetry")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.deletedEvents").value(3))
                    .andExpect(jsonPath("$.status").value("deleted"));
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  DELETE PATIENT CALL HISTORY TESTS (dev mode)
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Delete Patient Call History Tests (dev/local mode)")
    class DeletePatientCallHistoryTests {

        @Test
        @DisplayName("DELETE /patients/{patientUserId}/telemetry in test profile returns 200")
        @WithMockUser(username = "admin@test.com")
        void deletePatientCallHistory_testProfile_returns200() throws Exception {
            when(callTelemetryService.findCallHistoryForPatient(anyLong()))
                    .thenReturn(new CallTelemetryService.PatientCallHistoryMatch(List.of(), Set.of("call-123")));
            when(callTelemetryService.deleteTelemetryEvents(any())).thenReturn(5L);

            mockMvc.perform(delete(BASE_URL + "/patients/1/telemetry")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("deleted"));
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  SENTIMENT HISTORY TESTS
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Sentiment History Tests")
    class SentimentHistoryTests {

        @Test
        @DisplayName("GET /sentiment-history?userId=1 as own user returns 200")
        @WithMockUser(username = "patient@test.com")
        void getSentimentHistory_ownUserId_returns200() throws Exception {
            when(callTelemetryService.getSentimentHistoryForUser(anyLong())).thenReturn(List.of());

            mockMvc.perform(get(BASE_URL + "/sentiment-history")
                            .param("userId", "1")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("GET /sentiment-history?userId=42 as PATIENT (different user) returns 403")
        @WithMockUser(username = "patient@test.com")
        void getSentimentHistory_otherUserAsPatient_returns403() throws Exception {
            mockMvc.perform(get(BASE_URL + "/sentiment-history")
                            .param("userId", "42")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  MY TELEMETRY TESTS
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("My Telemetry Tests")
    class MyTelemetryTests {

        @Test
        @DisplayName("GET /telemetry/my returns 200 with list")
        @WithMockUser(username = "patient@test.com")
        void getMyTelemetry_returns200() throws Exception {
            when(callTelemetryService.getTelemetryForUser(1L)).thenReturn(List.of());

            mockMvc.perform(get(BASE_URL + "/telemetry/my")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  RECORDING EXTENDED TESTS
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Recording Extended Tests")
    class RecordingExtendedTests {

        @Test
        @DisplayName("POST /{callId}/recording/start returns 200 with result from recordingService")
        @WithMockUser(username = "caregiver@test.com")
        void startRecording_returns200WithResult() throws Exception {
            when(callRecordingService.startRecording(anyString(), anyLong()))
                    .thenReturn(Map.of("status", "STARTED", "pipelineId", "pipe-123"));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/recording/start")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("STARTED"))
                    .andExpect(jsonPath("$.pipelineId").value("pipe-123"));
        }

        @Test
        @DisplayName("POST /{callId}/recording/stop returns 200")
        @WithMockUser(username = "caregiver@test.com")
        void stopRecording_returns200() throws Exception {
            when(callRecordingService.getRecordingStatus(anyString()))
                    .thenReturn(Map.of("status", "RECORDING", "ownerUserId", "2"));
            when(callRecordingService.stopRecording(anyString()))
                    .thenReturn(Map.of("status", "STOPPED"));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/recording/stop")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("STOPPED"));
        }

        @Test
        @DisplayName("GET /{callId}/recording as ADMIN returns 200")
        @WithMockUser(username = "admin@test.com")
        void getRecordingStatus_admin_returns200() throws Exception {
            when(callRecordingService.getRecordingStatus(anyString()))
                    .thenReturn(Map.of("status", "RECORDING"));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/recording")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("RECORDING"));
        }

        @Test
        @DisplayName("GET /{callId}/recording as PATIENT non-participant returns 403")
        @WithMockUser(username = "patient@test.com")
        void getRecordingStatus_patientNonParticipant_returns403() throws Exception {
            when(callTelemetryService.getTelemetryForCall(anyString())).thenReturn(Collections.emptyList());
            doThrow(new AppException(HttpStatus.FORBIDDEN, "Recording access denied"))
                    .when(callSessionService).requireRecordingAccess(CALL_ID, patientUser);

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/recording")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("GET /{callId}/recording/playback-url as ADMIN returns 200 with url")
        @WithMockUser(username = "admin@test.com")
        void getRecordingPlaybackUrl_admin_returns200() throws Exception {
            when(callRecordingService.generatePlaybackUrl(anyString()))
                    .thenReturn(Map.of(
                            "playbackUrl", "https://s3.example.com/recording.mp4",
                            "recordingStartedAt", "2026-06-29T16:57:43Z"));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/recording/playback-url")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.playbackUrl").value("https://s3.example.com/recording.mp4"))
                    .andExpect(jsonPath("$.recordingStartedAt").value("2026-06-29T16:57:43Z"));
        }

        @Test
        @DisplayName("GET /{callId}/recording/playback-url as CAREGIVER returns 200")
        @WithMockUser(username = "caregiver@test.com")
        void getRecordingPlaybackUrl_caregiver_returns200() throws Exception {
            when(callRecordingService.generatePlaybackUrl(anyString()))
                    .thenReturn(Map.of("url", "https://s3.example.com/recording.mp4"));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/recording/playback-url")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("GET /{callId}/recording/playback-url as PATIENT non-participant returns 403")
        @WithMockUser(username = "patient@test.com")
        void getRecordingPlaybackUrl_patientNonParticipant_returns403() throws Exception {
            when(callTelemetryService.getTelemetryForCall(anyString())).thenReturn(Collections.emptyList());
            doThrow(new AppException(HttpStatus.FORBIDDEN, "Recording access denied"))
                    .when(callSessionService).requireRecordingAccess(CALL_ID, patientUser);

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/recording/playback-url")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("GET /recordings as ADMIN returns 200 (getAllRecordings called)")
        @WithMockUser(username = "admin@test.com")
        void listRecordings_admin_returns200() throws Exception {
            when(callRecordingService.getAllRecordings())
                    .thenReturn(List.of(Map.of("callId", "call-123")));

            mockMvc.perform(get(BASE_URL + "/recordings")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("GET /recordings as CAREGIVER returns 200 (getRecordingsByUser called)")
        @WithMockUser(username = "caregiver@test.com")
        void listRecordings_caregiver_returns200() throws Exception {
            when(callRecordingService.getRecordingsByUser(anyLong())).thenReturn(List.of());

            mockMvc.perform(get(BASE_URL + "/recordings")
                            .with(csrf()))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        void listRecordings_caregiverCannotFilterAnotherUser() throws Exception {
            mockMvc.perform(get(BASE_URL + "/recordings")
                            .param("userId", "999")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("GET /recordings as PATIENT returns 403")
        @WithMockUser(username = "patient@test.com")
        void listRecordings_patient_returns403() throws Exception {
            mockMvc.perform(get(BASE_URL + "/recordings")
                            .with(csrf()))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("POST /{callId}/recording/cleanup-raw in test profile returns 200")
        @WithMockUser(username = "admin@test.com")
        void cleanupRawRecordingArtifacts_testProfile_returns200() throws Exception {
            when(callRecordingService.cleanupRawArtifactsForCall(anyString()))
                    .thenReturn(Map.of("status", "CLEANED"));

            mockMvc.perform(post(BASE_URL + "/" + CALL_ID + "/recording/cleanup-raw")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("CLEANED"));
        }

        @Test
        @DisplayName("DELETE /recordings in test profile returns 200 (purgeAllRecordings)")
        @WithMockUser(username = "admin@test.com")
        void purgeAllRecordings_testProfile_returns200() throws Exception {
            when(callRecordingService.purgeAllRecordings())
                    .thenReturn(Map.of("deletedDbRows", 5, "deletedS3Objects", 10));

            mockMvc.perform(delete(BASE_URL + "/recordings")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON))
                    .andExpect(status().isOk());
        }

        @Test
        @WithMockUser(username = "caregiver@test.com")
        void purgeAllRecordings_caregiverReturns403EvenInTestProfile() throws Exception {
            mockMvc.perform(delete(BASE_URL + "/recordings")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON))
                    .andExpect(status().isForbidden());
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  TRANSCRIPTION DEBUG TESTS
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Transcription Debug Tests")
    class TranscriptionDebugTests {

        @Test
        @DisplayName("GET /{callId}/transcription/debug as ADMIN returns 200 with requestedByUserId")
        @WithMockUser(username = "admin@test.com")
        void getTranscriptionDebugStatus_admin_returns200WithUserId() throws Exception {
            when(chimeService.getTranscriptionDebugStatus(anyString()))
                    .thenReturn(Map.of("status", "STARTED"));

            mockMvc.perform(get(BASE_URL + "/" + CALL_ID + "/transcription/debug")
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.requestedByUserId").value(3));
        }
    }
}
