package com.careconnect.config;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link WebConfig}.
 * <p>
 * WebConfig is a Spring {@code @Configuration} class that exposes a
 * {@link WebMvcConfigurer} bean responsible for registering MVC-level CORS mappings.
 * These mappings allow the frontend (running on localhost development ports) to make
 * credentialed cross-origin requests to the backend.
 * <p>
 * In {@code setUp}, the configurer is exercised by invoking
 * {@code addCorsMappings(CorsRegistry)} on a real {@link CorsRegistry} instance.
 * The resulting {@link CorsConfiguration} is extracted from the registry via
 * {@link ReflectionTestUtils#invokeMethod} (the internal map is not publicly exposed),
 * then individual assertions are made per test for clarity and isolation.
 */
class WebConfigTest {

    private WebMvcConfigurer corsConfigurer;
    private CorsConfiguration config;

    @SuppressWarnings("unchecked")
    @BeforeEach
    void setUp() throws Exception {
        // Build the configurer bean and drive addCorsMappings() to populate a real
        // CorsRegistry, then extract the resulting CorsConfiguration for "/**"
        // using ReflectionTestUtils because getCorsConfigurations() is package-private.
        final WebConfig webConfig = new WebConfig();
        corsConfigurer = webConfig.corsConfigurer();

        final CorsRegistry registry = new CorsRegistry();
        corsConfigurer.addCorsMappings(registry);

        final Map<String, CorsConfiguration> configs =
                (Map<String, CorsConfiguration>) ReflectionTestUtils.invokeMethod(registry, "getCorsConfigurations");
        config = configs.get("/**");
    }

    @Test
    void corsConfigurer_IsNotNull() throws Exception {
        // Verifies that corsConfigurer() returns a non-null WebMvcConfigurer bean.
        assertNotNull(corsConfigurer);
    }

    @Test
    void corsConfigurer_MapsAllPaths() throws Exception {
        // Verifies that a CORS configuration is registered under the "/**" wildcard,
        // meaning all application paths are subject to the CORS policy.
        assertNotNull(config, "Expected CORS configuration for '/**' path mapping");
    }

    @Test
    void corsConfigurer_HasCorrectAllowedOrigins() throws Exception {
        // Verifies that the five explicit localhost origins (covering common dev ports
        // and both hostname variants) are all present in the allowed-origins list.
        final List<String> expected = List.of(
                "http://localhost:8080",
                "http://127.0.0.1:8080",
                "http://localhost:5173",
                "http://localhost",
                "http://127.0.0.1"
        );
        assertEquals(expected, config.getAllowedOrigins());
    }

    @Test
    void corsConfigurer_HasCorrectAllowedOriginPatterns() throws Exception {
        // Verifies that wildcard port patterns are registered in addition to the
        // explicit origins, allowing any port on localhost or 127.0.0.1 (e.g. for
        // dev servers that pick a random port).
        final List<String> patterns = config.getAllowedOriginPatterns();
        assertNotNull(patterns);
        assertTrue(patterns.contains("http://localhost:*"));
        assertTrue(patterns.contains("http://127.0.0.1:*"));
        assertEquals(2, patterns.size());
    }

    @Test
    void corsConfigurer_AllowsCorrectMethods() throws Exception {
        // Verifies that the standard RESTful HTTP methods plus OPTIONS (for browser
        // preflight requests) are all permitted by the CORS policy.
        final List<String> methods = config.getAllowedMethods();
        assertNotNull(methods);
        assertTrue(methods.containsAll(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS")));
        assertEquals(5, methods.size());
    }

    @Test
    void corsConfigurer_AllowsCredentials() throws Exception {
        // Verifies that credentialed requests (carrying cookies or Authorization headers)
        // are permitted, which is required for JWT cookie-based authentication.
        assertTrue(config.getAllowCredentials());
    }
}
