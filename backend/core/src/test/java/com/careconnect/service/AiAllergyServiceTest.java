package com.careconnect.service;

import com.careconnect.dto.AiAllergyDTO;
import com.careconnect.model.Allergy;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.Collections;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

class AiAllergyServiceTest {

    @Mock
    private BedrockStructuredAnalysisService bedrockAnalysisService;

    @Mock
    private DeepSeekContextBuilder contextBuilder;

    @InjectMocks
    private AiAllergyService aiAllergyService;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        try {
            var field = AiAllergyService.class.getDeclaredField("objectMapper");
            field.setAccessible(true);
            field.set(aiAllergyService, objectMapper);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private AiAllergyDTO.Request buildRequest(Long patientId, String text, Map<String, Object> context) {
        AiAllergyDTO.Request req = new AiAllergyDTO.Request();
        req.setPatientId(patientId);
        req.setText(text);
        req.setContext(context);
        return req;
    }

    @Test
    @DisplayName("analyze_validJsonResponse_returnsPopulatedResult")
    void analyze_validJsonResponse_returnsPopulatedResult() {
        String json = "{\"allergen\":\"Penicillin\",\"reaction\":\"Hives\",\"severity\":\"SEVERE\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("No known allergies.");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiAllergyDTO.Request req = buildRequest(1L, "I am allergic to penicillin", null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("Penicillin", result.getAllergen());
        assertEquals("Hives", result.getReaction());
        assertEquals("SEVERE", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_mildSeverityInJson_normalizesMild")
    void analyze_mildSeverityInJson_normalizesMild() {
        String json = "{\"allergen\":\"Dust\",\"reaction\":\"Sneezing\",\"severity\":\"mild\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiAllergyDTO.Request req = buildRequest(1L, "dust allergy", Map.of("hint", "sneezing"));
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("Dust", result.getAllergen());
        assertEquals("MILD", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_moderateSeverityInJson_normalizesModerate")
    void analyze_moderateSeverityInJson_normalizesModerate() {
        String json = "{\"allergen\":\"Shellfish\",\"reaction\":\"Swelling\",\"severity\":\"MODERATE\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiAllergyDTO.Request req = buildRequest(1L, "shellfish", null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("MODERATE", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_nonJsonContent_fallsBackToTranscript")
    void analyze_nonJsonContent_fallsBackToTranscript() {
        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString()))
                .thenReturn("I'm not sure about the allergy");

        AiAllergyDTO.Request req = buildRequest(1L, "penicillin allergy", null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("", result.getAllergen());
        assertEquals("penicillin allergy", result.getReaction());
        assertEquals("", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_emptyContent_fallsBackToTranscript")
    void analyze_emptyContent_fallsBackToTranscript() {
        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn("");

        AiAllergyDTO.Request req = buildRequest(1L, "my transcript", null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("", result.getAllergen());
        assertEquals("my transcript", result.getReaction());
    }

    @Test
    @DisplayName("analyze_nullText_fallsBackToEmptyString")
    void analyze_nullText_fallsBackToEmptyString() {
        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn("");

        AiAllergyDTO.Request req = buildRequest(1L, null, null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("", result.getReaction());
    }

    @Test
    @DisplayName("analyze_nullTextWithNonJsonContent_fallsBackToEmptyString")
    void analyze_nullTextWithNonJsonContent_fallsBackToEmptyString() {
        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn("some non-json content");

        AiAllergyDTO.Request req = buildRequest(1L, null, null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("", result.getReaction());
    }

    @Test
    @DisplayName("analyze_jsonMissingFields_returnsEmptyStrings")
    void analyze_jsonMissingFields_returnsEmptyStrings() {
        String json = "{\"allergen\":\"Pollen\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiAllergyDTO.Request req = buildRequest(1L, "pollen", null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("Pollen", result.getAllergen());
        assertEquals("", result.getReaction());
        assertEquals("", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_jsonWithUnknownSeverity_returnsEmptySeverity")
    void analyze_jsonWithUnknownSeverity_returnsEmptySeverity() {
        String json = "{\"allergen\":\"Eggs\",\"reaction\":\"Rash\",\"severity\":\"UNKNOWN\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiAllergyDTO.Request req = buildRequest(1L, "egg allergy", null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_withAllergyHistory_passesHistoryToContextBuilder")
    void analyze_withAllergyHistory_passesHistoryToContextBuilder() {
        Allergy allergy = Allergy.builder()
                .allergen("Aspirin")
                .severity(Allergy.AllergySeverity.MODERATE)
                .reaction("Stomach pain")
                .isActive(true)
                .build();

        String json = "{\"allergen\":\"Latex\",\"reaction\":\"Swelling\",\"severity\":\"SEVERE\"}";

        when(contextBuilder.buildAllergyContext(eq(1L), eq(List.of(allergy)))).thenReturn("history ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiAllergyDTO.Request req = buildRequest(1L, "latex gloves cause swelling", Map.of("source", "voice"));
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, List.of(allergy));

        assertEquals("Latex", result.getAllergen());
        assertEquals("SEVERE", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_emptyBedrockResponse_fallsBackToTranscript")
    void analyze_emptyBedrockResponse_fallsBackToTranscript() {
        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn("");

        AiAllergyDTO.Request req = buildRequest(1L, "some text", null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("some text", result.getReaction());
    }

    @Test
    @DisplayName("analyze_jsonWithMedicationKey_mapsToAllergen")
    void analyze_jsonWithMedicationKey_mapsToAllergen() {
        String json = "{\"medication\":\"Penicillin\",\"reaction\":\"Hives\",\"severity\":\"SEVERE\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiAllergyDTO.Request req = buildRequest(1L, "allergic to penicillin", null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("Penicillin", result.getAllergen());
        assertEquals("Hives", result.getReaction());
    }

    @Test
    @DisplayName("analyze_missingAllergenInJson_infersFromTranscript")
    void analyze_missingAllergenInJson_infersFromTranscript() {
        String json = "{\"reaction\":\"Hives\",\"severity\":\"MILD\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiAllergyDTO.Request req = buildRequest(1L, "I am allergic to penicillin and get hives", null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("penicillin", result.getAllergen());
    }

    @Test
    @DisplayName("analyze_jsonWithNullSeverity_returnsEmptySeverity")
    void analyze_jsonWithNullSeverity_returnsEmptySeverity() {
        String json = "{\"allergen\":\"Milk\",\"reaction\":\"Cramps\",\"severity\":null}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiAllergyDTO.Request req = buildRequest(1L, "milk cramps", null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("Milk", result.getAllergen());
        assertEquals("Cramps", result.getReaction());
        assertEquals("", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_jsonWrappedInCodeFences_parsesCorrectly")
    void analyze_jsonWrappedInCodeFences_parsesCorrectly() {
        String json = "```json\n{\"allergen\":\"Ibuprofen\",\"reaction\":\"Rash\",\"severity\":\"MILD\"}\n```";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiAllergyDTO.Request req = buildRequest(1L, "ibuprofen rash", null);
        AiAllergyDTO.Result result = aiAllergyService.analyze(req, Collections.emptyList());

        assertEquals("Ibuprofen", result.getAllergen());
        assertEquals("MILD", result.getSeverity());
    }
}
