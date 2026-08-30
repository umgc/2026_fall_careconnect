package com.careconnect.config;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.core.env.Environment;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link WebSocketModeConfig}.
 * <p>
 * WebSocketModeConfig produces a {@code "websocketMode"} String bean whose value is
 * either {@code "local"} or {@code "aws"}, determined by whether the environment
 * property {@code AWS_WEBSOCKET_API_GATEWAY_ENDPOINT} (or the legacy fallback
 * {@code AWS_WEBSOCKET_API_ENDPOINT}) is set to a non-blank value. This bean
 * is consumed by other components that need to switch between a local WebSocket server
 * and an AWS API Gateway WebSocket endpoint at runtime.
 * <p>
 * The Spring {@link Environment} is mocked so that tests can control the property value
 * precisely (null, empty, blank, or a real URL) without needing real environment variables
 * or a Spring context. {@code @ExtendWith(MockitoExtension.class)} manages the mock
 * lifecycle cleanly per test.
 */
@ExtendWith(MockitoExtension.class)
class WebSocketModeConfigTest {

    @Mock
    private Environment env;

    private WebSocketModeConfig config;

    @BeforeEach
    void setUp() throws Exception {
        config = new WebSocketModeConfig();
    }

    @Test
    void returnsLocalWhenAwsEndpointPropertyIsNull() throws Exception {
        // Verifies that a null property value (property not set at all) triggers the
        // local mode, which is the expected default for local development environments.
        when(env.getProperty("AWS_WEBSOCKET_API_GATEWAY_ENDPOINT")).thenReturn(null);
        when(env.getProperty("AWS_WEBSOCKET_API_ENDPOINT")).thenReturn(null);

        final String mode = config.websocketMode(env);

        assertEquals("local", mode);
    }

    @Test
    void returnsLocalWhenAwsEndpointPropertyIsEmpty() throws Exception {
        // Verifies that an empty string (property present but empty) also triggers
        // local mode, guarding against misconfigured environments.
        when(env.getProperty("AWS_WEBSOCKET_API_GATEWAY_ENDPOINT")).thenReturn("");
        when(env.getProperty("AWS_WEBSOCKET_API_ENDPOINT")).thenReturn("");

        final String mode = config.websocketMode(env);

        assertEquals("local", mode);
    }

    @Test
    void returnsLocalWhenAwsEndpointPropertyIsBlank() throws Exception {
        // Verifies that a whitespace-only value is also treated as absent,
        // preventing accidental "aws" mode from a property set to spaces.
        when(env.getProperty("AWS_WEBSOCKET_API_GATEWAY_ENDPOINT")).thenReturn("   ");
        when(env.getProperty("AWS_WEBSOCKET_API_ENDPOINT")).thenReturn("   ");

        final String mode = config.websocketMode(env);

        assertEquals("local", mode);
    }

    @Test
    void returnsAwsWhenAwsEndpointPropertyIsSet() throws Exception {
        // Verifies that a real AWS API Gateway endpoint URL triggers "aws" mode,
        // which causes the application to route WebSocket traffic to AWS rather than
        // the local server.
        when(env.getProperty("AWS_WEBSOCKET_API_GATEWAY_ENDPOINT")).thenReturn("https://abc123.execute-api.us-east-1.amazonaws.com/prod");

        final String mode = config.websocketMode(env);

        assertEquals("aws", mode);
    }

    @Test
    void returnsAwsWhenAwsEndpointPropertyIsMinimalNonBlankString() throws Exception {
        // Verifies that any non-blank string (not just a valid AWS URL) triggers "aws"
        // mode, confirming the logic checks for presence/non-blankness only.
        when(env.getProperty("AWS_WEBSOCKET_API_GATEWAY_ENDPOINT")).thenReturn("wss://example.com");

        final String mode = config.websocketMode(env);

        assertEquals("aws", mode);
    }
}
