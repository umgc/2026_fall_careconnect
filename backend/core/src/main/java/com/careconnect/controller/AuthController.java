package com.careconnect.controller;

import com.careconnect.dto.*;
import com.careconnect.exception.OAuthException;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.service.AuthService;
import com.careconnect.service.AlexaCodeStoreService;
import com.careconnect.service.PasswordResetService;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.TokenHashService;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import com.careconnect.repository.UserRepository;
import com.careconnect.repository.PatientRepository;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;

import java.io.IOException;
import java.net.URLEncoder;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@RestController
@RequestMapping("/v1/api/auth")
@Tag(name = "Authentication", description = "Authentication and authorization endpoints including login, registration, email verification, and OAuth")
public class AuthController {

    @Autowired
    private AuthService authService;

    @Autowired
    private PasswordResetService reset;

    @Autowired
    private JwtTokenProvider jwt;

    @Autowired
    private ObjectMapper objectMapper;

    @Value("${frontend.base-url}")
    private String frontendBaseUrl; // --- Register new user ---
    @Value("${alexa.oauth.client-id}")
    private String alexaClientId;
    @Value("${alexa.oauth.client-secret}")
    private String alexaClientSecret;
    @Autowired
    private UserRepository userRepository; // ✅ inject user repo to find patient by email
    @Autowired
    private PatientRepository patientRepository; // ✅ inject patient repo to find patient by email
    @Autowired
    private TokenHashService tokenHashService;
    @Autowired
    private AlexaCodeStoreService alexaCodeStore;

    @PostMapping("/register")
    @Operation(summary = "Register a new user", description = "Register a new patient or caregiver account.\n\n"
            + "**For Swagger UI Testing:**\n"
            + "1. Use this endpoint to create a test account\n"
            + "2. Check your email for verification (if email is configured)\n"
            + "3. Use the `/login` endpoint to get a JWT token\n"
            + "4. Click \"Authorize\" and enter the token for testing protected endpoints\n\n"
            + "**Registration Flow:**\n"
            + "1. Submit registration with email, password, and role\n"
            + "2. Account is created (may require email verification)\n"
            + "3. Use the email/password to login and get JWT token\n"
            + "4. Use JWT token to access protected endpoints\n\n"
            + "**Test Example:**\n"
            + "```json\n"
            + "{\n"
            + "    \"email\": \"test@example.com\",\n"
            + "    \"password\": \"password123\",\n"
            + "    \"name\": \"Test User\",\n"
            + "    \"role\": \"PATIENT\"\n"
            + "}\n"
            + "```\n", tags = {"Authentication"}, security = {} // No authentication required for registration
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Registration successful, verification email sent", content = @Content(mediaType = "application/json", examples = @ExampleObject(value = "{\n    \"message\": \"Registration successful. Please check your email to verify your account.\",\n    \"userId\": 123\n}"))),
            @ApiResponse(responseCode = "400", description = "Invalid request data", content = @Content(mediaType = "application/json", examples = @ExampleObject(value = "{\n    \"error\": \"Email already exists\"\n}")))
    })
    public ResponseEntity<?> register(
            @Parameter(description = "User registration details", required = true) @RequestBody RegisterRequest request) {
        // Delegate to AuthService for registration & verification logic
        return authService.register(request);
    }

    @PostMapping("/login")
    @Operation(summary = "Login user", description = "Authenticate user with email and password. Returns JWT token for API access.\n\n"
            + "**For Swagger UI Testing:**\n"
            + "1. Use this endpoint to login and get a JWT token\n"
            + "2. Copy the `token` from the response\n"
            + "3. Click the \"Authorize\" button at the top of this page\n"
            + "4. Enter: `Bearer {your-token-here}`\n"
            + "5. Now you can test all protected endpoints!\n\n"
            + "**Response includes:**\n"
            + "- `token`: JWT token for API authentication (valid for 3 hours)\n"
            + "- `user`: User profile information\n"
            + "- `patientId`/`caregiverId`: Role-specific ID (if applicable)\n\n"
            + "**Test Credentials:**\n"
            + "If you need test credentials, use the registration endpoint first.\n", tags = {"Authentication"}, security = {} // No authentication required for login
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Login successful", content = @Content(mediaType = "application/json", schema = @Schema(implementation = LoginResponse.class), examples = @ExampleObject(value = "{\n    \"token\": \"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...\",\n    \"user\": {\n        \"id\": 123,\n        \"name\": \"John Doe\",\n        \"email\": \"john@example.com\",\n        \"role\": \"PATIENT\"\n    },\n    \"patientId\": 456,\n    \"caregiverId\": null\n}"))),
            @ApiResponse(responseCode = "401", description = "Invalid credentials", content = @Content(mediaType = "application/json", examples = @ExampleObject(value = "{\n    \"error\": \"Invalid credentials\"\n}")))
    })
    public ResponseEntity<LoginResponse> loginV2(
            @Parameter(description = "Login credentials", required = true) @RequestBody LoginRequest req,
            HttpServletResponse response) {
        return ResponseEntity.ok(authService.loginV2(req, response));
    }

    @GetMapping("/validate-token")
    @Operation(summary = "Validate JWT token", description = "Check if the current JWT token is valid", tags = {"🔑 Authentication"})
    public ResponseEntity<?> validateToken(@RequestHeader(value = "Authorization", required = false) String authHeader) {

        try {
            if (authHeader == null || !authHeader.startsWith("Bearer ")) {
                return ResponseEntity.status(401).body(Collections.singletonMap("valid", false));
            }
            String token = authHeader.substring(7);
            if (jwt.validateToken(token)) {
                return ResponseEntity.ok(Collections.singletonMap("valid", true));
            }
            return ResponseEntity.status(401).body(Collections.singletonMap("valid", false));
        } catch (Exception e) {
            return ResponseEntity.status(401).body(Collections.singletonMap("valid", false));
        }

    }

    // --- Email verification ---
    @GetMapping("/verify/{token}")
    @Operation(summary = "✉️ Verify email address", description = "Verify user email address using verification token", tags = {
            "🔑 Authentication"}, security = {} // No authentication required for email verification
    )
    public ResponseEntity<?> verify(@PathVariable String token) {
        return authService.verifyToken(token);
    }

    @PostMapping("/resend-verification")
    @Operation(summary = "🔄 Resend verification email", description = "Resend verification email to an unverified user", tags = {
            "🔑 Authentication"}, security = {} // No authentication required for resending verification
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Verification email sent successfully", content = @Content(mediaType = "application/json", examples = @ExampleObject(value = "{\n    \"message\": \"Verification email sent successfully! Please check your inbox.\"\n}"))),
            @ApiResponse(responseCode = "400", description = "Email already verified", content = @Content(mediaType = "application/json", examples = @ExampleObject(value = "{\n    \"error\": \"This email address is already verified.\"\n}")))
    })
    public ResponseEntity<?> resendVerification(@RequestBody Map<String, String> request) {
        String email = request.get("email");
        if (email == null || email.isEmpty()) {
            return ResponseEntity.badRequest()
                    .body(Collections.singletonMap("error", "Email is required"));
        }
        return authService.resendVerificationEmail(email);
    }

    @GetMapping("/check-verification")
    @Operation(summary = "🔍 Check email verification status", description = "Check if an email address is verified without sending any emails", tags = {
            "🔑 Authentication"}, security = {} // No authentication required for checking verification status
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Verification status retrieved", content = @Content(mediaType = "application/json", examples = @ExampleObject(value = "{\n    \"verified\": true\n}")))
    })
    public ResponseEntity<?> checkVerification(@RequestParam String email) {
        if (email == null || email.isEmpty()) {
            return ResponseEntity.badRequest()
                    .body(Collections.singletonMap("error", "Email is required"));
        }
        return authService.checkEmailVerificationStatus(email);
    }

    @PostMapping("/password/forgot")
    @Operation(summary = "🔐 Request password reset", description = "Request a password reset link to be sent via email", tags = {
            "🔑 Authentication"}, security = {} // No authentication required for password reset request
    )
    public ResponseEntity<?> forgotPassword(@RequestBody Map<String, String> request,
                                            HttpServletRequest req) {
        String email = request.get("email");
        if (email == null || email.isEmpty()) {
            return ResponseEntity.badRequest().body(Collections.singletonMap("error", "Email is required"));
        }

        // Log password reset request
        // System.out.println("🔄 Password reset requested for email: " + email);

        // Use frontend URL for password reset link instead of backend URL
        String appUrl = frontendBaseUrl;
        try {
            reset.startReset(email, appUrl);
            // System.out.println("✅ Password reset process initiated for: " + email);
            return ResponseEntity.ok(Collections.singletonMap("message",
                    "If an account with this email exists, you will receive a password reset link."));
        } catch (Exception e) {
            System.err.println("❌ Password reset failed for " + email + ": " + e.getMessage());
            e.printStackTrace();
            // Don't reveal if email exists or not for security
            return ResponseEntity.ok(Collections.singletonMap("message",
                    "If an account with this email exists, you will receive a password reset link."));
        }
    }

    @PostMapping("/password/change")
    public ResponseEntity<?> changePassword(@RequestBody ChangePasswordRequest request,
                                            HttpServletRequest httpRequest) {
        try {
            String token = extractTokenFromRequest(httpRequest);
            if (token == null) {
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .body(Collections.singletonMap("error", "Authentication required"));
            }

            String email = jwt.getEmailFromToken(token);
            return authService.changePassword(email, request.currentPassword(), request.newPassword());

        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Collections.singletonMap("error", e.getMessage()));
        }
    }

    @GetMapping("/password/reset")
    public ResponseEntity<?> validateResetToken(@RequestParam String token) {
        try {
            boolean isValid = reset.isTokenValid(token);
            if (isValid) {
                return ResponseEntity.ok(Collections.singletonMap("message", "Token is valid"));
            } else {
                return ResponseEntity.badRequest().body(Collections.singletonMap("error", "Invalid or expired token"));
            }
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Collections.singletonMap("error", "Invalid or expired token"));
        }
    }

    private String extractTokenFromRequest(HttpServletRequest request) {
        String bearerToken = request.getHeader("Authorization");
        if (bearerToken != null && bearerToken.startsWith("Bearer ")) {
            return bearerToken.substring(7);
        }

        Cookie[] cookies = request.getCookies();
        if (cookies != null) {
            for (Cookie cookie : cookies) {
                if ("AUTH".equals(cookie.getName())) {
                    return cookie.getValue();
                }
            }
        }
        return null;
    }

    /**
     * Determine specific OAuth error type based on exception
     */
    private String determineOAuthErrorType(Exception e) {
        if (e == null || e.getMessage() == null) {
            return "oauth_failed";
        }

        String errorMessage = e.getMessage().toLowerCase();
        String exceptionType = e.getClass().getSimpleName().toLowerCase();

        // Check for specific OAuth error patterns
        if (errorMessage.contains("access_denied") || errorMessage.contains("denied")) {
            return "access_denied";
        }

        if (errorMessage.contains("invalid_grant") || errorMessage.contains("invalid_code")) {
            return "invalid_grant";
        }

        if (errorMessage.contains("invalid_client") || errorMessage.contains("unauthorized")) {
            return "invalid_client";
        }

        if (errorMessage.contains("invalid_request") || errorMessage.contains("bad request")) {
            return "invalid_request";
        }

        if (errorMessage.contains("temporarily_unavailable") || errorMessage.contains("server error") ||
                errorMessage.contains("503") || errorMessage.contains("502") || errorMessage.contains("500")) {
            return "temporarily_unavailable";
        }

        if (errorMessage.contains("invalid_scope") || errorMessage.contains("insufficient_scope") ||
                errorMessage.contains("insufficient permissions")) {
            return "invalid_scope";
        }

        if (errorMessage.contains("token") && (errorMessage.contains("invalid") || errorMessage.contains("expired"))) {
            return "invalid_token";
        }

        if (errorMessage.contains("timeout") || errorMessage.contains("connect") ||
                errorMessage.contains("network") || errorMessage.contains("socket")) {
            return "network_error";
        }

        if (errorMessage.contains("email") && errorMessage.contains("retrieve")) {
            return "invalid_response";
        }

        // Check exception types
        if (exceptionType.contains("httpclient") || exceptionType.contains("restclient")) {
            return "api_error";
        }

        if (exceptionType.contains("timeout") || exceptionType.contains("socket")) {
            return "network_error";
        }

        if (exceptionType.contains("json") || exceptionType.contains("parse")) {
            return "invalid_response";
        }

        if (exceptionType.contains("authentication")) {
            return "authentication_failed";
        }

        if (exceptionType.contains("oauth")) {
            return "oauth_failed";
        }

        // Default fallback
        return "oauth_failed";
    }

    @GetMapping("/sso/google")
    public void googleLogin(HttpServletResponse response) throws IOException {
        String googleAuthUrl = authService.buildGoogleOAuthUrl();
        response.sendRedirect(googleAuthUrl);
    }

    @GetMapping("/sso/google/callback")
    public void googleCallback(
            @RequestParam("code") String code,
            @RequestParam(value = "state", required = false) String state,
            @RequestParam(value = "error", required = false) String error,
            HttpServletResponse response) throws IOException {

        if (error != null) {
            // Handle error - redirect to frontend with error
            response.sendRedirect(frontendBaseUrl + "/oauth/callback?error=" + error);
            return;
        }

        try {
            // Delegate OAuth processing to AuthService
            LoginResponse loginResponse = authService.processGoogleOAuth(code, response);

            String jwt = loginResponse.token();
            String userData = objectMapper.writeValueAsString(loginResponse);

            response.sendRedirect(frontendBaseUrl + "/oauth/callback?token=" + jwt +
                    "&user=" + URLEncoder.encode(userData, "UTF-8"));

        } catch (OAuthException e) {
            // Handle specific OAuth errors
            System.err.println("Google OAuth error: " + e.getMessage());
            e.printStackTrace();

            response.sendRedirect(frontendBaseUrl + "/oauth/callback?error=" + e.getErrorType());
        } catch (Exception e) {
            // Log the error for debugging
            System.err.println("Google OAuth callback error: " + e.getMessage());
            e.printStackTrace();

            // Determine specific error type and redirect with appropriate error
            String errorType = determineOAuthErrorType(e);
            response.sendRedirect(frontendBaseUrl + "/oauth/callback?error=" + errorType);
        }
    }

    @PostMapping("/sso/alexa/code")
    public ResponseEntity<?> generateAlexaCode(HttpServletRequest request) {
        String token = extractTokenFromRequest(request);
        if (token == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "missing_token"));
        }

        // Validate token
        String email = jwt.getEmailFromToken(token);
        if (email == null || !jwt.validateToken(token)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "invalid_token"));
        }

        String code = alexaCodeStore.generateCode(token);
        return ResponseEntity.ok(Map.of("code", code));
    }

    @PostMapping(value = "/sso/alexa/token", consumes = "application/x-www-form-urlencoded")
    public ResponseEntity<?> exchangeAlexaToken(
            @RequestParam Map<String, String> params,
            @RequestHeader(value = "Authorization", required = false) String authHeader) {

        // 1️⃣ Validate Basic Auth (Alexa client credentials)
        if (authHeader == null || !authHeader.startsWith("Basic ")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "missing_authorization"));
        }

        try {
            String base64Credentials = authHeader.substring("Basic ".length());
            String decoded = new String(Base64.getDecoder().decode(base64Credentials));
            String[] parts = decoded.split(":", 2);
            String clientId = parts[0];
            String clientSecret = parts.length > 1 ? parts[1] : "";

            if (!clientId.equals(alexaClientId) || !clientSecret.equals(alexaClientSecret)) {
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .body(Map.of("error", "invalid_client_credentials"));
            }
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("error", "invalid_basic_auth"));
        }

        String grantType = params.get("grant_type");
        String code = params.get("code");
        String refreshToken = params.get("refresh_token");

        // 2️⃣ Handle authorization_code grant (initial linking)
        if ("authorization_code".equalsIgnoreCase(grantType)) {
            if (code == null || code.isBlank()) {
                return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                        .body(Map.of("error", "missing_authorization_code"));
            }

            String jwtToken = alexaCodeStore.consumeCode(code);
            if (jwtToken == null) {
                return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                        .body(Map.of("error", "invalid_code"));
            }

            // 🧠 Validate JWT token before linking
            if (!jwt.validateToken(jwtToken)) {
                System.err.println("🔓 Token expired during OAuth exchange");
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .body(Map.of("error", "expired_token"));
            }

            // ✅ Mark patient as Alexa-linked and SAVE REFRESH TOKEN
            try {
                String email = jwt.getEmailFromToken(jwtToken);
                if (email == null) {
                    System.err.println("⚠️ No email in token during Alexa linking");
                    return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                            .body(Map.of("error", "invalid_token_claims"));
                }

                Optional<User> userOpt = userRepository.findByEmail(email);
                if (userOpt.isEmpty()) {
                    System.err.println("🔓 User not found during Alexa linking: " + email);
                    return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                            .body(Map.of("error", "user_not_found"));
                }

                User user = userOpt.get();
                Optional<Patient> patientOpt = patientRepository.findByUser(user);

                if (patientOpt.isEmpty()) {
                    System.err.println("🔓 No patient record for user during Alexa linking: " + email);
                    return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                            .body(Map.of("error", "patient_not_found"));
                }

                Patient patient = patientOpt.get();

                // 🌀 Generate refresh token (PLAIN TEXT for returning to Alexa)
                String plainRefreshToken = UUID.randomUUID().toString();

                // 🔒 HASH the token before saving to database
                String hashedRefreshToken = tokenHashService.hashToken(plainRefreshToken);

                LocalDateTime expiresAt = LocalDateTime.now().plusDays(30);

                // ✅ Save HASHED token to patient entity
                patient.setAlexaLinked(true);
                patient.setAlexaRefreshToken(hashedRefreshToken);
                patient.setAlexaRefreshTokenExpiresAt(expiresAt);
                patient.setAlexaRefreshTokenCreatedAt(LocalDateTime.now());
                patientRepository.save(patient);

                System.out.println("✅ Successfully linked Alexa for patient " + patient.getId());
                System.out.println("🔑 Refresh token expires at: " + expiresAt);
                System.out.println("🔑 Refresh token: " + plainRefreshToken);
                System.out.println("alexaLinkedValue: " + patient.getAlexaLinked());

                // 📤 Return PLAIN TEXT token to Alexa (NOT hashed!)
                return ResponseEntity.ok(Map.of(
                        "access_token", jwtToken,
                        "token_type", "Bearer",
                        "expires_in", 3600,
                        "refresh_token", plainRefreshToken));

            } catch (Exception e) {
                System.err.println("⚠️ Failed to link Alexa: " + e.getMessage());
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(Map.of("error", "linking_failed", "details", e.getMessage()));
            }
        }

        // 3️⃣ Handle refresh_token grant (token refresh)
        else if ("refresh_token".equalsIgnoreCase(grantType)) {
            System.out.println("🌀 [DEBUG] Refresh token grant detected.");
            System.out.println("🧩 Incoming refresh_token value: " + refreshToken);
            if (refreshToken == null || refreshToken.isBlank()) {
                return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                        .body(Map.of("error", "missing_refresh_token"));
            }

            // 🔍 Get ALL patients and verify refresh token against each
            try {
                List<Patient> allPatients = patientRepository.findAll();
                Patient matchedPatient = null;

                // 🔐 Verify refresh token against each patient's hashed token
                for (Patient patient : allPatients) {
                    if (patient.isAlexaLinked() &&
                            patient.getAlexaRefreshToken() != null &&
                            tokenHashService.verifyToken(refreshToken, patient.getAlexaRefreshToken())) {

                        matchedPatient = patient;
                        break;
                    }
                }

                if (matchedPatient == null) {
                    System.err.println("🔓 Invalid refresh token - patient not found");
                    return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                            .body(Map.of("error", "invalid_refresh_token"));
                }

                Patient patient = matchedPatient;

                // ⏰ Check if refresh token is expired
                if (patient.isAlexaRefreshTokenExpired()) {
                    System.err.println("🔓 Refresh token expired - unlinking Alexa");

                    patient.setAlexaLinked(false);
                    patient.setAlexaRefreshToken(null);
                    patient.setAlexaRefreshTokenExpiresAt(null);
                    patientRepository.save(patient);

                    return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                            .body(Map.of("error", "refresh_token_expired"));
                }

                // 🧠 Generate new tokens
                try {
                    User user = patient.getUser();
                    String email = user.getEmail();

                    String newJwt = jwt.createToken(email, user.getRole());

                    // 🔄 Generate new refresh token
                    String newPlainRefreshToken = UUID.randomUUID().toString();
                    String newHashedRefreshToken = tokenHashService.hashToken(newPlainRefreshToken);

                    LocalDateTime newExpiresAt = LocalDateTime.now().plusDays(30);

                    // ✅ Save HASHED new token
                    patient.setAlexaRefreshToken(newHashedRefreshToken);
                    patient.setAlexaRefreshTokenExpiresAt(newExpiresAt);
                    patientRepository.save(patient);

                    System.out.println("✅ Refreshed token for patient " + patient.getId());
                    System.out.println("🔑 New refresh token expires at: " + newExpiresAt);

                    // 📤 Return PLAIN TEXT new token to Alexa (NOT hashed!)
                    return ResponseEntity.ok(Map.of(
                            "access_token", newJwt,
                            "token_type", "Bearer",
                            "expires_in", 3600,
                            "refresh_token", newPlainRefreshToken));

                } catch (Exception e) {
                    System.err.println("⚠️ Failed to refresh token: " + e.getMessage());
                    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                            .body(Map.of("error", "refresh_failed", "details", e.getMessage()));
                }

            } catch (Exception e) {
                System.err.println("⚠️ Error during refresh: " + e.getMessage());
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body(Map.of("error", "internal_error"));
            }
        }

        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(Map.of("error", "unsupported_grant_type"));
    }

    @PostMapping("/sso/alexa/unlink")
    public ResponseEntity<?> unlinkAlexaAccount(HttpServletRequest request) {
        try {
            String token = extractTokenFromRequest(request);
            if (token == null) {
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .body(Map.of("error", "missing_token"));
            }

            String email = jwt.getEmailFromToken(token);
            Optional<User> userOpt = userRepository.findByEmail(email);
            if (userOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                        .body(Map.of("error", "user_not_found"));
            }

            User user = userOpt.get();
            Optional<Patient> patientOpt = patientRepository.findByUser(user);
            if (patientOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                        .body(Map.of("error", "patient_not_found"));
            }

            Patient patient = patientOpt.get();
            patient.setAlexaLinked(false);
            patient.setAlexaRefreshToken(null);
            patient.setAlexaRefreshTokenExpiresAt(null);
            patient.setAlexaRefreshTokenCreatedAt(null);
            patientRepository.save(patient);

            System.out.println("❌ Alexa unlinked for patient " + patient.getId());
            return ResponseEntity.ok(Map.of("message", "Alexa account unlinked successfully."));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", e.getMessage()));
        }
    }

    @GetMapping("/me")
    @Operation(
            summary = "Get current authenticated user",
            description = "Returns the currently logged-in user's profile information",
            security = @SecurityRequirement(name = "bearerAuth")
    )
    public ResponseEntity<?> getCurrentUser(HttpServletRequest request) {

        try {

            String token = extractTokenFromRequest(request);

            if (token == null) {
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .body(Map.of("error", "Authentication required"));
            }

            String email = jwt.getEmailFromToken(token);

            Optional<User> userOpt = userRepository.findByEmail(email);

            if (userOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "User not found"));
            }

            User user = userOpt.get();

            return ResponseEntity.ok(Map.of(
                    "id", user.getId(),
                    "name", user.getName(),
                    "email", user.getEmail(),
                    "role", user.getRole()
            ));

        } catch (Exception e) {

            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "Invalid token"));

        }
    }
}
