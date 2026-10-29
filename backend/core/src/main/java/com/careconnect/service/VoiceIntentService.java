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

    private static final Map<String, String> ROUTE_MAP = Map.ofEntries(
            // Core
            Map.entry("home", "/dashboard"),
            Map.entry("dashboard", "/dashboard"),
            Map.entry("calendar", "/calendar"),
            Map.entry("messages", "/dashboard?tab=messages"),
            Map.entry("profile", "/profile"),
            Map.entry("settings", "/settings"),
            Map.entry("menu", "/dashboard?tab=menu"),

            // Health & Wellness
            Map.entry("symptoms", "/symptoms"),
            Map.entry("symptom tracker", "/symptoms"),
            Map.entry("medication", "/medication"),
            Map.entry("medications", "/medication"),
            Map.entry("medication tracker", "/medication"),
            Map.entry("virtual check-in", "/virtual-checkin"),
            Map.entry("virtual checkin", "/virtual-checkin"),
            Map.entry("check-in", "/virtual-checkin"),

            // Integrations & Devices
            Map.entry("wearables", "/wearables"),
            Map.entry("smart devices", "/smart-devices"),
            Map.entry("home monitoring", "/home-monitoring"),

            // Social
            Map.entry("social feed", "/social-feed"),
            Map.entry("social", "/social-feed"),

            // Caregiver
            Map.entry("patient list", "/tasks"),
            Map.entry("patients", "/tasks"),
            Map.entry("evv", "/evv"),
            Map.entry("evv dashboard", "/evv"),
            Map.entry("notetaker", "/notetaker-search"),
            Map.entry("medical notetaker", "/notetaker-search"),
            Map.entry("invoice", "/invoice-assistant"),
            Map.entry("invoice assistant", "/invoice-assistant"),

            // Files & Documents
            Map.entry("files", "/file-management"),
            Map.entry("file management", "/file-management"),
            Map.entry("informed delivery", "/informed-delivery"),
            Map.entry("mail", "/informed-delivery"),

            // Gamification
            Map.entry("gamification", "/gamification"),
            Map.entry("achievements", "/gamification"),

            // Configuration
            Map.entry("ai configuration", "/ai-configuration"),
            Map.entry("ai config", "/ai-configuration"),
            Map.entry("notetaker configuration", "/notetaker-configuration"),

            // Payments & Search
            Map.entry("subscription", "/subscription"),
            Map.entry("search", "/search"),

            // Voice
            Map.entry("voice", "/voice"),
            Map.entry("voice commands", "/voice")

    ); //end of ROUTE_MAP


private static final String PROMPT_TEMPLATE = """
            You are a strict voice command intent classifier for the CareConnect healthcare app.
            Given the user utterance below, extract the intent and entities.
            Respond ONLY with valid JSON, with no other text, markdown formatting, or prose.

            Supported intents:
            - "navigate": The user wants to view a screen or open a feature.
              ALLOWED DESTINATION KEYS:
              "home", "dashboard", "calendar", "messages", "profile", "settings", "menu",
              "symptoms", "symptom tracker", "medication", "medications", "medication tracker",
              "virtual check-in", "virtual checkin", "check-in", "wearables", "smart devices",
              "home monitoring", "social feed", "social", "patient list", "patients", "evv",
              "evv dashboard", "notetaker", "medical notetaker", "invoice", "invoice assistant",
              "files", "file management", "informed delivery", "mail", "gamification",
              "achievements", "ai configuration", "ai config", "notetaker configuration",
              "subscription", "search", "voice", "voice commands".
              (You must output one of these exact keys under entities.destination).
            - "call": The user wants to call someone. Entities: {"target": "<person name or role>"}
            - "schedule": The user wants to schedule an appointment. Entities: {"target": "<person>", "date": "<date if mentioned>"}
            - "unknown": Spoken phrase has nothing to do with CareConnect screens, or is casual non-healthcare chatter.

            CONCRETE EXAMPLES:
            Utterance: "where are my pills"
            {"intent": "navigate", "entities": {"destination": "medication"}, "confidence": 0.95}

            Utterance: "what medicine do I take"
            {"intent": "navigate", "entities": {"destination": "medications"}, "confidence": 0.95}

            Utterance: "how do I record my headache"
            {"intent": "navigate", "entities": {"destination": "symptoms"}, "confidence": 0.92}

            Utterance: "did I get any letters today"
            {"intent": "navigate", "entities": {"destination": "mail"}, "confidence": 0.90}

            Utterance: "show my badges and points"
            {"intent": "navigate", "entities": {"destination": "achievements"}, "confidence": 0.93}

            Utterance: "tell me a funny joke"
            {"intent": "unknown", "entities": {}, "confidence": 0.99}

            Utterance: "what is the weather like right now"
            {"intent": "unknown", "entities": {}, "confidence": 0.99}

            JSON schema: {"intent":"...","entities":{...},"confidence":0.0-1.0}

            User utterance: "%s"
            """;

            //end of PROMPT_TEMPLATE

    private final AIServiceFactory aiServiceFactory;
    private final ObjectMapper objectMapper;

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
            log.error("Voice intent extraction failed: {}", e.getClass().getSimpleName());
            return VoiceIntentResponse.error("Voice intent service is temporarily unavailable.");
        }
    }

    private VoiceIntentResponse parseAIResponse(String aiResponse) {
        try {
            String json = extractJson(aiResponse);
            Map<String, Object> parsed = objectMapper.readValue(json, new TypeReference<>() {
            });

            String intent = (String) parsed.getOrDefault("intent", "unknown");
            double confidence = parsed.containsKey("confidence")
                    ? ((Number) parsed.get("confidence")).doubleValue()
                    : 0.0;

            @SuppressWarnings("unchecked")
            Map<String, String> entities = parsed.containsKey("entities")
                    ? objectMapper.convertValue(parsed.get("entities"), new TypeReference<>() {
            })
                    : Map.of();

            return buildResponse(intent, entities, confidence);
        } catch (Exception e) {
            log.warn("Failed to parse AI response as JSON: {}", e.getClass().getSimpleName());
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
