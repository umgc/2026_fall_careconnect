package com.careconnect.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

import java.util.Map;

public class AiAllergyDTO {

    @Data
    public static class Request {
        @NotNull(message = "patientId is required")
        private Long patientId;

        @NotBlank(message = "text (voice transcript) is required")
        private String text;

        private Map<String, Object> context; // optional
    }

    @Data
    public static class Result {
        private String allergen;
        private String reaction;
        private String severity;
    }
}
