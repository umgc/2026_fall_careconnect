package com.careconnect.config;

import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.util.SecurityUtil;
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
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Base64;
import java.util.List;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Integration tests for {@link SecurityConfig#filterChain}.
 *
 * <p>Uses {@code @WebMvcTest} to spin up a minimal Spring Security context with
 * the real {@link SecurityConfig} imported. Two infrastructure concerns are handled:
 * <ul>
 *   <li>{@link CorsConfigurationSource} is provided as a concrete {@code @Primary}
 *       bean in {@link TestConfig} — mocking it replaces the internal
 *       {@code mvcHandlerMappingIntrospector} bean that also implements the interface,
 *       breaking the Spring MVC context.</li>
 *   <li>{@link GlobalExceptionHandler} is excluded from component scanning because its
 *       catch-all {@code @ExceptionHandler(Exception.class)} intercepts Spring MVC's
 *       own {@code NoResourceFoundException} handling, turning expected 404s into 500s
 *       and masking security-permit assertions.</li>
 * </ul>
 *
 * <p>{@link PingController} is registered explicitly via {@link TestConfig} rather than
 * relying on component scanning, which does not reliably pick up static inner classes
 * of test types in the {@code @WebMvcTest} slice.
 *
 * <p>Spring instantiates the {@code SecurityFilterChain} bean during context startup,
 * invoking {@code filterChain()} and all its inner {@code Customizer} lambdas (CSRF,
 * CORS, session management, HTTP Basic entry-point, exception handling, and the full
 * {@code authorizeHttpRequests} block). The HTTP-request tests then cover the two
 * {@code AuthenticationEntryPoint} lambdas that only fire on actual rejected requests.
 *
 * <p>Test Plan: TC-SEC-001…005 (inherited, §3.24.3) and TC-EMG-102…104, 124 (CC-12 passport
 * scan, §3.24.3). Test IDs are permanent. Never renumber, never reuse.
 */
@WebMvcTest(
        controllers = {SecurityConfigFilterChainTest.PingController.class},
        excludeFilters = @Filter(
                type = FilterType.ASSIGNABLE_TYPE,
                classes = GlobalExceptionHandler.class))
@Import({SecurityConfig.class, SecurityConfigFilterChainTest.TestConfig.class})
class SecurityConfigFilterChainTest {

    @Autowired
    MockMvc mockMvc;
    @MockitoBean
    JwtTokenProvider jwtTokenProvider;
    @MockitoBean
    UserDetailsService userDetailsService;
    @MockitoBean
    private SecurityUtil securityUtil;
    @MockitoBean
    private AuthorizationService authorizationService;

    @BeforeEach
    void setUp() throws Exception {
        // Ensure Basic-auth attempts always fail so the httpBasic entry-point fires.
        when(userDetailsService.loadUserByUsername(anyString()))
                .thenThrow(new UsernameNotFoundException("User not found"));
    }

    @Test
    @DisplayName("TC-SEC-001: /v1/api/auth/** is public: an unauthenticated request reaches the handler")
    void publicAuthEndpoint_IsAccessible() throws Exception {
        // Verifies that /v1/api/auth/** is permit-all: the JWT filter skips these
        // paths (shouldNotFilter returns true) and security allows the request through.
        mockMvc.perform(get("/v1/api/auth/ping"))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("TC-SEC-002: a protected path without credentials is 401")
    void protectedEndpoint_RequiresAuthentication() throws Exception {
        // Verifies that /v1/api/patients/** requires a valid JWT; without one the
        // exceptionHandling authenticationEntryPoint sends SC_UNAUTHORIZED (401).
        mockMvc.perform(get("/v1/api/patients/ping"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void epicCallback_IsAccessibleWithoutJwt() throws Exception {
        // The external Epic SMART redirect cannot carry the application's JWT.
        // The callback instead validates its signed, single-use state in the
        // controller flow, so this narrowly scoped endpoint must precede the
        // authenticated /api/** catch-all.
        mockMvc.perform(get("/api/epic/callback"))
                .andExpect(status().isOk());
    }

    @Test
    void otherEpicEndpoints_RequireAuthentication() throws Exception {
        // Only the callback is public; the general /api/** matcher protects
        // all remaining Epic endpoints.
        mockMvc.perform(get("/api/epic/protected"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void oracleHealthCallback_IsAccessibleWithoutJwt() throws Exception {
        // Oracle Health redirects the user's browser here and therefore cannot
        // provide the CareConnect JWT. Signed, single-use OAuth state protects
        // this callback in the controller flow.
        mockMvc.perform(get("/api/oracle-health/callback"))
                .andExpect(status().isOk());
    }

    @Test
    void otherOracleHealthEndpoints_RequireAuthentication() throws Exception {
        // Keep the exception narrowly scoped: starting, inspecting, or removing
        // a connection still requires an authenticated CareConnect user.
        mockMvc.perform(get("/api/oracle-health/authorize"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/oracle-health/status"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(post("/api/oracle-health/disconnect"))
                .andExpect(status().isUnauthorized());
    }

    // -------------------------------------------------
    // 1. Public auth endpoint → 200 (permitAll)
    // -------------------------------------------------

    @Test
    @DisplayName("TC-SEC-003: a path no matcher covers is denied (401 for an unauthenticated caller)")
    void unmatchedEndpoint_IsDeniedWithUnauthorized() throws Exception {
        // Verifies the anyRequest().denyAll() catch-all: unauthenticated requests
        // to paths not covered by any matcher also hit the exceptionHandling
        // authenticationEntryPoint (401 rather than 403 for unauthenticated callers).
        mockMvc.perform(get("/completely/unknown/path"))
                .andExpect(status().isUnauthorized());
    }

    // -------------------------------------------------
    // 2. Protected endpoint without credentials → 401
    // -------------------------------------------------

    @Test
    @DisplayName("TC-SEC-004: wrong HTTP Basic credentials on a protected path are 401 from the Basic entry point")
    void invalidBasicAuth_TriggersHttpBasicEntryPoint() throws Exception {
        // Sends an Authorization: Basic header with wrong credentials against a
        // protected path. Spring Security's BasicAuthenticationFilter processes it,
        // userDetailsService throws UsernameNotFoundException → BadCredentialsException,
        // and the httpBasic authenticationEntryPoint fires (401).
        final String invalidCreds = Base64.getEncoder()
                .encodeToString("user:wrongpassword".getBytes());
        mockMvc.perform(get("/v1/api/patients/ping")
                        .header("Authorization", "Basic " + invalidCreds))
                .andExpect(status().isUnauthorized());
    }

    // -------------------------------------------------
    // 3. Unmatched path → anyRequest().denyAll() → 401
    // -------------------------------------------------

    @Test
    @DisplayName("TC-SEC-005: /v3/api-docs is public: security lets it through (404, no handler in the slice)")
    void swaggerDocsPath_IsPermittedBySecurityNotBlocked() throws Exception {
        // Verifies that /v3/api-docs is on the permit-all list: security passes
        // the request through and MockMvc returns 404 (no registered handler)
        // rather than 401 (security rejection).
        mockMvc.perform(get("/v3/api-docs"))
                .andExpect(status().isNotFound());
    }

    // -------------------------------------------------
    // 6. CC-12 passport scan: only GET on one segment is public
    // -------------------------------------------------

    @Test
    @DisplayName("TC-EMG-102: GET /v1/api/passport/scan/{token} is public: security lets it through (404, no handler in the slice)")
    void passportScan_IsPermittedBySecurityNotBlocked() throws Exception {
        // No handler is registered in this slice, so a permitted request is 404, not 401.
        mockMvc.perform(get("/v1/api/passport/scan/someCode"))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("TC-EMG-103: the patient's own passport endpoints are 401 without sign-in")
    void passportOwnerEndpoints_RequireAuthentication() throws Exception {
        mockMvc.perform(get("/v1/api/passport"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(post("/v1/api/passport/token"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("TC-EMG-104: POST on the scan path and a deeper scan path are not public (401)")
    void passportScan_OtherMethodsAndDeeperPaths_RequireAuthentication() throws Exception {
        mockMvc.perform(post("/v1/api/passport/scan/someCode"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/v1/api/passport/scan/someCode/extra"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("TC-EMG-124: PUT and DELETE on the scan path are not public (401)")
    void passportScan_PutAndDelete_RequireAuthentication() throws Exception {
        mockMvc.perform(put("/v1/api/passport/scan/someCode"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(delete("/v1/api/passport/scan/someCode"))
                .andExpect(status().isUnauthorized());
    }

    // -------------------------------------------------
    // 4. Invalid HTTP Basic auth → httpBasic entry-point → 401
    // -------------------------------------------------

    /**
     * Supplies a concrete {@link CorsConfigurationSource} (to avoid replacing the
     * {@code mvcHandlerMappingIntrospector} bean) and registers {@link PingController}
     * as an explicit bean so its handler mappings are available to MockMvc.
     */
    @TestConfiguration
    static class TestConfig {

        @Bean
        @Primary
        CorsConfigurationSource testCorsConfigurationSource() throws Exception {
            final CorsConfiguration cfg = new CorsConfiguration();
            cfg.setAllowedOrigins(List.of("*"));
            cfg.setAllowedMethods(List.of("*"));
            cfg.setAllowedHeaders(List.of("*"));
            final UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
            source.registerCorsConfiguration("/**", cfg);
            return source;
        }

        @Bean
        PingController pingController() throws Exception {
            return new PingController();
        }
    }

    // -------------------------------------------------
    // 5. Swagger path → permitAll → not blocked by security (404 no handler)
    // -------------------------------------------------

    /**
     * Minimal controller used to verify permit-all paths return 200 and
     * protected paths are blocked at 401 by the security filter chain.
     */
    @RestController
    static class PingController {

        @GetMapping("/v1/api/auth/ping")
        String publicPing() throws Exception {
            return "ok";
        }

        @GetMapping("/v1/api/patients/ping")
        String protectedPing() throws Exception {
            return "ok";
        }

        @GetMapping("/api/epic/callback")
        String epicCallback() {
            return "ok";
        }

        @GetMapping("/api/epic/protected")
        String protectedEpicEndpoint() {
            return "ok";
        }

        @GetMapping("/api/oracle-health/callback")
        String oracleHealthCallback() {
            return "ok";
        }

        @GetMapping("/api/oracle-health/authorize")
        String protectedOracleHealthAuthorize() {
            return "ok";
        }

        @GetMapping("/api/oracle-health/status")
        String protectedOracleHealthStatus() {
            return "ok";
        }

        @PostMapping("/api/oracle-health/disconnect")
        String protectedOracleHealthDisconnect() {
            return "ok";
        }
    }
}
