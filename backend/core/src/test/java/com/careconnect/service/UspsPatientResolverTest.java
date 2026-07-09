package com.careconnect.service;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.UnauthorizedException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UspsPatientResolverTest {

    @Mock
    private UserRepository userRepository;

    private UspsPatientResolver resolver;
    private User currentUser;

    @BeforeEach
    void setUp() {
        resolver = new UspsPatientResolver(userRepository);
        currentUser = org.mockito.Mockito.mock(User.class);
    }

    @Test
    @DisplayName("defaults to current user when no identifier is provided")
    void resolvePatient_noIdentifier_returnsCurrentUser() throws Exception {
        User resolved = resolver.resolvePatient(null, null, currentUser);
        assertThat(resolved).isEqualTo(currentUser);
    }

    @Test
    @DisplayName("resolves patient by email")
    void resolvePatient_byEmail_returnsPatient() throws Exception {
        User patient = org.mockito.Mockito.mock(User.class);
        when(patient.isPatient()).thenReturn(true);
        when(userRepository.findByEmail("patient@example.com")).thenReturn(Optional.of(patient));

        User resolved = resolver.resolvePatient("patient@example.com", null, currentUser);
        assertThat(resolved).isEqualTo(patient);
    }

    @Test
    @DisplayName("resolves patient by numeric database id via legacy userId param")
    void resolvePatient_byNumericId_returnsPatient() throws Exception {
        User patient = org.mockito.Mockito.mock(User.class);
        when(patient.isPatient()).thenReturn(true);
        when(userRepository.findByEmail("7")).thenReturn(Optional.empty());
        when(userRepository.findById(7L)).thenReturn(Optional.of(patient));

        User resolved = resolver.resolvePatient(null, "7", currentUser);
        assertThat(resolved).isEqualTo(patient);
    }

    @Test
    @DisplayName("throws when identifier does not match any patient")
    void resolvePatient_unknownIdentifier_throwsUnauthorized() {
        when(userRepository.findByEmail("missing@example.com")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> resolver.resolvePatient("missing@example.com", null, currentUser))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("No patient found for identifier");
    }

    @Test
    @DisplayName("rejects demo-user identifier")
    void resolvePatient_demoUser_throwsUnauthorized() {
        assertThatThrownBy(() -> resolver.resolvePatient("demo-user", null, currentUser))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("Invalid patient identifier");
    }

    @Test
    @DisplayName("rejects explicit identifier that resolves to a non-patient role")
    void resolvePatient_nonPatientRole_throwsUnauthorized() {
        User caregiver = org.mockito.Mockito.mock(User.class);
        when(caregiver.isPatient()).thenReturn(false);
        when(userRepository.findByEmail("caregiver@example.com")).thenReturn(Optional.of(caregiver));

        assertThatThrownBy(() -> resolver.resolvePatient("caregiver@example.com", null, currentUser))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("does not refer to a patient");
    }
}
