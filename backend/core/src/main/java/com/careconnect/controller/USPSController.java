package com.careconnect.controller;

import com.careconnect.model.USPSDigest;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.USPSDigestService;
import com.careconnect.util.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;

@RestController
@RequestMapping("/v1/api/usps")
@RequiredArgsConstructor
public class USPSController {

    private final USPSDigestService service;
    private final UserRepository userRepository; // Inject the UserRepository to fetch user details based on userId

    @Autowired
    private SecurityUtil securityUtil;

    @Autowired
    private AuthorizationService authorizationService;

    @GetMapping("/mail")
    public ResponseEntity<USPSDigest> getDigest(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) throws UnauthorizedException {
        // RBAC: Only admins and caregivers can access USPS mail data
        //replaced with previous logic to fetch the userId from the JWT token or fallback to a default value for testing
                  var userId = jwt != null ? jwt.getSubject() : "demo-user"; // fallback for early testing
        if (securityUtil != null && authorizationService != null) {
            User currentUser = securityUtil.resolveCurrentUser();
            User patientUser = userRepository.findByEmail(userId)
                    .orElseThrow(() -> new UnauthorizedException("No patient found for userId: " + userId));
            authorizationService.requirePatientAccess(currentUser, patientUser.getId());
        }
        var digestOpt = date != null
                ? service.digestForDate(userId, date)
                : service.latestForUser(userId);
        var digest = digestOpt.orElseGet(() -> new USPSDigest(null, java.util.List.of(), java.util.List.of()));
        return ResponseEntity.ok(digest);
    }
}
