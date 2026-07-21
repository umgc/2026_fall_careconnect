package com.careconnect.controller;

import com.careconnect.dto.DashboardDTO;
import com.careconnect.dto.VitalSampleDTO;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.PatientCaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.AnalyticsService;
import com.careconnect.service.CaregiverService;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.VitalSampleService;
import com.careconnect.util.SecurityUtil;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
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
import org.springframework.test.util.ReflectionTestUtils;
import java.time.Instant;

import java.time.Period;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AnalyticsControllerTest {

    @Mock
    private UserRepository userRepository;
    @Mock
    private PatientRepository patientRepository;
    @Mock
    private CaregiverService caregiverService;
    @Mock
    private PatientCaregiverRepository caregiverPatientLinkRepository;
    @Mock
    private FamilyMemberLinkRepository familyMemberPatientLinkRepository;
    @Mock
    private AnalyticsService analyticsService;
    @Mock
    private VitalSampleService vitalSampleService;
    @Mock
    private Authentication authentication;
    @Mock
    private SecurityContext securityContext;

    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private AnalyticsController controller;

    // ── Shared test fixtures ──────────────────────────────────────────────────

    private static final Long PATIENT_ID = 1L;
    private static final Long USER_ID = 10L;
    private static final Long OTHER_ID = 99L;
    private static final String USER_EMAIL = "user@example.com";

    private User makeUser(Long id, Role role) {
        final User u = new User();
        u.setId(id);
        u.setEmail(USER_EMAIL);
        u.setRole(role);
        return u;
    }

    private Patient makePatient(User owner) {
        final Patient p = new Patient();
        p.setId(PATIENT_ID);
        p.setUser(owner);
        return p;
    }

    /** Wire up SecurityContextHolder so auth.getName() returns USER_EMAIL. */
    private void mockAuth() throws Exception {
        when(securityContext.getAuthentication()).thenReturn(authentication);
        SecurityContextHolder.setContext(securityContext);
        when(authentication.getName()).thenReturn(USER_EMAIL);
    }

    @BeforeEach
    void resetSecurityContext() throws Exception {
        SecurityContextHolder.clearContext();
        ReflectionTestUtils.setField(controller, "analyticsService", analyticsService);
        ReflectionTestUtils.setField(controller, "vitalSampleService", vitalSampleService);
    }

    // ── dashboard() ───────────────────────────────────────────────────────────

    @Nested
    class Dashboard {

        @Test
        void returnsDto() throws Exception {
            final DashboardDTO dto = mock(DashboardDTO.class);
            when(analyticsService.getDashboard(PATIENT_ID, Period.ofDays(7))).thenReturn(dto);

            final DashboardDTO result = controller.dashboard(PATIENT_ID, 7);

            assertThat(result).isSameAs(dto);
        }

        @Test
        void clampsNegativeDaysToOne() throws Exception {
            final DashboardDTO dto = mock(DashboardDTO.class);
            when(analyticsService.getDashboard(PATIENT_ID, Period.ofDays(1))).thenReturn(dto);

            final DashboardDTO result = controller.dashboard(PATIENT_ID, -5);

            assertThat(result).isSameAs(dto);
            verify(analyticsService).getDashboard(PATIENT_ID, Period.ofDays(1));
        }
    }

    // ── exportVitalsCsv() ────────────────────────────────────────────────────

    @Nested
    class ExportCsv {

        @Test
        void returnsCsvBytes() throws Exception {
            final byte[] csv = "col1,col2\n1,2\n".getBytes();
            when(analyticsService.exportVitalsCsv(PATIENT_ID, Period.ofDays(7))).thenReturn(csv);

            final ResponseEntity<byte[]> response = controller.exportVitalsCsv(PATIENT_ID, 7);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).isEqualTo(csv);
            assertThat(response.getHeaders().getFirst("Content-Disposition"))
                    .contains("vitals.csv");
        }

        @Test
        void clampsNegativeDaysToOne() throws Exception {
            final byte[] csv = new byte[0];
            when(analyticsService.exportVitalsCsv(PATIENT_ID, Period.ofDays(1))).thenReturn(csv);

            controller.exportVitalsCsv(PATIENT_ID, 0);

            verify(analyticsService).exportVitalsCsv(PATIENT_ID, Period.ofDays(1));
        }
    }

    // ── exportVitalsPdf() ────────────────────────────────────────────────────

    @Nested
    class ExportPdf {

        @Test
        void returnsPdfBytes() throws Exception {
            final byte[] pdf = new byte[] { 1, 2, 3 };
            when(analyticsService.exportVitalsPdf(PATIENT_ID, Period.ofDays(7))).thenReturn(pdf);

            final ResponseEntity<byte[]> response = controller.exportVitalsPdf(PATIENT_ID, 7);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).isEqualTo(pdf);
            assertThat(response.getHeaders().getFirst("Content-Disposition"))
                    .contains("vitals.pdf");
        }

        @Test
        void clampsNegativeDaysToOne() throws Exception {
            final byte[] pdf = new byte[0];
            when(analyticsService.exportVitalsPdf(PATIENT_ID, Period.ofDays(1))).thenReturn(pdf);

            controller.exportVitalsPdf(PATIENT_ID, 0);

            verify(analyticsService).exportVitalsPdf(PATIENT_ID, Period.ofDays(1));
        }
    }

    // ── live() SSE ────────────────────────────────────────────────────────────

    @Nested
    class Live {

        @Test
        void returnsNonNullEmitter() throws Exception {
            // Throw immediately so the infinite loop exits after one iteration
            when(analyticsService.getDashboard(PATIENT_ID, Period.ofDays(1)))
                    .thenThrow(new RuntimeException("stop"));

            final org.springframework.web.servlet.mvc.method.annotation.SseEmitter emitter =
                    controller.live(PATIENT_ID);

            assertThat(emitter).isNotNull();
            // Allow the executor thread to run before verifying
            Thread.sleep(200);
            verify(analyticsService, atLeastOnce()).getDashboard(PATIENT_ID, Period.ofDays(1));
        }
    }

    // ── vitals() GET ──────────────────────────────────────────────────────────

    @Nested
    class GetVitals {

        @Test
        void patientCanAccessOwnVitals() throws Exception {
            mockAuth();
            final User patientUser = makeUser(USER_ID, Role.PATIENT);
            final Patient patient = makePatient(patientUser);

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(patientUser));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(analyticsService.getVitals(PATIENT_ID, Period.ofDays(7))).thenReturn(List.of());

            final ResponseEntity<?> response = controller.vitals(PATIENT_ID, 7);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(bodyValue(response, "message")).isEqualTo("Vitals data retrieved successfully");
        }

        @Test
        void patientCannotAccessOtherPatientsVitals() throws Exception {
            mockAuth();
            final User requestingUser = makeUser(OTHER_ID, Role.PATIENT); // different id
            final User patientUser = makeUser(USER_ID, Role.PATIENT);
            final Patient patient = makePatient(patientUser);

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(requestingUser));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));

            final ResponseEntity<?> response = controller.vitals(PATIENT_ID, 7);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        }

        @Test
        void caregiverWithAccessCanReadVitals() throws Exception {
            mockAuth();
            final User caregiver = makeUser(USER_ID, Role.CAREGIVER);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(caregiver));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(true);
            when(analyticsService.getVitals(PATIENT_ID, Period.ofDays(7))).thenReturn(List.of());

            final ResponseEntity<?> response = controller.vitals(PATIENT_ID, 7);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void caregiverWithoutAccessIsRejected() throws Exception {
            mockAuth();
            final User caregiver = makeUser(USER_ID, Role.CAREGIVER);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(caregiver));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(false);

            final ResponseEntity<?> response = controller.vitals(PATIENT_ID, 7);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        }

        @Test
        void familyMemberWithAccessCanReadVitals() throws Exception {
            mockAuth();
            final User familyMember = makeUser(USER_ID, Role.FAMILY_MEMBER);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(familyMember));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(true);
            when(analyticsService.getVitals(PATIENT_ID, Period.ofDays(7))).thenReturn(List.of());

            final ResponseEntity<?> response = controller.vitals(PATIENT_ID, 7);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void adminCanAccessAnyPatientsVitals() throws Exception {
            mockAuth();
            final User admin = makeUser(USER_ID, Role.ADMIN);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(analyticsService.getVitals(PATIENT_ID, Period.ofDays(7))).thenReturn(List.of());

            final ResponseEntity<?> response = controller.vitals(PATIENT_ID, 7);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsNotFoundWhenPatientMissing() throws Exception {
            mockAuth();
            final User admin = makeUser(USER_ID, Role.ADMIN);

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.empty());

            final ResponseEntity<?> response = controller.vitals(PATIENT_ID, 7);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        }

        @Test
        void returnsEmptyListOnServiceException() throws Exception {
            mockAuth();
            final User admin = makeUser(USER_ID, Role.ADMIN);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(analyticsService.getVitals(any(), any())).thenThrow(new RuntimeException("DB error"));

            final ResponseEntity<?> response = controller.vitals(PATIENT_ID, 7);

            // Controller catches generic exceptions and returns 500
            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
            assertThat(bodyValue(response, "error")).isEqualTo("Failed to retrieve vitals data");
        }
    }

    // ── createVitalSample() POST ──────────────────────────────────────────────

    @Nested
    class CreateVitalSample {

        private VitalSampleDTO sampleDto() throws Exception {
            return new VitalSampleDTO(1L, PATIENT_ID, Instant.now(), 65.0, 98.0, 120, 80, 190.0, 8, 4);
        }

        @Test
        void patientCanCreateOwnVitalSample() throws Exception {
            mockAuth();
            final User patientUser = makeUser(USER_ID, Role.PATIENT);
            final Patient patient = makePatient(patientUser);
            final VitalSampleDTO dto = sampleDto();
            final VitalSampleDTO created = sampleDto();

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(patientUser));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(vitalSampleService.createVitalSample(dto)).thenReturn(created);

            final ResponseEntity<?> response = controller.createVitalSample(dto);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
            assertThat(bodyValue(response, "message")).isEqualTo("Vital sample created successfully");
        }

        @Test
        void patientCannotCreateVitalSampleForAnotherPatient() throws Exception {
            mockAuth();
            final User requestingUser = makeUser(OTHER_ID, Role.PATIENT);
            final Patient patient = makePatient(makeUser(USER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(requestingUser));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));

            final ResponseEntity<?> response = controller.createVitalSample(sampleDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        }

        @Test
        void caregiverWithAccessCanCreateVitalSample() throws Exception {
            mockAuth();
            final User caregiver = makeUser(USER_ID, Role.CAREGIVER);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));
            final VitalSampleDTO dto = sampleDto();

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(caregiver));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(true);
            when(vitalSampleService.createVitalSample(dto)).thenReturn(dto);

            final ResponseEntity<?> response = controller.createVitalSample(dto);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        }

        @Test
        void caregiverWithoutAccessIsRejected() throws Exception {
            mockAuth();
            final User caregiver = makeUser(USER_ID, Role.CAREGIVER);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(caregiver));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(false);

            final ResponseEntity<?> response = controller.createVitalSample(sampleDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        }

        @Test
        void familyMemberWithAccessCanCreateVitalSample() throws Exception {
            mockAuth();
            final User familyMember = makeUser(USER_ID, Role.FAMILY_MEMBER);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));
            final VitalSampleDTO dto = sampleDto();

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(familyMember));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(true);
            when(vitalSampleService.createVitalSample(dto)).thenReturn(dto);

            final ResponseEntity<?> response = controller.createVitalSample(dto);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        }

        @Test
        void familyMemberWithoutAccessIsRejected() throws Exception {
            mockAuth();
            final User familyMember = makeUser(USER_ID, Role.FAMILY_MEMBER);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(familyMember));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(false);

            final ResponseEntity<?> response = controller.createVitalSample(sampleDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        }

        @Test
        void adminCanCreateVitalSampleForAnyPatient() throws Exception {
            mockAuth();
            final User admin = makeUser(USER_ID, Role.ADMIN);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));
            final VitalSampleDTO dto = sampleDto();

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(vitalSampleService.createVitalSample(dto)).thenReturn(dto);

            final ResponseEntity<?> response = controller.createVitalSample(dto);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        }

        @Test
        void returnsNotFoundWhenPatientMissing() throws Exception {
            mockAuth();
            final User admin = makeUser(USER_ID, Role.ADMIN);

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.empty());

            final ResponseEntity<?> response = controller.createVitalSample(sampleDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        }

        @Test
        void returnsBadRequestOnIllegalArgument() throws Exception {
            mockAuth();
            final User admin = makeUser(USER_ID, Role.ADMIN);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));
            final VitalSampleDTO dto = sampleDto();

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(vitalSampleService.createVitalSample(dto))
                    .thenThrow(new IllegalArgumentException("Invalid heart rate"));

            final ResponseEntity<?> response = controller.createVitalSample(dto);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
            assertThat(bodyValue(response, "error")).isEqualTo("Invalid heart rate");
        }

        @Test
        void returnsInternalServerErrorOnUnexpectedException() throws Exception {
            mockAuth();
            final User admin = makeUser(USER_ID, Role.ADMIN);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));
            final VitalSampleDTO dto = sampleDto();

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(vitalSampleService.createVitalSample(dto)).thenThrow(new RuntimeException("DB down"));

            final ResponseEntity<?> response = controller.createVitalSample(dto);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    // ── updateVitalSample() PUT ───────────────────────────────────────────────

    @Nested
    class UpdateVitalSample {

        private static final Long VITAL_ID = 55L;

        private VitalSampleDTO existingDto() throws Exception {
            return new VitalSampleDTO(VITAL_ID, PATIENT_ID, null, null, null, null, null, null, null, null);
        }

        private VitalSampleDTO updateDto() throws Exception {
            return new VitalSampleDTO(VITAL_ID, PATIENT_ID, null, null, null, null, null, null, null, null);
        }

        @Test
        void patientCanUpdateOwnVitalSample() throws Exception {
            mockAuth();
            final User patientUser = makeUser(USER_ID, Role.PATIENT);
            final Patient patient = makePatient(patientUser);

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(patientUser));
            when(vitalSampleService.getVitalSample(VITAL_ID)).thenReturn(Optional.of(existingDto()));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(vitalSampleService.updateVitalSample(VITAL_ID, updateDto())).thenReturn(updateDto());

            final ResponseEntity<?> response = controller.updateVitalSample(VITAL_ID, updateDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(bodyValue(response, "message")).isEqualTo("Vital sample updated successfully");
        }

        @Test
        void patientCannotUpdateAnotherPatientsVitalSample() throws Exception {
            mockAuth();
            final User requestingUser = makeUser(OTHER_ID, Role.PATIENT);
            final Patient patient = makePatient(makeUser(USER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(requestingUser));
            when(vitalSampleService.getVitalSample(VITAL_ID)).thenReturn(Optional.of(existingDto()));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));

            final ResponseEntity<?> response = controller.updateVitalSample(VITAL_ID, updateDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        }

        @Test
        void caregiverWithAccessCanUpdate() throws Exception {
            mockAuth();
            final User caregiver = makeUser(USER_ID, Role.CAREGIVER);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(caregiver));
            when(vitalSampleService.getVitalSample(VITAL_ID)).thenReturn(Optional.of(existingDto()));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(true);
            when(vitalSampleService.updateVitalSample(VITAL_ID, updateDto())).thenReturn(updateDto());

            final ResponseEntity<?> response = controller.updateVitalSample(VITAL_ID, updateDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void caregiverWithoutAccessIsRejected() throws Exception {
            mockAuth();
            final User caregiver = makeUser(USER_ID, Role.CAREGIVER);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(caregiver));
            when(vitalSampleService.getVitalSample(VITAL_ID)).thenReturn(Optional.of(existingDto()));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(false);

            final ResponseEntity<?> response = controller.updateVitalSample(VITAL_ID, updateDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        }

        @Test
        void familyMemberWithAccessCanUpdate() throws Exception {
            mockAuth();
            final User familyMember = makeUser(USER_ID, Role.FAMILY_MEMBER);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(familyMember));
            when(vitalSampleService.getVitalSample(VITAL_ID)).thenReturn(Optional.of(existingDto()));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(true);
            when(vitalSampleService.updateVitalSample(VITAL_ID, updateDto())).thenReturn(updateDto());

            final ResponseEntity<?> response = controller.updateVitalSample(VITAL_ID, updateDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void familyMemberWithoutAccessIsRejected() throws Exception {
            mockAuth();
            final User familyMember = makeUser(USER_ID, Role.FAMILY_MEMBER);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(familyMember));
            when(vitalSampleService.getVitalSample(VITAL_ID)).thenReturn(Optional.of(existingDto()));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(caregiverService.hasAccessToPatient(USER_ID, PATIENT_ID)).thenReturn(false);

            final ResponseEntity<?> response = controller.updateVitalSample(VITAL_ID, updateDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        }

        @Test
        void returnsNotFoundWhenPatientMissingAfterVitalFound() throws Exception {
            mockAuth();
            final User admin = makeUser(USER_ID, Role.ADMIN);

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
            when(vitalSampleService.getVitalSample(VITAL_ID)).thenReturn(Optional.of(existingDto()));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.empty());

            final ResponseEntity<?> response = controller.updateVitalSample(VITAL_ID, updateDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        }

        @Test
        void adminCanUpdateAnyVitalSample() throws Exception {
            mockAuth();
            final User admin = makeUser(USER_ID, Role.ADMIN);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
            when(vitalSampleService.getVitalSample(VITAL_ID)).thenReturn(Optional.of(existingDto()));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(vitalSampleService.updateVitalSample(VITAL_ID, updateDto())).thenReturn(updateDto());

            final ResponseEntity<?> response = controller.updateVitalSample(VITAL_ID, updateDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        }

        @Test
        void returnsNotFoundWhenVitalSampleMissing() throws Exception {
            mockAuth();
            final User admin = makeUser(USER_ID, Role.ADMIN);

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
            when(vitalSampleService.getVitalSample(VITAL_ID)).thenReturn(Optional.empty());

            final ResponseEntity<?> response = controller.updateVitalSample(VITAL_ID, updateDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        }

        @Test
        void returnsBadRequestOnIllegalArgument() throws Exception {
            mockAuth();
            final User admin = makeUser(USER_ID, Role.ADMIN);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
            when(vitalSampleService.getVitalSample(VITAL_ID)).thenReturn(Optional.of(existingDto()));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(vitalSampleService.updateVitalSample(eq(VITAL_ID), any()))
                    .thenThrow(new IllegalArgumentException("Invalid value"));

            final ResponseEntity<?> response = controller.updateVitalSample(VITAL_ID, updateDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        }

        @Test
        void returnsInternalServerErrorOnUnexpectedException() throws Exception {
            mockAuth();
            final User admin = makeUser(USER_ID, Role.ADMIN);
            final Patient patient = makePatient(makeUser(OTHER_ID, Role.PATIENT));

            when(userRepository.findByEmail(USER_EMAIL)).thenReturn(Optional.of(admin));
            when(vitalSampleService.getVitalSample(VITAL_ID)).thenReturn(Optional.of(existingDto()));
            when(patientRepository.findById(PATIENT_ID)).thenReturn(Optional.of(patient));
            when(vitalSampleService.updateVitalSample(eq(VITAL_ID), any()))
                    .thenThrow(new RuntimeException("Unexpected"));

            final ResponseEntity<?> response = controller.updateVitalSample(VITAL_ID, updateDto());

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private Object bodyValue(ResponseEntity<?> response, String key) {
        return ((Map<String, Object>) response.getBody()).get(key);
    }
}