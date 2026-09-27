package com.careconnect.controller;

import com.careconnect.dto.VoiceIntentRequest;
import com.careconnect.dto.VoiceIntentResponse;
import com.careconnect.service.VoiceIntentService;
import jakarta.validation.Valid;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@Slf4j
@RestController
@RequestMapping("/api/voice")
@ConditionalOnProperty(name = "careconnect.ai.enabled", havingValue = "true")
public class VoiceIntentController {

    private static final String GENERIC_ERROR_MESSAGE = "Voice intent service is temporarily unavailable.";

    private final VoiceIntentService voiceIntentService;

    public VoiceIntentController(VoiceIntentService voiceIntentService) {
        this.voiceIntentService = voiceIntentService;
    }

    @PostMapping("/intent")
    public ResponseEntity<VoiceIntentResponse> extractIntent(@Valid @RequestBody VoiceIntentRequest request) {
        try {
            log.info("Voice intent request received: locale='{}'", request.getLocale());

            VoiceIntentResponse response = voiceIntentService.extractIntent(request);

            log.info("Voice intent result: intent='{}', confidence={}, success={}",
                    response.getIntent(), response.getConfidence(), response.isSuccess());

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Voice intent endpoint failed: {}", e.getClass().getSimpleName());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(VoiceIntentResponse.error(GENERIC_ERROR_MESSAGE));
        }
    }
}
