package com.careconnect.config;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.servers.Server;
import io.swagger.v3.oas.annotations.info.Info;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.Configuration;

import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link OpenApiConfig}.
 * <p>
 * OpenApiConfig is a pure-annotation Spring configuration class: it carries no runtime
 * bean factory methods, only Springdoc/Swagger annotations ({@code @OpenAPIDefinition},
 * {@code @SecurityScheme}) that Springdoc reads at startup to generate the OpenAPI spec.
 * <p>
 * Because the contract is expressed entirely in annotations, these tests use the Java
 * Reflection API ({@code Class.getAnnotation}, {@code Class.getAnnotationsByType}) to
 * inspect the annotations at compile time without starting a Spring context. This is the
 * appropriate technique when there are no runtime beans to instantiate or mock.
 */
class OpenApiConfigTest {

    @Test
    void classHasConfigurationAnnotation() throws Exception {
        // Confirms that Spring recognises OpenApiConfig as a configuration class so that
        // the Springdoc library picks it up during component scanning.
        assertTrue(OpenApiConfig.class.isAnnotationPresent(Configuration.class));
    }

    @Test
    void openApiDefinitionAnnotationExists() throws Exception {
        // Confirms the @OpenAPIDefinition annotation is present, which is what tells
        // Springdoc to populate the OpenAPI document with the metadata defined below.
        assertTrue(OpenApiConfig.class.isAnnotationPresent(OpenAPIDefinition.class));
    }

    @Test
    void openApiDefinitionContainsCorrectMetadata() throws Exception {
        // Verifies the API title, version, description snippet, contact details, and
        // license information shown in the generated Swagger UI / OpenAPI JSON.
        final OpenAPIDefinition definition =
                OpenApiConfig.class.getAnnotation(OpenAPIDefinition.class);

        final Info info = definition.info();

        assertEquals("CareConnect Backend API", info.title());
        assertEquals("1.0.0", info.version());
        assertTrue(info.description().contains("CareConnect Backend API provides"));

        assertEquals("CareConnect Development Team", info.contact().name());
        assertEquals("support@careconnect.com", info.contact().email());
        assertEquals("https://careconnect.com", info.contact().url());

        assertEquals("MIT License", info.license().name());
        assertEquals("https://opensource.org/licenses/MIT", info.license().url());
    }

    @Test
    void openApiDefinitionContainsServers() throws Exception {
        // Verifies that both the local development server and the production API server
        // are listed so that developers can target either from Swagger UI.
        final OpenAPIDefinition definition =
                OpenApiConfig.class.getAnnotation(OpenAPIDefinition.class);

        final Server[] servers = definition.servers();

        assertEquals(2, servers.length);

        assertTrue(Arrays.stream(servers)
                .anyMatch(s -> s.url().equals("http://localhost:8080")));

        assertTrue(Arrays.stream(servers)
                .anyMatch(s -> s.url().equals("https://api.careconnect.com")));
    }

    @Test
    void openApiDefinitionContainsSecurityRequirements() throws Exception {
        // Verifies that the three authentication methods used by the API (JWT bearer token,
        // HTTP Basic, and cookie-based) are declared as global security requirements so
        // every endpoint in the spec is marked as requiring authentication by default.
        final OpenAPIDefinition definition =
                OpenApiConfig.class.getAnnotation(OpenAPIDefinition.class);

        final SecurityRequirement[] security = definition.security();

        assertEquals(3, security.length);

        assertTrue(Arrays.stream(security)
                .anyMatch(s -> s.name().equals("JWT Authentication")));

        assertTrue(Arrays.stream(security)
                .anyMatch(s -> s.name().equals("Basic Authentication")));

        assertTrue(Arrays.stream(security)
                .anyMatch(s -> s.name().equals("Cookie Authentication")));
    }

    @Test
    void securitySchemesAreDefined() throws Exception {
        // Verifies that the three @SecurityScheme annotations are present, which define
        // how each authentication type works (e.g. Bearer token in Authorization header,
        // Basic credentials, or a session cookie) so Swagger UI can send real auth requests.
        final SecurityScheme[] schemes =
                OpenApiConfig.class.getAnnotationsByType(SecurityScheme.class);

        assertEquals(3, schemes.length);

        assertTrue(Arrays.stream(schemes)
                .anyMatch(s -> s.name().equals("JWT Authentication")));

        assertTrue(Arrays.stream(schemes)
                .anyMatch(s -> s.name().equals("Basic Authentication")));

        assertTrue(Arrays.stream(schemes)
                .anyMatch(s -> s.name().equals("Cookie Authentication")));
    }
}
