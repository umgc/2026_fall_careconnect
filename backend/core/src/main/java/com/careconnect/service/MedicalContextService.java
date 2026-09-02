package com.careconnect.service;

import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.UploadedFileDTO;
import com.careconnect.model.*;
import com.careconnect.repository.*;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.Base64;
import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class MedicalContextService {

    private final PatientRepository patientRepository;
    private final MoodPainLogRepository moodPainLogRepository;
    private final ClinicalNotesRepository clinicalNotesRepository;
    private final MedicationRepository medicationRepository;
    private final VitalsRepository vitalsRepository;
    private final AllergyRepository allergyRepository;
    private final DocumentProcessingService documentProcessingService;

    public String buildPatientContext(Long patientId, ChatRequest request, UserAIConfig aiConfig) {
        StringBuilder context = new StringBuilder();

        // Get patient basic info
        Patient patient = patientRepository.findById(patientId).orElse(null);
        if (patient == null) {
            return "";
        }

        // Removed old system prompt - now handled by the main system prompt

        // Add system prompt if configured
        if (aiConfig.getSystemPrompt() != null && !aiConfig.getSystemPrompt().trim().isEmpty()) {
            context.append("System Instructions: ").append(aiConfig.getSystemPrompt()).append("\n\n");
        }

        // Patient basic information
        context.append("PATIENT INFORMATION:\n");
        context.append("Name: ").append(patient.getFirstName()).append(" ").append(patient.getLastName()).append("\n");
        if (patient.getDob() != null) {
            context.append("Date of Birth: ").append(patient.getDob()).append("\n");
        }
        if (patient.getGender() != null) {
            context.append("Gender: ").append(patient.getGender()).append("\n");
        }
        context.append("\n");

        // Add medical context based on configuration and request overrides
        if (shouldIncludeVitals(request, aiConfig)) {
            addVitalsContext(context, patientId);
        }

        if (shouldIncludeMedications(request, aiConfig)) {
            addMedicationsContext(context, patientId);
        }

        if (shouldIncludeNotes(request, aiConfig)) {
            addNotesContext(context, patientId);
        }

        if (shouldIncludeMoodPainLogs(request, aiConfig)) {
            addMoodPainLogsContext(context, patientId);
        }

        if (shouldIncludeAllergies(request, aiConfig)) {
            addAllergiesContext(context, patientId);
        }

        // Add any additional context from request
        if (request.getAdditionalContext() != null && !request.getAdditionalContext().isEmpty()) {
            context.append("ADDITIONAL CONTEXT:\n");
            for (String additionalInfo : request.getAdditionalContext()) {
                context.append("- ").append(additionalInfo).append("\n");
            }
            context.append("\n");
        }

        // Process uploaded files if any — gated by the documents data-source flag (WBS 3.15.7)
        if (shouldIncludeDocuments(request, aiConfig)
                && request.getUploadedFiles() != null && !request.getUploadedFiles().isEmpty()) {
            context.append("UPLOADED FILES:\n");
            for (com.careconnect.dto.UploadedFileDTO file : request.getUploadedFiles()) {
                context.append("File: ").append(file.getFilename()).append("\n");
                context.append("Type: ").append(file.getContentType()).append("\n");
                context.append("Content:\n");

                // Use the new DocumentProcessingService for content extraction
                String fileContent = documentProcessingService.extractTextContent(file);
                context.append(fileContent).append("\n");
                context.append("---\n\n");
            }
        }

        context.append("IMPORTANT: Always remind the patient to consult with their healthcare provider for medical advice, diagnosis, or treatment decisions. Your role is to provide supportive information, not medical diagnosis or treatment recommendations.\n");

        return context.toString();
    }

    private boolean shouldIncludeVitals(ChatRequest request, UserAIConfig aiConfig) {
        return request.getIncludeVitals() != null ? request.getIncludeVitals() : aiConfig.getIncludeVitalsByDefault();
    }

    private boolean shouldIncludeMedications(ChatRequest request, UserAIConfig aiConfig) {
        return request.getIncludeMedications() != null ? request.getIncludeMedications() : aiConfig.getIncludeMedicationsByDefault();
    }

    private boolean shouldIncludeNotes(ChatRequest request, UserAIConfig aiConfig) {
        return request.getIncludeNotes() != null ? request.getIncludeNotes() : aiConfig.getIncludeNotesByDefault();
    }

    private boolean shouldIncludeMoodPainLogs(ChatRequest request, UserAIConfig aiConfig) {
        return request.getIncludeMoodPainLogs() != null ? request.getIncludeMoodPainLogs() : aiConfig.getIncludeMoodPainByDefault();
    }

    private boolean shouldIncludeAllergies(ChatRequest request, UserAIConfig aiConfig) {
        return request.getIncludeAllergies() != null ? request.getIncludeAllergies() : aiConfig.getIncludeAllergiesByDefault();
    }

    // WBS 3.15.7: gate uploaded documents on the data-source flag.
    // Per-request override wins; null config (older records) defaults to include.
    boolean shouldIncludeDocuments(ChatRequest request, UserAIConfig aiConfig) {
        if (request.getIncludeDocuments() != null) {
            return request.getIncludeDocuments();
        }
        Boolean flag = aiConfig.getIncludeDocumentsByDefault();
        return flag == null || flag;
    }

    private void addVitalsContext(StringBuilder context, Long patientId) {
        try {
            // Get recent vitals (last 10 entries)
            List<Vital> recentVitals = vitalsRepository.findByPatientIdOrderByRecordedAtDesc(patientId);

            if (!recentVitals.isEmpty()) {
                context.append("RECENT VITALS:\n");
                // Limit to 10 most recent
                List<Vital> limitedVitals = recentVitals.stream().limit(10).collect(Collectors.toList());

                for (Vital vital : limitedVitals) {
                    context.append("Date: ").append(vital.getRecordedAt()).append("\n");
                    context.append("  Type: ").append(vital.getVitalType()).append("\n");
                    context.append("  Value: ").append(vital.getValue()).append("\n");
                    if (vital.getUnit() != null) {
                        context.append("  Unit: ").append(vital.getUnit()).append("\n");
                    }
                    context.append("\n");
                }
            }
        } catch (Exception e) {
            log.warn("Error retrieving vitals for patient {}: {}", patientId, e.getMessage());
        }
    }

    private void addMedicationsContext(StringBuilder context, Long patientId) {
        try {
            List<Medication> activeMedications = medicationRepository.findActiveByPatientId(patientId);

            if (!activeMedications.isEmpty()) {
                context.append("CURRENT MEDICATIONS:\n");
                for (Medication medication : activeMedications) {
                    context.append("- ").append(medication.getMedicationName());
                    if (medication.getDosage() != null) {
                        context.append(" (").append(medication.getDosage()).append(")");
                    }
                    if (medication.getFrequency() != null) {
                        context.append(" - ").append(medication.getFrequency());
                    }
                    if (medication.getNotes() != null) {
                        context.append(" - ").append(medication.getNotes());
                    }
                    context.append("\n");
                }
                context.append("\n");
            }
        } catch (Exception e) {
            log.warn("Error retrieving medications for patient {}: {}", patientId, e.getMessage());
        }
    }

    private void addNotesContext(StringBuilder context, Long patientId) {
        try {
            // Get recent clinical notes (last 5)
            List<ClinicalNote> recentNotes = clinicalNotesRepository
                    .findByPatientIdOrderByCreatedAtDesc(patientId);

            if (!recentNotes.isEmpty()) {
                context.append("RECENT CLINICAL NOTES:\n");
                // Limit to 5 most recent
                List<ClinicalNote> limitedNotes = recentNotes.stream().limit(5).collect(Collectors.toList());

                for (ClinicalNote note : limitedNotes) {
                    context.append("Date: ").append(note.getCreatedAt().toLocalDate()).append("\n");
                    context.append("Type: ").append(note.getNoteType()).append("\n");
                    context.append("Note: ").append(note.getContent()).append("\n");
                    if (note.getCaregiverId() != null) {
                        context.append("By: Provider ID ").append(note.getCaregiverId()).append("\n");
                    }
                    context.append("\n");
                }
            }
        } catch (Exception e) {
            log.warn("Error retrieving clinical notes for patient {}: {}", patientId, e.getMessage());
        }
    }

    private void addMoodPainLogsContext(StringBuilder context, Long patientId) {
        try {
            // Get patient entity first
            Patient patient = patientRepository.findById(patientId).orElse(null);
            if (patient == null) return;

            // Get recent mood/pain logs (last 10)
            List<MoodPainLog> recentLogs = moodPainLogRepository
                    .findByPatientOrderByTimestampDesc(patient);

            if (!recentLogs.isEmpty()) {
                context.append("RECENT MOOD/PAIN LOGS:\n");
                // Limit to 10 most recent
                List<MoodPainLog> limitedLogs = recentLogs.stream().limit(10).collect(Collectors.toList());

                for (MoodPainLog log : limitedLogs) {
                    context.append("Date: ").append(log.getTimestamp().toLocalDate()).append("\n");
                    if (log.getMoodValue() != null) {
                        context.append("  Mood: ").append(log.getMoodValue()).append("/10\n");
                    }
                    if (log.getPainValue() != null) {
                        context.append("  Pain: ").append(log.getPainValue()).append("/10\n");
                    }
                    if (log.getNote() != null) {
                        context.append("  Notes: ").append(log.getNote()).append("\n");
                    }
                    context.append("\n");
                }
            }
        } catch (Exception e) {
            log.warn("Error retrieving mood/pain logs for patient {}: {}", patientId, e.getMessage());
        }
    }

    private void addAllergiesContext(StringBuilder context, Long patientId) {
        try {
            List<Allergy> allergies = allergyRepository.findByPatientId(patientId);

            if (!allergies.isEmpty()) {
                context.append("KNOWN ALLERGIES:\n");
                for (Allergy allergy : allergies) {
                    context.append("- ").append(allergy.getAllergen());
                    if (allergy.getReaction() != null) {
                        context.append(" (Reaction: ").append(allergy.getReaction()).append(")");
                    }
                    if (allergy.getSeverity() != null) {
                        context.append(" [Severity: ").append(allergy.getSeverity()).append("]");
                    }
                    context.append("\n");
                }
                context.append("\n");
            }
        } catch (Exception e) {
            log.warn("Error retrieving allergies for patient {}: {}", patientId, e.getMessage());
        }
    }
}
