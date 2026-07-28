package com.careconnect.service.mail;

import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Locale;
import java.util.Optional;

/**
 * Optional AI assist for mailpiece importance when rules are inconclusive
 * (Task 3.14.6 / #123). Soft-fails when AI provider is unavailable.
 */
@Component
public class MailpieceImportanceAiAssist {

    private static final Logger log = LoggerFactory.getLogger(MailpieceImportanceAiAssist.class);

    private final ObjectProvider<AIServiceFactory> aiServiceFactoryProvider;
    private final ObjectMapper objectMapper;
    private final String modelId;
    private final boolean enabled;

    public MailpieceImportanceAiAssist(
            final ObjectProvider<AIServiceFactory> aiServiceFactoryProvider,
            final ObjectMapper objectMapper,
            @Value("${careconnect.ai.model:amazon.nova-lite-v1:0}") final String modelId,
            @Value("${careconnect.mailpiece.importance.ai.enabled:true}") final boolean enabled) {
        this.aiServiceFactoryProvider = aiServiceFactoryProvider;
        this.objectMapper = objectMapper;
        this.modelId = modelId;
        this.enabled = enabled;
    }

    public Optional<MailpieceImportanceResult> classify(
            final String sender,
            final String summary,
            final String ocrText,
            final MailpieceImportanceResult ruleHint) {
        if (!enabled) {
            return Optional.empty();
        }
        final AIServiceFactory factory = aiServiceFactoryProvider.getIfAvailable();
        if (factory == null) {
            log.debug("AIServiceFactory unavailable; skipping mailpiece AI assist");
            return Optional.empty();
        }

        try {
            final ChatRequest request = new ChatRequest();
            request.setUserId(0L);
            request.setMessage(buildPrompt(sender, summary, ocrText, ruleHint));
            request.setPreferredModel(modelId);

            final ChatResponse response = factory.getService().processChat(request);
            final String raw = response == null ? null : response.getAiResponse();
            return parseResponse(raw);
        } catch (final Exception ex) {
            log.warn("Mailpiece AI importance assist failed: {}", ex.getMessage());
            return Optional.empty();
        }
    }

    Optional<MailpieceImportanceResult> parseResponse(final String raw) {
        if (raw == null || raw.isBlank()) {
            return Optional.empty();
        }
        try {
            final String json = extractJsonObject(raw);
            final JsonNode root = objectMapper.readTree(json);
            final MailpieceImportanceLevel level =
                    MailpieceImportanceLevel.fromRaw(text(root, "importanceLevel"));
            if (level == MailpieceImportanceLevel.UNKNOWN
                    && root.path("importanceLevel").isMissingNode()) {
                return Optional.empty();
            }
            final double confidence = root.path("confidence").isNumber()
                    ? root.path("confidence").asDouble()
                    : 0.70d;
            final String category = normalizeCategory(text(root, "category"));
            final String reasoning = firstNonBlank(
                    text(root, "reasoning"),
                    "AI assist classified mailpiece importance.");
            return Optional.of(MailpieceImportanceResult.of(
                    level,
                    confidence,
                    MailpieceImportanceResult.METHOD_AI,
                    "aws_bedrock:" + modelId,
                    reasoning,
                    category));
        } catch (final Exception ex) {
            log.debug("Unable to parse AI importance JSON: {}", ex.getMessage());
            return Optional.empty();
        }
    }

    private static String buildPrompt(
            final String sender,
            final String summary,
            final String ocrText,
            final MailpieceImportanceResult ruleHint) {
        final StringBuilder sb = new StringBuilder();
        sb.append("""
                You classify USPS Informed Delivery mailpieces for a patient caregiver app.
                Return ONLY valid JSON (no markdown) with this exact shape:
                {
                  "importanceLevel": "HIGH|MODERATE|LOW|UNKNOWN",
                  "confidence": 0.0,
                  "category": "MEDICAL|FINANCIAL|LEGAL|ADMINISTRATIVE|MARKETING|OTHER",
                  "reasoning": "one short sentence"
                }

                Guidelines:
                - HIGH: medical urgency, insurance denials, legal action, collections, shutoffs
                - MODERATE: billing statements, appointments, insurance renewals, utilities
                - LOW: marketing, coupons, catalogs, promotions
                - Prefer HIGH when clinically or financially material risk is likely

                """);
        sb.append("Rule-engine hint: level=")
                .append(ruleHint == null ? "n/a" : ruleHint.level())
                .append(", category=")
                .append(ruleHint == null ? "n/a" : ruleHint.category())
                .append(", reasoning=")
                .append(ruleHint == null ? "n/a" : ruleHint.reasoning())
                .append('\n');
        sb.append("Sender: ").append(nullToEmpty(sender)).append('\n');
        sb.append("Summary: ").append(nullToEmpty(summary)).append('\n');
        sb.append("OCR: ").append(nullToEmpty(ocrText)).append('\n');
        return sb.toString();
    }

    private static String extractJsonObject(final String raw) {
        final String trimmed = raw.trim();
        final int start = trimmed.indexOf('{');
        final int end = trimmed.lastIndexOf('}');
        if (start >= 0 && end > start) {
            return trimmed.substring(start, end + 1);
        }
        return trimmed;
    }

    private static String normalizeCategory(final String raw) {
        if (raw == null || raw.isBlank()) {
            return "OTHER";
        }
        final String value = raw.trim().toUpperCase(Locale.ROOT);
        return switch (value) {
            case "MEDICAL", "FINANCIAL", "LEGAL", "ADMINISTRATIVE", "MARKETING", "OTHER" -> value;
            default -> "OTHER";
        };
    }

    private static String text(final JsonNode node, final String field) {
        final JsonNode child = node.path(field);
        return child.isMissingNode() || child.isNull() ? null : child.asText(null);
    }

    private static String firstNonBlank(final String a, final String b) {
        if (a != null && !a.isBlank()) {
            return a.trim();
        }
        return b;
    }

    private static String nullToEmpty(final String value) {
        return value == null ? "" : value.trim();
    }
}
