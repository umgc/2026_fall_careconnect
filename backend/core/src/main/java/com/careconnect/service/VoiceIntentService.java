package com.careconnect.service;

import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.dto.VoiceIntentRequest;
import com.careconnect.dto.VoiceIntentResponse;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.Map;

@Slf4j
@Service
public class VoiceIntentService {

    private final AIServiceFactory aiServiceFactory;
    private final ObjectMapper objectMapper;

    private static final Map<String, String> ROUTE_MAP = Map.of(
            "home", "/dashboard",
            "dashboard", "/dashboard",
            "calendar", "/calendar",
            "symptoms", "/symptoms",
            "symptom tracker", "/symptoms"
    );

    private static final String PROMPT_TEMPLATE = """
            You are a voice command intent classifier for the CareConnect healthcare app.
            Given the user utterance below, extract the intent and entities.
            Respond ONLY with valid JSON, no other text.

            Supported intents:
            - "navigate": user wants to go to a screen. Entities: {"destination": "home|calendar|symptoms|dashboard"}
            - "call": user wants to call someone. Entities: {"target": "<person name or role>"}
            - "schedule": user wants to schedule an appointment. Entities: {"target": "<person>", "date": "<date if mentioned>"}
            - "unknown": cannot determine intent

            JSON schema: {"intent":"...","entities":{...},"confidence":0.0-1.0}

            User utterance: "%s"
            """;

    public VoiceIntentService(AIServiceFactory aiServiceFactory, ObjectMapper objectMapper) {
        this.aiServiceFactory = aiServiceFactory;
        this.objectMapper = objectMapper;
    }

    public VoiceIntentResponse extractIntent(VoiceIntentRequest request) {
        try {
            String prompt = String.format(PROMPT_TEMPLATE, request.getUtterance());

            ChatRequest chatRequest = ChatRequest.builder()
                    .message(prompt)
                    .userId(0L)
                    .build();

            ChatResponse chatResponse = aiServiceFactory.getService().processChat(chatRequest);

            if (chatResponse == null || chatResponse.getAiResponse() == null) {
                log.warn("Empty AI response for voice intent extraction");
                return VoiceIntentResponse.unknown();
            }

            return parseAIResponse(chatResponse.getAiResponse());
        } catch (Exception e) {
            log.error("Voice intent extraction failed: {}", e.getMessage(), e);
            return VoiceIntentResponse.error(e.getMessage());
        }
    }

    private VoiceIntentResponse parseAIResponse(String aiResponse) {
        try {
            String json = extractJson(aiResponse);
            Map<String, Object> parsed = objectMapper.readValue(json, new TypeReference<>() {});

            String intent = (String) parsed.getOrDefault("intent", "unknown");
            double confidence = parsed.containsKey("confidence")
                    ? ((Number) parsed.get("confidence")).doubleValue()
                    : 0.0;

            @SuppressWarnings("unchecked")
            Map<String, String> entities = parsed.containsKey("entities")
                    ? objectMapper.convertValue(parsed.get("entities"), new TypeReference<>() {})
                    : Map.of();

            return buildResponse(intent, entities, confidence);
        } catch (Exception e) {
            log.warn("Failed to parse AI response as JSON: {}", aiResponse, e);
            return VoiceIntentResponse.unknown();
        }
    }

    private String extractJson(String text) {
        String trimmed = text.trim();
        if (trimmed.startsWith("```")) {
            int start = trimmed.indexOf('{');
            int end = trimmed.lastIndexOf('}');
            if (start >= 0 && end > start) {
                return trimmed.substring(start, end + 1);
            }
        }
        int start = trimmed.indexOf('{');
        int end = trimmed.lastIndexOf('}');
        if (start >= 0 && end > start) {
            return trimmed.substring(start, end + 1);
        }
        return trimmed;
    }

    private VoiceIntentResponse buildResponse(String intent, Map<String, String> entities, double confidence) {
        return switch (intent) {
            case "navigate" -> {
                String dest = entities.getOrDefault("destination", "");
                String route = ROUTE_MAP.getOrDefault(dest.toLowerCase(), null);
                yield VoiceIntentResponse.builder()
                        .intent("navigate")
                        .entities(entities)
                        .confidence(confidence)
                        .destination(route)
                        .displayLabel("Navigate to " + dest)
                        .requiresConfirmation(true)
                        .success(route != null)
                        .build();
            }
            case "call" -> VoiceIntentResponse.builder()
                    .intent("call")
                    .entities(entities)
                    .confidence(confidence)
                    .displayLabel("Call " + entities.getOrDefault("target", "contact"))
                    .requiresConfirmation(true)
                    .success(true)
                    .build();
            case "schedule" -> VoiceIntentResponse.builder()
                    .intent("schedule")
                    .entities(entities)
                    .confidence(confidence)
                    .displayLabel("Schedule with " + entities.getOrDefault("target", "provider"))
                    .requiresConfirmation(true)
                    .success(true)
                    .build();
            default -> VoiceIntentResponse.unknown();
        };
    }
}
