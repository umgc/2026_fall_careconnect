package com.careconnect.service;

import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CallPatientResolverTest {

    @Mock
    private CallTelemetryService callTelemetryService;
    @Mock
    private UserRepository userRepository;
    @Mock
    private PatientRepository patientRepository;

    private CallPatientResolver resolver;

    @BeforeEach
    void setUp() {
        resolver = new CallPatientResolver(
                callTelemetryService, userRepository, patientRepository);
    }

    @Test
    void requirePatientId_mapsPatientJoinUserToPatientEntity() {
        final CallTelemetryEvent join = join(7L);
        final User user = new User();
        user.setId(7L);
        user.setRole(Role.PATIENT);
        final Patient patient = new Patient();
        patient.setId(42L);
        when(callTelemetryService.getTelemetryForCall("call-1")).thenReturn(List.of(join));
        when(userRepository.findById(7L)).thenReturn(Optional.of(user));
        when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient));

        assertThat(resolver.requirePatientId("call-1")).isEqualTo(42L);
    }

    @Test
    void requirePatientId_rejectsAmbiguousPatientParticipants() {
        final User first = patientUser(7L);
        final User second = patientUser(8L);
        when(callTelemetryService.getTelemetryForCall("call-1"))
                .thenReturn(List.of(join(7L), join(8L)));
        when(userRepository.findById(7L)).thenReturn(Optional.of(first));
        when(userRepository.findById(8L)).thenReturn(Optional.of(second));
        when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient(42L)));
        when(patientRepository.findByUserId(8L)).thenReturn(Optional.of(patient(43L)));

        assertThatThrownBy(() -> resolver.requirePatientId("call-1"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("exactly one patient");
    }

    @Test
    void requirePatientId_ignoresFailedJoinAttempts() {
        final CallTelemetryEvent failed = join(8L);
        failed.setStatus("ERROR");
        when(callTelemetryService.getTelemetryForCall("call-1"))
                .thenReturn(List.of(failed, join(7L)));
        when(userRepository.findById(7L)).thenReturn(Optional.of(patientUser(7L)));
        when(patientRepository.findByUserId(7L)).thenReturn(Optional.of(patient(42L)));

        assertThat(resolver.requirePatientId("call-1")).isEqualTo(42L);
    }

    private static CallTelemetryEvent join(final Long actorUserId) {
        final CallTelemetryEvent event = new CallTelemetryEvent();
        event.setEventType("CALL_JOIN");
        event.setActorUserId(actorUserId);
        event.setStatus("SUCCESS");
        return event;
    }

    private static User patientUser(final Long id) {
        final User user = new User();
        user.setId(id);
        user.setRole(Role.PATIENT);
        return user;
    }

    private static Patient patient(final Long id) {
        final Patient patient = new Patient();
        patient.setId(id);
        return patient;
    }
}
