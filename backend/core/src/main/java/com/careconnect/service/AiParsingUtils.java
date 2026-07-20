package com.careconnect.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.Locale;

final class AiParsingUtils {
    private AiParsingUtils() {}

    static String normalizeModelContent(String content) {
        if (content == null) {
            return "";
        }
        return stripCodeFences(content.trim());
    }

    static String stripCodeFences(String text) {
        if (text == null || text.isBlank()) {
            return text == null ? "" : text.trim();
        }
        return text.replaceAll("```(?:json)?", "").replace("```", "").trim();
    }

    static JsonNode tryParseJson(ObjectMapper om, String content) {
        if (content == null || content.isBlank()) return null;
        try {
            return om.readTree(content);
        } catch (Exception e) {
            return null;
        }
    }

    static String asText(JsonNode node, String key) {
        return node != null && node.has(key) && !node.get(key).isNull()
                ? node.get(key).asText("")
                : "";
    }

    static String normalizeSeverity(String raw) {
        if (raw == null) return "";
        String v = raw.trim().toUpperCase(Locale.ROOT);
        if (v.contains("MILD")) return "MILD";
        if (v.contains("MODERATE")) return "MODERATE";
        if (v.contains("SEVERE")) return "SEVERE";
        return "";
    }
}
