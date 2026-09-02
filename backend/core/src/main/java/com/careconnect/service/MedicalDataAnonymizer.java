package com.careconnect.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.security.SecureRandom;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;


@Service
public class MedicalDataAnonymizer {
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(MedicalDataAnonymizer.class);
    // Regex patterns for identifying sensitive data
    private static final Pattern NAME_PATTERN = Pattern.compile("\\b[A-Z][a-z]+ [A-Z][a-z]+\\b");
    private static final Pattern SSN_PATTERN = Pattern.compile("\\b\\d{3}-\\d{2}-\\d{4}\\b");
    private static final Pattern PHONE_PATTERN = Pattern.compile("\\b\\d{3}[-.\\s]?\\d{3}[-.\\s]?\\d{4}\\b");
    private static final Pattern EMAIL_PATTERN = Pattern.compile("\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b");
    private static final Pattern ADDRESS_PATTERN = Pattern.compile("\\b\\d+ [A-Za-z]+ (Street|St|Avenue|Ave|Road|Rd|Drive|Dr|Lane|Ln|Court|Ct|Boulevard|Blvd)\\b");
    private static final Pattern DATE_PATTERN = Pattern.compile("\\b(January|February|March|April|May|June|July|August|September|October|November|December) \\d{1,2}, \\d{4}\\b");
    private static final Pattern FACILITY_PATTERN = Pattern.compile("\\b[A-Z][a-z]+ (Hospital|Clinic|Medical Center|Health System)\\b");
    private final Map<String, String> pseudonymMapping = new ConcurrentHashMap<>();
    private final SecureRandom random = new SecureRandom();

    /**
     * Anonymize patient context based on specified level
     */
    public String anonymizePatientContext(String context, Long patientId, AnonymizationLevel level) {
        if (context == null || context.trim().isEmpty()) {
            return context;
        }

        String anonymized = context;

        // Apply anonymization based on level
        switch (level) {
            case STATISTICAL:
                anonymized = convertToStatisticalSummary(anonymized, patientId);
                break;
            case AGGRESSIVE:
                anonymized = applyAggressiveAnonymization(anonymized, patientId);
                break;
            case MODERATE:
                anonymized = applyModerateAnonymization(anonymized, patientId);
                break;
            case MINIMAL:
            default:
                anonymized = applyMinimalAnonymization(anonymized, patientId);
                break;
        }

        log.debug("Applied {} anonymization for patient {}", level, generatePseudoId(patientId));
        return anonymized;
    }

    private String applyMinimalAnonymization(String context, Long patientId) {
        return context
                .replaceAll(NAME_PATTERN.pattern(), generatePseudonym(patientId, "NAME"))
                .replaceAll(SSN_PATTERN.pattern(), "XXX-XX-XXXX")
                .replaceAll(PHONE_PATTERN.pattern(), "**PHONE**")
                .replaceAll(EMAIL_PATTERN.pattern(), "**EMAIL**");
    }

    private String applyModerateAnonymization(String context, Long patientId) {
        return applyMinimalAnonymization(context, patientId)
                .replaceAll(ADDRESS_PATTERN.pattern(), "**ADDRESS**")
                .replaceAll(DATE_PATTERN.pattern(), "**DATE**")
                .replaceAll(FACILITY_PATTERN.pattern(), "**FACILITY**")
                .replaceAll("\\b\\d{1,2}:\\d{2}\\s?(AM|PM)\\b", "**TIME**");
    }

    private String applyAggressiveAnonymization(String context, Long patientId) {
        String anonymized = applyModerateAnonymization(context, patientId);

        // Remove specific numeric values that could be identifying
        anonymized = roundDecimalNumbers(anonymized);

        // Remove ages over 89 (HIPAA requirement)
        anonymized = anonymized.replaceAll("\\b(9[0-9]|[1-9][0-9]{2,})\\s*years?\\s*old\\b", ">89 years old");

        // Generalize specific medication names to classes
        anonymized = generalizeMedications(anonymized);

        return anonymized;
    }

    private String convertToStatisticalSummary(String context, Long patientId) {
        // Convert detailed medical data to statistical summaries
        StringBuilder summary = new StringBuilder();

        summary.append(String.format("Statistical Patient Profile (ID: %s):%n", generatePseudoId(patientId)));
        summary.append("- Demographic cluster: Adult-Unknown-Region%n");
        summary.append("- Health indicators: Statistical summary available%n");
        summary.append("- Treatment response: Pattern analysis available%n");
        summary.append("- Risk factors: Categorical assessment available%n");
        summary.append("%nNote: All specific identifiers removed for maximum privacy.%n");

        return summary.toString();
    }

    /**
     * Generate consistent pseudonym for a patient and data type
     */
    public String generatePseudonym(Long patientId, String type) {
        String key = patientId + "_" + type;
        return pseudonymMapping.computeIfAbsent(key,
                k -> "Patient_" + Math.abs(k.hashCode() % 10000));
    }

    /**
     * Generate pseudo ID for patient
     */
    public String generatePseudoId(Long patientId) {
        return generatePseudonym(patientId, "ID");
    }

    /**
     * Clear all pseudonym mappings for a patient (for right to be forgotten)
     */
    public void clearPseudonymMappings(Long patientId) {
        pseudonymMapping.entrySet().removeIf(entry ->
                entry.getKey().startsWith(patientId + "_"));
        log.info("Cleared pseudonym mappings for patient {}", patientId);
    }

    /**
     * Clear all mappings (for system maintenance)
     */
    public void clearAllMappings(Long patientId) {
        clearPseudonymMappings(patientId);
    }

    private String roundDecimalNumbers(String text) {
        // Use a Pattern and Matcher to handle decimal replacement
        java.util.regex.Pattern pattern = java.util.regex.Pattern.compile("\\b\\d+\\.\\d{3,}\\b");
        java.util.regex.Matcher matcher = pattern.matcher(text);

        StringBuffer result = new StringBuffer();
        while (matcher.find()) {
            String replacement = roundToTwoDecimals(matcher.group());
            matcher.appendReplacement(result, replacement);
        }
        matcher.appendTail(result);
        return result.toString();
    }

    private String roundToTwoDecimals(String match) {
        try {
            double value = Double.parseDouble(match);
            return String.format("%.2f", value);
        } catch (NumberFormatException e) {
            return "**NUMERIC**";
        }
    }

    private String generalizeMedications(String context) {
        // Simple medication generalization - in production, use a proper drug database
        return context
                .replaceAll("\\b(Lisinopril|Enalapril|Captopril)\\b", "ACE Inhibitor")
                .replaceAll("\\b(Metoprolol|Atenolol|Propranolol)\\b", "Beta Blocker")
                .replaceAll("\\b(Amlodipine|Nifedipine)\\b", "Calcium Channel Blocker")
                .replaceAll("\\b(Metformin|Glipizide|Insulin)\\b", "Diabetes Medication")
                .replaceAll("\\b(Atorvastatin|Simvastatin)\\b", "Statin");
    }

    /**
     * Add differential privacy noise to numerical values
     */
    public String addDifferentialPrivacyNoise(String data, double epsilon) {
        // Use Pattern and Matcher for decimal number replacement
        java.util.regex.Pattern pattern = java.util.regex.Pattern.compile("\\b\\d+\\.\\d+\\b");
        java.util.regex.Matcher matcher = pattern.matcher(data);

        StringBuffer result = new StringBuffer();
        while (matcher.find()) {
            try {
                double value = Double.parseDouble(matcher.group());
                double noise = generateLaplaceNoise(epsilon);
                String replacement = String.format("%.2f", Math.max(0, value + noise));
                matcher.appendReplacement(result, replacement);
            } catch (NumberFormatException e) {
                matcher.appendReplacement(result, matcher.group());
            }
        }
        matcher.appendTail(result);
        return result.toString();
    }

    private double generateLaplaceNoise(double epsilon) {
        double u = random.nextDouble() - 0.5;
        return -Math.signum(u) * Math.log(1 - 2 * Math.abs(u)) / epsilon;
    }

    /**
     * Check if content contains potential PHI
     */
    public boolean containsPHI(String content) {
        if (content == null) return false;

        return NAME_PATTERN.matcher(content).find() ||
                SSN_PATTERN.matcher(content).find() ||
                PHONE_PATTERN.matcher(content).find() ||
                EMAIL_PATTERN.matcher(content).find() ||
                ADDRESS_PATTERN.matcher(content).find();
    }

    /**
     * True for a raw SSN (NNN-NN-NNNN) — the one identifier regex catches cleanly enough to gate
     * generated output on. Broad PHI matching for anonymisation lives in {@link #containsPHI}.
     */
    public boolean containsRawSsn(String content) {
        if (content == null) return false;
        return SSN_PATTERN.matcher(content).find();
    }

    public enum AnonymizationLevel {
        MINIMAL,      // Remove direct identifiers only
        MODERATE,     // Remove identifiers + specific dates/locations
        AGGRESSIVE,   // Remove all potentially identifying information
        STATISTICAL   // Convert to statistical summaries only
    }
}
