package com.careconnect.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class AiParsingUtilsTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    @DisplayName("normalizeModelContent_stripsCodeFences")
    void normalizeModelContent_stripsCodeFences() {
        String raw = "```json\n{\"key\":\"value\"}\n```";
        assertEquals("{\"key\":\"value\"}", AiParsingUtils.normalizeModelContent(raw));
    }

    @Test
    @DisplayName("normalizeModelContent_null_returnsEmptyString")
    void normalizeModelContent_null_returnsEmptyString() {
        assertEquals("", AiParsingUtils.normalizeModelContent(null));
    }

    @Test
    @DisplayName("normalizeModelContent_plainJson_returnsTrimmed")
    void normalizeModelContent_plainJson_returnsTrimmed() {
        assertEquals("{\"a\":1}", AiParsingUtils.normalizeModelContent("  {\"a\":1}  "));
    }

    @Test
    @DisplayName("tryParseJson_validJson_returnsJsonNode")
    void tryParseJson_validJson_returnsJsonNode() throws Exception {
        final JsonNode node = AiParsingUtils.tryParseJson(objectMapper, "{\"key\":\"value\"}");

        assertNotNull(node);
        assertEquals("value", node.get("key").asText());
    }

    @Test
    @DisplayName("tryParseJson_nullContent_returnsNull")
    void tryParseJson_nullContent_returnsNull() {
        assertNull(AiParsingUtils.tryParseJson(objectMapper, null));
    }

    @Test
    @DisplayName("tryParseJson_blankContent_returnsNull")
    void tryParseJson_blankContent_returnsNull() {
        assertNull(AiParsingUtils.tryParseJson(objectMapper, "   "));
    }

    @Test
    @DisplayName("tryParseJson_invalidJson_returnsNull")
    void tryParseJson_invalidJson_returnsNull() {
        assertNull(AiParsingUtils.tryParseJson(objectMapper, "not valid json {{{"));
    }

    @Test
    @DisplayName("asText_keyExists_returnsValue")
    void asText_keyExists_returnsValue() throws Exception {
        final JsonNode node = objectMapper.readTree("{\"name\":\"Alice\"}");
        assertEquals("Alice", AiParsingUtils.asText(node, "name"));
    }

    @Test
    @DisplayName("asText_keyMissing_returnsEmptyString")
    void asText_keyMissing_returnsEmptyString() throws Exception {
        final JsonNode node = objectMapper.readTree("{\"name\":\"Alice\"}");
        assertEquals("", AiParsingUtils.asText(node, "age"));
    }

    @Test
    @DisplayName("asText_nullNode_returnsEmptyString")
    void asText_nullNode_returnsEmptyString() {
        assertEquals("", AiParsingUtils.asText(null, "key"));
    }

    @Test
    @DisplayName("normalizeSeverity_mild_returnsMILD")
    void normalizeSeverity_mild_returnsMILD() {
        assertEquals("MILD", AiParsingUtils.normalizeSeverity("mild"));
    }

    @Test
    @DisplayName("normalizeSeverity_moderate_returnsMODERATE")
    void normalizeSeverity_moderate_returnsMODERATE() {
        assertEquals("MODERATE", AiParsingUtils.normalizeSeverity("moderate"));
    }

    @Test
    @DisplayName("normalizeSeverity_severe_returnsSEVERE")
    void normalizeSeverity_severe_returnsSEVERE() {
        assertEquals("SEVERE", AiParsingUtils.normalizeSeverity("severe"));
    }

    @Test
    @DisplayName("normalizeSeverity_unknownValue_returnsEmptyString")
    void normalizeSeverity_unknownValue_returnsEmptyString() {
        assertEquals("", AiParsingUtils.normalizeSeverity("UNKNOWN"));
    }

    @Test
    @DisplayName("normalizeSeverity_containsMildSubstring_returnsMILD")
    void normalizeSeverity_containsMildSubstring_returnsMILD() {
        assertEquals("MILD", AiParsingUtils.normalizeSeverity("very mild symptoms"));
    }
}
