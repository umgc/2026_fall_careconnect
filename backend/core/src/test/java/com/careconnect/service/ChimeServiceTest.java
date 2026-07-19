package com.careconnect.service;

import com.careconnect.repository.CallSessionRepository;
import com.careconnect.repository.CallParticipantRepository;
import com.careconnect.model.CallParticipant;
import com.careconnect.model.CallSession;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.ArgumentCaptor;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import software.amazon.awssdk.services.chimesdkmeetings.ChimeSdkMeetingsClient;
import software.amazon.awssdk.services.chimesdkmeetings.model.Attendee;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateAttendeeRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateAttendeeResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateMeetingResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.DeleteMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.DeleteMeetingResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.GetMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.GetMeetingResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.ListAttendeesRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.ListAttendeesResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.MediaPlacement;
import software.amazon.awssdk.services.chimesdkmeetings.model.Meeting;
import software.amazon.awssdk.services.chimesdkmeetings.model.StartMeetingTranscriptionRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.StartMeetingTranscriptionResponse;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for ChimeService covering local-mode and AWS-mode paths.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("ChimeService Tests")
class ChimeServiceTest {

    @Mock
    private ChimeSdkMeetingsClient chimeSdkMeetingsClient;
    @Mock
    private CallSessionRepository callSessionRepository;

    private static final String CALL_ID = "call-chime-001";
    private static final String USER_ID = "42";
    private static final String MEETING_ID = "meeting-abc-123";

    // Helper to build a full Meeting with MediaPlacement
    private Meeting buildMeeting(String meetingId) {
        MediaPlacement placement = MediaPlacement.builder()
                .audioHostUrl("wss://audio.example.com")
                .audioFallbackUrl("wss://audio-fallback.example.com")
                .screenDataUrl("wss://screen-data.example.com")
                .screenSharingUrl("wss://screen-sharing.example.com")
                .screenViewingUrl("wss://screen-viewing.example.com")
                .signalingUrl("wss://signaling.example.com")
                .turnControlUrl("https://turn.example.com")
                .eventIngestionUrl("https://events.example.com")
                .build();
        return Meeting.builder()
                .meetingId(meetingId)
                .externalMeetingId(CALL_ID)
                .mediaRegion("us-east-1")
                .mediaPlacement(placement)
                .build();
    }

    private Attendee buildAttendee() {
        return Attendee.builder()
                .attendeeId("attendee-xyz")
                .externalUserId(USER_ID)
                .joinToken("join-token-abc")
                .build();
    }

    // ══════════════════════════════════════════════════════════════════
    //  LOCAL / AWS-DISABLED MODE  (awsEnabled=false)
    // ══════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Local / AWS-disabled mode")
    class LocalModeTests {

        private ChimeService service;

        @BeforeEach
        void setUp() {
            // awsEnabled=false → local mock meetings only
            service = new ChimeService(
                    chimeSdkMeetingsClient,
                    false,      // awsEnabled
                    false,      // transcriptionEnabled
                    "en-US",
                    "us-east-1"
            );
        }

        @Test
        @DisplayName("createMeeting returns local mock meeting")
        void createMeeting_localMode_returnsMockMeeting() {
            Map<String, Object> result = service.createMeeting(CALL_ID);

            assertThat(result).containsKey("meetingId");
            assertThat(result.get("meetingId").toString()).startsWith("local-");
            assertThat(result.get("externalMeetingId")).isEqualTo(CALL_ID);
            verify(chimeSdkMeetingsClient, never()).createMeeting(any(CreateMeetingRequest.class));
        }

        @Test
        @DisplayName("createMeeting is idempotent for same callId")
        void createMeeting_localMode_idempotent() {
            Map<String, Object> first = service.createMeeting(CALL_ID);
            Map<String, Object> second = service.createMeeting(CALL_ID);

            assertThat(first.get("meetingId")).isEqualTo(second.get("meetingId"));
        }

        @Test
        @DisplayName("joinMeeting creates meeting and returns attendee credentials")
        void joinMeeting_localMode_returnsCredentials() {
            Map<String, Object> result = service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "John Doe");

            assertThat(result).containsKeys(
                    "meetingId", "attendeeId", "externalUserId", "joinToken");
            assertThat(String.valueOf(result.get("externalUserId")))
                    .doesNotContain("John")
                    .doesNotContain("CAREGIVER")
                    .doesNotContain(USER_ID);
        }

        @Test
        @DisplayName("joinMeeting second call returns cached credentials (L5a)")
        void joinMeeting_localMode_secondCallReturnsCachedCreds() {
            Map<String, Object> first = service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "John Doe");
            Map<String, Object> second = service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "John Doe");

            assertThat(second.get("attendeeId")).isEqualTo(first.get("attendeeId"));
            assertThat(second.get("joinToken")).isEqualTo(first.get("joinToken"));
        }

        @Test
        @DisplayName("joinMeeting after endMeeting issues new attendee credentials")
        void joinMeeting_localMode_afterEndMeetingNewCreds() {
            Map<String, Object> first = service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "John Doe");
            service.endMeeting(CALL_ID);
            Map<String, Object> second = service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "John Doe");

            assertThat(second.get("attendeeId")).isNotEqualTo(first.get("attendeeId"));
        }

        @Test
        @DisplayName("endMeeting removes active meeting")
        void endMeeting_localMode_removesMeeting() {
            service.createMeeting(CALL_ID);
            assertThat(service.isMeetingActive(CALL_ID)).isTrue();

            service.endMeeting(CALL_ID);

            assertThat(service.isMeetingActive(CALL_ID)).isFalse();
        }

        @Test
        @DisplayName("endMeeting on unknown callId is a no-op")
        void endMeeting_unknownCallId_noOp() {
            service.endMeeting("nonexistent-call");
            // no exception expected
        }

        @Test
        @DisplayName("isMeetingActive returns false before meeting created")
        void isMeetingActive_noMeeting_returnsFalse() {
            assertThat(service.isMeetingActive(CALL_ID)).isFalse();
        }

        @Test
        @DisplayName("getMeetingId returns null before meeting created")
        void getMeetingId_noMeeting_returnsNull() {
            assertThat(service.getMeetingId(CALL_ID)).isNull();
        }

        @Test
        @DisplayName("getMeetingId returns meetingId after meeting created")
        void getMeetingId_afterCreate_returnsMeetingId() {
            service.createMeeting(CALL_ID);
            assertThat(service.getMeetingId(CALL_ID)).isNotNull();
        }

        @Test
        @DisplayName("getTranscriptionDebugStatus returns structured map")
        void getTranscriptionDebugStatus_noMeeting_returnsMap() {
            Map<String, Object> status = service.getTranscriptionDebugStatus(CALL_ID);

            assertThat(status).containsKey("callId");
            assertThat(status).containsKey("meetingActive");
            assertThat(status).containsKey("awsEnabled");
            assertThat(status.get("callId")).isEqualTo(CALL_ID);
            assertThat(status.get("awsEnabled")).isEqualTo(false);
            assertThat(status.get("meetingActive")).isEqualTo(false);
        }

        @Test
        @DisplayName("getTranscriptionDebugStatus with active meeting includes meetingId")
        void getTranscriptionDebugStatus_activeMeeting_includesMeetingId() {
            service.createMeeting(CALL_ID);
            Map<String, Object> status = service.getTranscriptionDebugStatus(CALL_ID);

            assertThat(status.get("meetingActive")).isEqualTo(true);
            assertThat(status.get("meetingId")).isNotNull();
        }
    }

    // ══════════════════════════════════════════════════════════════════
    //  AWS-ENABLED MODE (awsEnabled=true, client mocked)
    // ══════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("AWS-enabled mode")
    class AwsModeTests {

        private ChimeService service;

        @BeforeEach
        void setUp() {
            service = new ChimeService(
                    chimeSdkMeetingsClient,
                    true,       // awsEnabled
                    false,      // transcriptionEnabled=false (skip transcription stub)
                    "en-US",
                    "us-east-1"
            );
        }

        @Test
        @DisplayName("createMeeting calls AWS and returns meeting data")
        void createMeeting_awsMode_callsChimeAndReturnsData() {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());

            Map<String, Object> result = service.createMeeting(CALL_ID);

            assertThat(result.get("meetingId")).isEqualTo(MEETING_ID);
            verify(chimeSdkMeetingsClient).createMeeting(any(CreateMeetingRequest.class));
        }

        @Test
        @DisplayName("createMeeting is idempotent for same callId")
        void createMeeting_awsMode_idempotent() {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());

            service.createMeeting(CALL_ID);
            Map<String, Object> second = service.createMeeting(CALL_ID);

            // createMeeting called only once — second returns cached
            verify(chimeSdkMeetingsClient).createMeeting(any(CreateMeetingRequest.class));
            assertThat(second.get("meetingId")).isEqualTo(MEETING_ID);
        }

        @Test
        @DisplayName("independent nodes use the same AWS meeting idempotency token")
        void createMeeting_acrossNodes_usesDeterministicToken() {
            Meeting meeting = buildMeeting(MEETING_ID);
            CallSession session = new CallSession();
            session.setCallId(CALL_ID);
            session.setStatus(CallSessionService.SESSION_CREATED);
            when(callSessionRepository.findByCallId(CALL_ID))
                    .thenReturn(Optional.of(session));
            when(callSessionRepository.persistMeetingIdIfAbsent(
                    any(), any(), any(), any())).thenReturn(1);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());
            ChimeService nodeOne = new ChimeService(
                    chimeSdkMeetingsClient, callSessionRepository,
                    true, false, "en-US", "us-east-1");
            ChimeService nodeTwo = new ChimeService(
                    chimeSdkMeetingsClient, callSessionRepository,
                    true, false, "en-US", "us-east-1");

            nodeOne.createMeeting(CALL_ID);
            nodeTwo.createMeeting(CALL_ID);

            ArgumentCaptor<CreateMeetingRequest> requests =
                    ArgumentCaptor.forClass(CreateMeetingRequest.class);
            verify(chimeSdkMeetingsClient, times(2)).createMeeting(requests.capture());
            assertThat(requests.getAllValues().get(0).clientRequestToken())
                    .isEqualTo(requests.getAllValues().get(1).clientRequestToken());
        }

        @Test
        @DisplayName("createMeeting throws when AWS call fails")
        void createMeeting_awsError_throwsRuntimeException() {
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenThrow(new RuntimeException("Chime quota exceeded"));

            assertThatThrownBy(() -> service.createMeeting(CALL_ID))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("Failed to create video call meeting");
        }

        @Test
        @DisplayName("createAttendee returns attendee credentials from AWS")
        void createAttendee_awsMode_returnsCredentials() {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());

            Attendee attendee = buildAttendee();
            when(chimeSdkMeetingsClient.createAttendee(any(CreateAttendeeRequest.class)))
                    .thenReturn(CreateAttendeeResponse.builder().attendee(attendee).build());

            service.createMeeting(CALL_ID); // set up the meeting first
            Map<String, Object> result = service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "John Doe");

            assertThat(result.get("attendeeId")).isEqualTo("attendee-xyz");
            assertThat(result.get("joinToken")).isEqualTo("join-token-abc");
        }

        @Test
        @DisplayName("concurrent same-user joins create one Chime attendee")
        void createAttendee_concurrentSameUser_createsOnce() throws Exception {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());
            when(chimeSdkMeetingsClient.listAttendees(any(ListAttendeesRequest.class)))
                    .thenReturn(ListAttendeesResponse.builder().attendees(List.of()).build());
            when(chimeSdkMeetingsClient.createAttendee(any(CreateAttendeeRequest.class)))
                    .thenReturn(CreateAttendeeResponse.builder().attendee(buildAttendee()).build());
            service.createMeeting(CALL_ID);

            int callers = 8;
            ExecutorService executor = Executors.newFixedThreadPool(callers);
            CountDownLatch ready = new CountDownLatch(callers);
            CountDownLatch start = new CountDownLatch(1);
            List<Future<Map<String, Object>>> futures = new ArrayList<>();
            try {
                for (int i = 0; i < callers; i++) {
                    futures.add(executor.submit(() -> {
                        ready.countDown();
                        start.await();
                        return service.createAttendee(
                                CALL_ID, USER_ID, "CAREGIVER", "John Doe");
                    }));
                }
                ready.await();
                start.countDown();
                for (Future<Map<String, Object>> future : futures) {
                    assertThat(future.get().get("attendeeId")).isEqualTo("attendee-xyz");
                }
            } finally {
                executor.shutdownNow();
            }

            verify(chimeSdkMeetingsClient, times(1))
                    .createAttendee(any(CreateAttendeeRequest.class));
        }

        @Test
        @DisplayName("a second node reuses attendee discovered in Chime")
        void createAttendee_secondNode_reusesExistingAttendee() {
            Meeting meeting = buildMeeting(MEETING_ID);
            CallSession session = new CallSession();
            session.setCallId(CALL_ID);
            session.setChimeMeetingId(MEETING_ID);
            session.setStatus(CallSessionService.SESSION_ACTIVE);
            when(callSessionRepository.findByCallId(CALL_ID))
                    .thenReturn(Optional.of(session));
            when(chimeSdkMeetingsClient.getMeeting(any(GetMeetingRequest.class)))
                    .thenReturn(GetMeetingResponse.builder().meeting(meeting).build());
            ChimeService secondNode = new ChimeService(
                    chimeSdkMeetingsClient, callSessionRepository,
                    true, false, "en-US", "us-east-1");
            final String opaqueId = secondNode.toOpaqueChimeExternalUserId(CALL_ID, USER_ID);
            when(chimeSdkMeetingsClient.listAttendees(any(ListAttendeesRequest.class)))
                    .thenReturn(ListAttendeesResponse.builder()
                            .attendees(Attendee.builder()
                                    .attendeeId("attendee-xyz")
                                    .externalUserId(opaqueId)
                                    .joinToken("join-token-abc")
                                    .build())
                            .build());
            secondNode.createMeeting(CALL_ID);

            Map<String, Object> result = secondNode.createAttendee(
                    CALL_ID, USER_ID, "CAREGIVER", "John Doe");

            assertThat(result.get("attendeeId")).isEqualTo("attendee-xyz");
            assertThat(result.get("externalUserId")).isEqualTo(opaqueId);
            verify(chimeSdkMeetingsClient, never())
                    .createAttendee(any(CreateAttendeeRequest.class));
        }

        @Test
        @DisplayName("Chime externalUserId contains no names, roles, or raw user IDs")
        void createAttendee_externalUserId_isOpaquePseudonym() {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());
            when(chimeSdkMeetingsClient.listAttendees(any(ListAttendeesRequest.class)))
                    .thenReturn(ListAttendeesResponse.builder().attendees(List.of()).build());
            when(chimeSdkMeetingsClient.createAttendee(any(CreateAttendeeRequest.class)))
                    .thenAnswer(invocation -> {
                        CreateAttendeeRequest request = invocation.getArgument(0);
                        return CreateAttendeeResponse.builder()
                                .attendee(Attendee.builder()
                                        .attendeeId("attendee-xyz")
                                        .externalUserId(request.externalUserId())
                                        .joinToken("join-token-abc")
                                        .build())
                                .build();
                    });

            service.createMeeting(CALL_ID);
            Map<String, Object> result = service.createAttendee(
                    CALL_ID, USER_ID, "CAREGIVER", "John Doe");

            String externalUserId = String.valueOf(result.get("externalUserId"));
            assertThat(externalUserId)
                    .doesNotContain("John")
                    .doesNotContain("DOE")
                    .doesNotContain("CAREGIVER")
                    .doesNotContain(USER_ID);
            assertThat(externalUserId)
                    .isEqualTo(service.toOpaqueChimeExternalUserId(CALL_ID, USER_ID));

            ArgumentCaptor<CreateAttendeeRequest> captor =
                    ArgumentCaptor.forClass(CreateAttendeeRequest.class);
            verify(chimeSdkMeetingsClient).createAttendee(captor.capture());
            assertThat(captor.getValue().externalUserId()).isEqualTo(externalUserId);
        }

        @Test
        @DisplayName("AWS list/create run only after the short claim transaction finishes")
        void createAttendee_awsOutsideClaimTransaction() {
            Meeting meeting = buildMeeting(MEETING_ID);
            CallSession session = new CallSession();
            session.setId(9L);
            session.setCallId(CALL_ID);
            session.setStatus(CallSessionService.SESSION_ACTIVE);
            CallParticipant participant = new CallParticipant();
            participant.setCallSessionId(9L);
            participant.setUserId(42L);

            CallParticipantRepository participantRepository =
                    org.mockito.Mockito.mock(CallParticipantRepository.class);
            org.springframework.transaction.PlatformTransactionManager txManager =
                    org.mockito.Mockito.mock(
                            org.springframework.transaction.PlatformTransactionManager.class);
            when(txManager.getTransaction(any()))
                    .thenReturn(new org.springframework.transaction.support.SimpleTransactionStatus());

            java.util.concurrent.atomic.AtomicBoolean insideClaim = new java.util.concurrent.atomic.AtomicBoolean();
            when(callSessionRepository.findByCallId(CALL_ID))
                    .thenReturn(Optional.of(session));
            when(callSessionRepository.findByCallIdForLifecycle(CALL_ID))
                    .thenReturn(Optional.of(session));
            when(participantRepository.findByCallSessionIdAndUserId(9L, 42L))
                    .thenReturn(Optional.of(participant));
            when(participantRepository.claimAttendeeCreation(
                    any(), any(), any(), any(), any(), any()))
                    .thenAnswer(invocation -> {
                        insideClaim.set(true);
                        try {
                            Thread.sleep(20);
                            return 1;
                        } finally {
                            insideClaim.set(false);
                        }
                    });
            when(participantRepository.finalizeAttendeeCreation(
                    any(), any(), any(), any(), any(), any()))
                    .thenReturn(1);
            when(callSessionRepository.persistMeetingIdIfAbsent(any(), any(), any(), any()))
                    .thenReturn(1);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());
            when(chimeSdkMeetingsClient.listAttendees(any(ListAttendeesRequest.class)))
                    .thenAnswer(invocation -> {
                        assertThat(insideClaim.get())
                                .as("listAttendees must not run under claim row lock")
                                .isFalse();
                        return ListAttendeesResponse.builder().attendees(List.of()).build();
                    });
            when(chimeSdkMeetingsClient.createAttendee(any(CreateAttendeeRequest.class)))
                    .thenAnswer(invocation -> {
                        assertThat(insideClaim.get())
                                .as("createAttendee must not run under claim row lock")
                                .isFalse();
                        CreateAttendeeRequest request = invocation.getArgument(0);
                        return CreateAttendeeResponse.builder()
                                .attendee(Attendee.builder()
                                        .attendeeId("attendee-xyz")
                                        .externalUserId(request.externalUserId())
                                        .joinToken("join-token-abc")
                                        .build())
                                .build();
                    });

            ChimeService coordinated = new ChimeService(
                    chimeSdkMeetingsClient,
                    callSessionRepository,
                    participantRepository,
                    txManager,
                    true,
                    false,
                    "en-US",
                    "us-east-1");
            coordinated.createMeeting(CALL_ID);

            Map<String, Object> result = coordinated.createAttendee(
                    CALL_ID, USER_ID, "CAREGIVER", "John Doe");

            assertThat(result.get("attendeeId")).isEqualTo("attendee-xyz");
            verify(participantRepository).claimAttendeeCreation(
                    any(), any(), any(), any(), any(), any());
            verify(participantRepository).finalizeAttendeeCreation(
                    any(), any(), any(), any(), any(), any());
            verify(chimeSdkMeetingsClient).createAttendee(any(CreateAttendeeRequest.class));
        }

        @Test
        @DisplayName("createAttendee throws when no meeting exists")
        void createAttendee_noMeeting_throwsRuntimeException() {
            assertThatThrownBy(() -> service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "John Doe"))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("No active meeting found");
        }

        @Test
        @DisplayName("joinMeeting creates meeting + attendee in one call")
        void joinMeeting_awsMode_createsMeetingAndAttendee() {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());

            Attendee attendee = buildAttendee();
            when(chimeSdkMeetingsClient.createAttendee(any(CreateAttendeeRequest.class)))
                    .thenReturn(CreateAttendeeResponse.builder().attendee(attendee).build());

            Map<String, Object> result = service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "John Doe");

            assertThat(result).containsKey("meetingId");
            assertThat(result).containsKey("attendeeId");
        }

        @Test
        @DisplayName("joinMeeting second call returns cached credentials without second AWS call (L5a)")
        void joinMeeting_awsMode_secondCallReturnsCachedCreds() {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());

            Attendee attendee = buildAttendee();
            when(chimeSdkMeetingsClient.createAttendee(any(CreateAttendeeRequest.class)))
                    .thenReturn(CreateAttendeeResponse.builder().attendee(attendee).build());

            Map<String, Object> first = service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "John Doe");
            Map<String, Object> second = service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "John Doe");

            assertThat(second.get("attendeeId")).isEqualTo(first.get("attendeeId"));
            verify(chimeSdkMeetingsClient, times(1)).createAttendee(any(CreateAttendeeRequest.class));
        }

        @Test
        @DisplayName("joinMeeting after endMeeting calls AWS createAttendee again")
        void joinMeeting_awsMode_afterEndMeetingCreatesNewAttendee() {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());

            Attendee attendee = buildAttendee();
            when(chimeSdkMeetingsClient.createAttendee(any(CreateAttendeeRequest.class)))
                    .thenReturn(CreateAttendeeResponse.builder().attendee(attendee).build());

            service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "John Doe");
            service.endMeeting(CALL_ID);
            service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "John Doe");

            verify(chimeSdkMeetingsClient, times(2)).createAttendee(any(CreateAttendeeRequest.class));
        }

        @Test
        @DisplayName("endMeeting calls AWS deleteMeeting")
        void endMeeting_awsMode_callsDeleteMeeting() {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());
            when(chimeSdkMeetingsClient.deleteMeeting(any(DeleteMeetingRequest.class)))
                    .thenReturn(DeleteMeetingResponse.builder().build());

            service.createMeeting(CALL_ID);
            service.endMeeting(CALL_ID);

            verify(chimeSdkMeetingsClient).deleteMeeting(any(DeleteMeetingRequest.class));
            assertThat(service.isMeetingActive(CALL_ID)).isFalse();
        }

        @Test
        @DisplayName("endMeeting surfaces retryable AWS deletion failures")
        void endMeeting_awsError_isRetryable() {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());
            when(chimeSdkMeetingsClient.deleteMeeting(any(DeleteMeetingRequest.class)))
                    .thenThrow(new RuntimeException("Network error"));

            service.createMeeting(CALL_ID);
            assertThatThrownBy(() -> service.endMeeting(CALL_ID))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("Retryable failure");
        }

        @Test
        @DisplayName("new node hydrates a durable meeting before creating another")
        void createMeeting_afterRestart_hydratesDurableMeeting() {
            Meeting meeting = buildMeeting(MEETING_ID);
            CallSession session = new CallSession();
            session.setCallId(CALL_ID);
            session.setChimeMeetingId(MEETING_ID);
            session.setStatus(CallSessionService.SESSION_ACTIVE);
            when(callSessionRepository.findByCallId(CALL_ID))
                    .thenReturn(Optional.of(session));
            when(chimeSdkMeetingsClient.getMeeting(any(GetMeetingRequest.class)))
                    .thenReturn(GetMeetingResponse.builder().meeting(meeting).build());
            ChimeService restarted = new ChimeService(
                    chimeSdkMeetingsClient, callSessionRepository,
                    true, false, "en-US", "us-east-1");

            Map<String, Object> result = restarted.createMeeting(CALL_ID);

            assertThat(result.get("meetingId")).isEqualTo(MEETING_ID);
            verify(chimeSdkMeetingsClient, never()).createMeeting(any(CreateMeetingRequest.class));
        }

        @Test
        @DisplayName("new AWS meeting is compensated when persistence loses termination race")
        void createMeeting_terminationRace_deletesNewMeeting() {
            Meeting meeting = buildMeeting(MEETING_ID);
            CallSession joinable = new CallSession();
            joinable.setCallId(CALL_ID);
            joinable.setStatus(CallSessionService.SESSION_CREATED);
            CallSession terminating = new CallSession();
            terminating.setCallId(CALL_ID);
            terminating.setStatus(CallSessionService.SESSION_TERMINATING);
            when(callSessionRepository.findByCallId(CALL_ID))
                    .thenReturn(Optional.of(joinable))
                    .thenReturn(Optional.of(joinable))
                    .thenReturn(Optional.of(terminating));
            when(callSessionRepository.persistMeetingIdIfAbsent(
                    any(), any(), any(), any())).thenReturn(0);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());
            when(chimeSdkMeetingsClient.deleteMeeting(any(DeleteMeetingRequest.class)))
                    .thenReturn(DeleteMeetingResponse.builder().build());
            ChimeService raced = new ChimeService(
                    chimeSdkMeetingsClient, callSessionRepository,
                    true, false, "en-US", "us-east-1");

            assertThatThrownBy(() -> raced.createMeeting(CALL_ID))
                    .isInstanceOf(RuntimeException.class)
                    .hasMessageContaining("non-joinable");
            verify(callSessionRepository).attachMeetingToTermination(
                    CALL_ID, MEETING_ID, CallSessionService.SESSION_TERMINATING);
            verify(chimeSdkMeetingsClient).deleteMeeting(any(DeleteMeetingRequest.class));
        }
    }

    // ══════════════════════════════════════════════════════════════════
    //  AWS-ENABLED + TRANSCRIPTION ENABLED
    // ══════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Transcription enabled mode")
    class TranscriptionEnabledTests {

        private ChimeService service;

        @BeforeEach
        void setUp() {
            service = new ChimeService(
                    chimeSdkMeetingsClient,
                    true,   // awsEnabled
                    true,   // transcriptionEnabled
                    "en-US",
                    "us-east-1"
            );
        }

        @Test
        @DisplayName("createMeeting starts transcription after meeting creation")
        void createMeeting_transcriptionEnabled_startsTranscription() {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());
            when(chimeSdkMeetingsClient.startMeetingTranscription(
                    any(StartMeetingTranscriptionRequest.class)))
                    .thenReturn(StartMeetingTranscriptionResponse.builder().build());

            service.createMeeting(CALL_ID);

            verify(chimeSdkMeetingsClient).startMeetingTranscription(
                    any(StartMeetingTranscriptionRequest.class));
        }

        @Test
        @DisplayName("transcription start failure is swallowed gracefully")
        void createMeeting_transcriptionStartFails_continuesSilently() {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());
            when(chimeSdkMeetingsClient.startMeetingTranscription(
                    any(StartMeetingTranscriptionRequest.class)))
                    .thenThrow(new RuntimeException("Transcribe not authorized"));

            // Should not throw even though transcription fails
            Map<String, Object> result = service.createMeeting(CALL_ID);

            assertThat(result.get("meetingId")).isEqualTo(MEETING_ID);
        }

        @Test
        @DisplayName("transcription is not started twice for same meeting")
        void createMeeting_transcriptionIdempotent_onlyStartsOnce() {
            Meeting meeting = buildMeeting(MEETING_ID);
            when(chimeSdkMeetingsClient.createMeeting(any(CreateMeetingRequest.class)))
                    .thenReturn(CreateMeetingResponse.builder().meeting(meeting).build());
            when(chimeSdkMeetingsClient.startMeetingTranscription(
                    any(StartMeetingTranscriptionRequest.class)))
                    .thenReturn(StartMeetingTranscriptionResponse.builder().build());
            when(chimeSdkMeetingsClient.createAttendee(any(CreateAttendeeRequest.class)))
                    .thenReturn(CreateAttendeeResponse.builder()
                            .attendee(buildAttendee()).build());

            service.createMeeting(CALL_ID);
            service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "John Doe"); // triggers second transcription attempt

            // startMeetingTranscription called exactly once (second attempt sees ALREADY_STARTED)
            verify(chimeSdkMeetingsClient).startMeetingTranscription(
                    any(StartMeetingTranscriptionRequest.class));
        }

        @Test
        @DisplayName("getTranscriptionDebugStatus shows transcriptionEnabled=true")
        void getTranscriptionDebugStatus_transcriptionEnabled_showsTrue() {
            Map<String, Object> status = service.getTranscriptionDebugStatus(CALL_ID);

            assertThat(status.get("transcriptionEnabled")).isEqualTo(true);
        }
    }

    // ══════════════════════════════════════════════════════════════════
    //  AWS-ENABLED, CLIENT NULL
    // ══════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("AWS enabled but client null")
    class AwsNullClientTests {

        private ChimeService service;

        @BeforeEach
        void setUp() {
            // awsEnabled=true but chimeSdkMeetingsClient=null → falls back to local mode
            service = new ChimeService(
                    null,   // client null
                    true,   // awsEnabled
                    false,
                    "en-US",
                    "us-east-1"
            );
        }

        @Test
        @DisplayName("createMeeting falls back to local mock when client is null")
        void createMeeting_clientNull_returnsLocalMeeting() {
            Map<String, Object> result = service.createMeeting(CALL_ID);

            assertThat(result.get("meetingId").toString()).startsWith("local-");
        }

        @Test
        @DisplayName("isMeetingActive works without client")
        void isMeetingActive_afterCreate_returnsTrue() {
            service.createMeeting(CALL_ID);
            assertThat(service.isMeetingActive(CALL_ID)).isTrue();
        }
    }
}
