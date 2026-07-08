package com.careconnect.controller;

import com.careconnect.dto.EmailConnectionStatus;
import com.careconnect.dto.GmailConnectUrlResponse;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.EmailCredentialService;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

@RestController
@RequestMapping("/v1/api/email-credentials")
@RequiredArgsConstructor
public class EmailCredentialController {

    private final EmailCredentialService emailCredentialService;

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/status")
    public ResponseEntity<EmailConnectionStatus> getConnectionStatus(
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false) String userId) throws UnauthorizedException {
        // Accept patientEmail (preferred) or legacy userId; null falls through to current user in service.
        String identifier = firstNonBlank(patientEmail, userId);
        return ResponseEntity.ok(emailCredentialService.getGmailConnectionStatus(identifier));
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @DeleteMapping("/gmail")
    public ResponseEntity<Void> disconnectGmail(
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false) String userId) throws UnauthorizedException {
        String identifier = firstNonBlank(patientEmail, userId);
        emailCredentialService.disconnectGmail(identifier);
        return ResponseEntity.noContent().build();
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/gmail/connect-url")
    public ResponseEntity<GmailConnectUrlResponse> getGmailConnectUrl(
            HttpServletRequest request,
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false) String userId,
            @RequestParam(required = false) String returnUrl) throws UnauthorizedException {
        String identifier = firstNonBlank(patientEmail, userId);
        String startToken = emailCredentialService.createGmailOAuthStartToken(identifier, returnUrl);
        String url = ServletUriComponentsBuilder.fromContextPath(request)
                .path("/oauth/google/start")
                .queryParam("startToken", startToken)
                .build()
                .toUriString();
        return ResponseEntity.ok(new GmailConnectUrlResponse(url));
    }

    /**
     * Shared param resolution for dual-named query params ({@code patientEmail} preferred,
     * {@code userId} legacy). Intentionally local to this controller — same pattern as USPS controllers.
     */
    private static String firstNonBlank(String first, String second) {
        if (first != null && !first.isBlank()) return first.trim();
        if (second != null && !second.isBlank()) return second.trim();
        return null;
    }
}
