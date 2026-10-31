package com.careconnect.service;

import com.careconnect.dto.PatientNoteDTO;
import com.careconnect.dto.PatientNotetakerConfigDTO;
import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.model.Patient;
import com.careconnect.model.PatientNote;
import com.careconnect.model.PatientNotetakerConfig;
import com.careconnect.repository.PatientNoteRepository;
import com.careconnect.repository.PatientNotetakerConfigRepository;
import com.careconnect.service.ai.indexing.RetrievalIndexService;
import com.careconnect.service.v2.TaskServiceV2;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class PatientNotetakerConfigCoverageTest {

    @Mock private PatientNoteRepository patientNoteRepository;
    @Mock private PatientNotetakerConfigRepository configRepository;
    @Mock private PatientService patientService;
    @Mock private AIChatService aiChatService;
    @Mock private TaskServiceV2 taskService;
    @Mock private IndexingEventEmitter indexingEventEmitter;
    @Mock private RetrievalIndexService retrievalIndexService;

    private PatientNotetakerService service;

    @BeforeEach
    void setUp() {
        service = new PatientNotetakerService(patientNoteRepository, configRepository, patientService,
                aiChatService, taskService, indexingEventEmitter, retrievalIndexService);
        when(patientService.getPatientById(1L)).thenReturn(new Patient());
        when(configRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
    }

    @Test
    void createsThenUpdatesConfig() {
        PatientNotetakerConfigDTO dto = new PatientNotetakerConfigDTO(null, null, true, false, List.of(), null);
        when(configRepository.findByPatientId(1L)).thenReturn(null);
        assertThat(service.createOrUpdatePatientNotetakerConfig(1L, dto).getPatientId()).isEqualTo(1L);

        PatientNotetakerConfig existing = new PatientNotetakerConfig();
        when(configRepository.findByPatientId(1L)).thenReturn(existing);
        assertThat(service.createOrUpdatePatientNotetakerConfig(1L, dto).getIsEnabled()).isTrue();

        assertThatThrownBy(() -> service.createOrUpdatePatientNotetakerConfig(1L, null))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.createOrUpdatePatientNotetakerConfig(2L, dto))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void noteLookupsAndGuards() {
        PatientNote note = new PatientNote();
        note.setId(3L);
        note.setPatientId(1L);
        note.setNote("text");
        when(patientNoteRepository.findById(3L)).thenReturn(Optional.of(note));
        assertThat(service.getNoteById(1L, 3L).getNote()).isEqualTo("text");
        assertThatThrownBy(() -> service.getNoteById(1L, 4L)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.createNoteForPatient(1L, null)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.updateNoteForPatient(1L, 3L, null))
                .isInstanceOf(IllegalArgumentException.class);
        PatientNoteDTO update = new PatientNoteDTO();
        update.setNote("new text");
        update.setAiSummary("");
        when(patientNoteRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        assertThat(service.updateNoteForPatient(1L, 3L, update)).isNotNull();
    }
}
