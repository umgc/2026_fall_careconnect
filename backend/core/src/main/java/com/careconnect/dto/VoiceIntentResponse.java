package com.careconnect.dto;

import lombok.*;

import java.util.Map;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class VoiceIntentResponse {

    private String intent;
    private Map<String, String> entities;
    private double confidence;
    private String destination;
    private String displayLabel;
    private boolean requiresConfirmation;
    private boolean success;
    private String errorMessage;

    public static VoiceIntentResponse unknown() {
        return VoiceIntentResponse.builder()
                .intent("unknown")
                .confidence(0.0)
                .requiresConfirmation(false)
                .success(false)
                .build();
    }

    public static VoiceIntentResponse error(String message) {
        return VoiceIntentResponse.builder()
                .intent("unknown")
                .confidence(0.0)
                .requiresConfirmation(false)
                .success(false)
                .errorMessage(message)
                .build();
    }
}
