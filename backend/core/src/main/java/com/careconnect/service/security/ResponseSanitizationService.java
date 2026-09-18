package com.careconnect.service.security;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import lombok.extern.slf4j.Slf4j;

import java.util.List;
import java.util.ArrayList;
import java.util.regex.Pattern;

@Service
@Slf4j
public class ResponseSanitizationService {

    // Patterns for detecting sensitive information in AI responses
    private static final Pattern SYSTEM_INFO_PATTERN = Pattern.compile(
            "(?i).*(system prompt|internal instructions|configuration|api key|database|server|localhost|127\\.0\\.0\\.1).*"
    );
    private static final Pattern SENSITIVE_DATA_PATTERN = Pattern.compile(
            "(?i).*(password|secret|token|credential|ssn|social security|credit card).*"
    );
    @Autowired
    private SecurityAuditService securityAuditService;

    public SanitizationResult sanitizeAIResponse(String response, Long userId, String conversationId, Long patientId) {
        if (response == null || response.trim().isEmpty()) {
            return new SanitizationResult("", new ArrayList<>());
        }

        List<String> sanitizedItems = new ArrayList<>();
        String sanitized = response;

        // Remove system information that shouldn't be exposed
        if (SYSTEM_INFO_PATTERN.matcher(response).find()) {
            sanitized = sanitized.replaceAll("(?i)(system prompt|internal instructions)[^.]*\\.", "[System information removed].");
            sanitized = sanitized.replaceAll("(?i)(api key|database|server): [^\\s]+", "[Sensitive information removed]");
            sanitized = sanitized.replaceAll("(?i)(localhost|127\\.0\\.0\\.1)", "[Server reference removed]");
            sanitizedItems.add("System information");
            securityAuditService.logSanitizationAction(userId, conversationId, "RESPONSE_SYSTEM_INFO_REMOVED", "Removed system information from AI response");
        }

        // Remove potential sensitive data
        if (SENSITIVE_DATA_PATTERN.matcher(response).find()) {
            sanitized = sanitized.replaceAll("(?i)(password|secret|token|credential): [^\\s]+", "[Sensitive data removed]");
            // Remove SSNs in formats: XXX-XX-XXXX, XXX XX XXXX
            sanitized = sanitized.replaceAll("\\b\\d{3}-\\d{2}-\\d{4}\\b|\\b\\d{3}\\s\\d{2}\\s\\d{4}\\b|\\b\\d{9}\\b", "[SSN removed]");
            sanitized = sanitized.replaceAll("\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b", "[Credit card number removed]");
            sanitizedItems.add("Sensitive personal data");
            securityAuditService.logSanitizationAction(userId, conversationId, "RESPONSE_SENSITIVE_DATA_REMOVED", "Removed sensitive data from AI response");
        }

        // Medical data protection - only allow medical information for authorized patient access
        if (patientId != null) {
            // Allow medical information in context of patient care
            log.debug("Allowing medical context for patient {}", patientId);
        } else {
            // Remove specific medical details when no patient context
            sanitized = sanitized.replaceAll("(?i)\\b(diagnosis|prescription|medication dosage): [^.]*\\.", "[Medical information restricted].");
            if (!sanitized.equals(response)) {
                sanitizedItems.add("Medical information without patient context");
                securityAuditService.logSanitizationAction(userId, conversationId, "RESPONSE_MEDICAL_DATA_RESTRICTED", "Removed medical details without patient authorization");
            }
        }

        // Remove any remaining potentially harmful content
        sanitized = sanitized
                .replaceAll("(?s)<script[^>]*>.*?</script>", "[Script content removed]")
                .replaceAll("(?i)javascript:[^\\s]*", "[JavaScript removed]")
                .trim();

        if (!sanitized.equals(response) && sanitizedItems.isEmpty()) {
            sanitizedItems.add("Potentially harmful content");
        }

        return new SanitizationResult(sanitized, sanitizedItems);
    }

    public static class SanitizationResult {
        private final String sanitizedContent;
        private final List<String> sanitizedItems;

        public SanitizationResult(String sanitizedContent, List<String> sanitizedItems) {
            this.sanitizedContent = sanitizedContent;
            this.sanitizedItems = sanitizedItems;
        }

        public String getSanitizedContent() {
            return sanitizedContent;
        }

        public List<String> getSanitizedItems() {
            return sanitizedItems;
        }
    }
}