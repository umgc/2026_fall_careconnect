package com.careconnect.controller;

import com.careconnect.dto.AiRetrievalConsentRequest;
import com.careconnect.dto.AiRetrievalConsentResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.ConsentGrant;
import com.careconnect.model.User;
import com.careconnect.security.Role;
import com.careconnect.service.ConsentService;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Patient-facing AI-retrieval consent grant/revoke API (Task 2.4).
 *
 * <p>The authenticated patient is always the grantor ({@code patientUserId}). Caregivers
 * cannot grant or revoke consent on a patient's behalf through this controller.
 */
@RestController
@RequiredArgsConstructor
@RequestMapping({"/api/v3/consent", "/v1/api/v3/consent"})
@Tag(name = "Consent", description = "Patient consent grants for Ask AI retrieval")
@SecurityRequirement(name = "bearerAuth")
public class ConsentController {

    private final ConsentService consentService;
    private final SecurityUtil securityUtil;

    @PostMapping(
            value = "/ai-retrieval",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    @Operation(summary = "Grant AI-retrieval consent to a caregiver")
    public ResponseEntity<AiRetrievalConsentResponse> grantAiRetrieval(
            @RequestBody final AiRetrievalConsentRequest request) {
        final User patient = requirePatientCaller();
        if (request == null || request.granteeUserId() == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "granteeUserId is required");
        }
        final ConsentGrant grant = consentService.grantAiRetrievalConsent(
                patient.getId(),
                request.granteeUserId(),
                request.granteeRole(),
                request.expiresAt());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(AiRetrievalConsentResponse.from(grant));
    }

    @DeleteMapping(
            value = "/ai-retrieval",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    @Operation(summary = "Revoke AI-retrieval consent previously granted to a caregiver")
    public ResponseEntity<Map<String, Object>> revokeAiRetrieval(
            @RequestBody final AiRetrievalConsentRequest request) {
        final User patient = requirePatientCaller();
        if (request == null || request.granteeUserId() == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "granteeUserId is required");
        }
        final Long granteeUserId = request.granteeUserId();
        final int revoked =
                consentService.revokeAiRetrievalConsent(patient.getId(), granteeUserId);
        return ResponseEntity.ok(Map.of(
                "patientUserId", patient.getId(),
                "granteeUserId", granteeUserId,
                "revokedCount", revoked));
    }

    @GetMapping(value = "/ai-retrieval", produces = MediaType.APPLICATION_JSON_VALUE)
    @Operation(summary = "Check whether AI-retrieval consent is currently active")
    public ResponseEntity<Map<String, Object>> checkAiRetrieval(
            @RequestParam final Long patientUserId,
            @RequestParam final Long granteeUserId) {
        final User caller = requireAuthenticatedCaller();
        // Patient may check their own grants; grantee may check grants issued to them.
        final boolean selfPatient = caller.getId().equals(patientUserId);
        final boolean selfGrantee = caller.getId().equals(granteeUserId);
        if (!selfPatient && !selfGrantee && caller.getRole() != Role.ADMIN) {
            throw new AppException(HttpStatus.FORBIDDEN, "Not allowed to inspect this consent");
        }
        final boolean explicitGrant =
                consentService.isAiRetrievalConsentGranted(granteeUserId, patientUserId);
        final boolean effectiveConsent =
                consentService.isEffectiveAiRetrievalConsent(granteeUserId, patientUserId);
        return ResponseEntity.ok(Map.of(
                "patientUserId", patientUserId,
                "granteeUserId", granteeUserId,
                // `granted` mirrors Ask AI effective consent so the dashboard toggle matches
                // retrieval (including care-circle grandfather when no grant history exists).
                "granted", effectiveConsent,
                "explicitGrant", explicitGrant,
                "effectiveConsent", effectiveConsent));
    }

    private User requirePatientCaller() {
        final User caller = requireAuthenticatedCaller();
        if (caller.getRole() != Role.PATIENT) {
            throw new AppException(
                    HttpStatus.FORBIDDEN, "Only the patient may manage AI retrieval consent");
        }
        return caller;
    }

    private User requireAuthenticatedCaller() {
        final User caller = securityUtil.resolveCurrentUser();
        if (caller == null || caller.getId() == null) {
            throw new AppException(HttpStatus.UNAUTHORIZED, "Authentication required");
        }
        return caller;
    }
}
