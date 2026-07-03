package com.careconnect.controller;

import com.careconnect.model.USPSDigest;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.USPSDigestService;
import com.careconnect.util.SecurityUtil;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.Optional;

/**
 * Primary USPS mail digest endpoint for authenticated clients (e.g. informed delivery screen).
 * <p>Requires a valid JWT — the previous {@code demo-user} unauthenticated fallback was removed
 * intentionally. {@link UserRepository} is injected via constructor (standard Spring bean wiring).
 */
@RestController
@RequestMapping("/v1/api/usps")
public class USPSController {

    private final USPSDigestService service;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final UserRepository userRepository;

    public USPSController(SecurityUtil securityUtil, AuthorizationService authorizationService,
                          USPSDigestService uspsDigestService, UserRepository userRepository) {
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
        this.service = uspsDigestService;
        this.userRepository = userRepository;
    }

    @GetMapping("/mail")
    public ResponseEntity<USPSDigest> getDigest(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) throws UnauthorizedException {
        if (jwt == null) {
            throw new UnauthorizedException("Missing or invalid authentication token");
        }
        User currentUser = securityUtil.resolveCurrentUser();
        User patientUser = resolvePatientUser(patientEmail, currentUser);
        authorizationService.requirePatientAccess(currentUser, patientUser.getId());

        // USPSDigestService keys cache/credentials by the patient's database user id (string).
        String serviceUserId = String.valueOf(patientUser.getId());
        var digestOpt = date != null
                ? service.digestForDate(serviceUserId, date)
                : service.latestForUser(serviceUserId);
        var digest = digestOpt.orElseGet(() -> new USPSDigest(null, java.util.List.of(), java.util.List.of()));
        return ResponseEntity.ok(digest);
    }

    /**
     * Resolve the patient whose USPS data is being requested.
     * Accepts email or numeric database id (frontend legacy {@code userId} param).
     */
    private User resolvePatientUser(String patientIdentifier, User currentUser) throws UnauthorizedException {
        if (patientIdentifier == null || patientIdentifier.isBlank()) {
            return currentUser;
        }
        return userRepository.findByEmail(patientIdentifier)
                .or(() -> parseNumericUserId(patientIdentifier).flatMap(userRepository::findById))
                .orElseThrow(() -> new UnauthorizedException(
                        "No patient found for identifier: " + patientIdentifier));
    }

    private static Optional<Long> parseNumericUserId(String value) {
        try {
            return Optional.of(Long.parseLong(value));
        } catch (NumberFormatException e) {
            return Optional.empty();
        }
    }
}
