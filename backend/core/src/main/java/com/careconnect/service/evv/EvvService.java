package com.careconnect.service.evv;

import com.careconnect.dto.evv.*;
import com.careconnect.model.evv.*;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.evv.EvvCorrectionRepository;
import com.careconnect.repository.evv.EvvOfflineQueueRepository;
import com.careconnect.repository.evv.EvvRecordRepository;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.service.VisitSummaryService;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class EvvService {
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(EvvService.class);

    private final EvvRecordRepository recordRepository;
    private final EvvCorrectionRepository correctionRepository;
    private final EvvOfflineQueueRepository offlineQueueRepository;
    private final PatientRepository patientRepository;
    private final UserRepository userRepository;
    private final EvvLocationService locationService;
    private final AuditLogger audit;
    private final ScheduledVisitRepository scheduledVisitRepository;
    private final VisitSummaryService visitSummaryService;

    /**
     * Build audit event details map with location information from EVV record
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

    /**
     * Validates EVV location fields per federal EVV quality guardrails (Issue #62).
     * Enforces:
     * - GPS coordinates present when locationType is GPS
     * - GPS accuracy within acceptable threshold (<500 meters)
     * - noGpsReason required when locationType is not GPS
     * - Manual address required when locationType is MANUAL
     */
    private void validateLocationGuardrails(
            String locationSource,
            Double lat,
            Double lng,
            Double accuracyM,
            String noGpsReason,
            String manualAddress,
            String role) {

        if (locationSource == null) return;

        switch (locationSource.toUpperCase()) {
            case "GPS" -> {
                if (lat == null || lng == null) {
                    throw new IllegalArgumentException(
                            role + " location type is GPS but coordinates are missing. " + "latitude and longitude are required when using GPS."
                    );
                }

                if (accuracyM != null && accuracyM > 500.0) {
                    throw new IllegalArgumentException(
                            role + " GPS accuracy is " + accuracyM + "m which exceeds the 500m threshold required for EVV compliance. Please retry GPS or use patient address."
                    );
                }
            }

            case "PATIENT_ADDRESS", "MANUAL" -> {
                if (noGpsReason == null || noGpsReason.isBlank()) {
                    throw new IllegalArgumentException(
                            role + " location type is " + locationSource + " but no GPS reason was provided. Federal EVV regulations require a reason when GPS is not used."
                    );
                }

                if ("MANUAL".equalsIgnoreCase(locationSource) && (manualAddress == null || manualAddress.isBlank())) {
                    throw new IllegalArgumentException(
                            role + " location type is MANUAL but no address was provided. A manual address is required when using manual location entry."
                    );
                }
            }

            default -> throw new IllegalArgumentException(
                    "Unknown " + role + " location source: " + locationSource + ". Valid values are: GPS, PATIENT_ADDRESS, MANUAL."
            );
        }
    }


    @Transactional
    public EvvRecord createRecord(EvvRecordRequestDto req, Long actorId) {
        var patient = patientRepository.findById(req.getPatientId())
                .orElseThrow(() -> new IllegalArgumentException("Patient not found"));

        // Build individual name from patient data
        String individualName = patient.getFirstName() + " " + patient.getLastName();

        // Snapshot caregiver name for immutable audit trail
        String caregiverName = userRepository.findById(req.getCaregiverId())
                .map(u -> u.getName() != null ? u.getName() : "Caregiver #" + req.getCaregiverId())
                .orElse("Caregiver #" + req.getCaregiverId());

        // EVV Quality Guardrail (Issue #62) - validate location fields before persisting
        validateLocationGuardrails(
                req.getCheckinLocationSource(),
                req.getCheckinLocationLat(),
                req.getCheckinLocationLng(),
                req.getCheckinAccuracyM(),
                req.getCheckinNoGpsReason(),
                req.getCheckinManualAddress(),
                "Check-in"
        );

        validateLocationGuardrails(
                req.getCheckoutLocationSource(),
                req.getCheckoutLocationLat(),
                req.getCheckoutLocationLng(),
                req.getCheckoutAccuracyM(),
                req.getCheckoutNoGpsReason(),
                req.getCheckoutManualAddress(),
                "Check-out"
        );

        var rec = EvvRecord.builder()
                .patient(patient)
                .serviceType(req.getServiceType())
                .individualName(individualName)
                .caregiverId(req.getCaregiverId())
                .caregiverName(caregiverName)
                .dateOfService(req.getDateOfService())
                .timeIn(req.getTimeIn())
                .timeOut(req.getTimeOut())
                // Legacy location fields for backward compatibility
                .locationLat(req.getLocationLat())
                .locationLng(req.getLocationLng())
                .locationSource(req.getLocationSource())
                .status("UNDER_REVIEW")
                .stateCode(req.getStateCode())
                .deviceInfo(req.getDeviceInfo())
                .isOffline(false)
                .eorApprovalRequired(false)
                .isCorrected(false)
                .scheduledVisitId(req.getScheduledVisitId())
                .createdAt(OffsetDateTime.now())
                .updatedAt(OffsetDateTime.now())
                .build();
        var saved = recordRepository.save(rec); // REQ 2

        // Save check-in and check-out locations using the new location service
        saveLocationsForRecord(saved, req);

        // Populate location fields and log with location data
        populateLocationFields(saved);
        var auditDetails = new java.util.HashMap<>(buildLocationDetails(saved));
        auditDetails.put("deviceInfo", req.getDeviceInfo());
        audit.log(saved, actorId, "CREATED", auditDetails); // REQ 4

        // If this EVV record is linked to a scheduled visit, mark the scheduled visit as completed
        if (req.getScheduledVisitId() != null) {
            try {
                var optionalVisit = scheduledVisitRepository.findById(req.getScheduledVisitId());
                if (optionalVisit.isPresent()) {
                    ScheduledVisit scheduledVisit = optionalVisit.get();
                    scheduledVisit.markCompleted();
                    scheduledVisitRepository.save(scheduledVisit);
                    try {
                        visitSummaryService.generateAndStoreSummary(scheduledVisit.getId(), null);
                    } catch (Exception summaryEx) {
                        log.warn(
                                "Visit summary generation failed for visit {}: {}",
                                scheduledVisit.getId(), summaryEx.getMessage(), summaryEx);
                    }
                } else {
                    // scheduled visit not found — ignore silently
                }
            } catch (Exception e) {
                // Don't fail the EVV record creation if we can't update the scheduled visit
            }
        }

        return saved;
    }

    /**
     * Convert EvvCorrectionRequestDto to EvvRecordRequestDto for location saving
     */
    private EvvRecordRequestDto convertCorrectionToRecordRequest(EvvCorrectionRequestDto correction, EvvRecord original) {
        return EvvRecordRequestDto.builder()
                .locationLat(correction.getLocationLat())
                .locationLng(correction.getLocationLng())
                .locationSource(correction.getLocationSource())
                .checkinLocationLat(correction.getCheckinLocationLat())
                .checkinLocationLng(correction.getCheckinLocationLng())
                .checkinLocationSource(correction.getCheckinLocationSource())
                .checkoutLocationLat(correction.getCheckoutLocationLat())
                .checkoutLocationLng(correction.getCheckoutLocationLng())
                .checkoutLocationSource(correction.getCheckoutLocationSource())
                .build();
    }

    /**
     * Helper method to save check-in and check-out locations for an EVV record.
     * Passes noGpsReason, manualAddress, and accuracyM per federal EVV requirements.
     */
    private void saveLocationsForRecord(EvvRecord record, EvvRecordRequestDto req) {
        // Determine check-in location source
        String checkinSource = req.getCheckinLocationSource();

        // Backward compatibility: If using legacy locationSource field, treat it as check-in
        if (checkinSource == null && req.getLocationSource() != null) {
            checkinSource = req.getLocationSource().equalsIgnoreCase("gps") ? "GPS" : "PATIENT_ADDRESS";
        }

        // Save check-in location if data is provided
        if (checkinSource != null) {
            try {
                NoGpsReason checkinReason = parseNoGpsReason(req.getCheckinNoGpsReason());
                EvvLocationRequest checkinLocationReq = EvvLocationRequest.builder()
                        .evvRecordId(record.getId())
                        .role(EvvLocationRole.CHECK_IN)
                        .type(EvvLocationType.valueOf(checkinSource))
                        .noGpsReason(checkinReason)
                        .manualAddress(req.getCheckinManualAddress())
                        .build();

                if ("GPS".equals(checkinSource)) {
                    Double lat = req.getCheckinLocationLat() != null ? req.getCheckinLocationLat() : req.getLocationLat();
                    Double lng = req.getCheckinLocationLng() != null ? req.getCheckinLocationLng() : req.getLocationLng();

                    if (lat != null && lng != null) {
                        EvvLocationRequest.CoordinatesDto coords = EvvLocationRequest.CoordinatesDto.builder()
                                .lat(BigDecimal.valueOf(lat))
                                .lng(BigDecimal.valueOf(lng))
                                .build();
                        if (req.getCheckinAccuracyM() != null) {
                            coords.setAccuracyM(BigDecimal.valueOf(req.getCheckinAccuracyM()));
                        }
                        checkinLocationReq.setCoords(coords);
                        locationService.saveLocation(checkinLocationReq);
                    } else {
                        log.warn("[EVV] GPS check-in location requested but coordinates not provided for record {}", record.getId());
                    }
                } else {
                    // PATIENT_ADDRESS or MANUAL - no GPS coords needed
                    locationService.saveLocation(checkinLocationReq);
                }
            } catch (Exception e) {
                log.error("[EVV] Failed to save check-in location for record {}: {}", record.getId(), e.getMessage());
            }
        }

        // Save check-out location if data is provided
        if (req.getCheckoutLocationSource() != null) {
            try {
                NoGpsReason checkoutReason = parseNoGpsReason(req.getCheckoutNoGpsReason());
                EvvLocationRequest checkoutLocationReq = EvvLocationRequest.builder()
                        .evvRecordId(record.getId())
                        .role(EvvLocationRole.CHECK_OUT)
                        .type(EvvLocationType.valueOf(req.getCheckoutLocationSource()))
                        .noGpsReason(checkoutReason)
                        .manualAddress(req.getCheckoutManualAddress())
                        .build();

                if ("GPS".equals(req.getCheckoutLocationSource())) {
                    if (req.getCheckoutLocationLat() != null && req.getCheckoutLocationLng() != null) {
                        EvvLocationRequest.CoordinatesDto coords = EvvLocationRequest.CoordinatesDto.builder()
                                .lat(BigDecimal.valueOf(req.getCheckoutLocationLat()))
                                .lng(BigDecimal.valueOf(req.getCheckoutLocationLng()))
                                .build();
                        if (req.getCheckoutAccuracyM() != null) {
                            coords.setAccuracyM(BigDecimal.valueOf(req.getCheckoutAccuracyM()));
                        }
                        checkoutLocationReq.setCoords(coords);
                        locationService.saveLocation(checkoutLocationReq);
                    } else {
                        log.warn("[EVV] GPS check-out location requested but coordinates not provided for record {}", record.getId());
                    }
                } else {
                    // PATIENT_ADDRESS or MANUAL
                    locationService.saveLocation(checkoutLocationReq);
                }
            } catch (Exception e) {
                log.error("[EVV] Failed to save check-out location for record {}: {}", record.getId(), e.getMessage());
            }
        }
    }

    private NoGpsReason parseNoGpsReason(String value) {
        if (value == null || value.isBlank()) return null;
        try {
            return NoGpsReason.valueOf(value.toUpperCase());
        } catch (IllegalArgumentException e) {
            return NoGpsReason.OTHER;
        }
    }

    @Transactional
    public EvvRecord review(Long id, boolean approve, Long actorId, String comment) {
        var rec = recordRepository.findByIdWithPatient(id).orElseThrow();
        if (approve) {
            rec.markApproved();
        } else {
            rec.markRejected();
        }
        recordRepository.save(rec);

        // Populate location data before audit logging
        populateLocationFields(rec);
        var auditDetails = new java.util.HashMap<>(buildLocationDetails(rec));
        if (comment != null) {
            auditDetails.put("comment", comment);
        }
        audit.log(rec, actorId, approve ? "APPROVED" : "REJECTED", auditDetails);

        return rec;
    }

    @Transactional
    public EvvRecord createOfflineRecord(EvvRecordRequestDto req, Long actorId, String deviceId) {
        var patient = patientRepository.findById(req.getPatientId())
                .orElseThrow(() -> new IllegalArgumentException("Patient not found"));

        // Build individual name from patient data
        String individualName = patient.getFirstName() + " " + patient.getLastName();

        // EVV Quality Guardrail (Issue #62) - validate location fields before persisting
        validateLocationGuardrails(
                req.getCheckinLocationSource(),
                req.getCheckinLocationLat(),
                req.getCheckinLocationLng(),
                req.getCheckinAccuracyM(),
                req.getCheckinNoGpsReason(),
                req.getCheckinManualAddress(),
                "Check-in"
        );

        validateLocationGuardrails(
                req.getCheckoutLocationSource(),
                req.getCheckoutLocationLat(),
                req.getCheckoutLocationLng(),
                req.getCheckoutAccuracyM(),
                req.getCheckoutNoGpsReason(),
                req.getCheckoutManualAddress(),
                "Check-out"
        );

        var rec = EvvRecord.builder()
                .patient(patient)
                .serviceType(req.getServiceType())
                .individualName(individualName)
                .caregiverId(req.getCaregiverId())
                .dateOfService(req.getDateOfService())
                .timeIn(req.getTimeIn())
                .timeOut(req.getTimeOut())
                .locationLat(req.getLocationLat())
                .locationLng(req.getLocationLng())
                .locationSource(req.getLocationSource())
                .status("UNDER_REVIEW")
                .stateCode(req.getStateCode())
                .deviceInfo(req.getDeviceInfo())
                .isOffline(true)
                .syncStatus("PENDING")
                .createdAt(OffsetDateTime.now())
                .updatedAt(OffsetDateTime.now())
                .build();

        var saved = recordRepository.save(rec);

        // Add to offline queue
        var queueItem = EvvOfflineQueue.builder()
                .recordId(saved.getId())
                .operationType("CREATE")
                .caregiverId(actorId)
                .deviceId(deviceId)
                .priority(1)
                .recordData(Map.ofEntries(
                        Map.entry("serviceType", req.getServiceType()),
                        Map.entry("individualName", individualName),
                        Map.entry("patientId", req.getPatientId()),
                        Map.entry("dateOfService", req.getDateOfService()),
                        Map.entry("timeIn", req.getTimeIn()),
                        Map.entry("timeOut", req.getTimeOut()),
                        Map.entry("locationLat", req.getLocationLat()),
                        Map.entry("locationLng", req.getLocationLng()),
                        Map.entry("locationSource", req.getLocationSource()),
                        Map.entry("stateCode", req.getStateCode()),
                        Map.entry("deviceInfo", req.getDeviceInfo())
                ))
                .build();

        offlineQueueRepository.save(queueItem);

        // Populate location fields and log with location data
        populateLocationFields(saved);
        var auditDetails = new java.util.HashMap<>(buildLocationDetails(saved));
        auditDetails.put("deviceId", deviceId);
        audit.log(saved, actorId, "OFFLINE_CREATED", auditDetails);

        return saved;
    }

    @Transactional
    public EvvRecord correctRecord(EvvCorrectionRequestDto req, Long actorId) {
        var originalRecord = recordRepository.findByIdWithPatient(req.getOriginalRecordId())
                .orElseThrow(() -> new IllegalArgumentException("Original record not found"));

        // Create corrected record - starts as UNDER_REVIEW since it needs approval
        var correctedRecord = EvvRecord.builder()
                .patient(originalRecord.getPatient())
                .serviceType(req.getServiceType() != null ? req.getServiceType() : originalRecord.getServiceType())
                .individualName(req.getIndividualName() != null ? req.getIndividualName() : originalRecord.getIndividualName())
                .caregiverId(originalRecord.getCaregiverId())
                .dateOfService(req.getDateOfService() != null ? req.getDateOfService() : originalRecord.getDateOfService())
                .timeIn(req.getTimeIn() != null ? req.getTimeIn() : originalRecord.getTimeIn())
                .timeOut(req.getTimeOut() != null ? req.getTimeOut() : originalRecord.getTimeOut())
                .locationLat(req.getLocationLat() != null ? req.getLocationLat() : originalRecord.getLocationLat())
                .locationLng(req.getLocationLng() != null ? req.getLocationLng() : originalRecord.getLocationLng())
                .locationSource(req.getLocationSource() != null ? req.getLocationSource() : originalRecord.getLocationSource())
                .status("UNDER_REVIEW") // Corrected records need approval
                .stateCode(req.getStateCode() != null ? req.getStateCode() : originalRecord.getStateCode())
                .deviceInfo(req.getDeviceInfo() != null ? req.getDeviceInfo() : originalRecord.getDeviceInfo())
                .isCorrected(true)
                .originalRecordId(originalRecord.getId())
                .correctionReasonCode(req.getReasonCode())
                .correctionExplanation(req.getExplanation())
                .correctedBy(actorId)
                .correctedAt(OffsetDateTime.now())
                .createdAt(OffsetDateTime.now())
                .updatedAt(OffsetDateTime.now())
                .build();

        var savedCorrected = recordRepository.save(correctedRecord);

        // Save location data for corrected record if provided
        saveLocationsForRecord(savedCorrected, convertCorrectionToRecordRequest(req, originalRecord));

        // Mark original record as rejected since it was found to be incorrect
        originalRecord.markRejected();
        recordRepository.save(originalRecord);

        // Create correction record
        var correction = EvvCorrection.builder()
                .originalRecord(originalRecord)
                .correctedRecord(savedCorrected)
                .reasonCode(req.getReasonCode())
                .explanation(req.getExplanation())
                .correctedBy(actorId)
                .correctedAt(OffsetDateTime.now())
                .approvalRequired(true) // Corrections require approval
                .originalValues(Map.of(
                        "serviceType", originalRecord.getServiceType(),
                        "individualName", originalRecord.getIndividualName(),
                        "dateOfService", originalRecord.getDateOfService(),
                        "timeIn", originalRecord.getTimeIn(),
                        "timeOut", originalRecord.getTimeOut(),
                        "locationLat", originalRecord.getLocationLat(),
                        "locationLng", originalRecord.getLocationLng(),
                        "locationSource", originalRecord.getLocationSource()
                ))
                .correctedValues(Map.of(
                        "serviceType", savedCorrected.getServiceType(),
                        "individualName", savedCorrected.getIndividualName(),
                        "dateOfService", savedCorrected.getDateOfService(),
                        "timeIn", savedCorrected.getTimeIn(),
                        "timeOut", savedCorrected.getTimeOut(),
                        "locationLat", savedCorrected.getLocationLat(),
                        "locationLng", savedCorrected.getLocationLng(),
                        "locationSource", savedCorrected.getLocationSource()
                ))
                .build();

        correctionRepository.save(correction);

        // Populate location fields and log with comprehensive audit details
        populateLocationFields(savedCorrected);
        var auditDetails = new java.util.HashMap<>(buildLocationDetails(savedCorrected));
        auditDetails.put("originalRecordId", originalRecord.getId());
        auditDetails.put("reasonCode", req.getReasonCode());
        auditDetails.put("explanation", req.getExplanation());
        audit.log(savedCorrected, actorId, "CORRECTED", auditDetails);

        return savedCorrected;
    }

    @Transactional
    public EvvRecord approveEor(EorApprovalRequestDto req, Long approverId) {
        var record = recordRepository.findByIdWithPatient(req.getRecordId())
                .orElseThrow(() -> new IllegalArgumentException("Record not found"));

        record.approveEor(approverId, req.getComment());
        recordRepository.save(record);

        // Populate location data before audit logging
        populateLocationFields(record);
        var auditDetails = new java.util.HashMap<>(buildLocationDetails(record));
        if (req.getComment() != null) {
            auditDetails.put("comment", req.getComment());
        }
        audit.log(record, approverId, "EOR_APPROVED", auditDetails);

        return record;
    }

    public Page<EvvRecord> searchRecords(EvvSearchRequestDto searchRequest) {
        Sort sort = Sort.by(Sort.Direction.fromString(searchRequest.getSortDirection()), searchRequest.getSortBy());
        Pageable pageable = PageRequest.of(searchRequest.getPage(), searchRequest.getSize(), sort);

        Page<EvvRecord> records = recordRepository.searchRecords(
                searchRequest.getPatientName(),
                searchRequest.getServiceType(),
                searchRequest.getPatientId(),
                searchRequest.getCaregiverId(),
                searchRequest.getStartDate(),
                searchRequest.getEndDate(),
                searchRequest.getStateCode(),
                searchRequest.getStatus(),
                pageable
        );

        // Populate location data from evv_record_location table
        records.forEach(this::populateLocationFields);

        return records;
    }

    /**
     * Populate check-in and check-out location fields from evv_record_location table
     */
    private void populateLocationFields(EvvRecord record) {
        try {
            List<EvvLocationResponse> locations = locationService.getLocationsForRecord(record.getId());

            for (EvvLocationResponse loc : locations) {
                if (loc.getRole() == EvvLocationRole.CHECK_IN) {
                    record.setCheckinLocationLat(loc.getLatitude() != null ? loc.getLatitude().doubleValue() : null);
                    record.setCheckinLocationLng(loc.getLongitude() != null ? loc.getLongitude().doubleValue() : null);
                    record.setCheckinLocationSource(loc.getType().name());
                } else if (loc.getRole() == EvvLocationRole.CHECK_OUT) {
                    record.setCheckoutLocationLat(loc.getLatitude() != null ? loc.getLatitude().doubleValue() : null);
                    record.setCheckoutLocationLng(loc.getLongitude() != null ? loc.getLongitude().doubleValue() : null);
                    record.setCheckoutLocationSource(loc.getType().name());
                }
            }
        } catch (Exception e) {
            // If no locations found, fields will remain null (OK for old records)
        }
    }

    public List<EvvRecord> getPendingEorApprovals() {
        return recordRepository.findPendingEorApprovals();
    }

    public List<EvvCorrection> getPendingCorrections() {
        return correctionRepository.findPendingApprovals();
    }

    @Transactional
    public EvvCorrection approveCorrection(Long correctionId, Long approverId, String comment) {
        var correction = correctionRepository.findById(correctionId)
                .orElseThrow(() -> new IllegalArgumentException("Correction not found"));

        correction.approve(approverId, comment);
        correctionRepository.save(correction);

        // Approve the corrected EVV record
        var correctedRecord = correction.getCorrectedRecord();
        correctedRecord.markApproved();
        recordRepository.save(correctedRecord);

        // Populate location data before audit logging
        populateLocationFields(correctedRecord);
        var auditDetails = new java.util.HashMap<>(buildLocationDetails(correctedRecord));
        auditDetails.put("correctionId", correctionId);
        if (comment != null) {
            auditDetails.put("comment", comment);
        }
        audit.log(correctedRecord, approverId, "CORRECTION_APPROVED", auditDetails);

        return correction;
    }

    @Transactional
    public EvvCorrection rejectCorrection(Long correctionId, Long reviewerId, String comment) {
        var correction = correctionRepository.findById(correctionId)
                .orElseThrow(() -> new IllegalArgumentException("Correction not found"));

        correction.reject(reviewerId, comment);
        correctionRepository.save(correction);

        // Reject the corrected EVV record
        var correctedRecord = correction.getCorrectedRecord();
        correctedRecord.markRejected();
        recordRepository.save(correctedRecord);

        // Populate location data before audit logging
        populateLocationFields(correctedRecord);
        var auditDetails = new java.util.HashMap<>(buildLocationDetails(correctedRecord));
        auditDetails.put("correctionId", correctionId);
        if (comment != null) {
            auditDetails.put("comment", comment);
        }
        audit.log(correctedRecord, reviewerId, "CORRECTION_REJECTED", auditDetails);

        return correction;
    }

    public List<EvvOfflineQueue> getOfflineQueue(Long caregiverId) {
        return offlineQueueRepository.findPendingItemsByCaregiver(caregiverId);
    }

}
