package com.careconnect.exception;

import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.retrieval.ScopeDenialReason;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("GlobalExceptionHandler")
class GlobalExceptionHandlerTest {

    private GlobalExceptionHandler handler;

    @BeforeEach
    void setUp() throws Exception {
        handler = new GlobalExceptionHandler();
    }

    // ── handleForbiddenScopeException ────────────────────────────────────────

    @Test
    @DisplayName("handleForbiddenScopeException returns 403 FORBIDDEN_SCOPE with WITHHELD delivery")
    void handleForbiddenScopeException_returns403WithContractBody() throws Exception {
        UUID auditId = UUID.fromString("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
        String detail = "Patient 42 is out of scope for user 'user@test.com'";
        final ForbiddenScopeException ex = ForbiddenScopeException.of(
                ScopeDenialReason.PATIENT_OUT_OF_SCOPE,
                42L,
                10L,
                detail,
                auditId);

        final ResponseEntity<?> response = handler.handleForbiddenScopeException(ex);

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertNotNull(body);
        assertEquals(false, body.get("success"));
        assertEquals("WITHHELD", body.get("deliveryStatus"));
        assertEquals(auditId.toString(), body.get("auditId"));

        @SuppressWarnings("unchecked")
        final Map<String, Object> error = (Map<String, Object>) body.get("error");
        assertNotNull(error);
        assertEquals("FORBIDDEN_SCOPE", error.get("code"));
        assertEquals(ex.getMessage(), error.get("message"));
        assertEquals("PATIENT_OUT_OF_SCOPE", error.get("denialReason"));
        assertEquals(List.of(), error.get("details"));
    }

    // ── handleRegistrationException ────────────────────────────────────────────

    @Test
    @DisplayName("handleRegistrationException returns 400 with error message")
    void handleRegistrationException_returns400WithMessage() throws Exception {
        final RegistrationException ex = new RegistrationException("email taken");

        final ResponseEntity<?> response = handler.handleRegistrationException(ex);

        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        @SuppressWarnings("unchecked")
        final Map<String, String> body = (Map<String, String>) response.getBody();
        assertNotNull(body);
        assertEquals("email taken", body.get("error"));
    }

    // ── handleAppException ─────────────────────────────────────────────────────

    @Test
    @DisplayName("handleAppException returns status from exception with error message")
    void handleAppException_returnsExceptionStatus() throws Exception {
        final AppException ex = new AppException(HttpStatus.FORBIDDEN, "access denied");

        final ResponseEntity<?> response = handler.handleAppException(ex);

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        @SuppressWarnings("unchecked")
        final Map<String, String> body = (Map<String, String>) response.getBody();
        assertNotNull(body);
        assertEquals("access denied", body.get("error"));
    }

    // ── handleOtherExceptions ──────────────────────────────────────────────────

    @Test
    @DisplayName("handleOtherExceptions returns 500 with generic message")
    void handleOtherExceptions_returns500WithGenericMessage() throws Exception {
        final Exception ex = new Exception("something broke");

        final ResponseEntity<?> response = handler.handleOtherExceptions(ex);

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());
        @SuppressWarnings("unchecked")
        final Map<String, String> body = (Map<String, String>) response.getBody();
        assertNotNull(body);
        assertEquals("An unexpected error occurred", body.get("error"));
    }

// ── handleUnauthorizedException ────────────────────────────────────────────

    @Test
    @DisplayName("handleUnauthorizedException returns 403 with error message (note: not 401 despite name)")
    void handleUnauthorizedException_returns403WithMessage() throws Exception {
        final UnauthorizedException ex = new UnauthorizedException("token expired");

        final ResponseEntity<?> response = handler.handleUnauthorizedException(ex);

        // The handler name is a legacy quirk — the semantics is "user is
        // authenticated but not authorized," so the wire response is 403,
        // not 401. Locking this in a test to prevent future well-meaning
        // "fix" that would break every UnauthorizedException call site.
        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        @SuppressWarnings("unchecked")
        final Map<String, String> body = (Map<String, String>) response.getBody();
        assertNotNull(body);
        assertEquals("token expired", body.get("error"));
    }

    // ── handleValidationException ──────────────────────────────────────────────

    @Test
    @DisplayName("handleValidationException returns 400 with fields list of 'name: message' entries")
    void handleValidationException_returns400WithFieldErrors() throws Exception {
        // Build a stubbed BindingResult with two field errors so the handler
        // exercises the stream + mapping logic.
        final org.springframework.validation.BindingResult bindingResult =
                new org.springframework.validation.BeanPropertyBindingResult(new Object(), "target");
        bindingResult.addError(new org.springframework.validation.FieldError(
                "target", "email", "must not be blank"));
        bindingResult.addError(new org.springframework.validation.FieldError(
                "target", "age", "must be >= 0"));

        final org.springframework.web.bind.MethodArgumentNotValidException ex =
                new org.springframework.web.bind.MethodArgumentNotValidException(
                        null, bindingResult);

        final ResponseEntity<?> response = handler.handleValidationException(ex);

        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertNotNull(body);
        assertEquals("Validation failed", body.get("error"));
        @SuppressWarnings("unchecked")
        final List<String> fields = (List<String>) body.get("fields");
        assertNotNull(fields);
        assertEquals(2, fields.size());
        assertTrue(fields.contains("email: must not be blank"));
        assertTrue(fields.contains("age: must be >= 0"));
    }

    // ── handleForbiddenScopeException (null audit / denial branches) ──────────

    @Test
    @DisplayName("handleForbiddenScopeException omits auditId and denialReason when both are null")
    void handleForbiddenScopeException_nullAuditAndDenial_omitsFields() throws Exception {
        // The primary handleForbiddenScopeException test above exercises the
        // audit-present + denial-present path. The handler's two `if != null`
        // branches for auditId and denialReason are otherwise uncovered.
        // Build an exception with both nulled out by passing null explicitly.
        final ForbiddenScopeException ex = ForbiddenScopeException.of(
                null,
                null,
                null,
                "scope denied without audit trail",
                null);

        final ResponseEntity<?> response = handler.handleForbiddenScopeException(ex);

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
        @SuppressWarnings("unchecked")
        final Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertNotNull(body);
        assertEquals(false, body.get("success"));
        assertEquals("WITHHELD", body.get("deliveryStatus"));
        assertFalse(body.containsKey("auditId"),
                "auditId key should be omitted when null, not present with null value");

        @SuppressWarnings("unchecked")
        final Map<String, Object> error = (Map<String, Object>) body.get("error");
        assertNotNull(error);
        assertFalse(error.containsKey("denialReason"),
                "denialReason key should be omitted when null, not present with null value");
        // FORBIDDEN_SCOPE error code is still populated (comes from exception).
        assertEquals("FORBIDDEN_SCOPE", error.get("code"));
    }
}
