package com.careconnect.service.evv;

import com.careconnect.model.evv.EvvRecord;
import com.careconnect.repository.evv.EvvRecordRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
@Slf4j
public class EvvSubmissionService {
    private final List<EvvIntegrationClient> clients;
    private final EvvOutboxService outbox;
    private final EvvRecordRepository evvRecordRepository;
    private final AuditLogger audit;

    public String destinationFor(String stateCode) {
        return switch (stateCode.toUpperCase()) {
            case "MD" -> "maryland-info-only";
            case "DC" -> "dc-sandata";
            case "VA" -> "virginia-mco";
            default -> throw new IllegalArgumentException("Unsupported state code: " + stateCode);
        };
    }

    @Transactional
    public void queueForSubmission(EvvRecord rec, Long actorId) {
        outbox.enqueue(rec, destinationFor(rec.getStateCode()));

        // Build audit details with location information
        var auditDetails = buildLocationDetails(rec);
        auditDetails.put("destination", destinationFor(rec.getStateCode()));
        audit.log(rec, actorId, "SUBMISSION_QUEUED", auditDetails);
    }

    /**
     * Submit an EVV record to the appropriate state system.
     * This method should be called when the outbox processor actually sends the record.
     */
    @Transactional
    public void submitRecord(EvvRecord rec, Long actorId) {
        String destination = destinationFor(rec.getStateCode());

        try {
            // Find and call the appropriate integration client
            for (EvvIntegrationClient client : clients) {
                try {
                    client.submit(rec);

                    // Log successful submission with location data
                    var auditDetails = buildLocationDetails(rec);
                    auditDetails.put("destination", destination);
                    auditDetails.put("success", true);
                    audit.log(rec, actorId, "SUBMITTED", auditDetails);

                    log.info("Successfully submitted EVV record {} to {}", rec.getId(), destination);
                    return;
                } catch (Exception e) {
                    log.debug("Integration client did not match or failed: {}", e.getMessage());
                }
            }

            // If no client succeeded, log as submission failed
            var auditDetails = buildLocationDetails(rec);
            auditDetails.put("destination", destination);
            auditDetails.put("success", false);
            auditDetails.put("error", "No matching integration client found");
            audit.log(rec, actorId, "SUBMISSION_FAILED", auditDetails);
            throw new IllegalStateException("No integration client found for state: " + rec.getStateCode());

        } catch (Exception e) {
            log.error("Error submitting EVV record {}: {}", rec.getId(), e.getMessage(), e);

            // Log submission failure with location data
            var auditDetails = buildLocationDetails(rec);
            auditDetails.put("destination", destination);
            auditDetails.put("success", false);
            auditDetails.put("error", e.getMessage());
            audit.log(rec, actorId, "SUBMISSION_FAILED", auditDetails);

            throw new RuntimeException("Failed to submit EVV record: " + e.getMessage(), e);
        }
    }

    /**
     * Helper method to extract location details from an EVV record for audit logging
     */
    private Map<String, Object> buildLocationDetails(EvvRecord record) {
        var details = new java.util.HashMap<String, Object>();

        // Add legacy location if available
        if (record.getLocationLat() != null || record.getLocationLng() != null) {
            details.put("locationLat", record.getLocationLat());
            details.put("locationLng", record.getLocationLng());
            details.put("locationSource", record.getLocationSource());
        }

        // Add check-in location if available
        if (record.getCheckinLocationLat() != null || record.getCheckinLocationLng() != null) {
            details.put("checkinLocationLat", record.getCheckinLocationLat());
            details.put("checkinLocationLng", record.getCheckinLocationLng());
            details.put("checkinLocationSource", record.getCheckinLocationSource());
        }

        // Add check-out location if available
        if (record.getCheckoutLocationLat() != null || record.getCheckoutLocationLng() != null) {
            details.put("checkoutLocationLat", record.getCheckoutLocationLat());
            details.put("checkoutLocationLng", record.getCheckoutLocationLng());
            details.put("checkoutLocationSource", record.getCheckoutLocationSource());
        }

        return details;
    }
}
