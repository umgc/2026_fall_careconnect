package com.careconnect.service.evv;

import com.careconnect.model.evv.EvvRecord;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.Map;

@Service
@RequiredArgsConstructor
public class EvvOutboxService {
    private final NamedParameterJdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public void enqueue(EvvRecord record, String destination) {
        try {
            // Handle potentially null patient and location data
            String patientIdentifier;
            try {
                patientIdentifier = record.getPatient() != null && record.getPatient().getMaNumber() != null
                        ? record.getPatient().getMaNumber()
                        : (record.getPatient() != null ? "PATIENT-" + record.getPatient().getId() : "UNKNOWN");
            } catch (Exception e) {
                System.err.println("ERROR: Failed to get patient identifier: " + e.getMessage());
                patientIdentifier = "UNKNOWN";
            }

            // Build check-in location map
            Map<String, Object> checkinLocationMap = new java.util.HashMap<>();
            if (record.getCheckinLocationLat() != null) checkinLocationMap.put("lat", record.getCheckinLocationLat());
            if (record.getCheckinLocationLng() != null) checkinLocationMap.put("lng", record.getCheckinLocationLng());
            if (record.getCheckinLocationSource() != null)
                checkinLocationMap.put("source", record.getCheckinLocationSource());

            // Build check-out location map
            Map<String, Object> checkoutLocationMap = new java.util.HashMap<>();
            if (record.getCheckoutLocationLat() != null)
                checkoutLocationMap.put("lat", record.getCheckoutLocationLat());
            if (record.getCheckoutLocationLng() != null)
                checkoutLocationMap.put("lng", record.getCheckoutLocationLng());
            if (record.getCheckoutLocationSource() != null)
                checkoutLocationMap.put("source", record.getCheckoutLocationSource());

            // Build legacy location map for backward compatibility
            Map<String, Object> legacyLocationMap = new java.util.HashMap<>();
            if (record.getLocationLat() != null) legacyLocationMap.put("lat", record.getLocationLat());
            if (record.getLocationLng() != null) legacyLocationMap.put("lng", record.getLocationLng());

            Map<String, Object> payload = new java.util.HashMap<>();
            payload.put("id", record.getId());
            payload.put("patient", patientIdentifier);
            payload.put("serviceType", record.getServiceType() != null ? record.getServiceType() : "UNKNOWN");
            payload.put("timeIn", record.getTimeIn() != null ? record.getTimeIn().toString() : "");
            payload.put("timeOut", record.getTimeOut() != null ? record.getTimeOut().toString() : "");
            payload.put("checkinLocation", checkinLocationMap);
            payload.put("checkoutLocation", checkoutLocationMap);
            // Include legacy location for backward compatibility
            if (!legacyLocationMap.isEmpty()) {
                payload.put("loc", legacyLocationMap);
            }


            // Convert payload to JSON string
            String payloadJson = objectMapper.writeValueAsString(payload);


            var params = new MapSqlParameterSource()
                    .addValue("recordId", record.getId())
                    .addValue("destination", destination)
                    .addValue("payload", payloadJson);


            jdbc.update("INSERT INTO evv_outbox (evv_record_id, destination, payload)"
                    + " VALUES (:recordId, :destination, CAST(:payload AS jsonb))", params);

        } catch (Exception e) {
            System.err.println("ERROR in enqueue: " + e.getClass().getName() + ": " + e.getMessage());
            e.printStackTrace();
            throw new RuntimeException("Failed to enqueue EVV record for submission: " + e.getMessage(), e);
        }
    }

    public void markSent(Long id) {
        jdbc.update("UPDATE evv_outbox SET status='SENT' WHERE id=:id", new MapSqlParameterSource("id", id));
    }

    public void markFailed(Long id, String err) {
        jdbc.update("UPDATE evv_outbox SET status='FAILED', last_error=:e, attempts=attempts+1 WHERE id=:id",
                new MapSqlParameterSource().addValue("id", id).addValue("e", err));
    }

    /**
     * Fetch up to {@code limit} outbox rows that are ready to be processed.
     * Rows with {@code status = 'READY'} and fewer than 3 attempts are returned
     * ordered by insertion ID (oldest first).
     */
    public java.util.List<java.util.Map<String, Object>> fetchPending(int limit) {
        return jdbc.queryForList(
                "SELECT id, evv_record_id, destination, attempts " +
                        "FROM evv_outbox WHERE status = 'READY' AND attempts < 3 " +
                        "ORDER BY id ASC LIMIT :limit",
                new MapSqlParameterSource("limit", limit));
    }
}
