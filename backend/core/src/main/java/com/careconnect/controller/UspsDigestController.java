package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.model.USPSDigest;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.USPSDigestService;
import com.careconnect.util.SecurityUtil;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import com.careconnect.repository.UserRepository;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/v1/api/usps")
public class UspsDigestController {

    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final USPSDigestService uspsDigestService;
    private final UserRepository userRepository;

    public UspsDigestController(SecurityUtil securityUtil, AuthorizationService authorizationService,
                                USPSDigestService uspsDigestService, UserRepository userRepository) {
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
        this.uspsDigestService = uspsDigestService;
        this.userRepository = userRepository;
    }

    // @RequirePermission gates role-level access; requirePatientAccess enforces link/expiry checks.
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/latest")
    public ResponseEntity<USPSDigest> getLatestDigest(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam String patientEmail,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) throws UnauthorizedException {

        if (jwt == null) throw new UnauthorizedException("Missing or invalid authentication token");
        User currentUser = securityUtil.resolveCurrentUser();
        User patientUser = resolvePatientUser(patientEmail);
        authorizationService.requirePatientAccess(currentUser, patientUser.getId());

        String serviceUserId = String.valueOf(patientUser.getId());
        var digest = date != null
                ? uspsDigestService.digestForDate(serviceUserId, date)
                : uspsDigestService.latestForUser(serviceUserId);

        return digest
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.noContent().build());
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/search")
    public ResponseEntity<List<Map<String, Object>>> search(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam String patientEmail,
            @RequestParam String keyword) throws UnauthorizedException {

        if (jwt == null) throw new UnauthorizedException("Missing or invalid authentication token");
        User currentUser = securityUtil.resolveCurrentUser();
        User patientUser = resolvePatientUser(patientEmail);
        authorizationService.requirePatientAccess(currentUser, patientUser.getId());

        String serviceUserId = String.valueOf(patientUser.getId());
        var results = uspsDigestService.search(serviceUserId, keyword);
        return ResponseEntity.ok(results);
    }

    @RequirePermission(Permission.CREATE_TASKS)
    @PostMapping("/clear-cache")
    public ResponseEntity<String> clearCache(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam String patientEmail) throws UnauthorizedException {

        if (jwt == null) throw new UnauthorizedException("Missing or invalid authentication token");
        User currentUser = securityUtil.resolveCurrentUser();
        User patientUser = resolvePatientUser(patientEmail);
        authorizationService.requirePatientAccess(currentUser, patientUser.getId());

        String serviceUserId = String.valueOf(patientUser.getId());
        uspsDigestService.clearCacheForUser(serviceUserId);
        return ResponseEntity.ok("Cache cleared successfully for user: " + patientEmail);
    }

    /**
     * Resolve patient by email or numeric database id (legacy {@code userId} query param).
     */
    private User resolvePatientUser(String patientIdentifier) throws UnauthorizedException {
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
