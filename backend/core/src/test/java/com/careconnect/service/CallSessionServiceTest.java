package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.exception.AppException;
import com.careconnect.model.CallParticipant;
import com.careconnect.model.CallSession;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.repository.CallParticipantRepository;
import com.careconnect.repository.CallSessionRepository;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import com.careconnect.security.Role;
import java.util.Optional;
import java.time.LocalDateTime;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CallSessionServiceTest {

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
        service = new CallSessionService(
                sessionRepository,
                participantRepository,
                patientRepository,
                userRepository,
                caregiverLinkService,
                familyMemberService,
                scheduledVisitRepository,
                caregiverRepository);
        lenient().when(sessionRepository.save(any(CallSession.class))).thenAnswer(invocation -> {
            CallSession session = invocation.getArgument(0);
            if (session.getId() == null) {
                session.setId(10L);
            }
            return session;
        });
        lenient().when(participantRepository.save(any(CallParticipant.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
    }

    @Test
    void createSession_mapsPatientUserIdToPatientEntityIdAndSeedsBothParticipants() {
        final User creator = user(2L, Role.CAREGIVER);
        final User patientUser = user(7L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(42L);
        patient.setUser(patientUser);
        when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient));
        when(caregiverLinkService.hasAccessToPatient(2L, 7L)).thenReturn(true);
        when(userRepository.findById(7L)).thenReturn(Optional.of(patientUser));
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.empty());
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.empty());
        when(participantRepository.findByCallSessionIdAndUserId(10L, 7L))
                .thenReturn(Optional.empty());

        final CallSession session = service.createSession(
                "call-1", 7L, 7L, null, creator);

        assertThat(session.getPatientId()).isEqualTo(42L);
        assertThat(session.getCreatedByUserId()).isEqualTo(2L);
        verify(participantRepository).insertIfAbsent(10L, 2L, 2L, "INVITED");
        verify(participantRepository).insertIfAbsent(10L, 7L, 2L, "INVITED");
    }

    @Test
    void createSession_rejectsCaregiverWithoutPatientRelationship() {
        final User creator = user(2L, Role.CAREGIVER);
        final Patient patient = new Patient();
        patient.setId(42L);
        when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient));
        when(caregiverLinkService.hasAccessToPatient(2L, 7L)).thenReturn(false);

        assertThatThrownBy(() -> service.createSession(
                "call-1", 7L, 7L, null, creator))
                .isInstanceOf(AppException.class);
        verify(sessionRepository, never()).save(any());
    }

    @Test
    void ensureJoinAuthorized_createsSessionWhenMissingAndPatientProvided() {
        final User creator = user(2L, Role.CAREGIVER);
        final User patientUser = user(7L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(42L);
        patient.setUser(patientUser);
        when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient));
        when(caregiverLinkService.hasAccessToPatient(2L, 7L)).thenReturn(true);
        when(userRepository.findById(7L)).thenReturn(Optional.of(patientUser));
        when(sessionRepository.findByCallId("call-1"))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(session(10L, 42L)));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(participant(
                        2L, CallSessionService.PARTICIPANT_INVITED)));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 7L))
                .thenReturn(Optional.empty());

        final CallSession joined = service.ensureJoinAuthorized(
                "call-1", creator, 7L, 7L, null);

        assertThat(joined.getId()).isEqualTo(10L);
        verify(sessionRepository).save(any(CallSession.class));
    }

    @Test
    void ensureJoinAuthorized_enrollsCareLinkedUserMissingParticipantRow() {
        final User invitee = user(9L, Role.CAREGIVER);
        final CallSession existing = session(10L, 42L);
        existing.setCreatedByUserId(2L);
        final User patientUser = user(7L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(42L);
        patient.setUser(patientUser);
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(existing));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 9L))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(participant(
                        9L, CallSessionService.PARTICIPANT_INVITED)));
        when(patientRepository.findById(42L)).thenReturn(Optional.of(patient));
        when(caregiverLinkService.hasAccessToPatient(9L, 7L)).thenReturn(true);

        final CallSession joined = service.ensureJoinAuthorized(
                "call-1", invitee, null, null, null);

        assertThat(joined.getId()).isEqualTo(10L);
        verify(participantRepository).insertIfAbsent(10L, 9L, 2L, "INVITED");
    }

    @Test
    void requireJoinAuthorized_rejectsUserWithoutParticipantRow() {
        final CallSession session = session(10L, 42L);
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 99L))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.requireJoinAuthorized("call-1", 99L))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("not authorized");
    }

    @Test
    void requireJoinAuthorized_rejectsDeclinedOrLeftParticipantUntilReinvited() {
        final CallSession session = session(10L, 42L);
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.of(participant(
                        2L, CallSessionService.PARTICIPANT_DECLINED)));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 3L))
                .thenReturn(Optional.of(participant(
                        3L, CallSessionService.PARTICIPANT_LEFT)));

        assertThatThrownBy(() -> service.requireJoinAuthorized("call-1", 2L))
                .isInstanceOf(AppException.class);
        assertThatThrownBy(() -> service.requireJoinAuthorized("call-1", 3L))
                .isInstanceOf(AppException.class);
    }

    @Test
    void recordJoin_persistsMeetingAndParticipantState() {
        final CallSession session = session(10L, 42L);
        final CallParticipant participant = new CallParticipant();
        participant.setCallSessionId(10L);
        participant.setUserId(2L);
        participant.setStatus(CallSessionService.PARTICIPANT_INVITED);
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));
        when(sessionRepository.activateIfJoinable(
                10L, "meeting-123", CallSessionService.SESSION_CREATED,
                CallSessionService.SESSION_ACTIVE)).thenReturn(1);
        when(participantRepository.markJoinedIfInvited(
                10L, 2L, CallSessionService.PARTICIPANT_INVITED,
                CallSessionService.PARTICIPANT_JOINED)).thenReturn(1);

        service.recordJoin(session, 2L, "meeting-123");

        verify(sessionRepository).activateIfJoinable(
                10L, "meeting-123", CallSessionService.SESSION_CREATED,
                CallSessionService.SESSION_ACTIVE);
        verify(participantRepository).markJoinedIfInvited(
                10L, 2L, CallSessionService.PARTICIPANT_INVITED,
                CallSessionService.PARTICIPANT_JOINED);
    }

    @Test
    void requireActiveParticipant_rejectsInvitedParticipant() {
        final CallSession session = session(10L, 42L);
        final CallParticipant participant = new CallParticipant();
        participant.setCallSessionId(10L);
        participant.setUserId(2L);
        participant.setStatus(CallSessionService.PARTICIPANT_INVITED);
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.of(participant));

        assertThatThrownBy(() -> service.requireActiveParticipant("call-1", 2L))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("must join");
    }

    @Test
    void transcriptUpload_allowsHistoricalParticipantWithinGrace() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_ENDED);
        session.setEndedAt(LocalDateTime.now(java.time.ZoneOffset.UTC).minusSeconds(30));
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.of(participant(
                        2L, CallSessionService.PARTICIPANT_LEFT)));

        assertThat(service.requireTranscriptUploadParticipant("call-1", 2L))
                .isSameAs(session);
    }

    @Test
    void transcriptUpload_rejectsHistoricalParticipantAfterGrace() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_ENDED);
        session.setEndedAt(LocalDateTime.now(java.time.ZoneOffset.UTC).minusMinutes(10));
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.of(participant(
                        2L, CallSessionService.PARTICIPANT_LEFT)));

        assertThatThrownBy(() ->
                service.requireTranscriptUploadParticipant("call-1", 2L))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("grace period");
    }

    @Test
    void transcriptUpload_allowsHistoricalParticipantWhileTerminating() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_TERMINATING);
        session.setEndedAt(null);
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.of(participant(
                        2L, CallSessionService.PARTICIPANT_LEFT)));

        assertThat(service.requireTranscriptUploadParticipant("call-1", 2L))
                .isSameAs(session);
    }

    @Test
    void requireRecordingAccess_allowsLinkedCaregiverWithoutJoinHistory() {
        final CallSession session = session(10L, 42L);
        final User caregiver = user(9L, Role.CAREGIVER);
        final Patient patient = new Patient();
        patient.setId(42L);
        patient.setUser(user(7L, Role.PATIENT));
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 9L))
                .thenReturn(Optional.empty());
        when(patientRepository.findById(42L)).thenReturn(Optional.of(patient));
        when(caregiverLinkService.hasAccessToPatient(9L, 7L)).thenReturn(true);

        assertThat(service.requireRecordingAccess("call-1", caregiver)).isSameAs(session);
    }

    @Test
    void requireRecordingAccess_rejectsUnrelatedUser() {
        final CallSession session = session(10L, 42L);
        final User stranger = user(9L, Role.CAREGIVER);
        final Patient patient = new Patient();
        patient.setId(42L);
        patient.setUser(user(7L, Role.PATIENT));
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 9L))
                .thenReturn(Optional.empty());
        when(patientRepository.findById(42L)).thenReturn(Optional.of(patient));
        when(caregiverLinkService.hasAccessToPatient(9L, 7L)).thenReturn(false);

        assertThatThrownBy(() -> service.requireRecordingAccess("call-1", stranger))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("not authorized");
    }

    @Test
    void leaveOrBeginTermination_rejectsInvitedUserDuringTerminating() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_TERMINATING);
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 9L))
                .thenReturn(Optional.of(participant(
                        9L, CallSessionService.PARTICIPANT_INVITED)));

        assertThatThrownBy(() -> service.leaveOrBeginTermination("call-1", 9L))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("must join");
    }

    @Test
    void revertJoinAfterChimeFailure_revertsJoinedAndClearsElection() {
        final CallSession session = session(10L, 42L);
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.revertJoinedToInvitedWithoutAttendee(
                10L, 2L, CallSessionService.PARTICIPANT_JOINED,
                CallSessionService.PARTICIPANT_INVITED)).thenReturn(1);
        when(participantRepository.countByCallSessionIdAndStatus(
                10L, CallSessionService.PARTICIPANT_JOINED)).thenReturn(0L);

        service.revertJoinAfterChimeFailure("call-1", 2L);

        verify(sessionRepository).clearRecordingStartElected(10L);
    }

    @Test
    void createSession_existingRowsAreIdempotent() {
        final User creator = user(2L, Role.CAREGIVER);
        final User patientUser = user(7L, Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(42L);
        patient.setUser(patientUser);
        final CallSession existing = session(10L, 42L);
        existing.setCreatedByUserId(2L);
        when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient));
        when(caregiverLinkService.hasAccessToPatient(2L, 7L)).thenReturn(true);
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(existing));

        assertThat(service.createSession("call-1", 7L, 7L, null, creator))
                .isSameAs(existing);
        verify(sessionRepository, never()).save(any(CallSession.class));
        verify(participantRepository, never()).save(any(CallParticipant.class));
    }

    @Test
    void createSession_activeReplayDoesNotReinviteOrAddParticipants() {
        final User creator = user(2L, Role.CAREGIVER);
        final Patient patient = new Patient();
        patient.setId(42L);
        patient.setUser(user(7L, Role.PATIENT));
        final CallSession existing = session(10L, 42L);
        existing.setCreatedByUserId(2L);
        existing.setStatus(CallSessionService.SESSION_ACTIVE);
        when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient));
        when(caregiverLinkService.hasAccessToPatient(2L, 7L)).thenReturn(true);
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(existing));

        assertThat(service.createSession("call-1", 7L, 99L, null, creator))
                .isSameAs(existing);

        verify(userRepository, never()).findById(99L);
        verify(participantRepository, never()).insertIfAbsent(
                any(), any(), any(), any());
        verify(participantRepository, never()).reinviteIfInactive(
                any(), any(), any(), any(), any(), any());
    }

    @Test
    void createSession_rejectsScheduledVisitOwnedByAnotherPatient() {
        final User creator = user(2L, Role.CAREGIVER);
        final Patient patient = new Patient();
        patient.setId(42L);
        patient.setUser(user(7L, Role.PATIENT));
        final ScheduledVisit visit = new ScheduledVisit();
        visit.setId(99L);
        visit.setPatientId(77L);
        when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient));
        when(caregiverLinkService.hasAccessToPatient(2L, 7L)).thenReturn(true);
        when(scheduledVisitRepository.findById(99L)).thenReturn(Optional.of(visit));

        assertThatThrownBy(() -> service.createSession(
                "call-1", 7L, null, 99L, creator))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("does not belong");
        verify(sessionRepository, never()).insertIfAbsent(
                any(), any(), any(), any(), any());
    }

    @Test
    void recordJoin_doesNotResurrectTerminatingSession() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_TERMINATING);
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));
        when(sessionRepository.activateIfJoinable(
                10L, "meeting-123", CallSessionService.SESSION_CREATED,
                CallSessionService.SESSION_ACTIVE)).thenReturn(0);

        assertThatThrownBy(() -> service.recordJoin(session, 2L, "meeting-123"))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("no longer joinable");
        verify(participantRepository, never()).markJoinedIfInvited(
                any(), any(), any(), any());
    }

    @Test
    void leaveOrBeginTermination_isIdempotentAfterEnded() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_ENDED);
        final CallParticipant participant = new CallParticipant();
        participant.setStatus(CallSessionService.PARTICIPANT_LEFT);
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.of(participant));

        final CallSessionService.LeaveResult result =
                service.leaveOrBeginTermination("call-1", 2L);

        assertThat(result.ended()).isTrue();
        assertThat(result.terminationOwner()).isFalse();
        verify(sessionRepository, never()).beginTermination(
                any(), any(), any(), any(), any(), any(), any(LocalDateTime.class), any());
    }

    @Test
    void declineInvitation_cancelsUnansweredSessionWhenNoValidParticipantsRemain() {
        final CallSession session = session(10L, 42L);
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));
        when(participantRepository.declineIfInvited(
                10L, 7L, CallSessionService.PARTICIPANT_INVITED,
                CallSessionService.PARTICIPANT_DECLINED)).thenReturn(1);

        final CallSessionService.DeclineResult result =
                service.declineInvitation("call-1", 7L);
        assertThat(result.notifyUserIds()).isEmpty();
        assertThat(result.terminationOwner()).isFalse();
        verify(sessionRepository).cancelIfNotActive(
                10L, CallSessionService.SESSION_CREATED,
                CallSessionService.SESSION_CANCELLED);
        verify(sessionRepository, never()).beginTermination(
                any(), any(), any(), any(), any(), any(), any(LocalDateTime.class), any());
    }

    @Test
    void declineInvitation_keepsSessionOpenForOtherInvitedAndJoinedParticipants() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_ACTIVE);
        final CallParticipant invited =
                participant(3L, CallSessionService.PARTICIPANT_INVITED);
        final CallParticipant joined =
                participant(4L, CallSessionService.PARTICIPANT_JOINED);
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));
        when(participantRepository.declineIfInvited(
                10L, 7L, CallSessionService.PARTICIPANT_INVITED,
                CallSessionService.PARTICIPANT_DECLINED)).thenReturn(1);
        when(participantRepository.findByCallSessionId(10L))
                .thenReturn(java.util.List.of(invited, joined));
        when(participantRepository.countByCallSessionIdAndStatus(
                10L, CallSessionService.PARTICIPANT_JOINED)).thenReturn(1L);
        when(participantRepository.countByCallSessionIdAndStatus(
                10L, CallSessionService.PARTICIPANT_INVITED)).thenReturn(1L);

        final CallSessionService.DeclineResult result =
                service.declineInvitation("call-1", 7L);

        assertThat(result.notifyUserIds()).containsExactly(3L, 4L);
        assertThat(result.terminationOwner()).isFalse();
        verify(sessionRepository, never()).beginTermination(
                any(), any(), any(), any(), any(), any(), any(LocalDateTime.class), any());
        verify(sessionRepository, never()).cancelIfNotActive(any(), any(), any());
    }

    @Test
    void leaveOrBeginTermination_capturesRecipientsAndReturnsFencedClaim() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_ACTIVE);
        final CallParticipant actor = participant(2L, CallSessionService.PARTICIPANT_JOINED);
        final CallParticipant joined = participant(7L, CallSessionService.PARTICIPANT_JOINED);
        final CallParticipant invited = participant(9L, CallSessionService.PARTICIPANT_INVITED);
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.of(actor));
        when(participantRepository.countByCallSessionIdAndStatus(
                10L, CallSessionService.PARTICIPANT_JOINED)).thenReturn(1L);
        when(participantRepository.findByCallSessionId(10L))
                .thenReturn(java.util.List.of(actor, joined, invited));
        when(sessionRepository.beginTermination(
                eq(10L), eq(CallSessionService.SESSION_CREATED),
                eq(CallSessionService.SESSION_ACTIVE),
                eq(CallSessionService.SESSION_TERMINATING),
                any(), eq(2L), any(LocalDateTime.class), eq("7,9"))).thenReturn(1);

        final CallSessionService.LeaveResult result =
                service.leaveOrBeginTermination("call-1", 2L);

        assertThat(result.terminationOwner()).isTrue();
        assertThat(result.terminationClaimId()).isNotNull();
        assertThat(result.notifyUserIds()).containsExactly(7L, 9L);
    }

    @Test
    void claimTerminationRetry_reusesImmutableRecipientsWithNewFence() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_TERMINATING);
        session.setTerminationNotifyUserIds("7,9");
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.of(participant(2L, CallSessionService.PARTICIPANT_LEFT)));
        when(sessionRepository.reclaimTermination(
                eq(10L), eq(CallSessionService.SESSION_TERMINATING),
                any(), eq(2L), any(LocalDateTime.class))).thenReturn(1);

        final CallSessionService.LeaveResult result =
                service.claimTerminationRetry("call-1", 2L);

        assertThat(result.terminationOwner()).isTrue();
        assertThat(result.terminationClaimId()).isNotNull();
        assertThat(result.notifyUserIds()).containsExactly(7L, 9L);
    }

    @Test
    void completeTermination_rejectsStaleClaimWithoutExpiringParticipants() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_TERMINATING);
        final java.util.UUID staleClaim = java.util.UUID.randomUUID();
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));
        when(sessionRepository.renewTerminationLease(
                eq(10L), eq(CallSessionService.SESSION_TERMINATING),
                eq(staleClaim), any(LocalDateTime.class))).thenReturn(0);

        assertThat(service.completeTermination("call-1", staleClaim)).isFalse();
        verify(sessionRepository, never()).completeTermination(
                any(), any(), any(), any());
        verify(participantRepository, never()).expireJoinedParticipants(any(), any(), any());
    }

    @Test
    void renewTerminationOwnership_rejectsExpiredForeignClaim() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_TERMINATING);
        session.setTerminationClaimId(java.util.UUID.randomUUID());
        final java.util.UUID otherClaim = java.util.UUID.randomUUID();
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));

        assertThat(service.renewTerminationOwnership("call-1", otherClaim)).isNull();
        verify(sessionRepository, never()).renewTerminationLease(
                any(), any(), any(), any(LocalDateTime.class));
    }

    @Test
    void renewTerminationOwnership_extendsLeaseAndReturnsStepProgress() {
        final java.util.UUID claimId = java.util.UUID.randomUUID();
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_TERMINATING);
        session.setTerminationClaimId(claimId);
        session.setTerminationSentimentAt(LocalDateTime.now());
        session.setTerminationSummaryAt(LocalDateTime.now());
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));
        when(sessionRepository.renewTerminationLease(
                eq(10L), eq(CallSessionService.SESSION_TERMINATING),
                eq(claimId), any(LocalDateTime.class))).thenReturn(1);

        final CallSessionService.TerminationProgress progress =
                service.renewTerminationOwnership("call-1", claimId);

        assertThat(progress).isNotNull();
        assertThat(progress.sentimentDone()).isTrue();
        assertThat(progress.summaryDone()).isTrue();
        assertThat(progress.recordingDone()).isFalse();
        assertThat(progress.meetingDone()).isFalse();
    }

    @Test
    void advanceTerminationStep_isTokenFencedCompareAndSet() {
        final java.util.UUID claimId = java.util.UUID.randomUUID();
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_TERMINATING);
        session.setTerminationClaimId(claimId);
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));
        when(sessionRepository.markTerminationRecording(
                eq(10L), eq(CallSessionService.SESSION_TERMINATING),
                eq(claimId), any(LocalDateTime.class))).thenReturn(1);

        assertThat(service.advanceTerminationStep(
                "call-1", claimId, com.careconnect.model.TerminationStep.RECORDING))
                .isTrue();
        verify(sessionRepository).markTerminationRecording(
                eq(10L), eq(CallSessionService.SESSION_TERMINATING),
                eq(claimId), any(LocalDateTime.class));
    }

    @Test
    void advanceTerminationStep_staleOwnerHasZeroSideEffects() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_TERMINATING);
        session.setTerminationClaimId(java.util.UUID.randomUUID());
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));

        assertThat(service.advanceTerminationStep(
                "call-1",
                java.util.UUID.randomUUID(),
                com.careconnect.model.TerminationStep.MEETING))
                .isFalse();
        verify(sessionRepository, never()).markTerminationMeeting(
                any(), any(), any(), any(LocalDateTime.class));
    }

    @Test
    void recordTerminationRetry_ignoresStaleOwner() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_TERMINATING);
        session.setTerminationClaimId(java.util.UUID.randomUUID());
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));

        service.recordTerminationRetry("call-1", java.util.UUID.randomUUID(), "retry");

        verify(sessionRepository, never()).failTermination(
                any(), any(), any(), any(LocalDateTime.class), any());
    }

    @Test
    void claimDueTermination_reclaimsExpiredLeaseWithoutResettingProgress() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_TERMINATING);
        session.setTerminationNotifyUserIds("7");
        session.setTerminationSentimentAt(LocalDateTime.now());
        session.setTerminationLeaseUntil(LocalDateTime.now().minusMinutes(5));
        when(sessionRepository.findByIdForLifecycle(10L)).thenReturn(Optional.of(session));
        when(sessionRepository.reclaimTermination(
                eq(10L), eq(CallSessionService.SESSION_TERMINATING),
                any(), eq(null), any(LocalDateTime.class))).thenReturn(1);

        final CallSessionService.TerminationClaim claim = service.claimDueTermination(10L);

        assertThat(claim).isNotNull();
        assertThat(claim.callId()).isEqualTo("call-1");
        assertThat(claim.notifyUserIds()).containsExactly(7L);
        assertThat(session.getTerminationSentimentAt()).isNotNull();
        verify(sessionRepository, never()).markTerminationSentiment(
                any(), any(), any(), any(LocalDateTime.class));
    }


    @Test
    void requireHistoricalParticipant_rejectsInvitedAndDeclinedParticipants() {
        final CallSession session = session(10L, 42L);
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.of(participant(
                        2L, CallSessionService.PARTICIPANT_INVITED)));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 3L))
                .thenReturn(Optional.of(participant(
                        3L, CallSessionService.PARTICIPANT_DECLINED)));

        assertThatThrownBy(() -> service.requireHistoricalParticipant("call-1", 2L))
                .isInstanceOf(AppException.class);
        assertThatThrownBy(() -> service.requireHistoricalParticipant("call-1", 3L))
                .isInstanceOf(AppException.class);
    }

    @Test
    void requireHistoricalParticipant_acceptsJoinedLeftAndExpiredParticipants() {
        final CallSession session = session(10L, 42L);
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(eq(10L), any()))
                .thenAnswer(invocation -> Optional.of(participant(
                        invocation.getArgument(1),
                        invocation.getArgument(1).equals(2L)
                                ? CallSessionService.PARTICIPANT_JOINED
                                : invocation.getArgument(1).equals(3L)
                                        ? CallSessionService.PARTICIPANT_LEFT
                                        : CallSessionService.PARTICIPANT_EXPIRED)));

        assertThat(service.requireHistoricalParticipant("call-1", 2L)).isSameAs(session);
        assertThat(service.requireHistoricalParticipant("call-1", 3L)).isSameAs(session);
        assertThat(service.requireHistoricalParticipant("call-1", 4L)).isSameAs(session);
    }

    @Test
    void addAuthorizedParticipant_reinvitesDeclinedParticipantAtomically() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_ACTIVE);
        final User inviter = user(2L, Role.CAREGIVER);
        final User invitee = user(7L, Role.PATIENT);
        final CallParticipant declined =
                participant(7L, CallSessionService.PARTICIPANT_DECLINED);
        final CallParticipant reinvited =
                participant(7L, CallSessionService.PARTICIPANT_INVITED);
        final java.util.concurrent.atomic.AtomicInteger participantLookup =
                new java.util.concurrent.atomic.AtomicInteger();
        final Patient patient = new Patient();
        patient.setUser(invitee);
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.of(participant(
                        2L, CallSessionService.PARTICIPANT_JOINED)));
        when(patientRepository.findById(42L)).thenReturn(Optional.of(patient));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 7L))
                .thenAnswer(invocation -> participantLookup.getAndIncrement() == 0
                        ? Optional.of(declined)
                        : Optional.of(reinvited));
        when(participantRepository.reinviteIfInactive(
                10L, 7L, 2L,
                CallSessionService.PARTICIPANT_INVITED,
                CallSessionService.PARTICIPANT_LEFT,
                CallSessionService.PARTICIPANT_DECLINED)).thenReturn(1);

        assertThat(service.addAuthorizedParticipant("call-1", inviter, invitee).getStatus())
                .isEqualTo(CallSessionService.PARTICIPANT_INVITED);
    }

    @Test
    void claimTerminationRetry_rejectsInviteeWithoutHistoricalAccess() {
        final CallSession session = session(10L, 42L);
        session.setStatus(CallSessionService.SESSION_TERMINATING);
        when(sessionRepository.findByCallIdForLifecycle("call-1"))
                .thenReturn(Optional.of(session));
        when(sessionRepository.findByCallId("call-1")).thenReturn(Optional.of(session));
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.of(participant(
                        2L, CallSessionService.PARTICIPANT_INVITED)));

        assertThatThrownBy(() -> service.claimTerminationRetry("call-1", 2L))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("historical");
        verify(sessionRepository, never()).reclaimTermination(
                any(), any(), any(), any(), any(LocalDateTime.class));
    }

    private static User user(Long id, Role role) {
        User user = new User();
        user.setId(id);
        user.setRole(role);
        return user;
    }

    private static CallSession session(Long id, Long patientId) {
        CallSession session = new CallSession();
        session.setId(id);
        session.setCallId("call-1");
        session.setPatientId(patientId);
        session.setStatus(CallSessionService.SESSION_CREATED);
        return session;
    }

    private static CallParticipant participant(Long userId, String status) {
        CallParticipant participant = new CallParticipant();
        participant.setCallSessionId(10L);
        participant.setUserId(userId);
        participant.setStatus(status);
        return participant;
    }
}
