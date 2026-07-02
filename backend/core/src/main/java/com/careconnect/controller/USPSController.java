package com.careconnect.controller;

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

import java.time.LocalDate;

@RestController
@RequestMapping("/v1/api/usps")
public class USPSController {

    private final USPSDigestService service;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    public USPSController(SecurityUtil securityUtil, AuthorizationService authorizationService, USPSDigestService uspsDigestService) {
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
        this.service = uspsDigestService;
    }

    @GetMapping("/mail")
    public ResponseEntity<USPSDigest> getDigest(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) throws UnauthorizedException {
        if (jwt == null) {
            throw new UnauthorizedException("Missing or invalid authentication token");
        }
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        var userId = jwt.getSubject();
        var digestOpt = date != null
                ? service.digestForDate(userId, date)
                : service.latestForUser(userId);
        var digest = digestOpt.orElseGet(() -> new USPSDigest(null, java.util.List.of(), java.util.List.of()));
        return ResponseEntity.ok(digest);
    }
}
