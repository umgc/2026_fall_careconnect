package com.careconnect.controller;

import com.careconnect.client.ehr.EhrApiClient;
import com.careconnect.client.ehr.EhrApiClientRegistry;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.ResourceAccessException;

/**
 * Admin-only connectivity check for EHR adapters — fetches one FHIR resource type directly from
 * the live source and returns the raw JSON, with no CareConnect patient or
 * {@code ehr_patient_crosswalk} row involved.
 *
 * <p>Exists to verify adapter credentials (base URL, OAuth client id/secret) against a real
 * source before any patient-linking or sync flow is built on top — see
 * {@code docs/ehr-integration-foundation.md}. Protected by the same {@code /v1/api/debug/**}
 * admin rule as {@link DebugController} (see {@code SecurityConfig}).
 */
@Slf4j
@RestController
@RequestMapping("/v1/api/debug/ehr")
@RequiredArgsConstructor
public class EhrDebugController {

    private static final String ATHENAHEALTH_SOURCE_CODE = "ATHENAHEALTH";

    private final EhrApiClientRegistry ehrApiClientRegistry;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    /**
     * Example: {@code GET /v1/api/debug/ehr/athenahealth/resources/Patient?externalPatientId=a-123}
     * Example: {@code GET /v1/api/debug/ehr/athenahealth/resources/Appointment?externalPatientId=a-123}
     */
    @GetMapping("/athenahealth/resources/{resourceType}")
    public ResponseEntity<Map<String, Object>> fetchAthenahealthResources(
            @PathVariable String resourceType,
            @RequestParam String externalPatientId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdmin(currentUser);

        EhrApiClient client = ehrApiClientRegistry.get(ATHENAHEALTH_SOURCE_CODE);

        try {
            List<JsonNode> resources = client.fetchResources(resourceType, externalPatientId);
            return ResponseEntity.ok(Map.of(
                    "sourceCode", client.sourceCode(),
                    "resourceType", resourceType,
                    "externalPatientId", externalPatientId,
                    "count", resources.size(),
                    "resources", resources));
        } catch (HttpStatusCodeException e) {
            log.warn("[ehr-debug] athenahealth returned {} for {} {}: {}",
                    e.getStatusCode(), resourceType, externalPatientId, e.getResponseBodyAsString());
            return ResponseEntity.status(e.getStatusCode()).body(Map.of(
                    "error", "athenahealth returned an error response",
                    "status", e.getStatusCode().value(),
                    "body", e.getResponseBodyAsString()));
        } catch (ResourceAccessException e) {
            log.warn("[ehr-debug] could not reach athenahealth for {} {}: {}",
                    resourceType, externalPatientId, e.getMessage());
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(Map.of(
                    "error", "could not reach athenahealth",
                    "message", String.valueOf(e.getMessage())));
        } catch (IllegalStateException e) {
            log.warn("[ehr-debug] athenahealth token acquisition failed: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(Map.of(
                    "error", "athenahealth token acquisition failed",
                    "message", String.valueOf(e.getMessage())));
        }
    }
}
