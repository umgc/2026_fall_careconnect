package com.careconnect.service.chat;

import org.springframework.stereotype.Service;

import java.util.List;
import java.util.regex.Pattern;

@Service
public class GuardrailService {

    // A simple regex for US Social Security Numbers. Add more for credit cards, etc.
    private static final Pattern SSN_PATTERN = Pattern.compile("\\b\\d{3}-\\d{2}-\\d{4}\\b");

    private static final List<String> FORBIDDEN_PHRASES = List.of(
            "medical diagnosis", "I diagnose you with", "prescribe you", "medical advice",
            "end your life", "commit suicide", "harm yourself"
            // Add other sensitive or dangerous phrases here
    );

    /**
     * Scans the input prompt for sensitive information and redacts it.
     *
     * @param prompt The user's input text.
     * @return A sanitized version of the prompt.
     */
    public String sanitizeRequest(String prompt) {
        if (prompt == null) return null;

        String sanitizedPrompt = prompt;
        // Example: Redact Social Security Numbers
        sanitizedPrompt = SSN_PATTERN.matcher(sanitizedPrompt).replaceAll("[REDACTED_SSN]");

        // Add more redaction rules here for other PII like credit card numbers

        return sanitizedPrompt;
    }

    /**
     * Scans the AI's response for forbidden content.
     * Throws an exception if forbidden content is found.
     *
     * @param response The AI's generated text.
     */
    public void validateResponse(String response) {
        if (response == null) return;

        String lowerCaseResponse = response.toLowerCase();

        for (String phrase : FORBIDDEN_PHRASES) {
            if (lowerCaseResponse.contains(phrase.toLowerCase())) {
                throw new UnsafeAiResponseException(
                        "The AI response was blocked because it contained forbidden content."
                );
            }
        }
    }

    // A custom exception for clarity
    public static class UnsafeAiResponseException extends RuntimeException {
        public UnsafeAiResponseException(String message) {
            super(message);
        }
    }
}