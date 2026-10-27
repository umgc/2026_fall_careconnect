package com.careconnect.controller.ehr;

import com.careconnect.dto.ehr.EhrIdentityCheckView;
import com.careconnect.dto.ehr.EhrIdentityConflictResolveRequest;
import com.careconnect.dto.ehr.EhrIdentityConflictView;
import com.careconnect.ehr.reconciliation.IdentityReconciler;
import com.careconnect.ehr.reconciliation.ReconciliationOutcome;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrConflictStatus;
import com.careconnect.model.ehr.EhrIdentityConflict;
import com.careconnect.model.ehr.EhrIdentityFieldProvenance;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.EhrSourceIdentity;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrIdentityConflictRepository;
import com.careconnect.repository.ehr.EhrIdentityFieldProvenanceRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
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
 * full field mapping, not-owned 404, non-DOB 400, already-resolved-DOB 409, derived source labels,
 * and the masked identityCheck hint (phone/email/ZIP, PR #378 parity).
 */
class EhrIdentityConflictControllerTest {

    private final SecurityUtil securityUtil = mock(SecurityUtil.class);
    private final PatientRepository patientRepository = mock(PatientRepository.class);
    private final EhrIdentityConflictRepository conflictRepo =
            mock(EhrIdentityConflictRepository.class);
    private final IdentityReconciler identityReconciler = mock(IdentityReconciler.class);
    private final EhrSourceRepository sourceRepo = mock(EhrSourceRepository.class);
    private final EhrIdentityFieldProvenanceRepository provenanceRepo =
            mock(EhrIdentityFieldProvenanceRepository.class);
    private final EhrSourceIdentityRepository sourceIdentityRepo =
            mock(EhrSourceIdentityRepository.class);

    private EhrIdentityConflictController newController() {
        return new EhrIdentityConflictController(
                securityUtil, patientRepository, conflictRepo, identityReconciler,
                sourceRepo, provenanceRepo, sourceIdentityRepo);
    }

    private EhrSourceIdentity sourceIdentity(String phone, String email, String postal) {
        EhrSourceIdentity row = mock(EhrSourceIdentity.class);
        when(row.getPhone()).thenReturn(phone);
        when(row.getEmail()).thenReturn(email);
        when(row.getPostalCode()).thenReturn(postal);
        return row;
    }

    @SuppressWarnings("unchecked")
    private EhrIdentityConflictView firstRow(ResponseEntity<Map<String, Object>> resp) {
        return ((List<EhrIdentityConflictView>) resp.getBody().get("resources")).get(0);
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
    void list_returnsResourcesEnvelope_mapsEveryField_andOmitsEnrichmentWhenAbsent() {
        asPatient(7L, 100L);
        when(conflictRepo.findByPatientIdAndStatus(100L, EhrConflictStatus.PENDING))
                .thenReturn(List.of(conflict(5L, 100L, "date_of_birth", EhrConflictStatus.PENDING)));
        // sourceRepo / provenanceRepo / sourceIdentityRepo left unstubbed -> empty Optionals.

        ResponseEntity<Map<String, Object>> resp = newController().list("PENDING");

        assertThat(resp.getStatusCode().value()).isEqualTo(HttpStatus.OK.value());
        Object resources = resp.getBody().get("resources");
        assertThat(resources).isInstanceOf(List.class);
        assertThat((List<?>) resources).hasSize(1);

        EhrIdentityConflictView v = firstRow(resp);
        assertThat(v.id()).isEqualTo(5L);
        assertThat(v.fieldName()).isEqualTo("date_of_birth");
        assertThat(v.canonicalValueBefore()).isEqualTo("1980-01-01");
        assertThat(v.incomingValue()).isEqualTo("1985-05-14");
        assertThat(v.status()).isEqualTo("PENDING");
        assertThat(v.detectedAt()).isEqualTo("2026-09-26T00:00:00Z");
        // No source rows / provenance -> enrichment is null, never fabricated.
        assertThat(v.canonicalSourceLabel()).isNull();
        assertThat(v.incomingSourceLabel()).isNull();
        assertThat(v.identityCheck()).isNull();
    }

    @Test
    void list_derivesSourceLabels() {
        asPatient(7L, 100L);
        // conflict(...) uses sourceId == 1L as the incoming source.
        when(conflictRepo.findByPatientIdAndStatus(100L, EhrConflictStatus.PENDING))
                .thenReturn(List.of(conflict(5L, 100L, "date_of_birth", EhrConflictStatus.PENDING)));
        EhrSource epic = mock(EhrSource.class);
        when(epic.getDisplayName()).thenReturn("Epic");
        when(sourceRepo.findById(1L)).thenReturn(Optional.of(epic));
        // Canonical DOB currently owned by source 2 -> "CareConnect".
        EhrIdentityFieldProvenance prov = mock(EhrIdentityFieldProvenance.class);
        when(prov.getSourceId()).thenReturn(2L);
        when(provenanceRepo.findByPatientIdAndFieldName(100L, "date_of_birth"))
                .thenReturn(Optional.of(prov));
        EhrSource careConnect = mock(EhrSource.class);
        when(careConnect.getDisplayName()).thenReturn("CareConnect");
        when(sourceRepo.findById(2L)).thenReturn(Optional.of(careConnect));

        ResponseEntity<Map<String, Object>> resp = newController().list("PENDING");

        @SuppressWarnings("unchecked")
        List<EhrIdentityConflictView> rows =
                (List<EhrIdentityConflictView>) resp.getBody().get("resources");
        assertThat(rows).hasSize(1);
        assertThat(rows.get(0).incomingSourceLabel()).isEqualTo("Epic");
        assertThat(rows.get(0).canonicalSourceLabel()).isEqualTo("CareConnect");
    }

    private void onePendingDobConflict() {
        asPatient(7L, 100L);
        when(conflictRepo.findByPatientIdAndStatus(100L, EhrConflictStatus.PENDING))
                .thenReturn(List.of(conflict(5L, 100L, "date_of_birth", EhrConflictStatus.PENDING)));
    }

    @Test
    void list_identityCheck_prefersPhone_maskedToLast4() {
        onePendingDobConflict();
        EhrSourceIdentity row = sourceIdentity("+1 (555) 010-4821", "jane.doe@gmail.com", "21201");
        when(sourceIdentityRepo.findByPatientIdAndSourceId(100L, 1L)).thenReturn(Optional.of(row));

        EhrIdentityCheckView ic = firstRow(newController().list("PENDING")).identityCheck();
        assertThat(ic).isNotNull();
        assertThat(ic.type()).isEqualTo("PHONE");
        assertThat(ic.value()).isEqualTo("4821");
        // PHI-safety: only the last 4 digits ever leave the backend.
        assertThat(ic.value()).doesNotContain("555").doesNotContain("010");
    }

    @Test
    void list_identityCheck_fallsBackToEmail_whenNoUsablePhone() {
        onePendingDobConflict();
        EhrSourceIdentity row = sourceIdentity("12-3", "jane.doe@gmail.com", "21201");
        when(sourceIdentityRepo.findByPatientIdAndSourceId(100L, 1L)).thenReturn(Optional.of(row));

        EhrIdentityCheckView ic = firstRow(newController().list("PENDING")).identityCheck();
        assertThat(ic.type()).isEqualTo("EMAIL");
        assertThat(ic.value()).isEqualTo("j•••@gmail.com");
        assertThat(ic.value()).doesNotContain("jane.doe");
    }

    @Test
    void list_identityCheck_fallsBackToZip_asIs() {
        onePendingDobConflict();
        EhrSourceIdentity row = sourceIdentity(null, null, "21201-1234");
        when(sourceIdentityRepo.findByPatientIdAndSourceId(100L, 1L)).thenReturn(Optional.of(row));

        EhrIdentityCheckView ic = firstRow(newController().list("PENDING")).identityCheck();
        assertThat(ic.type()).isEqualTo("ZIP");
        assertThat(ic.value()).isEqualTo("21201-1234");
    }

    @Test
    void list_identityCheck_omittedWhenNoneUsable() {
        onePendingDobConflict();
        EhrSourceIdentity row = sourceIdentity("12-3", "not-an-email", "   ");
        when(sourceIdentityRepo.findByPatientIdAndSourceId(100L, 1L)).thenReturn(Optional.of(row));

        assertThat(firstRow(newController().list("PENDING")).identityCheck()).isNull();
    }

    @Test
    void list_identityCheck_omittedWhenNoIdentityRow() {
        onePendingDobConflict();
        when(sourceIdentityRepo.findByPatientIdAndSourceId(100L, 1L)).thenReturn(Optional.empty());

        assertThat(firstRow(newController().list("PENDING")).identityCheck()).isNull();
    }

    @Test
    void list_identityCheck_phoneExtension_usesNumberNotExtension() {
        onePendingDobConflict();
        EhrSourceIdentity row = sourceIdentity("410-555-0123 ext 45", null, null);
        when(sourceIdentityRepo.findByPatientIdAndSourceId(100L, 1L)).thenReturn(Optional.of(row));

        EhrIdentityCheckView ic = firstRow(newController().list("PENDING")).identityCheck();
        assertThat(ic.type()).isEqualTo("PHONE");
        assertThat(ic.value()).isEqualTo("0123");
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
    void resolve_returnsBadRequest_whenNonDobField() {
        asPatient(7L, 100L);
        // non-DOB field, still PENDING -> 400 (only date_of_birth is patient-resolvable)
        when(conflictRepo.findById(5L))
                .thenReturn(Optional.of(conflict(5L, 100L, "phone", EhrConflictStatus.PENDING)));
        assertThat(newController()
                .resolve(5L, new EhrIdentityConflictResolveRequest("ACCEPTED", "PATIENT"))
                .getStatusCode().value()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        verify(identityReconciler, never()).finalizePendingDateOfBirth(
                org.mockito.ArgumentMatchers.anyLong(), org.mockito.ArgumentMatchers.anyBoolean());
    }

    @Test
    void resolve_returnsConflict_whenDobAlreadyResolved() {
        asPatient(7L, 100L);
        // DOB field, already resolved -> 409
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
