package com.careconnect.controller.emergency;

import com.careconnect.dto.emergency.PassportDtos.NewTokenResponse;
import com.careconnect.dto.emergency.PassportDtos.PassportView;
import com.careconnect.dto.emergency.PassportDtos.ProfileRequest;
import com.careconnect.dto.emergency.PassportDtos.PublicPassport;
import com.careconnect.dto.emergency.PassportDtos.VisibilityRequest;
import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.model.emergency.PassportField;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.emergency.EmergencyPassportService;
import com.careconnect.service.emergency.PassportScanRateLimiter;
import com.fasterxml.jackson.databind.exc.InvalidFormatException;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Arrays;
import java.util.Locale;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Emergency Care Passport endpoints (CC-12, Increment 2).
 * <p>
 * Everything except {@code GET /scan/{token}} is the signed-in patient managing their own passport;
 * nobody manages one for them. The scan is public ({@code SecurityConfig}) because whoever scans
 * the QR at a scene has no account. It is rate limited per client, never cached, and answers an
 * unknown, malformed or revoked code with the same 404 so a caller cannot tell them apart.
 */
@RestController
@RequestMapping("/v1/api/passport")
public class EmergencyPassportController {

    private static final Map<String, String> NOT_ACTIVE = Map.of("status", "NOT_ACTIVE");
    private static final Map<String, String> RATE_LIMITED = Map.of("status", "RATE_LIMITED");

    private final EmergencyPassportService passports;
    private final PassportScanRateLimiter rateLimiter;
    private final UserRepository users;
    private final PatientRepository patients;

    public EmergencyPassportController(
            final EmergencyPassportService passports,
            final PassportScanRateLimiter rateLimiter,
            final UserRepository users,
            final PatientRepository patients) {
        this.passports = passports;
        this.rateLimiter = rateLimiter;
        this.users = users;
        this.patients = patients;
    }

    @GetMapping
    public ResponseEntity<PassportView> get(final Authentication authentication) {
        return ResponseEntity.ok(passports.getPassport(currentPatientId(authentication)));
    }

    @PutMapping("/profile")
    public ResponseEntity<PassportView> updateProfile(
            @RequestBody final ProfileRequest request, final Authentication authentication) {
        return ResponseEntity.ok(passports.updateProfile(currentPatientId(authentication), request));
    }

    @PutMapping("/visibility/{field}")
    public ResponseEntity<PassportView> setVisibility(
            @PathVariable final String field,
            @RequestBody final VisibilityRequest request,
            final Authentication authentication) {
        final Long patientId = currentPatientId(authentication);
        if (request == null || request.isPublic() == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "isPublic is required");
        }
        return ResponseEntity.ok(passports.setVisibility(patientId, parseField(field), request.isPublic()));
    }

    /** Makes a new code and revokes the old one. The response is the only time the token is shown. */
    @PostMapping("/token")
    public ResponseEntity<NewTokenResponse> regenerateToken(final Authentication authentication) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .cacheControl(CacheControl.noStore())
                .body(passports.regenerateToken(currentPatientId(authentication)));
    }

    @DeleteMapping("/token")
    public ResponseEntity<Void> revokeToken(final Authentication authentication) {
        passports.revokeToken(currentPatientId(authentication));
        return ResponseEntity.noContent().build();
    }

    /**
     * Public. What a phone camera's scan of the QR shows (design screens 3 and 4). {@code /scan/} with no code is
     * mapped too: {@code SecurityConfig}'s {@code /scan/*} lets it through, and without a handler it became the
     * global handler's 500 (DEF-EMG-06). It gets the same 404 as any other code that is not active.
     */
    @GetMapping({"/scan/{token}", "/scan/"})
    public ResponseEntity<?> scan(
            @PathVariable(required = false) final String token, final HttpServletRequest request) {
        if (!rateLimiter.tryAcquire(clientKey(request))) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                    .cacheControl(CacheControl.noStore())
                    .body(RATE_LIMITED);
        }
        return passports.scan(token)
                .<ResponseEntity<?>>map(p -> ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(p))
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .cacheControl(CacheControl.noStore())
                        .body(NOT_ACTIVE));
    }

    /**
     * A body that cannot be read, such as a {@code bloodType} that is not one of the eight, is the
     * caller's mistake: 400 in this API's {@code {"error": ...}} shape. The global handler would make
     * it a 500. An unknown enum value names the field and the values it accepts.
     */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<Map<String, String>> unreadableBody(final HttpMessageNotReadableException e) {
        if (e.getCause() instanceof InvalidFormatException invalid
                && invalid.getTargetType() != null && invalid.getTargetType().isEnum()
                && !invalid.getPath().isEmpty()) {
            final String field = invalid.getPath().get(invalid.getPath().size() - 1).getFieldName();
            final String allowed = Arrays.stream(invalid.getTargetType().getEnumConstants())
                    .map(Object::toString)
                    .collect(Collectors.joining(", "));
            return ResponseEntity.badRequest().body(Map.of("error", field + " must be one of: " + allowed));
        }
        return ResponseEntity.badRequest().body(Map.of("error", "Request body is malformed"));
    }

    /**
     * Two saves for the same patient at the same moment, such as a double tap on "make a new code", can both pass
     * the service's checks and then collide on a unique index (one ACTIVE code, one profile, one row per field).
     * The database keeps exactly one; the loser is told to retry with 409 instead of the global handler's 500
     * (DEF-EMG-05).
     */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<Map<String, String>> concurrentSave(final DataIntegrityViolationException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(Map.of("error", "Another change to this passport was saved at the same moment; try again"));
    }

    private Long currentPatientId(final Authentication authentication) {
        if (authentication == null) {
            throw new AppException(HttpStatus.UNAUTHORIZED, "Sign in to manage your passport");
        }
        return users.findByEmail(authentication.getName())
                .flatMap(user -> patients.findByUserId(user.getId()))
                .map(Patient::getId)
                .orElseThrow(() -> new AppException(HttpStatus.FORBIDDEN,
                        "Only a patient can manage their own emergency passport"));
    }

    private static PassportField parseField(final String field) {
        try {
            return PassportField.valueOf(field.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw new AppException(HttpStatus.NOT_FOUND, "Unknown passport field");
        }
    }

    /**
     * The client as the load balancer saw it. The ALB appends the connecting address to
     * {@code X-Forwarded-For}, so the LAST entry is the one a client cannot forge; the first entry
     * is whatever the client sent, and keying on it would let one client rotate past the limit.
     */
    static String clientKey(final HttpServletRequest request) {
        final String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            final String[] hops = forwarded.split(",");
            final String last = hops[hops.length - 1].trim();
            if (!last.isEmpty()) {
                return last;
            }
        }
        return request.getRemoteAddr();
    }
}
