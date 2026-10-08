package com.careconnect.integration.cerner;

import com.careconnect.integration.cerner.CernerAllergyService.CernerSourceException;
import com.careconnect.integration.cerner.CernerAllergyService.UnknownPatientException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.security.Principal;
import java.util.List;
import java.util.Map;

/** Provisional endpoint; path and envelope are subject to OpenAPI 1.0 approval. */
@RestController
@RequestMapping("/v1/api/cerner/patients/{patientId}/allergies")
public class CernerAllergyController {

    private final CernerAllergyService service;
    private final CernerAccessPolicy policy;

    public CernerAllergyController(CernerAllergyService service, CernerAccessPolicy policy) {
        this.service = service;
        this.policy = policy;
    }

    @GetMapping
    public ResponseEntity<?> list(@PathVariable String patientId, Principal principal) {
        if (principal == null) {
            return error(HttpStatus.UNAUTHORIZED, "UNAUTHENTICATED", "Login required", "CARECONNECT", false);
        }
        final long id;
        try {
            id = Long.parseLong(patientId);
        } catch (NumberFormatException e) {
            return error(HttpStatus.BAD_REQUEST, "INVALID_PATIENT_ID", "Invalid patient id", "CARECONNECT", false);
        }
        if (!policy.canView(principal.getName(), id)) {
            return error(HttpStatus.FORBIDDEN, "ACCESS_DENIED", "Access denied", "CARECONNECT", false);
        }
        final List<CernerAllergyMapper.Allergy> records = service.getAllergies(id);
        return ResponseEntity.ok(Map.of("source", CernerAllergyMapper.SOURCE, "allergies", records));
    }

    @ExceptionHandler(UnknownPatientException.class)
    ResponseEntity<?> notFound() {
        return error(HttpStatus.NOT_FOUND, "PATIENT_NOT_FOUND", "Patient not found", "CARECONNECT", false);
    }

    @ExceptionHandler(CernerSourceException.class)
    ResponseEntity<?> source(CernerSourceException e) {
        final HttpStatus status = "CERNER_AUTH_EXPIRED".equals(e.code())
                ? HttpStatus.CONFLICT : HttpStatus.BAD_GATEWAY;
        return error(status, e.code(), "Cerner source error", "CERNER", e.retryable());
    }

    private static ResponseEntity<Map<String, Object>> error(HttpStatus status, String code, String message,
                                                             String source, boolean retryable) {
        return ResponseEntity.status(status).body(
                Map.of("code", code, "message", message, "source", source, "retryable", retryable));
    }
}
