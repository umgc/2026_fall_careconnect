package com.careconnect.service;

import com.careconnect.model.Vital;
import com.careconnect.model.ClinicalNote;
import com.careconnect.model.UserAIConfig;
import com.careconnect.dto.ChatRequest;
import com.careconnect.repository.VitalsRepository;
import com.careconnect.repository.ClinicalNotesRepository;
import com.careconnect.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.stream.Collectors;

@Service
@Slf4j
@RequiredArgsConstructor
public class PrivacyAwareMedicalContextService {

    private final MedicalDataAnonymizer anonymizer;
    private final VitalsRepository vitalsRepository;
    private final ClinicalNotesRepository clinicalNotesRepository;
    private final UserRepository userRepository;

    /**
     * Build anonymized patient context for AI consumption
     */
    public String buildAnonymizedPatientContext(Long patientId, ChatRequest request,
                                                UserAIConfig aiConfig) {
        StringBuilder context = new StringBuilder();

        // Add privacy disclaimer at the start
        context.append("PRIVACY NOTICE: This data has been anonymized. Do not attempt patient identification.\n\n");

        // Add anonymized patient demographics (always include basic demographics)
        context.append(buildAnonymizedDemographics(patientId));

        // Add anonymized vitals with statistical summaries
        if (request.isIncludeVitals() && aiConfig.getIncludeVitalsByDefault()) {
            context.append(buildAnonymizedVitals(patientId, request.getAnonymizationLevel()));
        }

        // Add generalized medication information
        if (request.isIncludeMedications() && aiConfig.getIncludeMedicationsByDefault()) {
            context.append(buildGeneralizedMedications(patientId));
        }

        // Add clinical notes summary
        if (request.isIncludeNotes() && aiConfig.getIncludeNotesByDefault()) {
            context.append(buildAnonymizedClinicalNotes(patientId, request.getAnonymizationLevel()));
        }

        // Add system prompt with medical disclaimer
        context.append("\n").append(buildMedicalDisclaimer());

        // Apply final anonymization pass
        String finalContext = anonymizer.anonymizePatientContext(
                context.toString(),
                patientId,
                request.getAnonymizationLevel()
        );

        // Add differential privacy noise if enabled
        if (request.isEnableDifferentialPrivacy()) {
            finalContext = anonymizer.addDifferentialPrivacyNoise(finalContext, 0.1);
        }

        return finalContext;
    }

    private String buildAnonymizedDemographics(Long patientId) {
        var user = userRepository.findById(patientId).orElse(null);
        if (user == null) {
            return "Patient Demographics: Information not available\n\n";
        }

        return String.format(
                "Patient Demographics:\n" +
                        "- ID: %s\n" +
                        "- Age Range: %s\n" +
                        "- Gender: %s\n" +
                        "- General Location: %s\n" +
                        "- Account Status: Active\n\n",
                anonymizer.generatePseudoId(patientId),
                "Adult", // Generalized age
                "Not Specified", // Generalized gender
                "United States" // Generalized location
        );
    }

    private String buildAnonymizedVitals(Long patientId, MedicalDataAnonymizer.AnonymizationLevel level) {
        List<Vital> recentVitals = vitalsRepository.findRecentByPatientId(patientId,
                org.springframework.data.domain.PageRequest.of(0, 10));

        if (recentVitals.isEmpty()) {
            return "Recent Vitals: No recent vital signs recorded\n\n";
        }

        StringBuilder vitalsContext = new StringBuilder("Recent Vitals Summary:\n");

        var vitalsByType = recentVitals.stream()
                .collect(Collectors.groupingBy(Vital::getVitalType));

        vitalsByType.forEach((type, vitals) -> {
            if (level == MedicalDataAnonymizer.AnonymizationLevel.STATISTICAL) {
                vitalsContext.append(String.format("- %s: Statistical data available (%d readings)\n",
                        type, vitals.size()));
            } else {
                String summary = buildVitalSummary(type, vitals, level);
                vitalsContext.append(summary);
            }
        });

        vitalsContext.append("\n");
        return vitalsContext.toString();
    }

    private String buildVitalSummary(String vitalType, List<Vital> vitals,
                                     MedicalDataAnonymizer.AnonymizationLevel level) {
        if (vitals.isEmpty()) return "";

        // Get recent values (anonymized)
        String recentValues = vitals.stream()
                .limit(3)
                .map(v -> anonymizeVitalValue(v.getValue(), level))
                .collect(Collectors.joining(", "));

        // Calculate trend
        String trend = analyzeTrend(vitals);

        return String.format("- %s: Recent readings [%s] (Trend: %s)\n",
                vitalType, recentValues, trend);
    }

    private String anonymizeVitalValue(String value, MedicalDataAnonymizer.AnonymizationLevel level) {
        if (level == MedicalDataAnonymizer.AnonymizationLevel.AGGRESSIVE) {
            // Return ranges instead of specific values
            try {
                if (value.contains("/")) {
                    // Blood pressure
                    String[] parts = value.split("/");
                    int systolic = Integer.parseInt(parts[0]);
                    int diastolic = Integer.parseInt(parts[1]);
                    return categorizeBloodPressure(systolic, diastolic);
                } else {
                    // Other vitals
                    double numValue = Double.parseDouble(value);
                    return categorizeVital(numValue);
                }
            } catch (NumberFormatException e) {
                return "normal range";
            }
        }
        return value; // For minimal/moderate, keep actual values
    }

    private String categorizeBloodPressure(int systolic, int diastolic) {
        if (systolic >= 140 || diastolic >= 90) return "elevated range";
        if (systolic >= 130 || diastolic >= 80) return "high-normal range";
        return "normal range";
    }

    private String categorizeVital(double value) {
        // Simplified categorization - in production, use proper medical ranges
        return "normal range";
    }

    private String analyzeTrend(List<Vital> vitals) {
        if (vitals.size() < 2) return "insufficient data";

        // Simple trend analysis
        try {
            String firstValue = vitals.get(vitals.size() - 1).getValue();
            String lastValue = vitals.get(0).getValue();

            if (firstValue.contains("/") && lastValue.contains("/")) {
                // Blood pressure trend
                return "stable";
            } else {
                double first = Double.parseDouble(firstValue);
                double last = Double.parseDouble(lastValue);

                if (Math.abs(last - first) < first * 0.1) return "stable";
                return last > first ? "increasing" : "decreasing";
            }
        } catch (Exception e) {
            return "stable";
        }
    }

    private String buildGeneralizedMedications(Long patientId) {
        // In a real implementation, this would query a medications repository
        // For now, return a placeholder
        return "Current Medication Classes:\n" +
                "- Cardiovascular medications: Present\n" +
                "- Monitoring medications: As needed\n\n" +
                "Note: Specific medications generalized to drug classes for privacy\n\n";
    }

    private String buildAnonymizedClinicalNotes(Long patientId,
                                                MedicalDataAnonymizer.AnonymizationLevel level) {
        List<ClinicalNote> recentNotes = clinicalNotesRepository.findRecentByPatientId(patientId,
                org.springframework.data.domain.PageRequest.of(0, 3));

        if (recentNotes.isEmpty()) {
            return "Clinical Notes: No recent clinical notes available\n\n";
        }

        StringBuilder notesContext = new StringBuilder("Recent Clinical Notes Summary:\n");

        if (level == MedicalDataAnonymizer.AnonymizationLevel.STATISTICAL) {
            notesContext.append(String.format("- %d recent clinical notes available\n", recentNotes.size()));
            notesContext.append("- Content: Statistical summary only\n");
        } else {
            for (ClinicalNote note : recentNotes) {
                String anonymizedContent = anonymizer.anonymizePatientContext(
                        note.getContent(), patientId, level);
                notesContext.append(String.format("- %s: %s\n",
                        note.getNoteType(),
                        truncateContent(anonymizedContent, 100)));
            }
        }

        notesContext.append("\n");
        return notesContext.toString();
    }

    private String truncateContent(String content, int maxLength) {
        if (content == null || content.length() <= maxLength) {
            return content;
        }
        return content.substring(0, maxLength) + "...";
    }

    private String buildMedicalDisclaimer() {
        return "MEDICAL DISCLAIMER:\n" +
                "This AI assistant provides general health information only and should not replace \n" +
                "professional medical advice, diagnosis, or treatment. Always consult with qualified \n" +
                "healthcare providers for medical decisions. In case of emergency, contact emergency \n" +
                "services immediately.\n\n" +
                "The information provided is based on anonymized patient data and general medical \n" +
                "knowledge. Individual medical situations may vary significantly.\n";
    }

    /**
     * Check if the built context contains PHI
     */
    public boolean contextContainsPHI(String context) {
        return anonymizer.containsPHI(context);
    }

    /**
     * Build minimal context for statistical queries only
     */
    public String buildStatisticalContext(Long patientId) {
        return String.format(
                "Statistical Patient Summary (ID: %s):\n" +
                        "- Demographic category: Adult patient\n" +
                        "- Health status: Active monitoring\n" +
                        "- Data points available: Vitals, medications, clinical notes\n" +
                        "- Privacy level: Maximum anonymization applied\n\n" +
                        "%s\n",
                anonymizer.generatePseudoId(patientId),
                buildMedicalDisclaimer()
        );
    }
}
