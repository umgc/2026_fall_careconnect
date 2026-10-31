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

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Synchronous, on-demand indexer for {@code retrieval_index_chunk} (Task 4.2),
 * triggered directly via {@code POST /v1/api/ai/index/{patientId}}
 * ({@link com.careconnect.controller.RetrievalIndexingController}).
 * Covers MEDICATION, TASK, and VITAL_SIGN record types only.
 *
 * <p><b>Not the same pipeline as
 * {@link com.careconnect.service.ai.indexing.IndexWorker} /
 * {@link com.careconnect.service.ai.indexing.RetrievalIndexService}</b>, which
 * asynchronously drains {@code indexing_outbox} and covers CALL_SUMMARY /
 * VISIT_SUMMARY, TRANSCRIPT_SEGMENT, and USPS_MAIL — a disjoint set of record
 * types. The two do not currently overlap, but both write into the same
 * {@code retrieval_index_chunk} table, so any new record type must be added to
 * exactly one of the two paths, not both, or {@code sourceRecordId} values
 * and chunk shapes can diverge for the same logical record.
 *
 * <p>Medications and tasks are also re-indexed one record at a time after every
 * committed create, update, or delete ({@link RetrievalRecordChangeListener} and
 * {@link RetrievalRecordIndexer}), so records entered in the app are answerable
 * by Ask AI without calling the endpoint. {@link RetrievalRecordIndexer} embeds those
 * per-record chunks as soon as they commit so the vector arm finds them too;
 * {@link #indexPatient}, which can write hundreds of chunks in one request, leaves
 * embedding to the backfill worker.
 * {@link #indexPatient} remains for manual/admin re-index and local dev/test seeding.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class RetrievalIndexingService {

    private static final DateTimeFormatter HUMAN_DATE =
            DateTimeFormatter.ofPattern("EEEE, MMMM d, yyyy", Locale.US);

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
            chunkRepository.deleteByPatientIdAndSourceRecordIdAndRecordType(patientId, sourceId, recordType);

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

            chunkRepository.deleteByPatientIdAndSourceRecordIdAndRecordType(patientId, sourceId, recordType);

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

            chunkRepository.deleteByPatientIdAndSourceRecordIdAndRecordType(patientId, sourceId, recordType);

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

    /**
     * Replaces the chunk for one medication with its committed state. Inactive or
     * deleted medications end with no chunk, matching {@link #indexMedications}.
     *
     * @return the saved chunk, or empty when the medication now has none
     *
     * <p>Runs in its own transaction because callers invoke it after the
     * medication's transaction has committed.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public Optional<RetrievalIndexChunk> reindexMedication(Long medicationId, Long patientId) {
        String sourceId = "medication-" + medicationId;
        String recordType = RetrievalRecordType.MEDICATION.name();
        chunkRepository.deleteByPatientIdAndSourceRecordIdAndRecordType(patientId, sourceId, recordType);
        return medicationRepository.findById(medicationId)
                .filter(med -> Boolean.TRUE.equals(med.getIsActive()))
                .map(med -> saveChunk(patientId, sourceId, recordType, buildMedicationText(med)));
    }

    /**
     * Replaces the chunk for one task with its committed state. A deleted task
     * ends with no chunk.
     *
     * @return the saved chunk, or empty when the task no longer exists
     *
     * <p>Runs in its own transaction because callers invoke it after the task's
     * transaction has committed.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public Optional<RetrievalIndexChunk> reindexTask(Long taskId, Long patientId) {
        String sourceId = "task-" + taskId;
        String recordType = RetrievalRecordType.TASK.name();
        chunkRepository.deleteByPatientIdAndSourceRecordIdAndRecordType(patientId, sourceId, recordType);
        return taskRepository.findById(taskId)
                .map(task -> saveChunk(patientId, sourceId, recordType, buildTaskText(task)));
    }

    private RetrievalIndexChunk saveChunk(Long patientId, String sourceId, String recordType, String text) {
        return chunkRepository.save(RetrievalIndexChunk.builder()
                .patientId(patientId)
                .recordType(recordType)
                .sourceRecordId(sourceId)
                .chunkText(text)
                .build());
    }

    // Medication and task text is written one fact per sentence, each naming its
    // subject. Ask AI accepts a claim only when it quotes complete sentences that
    // mention what was asked about, and models quote fragments of a single long
    // "Key: value, Key: value" line, which fails that check. mock_data.sql builds
    // the seed chunks with the same wording; keep the two in step.
    private String buildMedicationText(Medication med) {
        String name = med.getMedicationName();
        StringBuilder sb = new StringBuilder(name);
        if (med.getDosage() != null) sb.append(' ').append(med.getDosage());
        sb.append(Boolean.TRUE.equals(med.getIsActive()) ? " is an active medication." : " is an inactive medication.");
        if (med.getDosage() != null) appendSentence(sb, "The " + name + " dose is " + med.getDosage());
        // One instruction sentence ("Take X 10mg by the oral route once daily") because
        // that is the sentence models compose when asked what a patient takes; written
        // as separate facts, their composite is not in the source and gets rejected.
        if (med.getDosage() != null || med.getRoute() != null || med.getFrequency() != null) {
            StringBuilder take = new StringBuilder("Take ").append(name);
            if (med.getDosage() != null) take.append(' ').append(med.getDosage());
            if (med.getRoute() != null) take.append(" by the ").append(med.getRoute()).append(" route");
            if (med.getFrequency() != null) take.append(' ').append(med.getFrequency());
            appendSentence(sb, take.toString());
        }
        if (med.getPrescribedBy() != null) appendSentence(sb, name + " was prescribed by " + med.getPrescribedBy());
        if (hasText(med.getStartDate())) appendSentence(sb, name + " was started on " + humanDate(med.getStartDate()));
        if (hasText(med.getEndDate())) appendSentence(sb, name + " ends on " + humanDate(med.getEndDate()));
        if (med.getNotes() != null) appendSentence(sb, name + " notes: " + med.getNotes());
        return sb.toString();
    }

    private String buildTaskText(Task task) {
        String name = task.getName();
        StringBuilder sb = new StringBuilder(name);
        String type = task.getTaskType() == null ? "" : task.getTaskType().trim();
        sb.append(type.isEmpty() ? " is a task" : " is " + article(type) + " " + type + " task");
        if (hasText(task.getDate())) sb.append(" scheduled for ").append(humanDate(task.getDate()));
        if (hasText(task.getTimeOfDay())) sb.append(" at ").append(task.getTimeOfDay().trim());
        sb.append('.');
        if (isRecurring(task.getFrequency())) appendSentence(sb, name + " repeats " + task.getFrequency());
        if (hasText(task.getDescription())) appendSentence(sb, name + " details: " + task.getDescription());
        // "pending" is how people ask about open tasks ("Do I have any pending tasks?").
        appendSentence(sb, name + (task.isCompleted() ? " is completed" : " is pending and not yet completed"));
        return sb.toString();
    }

    private static boolean hasText(String value) {
        return value != null && !value.isBlank();
    }

    // The calendar stores dates as ISO date-times ("2026-10-20T00:00:00.000"); the
    // time of day is a separate field, so only the date part belongs in the sentence.
    private static String datePart(String date) {
        String trimmed = date.trim();
        int t = trimmed.indexOf('T');
        return t == 10 ? trimmed.substring(0, t) : trimmed;
    }

    // People ask "anything in October?" or "what's on Wednesday?", so dates are written
    // the way they are asked about ("Wednesday, October 21, 2026"). Anything that is not
    // an ISO date is kept as entered.
    private static String humanDate(String date) {
        String day = datePart(date);
        try {
            return LocalDate.parse(day).format(HUMAN_DATE);
        } catch (DateTimeParseException e) {
            return day;
        }
    }

    private static String article(String word) {
        return "AEIOUaeiou".indexOf(word.charAt(0)) >= 0 ? "an" : "a";
    }

    // "once" is how the app marks a one-off task; "repeats once" would misdescribe it.
    private static boolean isRecurring(String frequency) {
        return frequency != null && !frequency.isBlank() && !"once".equalsIgnoreCase(frequency.trim());
    }

    private static void appendSentence(StringBuilder sb, String sentence) {
        String trimmed = sentence.trim();
        sb.append(' ').append(trimmed);
        if (!trimmed.endsWith(".") && !trimmed.endsWith("!") && !trimmed.endsWith("?")) {
            sb.append('.');
        }
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