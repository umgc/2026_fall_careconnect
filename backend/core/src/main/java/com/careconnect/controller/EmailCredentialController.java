package com.careconnect.controller;

import com.careconnect.dto.EmailConnectionStatus;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.EmailCredentialService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

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

    private static String firstNonBlank(String first, String second) {
        if (first != null && !first.isBlank()) return first.trim();
        if (second != null && !second.isBlank()) return second.trim();
        return null;
    }
}
