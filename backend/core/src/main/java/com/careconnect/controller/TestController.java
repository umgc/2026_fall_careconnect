package com.careconnect.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;

import java.time.LocalDateTime;
import java.util.Map;

/**
 * Test controller for verifying API functionality and Swagger integration
 */
@RestController
@RequestMapping("/v1/api/test")
@Tag(name = "Testing", description = "Public testing endpoints for verifying API functionality")
public class TestController {


    @GetMapping("/health")
    @Operation(
            summary = "Health check",
            description = "Public health check endpoint to verify the API is running.\n\n"
                    + "**Use this endpoint to:**\n"
                    + "- Test that the API is accessible\n"
                    + "- Verify Swagger UI is working\n"
                    + "- Check server time and status\n"
                    + "- No authentication required\n\n"
                    + "This is a great starting point for testing the API!\n",
            tags = {"Testing"}
    )
    @ApiResponses({
            @ApiResponse(
                    responseCode = "200",
                    description = "API is healthy and running",
                    content = @Content(
                            mediaType = "application/json",
                            examples = @ExampleObject(value = "{\n    \"status\": \"healthy\",\n    \"timestamp\": \"2025-01-15T10:30:00Z\",\n    \"message\": \"CareConnect API is running successfully!\",\n    \"version\": \"1.0.0\"\n}")
                    )
            )
    })
    public ResponseEntity<Map<String, Object>> healthCheck() {
        return ResponseEntity.ok(Map.of(
                "status", "healthy",
                "timestamp", LocalDateTime.now(),
                "message", "CareConnect API is running successfully!",
                "version", "1.0.0",
                "documentation", "Available at /swagger-ui.html"
        ));
    }

    @GetMapping("/swagger-info")
    @Operation(
            summary = "ℹSwagger usage guide",
            description = "Get information about how to use this API with Swagger UI.\n\n"
                    + "**Quick Start Guide:**\n"
                    + "1. **Test this endpoint** - No authentication required\n"
                    + "2. **Register an account** - Use `/v1/api/auth/register`\n"
                    + "3. **Login** - Use `/v1/api/auth/login` to get JWT token\n"
                    + "4. **Authorize** - Click button, enter `Bearer {token}`\n"
                    + "5. **Test protected endpoints** - Try endpoints with icon\n\n"
                    + "**Authentication Tips:**\n"
                    + "- Copy the entire token from login response\n"
                    + "- Use format: `Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`\n"
                    + "- Tokens expire after 3 hours\n"
                    + "- Re-login if you get 401 errors\n",
            tags = {"Testing"}
    )
    @ApiResponses({
            @ApiResponse(
                    responseCode = "200",
                    description = "Swagger usage information",
                    content = @Content(
                            mediaType = "application/json",
                            examples = @ExampleObject(value = "{\n    \"message\": \"Welcome to CareConnect API!\",\n    \"swaggerUrl\": \"/swagger-ui.html\",\n    \"steps\": [\n        \"1. Test this endpoint (no auth required)\",\n        \"2. Register: POST /v1/api/auth/register\",\n        \"3. Login: POST /v1/api/auth/login\",\n        \"4. Click Authorize button\",\n        \"5. Enter: Bearer {your-token}\",\n        \"6. Test protected endpoints\"\n    ]\n}"))
            )

    })
    public ResponseEntity<Map<String, Object>> swaggerInfo() {
        return ResponseEntity.ok(Map.of(
                "message", "Welcome to CareConnect API!",
                "swaggerUrl", "/swagger-ui.html",
                "apiDocsUrl", "/v3/api-docs",
                "steps", new String[]{
                        "1. Test this endpoint (no auth required)",
                        "2. Register: POST /v1/api/auth/register",
                        "3. Login: POST /v1/api/auth/login",
                        "4. Click Authorize button",
                        "5. Enter: Bearer {your-token}",
                        "6. Test protected endpoints"
                },
                "authenticationRequired", false,
                "tokenLifetime", "3 hours",
                "supportContact", "support@careconnect.com"
        ));
    }


}
