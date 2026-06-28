package com.careconnect.controller;

import com.careconnect.service.ChimeMediaStreamEventService;
import java.util.Map;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Receives Chime media stream EventBridge notifications for local/dev wiring.
 *
 * <p>Enable with {@code careconnect.kvs.event-webhook.enabled=true}. Point an EventBridge rule at
 * {@code POST /api/internal/chime/media-stream-events} (API Gateway, ngrok, etc.).
 */
@RestController
@RequestMapping("/api/internal/chime")
@ConditionalOnProperty(name = "careconnect.kvs.event-webhook.enabled", havingValue = "true")
public class ChimeMediaStreamWebhookController {

    private final ChimeMediaStreamEventService chimeMediaStreamEventService;

    public ChimeMediaStreamWebhookController(
            final ChimeMediaStreamEventService chimeMediaStreamEventService) {
        this.chimeMediaStreamEventService = chimeMediaStreamEventService;
    }

    @PostMapping("/media-stream-events")
    public ResponseEntity<Void> handleMediaStreamEvent(@RequestBody final Map<String, Object> payload) {
        final Object detail = payload.get("detail");
        if (detail instanceof Map<?, ?> detailMap) {
            @SuppressWarnings("unchecked")
            final Map<String, Object> typedDetail = (Map<String, Object>) detailMap;
            chimeMediaStreamEventService.handleEventDetail(typedDetail);
        }
        return ResponseEntity.ok().build();
    }
}
