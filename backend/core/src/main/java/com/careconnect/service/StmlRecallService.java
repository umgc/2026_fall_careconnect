package com.careconnect.service;

import com.careconnect.dto.StmlRecallRequest;
import com.careconnect.dto.StmlRecallResponse;
import com.careconnect.dto.StmlRecallResponse.StmlRecallSourceDTO;
import com.careconnect.model.*;
import com.careconnect.repository.*;
import dev.langchain4j.data.message.SystemMessage;
import dev.langchain4j.data.message.UserMessage;
import dev.langchain4j.model.chat.ChatModel;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Service for STML-1 recall — answers patient questions from care records.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class StmlRecallService {

    private final ChatModel chatModel;
    private final MedicationRepository medicationRepository;
    private final AllergyRepository allergyRepository;
    private final VitalsRepository vitalsRepository;
    private final ClinicalNotesRepository clinicalNotesRepository;
    private final TaskRepository taskRepository;
    private final PatientRepository patientRepository;

    /**
     * Answers a patient recall question using grounded care record context.
     *
     * @param request the recall request containing patientId and question
     * @return the recall response with AI answer and source citations
     */
    public StmlRecallResponse recall(final StmlRecallRequest request) {
        Long patientId = request.getPatientId();

        StringBuilder context = new StringBuilder();
        List<StmlRecallSourceDTO> sources = new ArrayList<>();

        // Clinical notes
        try {
            List<ClinicalNote> notes = clinicalNotesRepository
                .findByPatientIdOrderByCreatedAtDesc(patientId)
                .stream().limit(5).toList();
            if (!notes.isEmpty()) {
                context.append("RECENT CLINICAL NOTES:\n");
                for (ClinicalNote n : notes) {
                    String date = n.getCreatedAt().toLocalDate().toString();
                    String summary = n.getNoteType() + " on " + date + ": " + n.getContent();
                    context.append("- ").append(summary).append("\n");
                    sources.add(StmlRecallSourceDTO.builder()
                        .sourceType("NOTE")
                        .summary(n.getContent())
                        .date(date)
                        .build());
                }
                context.append("\n");
            }
        } catch (Exception e) {
            log.warn("Could not load notes for patient {}: {}", patientId, e.getMessage());
        }

        // Medications
        try {
            List<Medication> meds = medicationRepository.findActiveByPatientId(patientId);
            if (!meds.isEmpty()) {
                context.append("CURRENT MEDICATIONS:\n");
                for (Medication m : meds) {
                    String summary = m.getMedicationName()
                        + (m.getDosage() != null ? " " + m.getDosage() : "")
                        + (m.getFrequency() != null ? ", " + m.getFrequency() : "");
                    context.append("- ").append(summary).append("\n");
                    sources.add(StmlRecallSourceDTO.builder()
                        .sourceType("MEDICATION")
                        .summary(summary)
                        .date(null)
                        .build());
                }
                context.append("\n");
            }
        } catch (Exception e) {
            log.warn("Could not load medications for patient {}: {}", patientId, e.getMessage());
        }

        // Tasks
        try {
            List<Task> tasks = taskRepository.findByPatientId(patientId).orElse(List.of());
            List<Task> pending = tasks.stream().filter(t -> !t.isCompleted()).toList();
            if (!pending.isEmpty()) {
                context.append("PENDING TASKS:\n");
                for (Task t : pending) {
                    String summary = t.getName()
                        + (t.getDescription() != null ? ": " + t.getDescription() : "")
                        + (t.getDate() != null ? " (due " + t.getDate() + ")" : "");
                    context.append("- ").append(summary).append("\n");
                    sources.add(StmlRecallSourceDTO.builder()
                        .sourceType("TASK")
                        .summary(summary)
                        .date(t.getDate())
                        .build());
                }
                context.append("\n");
            }
        } catch (Exception e) {
            log.warn("Could not load tasks for patient {}: {}", patientId, e.getMessage());
        }

        // Allergies
        try {
            List<Allergy> allergies = allergyRepository.findByPatientId(patientId);
            if (!allergies.isEmpty()) {
                context.append("KNOWN ALLERGIES:\n");
                for (Allergy a : allergies) {
                    String summary = a.getAllergen()
                        + (a.getReaction() != null ? " - " + a.getReaction() : "");
                    context.append("- ").append(summary).append("\n");
                    sources.add(StmlRecallSourceDTO.builder()
                        .sourceType("ALLERGY")
                        .summary(summary)
                        .date(null)
                        .build());
                }
                context.append("\n");
            }
        } catch (Exception e) {
            log.warn("Could not load allergies for patient {}: {}", patientId, e.getMessage());
        }

        // Call AI
        String systemPrompt = "You are a friendly care assistant helping a patient with short-term memory limitations. "
            + "Answer their recall question using ONLY the care records provided below. "
            + "Use plain, simple language. "
            + "If the records do not contain enough information to answer, say so clearly and kindly. "
            + "Do not make up information. Keep your answer under 100 words.\n\nCARE RECORDS:\n" + context;

        String answer;
        try {
            var response = chatModel.chat(List.of(
                SystemMessage.from(systemPrompt),
                UserMessage.from(request.getQuestion())
            ));
            answer = response.aiMessage().text();
        } catch (Exception e) {
            log.error("AI call failed for STML recall: {}", e.getMessage());
            answer = "I was unable to find an answer right now. Please try again.";
        }

        return StmlRecallResponse.builder()
            .answer(answer)
            .sources(sources)
            .disclaimer("This information is drawn from your care records. It is not medical advice.")
            .generatedAt(LocalDateTime.now())
            .build();
    }
}   