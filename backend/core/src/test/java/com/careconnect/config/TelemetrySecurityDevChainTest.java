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
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * HTTP-boundary tests for the telemetry ingest matcher on the {@code dev} filter chain, as
 * modified by PR #63 commit {@code 6f38c103}.
 *
 * <p>Test IDs TC-TEL-26 and TC-TEL-27 are permanent. Never renumber, never reuse.
 *
 * <p>{@code 6f38c103} changed {@code POST /v1/api/dev/telemetry} from {@code permitAll()} to
 * {@code .authenticated()} in {@link SecurityConfig}. That matcher lives on {@code devChain},
 * which declares {@code securityMatcher("/v1/api/dev/**")} and never registers a
 * {@code JwtAuthenticationFilter} - only {@code apiChain} builds one. No request routed to that
 * chain can therefore carry an {@code Authentication}, so the matcher is not "requires a token",
 * it is an unconditional 401. That is DEF-TEL-17.
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
     * TC-TEL-26 - an unauthenticated POST is rejected with 401.
     *
     * <p>Documents the regression rather than asserting it is correct. The Flutter client sends no
     * Authorization header (ApiService.sendTelemetryEventV3, api_service.dart:814-822) and emits
     * session_start before any login (main.dart:225), so this status is what the production client
     * now receives for every event. PR #25 TC-TEL-ING-001 asserts 200 for this same request.
     */
    @Test
    @DisplayName("TC-TEL-26: anonymous POST /v1/api/dev/telemetry is rejected 401 [DEF-TEL-17]")
    void tcTel26_anonymousIngestIsRejected() throws Exception {
        mockMvc.perform(post("/v1/api/dev/telemetry")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(CLIENT_PAYLOAD))
                .andExpect(status().isUnauthorized());

        verify(telemetryService, never()).record(any(TelemetryEvent.class));
    }

    /**
     * TC-TEL-27 - EXPECTED-FAIL. A caller presenting a valid admin bearer token must be accepted.
     *
     * <p>This is the case that separates an authorization decision from a wiring defect. If
     * {@code .authenticated()} were a deliberate policy, a valid token would satisfy it. It does
     * not: devChain never registers a JwtAuthenticationFilter, so the header is never read and the
     * request is anonymous by the time the authorization manager sees it. Expect 401 today.
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
