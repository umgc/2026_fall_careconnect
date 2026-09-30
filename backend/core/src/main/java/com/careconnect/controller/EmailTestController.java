package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.service.EmailTestService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Collections;
import java.util.Map;

@RestController
@RequestMapping("/v1/api/email-test")
public class EmailTestController {

    @Autowired
    private EmailTestService emailTestService;

    /**
     * Test email configuration and send a test email
     * POST /v1/api/email-test/send
     * Body: {"email": "test@example.com"}
     */
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/send")
    public ResponseEntity<Map<String, Object>> sendTestEmail(@RequestBody Map<String, String> request) {
        String testEmail = request.get("email");
        if (testEmail == null || testEmail.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Collections.singletonMap("error", "Email address is required")
            );
        }

        Map<String, Object> result = emailTestService.testEmailConfiguration(testEmail);
        return ResponseEntity.ok(result);
    }

    /**
     * Get email configuration details
     * GET /v1/api/email-test/config
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/config")
    public ResponseEntity<Map<String, Object>> getEmailConfig() {
        Map<String, Object> config = emailTestService.getEmailConfiguration();
        return ResponseEntity.ok(config);
    }

    /**
     * Validate email configuration without sending
     * GET /v1/api/email-test/validate
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/validate")
    public ResponseEntity<Map<String, Object>> validateEmailConfiguration() {
        Map<String, Object> validation = emailTestService.validateEmailConfiguration();
        return ResponseEntity.ok(validation);
    }

    /**
     * Test all email types (verification, password reset, password setup)
     * POST /v1/api/email-test/all
     * Body: {"email": "test@example.com"}
     */
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/all")
    public ResponseEntity<Map<String, Object>> testAllEmailTypes(@RequestBody Map<String, String> request) {
        String testEmail = request.get("email");
        if (testEmail == null || testEmail.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(
                    Collections.singletonMap("error", "Email address is required")
            );
        }

        Map<String, Object> results = emailTestService.testAllEmailTypes(testEmail);
        return ResponseEntity.ok(results);
    }

    /**
     * Quick health check for email service
     * GET /v1/api/email-test/health
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> healthCheck() {
        Map<String, Object> config = emailTestService.getEmailConfiguration();
        boolean healthy = (boolean) config.get("configurationValid");

        Map<String, Object> health = Map.of(
                "healthy", healthy,
                "provider", config.get("provider"),
                "mailSenderAvailable", config.get("mailSenderAvailable"),
                "status", healthy ? "UP" : "DOWN"
        );

        return ResponseEntity.ok(health);
    }

    /**
     * Test simple email sending
     * GET /v1/api/email-test/test-simple?email=test@example.com
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/test-simple")
    public ResponseEntity<Map<String, Object>> testSimpleEmail(@RequestParam String email) {
        Map<String, Object> response = emailTestService.testSimpleEmail(email);
        return ResponseEntity.ok(response);
    }
}
