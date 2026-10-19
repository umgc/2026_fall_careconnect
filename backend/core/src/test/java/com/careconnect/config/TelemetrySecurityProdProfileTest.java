package com.careconnect.config;

import com.careconnect.controller.TelemetryController;
import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.TelemetryEvent;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.service.TelemetryService;
import com.careconnect.service.TelemetryToggleService;
import com.careconnect.util.SecurityUtil;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan.Filter;
import org.springframework.context.annotation.FilterType;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.core.env.Environment;
import org.springframework.http.MediaType;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * HTTP-boundary regression tests for telemetry under the production profile.
 *
 * <p>These tests deliberately use the real {@link SecurityConfig}. They prove that the
 * telemetry controller is registered outside development and that anonymous ingestion does
 * not expose the administrative toggle or recent-event endpoints.
 */
@WebMvcTest(
        controllers = TelemetryController.class,
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
@Import({SecurityConfig.class, TelemetrySecurityProdProfileTest.TestConfig.class})
@ActiveProfiles("prod")
class TelemetrySecurityProdProfileTest {

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

    @Autowired
    private Environment environment;

    @MockitoBean
    private JwtTokenProvider jwtTokenProvider;

    @MockitoBean
    private UserDetailsService userDetailsService;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private AuthorizationService authorizationService;

    @MockitoBean
    private TelemetryService telemetryService;

    @MockitoBean
    private TelemetryToggleService toggleService;

    @BeforeEach
    void setUp() {
        when(toggleService.isEnabled()).thenReturn(true);
        when(toggleService.setEnabled(false)).thenReturn(false);

        final TelemetryEvent savedEvent = new TelemetryEvent();
        savedEvent.setEventName("screen_view");
        when(telemetryService.record(any(TelemetryEvent.class))).thenReturn(savedEvent);
        when(telemetryService.recent(10)).thenReturn(List.of(savedEvent));
    }

    /** TC-TEL-ING-001 — production profile registers the anonymous ingestion endpoint. */
    @Test
    void productionProfileRegistersAnonymousIngestionEndpoint() throws Exception {
        assertThat(environment.getActiveProfiles()).containsExactly("prod");

        mockMvc.perform(post("/v1/api/dev/telemetry")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "eventName": "screen_view",
                                  "details": {"screen": "home"}
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.eventName").value("screen_view"));

        verify(telemetryService).record(any(TelemetryEvent.class));
    }

    /** TC-TEL-ING-002 — anonymous caller can read the enabled state. */
    @Test
    void anonymousCallerCanReadEnabledState() throws Exception {
        mockMvc.perform(get("/v1/api/dev/telemetry/enabled"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.enabled").value(true));
    }

    /** TC-TEL-ING-003 — negative authorization: anonymous caller reaches no admin surface. */
    @Test
    void anonymousCallerCannotChangeToggleOrReadRecentEvents() throws Exception {
        mockMvc.perform(put("/v1/api/dev/telemetry/enabled").param("enabled", "false"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/v1/api/dev/telemetry/recent").param("limit", "10"))
                .andExpect(status().isUnauthorized());

        verify(toggleService, never()).setEnabled(false);
        verify(telemetryService, never()).recent(10);
    }

    /** TC-TEL-ING-004 — negative authorization: authenticated non-admin reaches no admin surface. */
    @Test
    void nonAdminCallerCannotChangeToggleOrReadRecentEvents() throws Exception {
        mockMvc.perform(put("/v1/api/dev/telemetry/enabled")
                        .param("enabled", "false")
                        .with(user("caregiver@test.invalid").roles("CAREGIVER")))
                .andExpect(status().isForbidden());
        mockMvc.perform(get("/v1/api/dev/telemetry/recent")
                        .param("limit", "10")
                        .with(user("caregiver@test.invalid").roles("CAREGIVER")))
                .andExpect(status().isForbidden());

        verify(toggleService, never()).setEnabled(false);
        verify(telemetryService, never()).recent(10);
    }

    /** TC-TEL-ING-005 — admin caller can change the toggle and read recent events. */
    @Test
    void adminCallerCanChangeToggleAndReadRecentEvents() throws Exception {
        mockMvc.perform(put("/v1/api/dev/telemetry/enabled")
                        .param("enabled", "false")
                        .with(user("admin@test.invalid").roles("ADMIN")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.enabled").value(false));
        mockMvc.perform(get("/v1/api/dev/telemetry/recent")
                        .param("limit", "10")
                        .with(user("admin@test.invalid").roles("ADMIN")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].eventName").value("screen_view"));

        verify(toggleService).setEnabled(false);
        verify(telemetryService).recent(10);
    }
}
