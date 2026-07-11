package com.careconnect.service;

import com.careconnect.dto.AiSymptomDTO;
import com.careconnect.model.Allergy;
import com.careconnect.model.SymptomEntry;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.time.Instant;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

class AiSymptomServiceTest {

    @Mock
    private BedrockStructuredAnalysisService bedrockAnalysisService;

    @Mock
    private DeepSeekContextBuilder contextBuilder;

    @InjectMocks
    private AiSymptomService aiSymptomService;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        try {
            var field = AiSymptomService.class.getDeclaredField("objectMapper");
            field.setAccessible(true);
            field.set(aiSymptomService, objectMapper);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private AiSymptomDTO.Request buildRequest(Long patientId, String text, Map<String, Object> context) {
        AiSymptomDTO.Request req = new AiSymptomDTO.Request();
        req.setPatientId(patientId);
        req.setText(text);
        req.setContext(context);
        return req;
    }

    @Test
    @DisplayName("analyze_validJsonResponse_returnsPopulatedResult")
    void analyze_validJsonResponse_returnsPopulatedResult() {
        String json = "{\"symptomKey\":\"headache\",\"symptomValue\":\"throbbing pain\",\"severity\":\"MODERATE\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("allergy ctx");
        when(contextBuilder.buildSymptomContext(any(), any())).thenReturn("symptom ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiSymptomDTO.Request req = buildRequest(1L, "I have a headache", null);
        AiSymptomDTO.Result result = aiSymptomService.analyze(req, Collections.emptyList(), Collections.emptyList());

        assertEquals("headache", result.getSymptomKey());
        assertEquals("throbbing pain", result.getSymptomValue());
        assertEquals("MODERATE", result.getSeverity());
        assertEquals("I have a headache", result.getNotes());
    }

    @Test
    @DisplayName("analyze_mildSeverity_normalizesMild")
    void analyze_mildSeverity_normalizesMild() {
        String json = "{\"symptomKey\":\"cough\",\"symptomValue\":\"dry cough\",\"severity\":\"mild\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(contextBuilder.buildSymptomContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiSymptomDTO.Request req = buildRequest(1L, "coughing", Map.of("hint", "dry"));
        AiSymptomDTO.Result result = aiSymptomService.analyze(req, Collections.emptyList(), Collections.emptyList());

        assertEquals("MILD", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_severeSeverity_normalizesSevere")
    void analyze_severeSeverity_normalizesSevere() {
        String json = "{\"symptomKey\":\"chest pain\",\"symptomValue\":\"sharp\",\"severity\":\"SEVERE\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(contextBuilder.buildSymptomContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiSymptomDTO.Request req = buildRequest(1L, "chest pain", null);
        AiSymptomDTO.Result result = aiSymptomService.analyze(req, Collections.emptyList(), Collections.emptyList());

        assertEquals("SEVERE", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_nonJsonContent_fallsBackWithWarning")
    void analyze_nonJsonContent_fallsBackWithWarning() {
        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(contextBuilder.buildSymptomContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString()))
                .thenReturn("I cannot determine the symptom");

        AiSymptomDTO.Request req = buildRequest(1L, "feeling dizzy", null);
        AiSymptomDTO.Result result = aiSymptomService.analyze(req, Collections.emptyList(), Collections.emptyList());

        assertEquals("", result.getSymptomKey());
        assertEquals("", result.getSymptomValue());
        assertEquals("", result.getSeverity());
        assertEquals("feeling dizzy", result.getNotes());
    }

    @Test
    @DisplayName("analyze_emptyContent_keepsDefaultValues")
    void analyze_emptyContent_keepsDefaultValues() {
        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(contextBuilder.buildSymptomContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn("");

        AiSymptomDTO.Request req = buildRequest(1L, "some text", null);
        AiSymptomDTO.Result result = aiSymptomService.analyze(req, Collections.emptyList(), Collections.emptyList());

        assertEquals("", result.getSymptomKey());
        assertEquals("", result.getSymptomValue());
        assertEquals("", result.getSeverity());
        assertEquals("some text", result.getNotes());
    }

    @Test
    @DisplayName("analyze_nullText_notesIsEmptyString")
    void analyze_nullText_notesIsEmptyString() {
        String json = "{\"symptomKey\":\"nausea\",\"symptomValue\":\"mild\",\"severity\":\"MILD\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(contextBuilder.buildSymptomContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiSymptomDTO.Request req = buildRequest(1L, null, null);
        AiSymptomDTO.Result result = aiSymptomService.analyze(req, Collections.emptyList(), Collections.emptyList());

        assertEquals("", result.getNotes());
        assertEquals("nausea", result.getSymptomKey());
    }

    @Test
    @DisplayName("analyze_withContext_passesContextToPrompt")
    void analyze_withContext_passesContextToPrompt() {
        String json = "{\"symptomKey\":\"fever\",\"symptomValue\":\"101F\",\"severity\":\"MODERATE\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("allergy ctx");
        when(contextBuilder.buildSymptomContext(any(), any())).thenReturn("symptom ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        Map<String, Object> ctx = Map.of("symptomKey", "fever", "severity", "MODERATE");
        AiSymptomDTO.Request req = buildRequest(1L, "I have a fever", ctx);
        AiSymptomDTO.Result result = aiSymptomService.analyze(req, Collections.emptyList(), Collections.emptyList());

        assertEquals("fever", result.getSymptomKey());
        assertEquals("MODERATE", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_withAllergyAndSymptomHistory_passesHistoryToBuilder")
    void analyze_withAllergyAndSymptomHistory_passesHistoryToBuilder() {
        Allergy allergy = Allergy.builder()
                .allergen("Pollen").severity(Allergy.AllergySeverity.MILD).build();
        SymptomEntry symptom = SymptomEntry.builder()
                .symptomKey("cough").symptomValue("dry").severity(2)
                .takenAt(Instant.now()).completed(true).build();

        String json = "{\"symptomKey\":\"runny nose\",\"symptomValue\":\"clear\",\"severity\":\"MILD\"}";

        when(contextBuilder.buildAllergyContext(eq(1L), eq(List.of(allergy)))).thenReturn("allergy history");
        when(contextBuilder.buildSymptomContext(eq(1L), eq(List.of(symptom)))).thenReturn("symptom history");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiSymptomDTO.Request req = buildRequest(1L, "runny nose", null);
        AiSymptomDTO.Result result = aiSymptomService.analyze(req, List.of(allergy), List.of(symptom));

        assertEquals("runny nose", result.getSymptomKey());
    }

    @Test
    @DisplayName("analyze_emptyBedrockResponse_keepsDefaults")
    void analyze_emptyBedrockResponse_keepsDefaults() {
        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(contextBuilder.buildSymptomContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn("");

        AiSymptomDTO.Request req = buildRequest(1L, "transcript", null);
        AiSymptomDTO.Result result = aiSymptomService.analyze(req, Collections.emptyList(), Collections.emptyList());

        assertEquals("", result.getSymptomKey());
        assertEquals("transcript", result.getNotes());
    }

    @Test
    @DisplayName("analyze_jsonMissingFields_returnsEmptyStrings")
    void analyze_jsonMissingFields_returnsEmptyStrings() {
        String json = "{\"symptomKey\":\"anxiety\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(contextBuilder.buildSymptomContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiSymptomDTO.Request req = buildRequest(1L, "feeling anxious", null);
        AiSymptomDTO.Result result = aiSymptomService.analyze(req, Collections.emptyList(), Collections.emptyList());

        assertEquals("anxiety", result.getSymptomKey());
        assertEquals("", result.getSymptomValue());
        assertEquals("", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_jsonWithUnknownSeverity_returnsEmptySeverity")
    void analyze_jsonWithUnknownSeverity_returnsEmptySeverity() {
        String json = "{\"symptomKey\":\"rash\",\"symptomValue\":\"red\",\"severity\":\"UNKNOWN\"}";

        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(contextBuilder.buildSymptomContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn(json);

        AiSymptomDTO.Request req = buildRequest(1L, "skin rash", null);
        AiSymptomDTO.Result result = aiSymptomService.analyze(req, Collections.emptyList(), Collections.emptyList());

        assertEquals("", result.getSeverity());
    }

    @Test
    @DisplayName("analyze_blankContent_keepsDefaults")
    void analyze_blankContent_keepsDefaults() {
        when(contextBuilder.buildAllergyContext(any(), any())).thenReturn("ctx");
        when(contextBuilder.buildSymptomContext(any(), any())).thenReturn("ctx");
        when(bedrockAnalysisService.complete(anyString(), anyString())).thenReturn("   ");

        AiSymptomDTO.Request req = buildRequest(1L, "text", null);
        AiSymptomDTO.Result result = aiSymptomService.analyze(req, Collections.emptyList(), Collections.emptyList());

        assertEquals("", result.getSymptomKey());
        assertEquals("text", result.getNotes());
    }
}
