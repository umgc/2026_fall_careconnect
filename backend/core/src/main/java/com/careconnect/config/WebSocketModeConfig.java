package com.careconnect.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;

/**
 * WebSocket Mode Configuration
 * <p>
 * Automatically determines whether to use Local or AWS WebSocket mode based on
 * environment.
 * Priority:
 * 1. If AWS_WEBSOCKET_API_GATEWAY_ENDPOINT env var is set -> AWS mode
 * 2. If AWS_WEBSOCKET_API_ENDPOINT env var is set -> AWS mode (legacy fallback)
 * 3. Otherwise -> Local mode (default)
 */
@Configuration
public class WebSocketModeConfig {
    private static final Logger log = LoggerFactory.getLogger(WebSocketModeConfig.class);

    @Bean
    public String websocketMode(Environment env) {
        String awsEndpoint = env.getProperty("AWS_WEBSOCKET_API_GATEWAY_ENDPOINT");
        if (awsEndpoint == null || awsEndpoint.isBlank()) {
            awsEndpoint = env.getProperty("AWS_WEBSOCKET_API_ENDPOINT");
        }

        if (awsEndpoint != null && !awsEndpoint.isBlank()) {
            log.info("AWS WebSocket endpoint detected: Using AWS WebSocket mode");
            log.info("AWS WebSocket endpoint: {}", awsEndpoint);
            return "aws";
        } else {
            log.info("AWS WebSocket endpoint not set: Using Local WebSocket mode");
            return "local";
        }
    }
}
