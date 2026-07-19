package com.careconnect.controller;

import com.careconnect.dto.VoiceIntentRequest;
import com.careconnect.dto.VoiceIntentResponse;
import com.careconnect.service.VoiceIntentService;
import jakarta.validation.Valid;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@Slf4j
@RestController
@RequestMapping("/api/voice")
@ConditionalOnProperty(name = "careconnect.ai.enabled", havingValue = "true")
public class VoiceIntentController {

    private final VoiceIntentService voiceIntentService;

    public VoiceIntentController(VoiceIntentService voiceIntentService) {
        this.voiceIntentService = voiceIntentService;
    }

    @PostMapping("/intent")
    public ResponseEntity<VoiceIntentResponse> extractIntent(@Valid @RequestBody VoiceIntentRequest request) {
        try {
            log.info("Voice intent request: utterance='{}', locale='{}'",
                    request.getUtterance(), request.getLocale());

            VoiceIntentResponse response = voiceIntentService.extractIntent(request);

            log.info("Voice intent result: intent='{}', confidence={}, success={}",
                    response.getIntent(), response.getConfidence(), response.isSuccess());

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Voice intent endpoint error: {}", e.getMessage(), e);
            return ResponseEntity.ok(VoiceIntentResponse.error(e.getMessage()));
        }
    }
}
