package com.careconnect.service;

import com.careconnect.model.Allergy;
import com.careconnect.model.SymptomEntry;
import org.springframework.stereotype.Component;

import java.util.List;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

/**
 * Builds AI context from patient medical history (allergies now, symptoms later)
 */
@Component
public class DeepSeekContextBuilder {

    private static final DateTimeFormatter TS =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
                    .withZone(ZoneId.systemDefault());

    private static String nz(String v) {
        return v == null ? "" : v;
    }

    public String buildAllergyContext(Long patientId, List<Allergy> allergies) {
        if (allergies == null || allergies.isEmpty()) {
            return "The patient has no known recorded drug allergies.";
        }

        StringBuilder context = new StringBuilder();
        context.append("Patient Allergy Record:\n");

        for (Allergy allergy : allergies) {
            context.append("- Allergen: ").append(allergy.getAllergen())
                    .append(" | Type: ").append(allergy.getAllergyType())
                    .append(" | Severity: ").append(allergy.getSeverity())
                    .append(" | Reaction: ").append(allergy.getReaction())
                    .append(" | Active: ").append(allergy.getIsActive())
                    .append("\n");
        }

        context.append("\nUse this allergy history to safely assist the patient.\n");
        return context.toString();
    }

    public String buildSymptomContext(Long patientId, List<SymptomEntry> symptoms) {
        if (symptoms == null || symptoms.isEmpty()) {
            return "No prior symptom entries on record.";
        }
        StringBuilder sb = new StringBuilder("Recent Symptom History:\n");
        for (SymptomEntry s : symptoms) {
            sb.append("- ").append(TS.format(s.getTakenAt()))
                    .append(" | key: ").append(nz(s.getSymptomKey()))
                    .append(" | value: ").append(nz(s.getSymptomValue()))
                    .append(" | severity: ").append(s.getSeverity() == null ? "" : s.getSeverity())
                    .append(" | completed: ").append(Boolean.TRUE.equals(s.getCompleted()))
                    .append("\n");
        }
        sb.append("\nUse this history to interpret the new symptom input.\n");
        return sb.toString();
    }
}

