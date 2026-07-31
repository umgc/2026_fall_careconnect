package com.careconnect.service;

import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.dto.PatientNoteDTO;
import com.careconnect.dto.PatientNotetakerConfigDTO;
import com.careconnect.dto.v2.TaskDtoV2;
import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.model.Patient;
import com.careconnect.model.PatientNote;
import com.careconnect.model.PatientNotetakerConfig;
import com.careconnect.model.PatientNotetakerKeyword;
import com.careconnect.model.PatientNotetakerKeyword.EventType;
import com.careconnect.repository.PatientNoteRepository;
import com.careconnect.repository.PatientNotetakerConfigRepository;
import com.careconnect.service.ai.indexing.RetrievalIndexService;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.service.v2.TaskServiceV2;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class PatientNotetakerServiceTest {

    @Mock private PatientNoteRepository patientNoteRepository;
    @Mock private PatientNotetakerConfigRepository patientNotetakerConfigRepository;
    @Mock private PatientService patientService;
    @Mock private AIChatService aiChatService;
    @Mock private TaskServiceV2 taskService;
    @Mock private IndexingEventEmitter indexingEventEmitter;
    @Mock private RetrievalIndexService retrievalIndexService;

    private PatientNotetakerService service;

    private Patient patient;
    private PatientNote patientNote;
    private PatientNotetakerConfig config;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);

        service = new PatientNotetakerService(
                patientNoteRepository,
                patientNotetakerConfigRepository,
                patientService,
                aiChatService,
                taskService,
                indexingEventEmitter,
                retrievalIndexService
        );

        patient = Patient.builder().id(10L).firstName("John").lastName("Doe").build();

        patientNote = PatientNote.builder()
                .id(1L)
                .patientId(10L)
                .note("Patient discussed symptoms")
                .aiSummary("Patient has symptoms")
                .createdAt(LocalDateTime.now())
                .updatedAt(LocalDateTime.now())
                .build();

        config = PatientNotetakerConfig.builder()
                .id(1L)
                .patientId(10L)
                .isEnabled(true)
                .permitCaregiverAccess(true)
                .triggerKeywords(List.of(
                        PatientNotetakerKeyword.builder().keyword("pain").eventType(EventType.ALERT).build(),
                        PatientNotetakerKeyword.builder().keyword("appointment").eventType(EventType.TASK).build()))
                .updatedAt(LocalDateTime.now())
                .build();
    }

    @Test
    @DisplayName("getNotetakerConfigByPatientId - valid patient with config")
    void getNotetakerConfigByPatientId_validPatientWithConfig() {
        when(patientService.getPatientById(10L)).thenReturn(patient);
        when(patientNotetakerConfigRepository.findByPatientId(10L)).thenReturn(config);

        PatientNotetakerConfigDTO result = service.getNotetakerConfigByPatientId(10L);

        assertNotNull(result);
        assertEquals(10L, result.getPatientId());
        assertTrue(result.getIsEnabled());
    }

    @Test
    @DisplayName("getAllNotesForPatient - patient has notes")
    void getAllNotesForPatient_patientHasNotes() {
        when(patientService.getPatientById(10L)).thenReturn(patient);
        when(patientNoteRepository.findByPatientId(10L)).thenReturn(Optional.of(List.of(patientNote)));

        List<PatientNoteDTO> result = service.getAllNotesForPatient(10L);

        assertEquals(1, result.size());
    }

    @Test
    @DisplayName("createNoteForPatient - AI summary success")
    void createNoteForPatient_aiSummarySuccess() {

        when(patientService.getPatientById(10L)).thenReturn(patient);

        ChatResponse response = new ChatResponse();
        response.setAiResponse("Summary of conversation");

        when(aiChatService.processChat(any(ChatRequest.class))).thenReturn(response);

        when(patientNoteRepository.save(any(PatientNote.class))).thenAnswer(inv -> {
            PatientNote saved = inv.getArgument(0);
            saved.setId(2L);
            return saved;
        });

        when(patientNotetakerConfigRepository.findByPatientId(10L)).thenReturn(null);

        PatientNoteDTO noteDTO = PatientNoteDTO.builder()
                .note("Doctor said take medicine daily")
                .aiSummary("")
                .build();

        PatientNoteDTO result = service.createNoteForPatient(10L, noteDTO);

        assertNotNull(result);
        verify(aiChatService).processChat(any(ChatRequest.class));
    }

    @Test
    @DisplayName("createNoteForPatient - AI failure handled")
    void createNoteForPatient_aiFailureHandled() {

        when(patientService.getPatientById(10L)).thenReturn(patient);

        when(aiChatService.processChat(any(ChatRequest.class)))
                .thenThrow(new RuntimeException("AI unavailable"));

        when(patientNoteRepository.save(any(PatientNote.class))).thenAnswer(inv -> {
            PatientNote saved = inv.getArgument(0);
            saved.setId(3L);
            return saved;
        });

        when(patientNotetakerConfigRepository.findByPatientId(10L)).thenReturn(null);

        PatientNoteDTO noteDTO = PatientNoteDTO.builder()
                .note("Some note content")
                .aiSummary("")
                .build();

        PatientNoteDTO result = service.createNoteForPatient(10L, noteDTO);

        assertNotNull(result);
    }

    @Test
    @DisplayName("createNoteForPatient - task keyword triggers task creation")
    void createNoteForPatient_keywordCreatesTask() {

        when(patientService.getPatientById(10L)).thenReturn(patient);

        ChatResponse summaryResponse = new ChatResponse();
        summaryResponse.setAiResponse("Summary");

        String taskJson =
                "{\"name\":\"Schedule appointment\",\"date\":\"2026-06-15\",\"daysOfWeek\":[true,false,false,false,false,false,false],\"description\":\"Follow-up appointment\",\"count\":1,\"frequency\":\"once\",\"taskType\":\"appointment\",\"timeOfDay\":\"10:00:00\"}";

        ChatResponse taskResponse = new ChatResponse();
        taskResponse.setAiResponse(taskJson);

        when(aiChatService.processChat(any(ChatRequest.class)))
                .thenReturn(summaryResponse)
                .thenReturn(taskResponse);

        when(patientNoteRepository.save(any(PatientNote.class))).thenAnswer(inv -> {
            PatientNote saved = inv.getArgument(0);
            saved.setId(9L);
            return saved;
        });

        when(patientNotetakerConfigRepository.findByPatientId(10L)).thenReturn(config);

        PatientNoteDTO noteDTO = PatientNoteDTO.builder()
                .note("Need to schedule an appointment for next month")
                .aiSummary("")
                .build();

        PatientNoteDTO result = service.createNoteForPatient(10L, noteDTO);

        assertNotNull(result);
        verify(taskService).createTask(eq(10L), any(TaskDtoV2.class));
    }

    @Test
    @DisplayName("updateNoteForPatient - uses provided summary")
    void updateNoteForPatient_usesProvidedSummary() {

        when(patientService.getPatientById(10L)).thenReturn(patient);
        when(patientNoteRepository.findById(1L)).thenReturn(Optional.of(patientNote));
        when(patientNoteRepository.save(any(PatientNote.class))).thenReturn(patientNote);

        PatientNoteDTO noteDTO = PatientNoteDTO.builder()
                .note("Updated note content")
                .aiSummary("Updated AI summary")
                .build();

        PatientNoteDTO result = service.updateNoteForPatient(10L, 1L, noteDTO);

        assertNotNull(result);
        assertEquals("Updated AI summary", patientNote.getAiSummary());
    }

    @Test
    @DisplayName("deleteNoteById de-indexes then deletes note")
    void deleteNoteById() {
        when(patientNoteRepository.findById(1L)).thenReturn(Optional.of(patientNote));

        service.deleteNoteById(1L);

        verify(retrievalIndexService).removeIndexedSource(
                10L, "1", RetrievalRecordType.CLINICAL_NOTE);
        verify(patientNoteRepository).delete(patientNote);
    }
}