package com.careconnect.config;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeIn;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import io.swagger.v3.oas.annotations.info.Contact;
import io.swagger.v3.oas.annotations.info.Info;
import io.swagger.v3.oas.annotations.info.License;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import io.swagger.v3.oas.annotations.servers.Server;
import org.springframework.context.annotation.Configuration;

/**
 * OpenAPI configuration for CareConnect Backend API
 * <p>
 * This configuration provides comprehensive API documentation using OpenAPI 3.0.
 * It includes JWT authentication setup, server configuration, and API metadata.
 * <p>
 * Access the documentation at:
 * - Swagger UI: http://localhost:8080/swagger-ui.html
 * - OpenAPI JSON: http://localhost:8080/api-docs
 *
 * @author CareConnect Team
 * @version 1.0
 * @since 2025
 */
@Configuration
@OpenAPIDefinition(
        info = @Info(
                title = "CareConnect Backend API",
                version = "1.0.0",
                description = "CareConnect Backend API provides comprehensive healthcare management services including:\n\n"
                        + "## Features\n"
                        + "- **Authentication & Authorization**: JWT-based authentication with Google OAuth integration\n"
                        + "- **User Management**: Patient and caregiver registration, profile management\n"
                        + "- **Feed Management**: Social feed for patients and caregivers\n"
                        + "- **Comments System**: Interactive commenting on posts\n"
                        + "- **Gamification**: Points and achievements system\n"
                        + "- **Payment Integration**: Stripe-based payment processing\n"
                        + "- **Email Services**: Multi-provider email support (SendGrid, Mailgun, Mailtrap, etc.)\n"
                        + "- **File Upload**: Image and document upload capabilities\n\n"
                        + "## Authentication\n"
                        + "Most endpoints require JWT authentication. Use the `/api/auth/login` endpoint to obtain a token.\n"
                        + "For Google OAuth, use the `/api/auth/google` endpoint.\n\n"
                        + "## Rate Limiting\n"
                        + "API endpoints are rate-limited to ensure fair usage and system stability.\n\n"
                        + "## Error Handling\n"
                        + "All API responses follow a consistent error format with appropriate HTTP status codes.\n",
                contact = @Contact(
                        name = "CareConnect Development Team",
                        email = "support@careconnect.com",
                        url = "https://careconnect.com"
                ),
                license = @License(
                        name = "MIT License",
                        url = "https://opensource.org/licenses/MIT"
                )
        ),
        servers = {
                @Server(
                        url = "http://localhost:8080",
                        description = "Development Server"
                ),
                @Server(
                        url = "https://api.careconnect.com",
                        description = "Production Server"
                )
        },
        security = {
                @SecurityRequirement(name = "JWT Authentication"),
                @SecurityRequirement(name = "Cookie Authentication"),
                @SecurityRequirement(name = "Basic Authentication")
        }
)
@SecurityScheme(
        name = "JWT Authentication",
        description = "JWT token authentication.\n\n"
                + "**How to authenticate:**\n"
                + "1. Use the `/v1/api/auth/login` endpoint to obtain a JWT token\n"
                + "2. Include the token in the Authorization header as: `Bearer {your-jwt-token}`\n"
                + "3. The token is valid for 3 hours\n\n"
                + "**Example:**\n"
                + "```\n"
                + "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...\n"
                + "```\n",
        scheme = "bearer",
        type = SecuritySchemeType.HTTP,
        bearerFormat = "JWT",
        in = SecuritySchemeIn.HEADER
)
@SecurityScheme(
        name = "Basic Authentication",
        description = "Basic HTTP authentication for testing purposes.\n\n"
                + "**How to authenticate:**\n"
                + "1. Use username (email) and password\n"
                + "2. Format: `username:password` encoded in Base64\n"
                + "3. Include in Authorization header as: `Basic {base64-encoded-credentials}`\n\n"
                + "**Example:**\n"
                + "```\n"
                + "Authorization: Basic dXNlckBleGFtcGxlLmNvbTpwYXNzd29yZA==\n"
                + "```\n",
        type = SecuritySchemeType.HTTP,
        scheme = "basic"
)
@SecurityScheme(
        name = "Cookie Authentication",
        description = "Cookie-based authentication using HttpOnly cookies.\n\n"
                + "**How it works:**\n"
                + "1. Login through `/v1/api/auth/login` - sets an HttpOnly cookie automatically\n"
                + "2. Browser automatically includes the cookie in subsequent requests\n"
                + "3. Useful for web applications and testing in browser\n",
        type = SecuritySchemeType.APIKEY,
        in = SecuritySchemeIn.COOKIE,
        paramName = "AUTH"
)
public class OpenApiConfig {
    // Configuration is handled through annotations
    // Bean configuration commented out temporarily to avoid conflicts
    
    /*
    @Bean
    public io.swagger.v3.oas.models.OpenAPI customOpenAPI() {
        return new io.swagger.v3.oas.models.OpenAPI()
            .info(new io.swagger.v3.oas.models.info.Info()
                .title("CareConnect Backend API")
                .version("1.0.0")
                .description("Enhanced API documentation with authentication guide"))
            .addServersItem(new io.swagger.v3.oas.models.servers.Server()
                .url("http://localhost:8080")
                .description("Development Server"));
    }
    */
}