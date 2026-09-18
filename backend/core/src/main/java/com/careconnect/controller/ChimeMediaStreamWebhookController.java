package com.careconnect.controller;

import com.careconnect.service.ChimeMediaStreamEventService;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Receives Chime media stream EventBridge notifications.
 *
 * <p>Primary discovery path on deploy (EventBridge rule in {@code 04-service.yaml}).
 * Enable with {@code careconnect.kvs.event-webhook.enabled=true}. Auth is the shared
 * secret in header {@code X-EventBridge-Connection} (API key from the EventBridge
 * connection). KVS polling in {@link com.careconnect.service.KvsPoolStreamDiscoveryService}
 * remains fallback.
 */
@RestController
@RequestMapping("/api/internal/chime")
@ConditionalOnProperty(name = "careconnect.kvs.event-webhook.enabled", havingValue = "true")
public class ChimeMediaStreamWebhookController {

    static final String EVENT_BRIDGE_CONNECTION_HEADER = "X-EventBridge-Connection";
    private static final Logger log = LoggerFactory.getLogger(ChimeMediaStreamWebhookController.class);
    private final ChimeMediaStreamEventService chimeMediaStreamEventService;
    private final String sharedSecret;

    public ChimeMediaStreamWebhookController(
            final ChimeMediaStreamEventService chimeMediaStreamEventService,
            @Value("${careconnect.kvs.event-webhook.shared-secret:}") final String sharedSecret) {
        this.chimeMediaStreamEventService = chimeMediaStreamEventService;
        this.sharedSecret = sharedSecret == null ? "" : sharedSecret;
    }

    @PostMapping("/media-stream-events")
    public ResponseEntity<Void> handleMediaStreamEvent(
            @RequestHeader(value = EVENT_BRIDGE_CONNECTION_HEADER, required = false) final String connectionKey,
            @RequestBody final Map<String, Object> payload) {
        if (!isAuthorized(connectionKey)) {
            if (log.isWarnEnabled()) {
                log.warn(
                        "Rejected Chime media-stream EventBridge webhook: missing/invalid {}"
                                + " (shared-secret configured={})",
                        EVENT_BRIDGE_CONNECTION_HEADER,
                        !sharedSecret.isBlank());
            }
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        final Object detail = payload.get("detail");
        if (detail instanceof Map<?, ?> detailMap) {
            @SuppressWarnings("unchecked") final Map<String, Object> typedDetail = (Map<String, Object>) detailMap;
            chimeMediaStreamEventService.handleEventDetail(typedDetail);
        }
        return ResponseEntity.ok().build();
    }

    private boolean isAuthorized(final String connectionKey) {
        if (sharedSecret.isBlank() || connectionKey == null || connectionKey.isBlank()) {
            return false;
        }
        final byte[] expected = sharedSecret.getBytes(StandardCharsets.UTF_8);
        final byte[] provided = connectionKey.getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(expected, provided);
    }
}
