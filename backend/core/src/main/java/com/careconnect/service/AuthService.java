package com.careconnect.service;

import com.careconnect.dto.*;
import com.careconnect.model.Address;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.client.HttpClientErrorException;

import com.careconnect.model.Caregiver;
import com.careconnect.model.Patient;
import com.careconnect.model.FamilyMember;
import com.careconnect.model.ProfessionalInfo;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.FamilyMemberRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.service.StripeService;
import com.careconnect.exception.*;

import jakarta.servlet.ServletException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseCookie;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.LocalDate;
import java.util.Collections;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.careconnect.security.Role;
import jakarta.servlet.http.HttpServletResponse;


@Service
public class AuthService {

    @Autowired
    private GamificationService gamificationService;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private EmailService emailService;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private UserRepository users;

    @Autowired
    private PatientRepository patients;

    @Autowired
    private CaregiverRepository caregivers;

    @Autowired
    private FamilyMemberRepository familyMembers;

    @Autowired
    private JwtTokenProvider jwt;

    @Autowired(required = false)
    private StripeService stripeService;

    @Autowired
    private RestTemplate restTemplate;

    @Autowired(required = false)
    private com.careconnect.websocket.CareConnectWebSocketHandler webSocketHandler;

    // Google OAuth configuration
    @Value("${spring.security.oauth2.client.registration.google.client-id}")
    private String googleClientId;

    @Value("${spring.security.oauth2.client.registration.google.client-secret}")
    private String googleClientSecret;

    @Value("${frontend.base-url}")
    private String frontendBaseUrl;

    @Value("${careconnect.baseurl:http://localhost:8080}")
    private String backendUrl;

    @Value("${spring.security.oauth2.client.provider.google.authorization-uri}")
    private String googleAuthUri;

    @Value("${spring.security.oauth2.client.provider.google.token-uri}")
    private String googleTokenUri;

    @Value("${spring.security.oauth2.client.provider.google.user-info-uri}")
    private String googleUserInfoUri;

    @Transactional
    public ResponseEntity<?> register(RegisterRequest request) {
        // 1. Lookup existing user by email & role
        Role roleEnum;
        try {
            roleEnum = Role.valueOf(request.getRole().toUpperCase());
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest()
                    .body(Collections.singletonMap("error", "Invalid role specified"));
        }

        Optional<User> existingUserOpt = userRepository.findByEmailAndRole(request.getEmail(), roleEnum);

        // 2. If user exists
        if (existingUserOpt.isPresent()) {
            final User existingUser = existingUserOpt.get();
            if (Boolean.FALSE.equals(existingUser.getIsVerified())) {
                // User exists but is not verified -> resend with a NEW token
                final String newToken = UUID.randomUUID().toString();
                existingUser.setVerificationToken(newToken);
                userRepository.save(existingUser);

                // Use frontend-supplied base URL if provided, fallback to backend baseUrl
                final String link = backendUrl + "/v1/api/auth/verify/" + newToken;

                emailService.sendVerificationEmail(existingUser.getEmail(), link);

                return ResponseEntity.ok(Collections.singletonMap("message",
                        "A new verification email has been sent! Please check your inbox."));
            } else {
                // User exists AND is verified
                return ResponseEntity.status(HttpStatus.CONFLICT)
                        .body(Collections.singletonMap("error",
                                "An account with this email already exists and is verified."));
            }
        }

        // 3. Normal registration flow for new users
        final String verificationToken = UUID.randomUUID().toString();
        final String encodedPassword = passwordEncoder.encode(request.getPassword());

        User user = new User();
        user.setEmail(request.getEmail());
        user.setPassword(encodedPassword);  // Set both fields for consistency
        user.setPasswordHash(encodedPassword);
        user.setName(request.getName());
        user.setRole(Role.valueOf(request.getRole().toUpperCase()));
        user.setIsVerified(false);
        user.setVerificationToken(verificationToken);
        user.setCreatedAt(new Timestamp(System.currentTimeMillis()));

        registerRole(request, user);

        final String verificationBaseUrl = request.getVerificationBaseUrl();
        final String link = ((verificationBaseUrl != null && !verificationBaseUrl.isEmpty())
                ? verificationBaseUrl : backendUrl)
                + "/v1/api/auth/verify/" + verificationToken;

        emailService.sendVerificationEmail(user.getEmail(), link);

        return ResponseEntity.ok(Collections.singletonMap("message",
                "Registration successful! Please check your email to verify your account."));
    }

    private void registerRole(RegisterRequest request, User user) {
        switch (user.getRole()) {
            case PATIENT -> {
                if (request instanceof PatientRegistration regReq) {
                    // Store address on User for tax calculations
                    if (regReq.getAddress() != null) {
                        user.setAddressLine1(regReq.getAddress().line1());
                        user.setAddressLine2(regReq.getAddress().line2());
                        user.setCity(regReq.getAddress().city());
                        user.setState(regReq.getAddress().state());
                        user.setPostalCode(regReq.getAddress().zip());
                        user.setCountry("US"); // Default for MVP
                    }

                    // Save user first to get the ID
                    User savedUser = userRepository.save(user);

                    final Patient patient = new Patient();
                    patient.setPhone(regReq.getPhone());
                    patient.setDob(regReq.getDob());
                    patient.setAddress(
                            new Address(
                                    regReq.getAddress().line1(),
                                    regReq.getAddress().line2(),
                                    regReq.getAddress().city(),
                                    regReq.getAddress().state(),
                                    regReq.getAddress().zip()
                            )
                    );
                    patient.setGender(regReq.getGender());
                    patient.setEmail(request.getEmail());
                    patient.setFirstName(regReq.getFirstName());
                    patient.setLastName(regReq.getLastName());
                    patient.setUser(savedUser);
                    patients.save(patient);
                }
            }
            case CAREGIVER -> {
                if (request instanceof CaregiverRegistration regReq) {
                    // Store address on User for tax calculations
                    if (regReq.getAddress() != null) {
                        user.setAddressLine1(regReq.getAddress().line1());
                        user.setAddressLine2(regReq.getAddress().line2());
                        user.setCity(regReq.getAddress().city());
                        user.setState(regReq.getAddress().state());
                        user.setPostalCode(regReq.getAddress().zip());
                        user.setCountry("US"); // Default for MVP
                    }

                    // Save user first to get the ID
                    User savedUser = userRepository.save(user);

                    final Caregiver caregiver = new Caregiver();
                    caregiver.setCaregiverType(regReq.getCaregiverType());
                    caregiver.setDob(regReq.getDob());
                    caregiver.setPhone(regReq.getPhone());
                    caregiver.setAddress(
                            new Address(
                                    regReq.getAddress().line1(),
                                    regReq.getAddress().line2(),
                                    regReq.getAddress().city(),
                                    regReq.getAddress().state(),
                                    regReq.getAddress().zip()
                            )
                    );
                    caregiver.setEmail(request.getEmail());
                    caregiver.setFirstName(regReq.getFirstName());
                    caregiver.setLastName(regReq.getLastName());
                    caregiver.setGender(regReq.getGender());
                    caregiver.setUser(savedUser);
                    caregivers.save(caregiver);
                }
            }
            default -> throw new AppException(HttpStatus.BAD_REQUEST,
                    "Registration for " + user.getRole().toString() + " is unsupported");
        }
    }

    // ✅ Validate user for login
    public Optional<User> validateUser(String email, String password, String role) {
        try {
            Role roleEnum = Role.valueOf(role.toUpperCase());
            Optional<User> userOpt = userRepository.findByEmailAndRole(email, roleEnum);
            if (userOpt.isPresent()) {
                User user = userOpt.get();
                // Check password
                if (!passwordEncoder.matches(password, user.getPasswordHash())) {
                    return Optional.empty();
                }
                // Check email verification
                if (!Boolean.TRUE.equals(user.getIsVerified())) {
                    // Instead of returning empty, you could throw to signal "not verified"
                    throw new RuntimeException("Please verify your email before logging in.");
                }
                return Optional.of(user);
            }
        } catch (IllegalArgumentException e) {
            // Invalid role provided
            return Optional.empty();
        }
        return Optional.empty();
    }


    // ✅ Email verification (optional if implemented)
    public ResponseEntity<?> verifyToken(String token) {
        Optional<User> userOpt = userRepository.findByVerificationToken(token);
        if (userOpt.isPresent()) {
            User user = userOpt.get();
            user.setIsVerified(true);
            user.setVerificationToken(null); // Clear token so it can't be reused
            userRepository.save(user);

            // Send WebSocket notification if handler is available
            if (webSocketHandler != null) {
                try {
                    webSocketHandler.sendEmailVerificationNotification(user.getEmail());
                } catch (Exception e) {
                    // Log error but don't fail the verification
                    System.err.println("Failed to send WebSocket notification for email verification: " + e.getMessage());
                }
            }

            return ResponseEntity.ok("Your email has been verified! You can now log in.");
        } else {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body("Invalid or expired verification link.");
        }
    }

    /**
     * Resend verification email for an unverified user
     */
    public ResponseEntity<?> resendVerificationEmail(String email) {
        // Find user by email
        Optional<User> userOpt = userRepository.findByEmail(email);

        if (userOpt.isEmpty()) {
            // Don't reveal if user exists for security reasons
            return ResponseEntity.ok(Collections.singletonMap("message",
                    "If an unverified account exists with this email, a verification email has been sent."));
        }

        User user = userOpt.get();

        // Check if user is already verified
        if (Boolean.TRUE.equals(user.getIsVerified())) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Collections.singletonMap("error",
                            "This email address is already verified."));
        }

        // Generate new verification token
        String newToken = UUID.randomUUID().toString();
        user.setVerificationToken(newToken);
        userRepository.save(user);

        // Build verification link (use backend URL as default)
        String link = backendUrl + "/v1/api/auth/verify/" + newToken;

        // Send verification email
        emailService.sendVerificationEmail(user.getEmail(), link);

        return ResponseEntity.ok(Collections.singletonMap("message",
                "Verification email sent successfully! Please check your inbox."));
    }

    /**
     * Check if an email address is verified (without sending email)
     */
    public ResponseEntity<?> checkEmailVerificationStatus(String email) {
        // Find user by email
        Optional<User> userOpt = userRepository.findByEmail(email);

        if (userOpt.isEmpty()) {
            // Don't reveal if user exists for security reasons
            return ResponseEntity.ok(Collections.singletonMap("verified", false));
        }

        User user = userOpt.get();

        // Return verification status
        return ResponseEntity.ok(Collections.singletonMap("verified",
                Boolean.TRUE.equals(user.getIsVerified())));
    }

    // public LoginResponse loginV2(LoginRequest req) {
    // User user = users.findByEmail(req.getEmail())
    //         .orElseThrow(() -> new AuthenticationException("Invalid credentials"));

    // // System.out.println("Raw: " + req.getPassword());
    // // System.out.println("Hash: " + user.getPassword());
    // // System.out.println("Match: " + encoder.matches(req.getPassword(), user.getPassword()));
    // if (!encoder.matches(req.getPassword(), user.getPassword()))
    //     throw new AuthenticationException("Invalid credentials");

    // if (!user.isActive())            
    //     throw new AuthenticationException("Account suspended");

    // Long patientId = null;
    // Long caregiverId = null;
    // String name = null;

    // switch (user.getRole()) {
    //     case PATIENT -> {
    //         Patient patient = patients.findByUser(user).orElse(null);
    //         if (patient != null) {
    //             patientId = patient.getId();
    //             name = patient.getFirstName() + " " + patient.getLastName();
    //         }
    //     }
    //     case CAREGIVER -> {
    //         Caregiver caregiver = caregivers.findByUser(user).orElse(null);
    //         if (caregiver != null) {
    //             caregiverId = caregiver.getId();
    //             name = caregiver.getFirstName() + " " + caregiver.getLastName();
    //         }
    //     }
    //     case FAMILY_MEMBER -> {
    //         // TODO: FAMILY_MEMBER
    //     }
    //     case ADMIN -> {
    //         // TODO: ADMIN 
    //     }
    // }

    // return LoginResponse.builder()
    //         .id(user.getId())
    //         .email(user.getEmail())
    //         .role(user.getRole())
    //         .token(jwt.createToken(user.getEmail(), user.getRole()))
    //         .patientId(patientId)
    //         .caregiverId(caregiverId)
    //         .name(name)
    //         .build();
    // }

    /**
     * Stateless login – issues a signed JWT in an HttpOnly cookie.
     */
    public LoginResponse loginV2(LoginRequest req,
                                 HttpServletResponse res) {

        // Fix: Use findByEmailAndRole to prevent authentication issues when multiple users
        // have the same email with different roles
        User user;
        if (req.getRole() != null && !req.getRole().trim().isEmpty()) {
            try {
                Role roleEnum = Role.valueOf(req.getRole().toUpperCase());
                user = users.findByEmailAndRole(req.getEmail(), roleEnum)
                        .orElseThrow(() -> new AuthenticationException("Invalid credentials"));
            } catch (IllegalArgumentException e) {
                throw new AuthenticationException("Invalid role specified");
            }
        } else {
            // Fallback to findByEmail for backward compatibility, but this may cause issues
            // if multiple users have the same email with different roles
            user = users.findByEmail(req.getEmail())
                    .orElseThrow(() -> new AuthenticationException("Invalid credentials"));
        }

        if (!passwordEncoder.matches(req.getPassword(), user.getPasswordHash()))
            throw new AuthenticationException("Invalid credentials");

        if (!user.isActive())
            throw new AuthenticationException("Account suspended");

        /* ---------------- Gamification: First Login & 5-Day Streak ---------------- */
        gamificationService.unlockAchievement(user.getId(), "First Login", 50);

        handleLoginStreak(user);
        userRepository.save(user);



        /* ---------------- Resolve profile info ------------------------------ */
        Long patientId = null;
        Long caregiverId = null;
        String name = null;

        switch (user.getRole()) {
            case PATIENT -> {
                Patient p = patients.findByUserId(user.getId()).orElse(null);
                if (p != null) {
                    patientId = p.getId();
                    name = p.getFirstName() + " " + p.getLastName();
                }
            }
            case CAREGIVER -> {
                Caregiver c = caregivers.findByUserId(user.getId()).orElse(null);
                if (c != null) {
                    caregiverId = c.getId();
                    name = c.getFirstName() + " " + c.getLastName();
                }
            }
            case FAMILY_MEMBER -> {
                FamilyMember fm = familyMembers.findByUser(user).orElse(null);
                if (fm != null) {
                    name = fm.getFirstName() + " " + fm.getLastName();
                    caregiverId = fm.getId();
                }
            }
            case ADMIN -> {
                name = user.getName();
            }
        }

        /* ---------------- Build short-lived access token -------------------- */
        String token = jwt.createToken(user.getEmail(), user.getRole());  // 15-min exp

        /* ---------------- Send it as an HttpOnly cookie --------------------- */
        ResponseCookie cookie = ResponseCookie.from("AUTH", token)
                .httpOnly(true)
                .secure(false)        // disable only when running localhost over http set to true in prod
                .sameSite("Lax")
                .path("/")
                .maxAge(Duration.ofHours(3))      // upper bound of sliding window
                .build();
        res.addHeader(HttpHeaders.SET_COOKIE, cookie.toString());

        /* ---------------- Response body (unchanged) ------------------------- */
        return LoginResponse.builder()
                .id(user.getId())
                .email(user.getEmail())
                .role(user.getRole())
                .token(token)           // optional but handy for Postman / unit tests
                .patientId(patientId)
                .caregiverId(caregiverId)
                .name(name)
                .status(user.getStatus())
                .emailVerified(user.getIsVerified())
                .build();
    }

    /**
     * OAuth login (Google) - no password validation required
     */
    public LoginResponse loginOAuth(String email, HttpServletResponse res) {
        User user = users.findByEmail(email)
                .orElseThrow(() -> new AuthenticationException("User not found"));

        // Skip password validation for OAuth users
        if (!user.isActive())
            throw new AuthenticationException("Account suspended");

        /* ---------------- Gamification: First Login & 5-Day Streak ---------------- */

        gamificationService.unlockAchievement(user.getId(), "First Login", 50);

        handleLoginStreak(user);

        userRepository.save(user);


        /* ---------------- Resolve profile info ------------------------------ */
        Long patientId = null;
        Long caregiverId = null;
        String name = null;

        switch (user.getRole()) {
            case PATIENT -> {
                Patient p = patients.findByUser(user).orElse(null);
                if (p != null) {
                    patientId = p.getId();
                    name = p.getFirstName() + " " + p.getLastName();
                }
            }
            case CAREGIVER -> {
                Caregiver c = caregivers.findByUser(user).orElse(null);
                if (c != null) {
                    caregiverId = c.getId();
                    name = c.getFirstName() + " " + c.getLastName();
                }
            }
            case FAMILY_MEMBER -> {
                FamilyMember fm = familyMembers.findByUser(user).orElse(null);
                if (fm != null) {
                    name = fm.getFirstName() + " " + fm.getLastName();
                    // Set the family member's ID so it can be used to fetch patient relationships later
                    caregiverId = fm.getId(); // Using caregiverId field to store family member ID
                }
            }
            case ADMIN -> {
                // Admin case - just use the user's name
                name = user.getName();
            }
        }

        /* ---------------- Build short-lived access token -------------------- */
        String token = jwt.createToken(user.getEmail(), user.getRole());  // 15-min exp

        /* ---------------- Send it as an HttpOnly cookie --------------------- */
        ResponseCookie cookie = ResponseCookie.from("AUTH", token)
                .httpOnly(true)
                .secure(false)        // disable only when running localhost over http set to true in prod
                .sameSite("Lax")
                .path("/")
                .maxAge(Duration.ofHours(3))
                .build();
        res.addHeader(HttpHeaders.SET_COOKIE, cookie.toString());

        /* ---------------- Response body (unchanged) ------------------------- */
        return LoginResponse.builder()
                .id(user.getId())
                .email(user.getEmail())
                .role(user.getRole())
                .token(token)
                .patientId(patientId)
                .caregiverId(caregiverId)
                .name(name)
                .status(user.getStatus())
                .build();
    }

    /**
     * Change password for authenticated user
     */
    public ResponseEntity<?> changePassword(String email, String currentPassword, String newPassword) {
        try {
            User user = users.findByEmail(email)
                    .orElseThrow(() -> new AuthenticationException("User not found"));

            // Verify current password
            if (!passwordEncoder.matches(currentPassword, user.getPasswordHash())) {
                return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                        .body(Collections.singletonMap("error", "Current password is incorrect"));
            }

            // Set new password
            String encodedNewPassword = passwordEncoder.encode(newPassword);
            user.setPassword(encodedNewPassword);
            user.setPasswordHash(encodedNewPassword);
            userRepository.save(user);

            return ResponseEntity.ok(Collections.singletonMap("message",
                    "Password changed successfully"));

        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Collections.singletonMap("error", "Failed to change password"));
        }
    }

    /**
     * Google token validation method - to be implemented with actual Google API
     */
    public Map<String, Object> validateGoogleToken(String token) {
        // TODO: Implement actual Google token validation using Google API
        // For now, this is a placeholder that returns null
        // In real implementation, you would:
        // 1. Call Google's tokeninfo endpoint
        // 2. Verify the token signature
        // 3. Extract user information

        throw new UnsupportedOperationException("Google token validation not yet implemented");
    }

    /**
     * Set password for patient account using setup token
     */
    public ResponseEntity<?> setupPassword(String token, String newPassword) {
        Optional<User> userOpt = userRepository.findByVerificationToken(token);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Collections.singletonMap("error", "Invalid or expired password setup link"));
        }

        User user = userOpt.get();

        // Set password and verify account
        String encodedPassword = passwordEncoder.encode(newPassword);
        user.setPassword(encodedPassword);
        user.setPasswordHash(encodedPassword);
        user.setIsVerified(true);
        user.setVerificationToken(null); // Clear token so it can't be reused
        userRepository.save(user);

        return ResponseEntity.ok(Collections.singletonMap("message",
                "Password has been set successfully! You can now log in."));
    }

    // ====================== Google OAuth Methods ======================

    /**
     * Build Google OAuth authorization URL
     */
    public String buildGoogleOAuthUrl() {
        try {
            String redirectUri = URLEncoder.encode(backendUrl + "/v1/api/auth/sso/google/callback", StandardCharsets.UTF_8);
            return googleAuthUri + "?" +
                    "client_id=" + googleClientId +
                    "&redirect_uri=" + redirectUri +
                    "&scope=openid%20email%20profile" +
                    "&response_type=code" +
                    "&state=" + generateSecureState();
        } catch (Exception e) {
            throw new RuntimeException("Failed to build Google OAuth URL", e);
        }
    }

    /**
     * Process Google OAuth callback - exchange code for user info and login
     */
    public LoginResponse processGoogleOAuth(String code, HttpServletResponse response) {
        try {
            // Exchange authorization code for access token
            String googleAccessToken = exchangeCodeForToken(code);

            // Get user info from Google
            Map<String, Object> userInfo = getUserInfoFromGoogle(googleAccessToken);
            String email = (String) userInfo.get("email");

            if (email == null || email.trim().isEmpty()) {
                throw new OAuthException("Unable to retrieve email from Google", "invalid_response");
            }

            // Login using OAuth (no password validation)
            return loginOAuth(email, response);

        } catch (OAuthException e) {
            // Re-throw OAuth exceptions as-is (they have specific error types)
            throw e;
        } catch (AuthenticationException e) {
            // Convert authentication exceptions to OAuth exceptions with generic error type
            throw new OAuthException(e.getMessage(), "authentication_failed", e);
        } catch (Exception e) {
            throw new OAuthException("Google OAuth authentication failed: " + e.getMessage(), "oauth_failed", e);
        }
    }

    private String exchangeCodeForToken(String code) {
        try {
            RestTemplate restTemplate = new RestTemplate();

            // Set the Content-Type header
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED); // <--- ADD THIS LINE

            MultiValueMap<String, String> body = new LinkedMultiValueMap<>();
            body.add("code", code);
            body.add("client_id", googleClientId);
            body.add("client_secret", googleClientSecret);
            body.add("redirect_uri", backendUrl + "/v1/api/auth/sso/google/callback");
            body.add("grant_type", "authorization_code");

            // Combine headers and body into an HttpEntity
            HttpEntity<MultiValueMap<String, String>> requestEntity = new HttpEntity<>(body, headers);

            // Use exchange method to send the request with explicit headers
            ResponseEntity<Map<String, Object>> response = restTemplate.exchange(
                    googleTokenUri,
                    HttpMethod.POST,
                    requestEntity,
                    new org.springframework.core.ParameterizedTypeReference<Map<String, Object>>() {
                    }
            );

            // Add logging for the response body for further debugging if needed
            if (response.getStatusCode().isError()) {
                // This block is for more specific error handling
                // In a real application, you might log the entire response body for 400 errors
                throw new AuthenticationException("Google token exchange failed with status " + response.getStatusCode() + ": " + response.getBody());
            }

            if (response.getBody() == null) {
                throw new AuthenticationException("No response from Google token endpoint");
            }

            String accessToken = (String) response.getBody().get("access_token");
            if (accessToken == null) {
                throw new AuthenticationException("No access token received from Google. Response: " + response.getBody());
            }

            return accessToken;

        } catch (HttpClientErrorException e) {
            // Catch specific HTTP client errors (like 400 BAD REQUEST)
            String responseBody = e.getResponseBodyAsString();

            if (e.getStatusCode().value() == 400) {
                if (responseBody.contains("invalid_grant")) {
                    throw new OAuthException("Authorization code has expired or is invalid", "invalid_grant", e);
                } else if (responseBody.contains("invalid_client")) {
                    throw new OAuthException("Invalid OAuth client configuration", "invalid_client", e);
                } else if (responseBody.contains("invalid_request")) {
                    throw new OAuthException("Invalid OAuth request parameters", "invalid_request", e);
                } else {
                    throw new OAuthException("Bad request to Google OAuth server", "invalid_request", e);
                }
            } else if (e.getStatusCode().value() == 401) {
                throw new OAuthException("Unauthorized OAuth request", "invalid_client", e);
            } else if (e.getStatusCode().value() >= 500) {
                throw new OAuthException("Google OAuth server is temporarily unavailable", "temporarily_unavailable", e);
            } else {
                throw new OAuthException("Failed to exchange code for token with Google. Status: " + e.getStatusCode(), "api_error", e);
            }
        } catch (Exception e) {
            throw new OAuthException("Failed to exchange code for token: " + e.getMessage(), "network_error", e);
        }
    }

    /**
     * Get user information from Google using access token
     */
    private Map<String, Object> getUserInfoFromGoogle(String accessToken) {
        try {
            String userInfoUrl = googleUserInfoUri + "?access_token=" + accessToken;

            RestTemplate restTemplate = new RestTemplate();
            ResponseEntity<Map<String, Object>> response = restTemplate.exchange(
                    userInfoUrl,
                    HttpMethod.GET,
                    null,
                    new org.springframework.core.ParameterizedTypeReference<Map<String, Object>>() {
                    }
            );

            if (response.getBody() == null) {
                throw new AuthenticationException("No user info received from Google");
            }

            return response.getBody();

        } catch (HttpClientErrorException e) {
            // Handle HTTP client errors when calling Google's user info endpoint
            if (e.getStatusCode().value() == 401) {
                throw new OAuthException("Invalid or expired access token from Google", "invalid_token", e);
            } else if (e.getStatusCode().value() == 403) {
                throw new OAuthException("Insufficient permissions to access Google user info", "invalid_scope", e);
            } else if (e.getStatusCode().value() >= 500) {
                throw new OAuthException("Google user info service is temporarily unavailable", "temporarily_unavailable", e);
            } else {
                throw new OAuthException("Failed to get user info from Google. Status: " + e.getStatusCode(), "api_error", e);
            }
        } catch (Exception e) {
            throw new OAuthException("Failed to get user info from Google: " + e.getMessage(), "network_error", e);
        }
    }

    /**
     * Generate secure state parameter for OAuth flow
     * TODO: Implement proper CSRF protection with session-based state validation
     */
    private String generateSecureState() {
        return UUID.randomUUID().toString();
    }

    private void handleLoginStreak(User user) {
        LocalDate today = LocalDate.now();
        LocalDate lastLogin = user.getLastLoginDate();
        Integer streak = user.getLoginStreak();

        if (streak == null || lastLogin == null || !lastLogin.plusDays(1).equals(today)) {
            user.setLoginStreak(1);
        } else {
            user.setLoginStreak(streak + 1);
        }

        user.setLastLoginDate(today);

        if (user.getLoginStreak() == 5) {
            gamificationService.unlockAchievement(user.getId(), "5-Day Streak", 100);
        }
    }

}
