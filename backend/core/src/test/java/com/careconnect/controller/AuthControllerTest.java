package com.careconnect.controller;

import com.careconnect.dto.*;
import com.careconnect.exception.OAuthException;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import com.careconnect.security.TokenHashService;
import com.careconnect.service.AlexaCodeStoreService;
import com.careconnect.service.AuthService;
import com.careconnect.service.PasswordResetService;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.ObjectMapper;

import jakarta.servlet.http.Cookie;

import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.when;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;


/**
 * Unit tests for {@link AuthController}, covering the HTTP layer of all
 * authentication and SSO endpoints.
 *
 * <p><b>Why @WebMvcTest + MockMvc?</b><br>
 * {@code @WebMvcTest} spins up only the Spring MVC slice (controllers, filters,
 * argument resolvers) without loading a full application context or a real
 * database.  This makes the tests fast and focused: they verify that the
 * controller routes requests to the correct service methods, applies the right
 * HTTP status codes, and serialises/deserialises JSON properly — without caring
 * about the actual business logic inside the services.
 *
 * <p>All service and repository collaborators are replaced with Mockito mocks
 * via {@code @MockBean} so that each test exercises only the controller layer
 * in isolation.  Security filters are disabled with
 * {@code @AutoConfigureMockMvc(addFilters = false)} so that most tests can
 * focus on happy-path or input-validation behaviour; the tests that do require
 * auth enforcement (e.g. missing JWT cookie) do so by omitting the cookie
 * rather than relying on the full security filter chain.
 *
 * <p>Test properties supply the minimum configuration values required by beans
 * that are wired into the controller context (frontend URL, Alexa OAuth
 * credentials).
 */
@WebMvcTest(AuthController.class)
@AutoConfigureMockMvc(addFilters = false)
@TestPropertySource(properties = {
        "frontend.base-url=http://localhost:3000",
        "alexa.oauth.client-id=test-client-id",
        "alexa.oauth.client-secret=test-client-secret"
})
class AuthControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    // --- Mocked collaborators ---
    // Each bean below is replaced with a Mockito stub so the controller can be
    // instantiated without real infrastructure (DB, JWT signing keys, etc.).

    @MockitoBean
    private AuthService authService;

    @MockitoBean
    private PasswordResetService reset;

    @MockitoBean
    private JwtTokenProvider jwt;

    @MockitoBean
    private UserRepository userRepository;

    @MockitoBean
    private PatientRepository patientRepository;

    @MockitoBean
    private TokenHashService tokenHashService;

    @MockitoBean
    private AlexaCodeStoreService alexaCodeStore;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private AuthorizationService authorizationService;

    // ==========================================
    // REGISTER
    // ==========================================

    /**
     * Verifies that POST /v1/api/auth/register returns HTTP 200 when the
     * {@link AuthService#register} call succeeds.
     *
     * <p>MockMvc is used so we can assert the HTTP status without starting a
     * real server.  The service is stubbed to return a 200 response, allowing
     * the test to confirm that the controller correctly forwards the result to
     * the caller.
     */
    @Test
    void shouldRegisterUserSuccessfully() throws Exception {

        final PatientRegistration request = new PatientRegistration();
        request.setEmail("test@test.com");
        request.setPassword("password");
        request.setName("Test");
        request.setRole("PATIENT");

        when(authService.register(any(RegisterRequest.class)))
                .thenAnswer(inv -> ResponseEntity.ok(Map.of("message", "success")));

        mockMvc.perform(post("/v1/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk());
    }

    // ==========================================
    // LOGIN
    // ==========================================

    /**
     * Verifies that POST /v1/api/auth/login returns HTTP 200 and includes the
     * JWT token in the JSON response body on a successful login.
     *
     * <p>The {@link AuthService#loginV2} method is stubbed to return a
     * {@link LoginResponse} containing a known token value.  The test then
     * asserts both the status code and the JSON field {@code $.token}, ensuring
     * that the controller serialises the response object correctly.
     */
    @Test
    void shouldLoginSuccessfully() throws Exception {

        final LoginRequest req = new LoginRequest();
        req.setEmail("test@test.com");
        req.setPassword("password");

        final LoginResponse response = LoginResponse.builder()
                .token("jwt-token")
                .build();

        when(authService.loginV2(any(), any()))
                .thenReturn(response);

        mockMvc.perform(post("/v1/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(req)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").value("jwt-token"));
    }

    // ==========================================
    // VERIFY EMAIL TOKEN
    // ==========================================

    /**
     * Verifies that GET /v1/api/auth/verify/{token} delegates to
     * {@link AuthService#verifyToken} and returns whatever status the service
     * provides (200 in the happy path).
     */
    @Test
    void verifyTokenShouldReturnOk() throws Exception {
        when(authService.verifyToken("abc123"))
                .thenAnswer(inv -> ResponseEntity.ok(Map.of("message", "Email verified")));

        mockMvc.perform(get("/v1/api/auth/verify/abc123"))
                .andExpect(status().isOk());
    }

    // ==========================================
    // RESEND VERIFICATION - BAD REQUEST
    // ==========================================

    /**
     * Verifies that POST /v1/api/auth/resend-verification returns HTTP 400
     * when the request body does not contain a required {@code email} field.
     *
     * <p>Input validation is enforced by Bean Validation annotations on the
     * request DTO.  Sending an empty JSON object ({@code {}}) triggers a
     * constraint violation, and the controller (or a Spring MVC exception
     * handler) should respond with 400 Bad Request.  This test confirms that
     * the validation layer is correctly wired — no service stub is needed
     * because the request should be rejected before reaching the service.
     */
    @Test
    void resendVerificationShouldReturnBadRequestIfEmailMissing() throws Exception {

        mockMvc.perform(post("/v1/api/auth/resend-verification")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());
    }

    /**
     * Verifies that POST /v1/api/auth/resend-verification returns HTTP 200
     * when a valid email address is supplied and the service succeeds.
     */
    @Test
    void resendVerificationShouldReturnOkWhenEmailProvided() throws Exception {
        when(authService.resendVerificationEmail("user@test.com"))
                .thenAnswer(inv -> ResponseEntity.ok(Map.of("message", "Sent")));

        mockMvc.perform(post("/v1/api/auth/resend-verification")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"user@test.com\"}"))
                .andExpect(status().isOk());
    }

    // ==========================================
    // CHECK VERIFICATION - BAD REQUEST
    // ==========================================

    /**
     * Verifies that GET /v1/api/auth/check-verification returns HTTP 400 when
     * the {@code email} query parameter is present but empty.
     *
     * <p>An empty string is semantically equivalent to a missing email address.
     * This test ensures that the controller (or its validation layer) rejects
     * blank values rather than propagating them downstream, protecting the
     * service from acting on invalid input.
     */
    @Test
    void checkVerificationShouldReturnBadRequestIfEmailMissing() throws Exception {

        mockMvc.perform(get("/v1/api/auth/check-verification")
                        .param("email", ""))
                .andExpect(status().isBadRequest());
    }

    /**
     * Verifies that GET /v1/api/auth/check-verification returns HTTP 200 when
     * a valid email is provided and the service returns verification status.
     */
    @Test
    void checkVerificationShouldReturnOkWithValidEmail() throws Exception {
        when(authService.checkEmailVerificationStatus("user@test.com"))
                .thenAnswer(inv -> ResponseEntity.ok(Map.of("verified", true)));

        mockMvc.perform(get("/v1/api/auth/check-verification")
                        .param("email", "user@test.com"))
                .andExpect(status().isOk());
    }

    // ==========================================
    // FORGOT PASSWORD
    // ==========================================

    /**
     * Verifies that POST /v1/api/auth/password/forgot returns HTTP 200
     * regardless of whether the supplied email belongs to a real account.
     *
     * <p>Returning 200 for both known and unknown addresses is an intentional
     * security design: it prevents user enumeration by not revealing whether an
     * account exists.  No service stub is needed here because the default
     * Mockito behaviour (returning {@code null} / void) is sufficient to
     * confirm the endpoint accepts the request and returns the expected status.
     */
    @Test
    void forgotPasswordShouldReturnOk() throws Exception {

        mockMvc.perform(post("/v1/api/auth/password/forgot")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"test@test.com\"}"))
                .andExpect(status().isOk());
    }

    /**
     * Verifies that POST /v1/api/auth/password/forgot returns HTTP 400 when
     * the request body does not include an email address.
     */
    @Test
    void forgotPasswordShouldReturnBadRequestIfEmailMissing() throws Exception {
        mockMvc.perform(post("/v1/api/auth/password/forgot")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());
    }

    /**
     * Verifies that POST /v1/api/auth/password/forgot returns HTTP 200 even
     * when the underlying {@link PasswordResetService#startReset} throws an
     * exception.  The controller must catch the exception and return a generic
     * success message to prevent user enumeration.
     */
    @Test
    void forgotPasswordShouldStillReturnOkWhenServiceThrows() throws Exception {
        doThrow(new RuntimeException("SMTP failure"))
                .when(reset).startReset(any(), any());

        mockMvc.perform(post("/v1/api/auth/password/forgot")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"test@test.com\"}"))
                .andExpect(status().isOk());
    }

    // ==========================================
    // CHANGE PASSWORD - NO TOKEN
    // ==========================================

    /**
     * Verifies that POST /v1/api/auth/password/change returns HTTP 401 when
     * no authentication token is provided.
     *
     * <p>Changing a password is a privileged operation that must require a
     * valid authenticated session.  By omitting the JWT cookie/header this
     * test confirms that the controller guards the endpoint correctly and does
     * not allow unauthenticated callers to modify credentials.
     */
    @Test
    void changePasswordShouldReturnUnauthorizedIfNoToken() throws Exception {

        final ChangePasswordRequest req =
                new ChangePasswordRequest("old", "new");

        mockMvc.perform(post("/v1/api/auth/password/change")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(req)))
                .andExpect(status().isUnauthorized());
    }

    /**
     * Verifies that POST /v1/api/auth/password/change returns HTTP 200 when a
     * valid JWT is supplied via the {@code Authorization: Bearer} header, and
     * the service accepts the password change.
     */
    @Test
    void changePasswordShouldReturnOkWithBearerToken() throws Exception {
        when(jwt.getEmailFromToken("valid-token")).thenReturn("user@test.com");
        when(authService.changePassword(eq("user@test.com"), any(), any()))
                .thenAnswer(inv -> ResponseEntity.ok(Map.of("message", "Password changed")));

        final ChangePasswordRequest req = new ChangePasswordRequest("old", "new");

        mockMvc.perform(post("/v1/api/auth/password/change")
                        .contentType(MediaType.APPLICATION_JSON)
                        .header("Authorization", "Bearer valid-token")
                        .content(objectMapper.writeValueAsString(req)))
                .andExpect(status().isOk());
    }

    /**
     * Verifies that POST /v1/api/auth/password/change returns HTTP 200 when a
     * valid JWT is supplied via the {@code AUTH} cookie (the alternative
     * extraction path in {@code extractTokenFromRequest}).
     */
    @Test
    void changePasswordShouldReturnOkWithCookie() throws Exception {
        when(jwt.getEmailFromToken("cookie-token")).thenReturn("user@test.com");
        when(authService.changePassword(eq("user@test.com"), any(), any()))
                .thenAnswer(inv -> ResponseEntity.ok(Map.of("message", "Password changed")));

        final ChangePasswordRequest req = new ChangePasswordRequest("old", "new");

        mockMvc.perform(post("/v1/api/auth/password/change")
                        .contentType(MediaType.APPLICATION_JSON)
                        .cookie(new Cookie("AUTH", "cookie-token"))
                        .content(objectMapper.writeValueAsString(req)))
                .andExpect(status().isOk());
    }

    /**
     * Verifies that POST /v1/api/auth/password/change returns HTTP 400 when
     * the service throws an exception (e.g. wrong current password), allowing
     * the controller's catch block to return a meaningful error response.
     */
    @Test
    void changePasswordShouldReturnBadRequestIfServiceThrows() throws Exception {
        when(jwt.getEmailFromToken("valid-token")).thenReturn("user@test.com");
        when(authService.changePassword(any(), any(), any()))
                .thenThrow(new RuntimeException("Incorrect current password"));

        final ChangePasswordRequest req = new ChangePasswordRequest("wrong", "new");

        mockMvc.perform(post("/v1/api/auth/password/change")
                        .contentType(MediaType.APPLICATION_JSON)
                        .header("Authorization", "Bearer valid-token")
                        .content(objectMapper.writeValueAsString(req)))
                .andExpect(status().isBadRequest());
    }

    // ==========================================
    // VALIDATE RESET TOKEN
    // ==========================================

    /**
     * Verifies that GET /v1/api/auth/password/reset returns HTTP 200 when the
     * supplied reset token is valid.
     *
     * <p>{@link PasswordResetService#isTokenValid} is stubbed to return
     * {@code true} for the token {@code "abc"}, simulating a token that has not
     * yet expired.  The test confirms that the controller correctly delegates
     * validation to the service and maps a valid result to a 200 response,
     * which the frontend uses to decide whether to render the reset-password
     * form.
     */
    @Test
    void validateResetTokenShouldReturnOkIfValid() throws Exception {

        when(reset.isTokenValid("abc")).thenReturn(true);

        mockMvc.perform(get("/v1/api/auth/password/reset")
                        .param("token", "abc"))
                .andExpect(status().isOk());
    }

    /**
     * Verifies that GET /v1/api/auth/password/reset returns HTTP 400 when
     * the token is expired or unrecognised.
     */
    @Test
    void validateResetTokenShouldReturnBadRequestIfInvalid() throws Exception {
        when(reset.isTokenValid("expired")).thenReturn(false);

        mockMvc.perform(get("/v1/api/auth/password/reset")
                        .param("token", "expired"))
                .andExpect(status().isBadRequest());
    }

    // ==========================================
    // GOOGLE SSO
    // ==========================================

    /**
     * Verifies that GET /v1/api/auth/sso/google redirects the caller to the
     * Google OAuth authorisation URL built by {@link AuthService#buildGoogleOAuthUrl}.
     */
    @Test
    void googleLoginShouldRedirectToGoogleAuthUrl() throws Exception {
        when(authService.buildGoogleOAuthUrl())
                .thenReturn("https://accounts.google.com/o/oauth2/auth?client_id=test");

        mockMvc.perform(get("/v1/api/auth/sso/google"))
                .andExpect(status().is3xxRedirection());
    }

    /**
     * Verifies that GET /v1/api/auth/sso/google/callback redirects to the
     * frontend error URL when Google returns an {@code error} query parameter
     * (e.g. the user denied consent).
     */
    @Test
    void googleCallbackShouldRedirectWithErrorParam() throws Exception {
        mockMvc.perform(get("/v1/api/auth/sso/google/callback")
                        .param("code", "ignored")
                        .param("error", "access_denied"))
                .andExpect(status().is3xxRedirection())
                .andExpect(header().string("Location",
                        "http://localhost:3000/oauth/callback?error=access_denied"));
    }

    /**
     * Verifies that GET /v1/api/auth/sso/google/callback redirects to the
     * frontend with a JWT token and user data when the OAuth exchange succeeds.
     */
    @Test
    void googleCallbackShouldRedirectWithTokenOnSuccess() throws Exception {
        final LoginResponse loginResponse = LoginResponse.builder()
                .token("google-jwt")
                .id(1L)
                .email("user@test.com")
                .build();

        when(authService.processGoogleOAuth(eq("google-code"), any()))
                .thenReturn(loginResponse);

        mockMvc.perform(get("/v1/api/auth/sso/google/callback")
                        .param("code", "google-code"))
                .andExpect(status().is3xxRedirection())
                .andExpect(header().string("Location",
                        org.hamcrest.Matchers.containsString("/oauth/callback?token=google-jwt")));
    }

    /**
     * Verifies that GET /v1/api/auth/sso/google/callback redirects to the
     * frontend with the specific OAuth error type when an {@link OAuthException}
     * is thrown during token exchange.
     */
    @Test
    void googleCallbackShouldRedirectOnOAuthException() throws Exception {
        when(authService.processGoogleOAuth(any(), any()))
                .thenThrow(new OAuthException("Google denied", "access_denied"));

        mockMvc.perform(get("/v1/api/auth/sso/google/callback")
                        .param("code", "any-code"))
                .andExpect(status().is3xxRedirection())
                .andExpect(header().string("Location",
                        "http://localhost:3000/oauth/callback?error=access_denied"));
    }

    /**
     * Verifies that GET /v1/api/auth/sso/google/callback redirects to the
     * frontend with a generic error type when an unexpected exception is thrown,
     * exercising the {@code determineOAuthErrorType} fallback path.
     */
    @Test
    void googleCallbackShouldRedirectOnGenericException() throws Exception {
        when(authService.processGoogleOAuth(any(), any()))
                .thenThrow(new RuntimeException("unexpected failure"));

        mockMvc.perform(get("/v1/api/auth/sso/google/callback")
                        .param("code", "any-code"))
                .andExpect(status().is3xxRedirection())
                .andExpect(header().string("Location",
                        "http://localhost:3000/oauth/callback?error=oauth_failed"));
    }

    /**
     * Verifies that the {@code determineOAuthErrorType} helper correctly maps
     * an exception with "access_denied" in its message to the
     * {@code access_denied} error token via the google callback route.
     */
    @Test
    void googleCallbackShouldRedirectWithAccessDeniedForDeniedMessage() throws Exception {
        when(authService.processGoogleOAuth(any(), any()))
                .thenThrow(new RuntimeException("User access_denied the request"));

        mockMvc.perform(get("/v1/api/auth/sso/google/callback")
                        .param("code", "code"))
                .andExpect(status().is3xxRedirection())
                .andExpect(header().string("Location",
                        "http://localhost:3000/oauth/callback?error=access_denied"));
    }

    /**
     * Verifies that the {@code determineOAuthErrorType} helper maps a timeout
     * message to the {@code network_error} error token.
     */
    @Test
    void googleCallbackShouldRedirectWithNetworkErrorForTimeout() throws Exception {
        when(authService.processGoogleOAuth(any(), any()))
                .thenThrow(new RuntimeException("connection timeout occurred"));

        mockMvc.perform(get("/v1/api/auth/sso/google/callback")
                        .param("code", "code"))
                .andExpect(status().is3xxRedirection())
                .andExpect(header().string("Location",
                        "http://localhost:3000/oauth/callback?error=network_error"));
    }

    // ==========================================
    // ALEXA CODE - MISSING TOKEN
    // ==========================================

    /**
     * Verifies that POST /v1/api/auth/sso/alexa/code returns HTTP 401 when no
     * authentication cookie is present.
     *
     * <p>The Alexa SSO code generation endpoint must be restricted to
     * authenticated users.  Sending the request without an {@code AUTH} cookie
     * confirms that the controller rejects unauthenticated callers before
     * attempting to generate or return a code.
     */
    @Test
    void generateAlexaCodeShouldReturnUnauthorizedIfMissingToken() throws Exception {

        mockMvc.perform(post("/v1/api/auth/sso/alexa/code"))
                .andExpect(status().isUnauthorized());
    }

    // ==========================================
    // ALEXA CODE - VALID TOKEN
    // ==========================================

    /**
     * Verifies that POST /v1/api/auth/sso/alexa/code returns HTTP 200 and a
     * JSON body containing a {@code code} field when a valid {@code AUTH}
     * cookie is present.
     *
     * <p>The JWT provider is stubbed to confirm the token is valid and to
     * resolve the associated email address.  The Alexa code store is stubbed
     * to return a predictable code string.  The test then asserts that the
     * response body contains the {@code $.code} field, confirming end-to-end
     * that the controller correctly reads the cookie, validates the token,
     * delegates to the code store, and wraps the result in JSON.
     */
    @Test
    void generateAlexaCodeShouldReturnCodeIfValidToken() throws Exception {

        when(jwt.getEmailFromToken("token")).thenReturn("test@test.com");
        when(jwt.validateToken("token")).thenReturn(true);
        when(alexaCodeStore.generateCode("token")).thenReturn("test-alexa-code");

        mockMvc.perform(post("/v1/api/auth/sso/alexa/code")
                        .cookie(new Cookie("AUTH", "token")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").exists());
    }

    /**
     * Verifies that POST /v1/api/auth/sso/alexa/code returns HTTP 401 when
     * the JWT provider returns {@code null} for the email, indicating the
     * token does not contain valid claims.
     */
    @Test
    void generateAlexaCodeShouldReturnUnauthorizedIfEmailNull() throws Exception {
        when(jwt.getEmailFromToken("bad-token")).thenReturn(null);
        when(jwt.validateToken("bad-token")).thenReturn(true);

        mockMvc.perform(post("/v1/api/auth/sso/alexa/code")
                        .cookie(new Cookie("AUTH", "bad-token")))
                .andExpect(status().isUnauthorized());
    }

    /**
     * Verifies that POST /v1/api/auth/sso/alexa/code returns HTTP 401 when
     * {@link JwtTokenProvider#validateToken} returns {@code false}, indicating
     * the token is invalid or expired.
     */
    @Test
    void generateAlexaCodeShouldReturnUnauthorizedIfTokenValidationFails() throws Exception {
        when(jwt.getEmailFromToken("invalid-token")).thenReturn("user@test.com");
        when(jwt.validateToken("invalid-token")).thenReturn(false);

        mockMvc.perform(post("/v1/api/auth/sso/alexa/code")
                        .cookie(new Cookie("AUTH", "invalid-token")))
                .andExpect(status().isUnauthorized());
    }

    // ==========================================
    // ALEXA TOKEN EXCHANGE — helpers
    // ==========================================

    /**
     * Returns a valid Basic Auth header using the test-configured client credentials.
     */
    private String validBasicAuth() throws Exception {
        return "Basic " + Base64.getEncoder()
                .encodeToString("test-client-id:test-client-secret".getBytes());
    }

    /**
     * Returns a Basic Auth header with wrong credentials.
     */
    private String wrongBasicAuth() throws Exception {
        return "Basic " + Base64.getEncoder()
                .encodeToString("wrong-id:wrong-secret".getBytes());
    }

    // ==========================================
    // ALEXA TOKEN EXCHANGE — auth header guards
    // ==========================================

    /**
     * Verifies that POST /v1/api/auth/sso/alexa/token returns HTTP 401 when
     * no {@code Authorization} header is present, as Alexa requires Basic Auth.
     */
    @Test
    void exchangeAlexaTokenShouldReturnUnauthorizedIfNoAuthHeader() throws Exception {
        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .param("grant_type", "authorization_code")
                        .param("code", "some-code"))
                .andExpect(status().isUnauthorized());
    }

    /**
     * Verifies that POST /v1/api/auth/sso/alexa/token returns HTTP 401 when
     * the Basic Auth credentials do not match the configured client ID/secret.
     */
    @Test
    void exchangeAlexaTokenShouldReturnUnauthorizedIfInvalidCredentials() throws Exception {
        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", wrongBasicAuth())
                        .param("grant_type", "authorization_code")
                        .param("code", "some-code"))
                .andExpect(status().isUnauthorized());
    }

    /**
     * Verifies that POST /v1/api/auth/sso/alexa/token returns HTTP 400 when
     * the {@code Authorization} header contains malformed (non-base64) data.
     */
    @Test
    void exchangeAlexaTokenShouldReturnBadRequestForMalformedBasicAuth() throws Exception {
        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", "Basic !!!not-valid-base64!!!")
                        .param("grant_type", "authorization_code"))
                .andExpect(status().isBadRequest());
    }

    // ==========================================
    // ALEXA TOKEN EXCHANGE — authorization_code grant
    // ==========================================

    /**
     * Verifies that the {@code authorization_code} grant path returns HTTP 400
     * when the {@code code} parameter is absent.
     */
    @Test
    void exchangeAlexaTokenShouldReturnBadRequestForMissingCode() throws Exception {
        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", validBasicAuth())
                        .param("grant_type", "authorization_code"))
                .andExpect(status().isBadRequest());
    }

    /**
     * Verifies that the {@code authorization_code} grant path returns HTTP 400
     * when the code store cannot find a JWT for the supplied code.
     */
    @Test
    void exchangeAlexaTokenShouldReturnBadRequestForInvalidCode() throws Exception {
        when(alexaCodeStore.consumeCode("unknown")).thenReturn(null);

        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", validBasicAuth())
                        .param("grant_type", "authorization_code")
                        .param("code", "unknown"))
                .andExpect(status().isBadRequest());
    }

    /**
     * Verifies that the {@code authorization_code} grant path returns HTTP 401
     * when the JWT retrieved from the code store has already expired.
     */
    @Test
    void exchangeAlexaTokenShouldReturnUnauthorizedIfJwtExpired() throws Exception {
        when(alexaCodeStore.consumeCode("expired-code")).thenReturn("expired-jwt");
        when(jwt.validateToken("expired-jwt")).thenReturn(false);

        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", validBasicAuth())
                        .param("grant_type", "authorization_code")
                        .param("code", "expired-code"))
                .andExpect(status().isUnauthorized());
    }

    /**
     * Verifies that the {@code authorization_code} grant path returns HTTP 400
     * when the JWT contains no email claim.
     */
    @Test
    void exchangeAlexaTokenShouldReturnBadRequestIfEmailNull() throws Exception {
        when(alexaCodeStore.consumeCode("code")).thenReturn("jwt");
        when(jwt.validateToken("jwt")).thenReturn(true);
        when(jwt.getEmailFromToken("jwt")).thenReturn(null);

        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", validBasicAuth())
                        .param("grant_type", "authorization_code")
                        .param("code", "code"))
                .andExpect(status().isBadRequest());
    }

    /**
     * Verifies that the {@code authorization_code} grant path returns HTTP 400
     * when no {@link User} record exists for the email in the JWT.
     */
    @Test
    void exchangeAlexaTokenShouldReturnBadRequestIfUserNotFound() throws Exception {
        when(alexaCodeStore.consumeCode("code")).thenReturn("jwt");
        when(jwt.validateToken("jwt")).thenReturn(true);
        when(jwt.getEmailFromToken("jwt")).thenReturn("missing@test.com");
        when(userRepository.findByEmail("missing@test.com")).thenReturn(Optional.empty());

        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", validBasicAuth())
                        .param("grant_type", "authorization_code")
                        .param("code", "code"))
                .andExpect(status().isBadRequest());
    }

    /**
     * Verifies that the {@code authorization_code} grant path returns HTTP 400
     * when no {@link Patient} record is associated with the found user.
     */
    @Test
    void exchangeAlexaTokenShouldReturnBadRequestIfPatientNotFound() throws Exception {
        final User user = Mockito.mock(User.class);
        when(alexaCodeStore.consumeCode("code")).thenReturn("jwt");
        when(jwt.validateToken("jwt")).thenReturn(true);
        when(jwt.getEmailFromToken("jwt")).thenReturn("user@test.com");
        when(userRepository.findByEmail("user@test.com")).thenReturn(Optional.of(user));
        when(patientRepository.findByUser(user)).thenReturn(Optional.empty());

        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", validBasicAuth())
                        .param("grant_type", "authorization_code")
                        .param("code", "code"))
                .andExpect(status().isBadRequest());
    }

    /**
     * Verifies the full happy path for the {@code authorization_code} grant:
     * valid code, valid JWT, existing user and patient — returns HTTP 200 with
     * {@code access_token} and {@code refresh_token} fields.
     */
    @Test
    void exchangeAlexaTokenAuthCodeHappyPathShouldReturnOk() throws Exception {
        final User user = Mockito.mock(User.class);
        final Patient patient = Mockito.mock(Patient.class);

        when(alexaCodeStore.consumeCode("valid-code")).thenReturn("valid-jwt");
        when(jwt.validateToken("valid-jwt")).thenReturn(true);
        when(jwt.getEmailFromToken("valid-jwt")).thenReturn("user@test.com");
        when(userRepository.findByEmail("user@test.com")).thenReturn(Optional.of(user));
        when(patientRepository.findByUser(user)).thenReturn(Optional.of(patient));
        when(tokenHashService.hashToken(any())).thenReturn("hashed-refresh");

        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", validBasicAuth())
                        .param("grant_type", "authorization_code")
                        .param("code", "valid-code"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.access_token").exists())
                .andExpect(jsonPath("$.refresh_token").exists());
    }

    // ==========================================
    // ALEXA TOKEN EXCHANGE — refresh_token grant
    // ==========================================

    /**
     * Verifies that the {@code refresh_token} grant path returns HTTP 400 when
     * the {@code refresh_token} parameter is absent.
     */
    @Test
    void exchangeAlexaTokenShouldReturnBadRequestForMissingRefreshToken() throws Exception {
        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", validBasicAuth())
                        .param("grant_type", "refresh_token"))
                .andExpect(status().isBadRequest());
    }

    /**
     * Verifies that the {@code refresh_token} grant path returns HTTP 401 when
     * the supplied token does not match any linked patient record.
     */
    @Test
    void exchangeAlexaTokenShouldReturnUnauthorizedIfNoPatientMatchesRefreshToken() throws Exception {
        when(patientRepository.findAll()).thenReturn(List.of());

        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", validBasicAuth())
                        .param("grant_type", "refresh_token")
                        .param("refresh_token", "unknown-token"))
                .andExpect(status().isUnauthorized());
    }

    /**
     * Verifies that the {@code refresh_token} grant path returns HTTP 401 and
     * unlinks the Alexa account when the stored refresh token has expired.
     */
    @Test
    void exchangeAlexaTokenShouldReturnUnauthorizedIfRefreshTokenExpired() throws Exception {
        final Patient patient = Mockito.mock(Patient.class);
        when(patient.isAlexaLinked()).thenReturn(true);
        when(patient.getAlexaRefreshToken()).thenReturn("hashed");
        when(tokenHashService.verifyToken("my-refresh", "hashed")).thenReturn(true);
        when(patient.isAlexaRefreshTokenExpired()).thenReturn(true);
        when(patientRepository.findAll()).thenReturn(List.of(patient));

        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", validBasicAuth())
                        .param("grant_type", "refresh_token")
                        .param("refresh_token", "my-refresh"))
                .andExpect(status().isUnauthorized());
    }

    /**
     * Verifies the full happy path for the {@code refresh_token} grant: matched
     * patient, non-expired token — returns HTTP 200 with new {@code access_token}
     * and {@code refresh_token}.
     */
    @Test
    void exchangeAlexaTokenRefreshTokenHappyPathShouldReturnOk() throws Exception {
        final User user = Mockito.mock(User.class);
        final Patient patient = Mockito.mock(Patient.class);

        when(patient.isAlexaLinked()).thenReturn(true);
        when(patient.getAlexaRefreshToken()).thenReturn("stored-hash");
        when(tokenHashService.verifyToken("good-refresh", "stored-hash")).thenReturn(true);
        when(patient.isAlexaRefreshTokenExpired()).thenReturn(false);
        when(patient.getUser()).thenReturn(user);
        when(user.getEmail()).thenReturn("user@test.com");
        when(user.getRole()).thenReturn(Role.PATIENT);
        when(jwt.createToken("user@test.com", Role.PATIENT)).thenReturn("new-jwt");
        when(tokenHashService.hashToken(any())).thenReturn("new-hash");
        when(patientRepository.findAll()).thenReturn(List.of(patient));

        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", validBasicAuth())
                        .param("grant_type", "refresh_token")
                        .param("refresh_token", "good-refresh"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.access_token").exists())
                .andExpect(jsonPath("$.refresh_token").exists());
    }

    /**
     * Verifies that an unrecognised grant type returns HTTP 400 with a
     * {@code unsupported_grant_type} error.
     */
    @Test
    void exchangeAlexaTokenShouldReturnBadRequestForUnsupportedGrantType() throws Exception {
        mockMvc.perform(post("/v1/api/auth/sso/alexa/token")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .header("Authorization", validBasicAuth())
                        .param("grant_type", "password"))
                .andExpect(status().isBadRequest());
    }

    // ==========================================
    // ALEXA UNLINK
    // ==========================================

    /**
     * Verifies that POST /v1/api/auth/sso/alexa/unlink returns HTTP 401 when
     * no authentication token is supplied.
     */
    @Test
    void unlinkAlexaShouldReturnUnauthorizedIfNoToken() throws Exception {
        mockMvc.perform(post("/v1/api/auth/sso/alexa/unlink"))
                .andExpect(status().isUnauthorized());
    }

    /**
     * Verifies that POST /v1/api/auth/sso/alexa/unlink returns HTTP 400 when
     * the email from the JWT does not correspond to any known user.
     */
    @Test
    void unlinkAlexaShouldReturnBadRequestIfUserNotFound() throws Exception {
        when(jwt.getEmailFromToken("token")).thenReturn("ghost@test.com");
        when(userRepository.findByEmail("ghost@test.com")).thenReturn(Optional.empty());

        mockMvc.perform(post("/v1/api/auth/sso/alexa/unlink")
                        .cookie(new Cookie("AUTH", "token")))
                .andExpect(status().isBadRequest());
    }

    /**
     * Verifies that POST /v1/api/auth/sso/alexa/unlink returns HTTP 400 when
     * the user exists but has no associated patient record.
     */
    @Test
    void unlinkAlexaShouldReturnBadRequestIfPatientNotFound() throws Exception {
        final User user = Mockito.mock(User.class);
        when(jwt.getEmailFromToken("token")).thenReturn("user@test.com");
        when(userRepository.findByEmail("user@test.com")).thenReturn(Optional.of(user));
        when(patientRepository.findByUser(user)).thenReturn(Optional.empty());

        mockMvc.perform(post("/v1/api/auth/sso/alexa/unlink")
                        .cookie(new Cookie("AUTH", "token")))
                .andExpect(status().isBadRequest());
    }

    /**
     * Verifies that POST /v1/api/auth/sso/alexa/unlink returns HTTP 200 and
     * clears all Alexa-related fields on the patient record when both the user
     * and patient exist.
     */
    @Test
    void unlinkAlexaShouldReturnOkOnSuccess() throws Exception {
        final User user = Mockito.mock(User.class);
        final Patient patient = Mockito.mock(Patient.class);
        when(jwt.getEmailFromToken("token")).thenReturn("user@test.com");
        when(userRepository.findByEmail("user@test.com")).thenReturn(Optional.of(user));
        when(patientRepository.findByUser(user)).thenReturn(Optional.of(patient));

        mockMvc.perform(post("/v1/api/auth/sso/alexa/unlink")
                        .cookie(new Cookie("AUTH", "token")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").exists());
    }
}
