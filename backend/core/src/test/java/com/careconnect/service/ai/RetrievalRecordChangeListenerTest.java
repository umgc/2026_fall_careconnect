package com.careconnect.service.ai;

import com.careconnect.model.Medication;
import com.careconnect.model.Task;
import com.careconnect.service.ai.RetrievalRecordChangeListener.RetrievalRecordChanged;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.testsupport.fixtures.MedicationFixtures;
import com.careconnect.testsupport.fixtures.PatientFixtures;
import com.careconnect.testsupport.fixtures.TaskFixtures;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationEventPublisher;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class RetrievalRecordChangeListenerTest {

    @Mock
    private ApplicationEventPublisher eventPublisher;

    private RetrievalRecordChangeListener listener;

    @BeforeEach
    void setUp() {
        listener = new RetrievalRecordChangeListener(eventPublisher);
    }

    @Test
    void onChange_publishesMedicationChange() {
        listener.onChange(MedicationFixtures.activeMedication(10L, PatientFixtures.patientWithId(5L)));

        verify(eventPublisher).publishEvent(new RetrievalRecordChanged(RetrievalRecordType.MEDICATION, 10L, 5L));
    }

    @Test
    void onChange_publishesTaskChange() {
        final Task task = TaskFixtures.taskWithId(20L);
        task.setPatient(PatientFixtures.patientWithId(5L));

        listener.onChange(task);

        verify(eventPublisher).publishEvent(new RetrievalRecordChanged(RetrievalRecordType.TASK, 20L, 5L));
    }

    @Test
    void onChange_skipsTaskWithoutPatient() {
        listener.onChange(TaskFixtures.taskWithId(20L));

        verify(eventPublisher, never()).publishEvent(any());
    }

    @Test
    void onChange_skipsPatientWithoutId() {
        final Medication medication = MedicationFixtures.activeMedication(10L, PatientFixtures.patientWithId(null));

        listener.onChange(medication);

        verify(eventPublisher, never()).publishEvent(any());
    }

    @Test
    void onChange_skipsRecordWithoutId() {
        listener.onChange(MedicationFixtures.activeMedication(null, PatientFixtures.patientWithId(5L)));

        verify(eventPublisher, never()).publishEvent(any());
    }

    @Test
    void onChange_ignoresOtherEntities() {
        listener.onChange(PatientFixtures.basicPatient());

        verify(eventPublisher, never()).publishEvent(any());
    }
}
