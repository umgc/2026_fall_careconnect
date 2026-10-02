package com.careconnect.service.ehr.athena;

import com.careconnect.config.AthenaProperties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestTemplate;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * Unit tests for the 2-legged athenahealth token service.
 *
 * <p>No network: a {@link MockRestServiceServer} is bound to a real {@link RestTemplate} so the
 * OUTGOING request can be asserted. That matters more than response parsing here, because every
 * failure mode observed against the live preview host was a request-shape or quota problem:
 * credentials in the body instead of the Basic header, an unconfigured scope, or hammering the
 * token endpoint until it returns 429.
 */
class AthenaClientCredentialsTokenServiceTest {

    private static final String TOKEN_URL = "https://athena.example/oauth2/v1/token";
    private static final String CLIENT_ID = "test-id";
    private static final String CLIENT_SECRET = "test-secret";

    private RestTemplate restTemplate;
    private MockRestServiceServer server;
    private AthenaProperties cfg;
    private AthenaClientCredentialsTokenService service;

    @BeforeEach
    void setUp() {
        restTemplate = new RestTemplate();
        server = MockRestServiceServer.createServer(restTemplate);

        // Spring is not involved, so @Value defaults do not apply; set what the service reads.
        cfg = new AthenaProperties();
        cfg.setTokenUrl(TOKEN_URL);
        cfg.setClientId(CLIENT_ID);
        cfg.setClientSecret(CLIENT_SECRET);
        cfg.setScopes("system/Patient.read system/Condition.read");

        service = new AthenaClientCredentialsTokenService(restTemplate, cfg);
    }

    private static String expectedBasic() {
        final String raw = CLIENT_ID + ":" + CLIENT_SECRET;
        return "Basic " + Base64.getEncoder().encodeToString(raw.getBytes(StandardCharsets.UTF_8));
    }

    private static String tokenJson(final String token, final long expiresIn, final String scope) {
        return "{\"access_token\":\"" + token + "\",\"token_type\":\"Bearer\",\"expires_in\":"
                + expiresIn + ",\"scope\":\"" + scope + "\"}";
    }

    @Test
    @DisplayName("sends client_credentials with Basic auth and keeps the secret out of the body")
    void sendsClientCredentialsWithBasicAuth() {
        // Arrange
        server.expect(requestTo(TOKEN_URL))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header("Authorization", expectedBasic()))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("grant_type=client_credentials")))
                .andExpect(content().string(org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("client_secret"))))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("scope=")))
                .andRespond(withSuccess(tokenJson("tok-1", 3600, "system/Patient.read"),
                        MediaType.APPLICATION_JSON));

        // Act
        final String token = service.accessToken();

        // Assert
        assertEquals("tok-1", token);
        server.verify();
    }

    @Test
    @DisplayName("caches the token: a second call issues no further request")
    void cachesTheToken() {
        // Arrange: exactly one expectation, so a second HTTP call would fail the test.
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withSuccess(tokenJson("tok-cached", 3600, "system/Patient.read"),
                        MediaType.APPLICATION_JSON));

        // Act
        final String first = service.accessToken();
        final String second = service.accessToken();

        // Assert
        assertEquals("tok-cached", first);
        assertEquals(second, first);
        server.verify();
    }

    @Test
    @DisplayName("re-acquires once the cached token falls inside the 120s renewal skew")
    void reacquiresWithinExpirySkew() {
        // Arrange: a 10s TTL is inside the skew, so the token is never considered usable.
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withSuccess(tokenJson("tok-old", 10, "system/Patient.read"),
                        MediaType.APPLICATION_JSON));
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withSuccess(tokenJson("tok-new", 3600, "system/Patient.read"),
                        MediaType.APPLICATION_JSON));

        // Act
        final String first = service.accessToken();
        final String second = service.accessToken();

        // Assert
        assertEquals("tok-old", first);
        assertEquals("tok-new", second);
        server.verify();
    }

    @Test
    @DisplayName("exposes the scopes athena granted, not the ones requested")
    void exposesGrantedScopes() {
        // Arrange: two scopes requested (see setUp), only one granted.
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withSuccess(tokenJson("tok-2", 3600, "system/Patient.read"),
                        MediaType.APPLICATION_JSON));

        // Act / Assert
        assertEquals(java.util.Set.of("system/Patient.read"), service.grantedScopes());
    }

    @Test
    @DisplayName("an unconfigured scope produces an actionable message, not 400 BAD_REQUEST")
    void invalidScopeIsActionable() {
        // Arrange: athena's real body for a scope the portal app does not have.
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withStatus(HttpStatus.BAD_REQUEST)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body("{\"error\":\"Invalid Scope\",\"detailedmessage\":"
                                + "\"One or more scopes are not configured for the authorization "
                                + "server resource.\"}"));

        // Act
        final IllegalStateException ex =
                assertThrows(IllegalStateException.class, () -> service.accessToken());

        // Assert: the message must name the cause and echo what was requested.
        assertTrue(ex.getMessage().contains("scopes"), ex.getMessage());
        assertTrue(ex.getMessage().contains("system/Patient.read"), ex.getMessage());
    }

    @Test
    @DisplayName("a 429 falls back to the still-valid cached token instead of failing")
    void quotaExceededReusesCachedToken() {
        // Arrange: 60s TTL is inside the skew (so a renewal is attempted) but not yet expired
        // (so the old token is still legitimately usable).
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withSuccess(tokenJson("tok-still-good", 60, "system/Patient.read"),
                        MediaType.APPLICATION_JSON));
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withStatus(HttpStatus.TOO_MANY_REQUESTS)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body("{\"error\":\"Quota Exceeded.\"}"));

        // Act
        final String first = service.accessToken();
        final String second = service.accessToken();

        // Assert
        assertEquals("tok-still-good", first);
        assertEquals("tok-still-good", second);
        server.verify();
    }

    @Test
    @DisplayName("a 429 with no cached token fails loudly")
    void quotaExceededWithoutCacheThrows() {
        // Arrange
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withStatus(HttpStatus.TOO_MANY_REQUESTS)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body("{\"error\":\"Quota Exceeded.\"}"));

        // Act
        final IllegalStateException ex =
                assertThrows(IllegalStateException.class, () -> service.accessToken());

        // Assert
        assertTrue(ex.getMessage().contains("429"), ex.getMessage());
    }

    @Test
    @DisplayName("missing credentials fail before any HTTP call")
    void missingCredentialsThrowBeforeRequest() {
        // Arrange: no expectations registered, so any request would fail the test.
        cfg.setClientSecret("");

        // Act
        final IllegalStateException ex =
                assertThrows(IllegalStateException.class, () -> service.accessToken());

        // Assert
        assertTrue(ex.getMessage().contains("client id/secret"), ex.getMessage());
        server.verify();
    }

    @Test
    @DisplayName("a 2xx with no access_token is treated as a failure")
    void missingAccessTokenThrows() {
        // Arrange
        server.expect(requestTo(TOKEN_URL))
                .andRespond(withSuccess("{\"token_type\":\"Bearer\",\"expires_in\":3600}",
                        MediaType.APPLICATION_JSON));

        // Act / Assert
        final IllegalStateException ex =
                assertThrows(IllegalStateException.class, () -> service.accessToken());
        assertTrue(ex.getMessage().contains("no access_token"), ex.getMessage());
    }
}
