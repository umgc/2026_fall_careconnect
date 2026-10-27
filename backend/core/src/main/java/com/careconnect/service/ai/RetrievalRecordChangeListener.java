package com.careconnect.service.ai;

import com.careconnect.model.Medication;
import com.careconnect.model.Patient;
import com.careconnect.model.Task;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;

import jakarta.persistence.PostPersist;
import jakarta.persistence.PostRemove;
import jakarta.persistence.PostUpdate;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;

/**
 * JPA entity listener on {@link Medication} and {@link Task} that announces every
 * create, update, and delete so the record's Ask AI chunk can be rebuilt.
 *
 * <p>Hooking the entity rather than the services catches every write path,
 * including {@code saveAll} in recurring-task generation and any service added
 * later. It only publishes; {@link RetrievalRecordIndexer} does the indexing
 * after the transaction commits, so a rolled-back write is never indexed.
 */
@Component
public class RetrievalRecordChangeListener {

    /** A medication or task changed; the indexer reloads its committed state. */
    public record RetrievalRecordChanged(RetrievalRecordType recordType, Long recordId, Long patientId) {
    }

    private final ApplicationEventPublisher eventPublisher;

    public RetrievalRecordChangeListener(final ApplicationEventPublisher eventPublisher) {
        this.eventPublisher = eventPublisher;
    }

    @PostPersist
    @PostUpdate
    @PostRemove
    void onChange(final Object entity) {
        if (entity instanceof Medication medication) {
            publish(RetrievalRecordType.MEDICATION, medication.getId(), medication.getPatient());
        } else if (entity instanceof Task task) {
            publish(RetrievalRecordType.TASK, task.getId(), task.getPatient());
        }
    }

    private void publish(final RetrievalRecordType recordType, final Long recordId, final Patient patient) {
        // Chunks are keyed by patient, so a record without one has nowhere to be indexed.
        if (recordId == null || patient == null || patient.getId() == null) {
            return;
        }
        eventPublisher.publishEvent(new RetrievalRecordChanged(recordType, recordId, patient.getId()));
    }
}
