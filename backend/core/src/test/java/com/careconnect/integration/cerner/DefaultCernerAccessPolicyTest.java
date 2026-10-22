package com.careconnect.integration.cerner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class DefaultCernerAccessPolicyTest {

    private final UserRepository users = mock(UserRepository.class);
    private final PatientRepository patients = mock(PatientRepository.class);
    private final AuthorizationService authorization = mock(AuthorizationService.class);
    private final DefaultCernerAccessPolicy policy =
            new DefaultCernerAccessPolicy(users, patients, authorization);
    private final User caller = mock(User.class);
    private final User patientUser = mock(User.class);
    private final Patient patient = mock(Patient.class);

    @BeforeEach
    void setUpLinkedRecords() {
        when(users.findByEmail("clinician@example.test")).thenReturn(Optional.of(caller));
        when(patients.findById(42L)).thenReturn(Optional.of(patient));
        when(patient.getUser()).thenReturn(patientUser);
        when(patientUser.getId()).thenReturn(84L);
    }

    @Test
    void delegatesToSharedAuthorizationPolicy() throws Exception {
        assertThat(policy.canView("clinician@example.test", 42L)).isTrue();
        verify(authorization).requirePatientAccess(caller, 84L);
    }

    @Test
    void deniesMissingCallerOrPatientIdentity() {
        when(users.findByEmail("missing@example.test")).thenReturn(Optional.empty());
        when(patient.getUser()).thenReturn(null);

        assertThat(policy.canView("missing@example.test", 42L)).isFalse();
        assertThat(policy.canView("clinician@example.test", 42L)).isFalse();
    }

    @Test
    void convertsSharedAuthorizationFailureToDeniedDecision() throws Exception {
        doThrow(new UnauthorizedException("denied"))
                .when(authorization).requirePatientAccess(caller, 84L);

        assertThat(policy.canView("clinician@example.test", 42L)).isFalse();
    }
}
