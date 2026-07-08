package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.model.USPSDigest;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.USPSDigestService;
import com.careconnect.service.UspsPatientResolver;
import com.careconnect.util.SecurityUtil;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * USPS digest endpoints scoped to a specific patient.
 * <p>All endpoints require a valid JWT ({@code SecurityConfig} enforces authentication).
 * Pass {@code patientEmail} (preferred) or legacy {@code userId} (email or numeric database id).
 * When neither is supplied, the authenticated user's own record is used.
 */
@RestController
@RequestMapping("/v1/api/usps")
public class UspsDigestController {

    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final USPSDigestService uspsDigestService;
    private final UspsPatientResolver patientResolver;

    public UspsDigestController(SecurityUtil securityUtil, AuthorizationService authorizationService,
                                USPSDigestService uspsDigestService, UspsPatientResolver patientResolver) {
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
        this.uspsDigestService = uspsDigestService;
        this.patientResolver = patientResolver;
    }

    // @RequirePermission gates role-level access; requirePatientAccess enforces link/expiry checks.
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/latest")
    public ResponseEntity<USPSDigest> getLatestDigest(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false) String userId,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) throws UnauthorizedException {

        if (jwt == null) throw new UnauthorizedException("Missing or invalid authentication token");
        User currentUser = securityUtil.resolveCurrentUser();
        User patientUser = patientResolver.resolvePatient(patientEmail, userId, currentUser);
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
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false) String userId,
            @RequestParam String keyword) throws UnauthorizedException {

        if (jwt == null) throw new UnauthorizedException("Missing or invalid authentication token");
        User currentUser = securityUtil.resolveCurrentUser();
        User patientUser = patientResolver.resolvePatient(patientEmail, userId, currentUser);
        authorizationService.requirePatientAccess(currentUser, patientUser.getId());

        String serviceUserId = String.valueOf(patientUser.getId());
        var results = uspsDigestService.search(serviceUserId, keyword);
        return ResponseEntity.ok(results);
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @PostMapping("/clear-cache")
    public ResponseEntity<String> clearCache(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false) String userId) throws UnauthorizedException {

        if (jwt == null) throw new UnauthorizedException("Missing or invalid authentication token");
        User currentUser = securityUtil.resolveCurrentUser();
        User patientUser = patientResolver.resolvePatient(patientEmail, userId, currentUser);
        authorizationService.requirePatientAccess(currentUser, patientUser.getId());

        String serviceUserId = String.valueOf(patientUser.getId());
        uspsDigestService.clearCacheForUser(serviceUserId);
        String identifier = patientEmail != null && !patientEmail.isBlank()
                ? patientEmail
                : (userId != null && !userId.isBlank() ? userId : String.valueOf(patientUser.getId()));
        return ResponseEntity.ok("Cache cleared successfully for user: " + identifier);
    }
}
