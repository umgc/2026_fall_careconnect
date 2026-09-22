package com.careconnect.service;

import com.careconnect.dto.StmlSearchRequest;
import com.careconnect.dto.StmlSearchResponse;
import com.careconnect.dto.StmlSearchResponse.StmlSearchResultDTO;
import com.careconnect.model.Allergy;
import com.careconnect.model.ChatConversation;
import com.careconnect.model.ChatMessage;
import com.careconnect.model.ClinicalNote;
import com.careconnect.model.Medication;
import com.careconnect.model.Task;
import com.careconnect.repository.AllergyRepository;
import com.careconnect.repository.ChatConversationRepository;
import com.careconnect.repository.ChatMessageRepository;
import com.careconnect.repository.ClinicalNotesRepository;
import com.careconnect.repository.MedicationRepository;
import com.careconnect.repository.TaskRepository;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Service for STML-4 recall history search by keyword, sender, or date.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class StmlSearchService {

    private final ChatConversationRepository chatConversationRepository;
    private final ChatMessageRepository chatMessageRepository;
    private final ClinicalNotesRepository clinicalNotesRepository;
    private final TaskRepository taskRepository;
    private final MedicationRepository medicationRepository;
    private final AllergyRepository allergyRepository;

    /**
     * Searches recall history for a patient by keyword, sender, or date.
     *
     * @param request the search request
     * @return the search response with matching results
     */
    public StmlSearchResponse search(final StmlSearchRequest request) {
        Long patientId = request.getPatientId();
        String keyword = request.getKeyword() != null
                ? request.getKeyword().toLowerCase() : null;
        String sender = request.getSender() != null
                ? request.getSender().toLowerCase() : null;

        List<StmlSearchResultDTO> results = new ArrayList<>();

        try {
            List<ChatConversation> conversations = chatConversationRepository
                    .findByPatientIdAndIsActiveTrueOrderByUpdatedAtDesc(patientId);
            for (ChatConversation conv : conversations) {
                List<ChatMessage> messages = chatMessageRepository
                        .findByConversationOrderByCreatedAtAsc(conv);
                for (ChatMessage msg : messages) {
                    if (!matchesFilters(msg.getContent(),
                            msg.getMessageType().getValue(),
                            msg.getCreatedAt(),
                            keyword, sender, request)) {
                        continue;
                    }
                    results.add(StmlSearchResultDTO.builder()
                            .sourceType("CHAT_MESSAGE")
                            .content(truncate(msg.getContent(), 200))
                            .sender(msg.getMessageType().getValue())
                            .date(msg.getCreatedAt().toLocalDate().toString())
                            .conversationId(conv.getConversationId())
                            .build());
                }
            }
        } catch (Exception e) {
            log.warn("Could not search chat messages for patient {}: {}",
                    patientId, e.getMessage());
        }

        try {
            List<ClinicalNote> notes = clinicalNotesRepository
                    .findByPatientIdOrderByCreatedAtDesc(patientId);
            for (ClinicalNote note : notes) {
                if (!matchesFilters(note.getContent(),
                        "PROVIDER",
                        note.getCreatedAt(),
                        keyword, sender, request)) {
                    continue;
                }
                results.add(StmlSearchResultDTO.builder()
                        .sourceType("CLINICAL_NOTE")
                        .content(truncate(note.getContent(), 200))
                        .sender("PROVIDER")
                        .date(note.getCreatedAt().toLocalDate().toString())
                        .conversationId(null)
                        .build());
            }
        } catch (Exception e) {
            log.warn("Could not search clinical notes for patient {}: {}",
                    patientId, e.getMessage());
        }

        try {
            List<Task> tasks = taskRepository
                    .findByPatientId(patientId).orElse(List.of());
            for (Task task : tasks) {
                String content = task.getName()
                        + (task.getDescription() != null ? " " + task.getDescription() : "");
                if (keyword != null && !content.toLowerCase().contains(keyword)) {
                    continue;
                }
                LocalDateTime taskDate = task.getDate() != null
                        ? LocalDate.parse(task.getDate()).atStartOfDay()
                        : LocalDateTime.now();
                if (!matchesDateFilter(taskDate, request)) {
                    continue;
                }
                results.add(StmlSearchResultDTO.builder()
                        .sourceType("TASK")
                        .content(content)
                        .sender("SYSTEM")
                        .date(task.getDate())
                        .conversationId(null)
                        .build());
            }
        } catch (Exception e) {
            log.warn("Could not search tasks for patient {}: {}",
                    patientId, e.getMessage());
        }

        try {
            List<Medication> meds = medicationRepository.findActiveByPatientId(patientId);
            for (Medication med : meds) {
                String content = med.getMedicationName()
                        + (med.getDosage() != null ? " " + med.getDosage() : "");
                if (keyword != null && !content.toLowerCase().contains(keyword)) {
                    continue;
                }
                results.add(StmlSearchResultDTO.builder()
                        .sourceType("MEDICATION")
                        .content(content)
                        .sender("PROVIDER")
                        .date(null)
                        .conversationId(null)
                        .build());
            }
        } catch (Exception e) {
            log.warn("Could not search medications for patient {}: {}",
                    patientId, e.getMessage());
        }

        try {
            List<Allergy> allergies = allergyRepository.findByPatientId(patientId);
            for (Allergy a : allergies) {
                String content = a.getAllergen()
                        + (a.getReaction() != null ? " " + a.getReaction() : "");
                if (keyword != null && !content.toLowerCase().contains(keyword)) {
                    continue;
                }
                results.add(StmlSearchResultDTO.builder()
                        .sourceType("ALLERGY")
                        .content(content)
                        .sender("PROVIDER")
                        .date(null)
                        .conversationId(null)
                        .build());
            }
        } catch (Exception e) {
            log.warn("Could not search allergies for patient {}: {}",
                    patientId, e.getMessage());
        }

        return StmlSearchResponse.builder()
                .patientId(patientId)
                .keyword(request.getKeyword())
                .totalResults(results.size())
                .results(results)
                .searchedAt(LocalDateTime.now())
                .build();
    }

    /**
     * Checks if a record matches the keyword, sender, and date filters.
     *
     * @param content     the record content
     * @param senderValue the sender type
     * @param recordDate  the record date
     * @param keyword     the keyword filter
     * @param sender      the sender filter
     * @param request     the full search request
     * @return true if matches all filters
     */
    private boolean matchesFilters(
            final String content,
            final String senderValue,
            final LocalDateTime recordDate,
            final String keyword,
            final String sender,
            final StmlSearchRequest request) {
        if (keyword != null && (content == null
                || !content.toLowerCase().contains(keyword))) {
            return false;
        }
        if (sender != null && !senderValue.toLowerCase().contains(sender)) {
            return false;
        }
        return matchesDateFilter(recordDate, request);
    }

    /**
     * Checks if a record date falls within the requested date range.
     *
     * @param recordDate the date of the record
     * @param request    the search request with date filters
     * @return true if within range
     */
    private boolean matchesDateFilter(
            final LocalDateTime recordDate,
            final StmlSearchRequest request) {
        if (request.getFromDate() != null && recordDate != null) {
            LocalDate from = LocalDate.parse(request.getFromDate());
            if (recordDate.toLocalDate().isBefore(from)) {
                return false;
            }
        }
        if (request.getToDate() != null && recordDate != null) {
            LocalDate to = LocalDate.parse(request.getToDate());
            if (recordDate.toLocalDate().isAfter(to)) {
                return false;
            }
        }
        return true;
    }

    /**
     * Truncates content to a maximum length.
     *
     * @param content   the content to truncate
     * @param maxLength the maximum length
     * @return truncated content
     */
    private String truncate(final String content, final int maxLength) {
        if (content == null) {
            return null;
        }
        if (content.length() <= maxLength) {
            return content;
        }
        return content.substring(0, maxLength) + "...";
    }
}