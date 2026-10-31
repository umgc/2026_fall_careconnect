package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.exception.AppException;
import com.careconnect.model.CallParticipant;
import com.careconnect.model.CallSession;
import com.careconnect.model.Caregiver;
import com.careconnect.model.Patient;
import com.careconnect.model.TerminationStep;
import com.careconnect.model.User;
import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.repository.CallParticipantRepository;
import com.careconnect.repository.CallSessionRepository;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import com.careconnect.security.Role;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

/**
 * Branch tests for {@link CallSessionService}: authorization guards, transcript/recording access,
 * termination claim fencing, invitation decline and helper edge cases. All repositories and access
 * services are Mockito mocks.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("CallSessionService branch coverage")
class CallSessionServiceBranchTest {

    private static final String CALL_ID = "call-1";

    @Mock private CallSessionRepository sessionRepository;
    @Mock private CallParticipantRepository participantRepository;
    @Mock private PatientRepository patientRepository;
    @Mock private UserRepository userRepository;
    @Mock private CaregiverPatientLinkService caregiverLinkService;
    @Mock private FamilyMemberService familyMemberService;
    @Mock private ScheduledVisitRepository scheduledVisitRepository;
    @Mock private CaregiverRepository caregiverRepository;

    private CallSessionService service;

    @BeforeEach
    void setUp() {
        service =
                new CallSessionService(
                        sessionRepository,
                        participantRepository,
                        patientRepository,
                        userRepository,
                        caregiverLinkService,
                        familyMemberService,
                        scheduledVisitRepository,
                        caregiverRepository);
    }

    private static User user(final Long id, final Role role) {
        final User user = new User();
        user.setId(id);
        user.setRole(role);
        return user;
    }

    private static CallSession session(final String status) {
        final CallSession session = new CallSession();
        session.setId(10L);
        session.setCallId(CALL_ID);
        session.setPatientId(42L);
        session.setCreatedByUserId(2L);
        session.setStatus(status);
        return session;
    }

    private static CallParticipant participant(final Long userId, final String status) {
        final CallParticipant participant = new CallParticipant();
        participant.setCallSessionId(10L);
        participant.setUserId(userId);
        participant.setStatus(status);
        return participant;
    }

    private static Patient patient(final Long userId) {
        final Patient patient = new Patient();
        patient.setId(42L);
        patient.setUser(userId == null ? null : user(userId, Role.PATIENT));
        return patient;
    }

    private void stubSession(final CallSession session) {
        lenient().when(sessionRepository.findByCallId(CALL_ID)).thenReturn(Optional.of(session));
        lenient().when(sessionRepository.findByCallIdForLifecycle(CALL_ID)).thenReturn(Optional.of(session));
    }

    private void stubParticipant(final Long userId, final String status) {
        when(participantRepository.findByCallSessionIdAndUserId(10L, userId))
                .thenReturn(Optional.of(participant(userId, status)));
    }

    private static HttpStatus status(final Throwable error) {
        return (HttpStatus) ((AppException) error).getStatus();
    }

    @Nested
    @DisplayName("createSession and ensureJoinAuthorized")
    class Creation {

        @Test
        @DisplayName("rejects invalid call ids, missing creator and missing patient")
        void createSession_guards() {
            final User creator = user(2L, Role.ADMIN);
            assertThatThrownBy(() -> service.createSession("bad id!", 7L, null, null, creator))
                    .isInstanceOf(AppException.class);
            assertThatThrownBy(() -> service.createSession(CALL_ID, 7L, null, null, null))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.UNAUTHORIZED));
            assertThatThrownBy(() -> service.createSession(CALL_ID, 7L, null, null, user(null, Role.ADMIN)))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.UNAUTHORIZED));
            assertThatThrownBy(() -> service.createSession(CALL_ID, null, null, null, creator))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.BAD_REQUEST));
        }

        @Test
        @DisplayName("a missing ON CONFLICT target falls back to the JPA path; other insert errors propagate")
        void createSession_conflictTargetFallback() {
            final User creator = user(2L, Role.ADMIN);
            when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient(7L)));
            when(sessionRepository.insertIfAbsent(anyString(), anyLong(), anyLong(), any(), anyString()))
                    .thenThrow(
                            new RuntimeException(
                                    "wrapper",
                                    new RuntimeException(
                                            "ERROR: there is no unique or exclusion constraint matching the ON CONFLICT")))
                    .thenThrow(new RuntimeException("connection refused", new RuntimeException((String) null)));
            final CallSession existing = session(CallSessionService.SESSION_CREATED);
            when(sessionRepository.findByCallId(CALL_ID)).thenReturn(Optional.of(existing));

            assertThat(service.createSession(CALL_ID, 7L, null, null, creator)).isSameAs(existing);
            verify(participantRepository, never()).insertIfAbsent(any(), any(), any(), any());

            assertThatThrownBy(() -> service.createSession(CALL_ID, 7L, null, null, creator))
                    .hasMessage("connection refused");
        }

        @Test
        @DisplayName("an existing call id owned by someone else or already ended conflicts")
        void createSession_ownershipConflict() {
            final User creator = user(2L, Role.ADMIN);
            when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient(7L)));
            final CallSession ended = session(CallSessionService.SESSION_ENDED);
            when(sessionRepository.findByCallId(CALL_ID)).thenReturn(Optional.of(ended));

            assertThatThrownBy(() -> service.createSession(CALL_ID, 7L, null, null, creator))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.CONFLICT));
        }

        @Test
        @DisplayName("a caregiver scheduled visit must belong to that caregiver")
        void createSession_scheduledVisitCaregiverChecks() {
            final User caregiver = user(2L, Role.CAREGIVER);
            when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient(7L)));
            when(caregiverLinkService.hasAccessToPatient(2L, 7L)).thenReturn(true);
            final ScheduledVisit visit = new ScheduledVisit();
            visit.setPatientId(42L);
            visit.setCaregiverId(99L);
            when(scheduledVisitRepository.findById(5L)).thenReturn(Optional.of(visit));
            when(caregiverRepository.findByUserId(2L))
                    .thenReturn(Optional.empty())
                    .thenReturn(Optional.of(Caregiver.builder().id(98L).build()));

            assertThatThrownBy(() -> service.createSession(CALL_ID, 7L, null, 5L, caregiver))
                    .hasMessageContaining("Caregiver profile not found");
            assertThatThrownBy(() -> service.createSession(CALL_ID, 7L, null, 5L, caregiver))
                    .hasMessageContaining("assigned to another caregiver");
        }

        @Test
        @DisplayName("ensureJoinAuthorized rejects unauthenticated users, unknown sessions and ended calls")
        void ensureJoinAuthorized_guards() {
            assertThatThrownBy(() -> service.ensureJoinAuthorized(CALL_ID, null, 7L, null, null))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.UNAUTHORIZED));

            when(sessionRepository.findByCallId(CALL_ID)).thenReturn(Optional.empty());
            assertThatThrownBy(() -> service.ensureJoinAuthorized(CALL_ID, user(3L, Role.ADMIN), null, null, null))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.NOT_FOUND));

            when(sessionRepository.findByCallId(CALL_ID)).thenReturn(Optional.of(session(CallSessionService.SESSION_ENDED)));
            assertThatThrownBy(() -> service.ensureJoinAuthorized(CALL_ID, user(3L, Role.ADMIN), null, null, null))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.GONE));
        }

        @Test
        @DisplayName("a family member with patient access is enrolled on join")
        void ensureJoinAuthorized_enrollsFamilyMember() {
            final CallSession active = session(CallSessionService.SESSION_ACTIVE);
            stubSession(active);
            when(patientRepository.findById(42L)).thenReturn(Optional.of(patient(7L)));
            when(familyMemberService.hasAccessToPatient(3L, 7L)).thenReturn(true);
            when(participantRepository.findByCallSessionIdAndUserId(10L, 3L))
                    .thenReturn(Optional.of(participant(3L, CallSessionService.PARTICIPANT_LEFT)))
                    .thenReturn(Optional.of(participant(3L, CallSessionService.PARTICIPANT_LEFT)))
                    .thenReturn(Optional.of(participant(3L, CallSessionService.PARTICIPANT_INVITED)));

            assertThat(service.ensureJoinAuthorized(CALL_ID, user(3L, Role.FAMILY_MEMBER), null, null, null))
                    .isSameAs(active);
            verify(participantRepository)
                    .reinviteIfInactive(eq(10L), eq(3L), eq(2L), anyString(), anyString(), anyString());
        }
    }

    @Nested
    @DisplayName("access checks")
    class Access {

        @Test
        @DisplayName("requireJoinAuthorized rejects ended sessions")
        void requireJoinAuthorized_gone() {
            stubSession(session(CallSessionService.SESSION_CANCELLED));

            assertThatThrownBy(() -> service.requireJoinAuthorized(CALL_ID, 3L))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.GONE));
        }

        @Test
        @DisplayName("requireParticipant accepts members and rejects null or unknown users")
        void requireParticipant_variants() {
            final CallSession active = session(CallSessionService.SESSION_ACTIVE);
            stubSession(active);
            stubParticipant(3L, CallSessionService.PARTICIPANT_DECLINED);
            when(participantRepository.findByCallSessionIdAndUserId(10L, 4L)).thenReturn(Optional.empty());

            assertThat(service.requireParticipant(CALL_ID, 3L)).isSameAs(active);
            assertThatThrownBy(() -> service.requireParticipant(CALL_ID, null)).isInstanceOf(AppException.class);
            assertThatThrownBy(() -> service.requireParticipant(CALL_ID, 4L)).isInstanceOf(AppException.class);
        }

        @Test
        @DisplayName("transcript upload is allowed for active joined users and during termination")
        void transcriptUpload_activeAndTerminating() {
            final CallSession active = session(CallSessionService.SESSION_ACTIVE);
            stubSession(active);
            stubParticipant(3L, CallSessionService.PARTICIPANT_JOINED);
            assertThat(service.requireTranscriptUploadParticipant(CALL_ID, 3L)).isSameAs(active);

            active.setStatus(CallSessionService.SESSION_ENDED);
            active.setEndedAt(null);
            assertThatThrownBy(() -> service.requireTranscriptUploadParticipant(CALL_ID, 3L))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.GONE));

            active.setEndedAt(LocalDateTime.now(ZoneOffset.UTC));
            assertThat(service.requireTranscriptUploadParticipant(CALL_ID, 3L)).isSameAs(active);
        }

        @Test
        @DisplayName("recording access covers unauthenticated, admin, historical participant and patient policy")
        void recordingAccess_variants() {
            final CallSession ended = session(CallSessionService.SESSION_ENDED);
            stubSession(ended);
            assertThatThrownBy(() -> service.requireRecordingAccess(CALL_ID, null))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.UNAUTHORIZED));
            assertThatThrownBy(() -> service.requireRecordingAccess(CALL_ID, user(null, Role.PATIENT)))
                    .isInstanceOf(AppException.class);
            assertThat(service.requireRecordingAccess(CALL_ID, user(1L, Role.ADMIN))).isSameAs(ended);

            stubParticipant(3L, CallSessionService.PARTICIPANT_EXPIRED);
            assertThat(service.requireRecordingAccess(CALL_ID, user(3L, Role.CAREGIVER))).isSameAs(ended);

            when(participantRepository.findByCallSessionIdAndUserId(10L, 7L)).thenReturn(Optional.empty());
            when(patientRepository.findById(42L)).thenReturn(Optional.of(patient(7L)));
            assertThat(service.requireRecordingAccess(CALL_ID, user(7L, Role.PATIENT))).isSameAs(ended);
        }

        @Test
        @DisplayName("patient entity and patient user access checks cover every guard")
        void patientAccessChecks() {
            assertThatThrownBy(() -> service.requirePatientEntityAccess(null, 42L))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.UNAUTHORIZED));
            service.requirePatientEntityAccess(user(1L, Role.ADMIN), null);
            assertThatThrownBy(() -> service.requirePatientEntityAccess(user(7L, Role.PATIENT), null))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.NOT_FOUND));
            when(patientRepository.findById(42L))
                    .thenReturn(Optional.of(patient(7L)))
                    .thenReturn(Optional.of(patient(null)))
                    .thenReturn(Optional.empty());
            service.requirePatientEntityAccess(user(7L, Role.PATIENT), 42L);
            assertThatThrownBy(() -> service.requirePatientEntityAccess(user(7L, Role.PATIENT), 42L))
                    .hasMessageContaining("Patient user not found");
            assertThatThrownBy(() -> service.requirePatientEntityAccess(user(7L, Role.PATIENT), 42L))
                    .hasMessageContaining("Patient not found");

            assertThatThrownBy(() -> service.requirePatientUserAccess(user(null, Role.PATIENT), 7L))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.UNAUTHORIZED));
            service.requirePatientUserAccess(user(1L, Role.ADMIN), null);
            assertThatThrownBy(() -> service.requirePatientUserAccess(user(7L, Role.PATIENT), null))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.NOT_FOUND));
            assertThatThrownBy(() -> service.requirePatientUserAccess(user(8L, Role.PATIENT), 7L))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.FORBIDDEN));
        }

        @Test
        @DisplayName("requirePatientUserId fails when the patient has no user mapping")
        void requirePatientUserId_noUser() {
            when(patientRepository.findById(42L)).thenReturn(Optional.of(patient(null)));

            assertThatThrownBy(() -> service.requirePatientUserId(session(CallSessionService.SESSION_ACTIVE)))
                    .hasMessageContaining("no user mapping");
        }

        @Test
        @DisplayName("participant listings and pending invitee resolution")
        void participantListings() {
            final CallSession active = session(CallSessionService.SESSION_ACTIVE);
            stubSession(active);
            final List<CallParticipant> all =
                    List.of(
                            participant(2L, CallSessionService.PARTICIPANT_JOINED),
                            participant(3L, CallSessionService.PARTICIPANT_INVITED),
                            participant(4L, CallSessionService.PARTICIPANT_DECLINED));
            when(participantRepository.findByCallSessionId(10L)).thenReturn(all);
            when(participantRepository.findByCallSessionIdAndStatus(10L, CallSessionService.PARTICIPANT_JOINED))
                    .thenReturn(List.of(all.get(0)));
            stubParticipant(2L, CallSessionService.PARTICIPANT_JOINED);

            assertThat(service.getParticipants(CALL_ID)).hasSize(3);
            assertThat(service.getJoinedParticipants(CALL_ID)).hasSize(1);
            assertThat(service.requirePendingInvitationRecipient(CALL_ID, 2L, 3L)).isEqualTo(3L);
            assertThatThrownBy(() -> service.requirePendingInvitationRecipient(CALL_ID, 2L, 4L))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.FORBIDDEN));
            assertThat(service.getOtherParticipantUserIds(CALL_ID, 2L)).containsExactly(3L);
        }
    }

    @Nested
    @DisplayName("join bookkeeping")
    class JoinBookkeeping {

        @Test
        @DisplayName("blank meeting ids are not attached")
        void attachChimeMeetingId_blank() {
            service.attachChimeMeetingId(CALL_ID, " ");
            service.attachChimeMeetingId(CALL_ID, null);
            verify(sessionRepository, never()).findByCallId(anyString());
        }

        @Test
        @DisplayName("reverting a failed join is skipped for unknown sessions and unreverted rows")
        void revertJoin_skips() {
            when(sessionRepository.findByCallId(CALL_ID))
                    .thenReturn(Optional.empty())
                    .thenReturn(Optional.of(session(CallSessionService.SESSION_ACTIVE)));
            service.revertJoinAfterChimeFailure(CALL_ID, 3L);
            service.revertJoinAfterChimeFailure(CALL_ID, null);
            service.revertJoinAfterChimeFailure(CALL_ID, 3L);

            verify(participantRepository).revertJoinedToInvitedWithoutAttendee(eq(10L), eq(3L), anyString(), anyString());
            verify(sessionRepository, never()).clearRecordingStartElected(anyLong());
        }
    }

    @Nested
    @DisplayName("termination fencing")
    class Termination {

        private final UUID claim = UUID.randomUUID();

        private CallSession terminating() {
            final CallSession session = session(CallSessionService.SESSION_TERMINATING);
            session.setTerminationClaimId(claim);
            session.setTerminationNotifyUserIds("3, ,4");
            return session;
        }

        @Test
        @DisplayName("leaving a terminating call reclaims the existing termination")
        void leave_terminating_reclaims() {
            stubSession(terminating());
            stubParticipant(3L, CallSessionService.PARTICIPANT_LEFT);
            when(sessionRepository.reclaimTermination(eq(10L), anyString(), any(UUID.class), eq(3L), any()))
                    .thenReturn(1);

            final CallSessionService.LeaveResult result = service.leaveOrBeginTermination(CALL_ID, 3L);

            assertThat(result.terminationOwner()).isTrue();
            assertThat(result.notifyUserIds()).containsExactly(3L, 4L);
        }

        @Test
        @DisplayName("leaving without having joined is forbidden")
        void leave_notJoined_forbidden() {
            stubSession(terminating());
            stubParticipant(3L, CallSessionService.PARTICIPANT_INVITED);
            assertThatThrownBy(() -> service.leaveOrBeginTermination(CALL_ID, 3L))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.FORBIDDEN));

            final CallSession active = session(CallSessionService.SESSION_ACTIVE);
            stubSession(active);
            assertThatThrownBy(() -> service.leaveOrBeginTermination(CALL_ID, 3L))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.FORBIDDEN));
        }

        @Test
        @DisplayName("renew, verify, advance and complete return false or null for stale claims")
        void staleClaims() {
            assertThat(service.renewTerminationOwnership(CALL_ID, null)).isNull();
            assertThat(service.verifyTerminationOwnership(CALL_ID, null)).isNull();
            assertThat(service.advanceTerminationStep(CALL_ID, null, TerminationStep.SUMMARY)).isFalse();
            assertThat(service.completeTermination(CALL_ID, null)).isFalse();

            stubSession(terminating());
            assertThat(service.renewTerminationOwnership(CALL_ID, claim)).isNull();
            assertThat(service.verifyTerminationOwnership(CALL_ID, UUID.randomUUID())).isNull();
            assertThat(service.advanceTerminationStep(CALL_ID, UUID.randomUUID(), TerminationStep.SUMMARY)).isFalse();

            when(sessionRepository.renewTerminationLease(eq(10L), anyString(), eq(claim), any())).thenReturn(1);
            when(sessionRepository.completeTermination(eq(10L), anyString(), anyString(), eq(claim))).thenReturn(0);
            assertThat(service.completeTermination(CALL_ID, claim)).isFalse();
            verify(participantRepository, never()).expireJoinedParticipants(any(), any(), any());
        }

        @Test
        @DisplayName("termination failures are recorded with derived and truncated messages")
        void recordTerminationFailure_messages() {
            service.recordTerminationFailure(CALL_ID, null, new RuntimeException("x"));
            service.recordTerminationRetry(CALL_ID, null, "x");
            stubSession(terminating());

            service.recordTerminationFailure(CALL_ID, claim, null);
            service.recordTerminationFailure(CALL_ID, claim, new IllegalStateException(" "));
            service.recordTerminationFailure(CALL_ID, claim, new RuntimeException("x".repeat(2500)));
            service.recordTerminationRetry(CALL_ID, claim, " ");
            service.recordTerminationRetry(CALL_ID, UUID.randomUUID(), "stale");

            verify(sessionRepository, org.mockito.Mockito.times(2))
                    .failTermination(eq(10L), anyString(), eq(claim), any(), eq("Unknown termination failure"));
            verify(sessionRepository)
                    .failTermination(eq(10L), anyString(), eq(claim), any(), eq("IllegalStateException"));
            verify(sessionRepository)
                    .failTermination(eq(10L), anyString(), eq(claim), any(), eq("x".repeat(2000)));
        }

        @Test
        @DisplayName("claimTerminationRetry reports ended calls and rejects calls not terminating")
        void claimTerminationRetry_variants() {
            final CallSession ended = session(CallSessionService.SESSION_ENDED);
            stubSession(ended);
            stubParticipant(3L, CallSessionService.PARTICIPANT_LEFT);
            assertThat(service.claimTerminationRetry(CALL_ID, 3L).ended()).isTrue();

            ended.setStatus(CallSessionService.SESSION_ACTIVE);
            assertThatThrownBy(() -> service.claimTerminationRetry(CALL_ID, 3L))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.CONFLICT));
        }

        @Test
        @DisplayName("claimDueTermination skips missing, non-terminating and unowned sessions")
        void claimDueTermination_skips() {
            when(sessionRepository.findByIdForLifecycle(10L))
                    .thenReturn(Optional.empty())
                    .thenReturn(Optional.of(session(CallSessionService.SESSION_ACTIVE)))
                    .thenReturn(Optional.of(terminating()));

            assertThat(service.claimDueTermination(10L)).isNull();
            assertThat(service.claimDueTermination(10L)).isNull();
            assertThat(service.claimDueTermination(10L)).isNull();
        }

        @Test
        @DisplayName("termination progress reports overall completion")
        void terminationProgress_complete() {
            final CallSessionService.TerminationProgress done =
                    new CallSessionService.TerminationProgress(true, true, true, true);
            final CallSessionService.TerminationProgress partial =
                    new CallSessionService.TerminationProgress(true, false, true, true);

            assertThat(done.allRequiredDone()).isTrue();
            assertThat(partial.isDone(TerminationStep.COMPLETE)).isFalse();
            assertThat(partial.isDone(TerminationStep.MEETING)).isTrue();
        }
    }

    @Nested
    @DisplayName("declineInvitation")
    class Decline {

        @Test
        @DisplayName("a decline that is no longer pending conflicts")
        void decline_notPending() {
            stubSession(session(CallSessionService.SESSION_CREATED));

            assertThatThrownBy(() -> service.declineInvitation(CALL_ID, 3L))
                    .satisfies(e -> assertThat(status(e)).isEqualTo(HttpStatus.CONFLICT));
        }

        @Test
        @DisplayName("the last decline on an active call begins termination")
        void decline_activeCall_beginsTermination() {
            stubSession(session(CallSessionService.SESSION_ACTIVE));
            when(participantRepository.declineIfInvited(10L, 3L, CallSessionService.PARTICIPANT_INVITED,
                    CallSessionService.PARTICIPANT_DECLINED)).thenReturn(1);
            when(participantRepository.findByCallSessionId(10L))
                    .thenReturn(List.of(participant(3L, CallSessionService.PARTICIPANT_DECLINED)));
            when(sessionRepository.beginTermination(eq(10L), anyString(), anyString(), anyString(),
                    any(UUID.class), eq(3L), any(), anyString())).thenReturn(1);

            final CallSessionService.DeclineResult result = service.declineInvitation(CALL_ID, 3L);

            assertThat(result.terminationOwner()).isTrue();
            assertThat(result.terminationClaimId()).isNotNull();
            assertThat(new CallSessionService.DeclineResult(List.of(1L), false).terminationClaimId()).isNull();
        }
    }

    @Nested
    @DisplayName("successful lifecycle paths")
    class SuccessPaths {

        private final UUID claim = UUID.randomUUID();

        private CallSession owned() {
            final CallSession session = session(CallSessionService.SESSION_TERMINATING);
            session.setTerminationClaimId(claim);
            return session;
        }

        @Test
        @DisplayName("attaching a meeting id activates the session")
        void attachChimeMeetingId_activates() {
            stubSession(session(CallSessionService.SESSION_CREATED));

            service.attachChimeMeetingId(CALL_ID, "meeting-1");

            verify(sessionRepository).activateIfJoinable(10L, "meeting-1",
                    CallSessionService.SESSION_CREATED, CallSessionService.SESSION_ACTIVE);
        }

        @Test
        @DisplayName("a patient may access their own calls by patient user id")
        void patientUserAccess_ownPatient() {
            service.requirePatientUserAccess(user(7L, Role.PATIENT), 7L);
        }

        @Test
        @DisplayName("leaving while others remain joined keeps the call open")
        void leave_othersRemain() {
            stubSession(session(CallSessionService.SESSION_ACTIVE));
            stubParticipant(3L, CallSessionService.PARTICIPANT_JOINED);
            when(participantRepository.countByCallSessionIdAndStatus(10L, CallSessionService.PARTICIPANT_JOINED))
                    .thenReturn(2L);

            final CallSessionService.LeaveResult result = service.leaveOrBeginTermination(CALL_ID, 3L);

            assertThat(result.terminationOwner()).isFalse();
            assertThat(result.remainingParticipants()).isEqualTo(2L);
        }

        @Test
        @DisplayName("an owning claim can verify, advance every step and complete")
        void owningClaim_advancesAndCompletes() {
            final CallSession session = owned();
            session.setTerminationSentimentAt(LocalDateTime.now());
            stubSession(session);
            when(sessionRepository.markTerminationSentiment(eq(10L), anyString(), eq(claim), any())).thenReturn(1);
            when(sessionRepository.markTerminationSummary(eq(10L), anyString(), eq(claim), any())).thenReturn(1);
            when(sessionRepository.markTerminationRecording(eq(10L), anyString(), eq(claim), any())).thenReturn(0);
            when(sessionRepository.markTerminationMeeting(eq(10L), anyString(), eq(claim), any())).thenReturn(1);
            when(sessionRepository.renewTerminationLease(eq(10L), anyString(), eq(claim), any())).thenReturn(1);
            when(sessionRepository.completeTermination(eq(10L), anyString(), anyString(), eq(claim))).thenReturn(1);

            final CallSessionService.TerminationProgress progress = service.verifyTerminationOwnership(CALL_ID, claim);
            assertThat(progress.isDone(TerminationStep.SENTIMENT)).isTrue();
            assertThat(progress.isDone(TerminationStep.SUMMARY)).isFalse();
            assertThat(progress.isDone(TerminationStep.RECORDING)).isFalse();
            assertThat(service.advanceTerminationStep(CALL_ID, claim, TerminationStep.SENTIMENT)).isTrue();
            assertThat(service.advanceTerminationStep(CALL_ID, claim, TerminationStep.SUMMARY)).isTrue();
            assertThat(service.advanceTerminationStep(CALL_ID, claim, TerminationStep.RECORDING)).isFalse();
            assertThat(service.advanceTerminationStep(CALL_ID, claim, TerminationStep.MEETING)).isTrue();
            assertThat(service.advanceTerminationStep(CALL_ID, claim, TerminationStep.COMPLETE)).isFalse();
            assertThat(service.completeTermination(CALL_ID, claim)).isTrue();
            verify(participantRepository).expireJoinedParticipants(10L,
                    CallSessionService.PARTICIPANT_JOINED, CallSessionService.PARTICIPANT_EXPIRED);
        }

        @Test
        @DisplayName("due termination ids use a minimum batch of one; null notify list deserializes empty")
        void dueTerminationIds_andEmptyNotifyList() {
            when(sessionRepository.findDueTerminationIds(CallSessionService.SESSION_TERMINATING, 1))
                    .thenReturn(List.of(10L));
            assertThat(service.findDueTerminationIds(0)).containsExactly(10L);

            when(sessionRepository.findByIdForLifecycle(10L)).thenReturn(Optional.of(owned()));
            when(sessionRepository.reclaimTermination(eq(10L), anyString(), any(UUID.class), any(), any()))
                    .thenReturn(1);
            final CallSessionService.TerminationClaim due = service.claimDueTermination(10L);
            assertThat(due.notifyUserIds()).isEmpty();
            assertThat(due.callId()).isEqualTo(CALL_ID);
        }

        @Test
        @DisplayName("an already-invited participant is reused when adding an authorized participant")
        void addAuthorizedParticipant_existingInvitee() {
            stubSession(session(CallSessionService.SESSION_ACTIVE));
            stubParticipant(2L, CallSessionService.PARTICIPANT_JOINED);
            when(participantRepository.findByCallSessionIdAndUserId(10L, 3L))
                    .thenReturn(Optional.of(participant(3L, CallSessionService.PARTICIPANT_INVITED)));
            when(patientRepository.findById(42L)).thenReturn(Optional.of(patient(7L)));

            final CallParticipant result =
                    service.addAuthorizedParticipant(CALL_ID, user(2L, Role.CAREGIVER), user(3L, Role.ADMIN));

            assertThat(result.getStatus()).isEqualTo(CallSessionService.PARTICIPANT_INVITED);
        }

        @Test
        @DisplayName("scheduled visits pass for admins and for the assigned caregiver")
        void scheduledVisit_allowed() {
            when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient(7L)));
            when(caregiverLinkService.hasAccessToPatient(2L, 7L)).thenReturn(true);
            final ScheduledVisit visit = new ScheduledVisit();
            visit.setPatientId(42L);
            visit.setCaregiverId(98L);
            when(scheduledVisitRepository.findById(5L)).thenReturn(Optional.of(visit));
            when(caregiverRepository.findByUserId(2L)).thenReturn(Optional.of(Caregiver.builder().id(98L).build()));
            final CallSession existing = session(CallSessionService.SESSION_CREATED);
            existing.setScheduledVisitId(5L);
            when(sessionRepository.findByCallId(CALL_ID)).thenReturn(Optional.of(existing));

            assertThat(service.createSession(CALL_ID, 7L, null, 5L, user(2L, Role.CAREGIVER))).isSameAs(existing);
            existing.setCreatedByUserId(1L);
            assertThat(service.createSession(CALL_ID, 7L, null, 5L, user(1L, Role.ADMIN))).isSameAs(existing);
        }
    }
}
