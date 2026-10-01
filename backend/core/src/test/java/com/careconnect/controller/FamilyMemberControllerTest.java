package com.careconnect.controller;

import com.careconnect.dto.DashboardDTO;
import com.careconnect.dto.PatientDataResponse;
import com.careconnect.dto.VitalSampleDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.AnalyticsService;
import com.careconnect.service.FamilyMemberService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
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

import java.time.Period;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
        /*
         * MockitoExtension enforces strict stubbing and manages mock lifecycle.
         * No Spring context needed — all dependencies are injected via @InjectMocks.
         */
class FamilyMemberControllerTest {

    private static final Long USER_ID = 1L;
    private static final Long PATIENT_ID = 2L;
    @Mock
    private FamilyMemberService familyMemberService;
    @Mock
    private UserRepository userRepository;
    @Mock
    private AnalyticsService analyticsService;
    @Mock
    private Authentication authentication;
    @Mock
    private SecurityContext securityContext;
    @InjectMocks
    private FamilyMemberController controller;

    @BeforeEach
    void setUpSecurityContext() throws Exception {
        /*
         * FamilyMemberController calls authentication.getName() and parses it as a Long.
         * Wire the mock SecurityContext into the static SecurityContextHolder.
         */
        when(securityContext.getAuthentication()).thenReturn(authentication);
        SecurityContextHolder.setContext(securityContext);
        when(authentication.getName()).thenReturn(USER_ID.toString());
    }

    @AfterEach
    void clearSecurityContext() throws Exception {
        SecurityContextHolder.clearContext();
    }

    private User makeFamilyMemberUser() throws Exception {
        final User u = new User();
        u.setId(USER_ID);
        u.setRole(Role.FAMILY_MEMBER);
        return u;
    }

    // ── getCurrentFamilyMember() — error branches ────────────────────────────

    @Test
    void getAccessiblePatients_throwsUnauthorized_whenUserNotFound() throws Exception {
        /*
         * Covers: userRepository.findById() returns empty
         * → orElseThrow fires AppException(UNAUTHORIZED)
         */
        when(userRepository.findByEmail(USER_ID.toString())).thenReturn(Optional.empty());

        assertThatThrownBy(() -> controller.getAccessiblePatients())
                .isInstanceOf(AppException.class)
                .satisfies(e -> assertThat(((AppException) e).getStatus())
                        .isEqualTo(HttpStatus.UNAUTHORIZED));
    }

    @Test
    void getAccessiblePatients_throwsForbidden_whenUserIsNotFamilyMember() throws Exception {
        /*
         * Covers: user found but role != FAMILY_MEMBER
         * → throws AppException(FORBIDDEN)
         */
        final User nonFamily = new User();
        nonFamily.setId(USER_ID);
        nonFamily.setRole(Role.PATIENT);
        when(userRepository.findByEmail(USER_ID.toString())).thenReturn(Optional.of(nonFamily));

        assertThatThrownBy(() -> controller.getAccessiblePatients())
                .isInstanceOf(AppException.class)
                .satisfies(e -> assertThat(((AppException) e).getStatus())
                        .isEqualTo(HttpStatus.FORBIDDEN));
    }

    // ── getAccessiblePatients() ───────────────────────────────────────────────

    @Test
    void getAccessiblePatients_returns200_withPatientList() throws Exception {
        /*
         * Covers: getCurrentFamilyMember() happy path (role == FAMILY_MEMBER)
         * and successful delegation to familyMemberService.
         */
        final User user = makeFamilyMemberUser();
        final List<PatientDataResponse> patients = List.of();
        when(userRepository.findByEmail(USER_ID.toString())).thenReturn(Optional.of(user));
        when(familyMemberService.getAccessiblePatients(USER_ID)).thenReturn(patients);

        final ResponseEntity<List<PatientDataResponse>> response = controller.getAccessiblePatients();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(patients);
    }

    // ── getPatientData() ──────────────────────────────────────────────────────

    @Test
    void getPatientData_returns200_withPatientData() throws Exception {
        /*
         * Covers: getCurrentFamilyMember() and getPatientData() delegation.
         */
        final User user = makeFamilyMemberUser();
        final PatientDataResponse patientData = mock(PatientDataResponse.class);
        when(userRepository.findByEmail(USER_ID.toString())).thenReturn(Optional.of(user));
        when(familyMemberService.getPatientData(USER_ID, PATIENT_ID)).thenReturn(patientData);

        final ResponseEntity<PatientDataResponse> response = controller.getPatientData(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(patientData);
    }

    // ── hasAccessToPatient() ─────────────────────────────────────────────────

    @Test
    void hasAccessToPatient_returns200_withBooleanResult() throws Exception {
        /*
         * Covers: successful delegation to familyMemberService.hasAccessToPatient().
         */
        final User user = makeFamilyMemberUser();
        when(userRepository.findByEmail(USER_ID.toString())).thenReturn(Optional.of(user));
        when(familyMemberService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(true);

        final ResponseEntity<Boolean> response = controller.hasAccessToPatient(PATIENT_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isTrue();
    }

    // ── getPatientDashboard() ────────────────────────────────────────────────

    @Test
    void getPatientDashboard_throwsForbidden_whenAccessDenied() throws Exception {
        /*
         * Covers: hasAccessToPatient returns false
         * → throws AppException(FORBIDDEN, "Access denied to patient data")
         */
        final User user = makeFamilyMemberUser();
        when(userRepository.findByEmail(USER_ID.toString())).thenReturn(Optional.of(user));
        when(familyMemberService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(false);

        assertThatThrownBy(() -> controller.getPatientDashboard(PATIENT_ID, 30))
                .isInstanceOf(AppException.class)
                .satisfies(e -> assertThat(((AppException) e).getStatus())
                        .isEqualTo(HttpStatus.FORBIDDEN));
    }

    @Test
    void getPatientDashboard_returns200_whenAccessGranted() throws Exception {
        /*
         * Covers: hasAccessToPatient returns true
         * → delegates to analyticsService.getDashboard().
         */
        final User user = makeFamilyMemberUser();
        final DashboardDTO dashboard = mock(DashboardDTO.class);
        when(userRepository.findByEmail(USER_ID.toString())).thenReturn(Optional.of(user));
        when(familyMemberService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(true);
        when(analyticsService.getDashboard(PATIENT_ID, Period.ofDays(30))).thenReturn(dashboard);

        final ResponseEntity<DashboardDTO> response = controller.getPatientDashboard(PATIENT_ID, 30);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(dashboard);
    }

    // ── getPatientVitals() ───────────────────────────────────────────────────

    @Test
    void getPatientVitals_throwsForbidden_whenAccessDenied() throws Exception {
        /*
         * Covers: hasAccessToPatient returns false
         * → throws AppException(FORBIDDEN, "Access denied to patient data")
         */
        final User user = makeFamilyMemberUser();
        when(userRepository.findByEmail(USER_ID.toString())).thenReturn(Optional.of(user));
        when(familyMemberService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(false);

        assertThatThrownBy(() -> controller.getPatientVitals(PATIENT_ID, 7))
                .isInstanceOf(AppException.class)
                .satisfies(e -> assertThat(((AppException) e).getStatus())
                        .isEqualTo(HttpStatus.FORBIDDEN));
    }

    @Test
    void getPatientVitals_returns200_whenAccessGranted() throws Exception {
        /*
         * Covers: hasAccessToPatient returns true
         * → delegates to analyticsService.getVitals().
         */
        final User user = makeFamilyMemberUser();
        final List<VitalSampleDTO> vitals = List.of();
        when(userRepository.findByEmail(USER_ID.toString())).thenReturn(Optional.of(user));
        when(familyMemberService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(true);
        when(analyticsService.getVitals(PATIENT_ID, Period.ofDays(7))).thenReturn(vitals);

        final ResponseEntity<List<VitalSampleDTO>> response = controller.getPatientVitals(PATIENT_ID, 7);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(vitals);
    }
}
