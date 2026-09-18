package com.careconnect.config;

import jakarta.servlet.ServletContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationContext;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;

/**
 * Unit tests for {@link WebMvcConfig}.
 * <p>
 * WebMvcConfig is a Spring {@link org.springframework.web.servlet.config.annotation.WebMvcConfigurer}
 * that configures two concerns:
 * <ol>
 *   <li><b>CORS mappings</b> — allows specific origins (local dev ports and deployed
 *       Amplify/GitHub Pages frontends) to make credentialed cross-origin requests.</li>
 *   <li><b>Static resource handler</b> — serves uploaded files from a local filesystem
 *       path under the {@code /uploads/**} URL pattern.</li>
 * </ol>
 * <p>
 * CORS configuration is extracted from a real {@link CorsRegistry} via
 * {@link ReflectionTestUtils#invokeMethod} (the map is not public API).
 * Resource handler registrations are similarly extracted from a {@link ResourceHandlerRegistry}
 * via {@link ReflectionTestUtils#getField} because the registry does not expose a
 * public accessor — both are Spring-internal details that reflection safely reaches
 * in a test context.
 */
class WebMvcConfigTest {

    private WebMvcConfig webMvcConfig;
    private CorsConfiguration corsConfig;

    @SuppressWarnings("unchecked")
    @BeforeEach
    void setUp() throws Exception {
        // Instantiate the config and drive addCorsMappings() against a real CorsRegistry.
        // Extract the resulting CorsConfiguration for "/**" using reflection since
        // getCorsConfigurations() is package-private on CorsRegistry.
        webMvcConfig = new WebMvcConfig();

        final CorsRegistry corsRegistry = new CorsRegistry();
        webMvcConfig.addCorsMappings(corsRegistry);

        final Map<String, CorsConfiguration> configs =
                (Map<String, CorsConfiguration>) ReflectionTestUtils.invokeMethod(corsRegistry, "getCorsConfigurations");
        corsConfig = configs.get("/**");
    }

    // --- CORS Tests ---

    @Test
    void addCorsMappings_MapsAllPaths() throws Exception {
        // Verifies that the CORS configuration is registered under "/**" so every
        // endpoint is covered by the policy.
        assertNotNull(corsConfig, "Expected CORS configuration for '/**' path mapping");
    }

    @Test
    void addCorsMappings_HasCorrectAllowedOriginPatterns() throws Exception {
        // Verifies that exactly the four expected origins are allowed:
        // the local dev server (port 50030 and 3000), the Amplify staging URL, and
        // the GitHub Pages URL for the deployed demo site.
        final List<String> patterns = corsConfig.getAllowedOriginPatterns();
        assertNotNull(patterns);
        assertTrue(patterns.contains("http://localhost:50030"));
        assertTrue(patterns.contains("http://localhost:3000"));
        assertTrue(patterns.contains("https://care-connect-develop.d26kqsucj1bwc1.amplifyapp.com"));
        assertTrue(patterns.contains("https://isabel-santiagolewis.github.io"));
        assertEquals(4, patterns.size());
    }

    @Test
    void addCorsMappings_AllowsCorrectMethods() throws Exception {
        // Verifies the five HTTP methods (including OPTIONS for CORS preflight) are permitted.
        final List<String> methods = corsConfig.getAllowedMethods();
        assertNotNull(methods);
        assertTrue(methods.containsAll(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS")));
        assertEquals(5, methods.size());
    }

    @Test
    void addCorsMappings_AllowsAllHeaders() throws Exception {
        // Verifies that any request header is accepted ("*"), so clients can send
        // custom headers (e.g. Authorization, Content-Type) without being rejected.
        assertEquals(List.of("*"), corsConfig.getAllowedHeaders());
    }

    @Test
    void addCorsMappings_AllowsCredentials() throws Exception {
        // Verifies that credentialed cross-origin requests (cookies, auth headers) are
        // permitted, which is required for session-based and JWT cookie authentication.
        assertTrue(corsConfig.getAllowCredentials());
    }

    // --- Resource Handler Tests ---

    /**
     * Helper that drives {@link WebMvcConfig#addResourceHandlers} against a real
     * {@link ResourceHandlerRegistry} and returns the internal list of registrations.
     * Mocked {@link ApplicationContext} and {@link ServletContext} are supplied because
     * the registry constructor requires them but does not use them in this code path.
     */
    @SuppressWarnings("unchecked")
    private List<ResourceHandlerRegistration> getRegistrations() throws Exception {
        final ResourceHandlerRegistry registry = new ResourceHandlerRegistry(
                mock(ApplicationContext.class), mock(ServletContext.class));
        webMvcConfig.addResourceHandlers(registry);
        return (List<ResourceHandlerRegistration>) ReflectionTestUtils.getField(registry, "registrations");
    }

    @Test
    void addResourceHandlers_RegistersOneHandler() throws Exception {
        // Verifies that exactly one resource handler is registered, preventing
        // accidental duplication or omission of the uploads handler.
        final List<ResourceHandlerRegistration> registrations = getRegistrations();
        assertNotNull(registrations);
        assertEquals(1, registrations.size());
    }

    @Test
    void addResourceHandlers_RegistersUploadsPattern() throws Exception {
        // Verifies that the handler is mapped to "/uploads/**", the URL prefix under
        // which uploaded user files (images, documents) are served.
        final List<ResourceHandlerRegistration> registrations = getRegistrations();
        final String[] patterns = (String[]) ReflectionTestUtils.getField(registrations.get(0), "pathPatterns");
        assertNotNull(patterns);
        assertEquals(1, patterns.length);
        assertEquals("/uploads/**", patterns[0]);
    }

    @Test
    @SuppressWarnings("unchecked")
    void addResourceHandlers_RegistersCorrectLocation() throws Exception {
        // Verifies that the handler serves files from the expected local filesystem path.
        // The "file:" prefix tells Spring to read from an absolute filesystem location
        // rather than the classpath.
        final List<ResourceHandlerRegistration> registrations = getRegistrations();
        final List<String> locationValues =
                (List<String>) ReflectionTestUtils.getField(registrations.get(0), "locationValues");
        assertNotNull(locationValues);
        assertEquals(1, locationValues.size());
        assertEquals("file:C:/Users/bompl/Documents/uploads/", locationValues.get(0));
    }
}
