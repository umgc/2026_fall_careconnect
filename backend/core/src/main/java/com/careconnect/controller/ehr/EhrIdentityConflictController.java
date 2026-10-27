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
import java.util.Objects;
import java.util.regex.Pattern;

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
 * resolve against a non-DOB field is a 400 and against an already-closed DOB conflict is a 409.
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
    private final EhrSourceRepository sourceRepo;
    private final EhrIdentityFieldProvenanceRepository provenanceRepo;
    private final EhrSourceIdentityRepository sourceIdentityRepo;

    /** Trailing phone extension, mirroring the frontend regex from PR #378 (DEF-EHR-REC-07). */
    private static final Pattern PHONE_EXTENSION =
            Pattern.compile("(?i)\\s*(?:;\\s*ext=|extension|ext\\.?|x|#)\\s*\\d+\\s*$");

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
                        .map(this::toView)
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
     *         400 if the field is not {@code date_of_birth} or the status is missing/invalid;
     *         409 if the {@code date_of_birth} conflict is not pending (already resolved).
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
        if (!DOB_FIELD.equals(conflict.getFieldName())) {
            // Only date_of_birth is patient-resolvable; a non-DOB field is a client error (400),
            // not a state conflict.
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Only date_of_birth conflicts can be resolved here"));
        }
        if (conflict.getStatus() != EhrConflictStatus.PENDING) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of(
                    "error", "Conflict is not pending and cannot be resolved"));
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

    private EhrIdentityConflictView toView(final EhrIdentityConflict c) {
        return new EhrIdentityConflictView(
                c.getId(),
                c.getFieldName(),
                c.getCanonicalValueBefore(),
                c.getIncomingValue(),
                canonicalSourceLabel(c),
                incomingSourceLabel(c),
                c.getStatus() == null ? null : c.getStatus().name(),
                c.getDetectedAt() == null ? null : c.getDetectedAt().toString(),
                identityCheck(c));
    }

    /**
     * A hidden second detail (phone, else email, else ZIP) from the incoming source's identity row
     * for the patient to confirm, or null when the source has none. Masked server-side so no raw
     * phone/email is sent; the shape matches PR #378's {@code IdentityCheck}.
     */
    private EhrIdentityCheckView identityCheck(final EhrIdentityConflict c) {
        if (c.getSourceId() == null) {
            return null;
        }
        return sourceIdentityRepo.findByPatientIdAndSourceId(c.getPatientId(), c.getSourceId())
                .map(EhrIdentityConflictController::toIdentityCheck)
                .orElse(null);
    }

    /** Phone first, then email, then ZIP (as-is); null when none is usable. */
    private static EhrIdentityCheckView toIdentityCheck(final EhrSourceIdentity row) {
        final String phone = phoneLast4(row.getPhone());
        if (phone != null) {
            return new EhrIdentityCheckView("PHONE", phone);
        }
        final String email = maskEmail(row.getEmail());
        if (email != null) {
            return new EhrIdentityCheckView("EMAIL", email);
        }
        final String zip = row.getPostalCode();
        if (zip != null && !zip.isBlank()) {
            return new EhrIdentityCheckView("ZIP", zip.trim());
        }
        return null;
    }

    /** Last 4 digits of the number (extension stripped), or null if fewer than 4 digits. */
    private static String phoneLast4(final String phone) {
        if (phone == null) {
            return null;
        }
        final String digits = PHONE_EXTENSION.matcher(phone).replaceFirst("").replaceAll("\\D", "");
        return digits.length() < 4 ? null : digits.substring(digits.length() - 4);
    }

    /** "jane.doe@gmail.com" -> "j•••@gmail.com", or null if it is not an email. */
    private static String maskEmail(final String email) {
        if (email == null) {
            return null;
        }
        final String e = email.trim();
        final int at = e.lastIndexOf('@');
        if (at < 1 || at == e.length() - 1) {
            return null;
        }
        return e.charAt(0) + "•••" + e.substring(at);
    }

    /** Display name of the source whose value is incoming in this conflict, or null if unknown. */
    private String incomingSourceLabel(final EhrIdentityConflict c) {
        if (c.getSourceId() == null) {
            return null;
        }
        return sourceRepo.findById(c.getSourceId())
                .map(EhrSource::getDisplayName)
                .orElse(null);
    }

    /**
     * Display name of the source that currently owns the canonical value for this field
     * (per {@code ehr_identity_field_provenance}), or null if no source has established provenance.
     */
    private String canonicalSourceLabel(final EhrIdentityConflict c) {
        return provenanceRepo.findByPatientIdAndFieldName(c.getPatientId(), c.getFieldName())
                .map(EhrIdentityFieldProvenance::getSourceId)
                .filter(Objects::nonNull)
                .flatMap(sourceRepo::findById)
                .map(EhrSource::getDisplayName)
                .orElse(null);
    }
}
