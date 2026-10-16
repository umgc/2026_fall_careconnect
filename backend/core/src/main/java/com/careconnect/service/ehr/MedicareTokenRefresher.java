package com.careconnect.service.ehr;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;

/**
 * Exchanges a stored Blue Button refresh token for a new access token (RFC 6749 §6), so a linked
 * patient keeps working past the one-hour access token without signing in again (STP-M3-E-12).
 * Refresh tokens are issued because the sandbox app is registered for 13-month access.
 * <p>
 * The token endpoint, client id and secret come from the {@code medicare} client registration, the
 * same ones Spring used for the original sign-in, and the client authenticates with HTTP Basic as it
 * did then. Nothing here logs a token.
 */
@Slf4j
@Component
public class MedicareTokenRefresher {

    private static final Duration TIMEOUT = Duration.ofSeconds(10);

    /** The outcome of one refresh attempt. */
    public sealed interface Result permits Refreshed, Rejected, Failed {
    }

    /** New tokens. {@code refreshToken} is null when the server did not rotate it. */
    public record Refreshed(String accessToken, Instant expiresAt, String refreshToken) implements Result {
    }

    /** The grant is no longer valid (revoked, expired, or the 13 months ran out): link again. */
    public record Rejected(int status) implements Result {
    }

    /** Could not tell: network error or server error. The stored tokens are left alone. */
    public record Failed(String reason) implements Result {
    }

    private final ObjectProvider<ClientRegistrationRepository> registrations;
    private final ObjectMapper json;
    private final HttpClient http;
    private final Clock clock;

    @Autowired
    public MedicareTokenRefresher(final ObjectProvider<ClientRegistrationRepository> registrations, final ObjectMapper json) {
        this(registrations, json, HttpClient.newBuilder().connectTimeout(TIMEOUT).build(), Clock.systemUTC());
    }

    MedicareTokenRefresher(
            final ObjectProvider<ClientRegistrationRepository> registrations,
            final ObjectMapper json,
            final HttpClient http,
            final Clock clock) {
        this.registrations = registrations;
        this.json = json;
        this.http = http;
        this.clock = clock;
    }

    public Result refresh(final String refreshToken) {
        final ClientRegistrationRepository repository = registrations.getIfAvailable();
        final ClientRegistration registration = repository == null
                ? null
                : repository.findByRegistrationId(MedicareConnectionService.REGISTRATION_ID);
        if (registration == null) {
            return new Failed("no '" + MedicareConnectionService.REGISTRATION_ID + "' client registration");
        }
        final String credentials = Base64.getEncoder().encodeToString(
                (registration.getClientId() + ":" + registration.getClientSecret()).getBytes(StandardCharsets.UTF_8));
        final HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(registration.getProviderDetails().getTokenUri()))
                .timeout(TIMEOUT)
                .header("Content-Type", "application/x-www-form-urlencoded")
                .header("Accept", "application/json")
                .header("Authorization", "Basic " + credentials)
                .POST(HttpRequest.BodyPublishers.ofString("grant_type=refresh_token&refresh_token="
                        + URLEncoder.encode(refreshToken, StandardCharsets.UTF_8)))
                .build();
        try {
            final HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
            final int status = response.statusCode();
            if (status == 400 || status == 401) {
                // RFC 6749 §5.2: invalid_grant, or the client itself rejected. Either way, link again.
                return new Rejected(status);
            }
            if (status != 200) {
                return new Failed("token endpoint returned HTTP " + status);
            }
            final JsonNode body = json.readTree(response.body());
            final String accessToken = text(body, "access_token");
            if (accessToken == null) {
                return new Failed("token response had no access_token");
            }
            final Instant expiresAt = body.hasNonNull("expires_in")
                    ? clock.instant().plusSeconds(body.get("expires_in").asLong())
                    : null;
            return new Refreshed(accessToken, expiresAt, text(body, "refresh_token"));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return new Failed("interrupted");
        } catch (Exception e) {
            return new Failed(e.getClass().getSimpleName());
        }
    }

    private static String text(final JsonNode body, final String field) {
        final JsonNode node = body.get(field);
        return node == null || node.isNull() || node.asText().isBlank() ? null : node.asText();
    }
}
