package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.exception.AppException;
import com.careconnect.model.CallParticipant;
import com.careconnect.model.CallSession;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.CallParticipantRepository;
import com.careconnect.repository.CallSessionRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import java.util.Optional;
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

    private CallSessionService service;

    @BeforeEach
    void setUp() {
        service = new CallSessionService(
                sessionRepository,
                participantRepository,
                patientRepository,
                userRepository,
                caregiverLinkService,
                familyMemberService);
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
        verify(participantRepository).findByCallSessionIdAndUserId(10L, 2L);
        verify(participantRepository).findByCallSessionIdAndUserId(10L, 7L);
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
    void recordJoin_persistsMeetingAndParticipantState() {
        final CallSession session = session(10L, 42L);
        final CallParticipant participant = new CallParticipant();
        participant.setCallSessionId(10L);
        participant.setUserId(2L);
        participant.setStatus(CallSessionService.PARTICIPANT_INVITED);
        when(participantRepository.findByCallSessionIdAndUserId(10L, 2L))
                .thenReturn(Optional.of(participant));

        service.recordJoin(session, 2L, "meeting-123");

        assertThat(session.getChimeMeetingId()).isEqualTo("meeting-123");
        assertThat(session.getStatus()).isEqualTo(CallSessionService.SESSION_ACTIVE);
        assertThat(participant.getStatus()).isEqualTo(CallSessionService.PARTICIPANT_JOINED);
        assertThat(participant.getJoinedAt()).isNotNull();
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
}
