package com.careconnect.service;

import com.careconnect.dto.*;
import com.careconnect.exception.AppException;
import com.careconnect.exception.AuthenticationException;
import com.careconnect.exception.OAuthException;
import com.careconnect.model.*;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.FamilyMemberRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import com.careconnect.websocket.CareConnectWebSocketHandler;
import com.sun.net.httpserver.HttpServer;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestTemplate;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.time.LocalDate;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class AuthServiceTest {

    private static HttpServer mockServer;
    private static int mockServerPort;
    @Mock
    private GamificationService gamificationService;
    @Mock
    private UserRepository userRepository;
    @Mock
    private EmailService emailService;
    @Mock
    private PasswordEncoder passwordEncoder;
    @Mock
    private UserRepository users;
    @Mock
    private PatientRepository patients;
    @Mock
    private CaregiverRepository caregivers;
    @Mock
    private FamilyMemberRepository familyMembers;
    @Mock
    private JwtTokenProvider jwt;
    @Mock
    private StripeService stripeService;
    @Mock
    private RestTemplate restTemplate;
    @Mock
    private CareConnectWebSocketHandler webSocketHandler;
    @InjectMocks
    private AuthService authService;
    @Mock
    private HttpServletResponse httpServletResponse;
    private User testUser;

    @BeforeAll
    static void startMockServer() throws IOException {
        mockServer = HttpServer.create(new InetSocketAddress(0), 0);
        mockServerPort = mockServer.getAddress().getPort();

        // Token endpoint: returns valid token
        mockServer.createContext("/token/valid", exchange -> {
            final String body = "{\"access_token\":\"fake-access-token\"}";
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // Token endpoint: returns 200 but empty body (null body scenario)
        mockServer.createContext("/token/empty-body", exchange -> {
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, -1);
            exchange.getResponseBody().close();
        });

        // Token endpoint: returns 200 but no access_token in body
        mockServer.createContext("/token/no-access-token", exchange -> {
            final String body = "{\"token_type\":\"Bearer\"}";
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // Token endpoint: returns 400 with invalid_grant
        mockServer.createContext("/token/400-invalid-grant", exchange -> {
            final String body = "{\"error\":\"invalid_grant\",\"error_description\":\"Code expired\"}";
            exchange.sendResponseHeaders(400, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // Token endpoint: returns 400 with invalid_client
        mockServer.createContext("/token/400-invalid-client", exchange -> {
            final String body = "{\"error\":\"invalid_client\"}";
            exchange.sendResponseHeaders(400, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // Token endpoint: returns 400 with invalid_request
        mockServer.createContext("/token/400-invalid-request", exchange -> {
            final String body = "{\"error\":\"invalid_request\"}";
            exchange.sendResponseHeaders(400, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // Token endpoint: returns 400 with generic error
        mockServer.createContext("/token/400-generic", exchange -> {
            final String body = "{\"error\":\"some_other_error\"}";
            exchange.sendResponseHeaders(400, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // Token endpoint: returns 401
        mockServer.createContext("/token/401", exchange -> {
            final String body = "{\"error\":\"unauthorized\"}";
            exchange.sendResponseHeaders(401, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // Token endpoint: returns 500
        mockServer.createContext("/token/500", exchange -> {
            final String body = "{\"error\":\"internal_server_error\"}";
            exchange.sendResponseHeaders(500, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // Token endpoint: returns 403 (not 400, 401, or 500+)
        mockServer.createContext("/token/403", exchange -> {
            final String body = "{\"error\":\"forbidden\"}";
            exchange.sendResponseHeaders(403, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // User info endpoint: returns valid user info
        mockServer.createContext("/userinfo/valid", exchange -> {
            final String body = "{\"email\":\"oauth@test.com\",\"name\":\"OAuth User\"}";
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // User info endpoint: returns null email
        mockServer.createContext("/userinfo/no-email", exchange -> {
            final String body = "{\"name\":\"No Email User\"}";
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // User info endpoint: returns empty email
        mockServer.createContext("/userinfo/empty-email", exchange -> {
            final String body = "{\"email\":\"  \",\"name\":\"Empty Email\"}";
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // User info endpoint: returns empty body
        mockServer.createContext("/userinfo/empty-body", exchange -> {
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, -1);
            exchange.getResponseBody().close();
        });

        // User info endpoint: returns 401
        mockServer.createContext("/userinfo/401", exchange -> {
            final String body = "{\"error\":\"unauthorized\"}";
            exchange.sendResponseHeaders(401, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // User info endpoint: returns 403
        mockServer.createContext("/userinfo/403", exchange -> {
            final String body = "{\"error\":\"forbidden\"}";
            exchange.sendResponseHeaders(403, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // User info endpoint: returns 500
        mockServer.createContext("/userinfo/500", exchange -> {
            final String body = "{\"error\":\"internal_server_error\"}";
            exchange.sendResponseHeaders(500, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        // User info endpoint: returns 404 (not 401, 403, or 500+)
        mockServer.createContext("/userinfo/404", exchange -> {
            final String body = "{\"error\":\"not_found\"}";
            exchange.sendResponseHeaders(404, body.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body.getBytes());
            }
        });

        mockServer.setExecutor(null);
        mockServer.start();
    }

    @AfterAll
    static void stopMockServer() throws Exception {
        if (mockServer != null) {
            mockServer.stop(0);
        }
    }

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);

        ReflectionTestUtils.setField(authService, "googleClientId", "test-client-id");
        ReflectionTestUtils.setField(authService, "googleClientSecret", "test-client-secret");
        ReflectionTestUtils.setField(authService, "frontendBaseUrl", "http://localhost:3000");
        ReflectionTestUtils.setField(authService, "backendUrl", "http://localhost:8080");
        ReflectionTestUtils.setField(authService, "googleAuthUri", "https://accounts.google.com/o/oauth2/v2/auth");
        ReflectionTestUtils.setField(authService, "googleTokenUri", "http://localhost:" + mockServerPort + "/token/valid");
        ReflectionTestUtils.setField(authService, "googleUserInfoUri", "http://localhost:" + mockServerPort + "/userinfo/valid");

        testUser = new User();
        testUser.setId(1L);
        testUser.setEmail("test@test.com");
        testUser.setPasswordHash("encodedPassword");
        testUser.setRole(Role.PATIENT);
        testUser.setIsVerified(true);
        testUser.setStatus("ACTIVE");
        testUser.setName("Test User");
        testUser.setLoginStreak(0);
        testUser.setLastLoginDate(null);
    }

    // ==================== register Tests ====================

    @Nested
    @DisplayName("register tests")
    class RegisterTests {

        @Test
        @DisplayName("register_invalidRole_shouldReturnBadRequest")
        void register_invalidRole_shouldReturnBadRequest() throws Exception {
            final PatientRegistration req = new PatientRegistration();
            req.setRole("INVALID_ROLE");
            req.setEmail("test@test.com");

            final ResponseEntity<?> response = authService.register(req);

            assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        }

        @Test
        @DisplayName("register_existingUnverifiedUser_shouldResendVerification")
        void register_existingUnverifiedUser_shouldResendVerification() throws Exception {
            final PatientRegistration req = new PatientRegistration();
            req.setRole("PATIENT");
            req.setEmail("test@test.com");
            req.setPassword("password123");

            final User unverifiedUser = new User();
            unverifiedUser.setEmail("test@test.com");
            unverifiedUser.setIsVerified(false);
            unverifiedUser.setRole(Role.PATIENT);

            when(userRepository.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(unverifiedUser));

            final ResponseEntity<?> response = authService.register(req);

            assertEquals(HttpStatus.OK, response.getStatusCode());
            verify(emailService).sendVerificationEmail(eq("test@test.com"), anyString());
            verify(userRepository).save(unverifiedUser);
        }

        @Test
        @DisplayName("register_existingVerifiedUser_shouldReturnConflict")
        void register_existingVerifiedUser_shouldReturnConflict() throws Exception {
            final PatientRegistration req = new PatientRegistration();
            req.setRole("PATIENT");
            req.setEmail("test@test.com");
            req.setPassword("password123");

            final User verifiedUser = new User();
            verifiedUser.setEmail("test@test.com");
            verifiedUser.setIsVerified(true);
            verifiedUser.setRole(Role.PATIENT);

            when(userRepository.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(verifiedUser));

            final ResponseEntity<?> response = authService.register(req);

            assertEquals(HttpStatus.CONFLICT, response.getStatusCode());
        }

        @Test
        @DisplayName("register_newPatient_shouldCreateUserAndSendEmail")
        void register_newPatient_shouldCreateUserAndSendEmail() throws Exception {
            final PatientRegistration req = new PatientRegistration();
            req.setRole("PATIENT");
            req.setEmail("new@test.com");
            req.setPassword("password123");
            req.setName("New User");
            req.setFirstName("New");
            req.setLastName("User");
            req.setPhone("1234567890");
            req.setDob("1990-01-01");
            req.setAddress(new AddressDto("123 Main St", null, "City", "MD", "21001", null));
            req.setVerificationBaseUrl(null);

            when(userRepository.findByEmailAndRole("new@test.com", Role.PATIENT))
                    .thenReturn(Optional.empty());
            when(passwordEncoder.encode("password123")).thenReturn("encodedPwd");
            when(userRepository.save(any(User.class))).thenAnswer(inv -> {
                final User u = inv.getArgument(0);
                u.setId(2L);
                return u;
            });

            final ResponseEntity<?> response = authService.register(req);

            assertEquals(HttpStatus.OK, response.getStatusCode());
            verify(patients).save(any(Patient.class));
            verify(emailService).sendVerificationEmail(eq("new@test.com"), anyString());
        }

        @Test
        @DisplayName("register_newPatientWithVerificationBaseUrl_shouldUseProvidedUrl")
        void register_newPatientWithVerificationBaseUrl_shouldUseProvidedUrl() throws Exception {
            final PatientRegistration req = new PatientRegistration();
            req.setRole("PATIENT");
            req.setEmail("new@test.com");
            req.setPassword("password123");
            req.setName("New User");
            req.setFirstName("New");
            req.setLastName("User");
            req.setPhone("1234567890");
            req.setDob("1990-01-01");
            req.setAddress(new AddressDto("123 Main St", null, "City", "MD", "21001", null));
            req.setVerificationBaseUrl("https://custom-frontend.com");

            when(userRepository.findByEmailAndRole("new@test.com", Role.PATIENT))
                    .thenReturn(Optional.empty());
            when(passwordEncoder.encode("password123")).thenReturn("encodedPwd");
            when(userRepository.save(any(User.class))).thenAnswer(inv -> {
                final User u = inv.getArgument(0);
                u.setId(2L);
                return u;
            });

            final ResponseEntity<?> response = authService.register(req);

            assertEquals(HttpStatus.OK, response.getStatusCode());
            verify(emailService).sendVerificationEmail(eq("new@test.com"), contains("https://custom-frontend.com"));
        }

        @Test
        @DisplayName("register_newCaregiver_shouldCreateCaregiverAndSendEmail")
        void register_newCaregiver_shouldCreateCaregiverAndSendEmail() throws Exception {
            final CaregiverRegistration req = new CaregiverRegistration();
            req.setRole("CAREGIVER");
            req.setEmail("caregiver@test.com");
            req.setPassword("password123");
            req.setName("Caregiver User");
            req.setFirstName("Care");
            req.setLastName("Giver");
            req.setDob("1985-05-15");
            req.setPhone("9876543210");
            req.setAddress(new AddressDto("456 Elm St", null, "Town", "VA", "22001", null));
            req.setCaregiverType("PROFESSIONAL");

            when(userRepository.findByEmailAndRole("caregiver@test.com", Role.CAREGIVER))
                    .thenReturn(Optional.empty());
            when(passwordEncoder.encode("password123")).thenReturn("encodedPwd");
            when(userRepository.save(any(User.class))).thenAnswer(inv -> {
                final User u = inv.getArgument(0);
                u.setId(3L);
                return u;
            });

            final ResponseEntity<?> response = authService.register(req);

            assertEquals(HttpStatus.OK, response.getStatusCode());
            verify(caregivers).save(any(Caregiver.class));
            verify(emailService).sendVerificationEmail(eq("caregiver@test.com"), anyString());
        }

        @Test
        @DisplayName("register_unsupportedRole_shouldThrowAppException")
        void register_unsupportedRole_shouldThrowAppException() throws Exception {
            final PatientRegistration req = new PatientRegistration();
            req.setRole("ADMIN");
            req.setEmail("admin@test.com");
            req.setPassword("password123");
            req.setName("Admin");

            when(userRepository.findByEmailAndRole("admin@test.com", Role.ADMIN))
                    .thenReturn(Optional.empty());
            when(passwordEncoder.encode("password123")).thenReturn("encodedPwd");

            assertThrows(AppException.class, () -> authService.register(req));
        }

        @Test
        @DisplayName("register_patientRoleWithCaregiverRegistration_shouldSkipPatientCreation")
        void register_patientRoleWithCaregiverRegistration_shouldSkipPatientCreation() throws Exception {
            final CaregiverRegistration req = new CaregiverRegistration();
            req.setRole("PATIENT");
            req.setEmail("skip@test.com");
            req.setPassword("password123");
            req.setName("Skip User");
            req.setVerificationBaseUrl(null);

            when(userRepository.findByEmailAndRole("skip@test.com", Role.PATIENT))
                    .thenReturn(Optional.empty());
            when(passwordEncoder.encode("password123")).thenReturn("encodedPwd");
            when(userRepository.save(any(User.class))).thenAnswer(inv -> {
                final User u = inv.getArgument(0);
                u.setId(10L);
                return u;
            });

            final ResponseEntity<?> response = authService.register(req);

            assertEquals(HttpStatus.OK, response.getStatusCode());
            verify(patients, never()).save(any(Patient.class));
            verify(emailService).sendVerificationEmail(eq("skip@test.com"), anyString());
        }

        @Test
        @DisplayName("register_caregiverRoleWithPatientRegistration_shouldSkipCaregiverCreation")
        void register_caregiverRoleWithPatientRegistration_shouldSkipCaregiverCreation() throws Exception {
            final PatientRegistration req = new PatientRegistration();
            req.setRole("CAREGIVER");
            req.setEmail("skip2@test.com");
            req.setPassword("password123");
            req.setName("Skip User 2");
            req.setVerificationBaseUrl(null);

            when(userRepository.findByEmailAndRole("skip2@test.com", Role.CAREGIVER))
                    .thenReturn(Optional.empty());
            when(passwordEncoder.encode("password123")).thenReturn("encodedPwd");
            when(userRepository.save(any(User.class))).thenAnswer(inv -> {
                final User u = inv.getArgument(0);
                u.setId(11L);
                return u;
            });

            final ResponseEntity<?> response = authService.register(req);

            assertEquals(HttpStatus.OK, response.getStatusCode());
            verify(caregivers, never()).save(any(Caregiver.class));
            verify(emailService).sendVerificationEmail(eq("skip2@test.com"), anyString());
        }

        @Test
        @DisplayName("register_newPatientWithEmptyVerificationBaseUrl_shouldUseBackendUrl")
        void register_newPatientWithEmptyVerificationBaseUrl_shouldUseBackendUrl() throws Exception {
            final PatientRegistration req = new PatientRegistration();
            req.setRole("PATIENT");
            req.setEmail("new2@test.com");
            req.setPassword("password123");
            req.setName("New User 2");
            req.setFirstName("New");
            req.setLastName("User2");
            req.setPhone("1234567890");
            req.setDob("1990-01-01");
            req.setAddress(new AddressDto("123 Main St", null, "City", "MD", "21001", null));
            req.setVerificationBaseUrl("");

            when(userRepository.findByEmailAndRole("new2@test.com", Role.PATIENT))
                    .thenReturn(Optional.empty());
            when(passwordEncoder.encode("password123")).thenReturn("encodedPwd");
            when(userRepository.save(any(User.class))).thenAnswer(inv -> {
                final User u = inv.getArgument(0);
                u.setId(5L);
                return u;
            });

            final ResponseEntity<?> response = authService.register(req);

            assertEquals(HttpStatus.OK, response.getStatusCode());
            verify(emailService).sendVerificationEmail(eq("new2@test.com"), contains("http://localhost:8080"));
        }

        @Test
        @DisplayName("register_familyMemberRole_shouldThrowAppException")
        void register_familyMemberRole_shouldThrowAppException() throws Exception {
            final PatientRegistration req = new PatientRegistration();
            req.setRole("FAMILY_MEMBER");
            req.setEmail("fm@test.com");
            req.setPassword("password123");
            req.setName("FM User");

            when(userRepository.findByEmailAndRole("fm@test.com", Role.FAMILY_MEMBER))
                    .thenReturn(Optional.empty());
            when(passwordEncoder.encode("password123")).thenReturn("encodedPwd");

            assertThrows(AppException.class, () -> authService.register(req));
        }
    }

    // ==================== validateUser Tests ====================

    @Nested
    @DisplayName("validateUser tests")
    class ValidateUserTests {

        @Test
        @DisplayName("validateUser_validCredentials_shouldReturnUser")
        void validateUser_validCredentials_shouldReturnUser() throws Exception {
            when(userRepository.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);

            final Optional<User> result = authService.validateUser("test@test.com", "password", "PATIENT");

            assertTrue(result.isPresent());
            assertEquals(testUser.getEmail(), result.get().getEmail());
        }

        @Test
        @DisplayName("validateUser_wrongPassword_shouldReturnEmpty")
        void validateUser_wrongPassword_shouldReturnEmpty() throws Exception {
            when(userRepository.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("wrongPassword", "encodedPassword")).thenReturn(false);

            final Optional<User> result = authService.validateUser("test@test.com", "wrongPassword", "PATIENT");

            assertTrue(result.isEmpty());
        }

        @Test
        @DisplayName("validateUser_unverifiedUser_shouldThrowRuntimeException")
        void validateUser_unverifiedUser_shouldThrowRuntimeException() throws Exception {
            final User unverifiedUser = new User();
            unverifiedUser.setEmail("test@test.com");
            unverifiedUser.setPasswordHash("encodedPassword");
            unverifiedUser.setIsVerified(false);
            unverifiedUser.setRole(Role.PATIENT);

            when(userRepository.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(unverifiedUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);

            assertThrows(RuntimeException.class,
                    () -> authService.validateUser("test@test.com", "password", "PATIENT"));
        }

        @Test
        @DisplayName("validateUser_userNotFound_shouldReturnEmpty")
        void validateUser_userNotFound_shouldReturnEmpty() throws Exception {
            when(userRepository.findByEmailAndRole("unknown@test.com", Role.PATIENT))
                    .thenReturn(Optional.empty());

            final Optional<User> result = authService.validateUser("unknown@test.com", "password", "PATIENT");

            assertTrue(result.isEmpty());
        }

        @Test
        @DisplayName("validateUser_invalidRole_shouldReturnEmpty")
        void validateUser_invalidRole_shouldReturnEmpty() throws Exception {
            final Optional<User> result = authService.validateUser("test@test.com", "password", "INVALID");

            assertTrue(result.isEmpty());
        }
    }

    // ==================== verifyToken Tests ====================

    @Nested
    @DisplayName("verifyToken tests")
    class VerifyTokenTests {

        @Test
        @DisplayName("verifyToken_validToken_shouldVerifyUser")
        void verifyToken_validToken_shouldVerifyUser() throws Exception {
            final User user = new User();
            user.setEmail("test@test.com");
            user.setIsVerified(false);
            user.setVerificationToken("valid-token");

            when(userRepository.findByVerificationToken("valid-token")).thenReturn(Optional.of(user));

            final ResponseEntity<?> response = authService.verifyToken("valid-token");

            assertEquals(HttpStatus.OK, response.getStatusCode());
            assertTrue(user.getIsVerified());
            assertNull(user.getVerificationToken());
            verify(userRepository).save(user);
        }

        @Test
        @DisplayName("verifyToken_validTokenWithWebSocket_shouldSendNotification")
        void verifyToken_validTokenWithWebSocket_shouldSendNotification() throws Exception {
            final User user = new User();
            user.setEmail("test@test.com");
            user.setIsVerified(false);
            user.setVerificationToken("valid-token");

            when(userRepository.findByVerificationToken("valid-token")).thenReturn(Optional.of(user));

            final ResponseEntity<?> response = authService.verifyToken("valid-token");

            assertEquals(HttpStatus.OK, response.getStatusCode());
            verify(webSocketHandler).sendEmailVerificationNotification("test@test.com");
        }

        @Test
        @DisplayName("verifyToken_webSocketThrowsException_shouldStillVerify")
        void verifyToken_webSocketThrowsException_shouldStillVerify() throws Exception {
            final User user = new User();
            user.setEmail("test@test.com");
            user.setIsVerified(false);
            user.setVerificationToken("valid-token");

            when(userRepository.findByVerificationToken("valid-token")).thenReturn(Optional.of(user));
            doThrow(new RuntimeException("WebSocket error"))
                    .when(webSocketHandler).sendEmailVerificationNotification("test@test.com");

            final ResponseEntity<?> response = authService.verifyToken("valid-token");

            assertEquals(HttpStatus.OK, response.getStatusCode());
            assertTrue(user.getIsVerified());
        }

        @Test
        @DisplayName("verifyToken_nullWebSocketHandler_shouldStillVerify")
        void verifyToken_nullWebSocketHandler_shouldStillVerify() throws Exception {
            ReflectionTestUtils.setField(authService, "webSocketHandler", null);

            final User user = new User();
            user.setEmail("test@test.com");
            user.setIsVerified(false);
            user.setVerificationToken("valid-token");

            when(userRepository.findByVerificationToken("valid-token")).thenReturn(Optional.of(user));

            final ResponseEntity<?> response = authService.verifyToken("valid-token");

            assertEquals(HttpStatus.OK, response.getStatusCode());
            assertTrue(user.getIsVerified());
        }

        @Test
        @DisplayName("verifyToken_invalidToken_shouldReturnBadRequest")
        void verifyToken_invalidToken_shouldReturnBadRequest() throws Exception {
            when(userRepository.findByVerificationToken("invalid-token")).thenReturn(Optional.empty());

            final ResponseEntity<?> response = authService.verifyToken("invalid-token");

            assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        }
    }

    // ==================== resendVerificationEmail Tests ====================

    @Nested
    @DisplayName("resendVerificationEmail tests")
    class ResendVerificationEmailTests {

        @Test
        @DisplayName("resendVerificationEmail_userNotFound_shouldReturnOkForSecurity")
        void resendVerificationEmail_userNotFound_shouldReturnOkForSecurity() throws Exception {
            when(userRepository.findByEmail("unknown@test.com")).thenReturn(Optional.empty());

            final ResponseEntity<?> response = authService.resendVerificationEmail("unknown@test.com");

            assertEquals(HttpStatus.OK, response.getStatusCode());
            verify(emailService, never()).sendVerificationEmail(anyString(), anyString());
        }

        @Test
        @DisplayName("resendVerificationEmail_alreadyVerified_shouldReturnBadRequest")
        void resendVerificationEmail_alreadyVerified_shouldReturnBadRequest() throws Exception {
            final User verifiedUser = new User();
            verifiedUser.setEmail("test@test.com");
            verifiedUser.setIsVerified(true);

            when(userRepository.findByEmail("test@test.com")).thenReturn(Optional.of(verifiedUser));

            final ResponseEntity<?> response = authService.resendVerificationEmail("test@test.com");

            assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        }

        @Test
        @DisplayName("resendVerificationEmail_unverifiedUser_shouldSendEmail")
        void resendVerificationEmail_unverifiedUser_shouldSendEmail() throws Exception {
            final User unverifiedUser = new User();
            unverifiedUser.setEmail("test@test.com");
            unverifiedUser.setIsVerified(false);

            when(userRepository.findByEmail("test@test.com")).thenReturn(Optional.of(unverifiedUser));

            final ResponseEntity<?> response = authService.resendVerificationEmail("test@test.com");

            assertEquals(HttpStatus.OK, response.getStatusCode());
            verify(userRepository).save(unverifiedUser);
            verify(emailService).sendVerificationEmail(eq("test@test.com"), anyString());
        }
    }

    // ==================== checkEmailVerificationStatus Tests ====================

    @Nested
    @DisplayName("checkEmailVerificationStatus tests")
    class CheckEmailVerificationStatusTests {

        @Test
        @DisplayName("checkEmailVerificationStatus_userNotFound_shouldReturnFalse")
        void checkEmailVerificationStatus_userNotFound_shouldReturnFalse() throws Exception {
            when(userRepository.findByEmail("unknown@test.com")).thenReturn(Optional.empty());

            final ResponseEntity<?> response = authService.checkEmailVerificationStatus("unknown@test.com");

            assertEquals(HttpStatus.OK, response.getStatusCode());
            @SuppressWarnings("unchecked") final Map<String, Object> body = (Map<String, Object>) response.getBody();
            assertNotNull(body);
            assertEquals(false, body.get("verified"));
        }

        @Test
        @DisplayName("checkEmailVerificationStatus_verifiedUser_shouldReturnTrue")
        void checkEmailVerificationStatus_verifiedUser_shouldReturnTrue() throws Exception {
            final User verifiedUser = new User();
            verifiedUser.setEmail("test@test.com");
            verifiedUser.setIsVerified(true);

            when(userRepository.findByEmail("test@test.com")).thenReturn(Optional.of(verifiedUser));

            final ResponseEntity<?> response = authService.checkEmailVerificationStatus("test@test.com");

            assertEquals(HttpStatus.OK, response.getStatusCode());
            @SuppressWarnings("unchecked") final Map<String, Object> body = (Map<String, Object>) response.getBody();
            assertNotNull(body);
            assertEquals(true, body.get("verified"));
        }

        @Test
        @DisplayName("checkEmailVerificationStatus_unverifiedUser_shouldReturnFalse")
        void checkEmailVerificationStatus_unverifiedUser_shouldReturnFalse() throws Exception {
            final User unverifiedUser = new User();
            unverifiedUser.setEmail("test@test.com");
            unverifiedUser.setIsVerified(false);

            when(userRepository.findByEmail("test@test.com")).thenReturn(Optional.of(unverifiedUser));

            final ResponseEntity<?> response = authService.checkEmailVerificationStatus("test@test.com");

            assertEquals(HttpStatus.OK, response.getStatusCode());
            @SuppressWarnings("unchecked") final Map<String, Object> body = (Map<String, Object>) response.getBody();
            assertNotNull(body);
            assertEquals(false, body.get("verified"));
        }
    }

    // ==================== loginV2 Tests ====================

    @Nested
    @DisplayName("loginV2 tests")
    class LoginV2Tests {

        @Test
        @DisplayName("loginV2_patientWithRole_shouldReturnLoginResponse")
        void loginV2_patientWithRole_shouldReturnLoginResponse() throws Exception {
            final LoginRequest req = new LoginRequest();
            req.setEmail("test@test.com");
            req.setPassword("password");
            req.setRole("PATIENT");

            final Patient patient = Patient.builder()
                    .id(10L)
                    .firstName("John")
                    .lastName("Doe")
                    .user(testUser)
                    .build();

            when(users.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(patients.findByUserId(1L)).thenReturn(Optional.of(patient));
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginV2(req, httpServletResponse);

            assertNotNull(response);
            assertEquals(1L, response.id());
            assertEquals("test@test.com", response.email());
            assertEquals(Role.PATIENT, response.role());
            assertEquals("jwt-token", response.token());
            assertEquals(10L, response.patientId());
            assertEquals("John Doe", response.name());
            verify(gamificationService).unlockAchievement(1L, "First Login", 50);
        }

        @Test
        @DisplayName("loginV2_caregiverWithRole_shouldReturnLoginResponse")
        void loginV2_caregiverWithRole_shouldReturnLoginResponse() throws Exception {
            final User caregiverUser = new User();
            caregiverUser.setId(2L);
            caregiverUser.setEmail("caregiver@test.com");
            caregiverUser.setPasswordHash("encodedPassword");
            caregiverUser.setRole(Role.CAREGIVER);
            caregiverUser.setIsVerified(true);
            caregiverUser.setStatus("ACTIVE");
            caregiverUser.setLoginStreak(0);

            final LoginRequest req = new LoginRequest();
            req.setEmail("caregiver@test.com");
            req.setPassword("password");
            req.setRole("CAREGIVER");

            final Caregiver caregiver = Caregiver.builder()
                    .id(20L)
                    .firstName("Jane")
                    .lastName("Smith")
                    .user(caregiverUser)
                    .build();

            when(users.findByEmailAndRole("caregiver@test.com", Role.CAREGIVER))
                    .thenReturn(Optional.of(caregiverUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(caregivers.findByUserId(2L)).thenReturn(Optional.of(caregiver));
            when(jwt.createToken("caregiver@test.com", Role.CAREGIVER)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginV2(req, httpServletResponse);

            assertNotNull(response);
            assertEquals(20L, response.caregiverId());
            assertEquals("Jane Smith", response.name());
        }

        @Test
        @DisplayName("loginV2_familyMember_shouldReturnLoginResponse")
        void loginV2_familyMember_shouldReturnLoginResponse() throws Exception {
            final User fmUser = new User();
            fmUser.setId(3L);
            fmUser.setEmail("family@test.com");
            fmUser.setPasswordHash("encodedPassword");
            fmUser.setRole(Role.FAMILY_MEMBER);
            fmUser.setIsVerified(true);
            fmUser.setStatus("ACTIVE");
            fmUser.setLoginStreak(0);

            final LoginRequest req = new LoginRequest();
            req.setEmail("family@test.com");
            req.setPassword("password");
            req.setRole("FAMILY_MEMBER");

            final FamilyMember fm = FamilyMember.builder()
                    .id(30L)
                    .firstName("Bob")
                    .lastName("Family")
                    .user(fmUser)
                    .build();

            when(users.findByEmailAndRole("family@test.com", Role.FAMILY_MEMBER))
                    .thenReturn(Optional.of(fmUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(familyMembers.findByUser(fmUser)).thenReturn(Optional.of(fm));
            when(jwt.createToken("family@test.com", Role.FAMILY_MEMBER)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginV2(req, httpServletResponse);

            assertNotNull(response);
            assertEquals("Bob Family", response.name());
            assertEquals(30L, response.caregiverId());
        }

        @Test
        @DisplayName("loginV2_admin_shouldReturnLoginResponse")
        void loginV2_admin_shouldReturnLoginResponse() throws Exception {
            final User adminUser = new User();
            adminUser.setId(4L);
            adminUser.setEmail("admin@test.com");
            adminUser.setPasswordHash("encodedPassword");
            adminUser.setRole(Role.ADMIN);
            adminUser.setIsVerified(true);
            adminUser.setStatus("ACTIVE");
            adminUser.setName("Admin User");
            adminUser.setLoginStreak(0);

            final LoginRequest req = new LoginRequest();
            req.setEmail("admin@test.com");
            req.setPassword("password");
            req.setRole("ADMIN");

            when(users.findByEmailAndRole("admin@test.com", Role.ADMIN))
                    .thenReturn(Optional.of(adminUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(jwt.createToken("admin@test.com", Role.ADMIN)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginV2(req, httpServletResponse);

            assertNotNull(response);
            assertEquals("Admin User", response.name());
        }

        @Test
        @DisplayName("loginV2_noRoleProvided_shouldFallbackToFindByEmail")
        void loginV2_noRoleProvided_shouldFallbackToFindByEmail() throws Exception {
            final LoginRequest req = new LoginRequest();
            req.setEmail("test@test.com");
            req.setPassword("password");
            req.setRole(null);

            when(users.findByEmail("test@test.com")).thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(patients.findByUserId(1L)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginV2(req, httpServletResponse);

            assertNotNull(response);
            assertEquals("test@test.com", response.email());
        }

        @Test
        @DisplayName("loginV2_emptyRoleProvided_shouldFallbackToFindByEmail")
        void loginV2_emptyRoleProvided_shouldFallbackToFindByEmail() throws Exception {
            final LoginRequest req = new LoginRequest();
            req.setEmail("test@test.com");
            req.setPassword("password");
            req.setRole("  ");

            when(users.findByEmail("test@test.com")).thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(patients.findByUserId(1L)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginV2(req, httpServletResponse);

            assertNotNull(response);
        }

        @Test
        @DisplayName("loginV2_invalidRole_shouldThrowAuthenticationException")
        void loginV2_invalidRole_shouldThrowAuthenticationException() throws Exception {
            final LoginRequest req = new LoginRequest();
            req.setEmail("test@test.com");
            req.setPassword("password");
            req.setRole("INVALID_ROLE");

            assertThrows(AuthenticationException.class, () -> authService.loginV2(req, httpServletResponse));
        }

        @Test
        @DisplayName("loginV2_wrongPassword_shouldThrowAuthenticationException")
        void loginV2_wrongPassword_shouldThrowAuthenticationException() throws Exception {
            final LoginRequest req = new LoginRequest();
            req.setEmail("test@test.com");
            req.setPassword("wrongPassword");
            req.setRole("PATIENT");

            when(users.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("wrongPassword", "encodedPassword")).thenReturn(false);

            assertThrows(AuthenticationException.class, () -> authService.loginV2(req, httpServletResponse));
        }

        @Test
        @DisplayName("loginV2_suspendedAccount_shouldThrowAuthenticationException")
        void loginV2_suspendedAccount_shouldThrowAuthenticationException() throws Exception {
            final User suspendedUser = new User();
            suspendedUser.setId(1L);
            suspendedUser.setEmail("test@test.com");
            suspendedUser.setPasswordHash("encodedPassword");
            suspendedUser.setRole(Role.PATIENT);
            suspendedUser.setStatus("SUSPENDED");

            final LoginRequest req = new LoginRequest();
            req.setEmail("test@test.com");
            req.setPassword("password");
            req.setRole("PATIENT");

            when(users.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(suspendedUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);

            assertThrows(AuthenticationException.class, () -> authService.loginV2(req, httpServletResponse));
        }

        @Test
        @DisplayName("loginV2_userNotFound_shouldThrowAuthenticationException")
        void loginV2_userNotFound_shouldThrowAuthenticationException() throws Exception {
            final LoginRequest req = new LoginRequest();
            req.setEmail("unknown@test.com");
            req.setPassword("password");
            req.setRole("PATIENT");

            when(users.findByEmailAndRole("unknown@test.com", Role.PATIENT))
                    .thenReturn(Optional.empty());

            assertThrows(AuthenticationException.class, () -> authService.loginV2(req, httpServletResponse));
        }

        @Test
        @DisplayName("loginV2_consecutiveDay_shouldIncrementLoginStreak")
        void loginV2_consecutiveDay_shouldIncrementLoginStreak() throws Exception {
            testUser.setLastLoginDate(LocalDate.now().minusDays(1));
            testUser.setLoginStreak(4);

            final LoginRequest req = new LoginRequest();
            req.setEmail("test@test.com");
            req.setPassword("password");
            req.setRole("PATIENT");

            when(users.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(patients.findByUserId(1L)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            authService.loginV2(req, httpServletResponse);

            assertEquals(5, testUser.getLoginStreak());
            verify(gamificationService).unlockAchievement(1L, "5-Day Streak", 100);
        }

        @Test
        @DisplayName("loginV2_nonConsecutiveDay_shouldResetLoginStreak")
        void loginV2_nonConsecutiveDay_shouldResetLoginStreak() throws Exception {
            testUser.setLastLoginDate(LocalDate.now().minusDays(3));
            testUser.setLoginStreak(4);

            final LoginRequest req = new LoginRequest();
            req.setEmail("test@test.com");
            req.setPassword("password");
            req.setRole("PATIENT");

            when(users.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(patients.findByUserId(1L)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            authService.loginV2(req, httpServletResponse);

            assertEquals(1, testUser.getLoginStreak());
        }

        @Test
        @DisplayName("loginV2_nullLastLogin_shouldResetLoginStreak")
        void loginV2_nullLastLogin_shouldResetLoginStreak() throws Exception {
            testUser.setLastLoginDate(null);
            testUser.setLoginStreak(null);

            final LoginRequest req = new LoginRequest();
            req.setEmail("test@test.com");
            req.setPassword("password");
            req.setRole("PATIENT");

            when(users.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(patients.findByUserId(1L)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            authService.loginV2(req, httpServletResponse);

            assertEquals(1, testUser.getLoginStreak());
        }

        @Test
        @DisplayName("loginV2_patientNotFound_shouldReturnNullPatientId")
        void loginV2_patientNotFound_shouldReturnNullPatientId() throws Exception {
            final LoginRequest req = new LoginRequest();
            req.setEmail("test@test.com");
            req.setPassword("password");
            req.setRole("PATIENT");

            when(users.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(patients.findByUserId(1L)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginV2(req, httpServletResponse);

            assertNull(response.patientId());
            assertNull(response.name());
        }

        @Test
        @DisplayName("loginV2_caregiverNotFound_shouldReturnNullCaregiverId")
        void loginV2_caregiverNotFound_shouldReturnNullCaregiverId() throws Exception {
            final User caregiverUser = new User();
            caregiverUser.setId(2L);
            caregiverUser.setEmail("caregiver@test.com");
            caregiverUser.setPasswordHash("encodedPassword");
            caregiverUser.setRole(Role.CAREGIVER);
            caregiverUser.setIsVerified(true);
            caregiverUser.setStatus("ACTIVE");
            caregiverUser.setLoginStreak(0);

            final LoginRequest req = new LoginRequest();
            req.setEmail("caregiver@test.com");
            req.setPassword("password");
            req.setRole("CAREGIVER");

            when(users.findByEmailAndRole("caregiver@test.com", Role.CAREGIVER))
                    .thenReturn(Optional.of(caregiverUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(caregivers.findByUserId(2L)).thenReturn(Optional.empty());
            when(jwt.createToken("caregiver@test.com", Role.CAREGIVER)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginV2(req, httpServletResponse);

            assertNull(response.caregiverId());
            assertNull(response.name());
        }

        @Test
        @DisplayName("loginV2_familyMemberNotFound_shouldReturnNullName")
        void loginV2_familyMemberNotFound_shouldReturnNullName() throws Exception {
            final User fmUser = new User();
            fmUser.setId(3L);
            fmUser.setEmail("family@test.com");
            fmUser.setPasswordHash("encodedPassword");
            fmUser.setRole(Role.FAMILY_MEMBER);
            fmUser.setIsVerified(true);
            fmUser.setStatus("ACTIVE");
            fmUser.setLoginStreak(0);

            final LoginRequest req = new LoginRequest();
            req.setEmail("family@test.com");
            req.setPassword("password");
            req.setRole("FAMILY_MEMBER");

            when(users.findByEmailAndRole("family@test.com", Role.FAMILY_MEMBER))
                    .thenReturn(Optional.of(fmUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(familyMembers.findByUser(fmUser)).thenReturn(Optional.empty());
            when(jwt.createToken("family@test.com", Role.FAMILY_MEMBER)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginV2(req, httpServletResponse);

            assertNull(response.caregiverId());
            assertNull(response.name());
        }
    }

    // ==================== loginOAuth Tests ====================

    @Nested
    @DisplayName("loginOAuth tests")
    class LoginOAuthTests {

        @Test
        @DisplayName("loginOAuth_patientUser_shouldReturnLoginResponse")
        void loginOAuth_patientUser_shouldReturnLoginResponse() throws Exception {
            final Patient patient = Patient.builder()
                    .id(10L)
                    .firstName("John")
                    .lastName("Doe")
                    .user(testUser)
                    .build();

            when(users.findByEmail("test@test.com")).thenReturn(Optional.of(testUser));
            when(patients.findByUser(testUser)).thenReturn(Optional.of(patient));
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("oauth-jwt-token");

            final LoginResponse response = authService.loginOAuth("test@test.com", httpServletResponse);

            assertNotNull(response);
            assertEquals(1L, response.id());
            assertEquals("oauth-jwt-token", response.token());
            assertEquals(10L, response.patientId());
            assertEquals("John Doe", response.name());
        }

        @Test
        @DisplayName("loginOAuth_caregiverUser_shouldReturnLoginResponse")
        void loginOAuth_caregiverUser_shouldReturnLoginResponse() throws Exception {
            final User caregiverUser = new User();
            caregiverUser.setId(2L);
            caregiverUser.setEmail("caregiver@test.com");
            caregiverUser.setRole(Role.CAREGIVER);
            caregiverUser.setStatus("ACTIVE");
            caregiverUser.setLoginStreak(0);

            final Caregiver caregiver = Caregiver.builder()
                    .id(20L)
                    .firstName("Jane")
                    .lastName("Smith")
                    .user(caregiverUser)
                    .build();

            when(users.findByEmail("caregiver@test.com")).thenReturn(Optional.of(caregiverUser));
            when(caregivers.findByUser(caregiverUser)).thenReturn(Optional.of(caregiver));
            when(jwt.createToken("caregiver@test.com", Role.CAREGIVER)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginOAuth("caregiver@test.com", httpServletResponse);

            assertNotNull(response);
            assertEquals(20L, response.caregiverId());
        }

        @Test
        @DisplayName("loginOAuth_familyMemberUser_shouldReturnLoginResponse")
        void loginOAuth_familyMemberUser_shouldReturnLoginResponse() throws Exception {
            final User fmUser = new User();
            fmUser.setId(3L);
            fmUser.setEmail("family@test.com");
            fmUser.setRole(Role.FAMILY_MEMBER);
            fmUser.setStatus("ACTIVE");
            fmUser.setLoginStreak(0);

            final FamilyMember fm = FamilyMember.builder()
                    .id(30L)
                    .firstName("Bob")
                    .lastName("Family")
                    .user(fmUser)
                    .build();

            when(users.findByEmail("family@test.com")).thenReturn(Optional.of(fmUser));
            when(familyMembers.findByUser(fmUser)).thenReturn(Optional.of(fm));
            when(jwt.createToken("family@test.com", Role.FAMILY_MEMBER)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginOAuth("family@test.com", httpServletResponse);

            assertNotNull(response);
            assertEquals("Bob Family", response.name());
            assertEquals(30L, response.caregiverId());
        }

        @Test
        @DisplayName("loginOAuth_adminUser_shouldReturnLoginResponse")
        void loginOAuth_adminUser_shouldReturnLoginResponse() throws Exception {
            final User adminUser = new User();
            adminUser.setId(4L);
            adminUser.setEmail("admin@test.com");
            adminUser.setRole(Role.ADMIN);
            adminUser.setStatus("ACTIVE");
            adminUser.setName("Admin User");
            adminUser.setLoginStreak(0);

            when(users.findByEmail("admin@test.com")).thenReturn(Optional.of(adminUser));
            when(jwt.createToken("admin@test.com", Role.ADMIN)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginOAuth("admin@test.com", httpServletResponse);

            assertNotNull(response);
            assertEquals("Admin User", response.name());
        }

        @Test
        @DisplayName("loginOAuth_userNotFound_shouldThrowAuthenticationException")
        void loginOAuth_userNotFound_shouldThrowAuthenticationException() throws Exception {
            when(users.findByEmail("unknown@test.com")).thenReturn(Optional.empty());

            assertThrows(AuthenticationException.class,
                    () -> authService.loginOAuth("unknown@test.com", httpServletResponse));
        }

        @Test
        @DisplayName("loginOAuth_suspendedUser_shouldThrowAuthenticationException")
        void loginOAuth_suspendedUser_shouldThrowAuthenticationException() throws Exception {
            final User suspendedUser = new User();
            suspendedUser.setId(1L);
            suspendedUser.setEmail("test@test.com");
            suspendedUser.setRole(Role.PATIENT);
            suspendedUser.setStatus("SUSPENDED");

            when(users.findByEmail("test@test.com")).thenReturn(Optional.of(suspendedUser));

            assertThrows(AuthenticationException.class,
                    () -> authService.loginOAuth("test@test.com", httpServletResponse));
        }

        @Test
        @DisplayName("loginOAuth_patientNotFound_shouldReturnNullPatientIdAndName")
        void loginOAuth_patientNotFound_shouldReturnNullPatientIdAndName() throws Exception {
            when(users.findByEmail("test@test.com")).thenReturn(Optional.of(testUser));
            when(patients.findByUser(testUser)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("oauth-jwt-token");

            final LoginResponse response = authService.loginOAuth("test@test.com", httpServletResponse);

            assertNotNull(response);
            assertNull(response.patientId());
            assertNull(response.name());
        }

        @Test
        @DisplayName("loginOAuth_caregiverNotFound_shouldReturnNullCaregiverIdAndName")
        void loginOAuth_caregiverNotFound_shouldReturnNullCaregiverIdAndName() throws Exception {
            final User caregiverUser = new User();
            caregiverUser.setId(2L);
            caregiverUser.setEmail("caregiver@test.com");
            caregiverUser.setRole(Role.CAREGIVER);
            caregiverUser.setStatus("ACTIVE");
            caregiverUser.setLoginStreak(0);

            when(users.findByEmail("caregiver@test.com")).thenReturn(Optional.of(caregiverUser));
            when(caregivers.findByUser(caregiverUser)).thenReturn(Optional.empty());
            when(jwt.createToken("caregiver@test.com", Role.CAREGIVER)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginOAuth("caregiver@test.com", httpServletResponse);

            assertNotNull(response);
            assertNull(response.caregiverId());
            assertNull(response.name());
        }

        @Test
        @DisplayName("loginOAuth_familyMemberNotFound_shouldReturnNullCaregiverIdAndName")
        void loginOAuth_familyMemberNotFound_shouldReturnNullCaregiverIdAndName() throws Exception {
            final User fmUser = new User();
            fmUser.setId(3L);
            fmUser.setEmail("family@test.com");
            fmUser.setRole(Role.FAMILY_MEMBER);
            fmUser.setStatus("ACTIVE");
            fmUser.setLoginStreak(0);

            when(users.findByEmail("family@test.com")).thenReturn(Optional.of(fmUser));
            when(familyMembers.findByUser(fmUser)).thenReturn(Optional.empty());
            when(jwt.createToken("family@test.com", Role.FAMILY_MEMBER)).thenReturn("jwt-token");

            final LoginResponse response = authService.loginOAuth("family@test.com", httpServletResponse);

            assertNotNull(response);
            assertNull(response.caregiverId());
            assertNull(response.name());
        }

        @Test
        @DisplayName("loginOAuth_consecutiveDay_shouldIncrementStreak")
        void loginOAuth_consecutiveDay_shouldIncrementStreak() throws Exception {
            testUser.setLastLoginDate(LocalDate.now().minusDays(1));
            testUser.setLoginStreak(4);

            when(users.findByEmail("test@test.com")).thenReturn(Optional.of(testUser));
            when(patients.findByUser(testUser)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            authService.loginOAuth("test@test.com", httpServletResponse);

            assertEquals(5, testUser.getLoginStreak());
            verify(gamificationService).unlockAchievement(1L, "5-Day Streak", 100);
        }

        @Test
        @DisplayName("loginOAuth_nonConsecutiveDay_shouldResetStreak")
        void loginOAuth_nonConsecutiveDay_shouldResetStreak() throws Exception {
            testUser.setLastLoginDate(LocalDate.now().minusDays(3));
            testUser.setLoginStreak(4);

            when(users.findByEmail("test@test.com")).thenReturn(Optional.of(testUser));
            when(patients.findByUser(testUser)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            authService.loginOAuth("test@test.com", httpServletResponse);

            assertEquals(1, testUser.getLoginStreak());
        }

        @Test
        @DisplayName("loginOAuth_nullStreakAndLastLogin_shouldResetStreak")
        void loginOAuth_nullStreakAndLastLogin_shouldResetStreak() throws Exception {
            testUser.setLastLoginDate(null);
            testUser.setLoginStreak(null);

            when(users.findByEmail("test@test.com")).thenReturn(Optional.of(testUser));
            when(patients.findByUser(testUser)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            authService.loginOAuth("test@test.com", httpServletResponse);

            assertEquals(1, testUser.getLoginStreak());
            assertEquals(LocalDate.now(), testUser.getLastLoginDate());
        }

        @Test
        @DisplayName("loginOAuth_sameDay_shouldResetStreakToOne")
        void loginOAuth_sameDay_shouldResetStreakToOne() throws Exception {
            testUser.setLastLoginDate(LocalDate.now());
            testUser.setLoginStreak(3);

            when(users.findByEmail("test@test.com")).thenReturn(Optional.of(testUser));
            when(patients.findByUser(testUser)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            authService.loginOAuth("test@test.com", httpServletResponse);

            assertEquals(1, testUser.getLoginStreak());
        }

        @Test
        @DisplayName("loginOAuth_gamificationUnlockCalled")
        void loginOAuth_gamificationUnlockCalled() throws Exception {
            when(users.findByEmail("test@test.com")).thenReturn(Optional.of(testUser));
            when(patients.findByUser(testUser)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            authService.loginOAuth("test@test.com", httpServletResponse);

            verify(gamificationService).unlockAchievement(1L, "First Login", 50);
            verify(userRepository).save(testUser);
        }
    }

    // ==================== changePassword Tests ====================

    @Nested
    @DisplayName("changePassword tests")
    class ChangePasswordTests {

        @Test
        @DisplayName("changePassword_validCurrentPassword_shouldChangePassword")
        void changePassword_validCurrentPassword_shouldChangePassword() throws Exception {
            when(users.findByEmail("test@test.com")).thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("currentPwd", "encodedPassword")).thenReturn(true);
            when(passwordEncoder.encode("newPwd")).thenReturn("newEncodedPwd");

            final ResponseEntity<?> response = authService.changePassword("test@test.com", "currentPwd", "newPwd");

            assertEquals(HttpStatus.OK, response.getStatusCode());
            verify(userRepository).save(testUser);
        }

        @Test
        @DisplayName("changePassword_wrongCurrentPassword_shouldReturnBadRequest")
        void changePassword_wrongCurrentPassword_shouldReturnBadRequest() throws Exception {
            when(users.findByEmail("test@test.com")).thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("wrongPwd", "encodedPassword")).thenReturn(false);

            final ResponseEntity<?> response = authService.changePassword("test@test.com", "wrongPwd", "newPwd");

            assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        }

        @Test
        @DisplayName("changePassword_userNotFound_shouldReturnInternalServerError")
        void changePassword_userNotFound_shouldReturnInternalServerError() throws Exception {
            when(users.findByEmail("unknown@test.com"))
                    .thenThrow(new AuthenticationException("User not found"));

            final ResponseEntity<?> response = authService.changePassword("unknown@test.com", "pwd", "newPwd");

            assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());
        }
    }

    // ==================== validateGoogleToken Tests ====================

    @Nested
    @DisplayName("validateGoogleToken tests")
    class ValidateGoogleTokenTests {

        @Test
        @DisplayName("validateGoogleToken_anyToken_shouldThrowUnsupportedOperationException")
        void validateGoogleToken_anyToken_shouldThrowUnsupportedOperationException() throws Exception {
            assertThrows(UnsupportedOperationException.class,
                    () -> authService.validateGoogleToken("some-token"));
        }
    }

    // ==================== setupPassword Tests ====================

    @Nested
    @DisplayName("setupPassword tests")
    class SetupPasswordTests {

        @Test
        @DisplayName("setupPassword_validToken_shouldSetPasswordAndVerify")
        void setupPassword_validToken_shouldSetPasswordAndVerify() throws Exception {
            final User user = new User();
            user.setEmail("test@test.com");
            user.setIsVerified(false);
            user.setVerificationToken("setup-token");

            when(userRepository.findByVerificationToken("setup-token")).thenReturn(Optional.of(user));
            when(passwordEncoder.encode("newPassword")).thenReturn("encodedNewPassword");

            final ResponseEntity<?> response = authService.setupPassword("setup-token", "newPassword");

            assertEquals(HttpStatus.OK, response.getStatusCode());
            assertTrue(user.getIsVerified());
            assertNull(user.getVerificationToken());
            assertEquals("encodedNewPassword", user.getPasswordHash());
            verify(userRepository).save(user);
        }

        @Test
        @DisplayName("setupPassword_invalidToken_shouldReturnBadRequest")
        void setupPassword_invalidToken_shouldReturnBadRequest() throws Exception {
            when(userRepository.findByVerificationToken("invalid-token")).thenReturn(Optional.empty());

            final ResponseEntity<?> response = authService.setupPassword("invalid-token", "newPassword");

            assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        }
    }

    // ==================== buildGoogleOAuthUrl Tests ====================

    @Nested
    @DisplayName("buildGoogleOAuthUrl tests")
    class BuildGoogleOAuthUrlTests {

        @Test
        @DisplayName("buildGoogleOAuthUrl_shouldReturnFormattedUrl")
        void buildGoogleOAuthUrl_shouldReturnFormattedUrl() throws Exception {
            final String url = authService.buildGoogleOAuthUrl();

            assertNotNull(url);
            assertTrue(url.startsWith("https://accounts.google.com/o/oauth2/v2/auth?"));
            assertTrue(url.contains("client_id=test-client-id"));
            assertTrue(url.contains("response_type=code"));
            assertTrue(url.contains("scope=openid%20email%20profile"));
        }
    }

    // ==================== processGoogleOAuth Tests ====================

    @Nested
    @DisplayName("processGoogleOAuth tests")
    class ProcessGoogleOAuthTests {

        @Test
        @DisplayName("processGoogleOAuth_validCodeAndEmail_shouldReturnLoginResponse")
        void processGoogleOAuth_validCodeAndEmail_shouldReturnLoginResponse() throws Exception {
            // Set token URI to valid endpoint and user info URI to valid endpoint
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/valid");
            ReflectionTestUtils.setField(authService, "googleUserInfoUri",
                    "http://localhost:" + mockServerPort + "/userinfo/valid");

            final User oauthUser = new User();
            oauthUser.setId(100L);
            oauthUser.setEmail("oauth@test.com");
            oauthUser.setRole(Role.PATIENT);
            oauthUser.setStatus("ACTIVE");
            oauthUser.setLoginStreak(0);

            when(users.findByEmail("oauth@test.com")).thenReturn(Optional.of(oauthUser));
            when(patients.findByUser(oauthUser)).thenReturn(Optional.empty());
            when(jwt.createToken("oauth@test.com", Role.PATIENT)).thenReturn("oauth-jwt");

            final LoginResponse response = authService.processGoogleOAuth("valid-code", httpServletResponse);

            assertNotNull(response);
            assertEquals("oauth@test.com", response.email());
        }

        @Test
        @DisplayName("processGoogleOAuth_nullEmail_shouldThrowOAuthException")
        void processGoogleOAuth_nullEmail_shouldThrowOAuthException() throws Exception {
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/valid");
            ReflectionTestUtils.setField(authService, "googleUserInfoUri",
                    "http://localhost:" + mockServerPort + "/userinfo/no-email");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> authService.processGoogleOAuth("code", httpServletResponse));
            assertEquals("invalid_response", ex.getErrorType());
            assertTrue(ex.getMessage().contains("Unable to retrieve email"));
        }

        @Test
        @DisplayName("processGoogleOAuth_emptyEmail_shouldThrowOAuthException")
        void processGoogleOAuth_emptyEmail_shouldThrowOAuthException() throws Exception {
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/valid");
            ReflectionTestUtils.setField(authService, "googleUserInfoUri",
                    "http://localhost:" + mockServerPort + "/userinfo/empty-email");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> authService.processGoogleOAuth("code", httpServletResponse));
            assertEquals("invalid_response", ex.getErrorType());
        }

        @Test
        @DisplayName("processGoogleOAuth_oauthExceptionFromToken_shouldRethrow")
        void processGoogleOAuth_oauthExceptionFromToken_shouldRethrow() throws Exception {
            // Use a 400 invalid_grant endpoint which throws OAuthException from exchangeCodeForToken
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/400-invalid-grant");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> authService.processGoogleOAuth("code", httpServletResponse));
            assertEquals("invalid_grant", ex.getErrorType());
        }

        @Test
        @DisplayName("processGoogleOAuth_authenticationException_shouldWrapInOAuthException")
        void processGoogleOAuth_authenticationException_shouldWrapInOAuthException() throws Exception {
            // Valid token exchange + valid user info, but loginOAuth throws AuthenticationException
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/valid");
            ReflectionTestUtils.setField(authService, "googleUserInfoUri",
                    "http://localhost:" + mockServerPort + "/userinfo/valid");

            // oauth@test.com user not found triggers AuthenticationException from loginOAuth
            when(users.findByEmail("oauth@test.com")).thenReturn(Optional.empty());

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> authService.processGoogleOAuth("code", httpServletResponse));
            assertEquals("authentication_failed", ex.getErrorType());
        }

        @Test
        @DisplayName("processGoogleOAuth_genericException_shouldWrapInOAuthException")
        void processGoogleOAuth_genericException_shouldWrapInOAuthException() throws Exception {
            // Set token URI to a completely invalid URL to trigger a generic exception
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:1/nonexistent");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> authService.processGoogleOAuth("code", httpServletResponse));
            // The exchangeCodeForToken wraps the connection error as OAuthException("network_error")
            // Then processGoogleOAuth's catch(OAuthException) re-throws it
            assertNotNull(ex);
        }
    }

    // ==================== exchangeCodeForToken Tests (private method via reflection + mock server) ====================

    @Nested
    @DisplayName("exchangeCodeForToken tests")
    class ExchangeCodeForTokenTests {

        @Test
        @DisplayName("exchangeCodeForToken_validResponse_shouldReturnAccessToken")
        void exchangeCodeForToken_validResponse_shouldReturnAccessToken() throws Exception {
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/valid");

            final String result = ReflectionTestUtils.invokeMethod(authService, "exchangeCodeForToken", "test-code");
            assertEquals("fake-access-token", result);
        }

        @Test
        @DisplayName("exchangeCodeForToken_noAccessTokenInResponse_shouldThrowOAuthException")
        void exchangeCodeForToken_noAccessTokenInResponse_shouldThrowOAuthException() throws Exception {
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/no-access-token");

            // The AuthenticationException from inside the try block is caught by catch(Exception e)
            // which wraps it as OAuthException with "network_error"
            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "exchangeCodeForToken", "test-code"));
            assertEquals("network_error", ex.getErrorType());
        }

        @Test
        @DisplayName("exchangeCodeForToken_400InvalidGrant_shouldThrowOAuthException")
        void exchangeCodeForToken_400InvalidGrant_shouldThrowOAuthException() throws Exception {
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/400-invalid-grant");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "exchangeCodeForToken", "test-code"));
            assertEquals("invalid_grant", ex.getErrorType());
        }

        @Test
        @DisplayName("exchangeCodeForToken_400InvalidClient_shouldThrowOAuthException")
        void exchangeCodeForToken_400InvalidClient_shouldThrowOAuthException() throws Exception {
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/400-invalid-client");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "exchangeCodeForToken", "test-code"));
            assertEquals("invalid_client", ex.getErrorType());
        }

        @Test
        @DisplayName("exchangeCodeForToken_400InvalidRequest_shouldThrowOAuthException")
        void exchangeCodeForToken_400InvalidRequest_shouldThrowOAuthException() throws Exception {
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/400-invalid-request");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "exchangeCodeForToken", "test-code"));
            assertEquals("invalid_request", ex.getErrorType());
        }

        @Test
        @DisplayName("exchangeCodeForToken_400Generic_shouldThrowOAuthException")
        void exchangeCodeForToken_400Generic_shouldThrowOAuthException() throws Exception {
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/400-generic");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "exchangeCodeForToken", "test-code"));
            assertEquals("invalid_request", ex.getErrorType());
            assertTrue(ex.getMessage().contains("Bad request"));
        }

        @Test
        @DisplayName("exchangeCodeForToken_401_shouldThrowOAuthException")
        void exchangeCodeForToken_401_shouldThrowOAuthException() throws Exception {
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/401");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "exchangeCodeForToken", "test-code"));
            assertEquals("invalid_client", ex.getErrorType());
        }

        @Test
        @DisplayName("exchangeCodeForToken_500_shouldThrowOAuthException")
        void exchangeCodeForToken_500_shouldThrowOAuthException() throws Exception {
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/500");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "exchangeCodeForToken", "test-code"));
            assertEquals("network_error", ex.getErrorType());
        }

        @Test
        @DisplayName("exchangeCodeForToken_403_shouldThrowOAuthExceptionWithApiError")
        void exchangeCodeForToken_403_shouldThrowOAuthExceptionWithApiError() throws Exception {
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:" + mockServerPort + "/token/403");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "exchangeCodeForToken", "test-code"));
            assertEquals("api_error", ex.getErrorType());
        }

        @Test
        @DisplayName("exchangeCodeForToken_connectionRefused_shouldThrowOAuthExceptionNetworkError")
        void exchangeCodeForToken_connectionRefused_shouldThrowOAuthExceptionNetworkError() throws Exception {
            ReflectionTestUtils.setField(authService, "googleTokenUri",
                    "http://localhost:1/token");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "exchangeCodeForToken", "test-code"));
            assertEquals("network_error", ex.getErrorType());
        }
    }

    // ==================== getUserInfoFromGoogle Tests (private method via reflection + mock server) ====================

    @Nested
    @DisplayName("getUserInfoFromGoogle tests")
    class GetUserInfoFromGoogleTests {

        @Test
        @DisplayName("getUserInfoFromGoogle_validResponse_shouldReturnUserInfo")
        void getUserInfoFromGoogle_validResponse_shouldReturnUserInfo() throws Exception {
            ReflectionTestUtils.setField(authService, "googleUserInfoUri",
                    "http://localhost:" + mockServerPort + "/userinfo/valid");

            final Map<String, Object> result = ReflectionTestUtils.invokeMethod(
                    authService, "getUserInfoFromGoogle", "fake-token");

            assertNotNull(result);
            assertEquals("oauth@test.com", result.get("email"));
        }

        @Test
        @DisplayName("getUserInfoFromGoogle_401_shouldThrowOAuthExceptionInvalidToken")
        void getUserInfoFromGoogle_401_shouldThrowOAuthExceptionInvalidToken() throws Exception {
            ReflectionTestUtils.setField(authService, "googleUserInfoUri",
                    "http://localhost:" + mockServerPort + "/userinfo/401");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "getUserInfoFromGoogle", "fake-token"));
            assertEquals("invalid_token", ex.getErrorType());
        }

        @Test
        @DisplayName("getUserInfoFromGoogle_403_shouldThrowOAuthExceptionInvalidScope")
        void getUserInfoFromGoogle_403_shouldThrowOAuthExceptionInvalidScope() throws Exception {
            ReflectionTestUtils.setField(authService, "googleUserInfoUri",
                    "http://localhost:" + mockServerPort + "/userinfo/403");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "getUserInfoFromGoogle", "fake-token"));
            assertEquals("invalid_scope", ex.getErrorType());
        }

        @Test
        @DisplayName("getUserInfoFromGoogle_500_shouldThrowOAuthExceptionTemporarilyUnavailable")
        void getUserInfoFromGoogle_500_shouldThrowOAuthExceptionTemporarilyUnavailable() throws Exception {
            ReflectionTestUtils.setField(authService, "googleUserInfoUri",
                    "http://localhost:" + mockServerPort + "/userinfo/500");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "getUserInfoFromGoogle", "fake-token"));
            assertEquals("network_error", ex.getErrorType());
        }

        @Test
        @DisplayName("getUserInfoFromGoogle_404_shouldThrowOAuthExceptionApiError")
        void getUserInfoFromGoogle_404_shouldThrowOAuthExceptionApiError() throws Exception {
            ReflectionTestUtils.setField(authService, "googleUserInfoUri",
                    "http://localhost:" + mockServerPort + "/userinfo/404");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "getUserInfoFromGoogle", "fake-token"));
            assertEquals("api_error", ex.getErrorType());
        }

        @Test
        @DisplayName("getUserInfoFromGoogle_connectionRefused_shouldThrowOAuthExceptionNetworkError")
        void getUserInfoFromGoogle_connectionRefused_shouldThrowOAuthExceptionNetworkError() throws Exception {
            ReflectionTestUtils.setField(authService, "googleUserInfoUri",
                    "http://localhost:1/userinfo");

            final OAuthException ex = assertThrows(OAuthException.class,
                    () -> ReflectionTestUtils.invokeMethod(authService, "getUserInfoFromGoogle", "fake-token"));
            assertEquals("network_error", ex.getErrorType());
        }
    }

    // ==================== handleLoginStreak Tests (covered via loginV2) ====================

    @Nested
    @DisplayName("handleLoginStreak tests via loginV2")
    class HandleLoginStreakTests {

        @Test
        @DisplayName("handleLoginStreak_sameDay_shouldResetToOne")
        void handleLoginStreak_sameDay_shouldResetToOne() throws Exception {
            testUser.setLastLoginDate(LocalDate.now());
            testUser.setLoginStreak(3);

            final LoginRequest req = new LoginRequest();
            req.setEmail("test@test.com");
            req.setPassword("password");
            req.setRole("PATIENT");

            when(users.findByEmailAndRole("test@test.com", Role.PATIENT))
                    .thenReturn(Optional.of(testUser));
            when(passwordEncoder.matches("password", "encodedPassword")).thenReturn(true);
            when(patients.findByUserId(1L)).thenReturn(Optional.empty());
            when(jwt.createToken("test@test.com", Role.PATIENT)).thenReturn("jwt-token");

            authService.loginV2(req, httpServletResponse);

            assertEquals(1, testUser.getLoginStreak());
        }
    }
}
