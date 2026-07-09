package com.careconnect.controller;

import com.careconnect.dto.EmailConnectionStatus;
import com.careconnect.dto.GmailConnectUrlResponse;
import com.careconnect.security.AuthRequestSupport;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.EmailCredentialService;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

@RestController
@RequestMapping("/v1/api/email-credentials")
@RequiredArgsConstructor
public class EmailCredentialController {

    private final EmailCredentialService emailCredentialService;

    @GetMapping("/status")
    public ResponseEntity<EmailConnectionStatus> getConnectionStatus(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false) String userId) throws UnauthorizedException {
        AuthRequestSupport.requireAuthenticated(jwt);
        String identifier = firstNonBlank(patientEmail, userId);
        return ResponseEntity.ok(emailCredentialService.getGmailConnectionStatus(identifier));
    }

    @DeleteMapping("/gmail")
    public ResponseEntity<Void> disconnectGmail(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false) String userId) throws UnauthorizedException {
        AuthRequestSupport.requireAuthenticated(jwt);
        String identifier = firstNonBlank(patientEmail, userId);
        emailCredentialService.disconnectGmail(identifier);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/gmail/connect-url")
    public ResponseEntity<GmailConnectUrlResponse> getGmailConnectUrl(
            @AuthenticationPrincipal Jwt jwt,
            HttpServletRequest request,
            @RequestParam(required = false) String patientEmail,
            @RequestParam(required = false) String userId,
            @RequestParam(required = false) String returnUrl) throws UnauthorizedException {
        AuthRequestSupport.requireAuthenticated(jwt);
        String identifier = firstNonBlank(patientEmail, userId);
        String startToken = emailCredentialService.createGmailOAuthStartToken(identifier, returnUrl);
        String url = ServletUriComponentsBuilder.fromContextPath(request)
                .path("/oauth/google/start")
                .queryParam("startToken", startToken)
                .build()
                .toUriString();
        return ResponseEntity.ok(new GmailConnectUrlResponse(url));
    }

    private static String firstNonBlank(String first, String second) {
        if (first != null && !first.isBlank()) return first.trim();
        if (second != null && !second.isBlank()) return second.trim();
        return null;
    }
}
