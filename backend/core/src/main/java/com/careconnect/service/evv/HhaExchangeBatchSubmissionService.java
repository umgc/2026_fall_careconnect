package com.careconnect.service.evv;

import com.careconnect.model.evv.EvvRecord;
import com.careconnect.repository.evv.EvvRecordRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Service for submitting EVV visit data to the Virginia HHAExchange aggregator.
 * <p>
 * Handles three submission scenarios required by the Virginia DMAS EVV mandate:
 * <ol>
 *   <li><b>Batch submission</b> — submit a list of approved VA records in a single API call.</li>
 *   <li><b>Corrected-visit re-submission</b> — re-submit a single corrected record with the
 *       {@code editVisit.edited=true} flag set in the payload.</li>
 *   <li><b>Offline-captured data submission</b> — flush all offline-captured, approved VA records
 *       that are awaiting aggregator submission after being synced from a caregiver device.</li>
 * </ol>
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class HhaExchangeBatchSubmissionService {

    private final VirginiaHhaExchangeClient hhaClient;
    private final EvvRecordRepository evvRecordRepository;
    private final AuditLogger audit;

    // -------------------------------------------------------------------------
    // 1. Batch submission
    // -------------------------------------------------------------------------

    /**
     * Submit a batch of EVV records to HHAExchange by their database IDs.
     * <p>
     * Only records with {@code stateCode = "VA"} and {@code status = "APPROVED"} are included; any
     * IDs that do not meet these criteria are silently excluded (a warning is logged).
     *
     * @param recordIds IDs of the EVV records to submit
     * @param actorId   ID of the user triggering the submission (for audit trail)
     * @throws IllegalArgumentException if no eligible records are found
     * @throws Exception                if the HHAExchange API call fails
     */
    /**
     * Builds the HHAExchange JSON payload for the given record IDs without submitting it.
     * Only VA/APPROVED records are included. Returns the request object ready for serialization.
     *
     * @throws IllegalArgumentException if no eligible records are found
     */
    public Object buildPayload(List<Long> recordIds) {
        log.info("[HHAExchange] Building payload for record IDs: {}", recordIds);

        // Fetch records with Patient eagerly loaded to avoid lazy-loading errors
        List<EvvRecord> records = evvRecordRepository.findAllByIdWithPatient(recordIds);
        log.info("[HHAExchange] Fetched {} records with Patient data eagerly loaded", records.size());

        List<EvvRecord> eligible = records.stream()
                .filter(r -> {
                    boolean isVA = "VA".equalsIgnoreCase(r.getStateCode());
                    boolean isApproved = "APPROVED".equalsIgnoreCase(r.getStatus());
                    if (!isVA || !isApproved) {
                        log.debug("[HHAExchange] Filtering out record {} - VA: {}, APPROVED: {}",
                                r.getId(), isVA, isApproved);
                    }
                    return isVA && isApproved;
                })
                .collect(java.util.stream.Collectors.toList());

        log.info("[HHAExchange] Found {} eligible records from {} requested",
                eligible.size(), recordIds.size());

        if (eligible.isEmpty()) {
            throw new IllegalArgumentException(
                    "No eligible VA/APPROVED records found in: " + recordIds);
        }

        try {
            Object request = hhaClient.buildRequest(eligible);
            log.info("[HHAExchange] Successfully built request for {} records", eligible.size());
            return request;
        } catch (Exception e) {
            log.error("[HHAExchange] Error building request for {} records: {}",
                    eligible.size(), e.getMessage(), e);
            throw e;
        }
    }

    /**
     * Returns the JSON payload that would be sent to HHAExchange for the given record IDs.
     * This is used for debugging and payload download functionality.
     *
     * @param recordIds IDs of the EVV records to include in payload
     * @return JSON string representation of the HHAExchange payload
     * @throws IllegalArgumentException if no eligible records are found
     */
    public String getPayloadJson(List<Long> recordIds) {
        // Fetch records with Patient eagerly loaded to avoid lazy-loading errors
        List<EvvRecord> records = evvRecordRepository.findAllByIdWithPatient(recordIds);
        List<EvvRecord> eligible = records.stream()
                .filter(r -> "VA".equalsIgnoreCase(r.getStateCode()))
                .filter(r -> "APPROVED".equalsIgnoreCase(r.getStatus()))
                .collect(Collectors.toList());
        if (eligible.isEmpty()) {
            throw new IllegalArgumentException(
                    "No eligible VA/APPROVED records found in the provided IDs: " + recordIds);
        }
        return hhaClient.getPayloadJson(eligible);
    }

    @Transactional
    public void submitBatch(List<Long> recordIds, Long actorId) throws Exception {
        // Fetch records with Patient eagerly loaded to avoid lazy-loading errors
        List<EvvRecord> records = evvRecordRepository.findAllByIdWithPatient(recordIds);
        List<EvvRecord> eligible = records.stream()
                .filter(r -> "VA".equalsIgnoreCase(r.getStateCode()))
                .filter(r -> "APPROVED".equalsIgnoreCase(r.getStatus()))
                .collect(Collectors.toList());

        if (eligible.isEmpty()) {
            throw new IllegalArgumentException(
                    "No eligible VA/APPROVED records found in the provided IDs: " + recordIds);
        }

        log.info("[HHAExchange] Batch submission of {} record(s) requested by actor {}",
                eligible.size(), actorId);
        try {
            hhaClient.submitBatch(eligible);
            eligible.forEach(rec -> audit.log(rec, actorId, "HHAEXCHANGE_SUBMITTED",
                    Map.of("batchSize", eligible.size(), "destination", "virginia-hhaexchange")));
            log.info("[HHAExchange] Batch of {} record(s) successfully submitted", eligible.size());
        } catch (Exception e) {
            eligible.forEach(rec -> audit.log(rec, actorId, "HHAEXCHANGE_SUBMISSION_FAILED",
                    Map.of("error", e.getMessage(), "destination", "virginia-hhaexchange")));
            throw e;
        }
    }

    // -------------------------------------------------------------------------
    // 2. Corrected-visit re-submission
    // -------------------------------------------------------------------------

    /**
     * Re-submit a corrected EVV record to HHAExchange.
     * <p>
     * The visit payload will have {@code editVisit.edited = true}, {@code editVisit.reasonCode}
     * and {@code editVisit.notes} populated from the correction data on the record.
     *
     * @param recordId ID of the corrected EVV record
     * @param actorId  ID of the user triggering the re-submission (for audit trail)
     * @throws IllegalArgumentException if the record does not exist or is not marked as corrected
     * @throws IllegalStateException    if the record belongs to a non-VA state
     * @throws Exception                if the HHAExchange API call fails
     */
    @Transactional
    public void resubmitCorrected(Long recordId, Long actorId) throws Exception {
        EvvRecord record = evvRecordRepository.findByIdWithPatient(recordId)
                .orElseThrow(() -> new IllegalArgumentException(
                        "EVV record not found: " + recordId));

        if (!Boolean.TRUE.equals(record.getIsCorrected())) {
            throw new IllegalArgumentException(
                    "Record " + recordId + " has no correction on file; nothing to re-submit");
        }
        if (!"VA".equalsIgnoreCase(record.getStateCode())) {
            throw new IllegalStateException(
                    "HHAExchange re-submission is only applicable to Virginia (VA) records; "
                            + "record " + recordId + " has state " + record.getStateCode());
        }

        log.info("[HHAExchange] Re-submitting corrected record {} for actor {}", recordId, actorId);
        try {
            hhaClient.submitBatch(List.of(record));
            audit.log(record, actorId, "HHAEXCHANGE_RESUBMITTED", Map.of(
                    "correctionReasonCode",
                    record.getCorrectionReasonCode() != null ? record.getCorrectionReasonCode() : "",
                    "destination", "virginia-hhaexchange"));
        } catch (Exception e) {
            audit.log(record, actorId, "HHAEXCHANGE_RESUBMISSION_FAILED",
                    Map.of("error", e.getMessage(), "destination", "virginia-hhaexchange"));
            throw e;
        }
    }

    // -------------------------------------------------------------------------
    // 3. Offline data submission
    // -------------------------------------------------------------------------

    /**
     * Submit all offline-captured, approved Virginia EVV records to HHAExchange.
     * <p>
     * This method is intended to be called after a caregiver device comes back online and the
     * local offline queue has been synced to the server. It finds all VA records that were captured
     * offline (isOffline=true OR syncStatus=SYNCED) and have been approved, then submits them as a
     * single batch.
     *
     * @param actorId ID of the user triggering the submission (for audit trail)
     * @return number of records submitted; {@code 0} if there is nothing to send
     * @throws Exception if the HHAExchange API call fails
     */
    @Transactional
    public int submitOfflineRecords(Long actorId) throws Exception {
        List<EvvRecord> offlineRecords = evvRecordRepository.findByIsOfflineTrue().stream()
                .filter(r -> "VA".equalsIgnoreCase(r.getStateCode()))
                .filter(r -> "APPROVED".equalsIgnoreCase(r.getStatus()))
                .collect(Collectors.toList());

        // Also include previously-offline records that have been synced but not yet forwarded
        List<EvvRecord> syncedRecords = evvRecordRepository.findBySyncStatus("SYNCED").stream()
                .filter(r -> "VA".equalsIgnoreCase(r.getStateCode()))
                .filter(r -> "APPROVED".equalsIgnoreCase(r.getStatus()))
                .filter(r -> Boolean.TRUE.equals(r.getIsOffline()))
                .collect(Collectors.toList());

        // Merge, de-duplicate by ID
        List<EvvRecord> combined = java.util.stream.Stream
                .concat(offlineRecords.stream(), syncedRecords.stream())
                .collect(Collectors.collectingAndThen(
                        Collectors.toMap(EvvRecord::getId, r -> r, (a, b) -> a),
                        m -> List.copyOf(m.values())));

        if (combined.isEmpty()) {
            log.info("[HHAExchange] No offline records pending submission");
            return 0;
        }

        log.info("[HHAExchange] Submitting {} offline-captured record(s) for actor {}",
                combined.size(), actorId);
        try {
            hhaClient.submitBatch(combined);
            combined.forEach(rec -> audit.log(rec, actorId, "HHAEXCHANGE_OFFLINE_SUBMITTED",
                    Map.of("isOffline", true, "destination", "virginia-hhaexchange")));
            return combined.size();
        } catch (Exception e) {
            combined.forEach(rec -> audit.log(rec, actorId, "HHAEXCHANGE_OFFLINE_SUBMISSION_FAILED",
                    Map.of("error", e.getMessage(), "destination", "virginia-hhaexchange")));
            throw e;
        }
    }
}
