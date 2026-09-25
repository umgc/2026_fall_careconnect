package com.careconnect.dto;

import lombok.Data;

import java.util.Map;

/**
 * AI Symptom extraction (request + response)
 */
public class AiSymptomDTO {

    @Data
    public static class Request {
        private Long patientId;               // required
        private String text;                  // raw transcript
        private Map<String, Object> context;  // optional: { symptomKey, severity, notes }
    }

    @Data
    public static class Result {
        private String symptomKey;    // e.g. "anxiety", "headache"
        private String symptomValue;  // free text detail (e.g. "racing heart", "panic")
        private String severity;      // "MILD" | "MODERATE" | "SEVERE"
        private String notes;         // always include full transcript as fallback
    }
}
