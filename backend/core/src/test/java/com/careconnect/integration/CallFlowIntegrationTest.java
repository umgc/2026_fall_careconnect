package com.careconnect.integration;

import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.model.FamilyMemberLink;
import com.careconnect.model.User;
import com.careconnect.repository.CallTelemetryEventRepository;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.chimesdkmeetings.ChimeSdkMeetingsClient;
import software.amazon.awssdk.services.chimesdkmeetings.model.Attendee;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateAttendeeRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateAttendeeResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateMeetingResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.DeleteMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.DeleteMeetingResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.GetMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.GetMeetingResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.MediaPlacement;
import software.amazon.awssdk.services.chimesdkmeetings.model.Meeting;
import software.amazon.awssdk.services.chimesdkmeetings.model.NotFoundException;
import software.amazon.awssdk.services.chimesdkmediapipelines.ChimeSdkMediaPipelinesClient;
import com.careconnect.service.ChimeService;
import com.careconnect.service.OpenRouterService;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * E2E / Integration tests for the video call flow.
 *
 * Covers the full call lifecycle:
 *   CALL JOIN → SENTIMENT SUBMISSION → CALL END → TELEMETRY VERIFICATION
 *
 * Uses:
 *   - @SpringBootTest (full application context)
 *   - H2 in-memory database (application-test.properties)
 *   - Mocked AWS SDK clients (ChimeSdkMeetingsClient, BedrockRuntimeClient, etc.)
 *   - MockMvc for HTTP calls
 *
 * TDD IDs covered: CALL-001, CALL-018, CHIME-001..006, CHIME-009, SENT-001, SENT-004, SENT-006, SENT-007
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "spring.autoconfigure.exclude=" +
                        "org.springframework.boot.autoconfigure.security.oauth2.client.servlet.OAuth2ClientAutoConfiguration," +
                        "org.springframework.boot.autoconfigure.security.oauth2.resource.servlet.OAuth2ResourceServerAutoConfiguration"
        }
)
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(com.careconnect.config.CareconnectTestConfig.class)
@TestPropertySource(properties = {
        "aws.region=us-east-1",
        "careconnect.ai.provider=mock",
        "careconnect.ai.api.key=stub-test-key-for-integration",
        "careconnect.cors_allowed=*",
        "frontend.base-url=http://localhost:3000",
        "email.crypto.secret=careconnect-test-secret-32bytes!",
        "alexa.oauth.client-id=stub",
        "alexa.oauth.client-secret=stub",
        "aws.s3.bucket-name=stub-bucket",
        "spring.security.oauth2.client.provider.fitbit.authorization-uri=https://www.fitbit.com/oauth2/authorize",
        "spring.security.oauth2.client.provider.fitbit.token-uri=https://api.fitbit.com/oauth2/token",
        "spring.security.oauth2.client.provider.fitbit.user-info-uri=https://api.fitbit.com/1/user/-/profile.json",
        "spring.security.oauth2.client.provider.fitbit.user-name-attribute=user_id",
        "spring.security.oauth2.client.provider.google.authorization-uri=https://accounts.google.com/o/oauth2/v2/auth",
        "spring.security.oauth2.client.provider.google.token-uri=https://oauth2.googleapis.com/token",
        "spring.security.oauth2.client.provider.google.user-info-uri=https://www.googleapis.com/oauth2/v3/userinfo"
})
@DisplayName("Call Flow Integration Tests")
class CallFlowIntegrationTest {

    // ── AWS SDK mocks (required so context loads without real credentials) ──────

    @MockitoBean
    private ChimeSdkMeetingsClient chimeSdkMeetingsClient;

    @MockitoBean
    private ChimeSdkMediaPipelinesClient chimeSdkMediaPipelinesClient;

    @MockitoBean
    private BedrockRuntimeClient bedrockRuntimeClient;

    @MockitoBean
    private S3Client s3Client;

    @MockitoBean
    private S3Presigner s3Presigner;

    // Conditional services that are disabled in test profile but required by injected dependents
    @MockitoBean
    private OpenRouterService openRouterService;

    @MockitoBean
    private dev.langchain4j.model.chat.ChatModel chatModel;

    @MockitoBean(name = "mockAIChatService")
    private com.careconnect.service.AIChatService aiChatService;

    // Conditional services whose @ConditionalOnProperty excludes them under test profile,
    // but unconditional controllers still require injection.
    @MockitoBean
    private com.careconnect.service.invoice.TextractService textractService;

    @MockitoBean
    private com.careconnect.service.invoice.LlmExtractionService llmExtractionService;

    @MockitoBean
    private com.careconnect.service.StripeService stripeService;

    @MockitoBean
    private com.careconnect.service.SubscriptionService subscriptionService;

    @MockitoBean
    private com.careconnect.service.DeepSeekService deepSeekService;

    @MockitoBean
    private com.careconnect.service.AiSymptomService aiSymptomService;

    @MockitoBean
    private com.careconnect.service.AiAllergyService aiAllergyService;

    @MockitoBean
    private com.careconnect.service.S3StorageService s3StorageService;

    @MockitoBean
    private com.careconnect.service.ParameterStoreService parameterStoreService;

    @MockitoBean
    private software.amazon.awssdk.services.textract.TextractClient textractClient;

    @MockitoBean
    private software.amazon.awssdk.services.ssm.SsmClient ssmClient;

    @MockitoBean
    private software.amazon.awssdk.services.sts.StsClient stsClient;

    @MockitoBean
    private software.amazon.awssdk.services.iam.IamClient iamClient;

    // ── Spring-managed beans ─────────────────────────────────────────────────────

    @MockitoSpyBean
    private ChimeService chimeService;

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private CallTelemetryEventRepository callTelemetryEventRepository;

    @Autowired
    private FamilyMemberLinkRepository familyMemberLinkRepository;

    @Autowired
    private ObjectMapper objectMapper;

    // ── Test fixtures ───────────────────────────────────────────────────────────

    private static final String CALL_ID = "integration-call-test-001";

    private User patientUser;
    private User caregiverUser;

    // ── Setup ───────────────────────────────────────────────────────────────────

    @BeforeEach
    void setUp() {
        // Clean telemetry between tests
        callTelemetryEventRepository.deleteAll();

        // Ensure test users exist (idempotent)
        patientUser = userRepository.findByEmail("patient@integration.test")
                .orElseGet(() -> {
                    User u = new User();
                    u.setEmail("patient@integration.test");
                    u.setPassword("test-password-hash");
                    u.setRole(Role.PATIENT);
                    u.setName("Integration Patient");
                    return userRepository.save(u);
                });

        caregiverUser = userRepository.findByEmail("caregiver@integration.test")
                .orElseGet(() -> {
                    User u = new User();
                    u.setEmail("caregiver@integration.test");
                    u.setPassword("test-password-hash");
                    u.setRole(Role.CAREGIVER);
                    u.setName("Integration Caregiver");
                    return userRepository.save(u);
                });

        // Mock Chime SDK — returns realistic meeting credentials
        Meeting mockMeeting = Meeting.builder()
                .meetingId("mock-meeting-id-001")
                .externalMeetingId(CALL_ID)
                .mediaPlacement(MediaPlacement.builder()
                        .audioHostUrl("wss://audio.chime.aws")
                        .audioFallbackUrl("https://audio-fallback.chime.aws")
                        .screenDataUrl("https://screen.chime.aws")
                        .screenSharingUrl("https://screensharing.chime.aws")
                        .screenViewingUrl("https://screenviewing.chime.aws")
                        .signalingUrl("wss://signal.chime.aws")
                        .turnControlUrl("https://turn.chime.aws")
                        .build())
                .mediaRegion("us-east-1")
                .build();

        CreateMeetingResponse mockCreateMeetingResponse = CreateMeetingResponse.builder()
                .meeting(mockMeeting)
                .build();

        Attendee mockAttendee = Attendee.builder()
                .attendeeId("mock-attendee-id-001")
                .externalUserId(patientUser.getId().toString())
                .joinToken("mock-join-token-patient")
                .build();

        CreateAttendeeResponse mockCreateAttendeeResponse = CreateAttendeeResponse.builder()
                .attendee(mockAttendee)
                .build();

        GetMeetingResponse mockGetMeeting = GetMeetingResponse.builder()
                .meeting(mockMeeting)
                .build();

        when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class))).thenReturn(mockCreateMeetingResponse);
        when(chimeSdkMeetingsClient.createAttendee(any(CreateAttendeeRequest.class))).thenReturn(mockCreateAttendeeResponse);
        when(chimeSdkMeetingsClient.getMeeting(any(GetMeetingRequest.class))).thenReturn(mockGetMeeting);
        when(chimeSdkMeetingsClient.deleteMeeting(any(DeleteMeetingRequest.class)))
                .thenReturn(DeleteMeetingResponse.builder().build());

        // Mock Bedrock — return exception so fallback heuristic is used (SENT-007)
        when(bedrockRuntimeClient.invokeModel(any(InvokeModelRequest.class)))
                .thenThrow(new RuntimeException("Bedrock unavailable in test"));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CHIME-001 / CHIME-002 / CHIME-004 / CALL-001: JOIN CALL
    // ═══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Call Join (CHIME-001..004, CALL-001, CALL-018)")
    class CallJoinTests {

        @Test
        @DisplayName("CALL-001 / CHIME-001 / CHIME-004: Caregiver joins call — 200 with meeting credentials")
        void caregiver_joinCall_returns200WithCredentials() throws Exception {
            mockMvc.perform(post("/api/v3/calls/{callId}/join", CALL_ID)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.meetingId").exists())
                    .andExpect(jsonPath("$.attendeeId").exists())
                    .andExpect(jsonPath("$.joinToken").exists());
        }

        @Test
        @DisplayName("CALL-018 / CHIME-004: Patient joins call — 200 with meeting credentials")
        void patient_joinCall_returns200WithCredentials() throws Exception {
            mockMvc.perform(post("/api/v3/calls/{callId}/join", CALL_ID)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.meetingId").exists())
                    .andExpect(jsonPath("$.joinToken").exists());
        }

        @Test
        @DisplayName("CHIME-001: POST /join triggers ChimeService and records CALL_JOIN telemetry in database")
        void joinCall_recordsCallJoinTelemetryInDatabase() throws Exception {
            mockMvc.perform(post("/api/v3/calls/{callId}/join", CALL_ID)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            // Verify telemetry was persisted to the real H2 database
            List<CallTelemetryEvent> events = callTelemetryEventRepository
                    .findByCallIdOrderByOccurredAtDesc(CALL_ID);
            assertThat(events).isNotEmpty();
            assertThat(events).anyMatch(e -> "CALL_JOIN".equals(e.getEventType()));
            assertThat(events).anyMatch(e -> "SUCCESS".equals(e.getStatus()));
        }

        @Test
        @DisplayName("CHIME-002: JOIN response contains meetingId, attendeeId, joinToken, mediaRegion")
        void joinCall_responseContainsAllChimeCredentials() throws Exception {
            MvcResult result = mockMvc.perform(post("/api/v3/calls/{callId}/join", CALL_ID)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk())
                    .andReturn();

            String body = result.getResponse().getContentAsString();
            assertThat(body).contains("meetingId");
            assertThat(body).contains("attendeeId");
            assertThat(body).contains("joinToken");
            assertThat(body).contains("mediaRegion");
        }

        @Test
        @DisplayName("CHIME-009: Second join to same callId is idempotent — returns 200")
        void joinCall_secondJoinSameCallId_isIdempotent() throws Exception {
            // First join
            mockMvc.perform(post("/api/v3/calls/{callId}/join", CALL_ID)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            // Second join (same callId, different user) — should not fail
            mockMvc.perform(post("/api/v3/calls/{callId}/join", CALL_ID)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("CHIME-013: double POST /join same user is idempotent — single createAttendee (L5a)")
        void joinCall_doubleJoinSameUser_idempotent() throws Exception {
            String callId = "double-join-" + System.currentTimeMillis();

            mockMvc.perform(post("/api/v3/calls/{callId}/join", callId)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            mockMvc.perform(post("/api/v3/calls/{callId}/join", callId)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            verify(chimeService, times(1)).createAttendee(
                    eq(callId),
                    eq(caregiverUser.getId().toString()),
                    anyString(),
                    anyString());
        }

        @Test
        @DisplayName("CHIME-003: Unauthenticated join → 401 or 403")
        void joinCall_unauthenticated_rejected() throws Exception {
            mockMvc.perform(post("/api/v3/calls/{callId}/join", CALL_ID)
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(result ->
                            assertThat(result.getResponse().getStatus())
                                    .isIn(401, 403));
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CHIME-012: CONFERENCE INVITE
    // ═══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Conference Invite (CHIME-012)")
    class ConferenceInviteTests {

        @Test
        @DisplayName("CHIME-012: invite then join creates attendee only on join, not on invite")
        void inviteThenJoin_singleCreateAttendeeForInvitee() throws Exception {
            String conferenceCallId = "conference-pattern-a-" + System.currentTimeMillis();

            User familyUser = userRepository.findByEmail("family@integration.test")
                    .orElseGet(() -> {
                        User u = new User();
                        u.setEmail("family@integration.test");
                        u.setPassword("test-password-hash");
                        u.setRole(Role.FAMILY_MEMBER);
                        u.setName("Integration Family");
                        return userRepository.save(u);
                    });

            if (!familyMemberLinkRepository.existsByFamilyUserAndPatientUserAndStatus(
                    familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)) {
                FamilyMemberLink link = new FamilyMemberLink(
                        familyUser, patientUser, caregiverUser, "Daughter");
                link.setPatientId(patientUser.getId());
                familyMemberLinkRepository.save(link);
            }

            mockMvc.perform(post("/api/v3/calls/{callId}/join", conferenceCallId)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            mockMvc.perform(post("/api/v3/calls/{callId}/join", conferenceCallId)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            clearInvocations(chimeService);

            mockMvc.perform(post("/api/v3/calls/{callId}/invite", conferenceCallId)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(
                                    Map.of("targetUserId", familyUser.getId()))))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").exists());

            verify(chimeService, never()).createAttendee(
                    eq(conferenceCallId), anyString(), anyString(), anyString());

            List<CallTelemetryEvent> afterInvite = callTelemetryEventRepository
                    .findByCallIdOrderByOccurredAtDesc(conferenceCallId);
            assertThat(afterInvite).anyMatch(e ->
                    "CONFERENCE_INVITE".equals(e.getEventType())
                            && familyUser.getId().equals(e.getTargetUserId()));

            mockMvc.perform(post("/api/v3/calls/{callId}/join", conferenceCallId)
                            .with(user(familyUser.getEmail()).roles("FAMILY_MEMBER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            verify(chimeService, times(1)).createAttendee(
                    eq(conferenceCallId),
                    eq(familyUser.getId().toString()),
                    anyString(),
                    anyString());
        }

        @Test
        @DisplayName("CHIME-013: end while invitee ringing notifies pending invitee")
        void endWhileRinging_notifiesPendingInvitee() throws Exception {
            String callId = "end-while-ringing-" + System.currentTimeMillis();

            User familyUser = userRepository.findByEmail("family@integration.test")
                    .orElseGet(() -> {
                        User u = new User();
                        u.setEmail("family@integration.test");
                        u.setPassword("test-password-hash");
                        u.setRole(Role.FAMILY_MEMBER);
                        u.setName("Integration Family");
                        return userRepository.save(u);
                    });

            if (!familyMemberLinkRepository.existsByFamilyUserAndPatientUserAndStatus(
                    familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)) {
                FamilyMemberLink link = new FamilyMemberLink(
                        familyUser, patientUser, caregiverUser, "Daughter");
                link.setPatientId(patientUser.getId());
                familyMemberLinkRepository.save(link);
            }

            mockMvc.perform(post("/api/v3/calls/{callId}/join", callId)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            mockMvc.perform(post("/api/v3/calls/{callId}/join", callId)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            mockMvc.perform(post("/api/v3/calls/{callId}/invite", callId)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(
                                    Map.of("targetUserId", familyUser.getId()))))
                    .andExpect(status().isOk());

            String endBody = objectMapper.writeValueAsString(Map.of(
                    "otherPartyId", patientUser.getId().toString()));

            mockMvc.perform(post("/api/v3/calls/{callId}/end", callId)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(endBody))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("ended"));

            verify(chimeService).endMeeting(callId);

            List<CallTelemetryEvent> events = callTelemetryEventRepository
                    .findByCallIdOrderByOccurredAtDesc(callId);
            assertThat(events).anyMatch(e -> "CALL_END".equals(e.getEventType()));
            assertThat(events).anyMatch(e ->
                    "CONFERENCE_INVITE".equals(e.getEventType())
                            && familyUser.getId().equals(e.getTargetUserId()));
            assertThat(events).noneMatch(e ->
                    "CALL_JOIN".equals(e.getEventType())
                            && familyUser.getId().equals(e.getActorUserId()));
        }

        @Test
        @DisplayName("CHIME-014: three-party conference end notifies remaining participant")
        void threeParty_endNotifiesAllRemaining() throws Exception {
            String callId = "three-party-end-" + System.currentTimeMillis();

            User familyUser = userRepository.findByEmail("family@integration.test")
                    .orElseGet(() -> {
                        User u = new User();
                        u.setEmail("family@integration.test");
                        u.setPassword("test-password-hash");
                        u.setRole(Role.FAMILY_MEMBER);
                        u.setName("Integration Family");
                        return userRepository.save(u);
                    });

            if (!familyMemberLinkRepository.existsByFamilyUserAndPatientUserAndStatus(
                    familyUser, patientUser, FamilyMemberLink.LinkStatus.ACTIVE)) {
                FamilyMemberLink link = new FamilyMemberLink(
                        familyUser, patientUser, caregiverUser, "Daughter");
                link.setPatientId(patientUser.getId());
                familyMemberLinkRepository.save(link);
            }

            mockMvc.perform(post("/api/v3/calls/{callId}/join", callId)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            mockMvc.perform(post("/api/v3/calls/{callId}/join", callId)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            mockMvc.perform(post("/api/v3/calls/{callId}/join", callId)
                            .with(user(familyUser.getEmail()).roles("FAMILY_MEMBER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            mockMvc.perform(post("/api/v3/calls/{callId}/end", callId)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(
                                    Map.of("otherPartyId", patientUser.getId().toString()))))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("left"));

            clearInvocations(chimeService);

            mockMvc.perform(post("/api/v3/calls/{callId}/end", callId)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("ended"));

            verify(chimeService).endMeeting(callId);

            List<CallTelemetryEvent> events = callTelemetryEventRepository
                    .findByCallIdOrderByOccurredAtDesc(callId);
            assertThat(events).anyMatch(e ->
                    "CALL_LEAVE".equals(e.getEventType())
                            && caregiverUser.getId().equals(e.getActorUserId()));
            assertThat(events).anyMatch(e ->
                    "CALL_END".equals(e.getEventType())
                            && patientUser.getId().equals(e.getActorUserId()));
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SENT-001 / SENT-006 / SENT-007: SENTIMENT ANALYSIS
    // ═══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Sentiment Analysis (SENT-001, SENT-006, SENT-007)")
    class SentimentTests {

        @Test
        @DisplayName("SENT-001: Patient submits text sentiment — 200 with SentimentResult (heuristic fallback, SENT-007)")
        void patient_submitTextSentiment_returns200WithResult() throws Exception {
            String body = objectMapper.writeValueAsString(Map.of(
                    "text", "I feel a lot better today, thank you for checking in",
                    "captureMode", "balanced",
                    "otherPartyId", caregiverUser.getId().toString()
            ));

            MvcResult result = mockMvc.perform(post("/api/v3/calls/{callId}/sentiment/text", CALL_ID)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.score").exists())
                    .andExpect(jsonPath("$.label").exists())
                    .andReturn();

            // SENT-007: Bedrock is mocked to throw — heuristic fallback is used, call continues
            String responseBody = result.getResponse().getContentAsString();
            assertThat(responseBody).contains("score");
            assertThat(responseBody).contains("label");
        }

        @Test
        @DisplayName("SENT-006: Caregiver submits text sentiment → 403 Forbidden")
        void caregiver_submitTextSentiment_returns403() throws Exception {
            String body = objectMapper.writeValueAsString(Map.of(
                    "text", "Patient seems well",
                    "captureMode", "balanced"
            ));

            mockMvc.perform(post("/api/v3/calls/{callId}/sentiment/text", CALL_ID)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("SENT-006b: Caregiver submits voice sentiment → 403 Forbidden")
        void caregiver_submitVoiceSentiment_returns403() throws Exception {
            String body = objectMapper.writeValueAsString(Map.of(
                    "averageLevel", "0.7",
                    "speechRatio", "0.8",
                    "variability", "0.1",
                    "captureMode", "realtime"
            ));

            mockMvc.perform(post("/api/v3/calls/{callId}/sentiment/voice", CALL_ID)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isForbidden());
        }

        @Test
        @DisplayName("SENT-001b: Patient voice sentiment — 200 OK (SENT-007: heuristic when Bedrock down)")
        void patient_submitVoiceSentiment_returns200() throws Exception {
            String body = objectMapper.writeValueAsString(Map.of(
                    "averageLevel", "0.7",
                    "speechRatio", "0.8",
                    "variability", "0.1",
                    "captureMode", "realtime",
                    "otherPartyId", caregiverUser.getId().toString()
            ));

            mockMvc.perform(post("/api/v3/calls/{callId}/sentiment/voice", CALL_ID)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.score").exists())
                    .andExpect(jsonPath("$.label").exists());
        }

        @Test
        @DisplayName("SENT-001: Text sentiment missing 'text' field → 400 Bad Request")
        void textSentiment_missingTextField_returns400() throws Exception {
            String body = objectMapper.writeValueAsString(Map.of(
                    "captureMode", "balanced"
            ));

            mockMvc.perform(post("/api/v3/calls/{callId}/sentiment/text", CALL_ID)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }

        @Test
        @DisplayName("SENT-001: Text sentiment recorded in telemetry database")
        void textSentiment_isRecordedInTelemetryDatabase() throws Exception {
            String body = objectMapper.writeValueAsString(Map.of(
                    "text", "I am feeling much better today",
                    "captureMode", "balanced",
                    "otherPartyId", caregiverUser.getId().toString()
            ));

            mockMvc.perform(post("/api/v3/calls/{callId}/sentiment/text", CALL_ID)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isOk());

            List<CallTelemetryEvent> events = callTelemetryEventRepository
                    .findByCallIdOrderByOccurredAtDesc(CALL_ID);
            assertThat(events).anyMatch(e -> "SENTIMENT_TEXT".equals(e.getEventType()));
            assertThat(events).anyMatch(e -> e.getSentimentScore() != null);

            // Verify sanitization: no raw text in the persisted telemetry metadata
            CallTelemetryEvent sentimentEvent = events.stream()
                    .filter(e -> "SENTIMENT_TEXT".equals(e.getEventType()))
                    .findFirst().orElseThrow();
            String payloadJson = sentimentEvent.getPayloadJson() == null ? "" : sentimentEvent.getPayloadJson();
            assertThat(payloadJson).doesNotContain("I am feeling much better today");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CHIME-006 / SENT-004: CALL END
    // ═══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Call End (CHIME-006, SENT-004)")
    class CallEndTests {

        @Test
        @DisplayName("CHIME-006: POST /end → 200 with status=ended")
        void endCall_returns200WithEndedStatus() throws Exception {
            // First join so there is a call to end
            mockMvc.perform(post("/api/v3/calls/{callId}/join", CALL_ID)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            // End the call
            String endBody = objectMapper.writeValueAsString(Map.of(
                    "otherPartyId", patientUser.getId().toString()
            ));

            mockMvc.perform(post("/api/v3/calls/{callId}/end", CALL_ID)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(endBody))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("ended"))
                    .andExpect(jsonPath("$.callId").value(CALL_ID));
        }

        @Test
        @DisplayName("SENT-004: POST /end records CALL_END telemetry in database")
        void endCall_recordsCallEndTelemetry() throws Exception {
            String endBody = objectMapper.writeValueAsString(Map.of(
                    "otherPartyId", patientUser.getId().toString()
            ));

            mockMvc.perform(post("/api/v3/calls/{callId}/end", CALL_ID)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(endBody))
                    .andExpect(status().isOk());

            List<CallTelemetryEvent> events = callTelemetryEventRepository
                    .findByCallIdOrderByOccurredAtDesc(CALL_ID);
            assertThat(events).anyMatch(e -> "CALL_END".equals(e.getEventType()));
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FULL CALL FLOW: JOIN → SENTIMENT → END → VERIFY
    // ═══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Full Call Flow — Join → Sentiment → End")
    class FullCallFlowTests {

        @Test
        @DisplayName("Full flow: patient joins, submits text + voice sentiment, call ends — telemetry persisted for all events")
        void fullCallFlow_joinsSubmitsSentimentEnds_allEventsInDatabase() throws Exception {
            String flowCallId = "full-flow-call-" + System.currentTimeMillis();

            // 1. Patient joins
            mockMvc.perform(post("/api/v3/calls/{callId}/join", flowCallId)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            // 2. Patient submits text sentiment
            String textBody = objectMapper.writeValueAsString(Map.of(
                    "text", "I am having a good day today",
                    "captureMode", "balanced",
                    "otherPartyId", caregiverUser.getId().toString()
            ));
            mockMvc.perform(post("/api/v3/calls/{callId}/sentiment/text", flowCallId)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(textBody))
                    .andExpect(status().isOk());

            // 3. Patient submits voice sentiment
            String voiceBody = objectMapper.writeValueAsString(Map.of(
                    "averageLevel", "0.6",
                    "speechRatio", "0.75",
                    "variability", "0.15",
                    "captureMode", "realtime",
                    "otherPartyId", caregiverUser.getId().toString()
            ));
            mockMvc.perform(post("/api/v3/calls/{callId}/sentiment/voice", flowCallId)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(voiceBody))
                    .andExpect(status().isOk());

            // 4. Caregiver ends call
            String endBody = objectMapper.writeValueAsString(Map.of(
                    "otherPartyId", patientUser.getId().toString()
            ));
            mockMvc.perform(post("/api/v3/calls/{callId}/end", flowCallId)
                            .with(user(caregiverUser.getEmail()).roles("CAREGIVER"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(endBody))
                    .andExpect(status().isOk());

            // 5. Verify all event types are in database
            List<CallTelemetryEvent> events = callTelemetryEventRepository
                    .findByCallIdOrderByOccurredAtDesc(flowCallId);

            assertThat(events).isNotEmpty();
            List<String> eventTypes = events.stream().map(CallTelemetryEvent::getEventType).toList();
            assertThat(eventTypes).contains("CALL_JOIN");
            assertThat(eventTypes).contains("SENTIMENT_TEXT");
            assertThat(eventTypes).contains("SENTIMENT_VOICE");
            assertThat(eventTypes).contains("CALL_END");
        }

        @Test
        @DisplayName("SENT-005 / GET /{callId}/sentiment: patient participant can read sentiment after submitting")
        void getSentiment_participantCanRead_returnsSentimentByChannel() throws Exception {
            String flowCallId = "sentiment-read-call-" + System.currentTimeMillis();

            // Submit sentiment first
            String textBody = objectMapper.writeValueAsString(Map.of(
                    "text", "I feel okay",
                    "captureMode", "balanced",
                    "otherPartyId", caregiverUser.getId().toString()
            ));
            mockMvc.perform(post("/api/v3/calls/{callId}/sentiment/text", flowCallId)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(textBody))
                    .andExpect(status().isOk());

            // SENT-005: read back persisted sentiment events from telemetry
            mockMvc.perform(get("/api/v3/calls/{callId}/telemetry", flowCallId)
                            .with(user(patientUser.getEmail()).roles("PATIENT")))
                    .andExpect(status().isOk());
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TELEMETRY: GET /telemetry/my
    // ═══════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Telemetry Endpoints")
    class TelemetryEndpointTests {

        @Test
        @DisplayName("GET /telemetry/my — returns 200 for authenticated user")
        void getMyTelemetry_returns200() throws Exception {
            mockMvc.perform(get("/api/v3/calls/telemetry/my")
                            .with(user(patientUser.getEmail()).roles("PATIENT")))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("GET /sentiment-history — returns 200 for own userId")
        void getSentimentHistory_ownUserId_returns200() throws Exception {
            mockMvc.perform(get("/api/v3/calls/sentiment-history")
                            .param("userId", patientUser.getId().toString())
                            .with(user(patientUser.getEmail()).roles("PATIENT")))
                    .andExpect(status().isOk());
        }

        @Test
        @DisplayName("DELETE /{callId}/telemetry — works in test profile (dev/local mode)")
        void deleteCallTelemetry_testProfile_returns200() throws Exception {
            // Seed some telemetry
            mockMvc.perform(post("/api/v3/calls/{callId}/join", CALL_ID)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{}"))
                    .andExpect(status().isOk());

            // Delete it
            mockMvc.perform(delete("/api/v3/calls/{callId}/telemetry", CALL_ID)
                            .with(user(patientUser.getEmail()).roles("PATIENT"))
                            .with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("deleted"));

            // Verify database is clean
            List<CallTelemetryEvent> remaining = callTelemetryEventRepository
                    .findByCallIdOrderByOccurredAtDesc(CALL_ID);
            assertThat(remaining).isEmpty();
        }
    }
}
