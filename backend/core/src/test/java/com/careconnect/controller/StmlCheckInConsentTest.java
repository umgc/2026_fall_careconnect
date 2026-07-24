package com.careconnect.controller;

import com.careconnect.dto.StmlCheckInDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.StmlCheckInService;
import com.careconnect.service.StmlRecallService;
import com.careconnect.service.StmlSearchService;
import com.careconnect.service.StmlService;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import com.careconnect.service.ai.retrieval.ScopeDenialReason;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Issue #213 — Tests: check-in hidden without caregiver consent.
 *
 * Verifies that STML-3 GET /patients/{patientId}/checkin:
 * - Returns 403 when RetrievalScopeService denies scope (no RBAC access)
 * - Returns 200 with consentGranted=false when scope passes but consent link is absent
 * - Returns 200 with consentGranted=true and full data when consent is granted
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("STML-3 Check-In Consent Gate Tests (Issue #213)")
class StmlCheckInConsentTest {

    @Mock private StmlService stmlService;
    @Mock private StmlRecallService stmlRecallService;
    @Mock private StmlCheckInService stmlCheckInService;
    @Mock private StmlSearchService stmlSearchService;
    @Mock private RetrievalScopeService retrievalScopeService;
    @Mock private UserRepository userRepository;

    @InjectMocks
    private StmlController stmlController;

    private static final Long PATIENT_ID = 1L;
    private static final Long CAREGIVER_ID = 2L;

    private User makeUser(Long id, Role role) {
        User u = new User();
        u.setId(id);
        u.setEmail("user" + id + "@test.com");
        u.setRole(role);
        return u;
    }

    private void setSecurityContext(User user) {
        SecurityContextHolder.getContext().setAuthentication(
            new UsernamePasswordAuthenticationToken(
                user.getEmail(), null, List.of()));
        when(userRepository.findByEmail(user.getEmail()))
            .thenReturn(Optional.of(user));
    }

    @BeforeEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    // ── Scenario 1: RBAC scope denied → 403 ──────────────────────────────────

    @Nested
    @DisplayName("When caller has no RBAC scope for patient")
    class NoRbacScope {

        @Test
        @DisplayName("Returns 403 when scope is denied for PATIENT role accessing another patient")
        void patient_accessingOtherPatient_returns403() throws Exception {
            // caller id must equal CAREGIVER_ID so the request clears the
            // caller-owns-caregiverId check and actually reaches
            // RetrievalScopeService — otherwise that check 403s first and
            // this stub is never invoked (UnnecessaryStubbingException).
            User otherPatient = makeUser(CAREGIVER_ID, Role.PATIENT);
            setSecurityContext(otherPatient);
            when(retrievalScopeService.resolveRetrievalScope(otherPatient, PATIENT_ID))
                .thenThrow(ForbiddenScopeException.of(
                    ScopeDenialReason.PATIENT_OUT_OF_SCOPE,
                    PATIENT_ID, otherPatient.getId(),
                    "Patient out of scope", UUID.randomUUID()));

            ResponseEntity<StmlCheckInDTO> response =
                stmlController.getCheckInView(PATIENT_ID, CAREGIVER_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
            verifyNoInteractions(stmlCheckInService);
        }

        @Test
        @DisplayName("Returns 403 when scope is denied for FAMILY_MEMBER with no access")
        void familyMember_noAccess_returns403() throws Exception {
            // Same reasoning as above — caller id must equal CAREGIVER_ID.
            User fm = makeUser(CAREGIVER_ID, Role.FAMILY_MEMBER);
            setSecurityContext(fm);
            when(retrievalScopeService.resolveRetrievalScope(fm, PATIENT_ID))
                .thenThrow(ForbiddenScopeException.of(
                    ScopeDenialReason.PATIENT_OUT_OF_SCOPE,
                    PATIENT_ID, fm.getId(),
                    "Patient out of scope", UUID.randomUUID()));

            ResponseEntity<StmlCheckInDTO> response =
                stmlController.getCheckInView(PATIENT_ID, CAREGIVER_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
            verifyNoInteractions(stmlCheckInService);
        }
    }

    // ── Scenario 2: RBAC passes but consent not granted → consentGranted=false ─

    @Nested
    @DisplayName("When RBAC scope passes but caregiver consent is not granted")
    class RbacPassesNoConsent {

        @Test
        @DisplayName("Returns 200 with consentGranted=false and empty data when no consent link")
        void caregiver_noConsentLink_returnsConsentDeniedDto() throws Exception {
            User caregiver = makeUser(CAREGIVER_ID, Role.CAREGIVER);
            setSecurityContext(caregiver);

            StmlCheckInDTO deniedDto = StmlCheckInDTO.builder()
                .patientId(PATIENT_ID)
                .caregiverId(CAREGIVER_ID)
                .generatedAt(LocalDateTime.now())
                .consentGranted(false)
                .notes(List.of())
                .pendingItems(List.of())
                .disclaimer("Access denied. The care recipient has not granted"
                    + " consent for caregiver check-in view.")
                .build();

            when(stmlCheckInService.getCheckInView(PATIENT_ID, CAREGIVER_ID))
                .thenReturn(deniedDto);

            ResponseEntity<StmlCheckInDTO> response =
                stmlController.getCheckInView(PATIENT_ID, CAREGIVER_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).isNotNull();
            assertThat(response.getBody().isConsentGranted()).isFalse();
            assertThat(response.getBody().getNotes()).isEmpty();
            assertThat(response.getBody().getPendingItems()).isEmpty();
            assertThat(response.getBody().getDisclaimer())
                .contains("has not granted");
            verify(stmlCheckInService).getCheckInView(PATIENT_ID, CAREGIVER_ID);
        }

        @Test
        @DisplayName("Check-in data (notes, medications, tasks) is hidden when consent not granted")
        void checkInData_isHidden_whenConsentNotGranted() throws Exception {
            User caregiver = makeUser(CAREGIVER_ID, Role.CAREGIVER);
            setSecurityContext(caregiver);

            StmlCheckInDTO deniedDto = StmlCheckInDTO.builder()
                .patientId(PATIENT_ID)
                .caregiverId(CAREGIVER_ID)
                .consentGranted(false)
                .notes(List.of())
                .pendingItems(List.of())
                .disclaimer("Access denied.")
                .build();

            when(stmlCheckInService.getCheckInView(PATIENT_ID, CAREGIVER_ID))
                .thenReturn(deniedDto);

            ResponseEntity<StmlCheckInDTO> response =
                stmlController.getCheckInView(PATIENT_ID, CAREGIVER_ID);

            StmlCheckInDTO body = response.getBody();
            assertThat(body).isNotNull();
            assertThat(body.isConsentGranted()).isFalse();
            assertThat(body.getNotes())
                .as("Medical notes must be hidden without consent")
                .isEmpty();
            assertThat(body.getPendingItems())
                .as("Pending tasks must be hidden without consent")
                .isEmpty();
        }
    }

    // ── Scenario 3: RBAC passes and consent granted → full data returned ──────

    @Nested
    @DisplayName("When RBAC scope passes and caregiver consent is granted")
    class RbacPassesConsentGranted {

        @Test
        @DisplayName("Returns 200 with consentGranted=true and full patient data")
        void caregiver_withConsent_returnsFullData() throws Exception {
            User caregiver = makeUser(CAREGIVER_ID, Role.CAREGIVER);
            setSecurityContext(caregiver);

            StmlCheckInDTO.StmlCheckInItemDTO medItem = StmlCheckInDTO.StmlCheckInItemDTO.builder()
                .type("MEDICATION")
                .summary("Metformin 500mg, twice daily")
                .source("MEDICATION")
                .build();

            StmlCheckInDTO.StmlCheckInItemDTO taskItem = StmlCheckInDTO.StmlCheckInItemDTO.builder()
                .type("TASK")
                .summary("Daily walk: 15 minutes")
                .source("TASK")
                .build();

            StmlCheckInDTO grantedDto = StmlCheckInDTO.builder()
                .patientId(PATIENT_ID)
                .caregiverId(CAREGIVER_ID)
                .generatedAt(LocalDateTime.now())
                .consentGranted(true)
                .notes(List.of(medItem))
                .pendingItems(List.of(taskItem))
                .disclaimer("This information is drawn from the care recipient's records.")
                .build();

            when(stmlCheckInService.getCheckInView(PATIENT_ID, CAREGIVER_ID))
                .thenReturn(grantedDto);

            ResponseEntity<StmlCheckInDTO> response =
                stmlController.getCheckInView(PATIENT_ID, CAREGIVER_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).isNotNull();
            assertThat(response.getBody().isConsentGranted()).isTrue();
            assertThat(response.getBody().getNotes()).hasSize(1);
            assertThat(response.getBody().getNotes().get(0).getType()).isEqualTo("MEDICATION");
            assertThat(response.getBody().getPendingItems()).hasSize(1);
            assertThat(response.getBody().getPendingItems().get(0).getType()).isEqualTo("TASK");
            verify(stmlCheckInService).getCheckInView(PATIENT_ID, CAREGIVER_ID);
        }

        @Test
        @DisplayName("ADMIN can access check-in with full data")
        void admin_canAccess_withFullData() throws Exception {
            User admin = makeUser(10L, Role.ADMIN);
            setSecurityContext(admin);

            StmlCheckInDTO grantedDto = StmlCheckInDTO.builder()
                .patientId(PATIENT_ID)
                .caregiverId(CAREGIVER_ID)
                .consentGranted(true)
                .notes(List.of())
                .pendingItems(List.of())
                .disclaimer("Admin access.")
                .build();

            when(stmlCheckInService.getCheckInView(PATIENT_ID, CAREGIVER_ID))
                .thenReturn(grantedDto);

            ResponseEntity<StmlCheckInDTO> response =
                stmlController.getCheckInView(PATIENT_ID, CAREGIVER_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody().isConsentGranted()).isTrue();
        }
    }
}
