package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import com.careconnect.model.CallParticipant;
import com.careconnect.model.CallSession;
import com.careconnect.repository.CallParticipantRepository;
import com.careconnect.repository.CallSessionRepository;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.slf4j.LoggerFactory;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.SimpleTransactionStatus;
import software.amazon.awssdk.services.chimesdkmeetings.ChimeSdkMeetingsClient;
import software.amazon.awssdk.services.chimesdkmeetings.model.Attendee;
import software.amazon.awssdk.services.chimesdkmeetings.model.ChimeSdkMeetingsException;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateAttendeeRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateAttendeeResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.CreateMeetingResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.DeleteAttendeeRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.DeleteMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.GetMeetingRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.GetMeetingResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.ListAttendeesRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.ListAttendeesResponse;
import software.amazon.awssdk.services.chimesdkmeetings.model.MediaPlacement;
import software.amazon.awssdk.services.chimesdkmeetings.model.Meeting;
import software.amazon.awssdk.services.chimesdkmeetings.model.StartMeetingTranscriptionRequest;
import software.amazon.awssdk.services.chimesdkmeetings.model.StartMeetingTranscriptionResponse;

/**
 * Branch tests for {@link ChimeService} durable meeting/attendee coordination: claim races,
 * persisted credentials, compensation, stale join caches, meeting deletion failures and roster
 * lookups. The Chime SDK meetings client, repositories and transaction manager are mocks.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("ChimeService coordination branches")
class ChimeServiceBranchTest {

    private static final String CALL_ID = "call-chime-branch";
    private static final String USER_ID = "42";
    private static final String MEETING_ID = "meeting-branch";

    @Mock private ChimeSdkMeetingsClient chime;
    @Mock private CallSessionRepository sessionRepository;
    @Mock private CallParticipantRepository participantRepository;
    @Mock private PlatformTransactionManager txManager;

    private final Logger serviceLogger = (Logger) LoggerFactory.getLogger(ChimeService.class);
    private Level originalLevel;
    private CallSession session;

    @BeforeEach
    void setUp() {
        originalLevel = serviceLogger.getLevel();
        serviceLogger.setLevel(Level.TRACE);
        when(txManager.getTransaction(any())).thenReturn(new SimpleTransactionStatus());
        session = new CallSession();
        session.setId(9L);
        session.setCallId(CALL_ID);
        session.setStatus(CallSessionService.SESSION_ACTIVE);
        when(sessionRepository.findByCallId(CALL_ID)).thenReturn(Optional.of(session));
        when(sessionRepository.findByCallIdForLifecycle(CALL_ID)).thenReturn(Optional.of(session));
        when(sessionRepository.persistMeetingIdIfAbsent(any(), any(), any(), any())).thenReturn(1);
        when(chime.createMeeting(any(CreateMeetingRequest.class)))
                .thenReturn(CreateMeetingResponse.builder().meeting(meeting(MEETING_ID, true)).build());
        when(chime.listAttendees(any(ListAttendeesRequest.class)))
                .thenReturn(ListAttendeesResponse.builder().attendees(List.of()).build());
    }

    @AfterEach
    void restoreLogger() {
        serviceLogger.setLevel(originalLevel);
    }

    private static Meeting meeting(final String id, final boolean withPlacement) {
        final Meeting.Builder builder =
                Meeting.builder().meetingId(id).externalMeetingId(CALL_ID).mediaRegion("us-west-2");
        if (withPlacement) {
            builder.mediaPlacement(
                    MediaPlacement.builder()
                            .audioHostUrl("a")
                            .audioFallbackUrl("b")
                            .screenDataUrl("c")
                            .screenSharingUrl("d")
                            .screenViewingUrl("e")
                            .signalingUrl("f")
                            .turnControlUrl("g")
                            .build());
        }
        return builder.build();
    }

    private ChimeService coordinated(final boolean transcription) {
        return new ChimeService(
                chime, sessionRepository, participantRepository, txManager, true, transcription, "en-US", "us-east-1");
    }

    private static CallParticipant participant(final String attendeeId, final String token, final String ext) {
        final CallParticipant participant = new CallParticipant();
        participant.setCallSessionId(9L);
        participant.setUserId(42L);
        participant.setChimeAttendeeId(attendeeId);
        participant.setChimeJoinToken(token);
        participant.setChimeExternalUserId(ext);
        return participant;
    }

    private static Attendee attendee(final String id, final String ext) {
        return Attendee.builder().attendeeId(id).externalUserId(ext).joinToken("tok-" + id).build();
    }

    private static ChimeSdkMeetingsException chimeError(final int status) {
        return (ChimeSdkMeetingsException)
                ChimeSdkMeetingsException.builder().statusCode(status).message("status " + status).build();
    }

    @Nested
    @DisplayName("createMeeting")
    class CreateMeeting {

        @Test
        @DisplayName("a local meeting that loses the persist race is compensated and rejected")
        void localMeetingLosesRace() {
            final ChimeService local =
                    new ChimeService(chime, sessionRepository, participantRepository, txManager, false, false, "en-US", "us-east-1");
            when(sessionRepository.persistMeetingIdIfAbsent(any(), any(), any(), any())).thenReturn(0);
            session.setStatus(CallSessionService.SESSION_ACTIVE);
            when(sessionRepository.findByCallId(CALL_ID))
                    .thenReturn(Optional.of(session))
                    .thenReturn(Optional.of(session))
                    .thenReturn(Optional.empty());

            assertThatThrownBy(() -> local.createMeeting(CALL_ID))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("non-joinable");
            verify(chime, never()).deleteMeeting(any(DeleteMeetingRequest.class));
        }

        @Test
        @DisplayName("an AWS meeting bound to another meeting id is rejected and compensation errors are logged")
        void persistedMismatch_rejected() {
            when(sessionRepository.persistMeetingIdIfAbsent(any(), any(), any(), any())).thenReturn(0);
            final CallSession bound = new CallSession();
            bound.setId(9L);
            bound.setStatus(CallSessionService.SESSION_ACTIVE);
            bound.setChimeMeetingId("other-meeting");
            when(sessionRepository.findByCallId(CALL_ID))
                    .thenReturn(Optional.of(session))
                    .thenReturn(Optional.of(session))
                    .thenReturn(Optional.of(bound));

            assertThatThrownBy(() -> coordinated(false).createMeeting(CALL_ID))
                    .hasMessageContaining("Failed to create video call meeting");
        }

        @Test
        @DisplayName("an AWS meeting that loses the race to termination is deleted and attached")
        void terminatingSession_compensates() {
            when(sessionRepository.persistMeetingIdIfAbsent(any(), any(), any(), any())).thenReturn(0);
            final CallSession terminating = new CallSession();
            terminating.setId(9L);
            terminating.setStatus(CallSessionService.SESSION_TERMINATING);
            when(sessionRepository.findByCallId(CALL_ID))
                    .thenReturn(Optional.of(session))
                    .thenReturn(Optional.of(session))
                    .thenReturn(Optional.of(terminating))
                    .thenReturn(Optional.of(terminating))
                    .thenReturn(Optional.of(terminating));
            when(chime.deleteMeeting(any(DeleteMeetingRequest.class)))
                    .thenThrow(chimeError(500))
                    .thenThrow(new RuntimeException("network"))
                    .thenThrow(chimeError(404));

            for (int i = 0; i < 3; i++) {
                assertThatThrownBy(() -> coordinated(false).createMeeting(CALL_ID))
                        .isInstanceOf(RuntimeException.class);
                when(sessionRepository.findByCallId(CALL_ID))
                        .thenReturn(Optional.of(session))
                        .thenReturn(Optional.of(session))
                        .thenReturn(Optional.of(terminating));
            }
            verify(sessionRepository, times(3))
                    .attachMeetingToTermination(CALL_ID, MEETING_ID, CallSessionService.SESSION_TERMINATING);
            verify(chime, times(3)).deleteMeeting(any(DeleteMeetingRequest.class));
        }

        @Test
        @DisplayName("an already-persisted matching meeting id is accepted")
        void persistedSameMeeting_accepted() {
            when(sessionRepository.persistMeetingIdIfAbsent(any(), any(), any(), any())).thenReturn(0);
            final CallSession bound = new CallSession();
            bound.setId(9L);
            bound.setStatus(CallSessionService.SESSION_ACTIVE);
            bound.setChimeMeetingId(MEETING_ID);
            when(sessionRepository.findByCallId(CALL_ID))
                    .thenReturn(Optional.of(session))
                    .thenReturn(Optional.of(session))
                    .thenReturn(Optional.of(bound));
            when(chime.startMeetingTranscription(any(StartMeetingTranscriptionRequest.class)))
                    .thenReturn(StartMeetingTranscriptionResponse.builder().build());

            final ChimeService service = coordinated(true);
            assertThat(service.createMeeting(CALL_ID)).containsEntry("meetingId", MEETING_ID);
            assertThat(service.getTranscriptionDebugStatus(CALL_ID)).containsEntry("transcriptionStarted", true);
        }

        @Test
        @DisplayName("a durable meeting that AWS no longer knows is cleared; other probe errors fail")
        void hydrateDurable_404ClearsOtherFails() {
            session.setChimeMeetingId("stale-meeting");
            when(chime.getMeeting(any(GetMeetingRequest.class)))
                    .thenThrow(chimeError(404))
                    .thenThrow(chimeError(503));

            assertThat(coordinated(false).createMeeting(CALL_ID)).containsEntry("meetingId", MEETING_ID);
            verify(sessionRepository).clearMeetingId(CALL_ID, "stale-meeting");

            assertThatThrownBy(() -> coordinated(false).createMeeting(CALL_ID))
                    .hasMessageContaining("Failed to probe durable Chime meeting");
        }

        @Test
        @DisplayName("a non-joinable session is rejected before any meeting work")
        void nonJoinableSession_rejected() {
            session.setStatus(CallSessionService.SESSION_ENDED);

            assertThatThrownBy(() -> coordinated(false).createMeeting(CALL_ID))
                    .hasMessageContaining("no longer joinable");
        }
    }

    @Nested
    @DisplayName("createAttendee claim paths")
    class AttendeeClaims {

        @Test
        @DisplayName("a participant with persisted credentials gets them back and the external id is backfilled")
        void persistedCredentials_backfilled() {
            final ChimeService service = coordinated(false);
            service.createMeeting(CALL_ID);
            when(participantRepository.findByCallSessionIdAndUserId(9L, 42L))
                    .thenReturn(Optional.of(participant("att-1", "tok-1", " ")));

            final Map<String, Object> creds = service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "x");

            assertThat(creds).containsEntry("attendeeId", "att-1").containsEntry("joinToken", "tok-1");
            assertThat(((Map<?, ?>) creds.get("mediaPlacement")).get("eventIngestionUrl")).isEqualTo("");
            verify(participantRepository).backfillChimeExternalUserIdIfBlank(eq(9L), eq(42L), anyString());
            // Cached on second call.
            assertThat(service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "x")).isSameAs(creds);
        }

        @Test
        @DisplayName("a lost claim returns the winner's credentials after backfilling its external id")
        void lostClaim_returnsWinner() {
            final ChimeService service = coordinated(false);
            service.createMeeting(CALL_ID);
            when(participantRepository.findByCallSessionIdAndUserId(9L, 42L))
                    .thenReturn(Optional.of(participant(null, null, null)))
                    .thenReturn(Optional.of(participant("att-w", "tok-w", null)));
            when(participantRepository.claimAttendeeCreation(any(), any(), any(), any(), any(), any())).thenReturn(0);

            final Map<String, Object> creds = service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "x");

            assertThat(creds).containsEntry("attendeeId", "att-w");
            verify(participantRepository).backfillChimeExternalUserIdIfBlank(eq(9L), eq(42L), anyString());
        }

        @Test
        @DisplayName("a lost claim with no winner yet reports creation in progress")
        void lostClaim_noWinner_inProgress() {
            final ChimeService service = coordinated(false);
            service.createMeeting(CALL_ID);
            when(participantRepository.findByCallSessionIdAndUserId(9L, 42L))
                    .thenReturn(Optional.of(participant(null, null, null)));
            when(participantRepository.claimAttendeeCreation(any(), any(), any(), any(), any(), any())).thenReturn(0);

            assertThatThrownBy(() -> service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "x"))
                    .hasMessageContaining("already in progress");
        }

        @Test
        @DisplayName("a session that ended before the claim rejects the join")
        void claim_sessionEnded() {
            final ChimeService service = coordinated(false);
            service.createMeeting(CALL_ID);
            final CallSession ended = new CallSession();
            ended.setId(9L);
            ended.setStatus(CallSessionService.SESSION_ENDED);
            when(sessionRepository.findByCallIdForLifecycle(CALL_ID)).thenReturn(Optional.of(ended));

            assertThatThrownBy(() -> service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "x"))
                    .hasMessageContaining("no longer joinable");
        }

        @Test
        @DisplayName("an AWS create failure releases the durable claim")
        void createFailure_releasesClaim() {
            final ChimeService service = coordinated(false);
            service.createMeeting(CALL_ID);
            when(participantRepository.findByCallSessionIdAndUserId(9L, 42L))
                    .thenReturn(Optional.of(participant(null, null, null)));
            when(participantRepository.claimAttendeeCreation(any(), any(), any(), any(), any(), any())).thenReturn(1);
            when(chime.createAttendee(any(CreateAttendeeRequest.class))).thenThrow(new RuntimeException("limit"));

            assertThatThrownBy(() -> service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "x"))
                    .hasMessageContaining("Failed to join video call");
            verify(participantRepository).releaseAttendeeClaim(eq(9L), eq(42L), any(UUID.class));
        }

        @Test
        @DisplayName("losing finalize after creating a different attendee deletes it; no winner throws")
        void lostFinalize_compensatesAndThrows() {
            final ChimeService service = coordinated(false);
            service.createMeeting(CALL_ID);
            when(participantRepository.findByCallSessionIdAndUserId(9L, 42L))
                    .thenReturn(Optional.of(participant(null, null, null)))
                    .thenReturn(Optional.empty());
            when(participantRepository.claimAttendeeCreation(any(), any(), any(), any(), any(), any())).thenReturn(1);
            when(participantRepository.finalizeAttendeeCreation(any(), any(), any(), any(), any(), any())).thenReturn(0);
            when(chime.createAttendee(any(CreateAttendeeRequest.class)))
                    .thenReturn(CreateAttendeeResponse.builder().attendee(attendee("att-new", "ext")).build());
            when(chime.deleteAttendee(any(DeleteAttendeeRequest.class))).thenThrow(new RuntimeException("delete failed"));
            // Session row gone by the time the claim is released.
            when(sessionRepository.findByCallId(CALL_ID)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "x"))
                    .hasMessageContaining("already in progress");
            verify(chime).deleteAttendee(any(DeleteAttendeeRequest.class));
        }

        @Test
        @DisplayName("an existing AWS attendee found on a later roster page is reused")
        void existingAttendeeOnSecondPage_reused() {
            final ChimeService service = coordinated(false);
            service.createMeeting(CALL_ID);
            final String opaque = service.toOpaqueChimeExternalUserId(CALL_ID, USER_ID);
            when(participantRepository.findByCallSessionIdAndUserId(9L, 42L))
                    .thenReturn(Optional.of(participant(null, null, null)));
            when(participantRepository.claimAttendeeCreation(any(), any(), any(), any(), any(), any())).thenReturn(1);
            when(participantRepository.finalizeAttendeeCreation(any(), any(), any(), any(), any(), any())).thenReturn(1);
            when(chime.listAttendees(any(ListAttendeesRequest.class)))
                    .thenReturn(
                            ListAttendeesResponse.builder()
                                    .attendees(attendee("other", "someone"))
                                    .nextToken("page-2")
                                    .build())
                    .thenReturn(ListAttendeesResponse.builder().attendees(attendee("att-existing", opaque)).build());

            assertThat(service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "x"))
                    .containsEntry("attendeeId", "att-existing");
            verify(chime, never()).createAttendee(any(CreateAttendeeRequest.class));
            final ArgumentCaptor<ListAttendeesRequest> captor = ArgumentCaptor.forClass(ListAttendeesRequest.class);
            verify(chime, times(2)).listAttendees(captor.capture());
            assertThat(captor.getAllValues().get(1).nextToken()).isEqualTo("page-2");
        }

        @Test
        @DisplayName("without participant repository a non-joinable session rejects the join")
        void withoutParticipantRepo_nonJoinable() {
            final ChimeService service = new ChimeService(chime, sessionRepository, true, false, "en-US", "us-east-1");
            service.createMeeting(CALL_ID);
            session.setStatus(CallSessionService.SESSION_ENDED);

            assertThatThrownBy(() -> service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "x"))
                    .hasMessageContaining("no longer joinable");
        }

        @Test
        @DisplayName("persisted credentials without a cached meeting fall back to blank meeting fields")
        void persistedCredentials_withoutMeeting() {
            final ChimeService service = coordinated(false);
            service.createMeeting(CALL_ID);
            when(participantRepository.findByCallSessionIdAndUserId(9L, 42L))
                    .thenAnswer(
                            inv -> {
                                // Simulate the local meeting cache being evicted mid-claim.
                                @SuppressWarnings("unchecked")
                                final Map<String, Meeting> meetings =
                                        (Map<String, Meeting>)
                                                org.springframework.test.util.ReflectionTestUtils.getField(
                                                        service, "activeMeetings");
                                meetings.remove(CALL_ID);
                                return Optional.of(participant("att-1", "tok-1", "ext-1"));
                            });

            final Map<String, Object> creds = service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "x");

            assertThat(creds).containsEntry("meetingId", "").containsEntry("externalUserId", "ext-1");
        }
    }

    @Nested
    @DisplayName("joinMeeting cache and roster")
    class JoinAndRoster {

        @Test
        @DisplayName("a cached attendee still on the roster is returned; a missing one is re-created")
        void cachedAttendee_liveCheck() {
            final ChimeService service = new ChimeService(chime, true, false, "en-US", "us-east-1");
            final String opaque = service.toOpaqueChimeExternalUserId(CALL_ID, USER_ID);
            when(chime.createAttendee(any(CreateAttendeeRequest.class)))
                    .thenReturn(CreateAttendeeResponse.builder().attendee(attendee("att-1", opaque)).build())
                    .thenReturn(CreateAttendeeResponse.builder().attendee(attendee("att-2", opaque)).build());
            final Map<String, Object> first = service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "x");
            assertThat(first).containsEntry("attendeeId", "att-1");

            // Roster shows only pipeline/blank rows: cannot verify → keep cache.
            when(chime.listAttendees(any(ListAttendeesRequest.class)))
                    .thenReturn(
                            ListAttendeesResponse.builder()
                                    .attendees(attendee("p", "aws:MediaPipeline-1"), attendee("b", " "))
                                    .build());
            assertThat(service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "x")).isSameAs(first);

            // Roster shows the same attendee → keep cache.
            when(chime.listAttendees(any(ListAttendeesRequest.class)))
                    .thenReturn(ListAttendeesResponse.builder().attendees(attendee("att-1", opaque)).build());
            assertThat(service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "x")).isSameAs(first);

            // Roster shows another user only → stale cache, re-create.
            when(chime.listAttendees(any(ListAttendeesRequest.class)))
                    .thenReturn(ListAttendeesResponse.builder().attendees(attendee("x", "ROLE_PATIENT_7")).build());
            assertThat(service.joinMeeting(CALL_ID, USER_ID, "CAREGIVER", "x"))
                    .containsEntry("attendeeId", "att-2");
        }

        @Test
        @DisplayName("findLiveAttendeeIdForUser matches opaque and legacy ids and ignores blanks")
        void findLiveAttendee_variants() {
            final ChimeService service = new ChimeService(chime, true, false, "en-US", "us-east-1");
            final String opaque = service.toOpaqueChimeExternalUserId(CALL_ID, USER_ID);
            when(chime.listAttendees(any(ListAttendeesRequest.class)))
                    .thenReturn(
                            ListAttendeesResponse.builder()
                                    .attendees(attendee("blank", " "), attendee("legacy", "ROLE_CAREGIVER_42"))
                                    .build())
                    .thenReturn(ListAttendeesResponse.builder().attendees(attendee("opaque", opaque)).build())
                    .thenThrow(new RuntimeException("throttled"));

            assertThat(service.findLiveAttendeeIdForUser(CALL_ID, MEETING_ID, USER_ID)).isEqualTo("legacy");
            assertThat(service.findLiveAttendeeIdForUser(CALL_ID, MEETING_ID, USER_ID)).isEqualTo("opaque");
            assertThat(service.findLiveAttendeeIdForUser(CALL_ID, MEETING_ID, "not-a-number")).isNull();
            assertThat(service.findLiveAttendeeIdForUser(CALL_ID, MEETING_ID, " ")).isNull();
            assertThat(service.findLiveAttendeeIdForUser(CALL_ID, " ", USER_ID)).isNull();
        }

        @Test
        @DisplayName("listMeetingAttendees maps attendees and is empty when AWS is disabled")
        void listMeetingAttendees_mapsRows() {
            final ChimeService service = new ChimeService(chime, true, false, "en-US", "us-east-1");
            when(chime.listAttendees(any(ListAttendeesRequest.class)))
                    .thenReturn(ListAttendeesResponse.builder().attendees(attendee("a", "ext-a")).build());

            assertThat(service.listMeetingAttendees(MEETING_ID))
                    .extracting(ChimeMeetingAttendee::attendeeId)
                    .containsExactly("a");
            assertThat(new ChimeService(chime, false, false, "en-US", "us-east-1").listMeetingAttendees(MEETING_ID))
                    .isEmpty();
        }

        @Test
        @DisplayName("meeting lookups resolve region, source ARN and reverse call id")
        void meetingLookups() {
            final ChimeService service = new ChimeService(chime, true, false, "en-US", "us-east-1");
            service.createMeeting(CALL_ID);

            assertThat(service.getMediaRegion(CALL_ID)).isEqualTo("us-west-2");
            assertThat(service.getMediaRegion("unknown")).isEqualTo("us-east-1");
            assertThat(service.buildMeetingSourceArn(CALL_ID, MEETING_ID, "123"))
                    .isEqualTo("arn:aws:chime:us-west-2:123:meeting/" + MEETING_ID);
            assertThat(service.findCallIdByMeetingId(MEETING_ID)).isEqualTo(CALL_ID);
            assertThat(service.findCallIdByMeetingId("other")).isNull();
            assertThat(service.findCallIdByMeetingId(null)).isNull();
            assertThat(service.findCallIdByMeetingId(" ")).isNull();
        }

        @Test
        @DisplayName("durable meeting id is preferred for lookups and debug status")
        void durableMeetingId_preferred() {
            session.setChimeMeetingId("durable-meeting");
            final ChimeService service = coordinated(false);

            assertThat(service.getMeetingId(CALL_ID)).isEqualTo("durable-meeting");
            assertThat(service.getTranscriptionDebugStatus(CALL_ID)).containsEntry("meetingId", "durable-meeting");
        }
    }

    @Nested
    @DisplayName("endMeeting")
    class EndMeeting {

        @Test
        @DisplayName("deletes the durable meeting and tolerates 404")
        void endMeeting_deletesAndTolerates404() {
            session.setChimeMeetingId("durable-meeting");
            final ChimeService service = coordinated(false);
            when(chime.deleteMeeting(any(DeleteMeetingRequest.class)))
                    .thenReturn(null)
                    .thenThrow(chimeError(404))
                    .thenThrow(chimeError(500))
                    .thenThrow(new RuntimeException("network"));

            service.endMeeting(CALL_ID);
            service.endMeeting(CALL_ID);
            assertThatThrownBy(() -> service.endMeeting(CALL_ID)).hasMessageContaining("Retryable failure");
            assertThatThrownBy(() -> service.endMeeting(CALL_ID)).hasMessageContaining("Retryable failure");
            verify(chime, times(4)).deleteMeeting(any(DeleteMeetingRequest.class));
        }
    }

    @Test
    @DisplayName("a meeting without media placement yields blank placement urls for new attendees")
    void meetingWithoutPlacement_blankUrls() {
        when(chime.createMeeting(any(CreateMeetingRequest.class)))
                .thenReturn(CreateMeetingResponse.builder().meeting(meeting(MEETING_ID, false)).build());
        when(chime.getMeeting(any(GetMeetingRequest.class)))
                .thenReturn(GetMeetingResponse.builder().meeting(meeting(MEETING_ID, false)).build());
        final ChimeService service = coordinated(false);
        service.createMeeting(CALL_ID);
        when(participantRepository.findByCallSessionIdAndUserId(9L, 42L))
                .thenReturn(Optional.of(participant("att-1", "tok-1", null)));

        final Map<String, Object> creds = service.createAttendee(CALL_ID, USER_ID, "CAREGIVER", "x");

        assertThat(((Map<?, ?>) creds.get("mediaPlacement")).get("audioHostUrl")).isEqualTo("");
        verify(participantRepository).backfillChimeExternalUserIdIfBlank(eq(9L), eq(42L), anyString());
    }

    @Test
    @DisplayName("isMeetingActive reads the durable session when a repository is present")
    void isMeetingActive_usesDurableSession() {
        final ChimeService service = coordinated(false);
        assertThat(service.isMeetingActive(CALL_ID)).isFalse();

        session.setChimeMeetingId("durable-meeting");
        assertThat(service.isMeetingActive(CALL_ID)).isTrue();

        session.setStatus(CallSessionService.SESSION_ENDED);
        assertThat(service.isMeetingActive(CALL_ID)).isFalse();
    }

    @Test
    @DisplayName("a transcription start failure is recorded and does not fail meeting creation")
    void transcriptionStartFailure_recorded() {
        when(chime.startMeetingTranscription(any(StartMeetingTranscriptionRequest.class)))
                .thenThrow(new RuntimeException("access denied"));
        final ChimeService service = coordinated(true);

        assertThat(service.createMeeting(CALL_ID)).containsEntry("meetingId", MEETING_ID);
        assertThat(service.getTranscriptionDebugStatus(CALL_ID))
                .containsEntry("lastStartStatus", "START_FAILED")
                .containsEntry("transcriptionStarted", false);
    }
}
