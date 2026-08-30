package com.careconnect.controller;

import com.careconnect.dto.SymptomDTO;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverService;
import com.careconnect.service.SymptomService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class SymptomControllerTest {

    private static final Long PATIENT_ID = 1L;
    private static final Long SYMPTOM_ID = 10L;
    private static final String USER_EMAIL = "user@test.com";
    @Mock
    private SymptomService symptomService;
    @Mock
    private UserRepository userRepository;
    @Mock
    private PatientRepository patientRepository;
    @Mock
    private CaregiverService caregiverService;
    @InjectMocks
    private SymptomController controller;

    @AfterEach
    void clearSecurity() throws Exception {
        SecurityContextHolder.clearContext();
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    private void setUpSecurity(String email) {
        final Authentication auth = mock(Authentication.class);
        when(auth.getName()).thenReturn(email);
        final SecurityContext ctx = mock(SecurityContext.class);
        when(ctx.getAuthentication()).thenReturn(auth);
        SecurityContextHolder.setContext(ctx);
    }

    private User userWithRole(Long id, String email, Role role) {
        return User.builder().id(id).email(email).role(role).password("p").status("ACTIVE").build();
    }

    private Patient patientWithUser(User user) {
        return Patient.builder().id(PATIENT_ID).user(user).build();
    }

    private SymptomDTO dto(Long patientId) {
        return SymptomDTO.builder().patientId(patientId).symptomKey("headache").build();
    }

    // ─── create ───────────────────────────────────────────────────────────────

    @Test
    void create_nullPatientId_returnsForbidden() throws Exception {
        final SymptomDTO dto = dto(null);

        final ResponseEntity<?> response = controller.create(dto);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void create_noSecurityContext_hasAccessReturnsFalse_returnsForbidden() throws Exception {
        // No security context set → NullPointerException in hasAccessToPatient → returns false
        final SymptomDTO dto = dto(PATIENT_ID);

        final ResponseEntity<?> response = controller.create(dto);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void create_patientNotFound_returnsForbidden() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User user = userWithRole(1L, USER_EMAIL, Role.PATIENT);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.create(dto(PATIENT_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void create_patientRole_sameUser_returnsCreated() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User user = userWithRole(1L, USER_EMAIL, Role.PATIENT);
        final Patient patient = patientWithUser(user);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(user));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
        final SymptomDTO created = dto(PATIENT_ID);
        when(symptomService.create(any())).thenReturn(created);

        final ResponseEntity<?> response = controller.create(dto(PATIENT_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    void create_patientRole_differentUser_returnsForbidden() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User currentUser = userWithRole(1L, USER_EMAIL, Role.PATIENT);
        final User patientUser = userWithRole(2L, "other@test.com", Role.PATIENT);
        final Patient patient = patientWithUser(patientUser);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(currentUser));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));

        final ResponseEntity<?> response = controller.create(dto(PATIENT_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void create_adminRole_serviceThrowsException_returnsBadRequest() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User adminUser = userWithRole(1L, USER_EMAIL, Role.ADMIN);
        final Patient patient = patientWithUser(adminUser);
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(adminUser));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
        when(symptomService.create(any())).thenThrow(new RuntimeException("DB error"));

        final ResponseEntity<?> response = controller.create(dto(PATIENT_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    // ─── update ───────────────────────────────────────────────────────────────

    @Test
    void update_symptomNotFound_returnsNotFound() throws Exception {
        when(symptomService.get(SYMPTOM_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.update(SYMPTOM_ID, dto(PATIENT_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    void update_noAccess_returnsForbidden() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User currentUser = userWithRole(1L, USER_EMAIL, Role.PATIENT);
        final User patientUser = userWithRole(2L, "other@test.com", Role.PATIENT);
        final Patient patient = patientWithUser(patientUser);
        final SymptomDTO existing = dto(PATIENT_ID);
        when(symptomService.get(SYMPTOM_ID)).thenReturn(Optional.of(existing));
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(currentUser));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));

        final ResponseEntity<?> response = controller.update(SYMPTOM_ID, dto(PATIENT_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void update_adminAccess_returnsOk() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User adminUser = userWithRole(1L, USER_EMAIL, Role.ADMIN);
        final Patient patient = patientWithUser(adminUser);
        final SymptomDTO existing = dto(PATIENT_ID);
        final SymptomDTO updated = dto(PATIENT_ID);
        when(symptomService.get(SYMPTOM_ID)).thenReturn(Optional.of(existing));
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(adminUser));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
        when(symptomService.update(eq(SYMPTOM_ID), any())).thenReturn(updated);

        final ResponseEntity<?> response = controller.update(SYMPTOM_ID, dto(PATIENT_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void update_serviceException_returnsBadRequest() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User adminUser = userWithRole(1L, USER_EMAIL, Role.ADMIN);
        final Patient patient = patientWithUser(adminUser);
        final SymptomDTO existing = dto(PATIENT_ID);
        when(symptomService.get(SYMPTOM_ID)).thenReturn(Optional.of(existing));
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(adminUser));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
        when(symptomService.update(eq(SYMPTOM_ID), any())).thenThrow(new RuntimeException("fail"));

        final ResponseEntity<?> response = controller.update(SYMPTOM_ID, dto(PATIENT_ID));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    // ─── list ─────────────────────────────────────────────────────────────────

    @Test
    void list_caregiverAccessDenied_returnsForbidden() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User caregiver = userWithRole(5L, USER_EMAIL, Role.CAREGIVER);
        final Patient patient = patientWithUser(userWithRole(2L, "p@test.com", Role.PATIENT));
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(caregiver));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
        when(caregiverService.hasAccessToPatient(5L, PATIENT_ID)).thenReturn(false);

        final ResponseEntity<?> response = controller.list(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void list_caregiverAccessGranted_returnsOk() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User caregiver = userWithRole(5L, USER_EMAIL, Role.CAREGIVER);
        final Patient patient = patientWithUser(userWithRole(2L, "p@test.com", Role.PATIENT));
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(caregiver));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
        when(caregiverService.hasAccessToPatient(5L, PATIENT_ID)).thenReturn(true);
        when(symptomService.listByPatient(PATIENT_ID)).thenReturn(List.of());

        final ResponseEntity<?> response = controller.list(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void list_familyMemberAccessGranted_returnsOk() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User familyMember = userWithRole(6L, USER_EMAIL, Role.FAMILY_MEMBER);
        final Patient patient = patientWithUser(userWithRole(2L, "p@test.com", Role.PATIENT));
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(familyMember));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
        when(caregiverService.hasAccessToPatient(6L, PATIENT_ID)).thenReturn(true);
        when(symptomService.listByPatient(PATIENT_ID)).thenReturn(List.of());

        final ResponseEntity<?> response = controller.list(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    void list_familyMemberAccessDenied_returnsForbidden() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User familyMember = userWithRole(6L, USER_EMAIL, Role.FAMILY_MEMBER);
        final Patient patient = patientWithUser(userWithRole(2L, "p@test.com", Role.PATIENT));
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(familyMember));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
        when(caregiverService.hasAccessToPatient(6L, PATIENT_ID)).thenReturn(false);

        final ResponseEntity<?> response = controller.list(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void list_userRepoThrowsException_returnsForbidden() throws Exception {
        setUpSecurity(USER_EMAIL);
        when(userRepository.findByEmail(USER_EMAIL)).thenThrow(new RuntimeException("DB down"));

        final ResponseEntity<?> response = controller.list(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void list_nullRoleUser_returnsForbidden() throws Exception {
        setUpSecurity(USER_EMAIL);
        // Mock a user whose getRole() returns null — falls through all role checks to "return false"
        final User mockUser = mock(User.class);
        when(mockUser.getRole()).thenReturn(null);
        final Patient patient = patientWithUser(mock(User.class));
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(mockUser));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));

        final ResponseEntity<?> response = controller.list(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    // ─── delete ───────────────────────────────────────────────────────────────

    @Test
    void delete_symptomNotFound_returnsNotFound() throws Exception {
        when(symptomService.get(SYMPTOM_ID)).thenReturn(Optional.empty());

        final ResponseEntity<?> response = controller.delete(SYMPTOM_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    void delete_noAccess_returnsForbidden() throws Exception {
        // No security context → NPE → access = false
        final SymptomDTO existing = dto(PATIENT_ID);
        when(symptomService.get(SYMPTOM_ID)).thenReturn(Optional.of(existing));

        final ResponseEntity<?> response = controller.delete(SYMPTOM_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void delete_success_returnsOk() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User adminUser = userWithRole(1L, USER_EMAIL, Role.ADMIN);
        final Patient patient = patientWithUser(adminUser);
        final SymptomDTO existing = dto(PATIENT_ID);
        when(symptomService.get(SYMPTOM_ID)).thenReturn(Optional.of(existing));
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(adminUser));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
        doNothing().when(symptomService).delete(SYMPTOM_ID);

        final ResponseEntity<?> response = controller.delete(SYMPTOM_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked") final Map<String, String> body = (Map<String, String>) response.getBody();
        assertThat(body).containsEntry("message", "Symptom deleted");
    }

    @Test
    void delete_serviceException_returnsBadRequest() throws Exception {
        setUpSecurity(USER_EMAIL);
        final User adminUser = userWithRole(1L, USER_EMAIL, Role.ADMIN);
        final Patient patient = patientWithUser(adminUser);
        final SymptomDTO existing = dto(PATIENT_ID);
        when(symptomService.get(SYMPTOM_ID)).thenReturn(Optional.of(existing));
        when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(adminUser));
        when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
        doThrow(new RuntimeException("DB error")).when(symptomService).delete(SYMPTOM_ID);

        final ResponseEntity<?> response = controller.delete(SYMPTOM_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    }
}
