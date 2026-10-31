package com.careconnect.service.ai;

import com.careconnect.model.Medication;
import com.careconnect.model.Patient;
import com.careconnect.model.Task;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.repository.MedicationRepository;
import com.careconnect.repository.TaskRepository;
import com.careconnect.repository.VitalsRepository;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.testsupport.fixtures.MedicationFixtures;
import com.careconnect.testsupport.fixtures.PatientFixtures;
import com.careconnect.testsupport.fixtures.TaskFixtures;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class RetrievalIndexingServiceTest {

    private static final Long PATIENT_ID = 5L;

    @Mock
    private RetrievalIndexChunkRepository chunkRepository;
    @Mock
    private MedicationRepository medicationRepository;
    @Mock
    private TaskRepository taskRepository;
    @Mock
    private VitalsRepository vitalsRepository;

    private RetrievalIndexingService service;
    private Patient patient;

    @BeforeEach
    void setUp() {
        service = new RetrievalIndexingService(
                chunkRepository, medicationRepository, taskRepository, vitalsRepository);
        lenient().when(chunkRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        patient = PatientFixtures.patientWithId(PATIENT_ID);
    }

    @Test
    void reindexMedication_replacesChunkForActiveMedication() {
        // Arrange
        when(medicationRepository.findById(10L))
                .thenReturn(Optional.of(MedicationFixtures.activeMedication(10L, patient)));

        // Act
        service.reindexMedication(10L, PATIENT_ID);

        // Assert
        verify(chunkRepository).deleteByPatientIdAndSourceRecordIdAndRecordType(
                PATIENT_ID, "medication-10", "MEDICATION");
        final ArgumentCaptor<RetrievalIndexChunk> saved = ArgumentCaptor.forClass(RetrievalIndexChunk.class);
        verify(chunkRepository).save(saved.capture());
        assertThat(saved.getValue().getPatientId()).isEqualTo(PATIENT_ID);
        assertThat(saved.getValue().getRecordType()).isEqualTo("MEDICATION");
        assertThat(saved.getValue().getSourceRecordId()).isEqualTo("medication-10");
        assertThat(saved.getValue().getChunkText()).isEqualTo(
                "Lisinopril 10mg is an active medication. The Lisinopril dose is 10mg."
                        + " Take Lisinopril 10mg by the oral route once daily.");
    }

    @Test
    void reindexMedication_removesChunkWhenMedicationDeactivated() {
        // Arrange
        when(medicationRepository.findById(10L))
                .thenReturn(Optional.of(MedicationFixtures.inactiveMedication(10L, patient)));

        // Act
        service.reindexMedication(10L, PATIENT_ID);

        // Assert
        verify(chunkRepository).deleteByPatientIdAndSourceRecordIdAndRecordType(
                PATIENT_ID, "medication-10", "MEDICATION");
        verify(chunkRepository, never()).save(any());
    }

    @Test
    void reindexMedication_removesChunkWhenMedicationDeleted() {
        // Arrange
        when(medicationRepository.findById(10L)).thenReturn(Optional.empty());

        // Act
        service.reindexMedication(10L, PATIENT_ID);

        // Assert
        verify(chunkRepository).deleteByPatientIdAndSourceRecordIdAndRecordType(
                PATIENT_ID, "medication-10", "MEDICATION");
        verify(chunkRepository, never()).save(any());
    }

    @Test
    void reindexTask_replacesChunkForExistingTask() {
        // Arrange
        final Task task = TaskFixtures.taskWithId(20L);
        task.setPatient(patient);
        when(taskRepository.findById(20L)).thenReturn(Optional.of(task));

        // Act
        service.reindexTask(20L, PATIENT_ID);

        // Assert
        verify(chunkRepository).deleteByPatientIdAndSourceRecordIdAndRecordType(
                PATIENT_ID, "task-20", "TASK");
        final ArgumentCaptor<RetrievalIndexChunk> saved = ArgumentCaptor.forClass(RetrievalIndexChunk.class);
        verify(chunkRepository).save(saved.capture());
        assertThat(saved.getValue().getSourceRecordId()).isEqualTo("task-20");
        assertThat(saved.getValue().getChunkText()).isEqualTo(
                "Check Vitals is a Health task scheduled for Wednesday, January 1, 2025 at 08:00."
                        + " Check Vitals repeats daily. Check Vitals details: Daily vitals check."
                        + " Check Vitals is pending and not yet completed.");
    }

    @Test
    void reindexTask_removesChunkWhenTaskDeleted() {
        // Arrange
        when(taskRepository.findById(20L)).thenReturn(Optional.empty());

        // Act
        service.reindexTask(20L, PATIENT_ID);

        // Assert
        verify(chunkRepository).deleteByPatientIdAndSourceRecordIdAndRecordType(
                PATIENT_ID, "task-20", "TASK");
        verify(chunkRepository, never()).save(any());
    }

    @Test
    void reindexMedication_writesEveryFactAsItsOwnSentence() {
        // Arrange: notes already ending in a period must not get a second one
        final Medication medication = MedicationFixtures.activeMedication(10L, patient);
        medication.setPrescribedBy("Dr. Rivera");
        medication.setStartDate("2026-10-01");
        medication.setEndDate("2026-12-31");
        medication.setNotes("Take with food.");
        when(medicationRepository.findById(10L)).thenReturn(Optional.of(medication));

        // Act
        service.reindexMedication(10L, PATIENT_ID);

        // Assert
        final ArgumentCaptor<RetrievalIndexChunk> saved = ArgumentCaptor.forClass(RetrievalIndexChunk.class);
        verify(chunkRepository).save(saved.capture());
        assertThat(saved.getValue().getChunkText()).isEqualTo(
                "Lisinopril 10mg is an active medication. The Lisinopril dose is 10mg."
                        + " Take Lisinopril 10mg by the oral route once daily."
                        + " Lisinopril was prescribed by Dr. Rivera."
                        + " Lisinopril was started on Thursday, October 1, 2026. Lisinopril ends on Thursday, December 31, 2026."
                        + " Lisinopril notes: Take with food.");
    }

    @Test
    void reindexTask_describesUntypedUnscheduledCompletedTask() {
        // Arrange
        final Task task = Task.builder().id(21L).name("Call pharmacy").isCompleted(true).patient(patient).build();
        when(taskRepository.findById(21L)).thenReturn(Optional.of(task));

        // Act
        service.reindexTask(21L, PATIENT_ID);

        // Assert
        final ArgumentCaptor<RetrievalIndexChunk> saved = ArgumentCaptor.forClass(RetrievalIndexChunk.class);
        verify(chunkRepository).save(saved.capture());
        assertThat(saved.getValue().getChunkText())
                .isEqualTo("Call pharmacy is a task. Call pharmacy is completed.");
    }

    @Test
    void reindexMedication_returnsTheSavedChunk() {
        when(medicationRepository.findById(10L))
                .thenReturn(Optional.of(MedicationFixtures.activeMedication(10L, patient)));

        final Optional<RetrievalIndexChunk> result = service.reindexMedication(10L, PATIENT_ID);

        assertThat(result).get()
                .extracting(RetrievalIndexChunk::getSourceRecordId).isEqualTo("medication-10");
    }

    @Test
    void reindexMedication_returnsEmptyWhenNoChunkWritten() {
        when(medicationRepository.findById(10L))
                .thenReturn(Optional.of(MedicationFixtures.inactiveMedication(10L, patient)));

        assertThat(service.reindexMedication(10L, PATIENT_ID)).isEmpty();
    }

    @Test
    void reindexTask_oneOffTaskWithVowelTypeReadsNaturally() {
        // Arrange: "once" marks a one-off task; "an" precedes a vowel
        final Task task = Task.builder().id(22L).name("Physical therapy").taskType("Appointment")
                .frequency("Once").isCompleted(false).patient(patient).build();
        when(taskRepository.findById(22L)).thenReturn(Optional.of(task));

        // Act
        service.reindexTask(22L, PATIENT_ID);

        // Assert
        final ArgumentCaptor<RetrievalIndexChunk> saved = ArgumentCaptor.forClass(RetrievalIndexChunk.class);
        verify(chunkRepository).save(saved.capture());
        assertThat(saved.getValue().getChunkText())
                .isEqualTo("Physical therapy is an Appointment task. Physical therapy is pending and not yet completed.");
    }

    @Test
    void reindexTask_blankTypeIsTreatedAsMissing() {
        final Task task = Task.builder().id(23L).name("Call pharmacy").taskType("  ")
                .isCompleted(false).patient(patient).build();
        when(taskRepository.findById(23L)).thenReturn(Optional.of(task));

        service.reindexTask(23L, PATIENT_ID);

        final ArgumentCaptor<RetrievalIndexChunk> saved = ArgumentCaptor.forClass(RetrievalIndexChunk.class);
        verify(chunkRepository).save(saved.capture());
        assertThat(saved.getValue().getChunkText())
                .isEqualTo("Call pharmacy is a task. Call pharmacy is pending and not yet completed.");
    }

    @Test
    void reindexMedication_instructionSentenceOmitsMissingParts() {
        // Arrange: no dosage or route, only a frequency
        final Medication medication = Medication.builder().id(30L).patient(patient)
                .medicationName("Vitamin D").frequency("once weekly").isActive(true).build();
        when(medicationRepository.findById(30L)).thenReturn(Optional.of(medication));

        // Act
        service.reindexMedication(30L, PATIENT_ID);

        // Assert
        final ArgumentCaptor<RetrievalIndexChunk> saved = ArgumentCaptor.forClass(RetrievalIndexChunk.class);
        verify(chunkRepository).save(saved.capture());
        assertThat(saved.getValue().getChunkText())
                .isEqualTo("Vitamin D is an active medication. Take Vitamin D once weekly.");
    }

    @Test
    void reindexMedication_omitsInstructionWhenNothingToSay() {
        final Medication medication = Medication.builder().id(31L).patient(patient)
                .medicationName("Saline spray").isActive(true).build();
        when(medicationRepository.findById(31L)).thenReturn(Optional.of(medication));

        service.reindexMedication(31L, PATIENT_ID);

        final ArgumentCaptor<RetrievalIndexChunk> saved = ArgumentCaptor.forClass(RetrievalIndexChunk.class);
        verify(chunkRepository).save(saved.capture());
        assertThat(saved.getValue().getChunkText()).isEqualTo("Saline spray is an active medication.");
    }

    @Test
    void reindexTask_calendarTaskWithIsoDateAndEmptyDescription() {
        // Arrange: the calendar saves an ISO date-time and an empty description
        final Task task = Task.builder().id(24L).name("Check Blood Sugar").taskType("HEALTH_CHECK")
                .date("2025-10-06T00:00:00.000").timeOfDay("07:30").description("")
                .isCompleted(false).patient(patient).build();
        when(taskRepository.findById(24L)).thenReturn(Optional.of(task));

        // Act
        service.reindexTask(24L, PATIENT_ID);

        // Assert
        final ArgumentCaptor<RetrievalIndexChunk> saved = ArgumentCaptor.forClass(RetrievalIndexChunk.class);
        verify(chunkRepository).save(saved.capture());
        assertThat(saved.getValue().getChunkText()).isEqualTo(
                "Check Blood Sugar is a HEALTH_CHECK task scheduled for Monday, October 6, 2025 at 07:30."
                        + " Check Blood Sugar is pending and not yet completed.");
    }

    @Test
    void reindexTask_keepsANonIsoDateAsEntered() {
        final Task task = Task.builder().id(25L).name("Check Blood Sugar").date("next Tuesday")
                .isCompleted(false).patient(patient).build();
        when(taskRepository.findById(25L)).thenReturn(Optional.of(task));

        service.reindexTask(25L, PATIENT_ID);

        final ArgumentCaptor<RetrievalIndexChunk> saved = ArgumentCaptor.forClass(RetrievalIndexChunk.class);
        verify(chunkRepository).save(saved.capture());
        assertThat(saved.getValue().getChunkText()).startsWith("Check Blood Sugar is a task scheduled for next Tuesday.");
    }
}
