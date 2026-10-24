package com.careconnect.controller.ehr;

import com.careconnect.dto.ehr.EhrIdentityConflictResolveRequest;
import com.careconnect.ehr.reconciliation.IdentityReconciler;
import com.careconnect.ehr.reconciliation.ReconciliationOutcome;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrConflictStatus;
import com.careconnect.model.ehr.EhrIdentityConflict;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrIdentityConflictRepository;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link EhrIdentityConflictController} (review item I3e) — the patient-only,
 * source-generic DOB identity-conflict surface that replaces the retired Epic endpoint. Collaborators
 * are mocked and the controller is driven directly (no Spring context). Covers the migrated DOB cases
 * (auth gating, accept/reject outcome, no-pending 409) plus the new by-id contract: list envelope,
 * not-owned 404, and non-pending / non-DOB 409.
 */
class EhrIdentityConflictControllerTest {

    private final SecurityUtil securityUtil = mock(SecurityUtil.class);
    private final PatientRepository patientRepository = mock(PatientRepository.class);
    private final EhrIdentityConflictRepository conflictRepo =
            mock(EhrIdentityConflictRepository.class);
    private final IdentityReconciler identityReconciler = mock(IdentityReconciler.class);

    private EhrIdentityConflictController newController() {
        return new EhrIdentityConflictController(
                securityUtil, patientRepository, conflictRepo, identityReconciler);
    }

    private User nonPatient(long id) {
        User u = mock(User.class);
        when(u.getId()).thenReturn(id);
        return u; // isPatient() defaults to false
    }

    /** Authenticate as a patient whose user id maps to {@code patientId}. */
    private void asPatient(long userId, long patientId) {
        User me = mock(User.class);
        when(me.getId()).thenReturn(userId);
        when(me.isPatient()).thenReturn(true);
        when(securityUtil.resolveCurrentUser()).thenReturn(me);
        Patient p = mock(Patient.class);
        when(p.getId()).thenReturn(patientId);
        when(patientRepository.findByUserId(userId)).thenReturn(Optional.of(p));
    }

    private EhrIdentityConflict conflict(long id, long patientId, String field, EhrConflictStatus status) {
        return EhrIdentityConflict.builder()
                .id(id)
                .patientId(patientId)
                .sourceId(1L)
                .fieldName(field)
                .canonicalValueBefore("1980-01-01")
                .incomingValue("1985-05-14")
                .status(status)
                .sourceUpdatedAt(Instant.parse("2026-09-26T00:00:00Z"))
                .detectedAt(Instant.parse("2026-09-26T00:00:00Z"))
                .build();
    }

    // ---- GET /v1/api/ehr/identity-conflicts ------------------------------

    @Test
    void list_returnsUnauthorized_whenNoCurrentUser() {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);
        assertThat(newController().list("PENDING").getStatusCode().value())
                .isEqualTo(HttpStatus.UNAUTHORIZED.value());
    }

    @Test
    void list_returnsForbidden_forNonPatient() {
        User me = nonPatient(7L); // build before the outer when(), not nested in it
        when(securityUtil.resolveCurrentUser()).thenReturn(me);
        assertThat(newController().list("PENDING").getStatusCode().value())
                .isEqualTo(HttpStatus.FORBIDDEN.value());
    }

    @Test
    void list_returnsConflict_whenNoPatientRecord() {
        User me = mock(User.class);
        when(me.getId()).thenReturn(7L);
        when(me.isPatient()).thenReturn(true);
        when(securityUtil.resolveCurrentUser()).thenReturn(me);
        when(patientRepository.findByUserId(7L)).thenReturn(Optional.empty());
        assertThat(newController().list("PENDING").getStatusCode().value())
                .isEqualTo(HttpStatus.CONFLICT.value());
    }

    @Test
    void list_returnsResourcesEnvelope_withMappedRows() {
        asPatient(7L, 100L);
        when(conflictRepo.findByPatientIdAndStatus(100L, EhrConflictStatus.PENDING))
                .thenReturn(List.of(conflict(5L, 100L, "date_of_birth", EhrConflictStatus.PENDING)));

        ResponseEntity<Map<String, Object>> resp = newController().list("PENDING");

        assertThat(resp.getStatusCode().value()).isEqualTo(HttpStatus.OK.value());
        Object resources = resp.getBody().get("resources");
        assertThat(resources).isInstanceOf(List.class);
        assertThat((List<?>) resources).hasSize(1);
    }

    @Test
    void list_defaultsToPending_andRejectsUnknownStatus() {
        asPatient(7L, 100L);
        assertThat(newController().list("BOGUS").getStatusCode().value())
                .isEqualTo(HttpStatus.BAD_REQUEST.value());
    }

    // ---- POST /v1/api/ehr/identity-conflicts/{id}/resolve ----------------

    @Test
    void resolve_returnsUnauthorized_whenNoCurrentUser() {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);
        assertThat(newController()
                .resolve(5L, new EhrIdentityConflictResolveRequest("ACCEPTED", "PATIENT"))
                .getStatusCode().value()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
    }

    @Test
    void resolve_returnsForbidden_forNonPatient() {
        User me = nonPatient(7L); // build before the outer when(), not nested in it
        when(securityUtil.resolveCurrentUser()).thenReturn(me);
        assertThat(newController()
                .resolve(5L, new EhrIdentityConflictResolveRequest("ACCEPTED", "PATIENT"))
                .getStatusCode().value()).isEqualTo(HttpStatus.FORBIDDEN.value());
    }

    @Test
    void resolve_returnsBadRequest_whenStatusMissing() {
        asPatient(7L, 100L);
        assertThat(newController().resolve(5L, null).getStatusCode().value())
                .isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(newController()
                .resolve(5L, new EhrIdentityConflictResolveRequest(null, "PATIENT"))
                .getStatusCode().value()).isEqualTo(HttpStatus.BAD_REQUEST.value());
    }

    @Test
    void resolve_returnsBadRequest_whenStatusInvalid() {
        asPatient(7L, 100L);
        assertThat(newController()
                .resolve(5L, new EhrIdentityConflictResolveRequest("MAYBE", "PATIENT"))
                .getStatusCode().value()).isEqualTo(HttpStatus.BAD_REQUEST.value());
    }

    @Test
    void resolve_returnsNotFound_whenIdUnknown() {
        asPatient(7L, 100L);
        when(conflictRepo.findById(5L)).thenReturn(Optional.empty());
        assertThat(newController()
                .resolve(5L, new EhrIdentityConflictResolveRequest("ACCEPTED", "PATIENT"))
                .getStatusCode().value()).isEqualTo(HttpStatus.NOT_FOUND.value());
    }

    @Test
    void resolve_returnsNotFound_whenOwnedByAnotherPatient() {
        asPatient(7L, 100L);
        when(conflictRepo.findById(5L))
                .thenReturn(Optional.of(conflict(5L, 999L, "date_of_birth", EhrConflictStatus.PENDING)));
        assertThat(newController()
                .resolve(5L, new EhrIdentityConflictResolveRequest("ACCEPTED", "PATIENT"))
                .getStatusCode().value()).isEqualTo(HttpStatus.NOT_FOUND.value());
        verify(identityReconciler, never()).finalizePendingDateOfBirth(org.mockito.ArgumentMatchers.anyLong(),
                org.mockito.ArgumentMatchers.anyBoolean());
    }

    @Test
    void resolve_returnsConflict_whenNotPendingOrNotDob() {
        asPatient(7L, 100L);
        // non-DOB field, still PENDING
        when(conflictRepo.findById(5L))
                .thenReturn(Optional.of(conflict(5L, 100L, "phone", EhrConflictStatus.PENDING)));
        assertThat(newController()
                .resolve(5L, new EhrIdentityConflictResolveRequest("ACCEPTED", "PATIENT"))
                .getStatusCode().value()).isEqualTo(HttpStatus.CONFLICT.value());
        // DOB field, already resolved
        when(conflictRepo.findById(6L))
                .thenReturn(Optional.of(conflict(6L, 100L, "date_of_birth", EhrConflictStatus.ACCEPTED)));
        assertThat(newController()
                .resolve(6L, new EhrIdentityConflictResolveRequest("ACCEPTED", "PATIENT"))
                .getStatusCode().value()).isEqualTo(HttpStatus.CONFLICT.value());
    }

    @Test
    void resolve_accepted_returnsOutcome() {
        asPatient(7L, 100L);
        when(conflictRepo.findById(5L))
                .thenReturn(Optional.of(conflict(5L, 100L, "date_of_birth", EhrConflictStatus.PENDING)));
        when(identityReconciler.finalizePendingDateOfBirth(100L, true)).thenReturn(
                new ReconciliationOutcome("date_of_birth",
                        ReconciliationOutcome.Decision.ACCEPTED_BY_PATIENT, "1985-05-14"));

        ResponseEntity<Map<String, Object>> resp = newController()
                .resolve(5L, new EhrIdentityConflictResolveRequest("ACCEPTED", "PATIENT"));

        assertThat(resp.getStatusCode().value()).isEqualTo(HttpStatus.OK.value());
        assertThat(resp.getBody()).containsEntry("fieldName", "date_of_birth");
        assertThat(resp.getBody()).containsEntry("decision", "ACCEPTED_BY_PATIENT");
        assertThat(resp.getBody()).containsEntry("appliedValue", "1985-05-14");
        verify(identityReconciler).finalizePendingDateOfBirth(100L, true);
    }

    @Test
    void resolve_rejected_mapsToAcceptIncomingFalse() {
        asPatient(7L, 100L);
        when(conflictRepo.findById(5L))
                .thenReturn(Optional.of(conflict(5L, 100L, "date_of_birth", EhrConflictStatus.PENDING)));
        when(identityReconciler.finalizePendingDateOfBirth(100L, false)).thenReturn(
                new ReconciliationOutcome("date_of_birth",
                        ReconciliationOutcome.Decision.REJECTED_BY_PATIENT, null));

        ResponseEntity<Map<String, Object>> resp = newController()
                .resolve(5L, new EhrIdentityConflictResolveRequest("REJECTED", "PATIENT"));

        assertThat(resp.getStatusCode().value()).isEqualTo(HttpStatus.OK.value());
        verify(identityReconciler).finalizePendingDateOfBirth(100L, false);
    }

    @Test
    void resolve_returnsConflict_whenReconcilerFindsNothingPending() {
        asPatient(7L, 100L);
        when(conflictRepo.findById(5L))
                .thenReturn(Optional.of(conflict(5L, 100L, "date_of_birth", EhrConflictStatus.PENDING)));
        when(identityReconciler.finalizePendingDateOfBirth(100L, true))
                .thenThrow(new IllegalStateException("no pending DOB conflict"));

        assertThat(newController()
                .resolve(5L, new EhrIdentityConflictResolveRequest("ACCEPTED", "PATIENT"))
                .getStatusCode().value()).isEqualTo(HttpStatus.CONFLICT.value());
    }
}
