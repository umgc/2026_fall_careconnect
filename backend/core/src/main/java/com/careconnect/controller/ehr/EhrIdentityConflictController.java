package com.careconnect.controller.ehr;

import com.careconnect.dto.ehr.EhrIdentityConflictResolveRequest;
import com.careconnect.dto.ehr.EhrIdentityConflictView;
import com.careconnect.ehr.reconciliation.IdentityReconciler;
import com.careconnect.ehr.reconciliation.ReconciliationOutcome;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrConflictStatus;
import com.careconnect.model.ehr.EhrIdentityConflict;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrIdentityConflictRepository;
import com.careconnect.util.SecurityUtil;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Patient-only identity-conflict surface (Cononical_5_1 Step 7; review item I3e). Source-generic
 * replacement for the retired Epic-specific {@code POST /api/epic/identity/date-of-birth}: the
 * frontend DOB confirmation screen lists its pending conflicts here and resolves them by id.
 *
 * <ul>
 *   <li>{@code GET /v1/api/ehr/identity-conflicts?status=PENDING} — the caller's own conflicts.</li>
 *   <li>{@code POST /v1/api/ehr/identity-conflicts/{id}/resolve} — confirm or decline a pending
 *       {@code date_of_birth} conflict; delegates to
 *       {@link IdentityReconciler#finalizePendingDateOfBirth}.</li>
 * </ul>
 *
 * <p>Patient self-service only — a caregiver/admin is refused with 403, mirroring the retired
 * endpoint. {@code date_of_birth} is the one patient-resolvable field ({@code EhrConflictResolver}
 * has {@code PATIENT} for it alone); every other field auto-resolves and is never PENDING, so a
 * resolve against a non-DOB or already-closed conflict is a 409.
 */
@Slf4j
@RestController
@RequestMapping("/v1/api/ehr/identity-conflicts")
@RequiredArgsConstructor
public class EhrIdentityConflictController {

    private static final String DOB_FIELD = "date_of_birth";

    private final SecurityUtil securityUtil;
    private final PatientRepository patientRepository;
    private final EhrIdentityConflictRepository conflictRepo;
    private final IdentityReconciler identityReconciler;

    /**
     * List the authenticated patient's identity conflicts in {@code status} (default PENDING),
     * wrapped as {@code {"resources":[...]}} so the body matches the frontend's envelope.
     */
    @GetMapping
    public ResponseEntity<Map<String, Object>> list(
            @RequestParam(required = false, defaultValue = "PENDING") final String status) {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        if (!me.isPatient()) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        final Long patientId = patientRepository.findByUserId(me.getId())
                .map(Patient::getId).orElse(null);
        if (patientId == null) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("error", "No patient record for this account"));
        }
        final EhrConflictStatus parsed;
        try {
            parsed = EhrConflictStatus.valueOf(status.toUpperCase());
        } catch (final IllegalArgumentException ex) {
            return ResponseEntity.badRequest().body(Map.of("error", "Unknown status: " + status));
        }
        final List<EhrIdentityConflictView> resources =
                conflictRepo.findByPatientIdAndStatus(patientId, parsed).stream()
                        .map(EhrIdentityConflictController::toView)
                        .toList();
        return ResponseEntity.ok(Map.of("resources", resources));
    }

    /**
     * Resolve one pending {@code date_of_birth} conflict for the authenticated patient. Translates
     * the frontend's by-id contract onto the reconciler's by-patient finalize call: the id is used
     * only to locate and authorize the conflict; the reconciler always acts on the one open DOB
     * conflict for the patient.
     *
     * @return 200 with the reconciliation outcome; 404 if the id is unknown or not the caller's;
     *         409 if it is not a pending {@code date_of_birth}; 400 on a missing/invalid status.
     */
    @PostMapping("/{id}/resolve")
    public ResponseEntity<Map<String, Object>> resolve(
            @PathVariable("id") final Long id,
            @RequestBody(required = false) final EhrIdentityConflictResolveRequest request) {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        if (!me.isPatient()) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        final Long patientId = patientRepository.findByUserId(me.getId())
                .map(Patient::getId).orElse(null);
        if (patientId == null) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("error", "No patient record for this account"));
        }
        if (request == null || request.status() == null) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "status (ACCEPTED|REJECTED) is required"));
        }
        final Boolean acceptIncoming = switch (request.status().toUpperCase()) {
            case "ACCEPTED" -> Boolean.TRUE;
            case "REJECTED" -> Boolean.FALSE;
            default -> null;
        };
        if (acceptIncoming == null) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "status must be ACCEPTED or REJECTED"));
        }
        // Not-found and not-owned are the same 404 — never reveal another patient's conflict id.
        final EhrIdentityConflict conflict = conflictRepo.findById(id).orElse(null);
        if (conflict == null || !patientId.equals(conflict.getPatientId())) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        if (conflict.getStatus() != EhrConflictStatus.PENDING
                || !DOB_FIELD.equals(conflict.getFieldName())) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of(
                    "error", "Conflict is not a pending date_of_birth and cannot be resolved here"));
        }
        try {
            final ReconciliationOutcome outcome =
                    identityReconciler.finalizePendingDateOfBirth(patientId, acceptIncoming);
            final Map<String, Object> body = new HashMap<>();
            body.put("fieldName", outcome.fieldName());
            body.put("decision", outcome.decision().name());
            body.put("appliedValue", outcome.appliedValue());
            return ResponseEntity.ok(body);
        } catch (final IllegalStateException ex) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("error", "No pending date_of_birth conflict to resolve"));
        }
    }

    private static EhrIdentityConflictView toView(final EhrIdentityConflict c) {
        return new EhrIdentityConflictView(
                c.getId(),
                c.getFieldName(),
                c.getCanonicalValueBefore(),
                c.getIncomingValue(),
                c.getStatus() == null ? null : c.getStatus().name(),
                c.getDetectedAt() == null ? null : c.getDetectedAt().toString());
    }
}
