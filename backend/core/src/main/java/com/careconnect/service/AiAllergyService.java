package com.careconnect.service;

import com.careconnect.dto.AiAllergyDTO;
import com.careconnect.model.Allergy;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.Optional;

@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.ai.provider", havingValue = "bedrock")
public class AiAllergyService {

    private final BedrockStructuredAnalysisService bedrockAnalysisService;
    private final DeepSeekContextBuilder contextBuilder;
    private final ObjectMapper objectMapper;

    public AiAllergyDTO.Result analyze(AiAllergyDTO.Request req, List<Allergy> history) {
        String system = "You are a medical assistant. Extract structured drug allergy info from the user's sentence.\n" +
            "Return ONLY a compact JSON object:\n" +
            "{\"allergen\":\"<drug or medication name>\", \"reaction\":\"...\", \"severity\":\"MILD|MODERATE|SEVERE\"}.\n" +
            "Put the drug/medication name in allergen (e.g. Penicillin, Aspirin). If something is missing, leave it as an empty string. Do NOT add extra keys or text.\n";

        String historyBlock = contextBuilder.buildAllergyContext(req.getPatientId(), history);

        Map<String, Object> ctx = Optional.ofNullable(req.getContext()).orElse(Map.of());
        String user = String.format(
            "Patient history:\n" +
            "%s\n\n" +
            "Current input (voice transcript):\n" +
            "\"%s\"\n\n" +
            "Hints (optional context from UI): %s\n\n" +
            "Output JSON only.\n",
            historyBlock, req.getText(), ctx);

        String content = AiParsingUtils.normalizeModelContent(
                bedrockAnalysisService.complete(system, user));

        AiAllergyDTO.Result out = new AiAllergyDTO.Result();
        out.setAllergen("");
        out.setReaction("");
        out.setSeverity("");

        JsonNode node = AiParsingUtils.tryParseJson(objectMapper, content);
        if (node != null) {
            out.setAllergen(extractAllergen(node));
            out.setReaction(AiParsingUtils.asText(node, "reaction"));
            out.setSeverity(
                    AiParsingUtils.normalizeSeverity(
                            AiParsingUtils.asText(node, "severity")
                    )
            );
        } else if (!content.isBlank()) {
            log.warn("AI content was not strict JSON. Falling back. Content: {}", content);
            out.setReaction(Optional.ofNullable(req.getText()).orElse(""));
        } else {
            out.setReaction(Optional.ofNullable(req.getText()).orElse(""));
        }

        if (out.getAllergen() == null || out.getAllergen().isBlank()) {
            out.setAllergen(inferAllergenFromText(req.getText()));
        }

        return out;
    }

    private static String extractAllergen(JsonNode node) {
        for (String key : List.of("allergen", "medication", "drug", "medicationName", "drugName")) {
            String value = AiParsingUtils.asText(node, key);
            if (value != null && !value.isBlank()) {
                return value.trim();
            }
        }
        return "";
    }

    private static String inferAllergenFromText(String text) {
        if (text == null || text.isBlank()) {
            return "";
        }
        java.util.regex.Pattern pattern = java.util.regex.Pattern.compile(
                "(?i)allerg(?:y|ic)\\s+to\\s+([A-Za-z0-9][A-Za-z0-9\\s\\-]{0,40}?)(?:[,\\.;]|\\s+(?:I|it|which|that|causes|gives|and)\\b|$)"
        );
        java.util.regex.Matcher matcher = pattern.matcher(text.trim());
        if (matcher.find()) {
            return matcher.group(1).trim();
        }
        return "";
    }
}
