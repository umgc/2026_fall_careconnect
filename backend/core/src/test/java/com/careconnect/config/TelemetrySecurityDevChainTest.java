package com.careconnect.config;

import com.careconnect.controller.dev.DevTelemetryController;
import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.TelemetryEvent;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.UserDetailsServiceImpl;
import com.careconnect.service.TelemetryService;
import com.careconnect.service.TelemetryToggleService;
import com.careconnect.util.SecurityUtil;
import io.jsonwebtoken.Claims;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan.Filter;
import org.springframework.context.annotation.FilterType;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * HTTP-boundary tests for the telemetry ingest matcher on the {@code dev} filter chain.
 *
 * <p>Test IDs TC-TEL-26 and TC-TEL-27 are permanent. Never renumber, never reuse.
 *
 * <p>Both cases were written 2026-08-29 against commit {@code 6f38c103}, which changed
 * {@code POST /v1/api/dev/telemetry} from {@code permitAll()} to {@code .authenticated()} in
 * {@link SecurityConfig}. That matcher lives on {@code devChain}, which declares
 * {@code securityMatcher("/v1/api/dev/**")} and never registers a {@code JwtAuthenticationFilter}
 * - only {@code apiChain} builds one. No request routed to that chain could therefore carry an
 * {@code Authentication}, so the matcher was not "requires a token", it was an unconditional 401.
 * That was DEF-TEL-17, and TC-TEL-27 was the expected-fail that proved it.
 *
 * <p>{@code 0139bd84} reverted {@code SecurityConfig.java:51} to {@code permitAll()}. Both cases
 * pass as of {@code d48358e6} and are retained as regression cover: TC-TEL-27 fails again if the
 * matcher is tightened without a filter behind it, and TC-TEL-26 fails if ingest is closed to the
 * anonymous client that actually calls it. TC-TEL-26 was amended 2026-09-01 from 401 to 200.
 *
 * <p>These tests deliberately use the real {@link SecurityConfig} and a real bearer token rather
 * than {@code SecurityMockMvcRequestPostProcessors.user(...)}. The post-processor injects an
 * Authentication straight into the SecurityContext and bypasses the filter chain entirely, so it
 * would report a pass and hide the defect. Only a credential that has to survive the chain proves
 * the wiring gap.
 *
 * <p>Executed by: Kristopher Bickmore (Testing Lead). PR author: MaximumVolts. Separation of duties
 * per CLAUDE.md is satisfied - the author is not the executor.
 */
@WebMvcTest(
        controllers = DevTelemetryController.class,
        excludeFilters = @Filter(
                type = FilterType.ASSIGNABLE_TYPE,
                classes = GlobalExceptionHandler.class),
        properties = {
            "careconnect.aws.enabled=false",
            "careconnect.ai.enabled=false",
            "careconnect.websocket.enabled=false",
            "careconnect.email.provider=console",
            "context.initializer.classes=",
            "spring.security.oauth2.client.registration.fitbit.client-id=stub",
            "spring.security.oauth2.client.registration.fitbit.client-secret=stub",
            "spring.security.oauth2.client.registration.fitbit.authorization-grant-type=authorization_code",
            "spring.security.oauth2.client.registration.fitbit.redirect-uri={baseUrl}/login/oauth2/code/fitbit",
            "spring.security.oauth2.client.registration.fitbit.scope=activity",
            "spring.security.oauth2.client.provider.fitbit.authorization-uri=https://www.fitbit.com/oauth2/authorize",
            "spring.security.oauth2.client.provider.fitbit.token-uri=https://api.fitbit.com/oauth2/token",
            "spring.security.oauth2.client.provider.fitbit.user-info-uri=https://api.fitbit.com/1/user/-/profile.json",
            "spring.security.oauth2.client.provider.fitbit.user-name-attribute=user_id",
            "spring.security.oauth2.client.registration.google.client-id=stub",
            "spring.security.oauth2.client.registration.google.client-secret=stub"
        })
@Import({SecurityConfig.class, TelemetrySecurityDevChainTest.TestConfig.class})
@ActiveProfiles("dev")
@DisplayName("Telemetry ingest authorization on the dev filter chain (PR #63)")
class TelemetrySecurityDevChainTest {

    /** A syntactically valid-looking bearer token; validity is decided by the mocked provider. */
    private static final String BEARER = "a.valid.looking.token";

    /** The exact body the Flutter client posts (telemetry.dart:151-164). */
    private static final String CLIENT_PAYLOAD = """
            {
              "eventName": "screen_view",
              "sessionId": "session-1",
              "traceId": "trace-1",
              "spanId": "span-1",
              "details": {"screen": "settings"},
              "deviceInfo": {
                "uiSurface": "web",
                "platform": "android",
                "isWeb": true,
                "debug": false
              }
            }
            """;

    @TestConfiguration
    static class TestConfig {

        @Bean
        @Primary
        CorsConfigurationSource testCorsConfigurationSource() {
            final CorsConfiguration configuration = new CorsConfiguration();
            configuration.setAllowedOrigins(List.of("*"));
            configuration.setAllowedMethods(List.of("*"));
            configuration.setAllowedHeaders(List.of("*"));
            final UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
            source.registerCorsConfiguration("/**", configuration);
            return source;
        }
    }

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private JwtTokenProvider jwtTokenProvider;

    @MockitoBean
    private UserDetailsServiceImpl userDetailsService;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private AuthorizationService authorizationService;

    @MockitoBean
    private TelemetryService telemetryService;

    @MockitoBean
    private TelemetryToggleService toggleService;

    @MockitoBean
    private Claims claims;

    @BeforeEach
    void setUp() {
        lenient().when(toggleService.isEnabled()).thenReturn(true);

        final TelemetryEvent savedEvent = new TelemetryEvent();
        savedEvent.setEventName("screen_view");
        lenient().when(telemetryService.record(any(TelemetryEvent.class))).thenReturn(savedEvent);

        // Stub the token as valid and resolvable. If a JwtAuthenticationFilter were registered on
        // the chain that serves /v1/api/dev/**, these stubs would authenticate the request.
        lenient().when(jwtTokenProvider.validateToken(BEARER)).thenReturn(true);
        lenient().when(jwtTokenProvider.getClaims(BEARER)).thenReturn(claims);
        lenient().when(claims.getSubject()).thenReturn("admin@test.invalid");
        lenient().when(claims.get("role", String.class)).thenReturn("ADMIN");

        final UserDetails admin = User.withUsername("admin@test.invalid")
                .password("n/a")
                .roles("ADMIN")
                .build();
        lenient().when(userDetailsService.loadUserByEmailAndRole(anyString(), anyString()))
                .thenReturn(admin);
        lenient().when(userDetailsService.loadUserByUsername(anyString())).thenReturn(admin);
    }

    /**
     * TC-TEL-26 - an unauthenticated POST is accepted.
     *
     * <p>Amended 2026-09-01. Written on 2026-08-29 asserting 401, to document the lockout
     * {@code 6f38c103} introduced. {@code 0139bd84} reverted {@code SecurityConfig.java:51} to
     * {@code permitAll()}, so 401 is no longer the expected result and the case is now a positive
     * one.
     *
     * <p>200 is the correct expectation, not merely the current behaviour. The Flutter client sends
     * no Authorization header (ApiService.sendTelemetryEventV3, api_service.dart:814-822) and emits
     * session_start before any login (main.dart:225), so an authenticated ingest path would drop
     * every pre-login event. The endpoint is defended by what it accepts - the TelemetryService
     * allowlist - not by who calls it. PR #25 TC-TEL-ING-001 asserts 200 for this same request; the
     * two branches now agree.
     */
    @Test
    @DisplayName("TC-TEL-26: anonymous POST /v1/api/dev/telemetry is accepted [DEF-TEL-17]")
    void tcTel26_anonymousIngestIsAccepted() throws Exception {
        mockMvc.perform(post("/v1/api/dev/telemetry")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(CLIENT_PAYLOAD))
                .andExpect(status().isOk());

        verify(telemetryService).record(any(TelemetryEvent.class));
    }

    /**
     * TC-TEL-27 - a caller presenting a valid admin bearer token is accepted.
     *
     * <p>This is the case that separated an authorization decision from a wiring defect. If
     * {@code .authenticated()} had been a deliberate policy, a valid token would have satisfied it.
     * It did not: devChain registers no JwtAuthenticationFilter, so the header was never read and
     * the request was anonymous by the time the authorization manager saw it. The case failed
     * {@code Status expected:<200> but was:<401>} at {@code 6f38c103} and passes from
     * {@code 0139bd84}, which restored {@code permitAll()}.
     */
    @Test
    @DisplayName("TC-TEL-27: POST with a valid admin bearer token is accepted [DEF-TEL-17]")
    void tcTel27_validBearerTokenIsAccepted() throws Exception {
        mockMvc.perform(post("/v1/api/dev/telemetry")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + BEARER)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(CLIENT_PAYLOAD))
                .andExpect(status().isOk());

        verify(telemetryService).record(any(TelemetryEvent.class));
    }
}
