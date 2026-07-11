package com.careconnect.service.ai;

import com.careconnect.model.Medication;
import com.careconnect.model.Task;
import com.careconnect.model.Vital;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.repository.MedicationRepository;
import com.careconnect.repository.TaskRepository;
import com.careconnect.repository.VitalsRepository;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Indexes patient records into retrieval_index_chunk for Ask AI (Task 4.2).
 * Covers MEDICATION, TASK, and VITAL_SIGN record types.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class RetrievalIndexingService {

    private final RetrievalIndexChunkRepository chunkRepository;
    private final MedicationRepository medicationRepository;
    private final TaskRepository taskRepository;
    private final VitalsRepository vitalsRepository;

    /**
     * Indexes all supported record types for a patient.
     * Existing chunks for each source record are replaced to avoid duplicates.
     *
     * @param patientId the patient entity ID
     * @return total number of chunks indexed
     */
    @Transactional
    public int indexPatient(Long patientId) {
        log.info("Starting full index for patientId={}", patientId);
        int total = 0;
        total += indexMedications(patientId);
        total += indexTasks(patientId);
        total += indexVitals(patientId);
        log.info("Completed full index for patientId={} — {} chunks written", patientId, total);
        return total;
    }

    /**
     * Indexes active medications for a patient.
     */
    @Transactional
    public int indexMedications(Long patientId) {
        List<Medication> meds = medicationRepository.findActiveByPatientId(patientId);
        int count = 0;
        for (Medication med : meds) {
            String sourceId = "medication-" + med.getId();
            String recordType = RetrievalRecordType.MEDICATION.name();

            // Delete existing chunk for this source record to avoid duplicates
            chunkRepository.deleteBySourceRecordIdAndRecordType(sourceId, recordType);

            String text = buildMedicationText(med);
            RetrievalIndexChunk chunk = RetrievalIndexChunk.builder()
                    .patientId(patientId)
                    .recordType(recordType)
                    .sourceRecordId(sourceId)
                    .chunkText(text)
                    .build();
            chunkRepository.save(chunk);
            count++;
        }
        log.info("Indexed {} medication chunks for patientId={}", count, patientId);
        return count;
    }

    /**
     * Indexes tasks for a patient.
     */
    @Transactional
    public int indexTasks(Long patientId) {
        List<Task> tasks = taskRepository.findByPatientId(patientId).orElse(List.of());
        int count = 0;
        for (Task task : tasks) {
            String sourceId = "task-" + task.getId();
            String recordType = RetrievalRecordType.TASK.name();

            chunkRepository.deleteBySourceRecordIdAndRecordType(sourceId, recordType);

            String text = buildTaskText(task);
            RetrievalIndexChunk chunk = RetrievalIndexChunk.builder()
                    .patientId(patientId)
                    .recordType(recordType)
                    .sourceRecordId(sourceId)
                    .chunkText(text)
                    .build();
            chunkRepository.save(chunk);
            count++;
        }
        log.info("Indexed {} task chunks for patientId={}", count, patientId);
        return count;
    }

    /**
     * Indexes vitals for a patient.
     */
    @Transactional
    public int indexVitals(Long patientId) {
        List<Vital> vitals = vitalsRepository.findByPatientIdOrderByRecordedAtDesc(patientId);
        int count = 0;
        for (Vital vital : vitals) {
            String sourceId = "vital-" + vital.getId();
            String recordType = RetrievalRecordType.VITAL_SIGN.name();

            chunkRepository.deleteBySourceRecordIdAndRecordType(sourceId, recordType);

            String text = buildVitalText(vital);
            RetrievalIndexChunk chunk = RetrievalIndexChunk.builder()
                    .patientId(patientId)
                    .recordType(recordType)
                    .sourceRecordId(sourceId)
                    .chunkText(text)
                    .build();
            chunkRepository.save(chunk);
            count++;
        }
        log.info("Indexed {} vital chunks for patientId={}", count, patientId);
        return count;
    }

    private String buildMedicationText(Medication med) {
        StringBuilder sb = new StringBuilder();
        sb.append("Medication: ").append(med.getMedicationName());
        if (med.getDosage() != null) sb.append(", Dosage: ").append(med.getDosage());
        if (med.getFrequency() != null) sb.append(", Frequency: ").append(med.getFrequency());
        if (med.getRoute() != null) sb.append(", Route: ").append(med.getRoute());
        if (med.getPrescribedBy() != null) sb.append(", Prescribed by: ").append(med.getPrescribedBy());
        if (med.getStartDate() != null) sb.append(", Start date: ").append(med.getStartDate());
        if (med.getEndDate() != null) sb.append(", End date: ").append(med.getEndDate());
        if (med.getNotes() != null) sb.append(". Notes: ").append(med.getNotes());
        sb.append(". Status: ").append(Boolean.TRUE.equals(med.getIsActive()) ? "Active" : "Inactive");
        return sb.toString();
    }

    private String buildTaskText(Task task) {
        StringBuilder sb = new StringBuilder();
        sb.append("Task: ").append(task.getName());
        if (task.getTaskType() != null) sb.append(", Type: ").append(task.getTaskType());
        if (task.getDescription() != null) sb.append(", Description: ").append(task.getDescription());
        if (task.getDate() != null) sb.append(", Date: ").append(task.getDate());
        if (task.getTimeOfDay() != null) sb.append(", Time: ").append(task.getTimeOfDay());
        if (task.getFrequency() != null) sb.append(", Frequency: ").append(task.getFrequency());
        sb.append(", Completed: ").append(task.isCompleted() ? "Yes" : "No");
        return sb.toString();
    }

    private String buildVitalText(Vital vital) {
        StringBuilder sb = new StringBuilder();
        sb.append("Vital sign: ").append(vital.getVitalType());
        sb.append(", Value: ").append(vital.getValue());
        if (vital.getUnit() != null) sb.append(" ").append(vital.getUnit());
        if (vital.getRecordedAt() != null) sb.append(", Recorded at: ").append(vital.getRecordedAt());
        if (vital.getNotes() != null) sb.append(". Notes: ").append(vital.getNotes());
        sb.append(", Abnormal: ").append(Boolean.TRUE.equals(vital.getIsAbnormal()) ? "Yes" : "No");
        return sb.toString();
    }
}