package com.careconnect.controller;

import com.careconnect.dto.CaregiverRegistration;
import com.careconnect.dto.PatientRegistration;
import com.careconnect.dto.PatientWithLinkDto;
import com.careconnect.exception.AppException;
import com.careconnect.model.Caregiver;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.CaregiverService;
import com.careconnect.util.SecurityUtil;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class CaregiverControllerTest {

    private static final Long CAREGIVER_ID = 1L;
    private static final Long PATIENT_ID = 2L;
    private static final Long CG_USER_ID = 10L;
    private static final Long PT_USER_ID = 20L;
    private static final String PATIENT_EMAIL = "patient@example.com";
    // Two mocks of the same type – Mockito matches by field name to inject into
    // the controller's `caregiverService` and `auth` fields respectively.
    @Mock
    private CaregiverService caregiverService;
    @Mock
    private CaregiverService auth;
    @Mock
    private CaregiverPatientLinkService caregiverPatientLinkService;
    @Mock
    private UserRepository userRepository;

    // ── shared constants ──────────────────────────────────────────────────────
    @Mock
    private PatientRepository patientRepository;
    @Mock
    private CaregiverRepository caregiverRepository;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @InjectMocks
    private CaregiverController controller;

    // ── shared helpers ────────────────────────────────────────────────────────

    private User makeUser(Long id, Role role) {
        final User u = new User();
        u.setId(id);
        u.setRole(role);
        u.setEmail("user" + id + "@example.com");
        return u;
    }

    private Caregiver makeCaregiver(Long id, User user) {
        final Caregiver c = new Caregiver();
        c.setId(id);
        c.setUser(user);
        return c;
    }

    /**
     * Builds a request body map containing only an email entry.
     */
    private Map<String, String> emailBody(String email) {
        return Map.of("email", email);
    }

    // ── GET /{caregiverId}/patients ───────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private Map<String, Object> bodyMap(ResponseEntity<?> response) {
        return (Map<String, Object>) response.getBody();
    }

    // ── GET /{caregiverId} ────────────────────────────────────────────────────

    @Nested
    class GetPatientsByCaregiver {

        @Test
        void returnsListOfPatientsWithNoFilters() throws Exception {
            final PatientWithLinkDto dto = mock(PatientWithLinkDto.class);
            when(caregiverService.getPatientsByCaregiver(CAREGIVER_ID, null, null))
                    .thenReturn(List.of(dto));

            final ResponseEntity<List<PatientWithLinkDto>> response =
                    controller.getPatientsByCaregiver(CAREGIVER_ID, null, null);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).containsExactly(dto);
        }

        @Test
        void passesEmailAndNameFiltersToService() throws Exception {
            when(caregiverService.getPatientsByCaregiver(CAREGIVER_ID, PATIENT_EMAIL, "Jane"))
                    .thenReturn(List.of());

            controller.getPatientsByCaregiver(CAREGIVER_ID, PATIENT_EMAIL, "Jane");

            verify(caregiverService).getPatientsByCaregiver(CAREGIVER_ID, PATIENT_EMAIL, "Jane");
        }
    }

    // ── POST / ───────────────────────────────────────────────────────────────

    @Nested
    class GetCaregiver {

        @Test
        void returnsCaregiver() throws Exception {
            final Caregiver caregiver = makeCaregiver(CAREGIVER_ID, makeUser(CG_USER_ID, Role.CAREGIVER));
            when(caregiverService.getCaregiverById(CAREGIVER_ID)).thenReturn(caregiver);

            final ResponseEntity<Caregiver> response =
                    controller.getCaregiver(CAREGIVER_ID, mock(HttpServletRequest.class));

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).isSameAs(caregiver);
        }
    }

    // ── PUT /{caregiverId} ────────────────────────────────────────────────────

    @Nested
    class RegisterCaregiver {

        @Test
        void returnsCreatedStatusWithCaregiver() throws Exception {
            final CaregiverRegistration reg = new CaregiverRegistration();
            final Caregiver caregiver = makeCaregiver(CAREGIVER_ID, makeUser(CG_USER_ID, Role.CAREGIVER));
            when(auth.registerCaregiver(reg)).thenReturn(caregiver);

            final ResponseEntity<Caregiver> response = controller.registerCaregiver(reg);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
            assertThat(response.getBody()).isSameAs(caregiver);
        }
    }

    // ── POST /{caregiverId}/patients ──────────────────────────────────────────

    @Nested
    class UpdateCaregiver {

        @Test
        void returnsUpdatedCaregiver() throws Exception {
            final Caregiver incoming = new Caregiver();
            final Caregiver saved = new Caregiver();
            when(caregiverService.updateCaregiver(CAREGIVER_ID, incoming)).thenReturn(saved);

            final ResponseEntity<Caregiver> response = controller.updateCaregiver(CAREGIVER_ID, incoming);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).isSameAs(saved);
        }
    }

    // ── POST /{caregiverId}/patients/add ──────────────────────────────────────

    @Nested
    class RegisterPatient {

        @Test
        void setsCaregiverIdOnRegistrationAndReturnsPatient() throws Exception {
            final PatientRegistration reg = new PatientRegistration();
            final Patient patient = mock(Patient.class);
            when(auth.registerPatient(reg)).thenReturn(patient);

            final ResponseEntity<Patient> response = controller.registerPatient(CAREGIVER_ID, reg);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).isSameAs(patient);
            // Verify the controller wired the path variable into the DTO before delegating
            assertThat(reg.getCaregiverId()).isEqualTo(CAREGIVER_ID);
        }
    }

    // ── GET /{caregiverId}/patients/{patientId} ───────────────────────────────

    @Nested
    class AddPatient {

        @Test
        void throwsBadRequestWhenEmailKeyIsAbsent() throws Exception {
            // emptyMap().get("email") == null, triggering the null guard
            assertThatThrownBy(() -> controller.addPatient(CAREGIVER_ID, Collections.emptyMap()))
                    .isInstanceOf(AppException.class)
                    .hasMessage("Patient email is required");
        }

        @Test
        void throwsBadRequestWhenEmailIsBlank() throws Exception {
            assertThatThrownBy(() -> controller.addPatient(CAREGIVER_ID, emailBody("   ")))
                    .isInstanceOf(AppException.class)
                    .hasMessage("Patient email is required");
        }

        @Test
        void throwsNotFoundWhenCaregiverDoesNotExist() throws Exception {
            when(caregiverRepository.findById(CAREGIVER_ID)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> controller.addPatient(CAREGIVER_ID, emailBody(PATIENT_EMAIL)))
                    .isInstanceOf(AppException.class)
                    .hasMessage("Caregiver not found");
        }

        @Test
        void returnsAcceptedWithInvitationWhenPatientNotRegistered() throws Exception {
            when(caregiverRepository.findById(CAREGIVER_ID))
                    .thenReturn(Optional.of(makeCaregiver(CAREGIVER_ID, makeUser(CG_USER_ID, Role.CAREGIVER))));
            when(userRepository.findByEmailAndRole(PATIENT_EMAIL, Role.PATIENT))
                    .thenReturn(Optional.empty());

            final ResponseEntity<?> response = controller.addPatient(CAREGIVER_ID, emailBody(PATIENT_EMAIL));

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.ACCEPTED);
            assertThat(bodyMap(response).get("action")).isEqualTo("invitation_sent");
        }

        @Test
        void throwsNotFoundWhenPatientRecordMissingForExistingUser() throws Exception {
            final User patientUser = makeUser(PT_USER_ID, Role.PATIENT);
            when(caregiverRepository.findById(CAREGIVER_ID))
                    .thenReturn(Optional.of(makeCaregiver(CAREGIVER_ID, makeUser(CG_USER_ID, Role.CAREGIVER))));
            when(userRepository.findByEmailAndRole(PATIENT_EMAIL, Role.PATIENT))
                    .thenReturn(Optional.of(patientUser));
            when(patientRepository.findByUser(patientUser)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> controller.addPatient(CAREGIVER_ID, emailBody(PATIENT_EMAIL)))
                    .isInstanceOf(AppException.class)
                    .hasMessage("Patient record not found for user");
        }

        @Test
        void throwsBadRequestWhenLinkAlreadyExists() throws Exception {
            final User caregiverUser = makeUser(CG_USER_ID, Role.CAREGIVER);
            final User patientUser = makeUser(PT_USER_ID, Role.PATIENT);
            final Patient patient = mock(Patient.class);
            when(caregiverRepository.findById(CAREGIVER_ID))
                    .thenReturn(Optional.of(makeCaregiver(CAREGIVER_ID, caregiverUser)));
            when(userRepository.findByEmailAndRole(PATIENT_EMAIL, Role.PATIENT))
                    .thenReturn(Optional.of(patientUser));
            when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
            when(caregiverPatientLinkService.hasActiveLink(CG_USER_ID, PT_USER_ID)).thenReturn(true);

            assertThatThrownBy(() -> controller.addPatient(CAREGIVER_ID, emailBody(PATIENT_EMAIL)))
                    .isInstanceOf(AppException.class)
                    .hasMessage("Patient is already linked to this caregiver");
        }

        @Test
        void returnsOkAndCreatesLinkWhenSuccessful() throws Exception {
            final User caregiverUser = makeUser(CG_USER_ID, Role.CAREGIVER);
            final User patientUser = makeUser(PT_USER_ID, Role.PATIENT);
            final Patient patient = mock(Patient.class);
            when(patient.getId()).thenReturn(PATIENT_ID);
            when(patient.getFirstName()).thenReturn("Jane");
            when(patient.getLastName()).thenReturn("Smith");

            when(caregiverRepository.findById(CAREGIVER_ID))
                    .thenReturn(Optional.of(makeCaregiver(CAREGIVER_ID, caregiverUser)));
            when(userRepository.findByEmailAndRole(PATIENT_EMAIL, Role.PATIENT))
                    .thenReturn(Optional.of(patientUser));
            when(patientRepository.findByUser(patientUser)).thenReturn(Optional.of(patient));
            when(caregiverPatientLinkService.hasActiveLink(CG_USER_ID, PT_USER_ID)).thenReturn(false);

            final ResponseEntity<?> response = controller.addPatient(CAREGIVER_ID, emailBody(PATIENT_EMAIL));

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(bodyMap(response).get("message"))
                    .isEqualTo("Patient successfully added to caregiver");
            assertThat(bodyMap(response).get("patientId")).isEqualTo(PATIENT_ID);
            assertThat(bodyMap(response).get("patientEmail")).isEqualTo(PATIENT_EMAIL);
            verify(caregiverPatientLinkService)
                    .createPermanentLink(CG_USER_ID, PT_USER_ID, "Patient added by caregiver");
        }
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    @Nested
    class GetPatientForCaregiver {

        @Test
        void returnsForbiddenWhenCaregiverHasNoAccess() throws Exception {
            when(caregiverService.caregiverHasAccessToPatient(CAREGIVER_ID, PATIENT_ID))
                    .thenReturn(false);

            final ResponseEntity<?> response =
                    controller.getPatientForCaregiver(CAREGIVER_ID, PATIENT_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        }

        @Test
        void returnsNotFoundWhenServiceReturnsNull() throws Exception {
            when(caregiverService.caregiverHasAccessToPatient(CAREGIVER_ID, PATIENT_ID))
                    .thenReturn(true);
            when(caregiverService.getPatientWithLinkById(CAREGIVER_ID, PATIENT_ID))
                    .thenReturn(null);

            final ResponseEntity<?> response =
                    controller.getPatientForCaregiver(CAREGIVER_ID, PATIENT_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        }

        @Test
        void returnsOkWithPatientDto() throws Exception {
            final PatientWithLinkDto dto = mock(PatientWithLinkDto.class);
            when(caregiverService.caregiverHasAccessToPatient(CAREGIVER_ID, PATIENT_ID))
                    .thenReturn(true);
            when(caregiverService.getPatientWithLinkById(CAREGIVER_ID, PATIENT_ID))
                    .thenReturn(dto);

            final ResponseEntity<?> response =
                    controller.getPatientForCaregiver(CAREGIVER_ID, PATIENT_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).isSameAs(dto);
        }
    }
}
