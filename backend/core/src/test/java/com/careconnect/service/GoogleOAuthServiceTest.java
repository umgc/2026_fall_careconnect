package com.careconnect.service;

import com.careconnect.exception.EmailCredentialNeedsReauthException;
import com.careconnect.model.EmailCredential;
import com.careconnect.repository.EmailCredentialRepository;
import com.careconnect.security.TokenCryptor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestTemplate;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.time.Instant;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;

class GoogleOAuthServiceTest {

    private TokenCryptor tokenCryptor;
    private GoogleOAuthService service;
    private EmailCredentialLifecycleService lifecycle;
    private AtomicReference<EmailCredential> savedRef;
    private MockRestServiceServer server;
    private AtomicReference<EmailCredential> existingCredRef;

    @BeforeEach
    void setUp() throws Exception {
        tokenCryptor = new TokenCryptor("unit-test-secret-32-bytes-long!!!");
        savedRef = new AtomicReference<>();
        existingCredRef = new AtomicReference<>();

        final RestTemplate rt = new RestTemplate();
        server = MockRestServiceServer.createServer(rt);

        final EmailCredentialRepository repo = createRepositoryStub();
        lifecycle = new EmailCredentialLifecycleService(repo, mock(NotificationService.class));
        service = new GoogleOAuthService(rt, repo, tokenCryptor, lifecycle);
        service.clientId = "test-client";
        service.clientSecret = "test-secret";
        service.redirectUri = "http://localhost/oauth/callback";
    }

    // -----------------------------------------------------------------------
    // exchange() tests
    // -----------------------------------------------------------------------

    @Nested
    @DisplayName("exchange() method")
    class ExchangeTests {

        @Test
        @DisplayName("exchange succeeds with access token and refresh token")
        void exchangeSucceedsWithAccessAndRefreshToken() throws Exception {
            final String json = "{\"access_token\": \"access-abc\",\"refresh_token\":" +
            "\"refresh-xyz\",\"expires_in\": 3600}";

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andExpect(content().string(org.hamcrest.Matchers.containsString("grant_type=authorization_code")))
                    .andExpect(content().string(org.hamcrest.Matchers.containsString("code=auth-code-123")))
                    .andExpect(content().string(org.hamcrest.Matchers.containsString("client_id=test-client")))
                    .andExpect(content().string(org.hamcrest.Matchers.containsString("client_secret=test-secret")))
                    .andExpect(content().string(org.hamcrest.Matchers.containsString("redirect_uri=http%3A%2F%2Flocalhost%2Foauth%2Fcallback")))
                    .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

            service.exchange("user-1", "auth-code-123");

            final EmailCredential saved = savedRef.get();
            assertNotNull(saved, "Credential should be saved");
            assertEquals("user-1", saved.getUserId());
            assertEquals(EmailCredential.Provider.GMAIL, saved.getProvider());
            assertEquals("access-abc", tokenCryptor.decrypt(saved.getAccessTokenEnc()));
            assertEquals("refresh-xyz", tokenCryptor.decrypt(saved.getRefreshTokenEnc()));
            assertNotNull(saved.getExpiresAt());
            assertTrue(saved.getExpiresAt().isAfter(Instant.now()));

            server.verify();
        }

        @Test
        @DisplayName("exchange succeeds without refresh token and no existing credential")
        void exchangeSucceedsWithoutRefreshTokenNoExisting() throws Exception {
            final String json = "{\"access_token\": \"access-only\"," +
                      "\"expires_in\": 3600}";

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

            service.exchange("user-2", "auth-code-456");

            final EmailCredential saved = savedRef.get();
            assertNotNull(saved);
            assertEquals("access-only", tokenCryptor.decrypt(saved.getAccessTokenEnc()));
            assertNull(saved.getRefreshTokenEnc(), "No refresh token should be set when none returned and none existing");

            server.verify();
        }

        @Test
        @DisplayName("exchange succeeds without refresh token but reuses existing refresh token")
        void exchangeSucceedsWithoutRefreshTokenReusesExisting() throws Exception {
            // Set up existing credential with a refresh token
            final EmailCredential existing = new EmailCredential();
            existing.setUserId("user-3");
            existing.setProvider(EmailCredential.Provider.GMAIL);
            existing.setRefreshTokenEnc(tokenCryptor.encrypt("old-refresh-token"));
            existingCredRef.set(existing);

            final String json = "{\"access_token\": \"new-access\"," +
                      "\"expires_in\": 7200}";

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

            service.exchange("user-3", "auth-code-789");

            final EmailCredential saved = savedRef.get();
            assertNotNull(saved);
            assertEquals("new-access", tokenCryptor.decrypt(saved.getAccessTokenEnc()));
            assertEquals("old-refresh-token", tokenCryptor.decrypt(saved.getRefreshTokenEnc()),
                    "Should reuse existing refresh token");

            server.verify();
        }

        @Test
        @DisplayName("exchange throws RuntimeException when token response is null (non-2xx)")
        void exchangeThrowsWhenTokenResponseIsNull() throws Exception {
            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess("null", MediaType.APPLICATION_JSON));

            final RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> service.exchange("user-4", "bad-code"));

            assertTrue(ex.getMessage().contains("Google OAuth token exchange failed"));

            server.verify();
        }

        @Test
        @DisplayName("exchange throws RuntimeException when access token is null")
        void exchangeThrowsWhenAccessTokenIsNull() throws Exception {
            final String json = "{\"refresh_token\": \"refresh-only\"," +
                      "\"expires_in\": 3600}";

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

            final RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> service.exchange("user-5", "no-access-code"));

            assertTrue(ex.getMessage().contains("Google OAuth token exchange failed"));

            server.verify();
        }

        @Test
        @DisplayName("exchange wraps any exception in RuntimeException")
        void exchangeWrapsExceptionInRuntimeException() throws Exception {
            // Simulate a server error which will cause RestTemplate to throw
            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withServerError());

            final RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> service.exchange("user-6", "error-code"));

            assertTrue(ex.getMessage().contains("Google OAuth token exchange failed"));

            server.verify();
        }
    }

    // -----------------------------------------------------------------------
    // ensureFreshToken() tests
    // -----------------------------------------------------------------------

    @Nested
    @DisplayName("ensureFreshToken() method")
    class EnsureFreshTokenTests {

        @Test
        @DisplayName("returns current credential when token is still valid")
        void returnsCurrentWhenStillValid() throws Exception {
            final EmailCredential credential = new EmailCredential();
            credential.setAccessTokenEnc(tokenCryptor.encrypt("existing"));
            credential.setRefreshTokenEnc(tokenCryptor.encrypt("refresh-123"));
            credential.setExpiresAt(Instant.now().plusSeconds(600));

            final EmailCredential result = service.ensureFreshToken(credential);

            assertSame(credential, result);
            assertNull(savedRef.get(), "Repository save should not be invoked");
            server.verify();
        }

        @Test
        @DisplayName("refreshes token when expired")
        void refreshesWhenExpired() throws Exception {
            final EmailCredential credential = new EmailCredential();
            credential.setAccessTokenEnc(tokenCryptor.encrypt("stale"));
            credential.setRefreshTokenEnc(tokenCryptor.encrypt("refresh-321"));
            credential.setExpiresAt(Instant.now().minusSeconds(5));

            final String json = "{\"access_token\": \"new-access-token\"," +
                      "\"expires_in\": 3600}";

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andExpect(header("Content-Type", MediaType.APPLICATION_FORM_URLENCODED_VALUE))
                    .andExpect(content().contentType(MediaType.APPLICATION_FORM_URLENCODED))
                    .andExpect(content().string(org.hamcrest.Matchers.containsString("grant_type=refresh_token")))
                    .andExpect(content().string(org.hamcrest.Matchers.containsString("client_id=test-client")))
                    .andExpect(content().string(org.hamcrest.Matchers.containsString("client_secret=test-secret")))
                    .andExpect(content().string(org.hamcrest.Matchers.containsString("refresh_token=refresh-321")))
                    .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

            final EmailCredential result = service.ensureFreshToken(credential);

            assertSame(credential, result);
            final EmailCredential persisted = savedRef.get();
            assertNotNull(persisted, "Repository save should capture entity");
            assertSame(credential, persisted, "Service should update the same credential instance");
            assertEquals("new-access-token", tokenCryptor.decrypt(persisted.getAccessTokenEnc()));
            assertTrue(persisted.getExpiresAt().isAfter(Instant.now()));

            server.verify();
        }

        @Test
        @DisplayName("refreshes token when expiresAt is null")
        void refreshesWhenExpiresAtIsNull() throws Exception {
            final EmailCredential credential = new EmailCredential();
            credential.setAccessTokenEnc(tokenCryptor.encrypt("stale"));
            credential.setRefreshTokenEnc(tokenCryptor.encrypt("refresh-null-exp"));
            credential.setExpiresAt(null);

            final String json = "{\"access_token\": \"refreshed-access\"," +
                      "\"expires_in\": 1800}";

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

            final EmailCredential result = service.ensureFreshToken(credential);

            assertSame(credential, result);
            assertEquals("refreshed-access", tokenCryptor.decrypt(result.getAccessTokenEnc()));
            assertNotNull(savedRef.get());

            server.verify();
        }

        @Test
        @DisplayName("refreshes token when expiry is within 120 seconds")
        void refreshesWhenExpiryWithinBuffer() throws Exception {
            final EmailCredential credential = new EmailCredential();
            credential.setAccessTokenEnc(tokenCryptor.encrypt("almost-stale"));
            credential.setRefreshTokenEnc(tokenCryptor.encrypt("refresh-buffer"));
            // Expires in 60 seconds - within the 120-second buffer
            credential.setExpiresAt(Instant.now().plusSeconds(60));

            final String json = "{\"access_token\": \"fresh-access\"," +
                      "\"expires_in\": 3600}";

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

            final EmailCredential result = service.ensureFreshToken(credential);

            assertSame(credential, result);
            assertEquals("fresh-access", tokenCryptor.decrypt(result.getAccessTokenEnc()));
            assertNotNull(savedRef.get());

            server.verify();
        }

        @Test
        @DisplayName("halts sync when decrypted refresh token is null")
        void haltsWhenRefreshTokenDecryptsToNull() throws Exception {
            final EmailCredential credential = new EmailCredential();
            credential.setUserId("user-1");
            credential.setAccessTokenEnc(tokenCryptor.encrypt("stale"));
            credential.setRefreshTokenEnc(null);
            credential.setExpiresAt(Instant.now().minusSeconds(5));

            assertThrows(EmailCredentialNeedsReauthException.class,
                    () -> service.ensureFreshToken(credential));
            assertEquals(EmailCredential.Status.NEEDS_REAUTH, credential.getStatus());
            assertFalse(credential.isSyncEnabled());
            server.verify();
        }

        @Test
        @DisplayName("halts sync when decrypted refresh token is blank")
        void haltsWhenRefreshTokenIsBlank() throws Exception {
            final EmailCredential credential = new EmailCredential();
            credential.setUserId("user-1");
            credential.setAccessTokenEnc(tokenCryptor.encrypt("stale"));
            credential.setRefreshTokenEnc(tokenCryptor.encrypt("   "));
            credential.setExpiresAt(Instant.now().minusSeconds(5));

            assertThrows(EmailCredentialNeedsReauthException.class,
                    () -> service.ensureFreshToken(credential));
            assertEquals(EmailCredential.Status.NEEDS_REAUTH, credential.getStatus());
            assertFalse(credential.isSyncEnabled());
            server.verify();
        }

        @Test
        @DisplayName("halts sync when refresh response has no access token")
        void haltsWhenRefreshResponseHasNoAccessToken() throws Exception {
            final EmailCredential credential = new EmailCredential();
            credential.setUserId("user-1");
            credential.setAccessTokenEnc(tokenCryptor.encrypt("old-access"));
            credential.setRefreshTokenEnc(tokenCryptor.encrypt("refresh-no-result"));
            credential.setExpiresAt(Instant.now().minusSeconds(5));

            final String json = "{\"expires_in\": 3600}";

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

            assertThrows(EmailCredentialNeedsReauthException.class,
                    () -> service.ensureFreshToken(credential));
            assertEquals(EmailCredential.Status.NEEDS_REAUTH, credential.getStatus());
            assertFalse(credential.isSyncEnabled());

            server.verify();
        }

        @Test
        @DisplayName("halts sync when refresh returns null body")
        void haltsWhenRefreshReturnsNullBody() throws Exception {
            final EmailCredential credential = new EmailCredential();
            credential.setUserId("user-1");
            credential.setAccessTokenEnc(tokenCryptor.encrypt("old-access"));
            credential.setRefreshTokenEnc(tokenCryptor.encrypt("refresh-null-body"));
            credential.setExpiresAt(Instant.now().minusSeconds(5));

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess("null", MediaType.APPLICATION_JSON));

            assertThrows(EmailCredentialNeedsReauthException.class,
                    () -> service.ensureFreshToken(credential));
            assertEquals(EmailCredential.Status.NEEDS_REAUTH, credential.getStatus());

            server.verify();
        }

        @Test
        @DisplayName("halts sync on invalid_grant from Google token endpoint")
        void haltsOnInvalidGrant() throws Exception {
            final EmailCredential credential = new EmailCredential();
            credential.setUserId("42");
            credential.setAccessTokenEnc(tokenCryptor.encrypt("stale"));
            credential.setRefreshTokenEnc(tokenCryptor.encrypt("revoked-refresh"));
            credential.setExpiresAt(Instant.now().minusSeconds(5));

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withStatus(HttpStatus.BAD_REQUEST)
                            .body("{\"error\":\"invalid_grant\"}")
                            .contentType(MediaType.APPLICATION_JSON));

            final EmailCredentialNeedsReauthException ex = assertThrows(
                    EmailCredentialNeedsReauthException.class,
                    () -> service.ensureFreshToken(credential));

            assertTrue(ex.getMessage().toLowerCase().contains("revoked")
                    || ex.getMessage().toLowerCase().contains("expired"));
            assertEquals(EmailCredential.Status.NEEDS_REAUTH, credential.getStatus());
            assertFalse(credential.isSyncEnabled());
            assertEquals("/oauth/google/start", ex.getReconnectPath());
            server.verify();
        }

        @Test
        @DisplayName("halts sync on HTTP 401 from Google token endpoint")
        void haltsOnUnauthorized() throws Exception {
            final EmailCredential credential = expiredCredential("43");

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withStatus(HttpStatus.UNAUTHORIZED)
                            .body("{\"error\":\"unauthorized_client\"}")
                            .contentType(MediaType.APPLICATION_JSON));

            assertThrows(EmailCredentialNeedsReauthException.class,
                    () -> service.ensureFreshToken(credential));
            assertEquals(EmailCredential.Status.NEEDS_REAUTH, credential.getStatus());
            assertFalse(credential.isSyncEnabled());
            server.verify();
        }

        @Test
        @DisplayName("does not halt on transient 429 — retries then surfaces without NEEDS_REAUTH")
        void doesNotHaltOnTooManyRequests() throws Exception {
            final EmailCredential credential = expiredCredential("44");

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withStatus(HttpStatus.TOO_MANY_REQUESTS));
            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withStatus(HttpStatus.TOO_MANY_REQUESTS));
            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withStatus(HttpStatus.TOO_MANY_REQUESTS));

            final IllegalStateException ex = assertThrows(
                    IllegalStateException.class,
                    () -> service.ensureFreshToken(credential));

            assertTrue(ex.getMessage().toLowerCase().contains("temporarily unavailable"));
            assertEquals(EmailCredential.Status.ACTIVE, credential.getStatus());
            assertTrue(credential.isSyncEnabled());
            server.verify();
        }

        @Test
        @DisplayName("does not halt on 5xx — retries then surfaces without NEEDS_REAUTH")
        void doesNotHaltOnServerError() throws Exception {
            final EmailCredential credential = expiredCredential("45");

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));
            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));
            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));

            assertThrows(IllegalStateException.class, () -> service.ensureFreshToken(credential));
            assertEquals(EmailCredential.Status.ACTIVE, credential.getStatus());
            assertTrue(credential.isSyncEnabled());
            server.verify();
        }

        @Test
        @DisplayName("does not halt on non-invalid_grant 400 from token endpoint")
        void doesNotHaltOnNonInvalidGrantBadRequest() throws Exception {
            final EmailCredential credential = expiredCredential("46");

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withStatus(HttpStatus.BAD_REQUEST)
                            .body("{\"error\":\"invalid_request\"}")
                            .contentType(MediaType.APPLICATION_JSON));

            assertThrows(IllegalStateException.class, () -> service.ensureFreshToken(credential));
            assertEquals(EmailCredential.Status.ACTIVE, credential.getStatus());
            assertTrue(credential.isSyncEnabled());
            server.verify();
        }

        @Test
        @DisplayName("retries after 429 then succeeds without marking NEEDS_REAUTH")
        void retriesTransientThenSucceeds() throws Exception {
            final EmailCredential credential = expiredCredential("47");

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withStatus(HttpStatus.TOO_MANY_REQUESTS));
            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess(
                            "{\"access_token\":\"recovered\",\"expires_in\":3600,\"token_type\":\"Bearer\"}",
                            MediaType.APPLICATION_JSON));

            final EmailCredential result = service.ensureFreshToken(credential);

            assertEquals(EmailCredential.Status.ACTIVE, result.getStatus());
            assertTrue(result.isSyncEnabled());
            assertEquals("recovered", tokenCryptor.decrypt(result.getAccessTokenEnc()));
            server.verify();
        }

        private EmailCredential expiredCredential(final String userId) {
            final EmailCredential credential = new EmailCredential();
            credential.setUserId(userId);
            credential.setAccessTokenEnc(tokenCryptor.encrypt("stale"));
            credential.setRefreshTokenEnc(tokenCryptor.encrypt("refresh-" + userId));
            credential.setExpiresAt(Instant.now().minusSeconds(5));
            credential.setStatus(EmailCredential.Status.ACTIVE);
            credential.setSyncEnabled(true);
            return credential;
        }

        @Test
        @DisplayName("skips refresh and throws when sync already halted")
        void throwsWhenSyncAlreadyHalted() {
            final EmailCredential credential = new EmailCredential();
            credential.setUserId("user-1");
            credential.setStatus(EmailCredential.Status.NEEDS_REAUTH);
            credential.setSyncEnabled(false);
            credential.setExpiresAt(Instant.now().plusSeconds(600));

            assertThrows(EmailCredentialNeedsReauthException.class,
                    () -> service.ensureFreshToken(credential));
            server.verify();
        }
    }

    // -----------------------------------------------------------------------
    // postForToken() non-2xx branch
    // -----------------------------------------------------------------------

    @Nested
    @DisplayName("postForToken() non-2xx handling")
    class PostForTokenNon2xxTests {

        @Test
        @DisplayName("exchange throws when token endpoint returns non-2xx status")
        void exchangeThrowsOnNon2xxFromTokenEndpoint() throws Exception {
            // 4xx client errors cause RestTemplate to throw, which triggers catch block
            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withBadRequest());

            final RuntimeException ex = assertThrows(RuntimeException.class,
                    () -> service.exchange("user-non2xx", "code-non2xx"));

            assertTrue(ex.getMessage().contains("Google OAuth token exchange failed"));

            server.verify();
        }
    }

    // -----------------------------------------------------------------------
    // safeId() private method coverage
    // -----------------------------------------------------------------------

    @Nested
    @DisplayName("safeId() private method via exchange")
    class SafeIdTests {

        @Test
        @DisplayName("safeId truncates long client IDs (length > 12)")
        void safeIdTruncatesLongId() throws Exception {
            // Set clientId to a long string (>12 chars) to cover the truncation branch
            service.clientId = "a]very-long-client-id-for-testing";

            final String json = "{" +
                      "\"access_token\": \"token-abc\"," +
                      "\"refresh_token\": \"refresh-abc\"," +
                      "\"expires_in\": 3600" +
                    "}";

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

            service.exchange("user-long-id", "code-long-id");

            assertNotNull(savedRef.get());
            server.verify();
        }

        @Test
        @DisplayName("safeId returns short client IDs as-is (length <= 12)")
        void safeIdReturnsShortIdAsIs() throws Exception {
            // Set clientId to a short string (<=12 chars)
            service.clientId = "short-id";

            final String json =
                    "{" +
                      "\"access_token\": \"token-short\"," +
                      "\"refresh_token\": \"refresh-short\"," +
                      "\"expires_in\": 3600" +
                    "}";

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

            service.exchange("user-short-id", "code-short-id");

            assertNotNull(savedRef.get());
            server.verify();
        }

        @Test
        @DisplayName("safeId handles null client ID - exchange throws when clientId is null")
        void safeIdHandlesNullId() {
            service.clientId = null;

            // The service guards against null clientId before reaching safeId(),
            // so exchange() throws RuntimeException wrapping IllegalStateException.
            assertThrows(RuntimeException.class,
                    () -> service.exchange("user-null-id", "code-null-id"));
        }

        @Test
        @DisplayName("safeId handles exactly 12-character client ID")
        void safeIdHandlesExactly12CharId() throws Exception {
            service.clientId = "123456789012"; // exactly 12 chars

            final String json =
                    "{" +
                      "\"access_token\": \"token-12\"," +
                      "\"refresh_token\": \"refresh-12\"," +
                      "\"expires_in\": 3600" +
                    "}";

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

            service.exchange("user-12-id", "code-12-id");

            assertNotNull(savedRef.get());
            server.verify();
        }
    }

    // -----------------------------------------------------------------------
    // Edge cases
    // -----------------------------------------------------------------------

    @Nested
    @DisplayName("Edge cases")
    class EdgeCaseTests {

        @Test
        @DisplayName("exchange with existing credential that has null refreshTokenEnc")
        void exchangeWithExistingCredentialNullRefreshEnc() throws Exception {
            // Existing credential with null refreshTokenEnc
            final EmailCredential existing = new EmailCredential();
            existing.setUserId("user-edge");
            existing.setProvider(EmailCredential.Provider.GMAIL);
            existing.setRefreshTokenEnc(null);
            existingCredRef.set(existing);

            final String json =
                    "{" +
                      "\"access_token\": \"access-edge\"," +
                      "\"expires_in\": 3600" +
                    "}";

            server.expect(requestTo("https://oauth2.googleapis.com/token"))
                    .andExpect(method(HttpMethod.POST))
                    .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

            service.exchange("user-edge", "code-edge");

            final EmailCredential saved = savedRef.get();
            assertNotNull(saved);
            assertNull(saved.getRefreshTokenEnc(),
                    "No refresh token should be set when none returned and existing has null");

            server.verify();
        }
    }

    // -----------------------------------------------------------------------
    // Repository stub
    // -----------------------------------------------------------------------

    private EmailCredentialRepository createRepositoryStub() throws Exception {
        final InvocationHandler handler = new InvocationHandler() {
            @Override
            public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
                final String name = method.getName();
                if (method.getDeclaringClass() == Object.class) {
                    return switch (name) {
                        case "toString" -> "EmailCredentialRepositoryStub";
                        case "hashCode" -> System.identityHashCode(proxy);
                        case "equals" -> proxy == args[0];
                        default -> method.invoke(this, args);
                    };
                }
                switch (name) {
                    case "save" -> {
                        final EmailCredential entity = (EmailCredential) args[0];
                        savedRef.set(entity);
                        return entity;
                    }
                    case "findFirstByUserIdAndProvider", "findFirstByUserIdAndProviderOrderByIdDesc" -> {
                        final EmailCredential existing = existingCredRef.get();
                        if (existing != null) {
                            return Optional.of(existing);
                        }
                        return Optional.empty();
                    }
                    default -> throw new UnsupportedOperationException("Method " + name + " not supported in stub");
                }
            }
        };
        return (EmailCredentialRepository) Proxy.newProxyInstance(
                GoogleOAuthServiceTest.class.getClassLoader(),
                new Class[]{EmailCredentialRepository.class},
                handler
        );
    }
}
