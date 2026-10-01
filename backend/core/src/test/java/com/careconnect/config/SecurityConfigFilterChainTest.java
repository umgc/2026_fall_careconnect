package com.careconnect.config;

import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.util.SecurityUtil;
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
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Base64;
import java.util.List;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
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
    void publicAuthEndpoint_IsAccessible() throws Exception {
        // Verifies that /v1/api/auth/** is permit-all: the JWT filter skips these
        // paths (shouldNotFilter returns true) and security allows the request through.
        mockMvc.perform(get("/v1/api/auth/ping"))
                .andExpect(status().isOk());
    }

    @Test
    void protectedEndpoint_RequiresAuthentication() throws Exception {
        // Verifies that /v1/api/patients/** requires a valid JWT; without one the
        // exceptionHandling authenticationEntryPoint sends SC_UNAUTHORIZED (401).
        mockMvc.perform(get("/v1/api/patients/ping"))
                .andExpect(status().isUnauthorized());
    }

    // -------------------------------------------------
    // 1. Public auth endpoint → 200 (permitAll)
    // -------------------------------------------------

    @Test
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
    void swaggerDocsPath_IsPermittedBySecurityNotBlocked() throws Exception {
        // Verifies that /v3/api-docs is on the permit-all list: security passes
        // the request through and MockMvc returns 404 (no registered handler)
        // rather than 401 (security rejection).
        mockMvc.perform(get("/v3/api-docs"))
                .andExpect(status().isNotFound());
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
    }
}
