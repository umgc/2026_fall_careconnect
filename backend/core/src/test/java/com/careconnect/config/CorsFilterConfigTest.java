package com.careconnect.config;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link CorsFilterConfig}.
 * <p>
 * CorsFilterConfig produces a Spring Security {@code CorsConfigurationSource} bean that
 * controls which origins, methods, and headers are allowed for cross-origin requests.
 * <p>
 * The class reads allowed origins from a {@code @Value}-injected list, which Spring does
 * not populate when the object is instantiated directly (outside a Spring context).
 * {@link ReflectionTestUtils#setField} is therefore used in {@code setUp} to inject a
 * controlled list of origins, keeping these tests fast and free of a full application
 * context while still exercising the real configuration logic.
 */
class CorsFilterConfigTest {

    private CorsFilterConfig corsFilterConfig;

    @BeforeEach
    void setUp() throws Exception {
        corsFilterConfig = new CorsFilterConfig();

        // Inject allowed origins manually (since @Value won't run without a Spring context)
        ReflectionTestUtils.setField(
                corsFilterConfig,
                "allowedOrigins",
                List.of("http://localhost:3000", "https://careconnect.com")
        );
    }

    @Test
    void corsConfigurationSource_IsCreated() throws Exception {
        // Verifies that corsFilter() returns a non-null UrlBasedCorsConfigurationSource,
        // which is the expected concrete type used to map CORS rules to URL patterns.
        final CorsConfigurationSource source = corsFilterConfig.corsFilter();
        assertNotNull(source);
        assertTrue(source instanceof UrlBasedCorsConfigurationSource);
    }

    @Test
    void corsConfiguration_HasCorrectAllowedOrigins() throws Exception {
        // Verifies that the injected origins are registered as allowed origin patterns
        // on the CORS configuration mapped to "/**" (all paths).
        final CorsConfigurationSource source = corsFilterConfig.corsFilter();
        final UrlBasedCorsConfigurationSource urlSource =
                (UrlBasedCorsConfigurationSource) source;

        final CorsConfiguration config =
                urlSource.getCorsConfigurations().get("/**");

        assertNotNull(config);
        assertEquals(
                List.of("http://localhost:3000", "https://careconnect.com"),
                config.getAllowedOriginPatterns()
        );
    }

    @Test
    void corsConfiguration_AllowsCredentials() throws Exception {
        // Verifies that credentials (cookies, Authorization headers) are permitted,
        // which is required for JWT cookie-based authentication flows.
        final UrlBasedCorsConfigurationSource source =
                (UrlBasedCorsConfigurationSource) corsFilterConfig.corsFilter();

        final CorsConfiguration config =
                source.getCorsConfigurations().get("/**");

        assertTrue(config.getAllowCredentials());
    }

    @Test
    void corsConfiguration_AllowsAllHeaders() throws Exception {
        // Verifies that both allowedHeaders and exposedHeaders are set to "*", meaning
        // any request header is accepted and any response header is visible to the client.
        final UrlBasedCorsConfigurationSource source =
                (UrlBasedCorsConfigurationSource) corsFilterConfig.corsFilter();

        final CorsConfiguration config =
                source.getCorsConfigurations().get("/**");

        assertEquals(List.of("*"), config.getAllowedHeaders());
        assertEquals(List.of("*"), config.getExposedHeaders());
    }

    @Test
    void corsConfiguration_HasCorrectAllowedMethods() throws Exception {
        // Verifies that the five standard HTTP methods required by the API are listed,
        // including OPTIONS which is needed for preflight CORS requests from browsers.
        final UrlBasedCorsConfigurationSource source =
                (UrlBasedCorsConfigurationSource) corsFilterConfig.corsFilter();

        final CorsConfiguration config =
                source.getCorsConfigurations().get("/**");

        assertEquals(
                List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"),
                config.getAllowedMethods()
        );
    }

    @Test
    void corsConfiguration_IsRegisteredForAllPaths() throws Exception {
        // Verifies that the CORS policy is applied globally (mapped to "/**"),
        // ensuring no endpoint is inadvertently left without CORS protection.
        final UrlBasedCorsConfigurationSource source =
                (UrlBasedCorsConfigurationSource) corsFilterConfig.corsFilter();

        assertTrue(source.getCorsConfigurations().containsKey("/**"));
    }
}
