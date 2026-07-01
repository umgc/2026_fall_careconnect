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

@RestController
@RequestMapping("/v1/api/usps")
public class USPSController {

    private final USPSDigestService service;
    private final UserRepository userRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    public USPSController(USPSDigestService service, UserRepository userRepository, SecurityUtil securityUtil, AuthorizationService authorizationService) {
        this.service = service;
        this.userRepository = userRepository;
        this.securityUtil = securityUtil;
        this.authorizationService = authorizationService;
    }

    @GetMapping("/mail")
    public ResponseEntity<USPSDigest> getDigest(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) throws UnauthorizedException {
        // RBAC: Only admins and caregivers can access USPS mail data
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        if (jwt == null) {
            throw new UnauthorizedException("Missing or invalid authentication token");
        }
        var userId = jwt.getSubject();
        var digestOpt = date != null
                ? service.digestForDate(userId, date)
                : service.latestForUser(userId);
        var digest = digestOpt.orElseGet(() -> new USPSDigest(null, java.util.List.of(), java.util.List.of()));
        return ResponseEntity.ok(digest);
    }
}
