package com.careconnect.exception;

import com.careconnect.exception.EmailCredentialNeedsReauthException;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import org.springframework.http.HttpStatus;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@ControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(EmailCredentialNeedsReauthException.class)
    public ResponseEntity<Map<String, Object>> handleEmailCredentialNeedsReauth(
            final EmailCredentialNeedsReauthException ex) {
        final Map<String, Object> body = new LinkedHashMap<>();
        body.put("code", "NEEDS_REAUTH");
        body.put("message", ex.getMessage());
        body.put("userId", ex.getUserId());
        body.put("needsReconnect", true);
        body.put("reconnectPath", ex.getReconnectPath());
        body.put("syncHalted", true);
        return ResponseEntity.status(HttpStatus.CONFLICT).body(body);
    }

    @ExceptionHandler(UnauthorizedException.class)
    public ResponseEntity<?> handleUnauthorizedException(UnauthorizedException ex) {
        return ResponseEntity
                .status(HttpStatus.FORBIDDEN)
                .body(Map.of("error", ex.getMessage()));
    }

    @ExceptionHandler(ForbiddenScopeException.class)
    public ResponseEntity<?> handleForbiddenScopeException(ForbiddenScopeException ex) {
        Map<String, Object> error = new LinkedHashMap<>();
        error.put("code", ex.getErrorCode());
        error.put("message", ex.getMessage());
        if (ex.getDenialReason() != null) {
            error.put("denialReason", ex.getDenialReason().name());
        }
        error.put("details", List.of());

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("success", false);
        if (ex.getAuditId() != null) {
            body.put("auditId", ex.getAuditId().toString());
        }
        body.put("deliveryStatus", "WITHHELD");
        body.put("error", error);
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(body);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<?> handleValidationException(MethodArgumentNotValidException ex) {
        List<String> fieldErrors = ex.getBindingResult().getFieldErrors().stream()
                .map(fe -> fe.getField() + ": " + fe.getDefaultMessage())
                .toList();
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("error", "Validation failed");
        body.put("fields", fieldErrors);
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(body);
    }

    @ExceptionHandler(RegistrationException.class)
    public ResponseEntity<?> handleRegistrationException(RegistrationException ex) {
        return ResponseEntity
                .status(HttpStatus.BAD_REQUEST)
                .body(Map.of("error", ex.getMessage()));
    }

    @ExceptionHandler(AppException.class)
    public ResponseEntity<?> handleAppException(AppException ex) {
        return ResponseEntity
                .status(ex.getStatus())
                .body(Map.of("error", ex.getMessage()));
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<Map<String, Object>> handleTypeMismatch(
            final MethodArgumentTypeMismatchException ex) {
        final Map<String, Object> body = new LinkedHashMap<>();
        body.put("error", "Invalid parameter type");
        body.put("parameter", ex.getName());
        body.put("message", "Expected type: " + (ex.getRequiredType() == null
                ? "unknown"
                : ex.getRequiredType().getSimpleName()));
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(body);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<?> handleOtherExceptions(Exception ex) {
        org.slf4j.LoggerFactory.getLogger(GlobalExceptionHandler.class)
                .error("Unhandled exception", ex);
        return ResponseEntity
                .status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "An unexpected error occurred"));
    }
}
