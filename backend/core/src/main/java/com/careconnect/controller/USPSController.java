package com.careconnect.controller;

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

/**
 * Primary USPS mail digest endpoint for authenticated clients (e.g. informed delivery screen).
 * <p>Requires a valid JWT — the previous {@code demo-user} unauthenticated fallback was removed
 * intentionally. Patient resolution is delegated to {@link UspsPatientResolver}.
 */
@RestController
@RequestMapping("/v1/api/usps")
public class USPSController {

    private final USPSDigestService service;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final UspsPatientResolver patientResolver;

    public USPSController(SecurityUtil securityUtil, AuthorizationService authorizationService,
                          USPSDigestService uspsDigestService, UspsPatientResolver patientResolver) {
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
        this.service = uspsDigestService;
        this.patientResolver = patientResolver;
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
        User patientUser = patientResolver.resolvePatient(patientEmail, currentUser);
        authorizationService.requirePatientAccess(currentUser, patientUser.getId());

        // USPSDigestService keys cache/credentials by the patient's database user id (string).
        String serviceUserId = String.valueOf(patientUser.getId());
        var digestOpt = date != null
                ? service.digestForDate(serviceUserId, date)
                : service.latestForUser(serviceUserId);
        var digest = digestOpt.orElseGet(() -> new USPSDigest(null, java.util.List.of(), java.util.List.of()));
        return ResponseEntity.ok(digest);
    }
}
