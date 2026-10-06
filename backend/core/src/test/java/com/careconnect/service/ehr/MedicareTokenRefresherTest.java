package com.careconnect.service.ehr;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;
import org.springframework.security.oauth2.client.registration.InMemoryClientRegistrationRepository;
import org.springframework.security.oauth2.core.AuthorizationGrantType;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

/** The refresh-token exchange against a local stand-in for Blue Button's token endpoint. */
class MedicareTokenRefresherTest {

    private static final Instant NOW = Instant.parse("2026-10-04T12:00:00Z");

    private HttpServer server;
    private final AtomicReference<String> requestBody = new AtomicReference<>();
    private final AtomicReference<String> authorization = new AtomicReference<>();
    private volatile int status = 200;
    private volatile String responseBody = "{}";
    private MedicareTokenRefresher refresher;

    @BeforeEach
    void start() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/v3/o/token", exchange -> {
            requestBody.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            authorization.set(exchange.getRequestHeaders().getFirst("Authorization"));
            final byte[] bytes = responseBody.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(status, bytes.length);
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(bytes);
            }
        });
        server.start();
        final String tokenUri = "http://127.0.0.1:" + server.getAddress().getPort() + "/v3/o/token";
        final ClientRegistrationRepository registrations = new InMemoryClientRegistrationRepository(
                ClientRegistration.withRegistrationId("medicare")
                        .clientId("client-id")
                        .clientSecret("client-secret")
                        .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                        .redirectUri("http://localhost:8080/login/oauth2/code/medicare")
                        .authorizationUri("http://127.0.0.1/authorize")
                        .tokenUri(tokenUri)
                        .build());
        refresher = new MedicareTokenRefresher(
                new org.springframework.beans.factory.support.StaticListableBeanFactory(java.util.Map.of("registrations", registrations))
                        .getBeanProvider(ClientRegistrationRepository.class),
                new ObjectMapper(), HttpClient.newHttpClient(),
                Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @AfterEach
    void stop() {
        server.stop(0);
    }

    @Test
    @DisplayName("TC-MCR-LINK-021: sends grant_type=refresh_token with HTTP Basic client credentials and returns the new tokens")
    void refreshes() {
        responseBody = "{\"access_token\":\"new-access\",\"expires_in\":3600,\"refresh_token\":\"new-refresh\",\"token_type\":\"Bearer\"}";

        final MedicareTokenRefresher.Result result = refresher.refresh("old/refresh+token");

        assertThat(result).isEqualTo(new MedicareTokenRefresher.Refreshed("new-access", NOW.plusSeconds(3600), "new-refresh"));
        assertThat(URLDecoder.decode(requestBody.get(), StandardCharsets.UTF_8))
                .isEqualTo("grant_type=refresh_token&refresh_token=old/refresh+token");
        assertThat(authorization.get()).isEqualTo("Basic " + Base64.getEncoder()
                .encodeToString("client-id:client-secret".getBytes(StandardCharsets.UTF_8)));
    }

    @Test
    @DisplayName("TC-MCR-LINK-022: a response without a new refresh token or expiry still refreshes")
    void refreshWithoutRotation() {
        responseBody = "{\"access_token\":\"new-access\"}";

        assertThat(refresher.refresh("old")).isEqualTo(new MedicareTokenRefresher.Refreshed("new-access", null, null));
    }

    @Test
    @DisplayName("TC-MCR-LINK-023: 400 invalid_grant is Rejected: the grant is gone and the patient must link again")
    void invalidGrantIsRejected() {
        status = 400;
        responseBody = "{\"error\":\"invalid_grant\"}";

        assertThat(refresher.refresh("old")).isEqualTo(new MedicareTokenRefresher.Rejected(400));
    }

    @Test
    @DisplayName("TC-MCR-LINK-024: a server error is Failed, not Rejected, so the stored tokens are kept")
    void serverErrorIsFailed() {
        status = 503;

        assertThat(refresher.refresh("old")).isInstanceOf(MedicareTokenRefresher.Failed.class);
    }

    @Test
    @DisplayName("TC-MCR-LINK-025: a 200 without an access token is Failed")
    void missingAccessTokenIsFailed() {
        responseBody = "{\"token_type\":\"Bearer\"}";

        assertThat(refresher.refresh("old")).isInstanceOf(MedicareTokenRefresher.Failed.class);
    }
}
