package com.careconnect.service;

import com.careconnect.ai.AIService;
import com.careconnect.dto.ChatResponse;
import com.careconnect.dto.StmlCheckInDTO;
import com.careconnect.dto.StmlRecallRequest;
import com.careconnect.dto.StmlRecallResponse;
import com.careconnect.dto.StmlSearchRequest;
import com.careconnect.dto.StmlSearchResponse;
import com.careconnect.model.Allergy;
import com.careconnect.model.ChatConversation;
import com.careconnect.model.ChatMessage;
import com.careconnect.model.ClinicalNote;
import com.careconnect.model.Medication;
import com.careconnect.model.Patient;
import com.careconnect.model.Task;
import com.careconnect.model.User;
import com.careconnect.repository.AllergyRepository;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.ChatConversationRepository;
import com.careconnect.repository.ChatMessageRepository;
import com.careconnect.repository.ClinicalNotesRepository;
import com.careconnect.repository.MedicationRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.TaskRepository;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class StmlServicesCoverageTest {

    @Mock private ChatConversationRepository chatConversationRepository;
    @Mock private ChatMessageRepository chatMessageRepository;
    @Mock private ClinicalNotesRepository clinicalNotesRepository;
    @Mock private TaskRepository taskRepository;
    @Mock private MedicationRepository medicationRepository;
    @Mock private AllergyRepository allergyRepository;
    @Mock private AIService aiService;
    @Mock private PatientRepository patientRepository;
    @Mock private CaregiverPatientLinkRepository caregiverPatientLinkRepository;
    @Mock private UserRepository userRepository;

    private final LocalDateTime now = LocalDateTime.of(2026, 5, 10, 9, 0);

    @BeforeEach
    void stubRecords() {
        ChatConversation conv = ChatConversation.builder().conversationId("conv-1").build();
        when(chatConversationRepository.findByPatientIdAndIsActiveTrueOrderByUpdatedAtDesc(anyLong()))
                .thenReturn(List.of(conv));
        when(chatMessageRepository.findByConversationOrderByCreatedAtAsc(conv)).thenReturn(List.of(
                ChatMessage.builder().messageType(ChatMessage.MessageType.USER)
                        .content("Remember the pharmacy appointment " + "x".repeat(250)).createdAt(now).build(),
                ChatMessage.builder().messageType(ChatMessage.MessageType.ASSISTANT)
                        .content("unrelated").createdAt(now).build(),
                ChatMessage.builder().messageType(ChatMessage.MessageType.USER)
                        .content("pharmacy too early").createdAt(now.minusYears(1)).build(),
                ChatMessage.builder().messageType(ChatMessage.MessageType.USER)
                        .content("pharmacy too late").createdAt(now.plusYears(1)).build(),
                ChatMessage.builder().messageType(ChatMessage.MessageType.SYSTEM)
                        .content("pharmacy system").createdAt(now).build()));
        when(clinicalNotesRepository.findByPatientIdOrderByCreatedAtDesc(anyLong())).thenReturn(List.of(
                ClinicalNote.builder().noteType("PLAN").content("pharmacy pickup").createdAt(now).build(),
                ClinicalNote.builder().noteType("PLAN").content(null).createdAt(now).build()));
        when(taskRepository.findByPatientId(anyLong())).thenReturn(Optional.of(List.of(
                Task.builder().name("Pharmacy visit").description("bring card").date("2026-05-10").build(),
                Task.builder().name("Pharmacy later").date(null).build(),
                Task.builder().name("Walk").date("2026-05-10").build(),
                Task.builder().name("Pharmacy old").date("2020-01-01").build(),
                Task.builder().name("Done pharmacy").isCompleted(true).date("2026-05-10").build())));
        when(medicationRepository.findActiveByPatientId(anyLong())).thenReturn(List.of(
                Medication.builder().medicationName("Pharmacyzol").dosage("10mg").frequency("daily").build(),
                Medication.builder().medicationName("Aspirin").build()));
        when(allergyRepository.findByPatientId(anyLong())).thenReturn(List.of(
                Allergy.builder().allergen("Pharmacy dust").reaction("sneeze").build(),
                Allergy.builder().allergen("Peanut").build()));
    }

    @Test
    void searchFiltersAcrossAllSources() {
        StmlSearchService service = new StmlSearchService(chatConversationRepository, chatMessageRepository,
                clinicalNotesRepository, taskRepository, medicationRepository, allergyRepository);
        StmlSearchRequest req = new StmlSearchRequest();
        req.setPatientId(1L);
        req.setKeyword("Pharmacy");
        req.setSender("user");
        req.setFromDate("2026-01-01");
        req.setToDate("2026-12-31");
        StmlSearchResponse resp = service.search(req);
        assertThat(resp.getTotalResults()).isGreaterThan(0);

        StmlSearchRequest all = new StmlSearchRequest();
        all.setPatientId(1L);
        assertThat(service.search(all).getTotalResults()).isGreaterThan(resp.getTotalResults());
    }

    @Test
    void searchToleratesRepositoryFailures() {
        when(chatConversationRepository.findByPatientIdAndIsActiveTrueOrderByUpdatedAtDesc(anyLong()))
                .thenThrow(new RuntimeException("x"));
        when(clinicalNotesRepository.findByPatientIdOrderByCreatedAtDesc(anyLong())).thenThrow(new RuntimeException("x"));
        when(taskRepository.findByPatientId(anyLong())).thenThrow(new RuntimeException("x"));
        when(medicationRepository.findActiveByPatientId(anyLong())).thenThrow(new RuntimeException("x"));
        when(allergyRepository.findByPatientId(anyLong())).thenThrow(new RuntimeException("x"));
        StmlSearchService service = new StmlSearchService(chatConversationRepository, chatMessageRepository,
                clinicalNotesRepository, taskRepository, medicationRepository, allergyRepository);
        StmlSearchRequest req = new StmlSearchRequest();
        req.setPatientId(1L);
        assertThat(service.search(req).getTotalResults()).isZero();
    }

    @Test
    void recallBuildsContextAndCallsAi() {
        StmlRecallService service = new StmlRecallService(aiService, medicationRepository, allergyRepository,
                clinicalNotesRepository, taskRepository, patientRepository);
        ChatResponse ai = new ChatResponse();
        ai.setAiResponse("You have a pharmacy visit.");
        when(aiService.processChat(any())).thenReturn(ai);
        StmlRecallRequest req = new StmlRecallRequest();
        req.setPatientId(1L);
        req.setQuestion("What is next?");
        StmlRecallResponse resp = service.recall(req);
        assertThat(resp.getAnswer()).contains("pharmacy");
        assertThat(resp.getSources()).isNotEmpty();
    }

    @Test
    void recallFallsBackWhenEverythingFails() {
        when(clinicalNotesRepository.findByPatientIdOrderByCreatedAtDesc(anyLong())).thenThrow(new RuntimeException("x"));
        when(taskRepository.findByPatientId(anyLong())).thenThrow(new RuntimeException("x"));
        when(medicationRepository.findActiveByPatientId(anyLong())).thenThrow(new RuntimeException("x"));
        when(allergyRepository.findByPatientId(anyLong())).thenThrow(new RuntimeException("x"));
        when(aiService.processChat(any())).thenThrow(new RuntimeException("ai down"));
        StmlRecallService service = new StmlRecallService(aiService, medicationRepository, allergyRepository,
                clinicalNotesRepository, taskRepository, patientRepository);
        StmlRecallRequest req = new StmlRecallRequest();
        req.setPatientId(1L);
        assertThat(service.recall(req).getAnswer()).contains("unable");
    }

    @Test
    void checkInViewWithConsentListsRecords() {
        User caregiver = User.builder().id(5L).build();
        User patientUser = User.builder().id(6L).build();
        when(userRepository.findById(5L)).thenReturn(Optional.of(caregiver));
        when(patientRepository.findById(1L)).thenReturn(Optional.of(Patient.builder().id(1L).user(patientUser).build()));
        when(caregiverPatientLinkRepository.existsActiveNonExpiredLink(any(), any(), any())).thenReturn(true);
        StmlCheckInService service = new StmlCheckInService(caregiverPatientLinkRepository, userRepository,
                patientRepository, clinicalNotesRepository, taskRepository, medicationRepository, allergyRepository);
        StmlCheckInDTO dto = service.getCheckInView(1L, 5L);
        assertThat(dto.isConsentGranted()).isTrue();
        assertThat(dto.getNotes()).isNotEmpty();
        assertThat(dto.getPendingItems()).isNotEmpty();

        when(clinicalNotesRepository.findByPatientIdOrderByCreatedAtDesc(anyLong())).thenThrow(new RuntimeException("x"));
        when(taskRepository.findByPatientId(anyLong())).thenThrow(new RuntimeException("x"));
        when(medicationRepository.findActiveByPatientId(anyLong())).thenThrow(new RuntimeException("x"));
        when(allergyRepository.findByPatientId(anyLong())).thenThrow(new RuntimeException("x"));
        assertThat(service.getCheckInView(1L, 5L).getNotes()).isEmpty();

        when(caregiverPatientLinkRepository.existsActiveNonExpiredLink(any(), any(), any())).thenReturn(false);
        assertThat(service.getCheckInView(1L, 5L).isConsentGranted()).isFalse();
    }

    @Test
    void dailyBriefListsOpenTasks() {
        StmlService service = new StmlService(taskRepository);
        assertThat(service.getDailyBrief(1L).getCards()).hasSize(4);
    }
}
