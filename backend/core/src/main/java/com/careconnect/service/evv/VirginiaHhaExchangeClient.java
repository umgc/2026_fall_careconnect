package com.careconnect.service.evv;

import com.careconnect.config.HhaExchangeProperties;
import com.careconnect.dto.evv.hhaexchange.HhaExchangeVisit;
import com.careconnect.dto.evv.hhaexchange.HhaExchangeVisitRequest;
import com.careconnect.model.Address;
import com.careconnect.model.Patient;
import com.careconnect.model.evv.EvvRecord;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.*;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * EVV integration client for the Virginia HHAExchange aggregator.
 * <p>
 * Submits visit data to: {@code POST https://implementation.hhaexchange.com/api/v2/visits}
 * <p>
 * This client replaces the earlier stub {@link VirginiaMcoClient} for Virginia state submissions
 * as required by the Virginia DMAS EVV mandate. It supports:
 * <ul>
 *   <li>Single-visit submission (via {@link #submit(EvvRecord)})</li>
 *   <li>Batch submission of multiple visits in one API call (via {@link #submitBatch(List)})</li>
 *   <li>Re-submission of corrected visits (editVisit.edited is set based on isCorrected)</li>
 *   <li>Offline-captured visits (handled identically — offline flag has no effect on the payload)</li>
 * </ul>
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class VirginiaHhaExchangeClient implements EvvIntegrationClient {

    /**
     * DateTime pattern expected by HHAExchange for visitStartDateTime / scheduleStartTime fields.
     */
    private static final DateTimeFormatter VISIT_DT_FMT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm");

    /**
     * DateTime pattern expected by HHAExchange for EVV clockIn / clockOut callDateTime fields.
     */
    private static final DateTimeFormatter CLOCK_DT_FMT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss");

    private final RestTemplate restTemplate;
    private final HhaExchangeProperties props;

    // -------------------------------------------------------------------------
    // EvvIntegrationClient contract
    // -------------------------------------------------------------------------

    /**
     * Maps a CareConnect service type label to the corresponding HCPCS/CPT procedure code
     * used by Virginia DMAS.
     */
    private static String mapServiceTypeToCode(String serviceType) {
        if (serviceType == null) return "T1019";
        return switch (serviceType.toLowerCase().trim()) {
            case "personal care" -> "T1019";
            case "companion care" -> "T1020";
            case "respite care" -> "S5150";
            case "homemaker services" -> "S5130";
            case "skilled nursing" -> "G0299";
            case "physical therapy" -> "97110";
            case "occupational therapy" -> "97530";
            case "speech therapy" -> "92507";
            case "home health aide" -> "G0156";
            default -> "T1019";
        };
    }

    private static <T> T coalesce(T first, T second) {
        return first != null ? first : second;
    }

    // -------------------------------------------------------------------------
    // Batch submission
    // -------------------------------------------------------------------------

    /**
     * Submit a batch of EVV records to the HHAExchange Virginia aggregator in a single API call.
     * <p>
     * All records are mapped to {@link HhaExchangeVisit} objects regardless of online/offline
     * origin; the caller is responsible for ensuring only eligible (APPROVED, VA state) records
     * are included.
     *
     * @param records non-empty list of {@link EvvRecord} instances to submit
     * @throws Exception if the HTTP call fails or the aggregator returns a non-2xx response
     */

    @Override
    public String destination() {
        return "virginia-hhaexchange";
    }

    /**
     * Submit a single EVV record to HHAExchange.
     * Delegates to {@link #submitBatch(List)} with a one-element list.
     */
    @Override
    public void submit(EvvRecord record) throws Exception {
        submitBatch(List.of(record));
    }

    /**
     * Builds the HHAExchange request payload without submitting it.
     * Useful for payload preview and download before submission.
     */
    public HhaExchangeVisitRequest buildRequest(List<EvvRecord> records) {
        log.info("[VA-HHAExchange] Building request for {} record(s)", records.size());
        List<HhaExchangeVisit> visits = records.stream()
                .map(record -> {
                    try {
                        HhaExchangeVisit visit = mapToHhaVisit(record);
                        log.debug("[VA-HHAExchange] Successfully mapped record {}", record.getId());
                        return visit;
                    } catch (Exception e) {
                        log.error("[VA-HHAExchange] Error mapping record {}: {}",
                                record.getId(), e.getMessage(), e);
                        throw new RuntimeException("Error mapping record " + record.getId() +
                                ": " + e.getMessage(), e);
                    }
                })
                .collect(Collectors.toList());
        log.info("[VA-HHAExchange] Successfully mapped {} record(s) to HhaExchangeVisit", visits.size());
        return HhaExchangeVisitRequest.builder().visits(visits).build();
    }

    // -------------------------------------------------------------------------
    // Mapping
    // -------------------------------------------------------------------------

    public void submitBatch(List<EvvRecord> records) throws Exception {
        HhaExchangeVisitRequest request = buildRequest(records);

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.set("X-API-KEY", props.getApi().getKey());

        String url = props.getApi().getBaseUrl() + "/api/v2/visits";
        log.info("[VA-HHAExchange] Submitting {} visit(s) to {}", request.getVisits().size(), url);

        ResponseEntity<String> response = restTemplate.postForEntity(
                url, new HttpEntity<>(request, headers), String.class);

        if (!response.getStatusCode().is2xxSuccessful()) {
            throw new RuntimeException(
                    "[VA-HHAExchange] Batch submission failed — HTTP " + response.getStatusCode()
                            + " | body: " + response.getBody());
        }
        log.info("[VA-HHAExchange] Batch of {} visit(s) accepted, status={}",
                request.getVisits().size(), response.getStatusCode());
    }

    /**
     * Returns the JSON payload that would be sent to HHAExchange for the given visits.
     * This is used for debugging and payload download functionality.
     */
    public String getPayloadJson(List<EvvRecord> records) {
        try {
            HhaExchangeVisitRequest request = buildRequest(records);
            return new com.fasterxml.jackson.databind.ObjectMapper()
                    .writerWithDefaultPrettyPrinter()
                    .writeValueAsString(request);
        } catch (Exception e) {
            log.error("[VA-HHAExchange] Failed to serialize payload to JSON", e);
            return "{\"error\": \"Failed to serialize payload: " + e.getMessage() + "\"}";
        }
    }

    private HhaExchangeVisit mapToHhaVisit(EvvRecord record) {
        Patient patient = record.getPatient();

        // MedicaidID falls back to a synthetic value when the patient MA number is absent
        String memberIdentifier = (patient != null && patient.getMaNumber() != null)
                ? patient.getMaNumber()
                : "UNKNOWN-" + record.getId();

        HhaExchangeVisit.ServiceAddress serviceAddress = buildServiceAddress(patient);

        // Prefer dedicated check-in/out coordinate fields; fall back to legacy single-location
        Double inLat = coalesce(record.getCheckinLocationLat(), record.getLocationLat());
        Double inLng = coalesce(record.getCheckinLocationLng(), record.getLocationLng());
        Double outLat = coalesce(record.getCheckoutLocationLat(), record.getLocationLat());
        Double outLng = coalesce(record.getCheckoutLocationLng(), record.getLocationLng());

        String phone = (patient != null && patient.getPhone() != null) ? patient.getPhone() : "";

        HhaExchangeVisit.ClockEvent clockIn = HhaExchangeVisit.ClockEvent.builder()
                .callDateTime(record.getTimeIn().format(CLOCK_DT_FMT))
                .callType("Mobile")
                .callLatitude(inLat)
                .callLongitude(inLng)
                .originatingPhoneNumber(phone)
                .locationType("Home")
                .serviceAddress(serviceAddress)
                .build();

        HhaExchangeVisit.ClockEvent clockOut = HhaExchangeVisit.ClockEvent.builder()
                .callDateTime(record.getTimeOut().format(CLOCK_DT_FMT))
                .callType("Mobile")
                .callLatitude(outLat)
                .callLongitude(outLng)
                .originatingPhoneNumber(phone)
                .locationType("Home")
                .serviceAddress(serviceAddress)
                .build();

        boolean isCorrected = Boolean.TRUE.equals(record.getIsCorrected());
        HhaExchangeVisit.EditVisit editVisit = HhaExchangeVisit.EditVisit.builder()
                .edited(isCorrected)
                .reasonCode(isCorrected && record.getCorrectionReasonCode() != null
                        ? record.getCorrectionReasonCode() : "")
                .actionCode(isCorrected ? "100" : "")
                .notes(isCorrected && record.getCorrectionExplanation() != null
                        ? record.getCorrectionExplanation() : "")
                .build();

        return HhaExchangeVisit.builder()
                .providerTaxId(props.getProvider().getTaxId())
                .office(HhaExchangeVisit.Office.builder()
                        .qualifier("NPI")
                        .identifier(props.getProvider().getNpi())
                        .build())
                .member(HhaExchangeVisit.Member.builder()
                        .qualifier("MedicaidID")
                        .identifier(memberIdentifier)
                        .build())
                .caregiver(HhaExchangeVisit.Caregiver.builder()
                        .qualifier("ExternalID")
                        .identifier(String.valueOf(record.getCaregiverId()))
                        .build())
                .residingCaregiver("No")
                .payerId(props.getPayer().getId())
                .externalVisitId(String.valueOf(record.getId()))
                .evvmsid(UUID.randomUUID().toString())
                .procedureCode(mapServiceTypeToCode(record.getServiceType()))
                .procedureModifierCode(List.of()) // Empty list as per HHAExchange spec
                .timezone("US/Eastern")
                .scheduleStartTime(record.getTimeIn().format(VISIT_DT_FMT))
                .scheduleEndTime(record.getTimeOut().format(VISIT_DT_FMT))
                .visitStartDateTime(record.getTimeIn().format(VISIT_DT_FMT))
                .visitEndDateTime(record.getTimeOut().format(VISIT_DT_FMT))
                .timesheetRequired(false)
                .timesheetApproved(true)
                .evv(HhaExchangeVisit.EvvData.builder()
                        .clockIn(clockIn)
                        .clockOut(clockOut)
                        .build())
                .missedVisit(HhaExchangeVisit.MissedVisit.builder()
                        .missed(false)
                        .reasonCode("")
                        .actionCode("")
                        .notes("")
                        .build())
                .editVisit(editVisit)
                .billing(buildBilling(record))
                .billSecondaryPayer(List.of()) // Empty list as per HHAExchange spec
                .shiftSignOff(HhaExchangeVisit.ShiftSignOff.builder()
                        .employerInternalNumber("")
                        .employerName(props.getProvider().getName())
                        .build())
                .build();
    }

    private HhaExchangeVisit.ServiceAddress buildServiceAddress(Patient patient) {
        if (patient != null && patient.getAddress() != null) {
            Address addr = patient.getAddress();
            return HhaExchangeVisit.ServiceAddress.builder()
                    .addressLine1(addr.getLine1() != null ? addr.getLine1() : "")
                    .addressLine2(addr.getLine2() != null ? addr.getLine2() : "")
                    .city(addr.getCity() != null ? addr.getCity() : "")
                    .state(addr.getState() != null ? addr.getState() : "VA")
                    .zipcode(addr.getZip() != null ? addr.getZip() : "")
                    .build();
        }
        return HhaExchangeVisit.ServiceAddress.builder()
                .addressLine1("Address on file")
                .city("Unknown")
                .state("VA")
                .zipcode("00000")
                .build();
    }

    private HhaExchangeVisit.Billing buildBilling(EvvRecord record) {
        try {
            // Calculate visit duration in minutes with null safety
            long minutes = 0;
            if (record.getTimeIn() != null && record.getTimeOut() != null) {
                minutes = java.time.Duration.between(record.getTimeIn(), record.getTimeOut()).toMinutes();
            }

            // Ensure we have at least 1 minute for billing purposes
            if (minutes <= 0) {
                minutes = 1;
            }

            // For now, use a default contract rate of $20/hour (0.3333/minute)
            // This should be configurable based on service type and payer agreements
            double contractRate = 20.0 / 60.0; // $20 per hour
            double totalBilledAmount = minutes * contractRate;

            return HhaExchangeVisit.Billing.builder()
                    .externalInvoiceNumber("INV-" + record.getId())
                    .totalBilledAmount(totalBilledAmount)
                    .totalUnitsBilled((int) minutes) // Units in minutes
                    .contractRate(contractRate)
                    .diagnosisCodes(List.of()) // Empty list - would need patient diagnosis data
                    .build();
        } catch (Exception e) {
            log.warn("[VA-HHAExchange] Error building billing section for record {}: {}",
                    record.getId(), e.getMessage());
            // Return empty billing if calculation fails
            return HhaExchangeVisit.Billing.builder()
                    .externalInvoiceNumber("INV-" + record.getId())
                    .totalBilledAmount(0.0)
                    .totalUnitsBilled(0)
                    .contractRate(0.0)
                    .diagnosisCodes(List.of())
                    .build();
        }
    }
}
