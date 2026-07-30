package com.careconnect.service;

import com.careconnect.config.VitalAlertThresholdProperties;
import com.careconnect.dto.VitalSampleDTO;
import com.careconnect.dto.WearableReadingIngestionRequest;
import com.careconnect.dto.WearableReadingIngestionResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.VitalSample;
import com.careconnect.model.VitalAlertEvent;
import com.careconnect.model.WearableMetric;
import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.FamilyMemberLink;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.VitalSampleRepository;
import com.careconnect.repository.WearableMetricRepository;
import com.careconnect.repository.PatientCaregiverRepository;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.VitalAlertEventRepository;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.Period;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.CompletableFuture;

@Service
@RequiredArgsConstructor
public class VitalSampleService {

    private static final Logger LOG = LoggerFactory.getLogger(VitalSampleService.class);

    private final VitalSampleRepository vitalSampleRepository;
    private final PatientRepository patientRepository;
    private final WearableMetricRepository wearableMetricRepository;
    private final CaregiverService caregiverService;
    private final NotificationService notificationService;
    private final PatientCaregiverRepository patientCaregiverRepository;
    private final FamilyMemberLinkRepository familyMemberLinkRepository;
    private final VitalAlertEventRepository vitalAlertEventRepository;
    private final VitalAlertThresholdProperties vitalAlertThresholdProperties;

    /**
     * Create a new vital sample
     */
    @Transactional
    public VitalSampleDTO createVitalSample(VitalSampleDTO dto) {
        Patient patient = patientRepository.findById(dto.patientId())
            .orElseThrow(() -> new IllegalArgumentException("Patient not found with id: " + dto.patientId()));
        
        VitalSample vitalSample = VitalSample.builder()
            .patient(patient)
            .timestamp(dto.timestamp() != null ? dto.timestamp() : Instant.now())
            .heartRate(dto.heartRate())
            .spo2(dto.spo2())
            .systolic(dto.systolic())
            .diastolic(dto.diastolic())
            .weight(dto.weight())
            .moodValue(dto.moodValue())
            .painValue(dto.painValue())
            .build();
        
        VitalSample saved = vitalSampleRepository.save(vitalSample);
        
        // Check for vital alerts and send notifications asynchronously
        checkAndSendVitalAlerts(saved);
        
        return mapToDTO(saved);
    }

    @Transactional
    public WearableReadingIngestionResponse ingestWearableReadings(User currentUser, WearableReadingIngestionRequest request) {
        Patient patient = resolveTargetPatient(currentUser, request.patientId());
        Long patientId = patient.getId();
        Long patientUserId = patient.getUser().getId();
        String batchSource = normalizeSource(request.source(), "wearable");

        LOG.info("Starting wearable ingestion: actorUserId={}, patientId={}, patientUserId={}, source={}, batchSize={}",
                currentUser.getId(), patientId, patientUserId, batchSource, request.readings().size());

        List<WearableMetric> wearableMetricsToPersist = new ArrayList<>();
        List<WearableReadingIngestionResponse.IngestedReading> accepted = new ArrayList<>();
        List<WearableReadingIngestionResponse.RejectedReading> rejected = new ArrayList<>();

        for (int i = 0; i < request.readings().size(); i++) {
            WearableReadingIngestionRequest.WearableReadingPayload reading = request.readings().get(i);
            String readingSource = normalizeSource(reading.source(), batchSource);
            try {
                validateRecordedAt(reading.recordedAt());
                validateMetricValue(reading.metricValue());
                WearableMetric.MetricType metricType = parseMetricType(reading.metric());

                WearableMetric wearableMetric = WearableMetric.builder()
                        .patient(patient.getUser())
                        .metric(metricType)
                        .metricValue(reading.metricValue())
                        .recordedAt(reading.recordedAt())
                        .source(readingSource)
                        .build();
                wearableMetricsToPersist.add(wearableMetric);

                accepted.add(new WearableReadingIngestionResponse.IngestedReading(
                        metricType,
                        reading.metricValue(),
                        reading.recordedAt(),
                        readingSource
                ));
            } catch (IllegalArgumentException ex) {
                rejected.add(new WearableReadingIngestionResponse.RejectedReading(
                        i,
                        reading.metric(),
                        reading.metricValue(),
                        reading.recordedAt(),
                        readingSource,
                        ex.getMessage()
                ));
            }
        }

        List<WearableReadingIngestionResponse.IngestedReading> persistedAccepted = new ArrayList<>();
        for (int i = 0; i < wearableMetricsToPersist.size(); i++) {
            WearableMetric metricEntity = wearableMetricsToPersist.get(i);
            WearableReadingIngestionResponse.IngestedReading acceptedReading = accepted.get(i);
            try {
                wearableMetricRepository.save(metricEntity);
                persistedAccepted.add(acceptedReading);
            } catch (DataIntegrityViolationException ex) {
                String reason = rootCauseMessage(ex);
                rejected.add(new WearableReadingIngestionResponse.RejectedReading(
                        -1,
                        acceptedReading.metric().name(),
                        acceptedReading.metricValue(),
                        acceptedReading.recordedAt(),
                        acceptedReading.source(),
                        "Database rejected reading: " + reason
                ));
            } catch (Exception ex) {
                String reason = rootCauseMessage(ex);
                rejected.add(new WearableReadingIngestionResponse.RejectedReading(
                        -1,
                        acceptedReading.metric().name(),
                        acceptedReading.metricValue(),
                        acceptedReading.recordedAt(),
                        acceptedReading.source(),
                        "Failed to persist reading: " + reason
                ));
            }
        }

        List<VitalSample> vitalSamplesToPersist = buildVitalSamplesFromAccepted(patient, persistedAccepted);
        List<VitalSample> savedVitalSamples = new ArrayList<>();
        if (!vitalSamplesToPersist.isEmpty()) {
            try {
                savedVitalSamples = vitalSampleRepository.saveAll(vitalSamplesToPersist);
            } catch (Exception ex) {
                LOG.warn("Skipping vital_sample persistence for wearable ingestion due to error: actorUserId={}, patientId={}, reason={}",
                        currentUser.getId(), patientId, rootCauseMessage(ex));
            }
        }

        for (VitalSample savedVitalSample : savedVitalSamples) {
            checkAndSendVitalAlerts(savedVitalSample);
        }

        LOG.info("Completed wearable ingestion: actorUserId={}, patientId={}, patientUserId={}, accepted={}, rejected={}",
                currentUser.getId(), patientId, patientUserId, persistedAccepted.size(), rejected.size());

        return WearableReadingIngestionResponse.builder()
                .patientId(patientId)
                .source(batchSource)
                .acceptedCount(persistedAccepted.size())
                .rejectedCount(rejected.size())
                .acceptedReadings(persistedAccepted)
                .rejectedReadings(rejected)
                .build();
    }
    
    /**
     * Update an existing vital sample
     */
    @Transactional
    public VitalSampleDTO updateVitalSample(Long id, VitalSampleDTO dto) {
        VitalSample existing = vitalSampleRepository.findById(id)
            .orElseThrow(() -> new IllegalArgumentException("VitalSample not found with id: " + id));
        
        // Update only non-null fields
        if (dto.timestamp() != null) {
            existing.setTimestamp(dto.timestamp());
        }
        if (dto.heartRate() != null) {
            existing.setHeartRate(dto.heartRate());
        }
        if (dto.spo2() != null) {
            existing.setSpo2(dto.spo2());
        }
        if (dto.systolic() != null) {
            existing.setSystolic(dto.systolic());
        }
        if (dto.diastolic() != null) {
            existing.setDiastolic(dto.diastolic());
        }
        if (dto.weight() != null) {
            existing.setWeight(dto.weight());
        }
        if (dto.moodValue() != null) {
            existing.setMoodValue(dto.moodValue());
        }
        if (dto.painValue() != null) {
            existing.setPainValue(dto.painValue());
        }
        
        VitalSample updated = vitalSampleRepository.save(existing);
        return mapToDTO(updated);
    }
    
    /**
     * Get vital samples for a patient within a time period
     */
    public List<VitalSampleDTO> getVitalSamples(Long patientId, Period period) {
        Patient patient = patientRepository.findById(patientId)
            .orElseThrow(() -> new IllegalArgumentException("Patient not found with id: " + patientId));
        
        Instant fromTime = Instant.now().minus(period);
        Instant toTime = Instant.now();
        
        return vitalSampleRepository.findByPatientAndTimestampBetweenOrderByTimestampDesc(
                patient, fromTime, toTime)
            .stream()
            .map(this::mapToDTO)
            .toList();
    }
    
    /**
     * Get a specific vital sample by ID
     */
    public Optional<VitalSampleDTO> getVitalSample(Long id) {
        return vitalSampleRepository.findById(id)
            .map(this::mapToDTO);
    }
    
    /**
     * Delete a vital sample
     */
    @Transactional
    public void deleteVitalSample(Long id) {
        if (!vitalSampleRepository.existsById(id)) {
            throw new IllegalArgumentException("VitalSample not found with id: " + id);
        }
        vitalSampleRepository.deleteById(id);
    }
    
    /**
     * Get the latest vital sample for a patient
     */
    public Optional<VitalSampleDTO> getLatestVitalSample(Long patientId) {
        Patient patient = patientRepository.findById(patientId)
            .orElseThrow(() -> new IllegalArgumentException("Patient not found with id: " + patientId));
        
        return vitalSampleRepository.findFirstByPatientOrderByTimestampDesc(patient)
            .map(this::mapToDTO);
    }
    
    /**
     * Map VitalSample entity to DTO
     */
    private VitalSampleDTO mapToDTO(VitalSample vitalSample) {
        return VitalSampleDTO.builder()
            .id(vitalSample.getId())
            .patientId(vitalSample.getPatient().getId())
            .timestamp(vitalSample.getTimestamp())
            .heartRate(vitalSample.getHeartRate())
            .spo2(vitalSample.getSpo2())
            .systolic(vitalSample.getSystolic())
            .diastolic(vitalSample.getDiastolic())
            .weight(vitalSample.getWeight())
            .moodValue(vitalSample.getMoodValue())
            .painValue(vitalSample.getPainValue())
            .build();
    }
    
    /**
     * Check vital signs and send alerts if necessary
     */
    private void checkAndSendVitalAlerts(VitalSample vitalSample) {
        try {
            if (vitalSample.getPatient() == null || vitalSample.getPatient().getUser() == null) {
                LOG.warn("Skipping vital alert dispatch because patient/user linkage is missing for sample {}", vitalSample.getId());
                return;
            }
            Long patientUserId = vitalSample.getPatient().getUser().getId();
            
            // Check heart rate alerts
            if (vitalSample.getHeartRate() != null) {
                String alertLevel = determineHeartRateAlert(vitalSample.getHeartRate());
                if (!"NORMAL".equals(alertLevel)) {
                    sendVitalAlertIfEnabled(
                        vitalSample.getPatient(),
                        patientUserId,
                        "heart_rate",
                        vitalSample.getHeartRate() + " bpm",
                        alertLevel
                    );
                }
            }
            
            // Check SpO2 alerts
            if (vitalSample.getSpo2() != null) {
                String alertLevel = determineSpO2Alert(vitalSample.getSpo2());
                if (!"NORMAL".equals(alertLevel)) {
                    sendVitalAlertIfEnabled(
                        vitalSample.getPatient(),
                        patientUserId,
                        "spo2",
                        vitalSample.getSpo2() + "%",
                        alertLevel
                    );
                }
            }
            
            // Check blood pressure alerts
            if (vitalSample.getSystolic() != null || vitalSample.getDiastolic() != null) {
                String alertLevel = determineBPAlert(vitalSample.getSystolic(), vitalSample.getDiastolic());
                if (!"NORMAL".equals(alertLevel)) {
                    String bpValue = (vitalSample.getSystolic() != null ? vitalSample.getSystolic() : "?") + 
                                   "/" + (vitalSample.getDiastolic() != null ? vitalSample.getDiastolic() : "?");
                    sendVitalAlertIfEnabled(
                        vitalSample.getPatient(),
                        patientUserId,
                        "blood_pressure",
                        bpValue + " mmHg",
                        alertLevel
                    );
                }
            }
            
            // Check mood alerts (severe depression or anxiety)
            if (vitalSample.getMoodValue() != null && vitalSample.getMoodValue() <= 2) {
                sendVitalAlertIfEnabled(
                    vitalSample.getPatient(),
                    patientUserId,
                    "mood",
                    "score=" + vitalSample.getMoodValue(),
                    "HIGH"
                );
            }
            
            // Check pain alerts (severe pain)
            if (vitalSample.getPainValue() != null && vitalSample.getPainValue() >= 8) {
                sendVitalAlertIfEnabled(
                    vitalSample.getPatient(),
                    patientUserId,
                    "pain",
                    "score=" + vitalSample.getPainValue(),
                    "HIGH"
                );
            }
            
        } catch (Exception e) {
            // Log error but don't fail the vital recording
            LOG.warn("Error sending vital alerts: {}", e.getMessage(), e);
        }
    }

    private Patient resolveTargetPatient(User currentUser, Long requestedPatientId) {
        if (currentUser.getRole() == com.careconnect.security.Role.PATIENT) {
            Patient ownPatient = patientRepository.findByUser(currentUser)
                    .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));
            if (requestedPatientId != null && !requestedPatientId.equals(ownPatient.getId())) {
                throw new AppException(HttpStatus.FORBIDDEN, "Not authorized to ingest readings for this patient");
            }
            return ownPatient;
        }

        if (requestedPatientId == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "patientId is required for this role");
        }

        Patient patient = patientRepository.findById(requestedPatientId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));

        switch (currentUser.getRole()) {
            case CAREGIVER, FAMILY_MEMBER -> {
                boolean hasAccess = caregiverService.hasAccessToPatient(currentUser.getId(), requestedPatientId);
                if (!hasAccess) {
                    throw new AppException(HttpStatus.FORBIDDEN, "Not authorized to ingest readings for this patient");
                }
            }
            case ADMIN -> {
                // Admin can ingest for any patient.
            }
            default -> throw new AppException(HttpStatus.FORBIDDEN, "Not authorized to ingest readings for this patient");
        }

        return patient;
    }

    private WearableMetric.MetricType parseMetricType(String rawMetric) {
        if (rawMetric == null || rawMetric.isBlank()) {
            throw new IllegalArgumentException("metric is required");
        }
        try {
            return WearableMetric.MetricType.valueOf(rawMetric.trim().toUpperCase());
        } catch (IllegalArgumentException ex) {
            throw new IllegalArgumentException("Unsupported metric: " + rawMetric);
        }
    }

    private void validateRecordedAt(Instant recordedAt) {
        if (recordedAt == null) {
            throw new IllegalArgumentException("recordedAt is required");
        }
        if (recordedAt.isAfter(Instant.now())) {
            throw new IllegalArgumentException("recordedAt cannot be in the future");
        }
    }

    private void validateMetricValue(Double metricValue) {
        if (metricValue == null) {
            throw new IllegalArgumentException("metricValue is required");
        }
        if (!Double.isFinite(metricValue)) {
            throw new IllegalArgumentException("metricValue must be a finite number");
        }
    }

    private String normalizeSource(String source, String fallback) {
        String normalized = (source == null || source.isBlank()) ? fallback : source.trim();
        return normalized.length() > 64 ? normalized.substring(0, 64) : normalized;
    }

    private void applyMetricToVitalSample(VitalSample vitalSample, WearableMetric.MetricType metricType, Double metricValue) {
        switch (metricType) {
            case HEART_RATE -> vitalSample.setHeartRate(metricValue);
            case SPO2 -> vitalSample.setSpo2(metricValue);
            case BLOOD_PRESSURE_SYS -> vitalSample.setSystolic(metricValue.intValue());
            case BLOOD_PRESSURE_DIA -> vitalSample.setDiastolic(metricValue.intValue());
            case WEIGHT -> vitalSample.setWeight(metricValue);
            case TEMPERATURE, STEPS -> {
                // Stored in wearable_metric only for now.
            }
        }
    }
    private boolean supportsVitalSampleMetric(WearableMetric.MetricType metricType) {
        return switch (metricType) {
            case HEART_RATE, SPO2, BLOOD_PRESSURE_SYS, BLOOD_PRESSURE_DIA, WEIGHT -> true;
            case TEMPERATURE, STEPS -> false;
        };
    }

    private List<VitalSample> buildVitalSamplesFromAccepted(
            Patient patient,
            List<WearableReadingIngestionResponse.IngestedReading> acceptedReadings
    ) {
        java.util.Map<Instant, VitalSample> byTimestamp = new java.util.HashMap<>();
        for (WearableReadingIngestionResponse.IngestedReading reading : acceptedReadings) {
            if (!supportsVitalSampleMetric(reading.metric())) {
                continue;
            }
            VitalSample vitalSample = byTimestamp.computeIfAbsent(reading.recordedAt(), timestamp ->
                    VitalSample.builder()
                            .patient(patient)
                            .timestamp(timestamp)
                            .source(reading.source())
                            .build());
            applyMetricToVitalSample(vitalSample, reading.metric(), reading.metricValue());
        }
        return new ArrayList<>(byTimestamp.values());
    }

    private String rootCauseMessage(Throwable throwable) {
        Throwable root = throwable;
        while (root.getCause() != null) {
            root = root.getCause();
        }
        String message = root.getMessage();
        if (message == null || message.isBlank()) {
            message = throwable.getMessage();
        }
        if (message == null || message.isBlank()) {
            return "Unknown persistence error";
        }
        return message.length() > 180 ? message.substring(0, 180) + "..." : message;
    }
    
    private String determineHeartRateAlert(Double heartRate) {
        if (heartRate == null) return "NORMAL";
        VitalAlertThresholdProperties.HeartRate policy = vitalAlertThresholdProperties.getHeartRate();
        if (heartRate > policy.getCriticalMin()) return "CRITICAL";
        if (heartRate > policy.getHighMin()) return "HIGH";
        if (heartRate < policy.getLowMax()) return "LOW";
        return "NORMAL";
    }
    
    private String determineSpO2Alert(Double spo2) {
        if (spo2 == null) return "NORMAL";
        VitalAlertThresholdProperties.Spo2 policy = vitalAlertThresholdProperties.getSpo2();
        if (spo2 < policy.getCriticalMax()) return "CRITICAL";
        if (spo2 < policy.getHighMax()) return "HIGH";
        return "NORMAL";
    }
    
    private String determineBPAlert(Integer systolic, Integer diastolic) {
        VitalAlertThresholdProperties.Thresholds systolicPolicy = vitalAlertThresholdProperties.getBloodPressure().getSystolic();
        VitalAlertThresholdProperties.Thresholds diastolicPolicy = vitalAlertThresholdProperties.getBloodPressure().getDiastolic();
        if (systolic != null && systolic > systolicPolicy.getCriticalMin()) return "CRITICAL";
        if (diastolic != null && diastolic > diastolicPolicy.getCriticalMin()) return "CRITICAL";
        if (systolic != null && systolic > systolicPolicy.getHighMin()) return "HIGH";
        if (diastolic != null && diastolic > diastolicPolicy.getHighMin()) return "HIGH";
        if (systolic != null && systolic < systolicPolicy.getLowMax()) return "LOW";
        if (diastolic != null && diastolic < diastolicPolicy.getLowMax()) return "LOW";
        return "NORMAL";
    }
    
    /**
     * Helper method to send vital alerts only if Firebase is enabled
     */
    private void sendVitalAlertIfEnabled(
            Patient patient,
            Long patientUserId,
            String metricType,
            String measuredValue,
            String alertLevel
    ) {
        if (patient == null || patient.getId() == null) {
            LOG.warn("Skipping vital alert event because patient context is missing for user {}", patientUserId);
            return;
        }

        Set<Long> recipientUserIds = resolveAlertRecipientUserIds(patient.getUser(), patientUserId);
        if (recipientUserIds.isEmpty()) {
            saveVitalAlertEvent(
                    patient.getId(),
                    patientUserId,
                    metricType,
                    measuredValue,
                    alertLevel,
                    "NO_RECIPIENTS",
                    0,
                    0,
                    0,
                    "No active care-circle recipients found"
            );
            return;
        }

        String patientDisplayName = buildPatientDisplayName(patient);
        CompletableFuture.runAsync(() -> dispatchVitalAlertAndRecordEvent(
                patient.getId(),
                patientUserId,
                patientDisplayName,
                metricType,
                measuredValue,
                alertLevel,
                recipientUserIds
        )).exceptionally(ex -> {
            LOG.warn(
                    "Failed to dispatch vital alert event for patientUserId={} (metricType={}, measuredValue={}, severity={})",
                    patientUserId,
                    metricType,
                    measuredValue,
                    alertLevel,
                    ex
            );
            saveVitalAlertEvent(
                    patient.getId(),
                    patientUserId,
                    metricType,
                    measuredValue,
                    alertLevel,
                    "FAILED",
                    recipientUserIds.size(),
                    0,
                    recipientUserIds.size(),
                    rootCauseMessage(ex)
            );
            return null;
        });
    }

    private void dispatchVitalAlertAndRecordEvent(
            Long patientId,
            Long patientUserId,
            String patientDisplayName,
            String metricType,
            String measuredValue,
            String alertLevel,
            Set<Long> recipientUserIds
    ) {
        int successCount = 0;
        int failureCount = 0;
        String firstFailure = null;

        for (Long recipientUserId : recipientUserIds) {
            try {
                List<com.careconnect.dto.NotificationResponse> responses = notificationService.sendVitalAlertToRecipient(
                        recipientUserId,
                        patientDisplayName,
                        metricType,
                        measuredValue,
                        alertLevel
                );
                boolean recipientSucceeded = responses.stream().anyMatch(com.careconnect.dto.NotificationResponse::isSuccess);
                if (recipientSucceeded) {
                    successCount++;
                } else {
                    failureCount++;
                    if (firstFailure == null) {
                        firstFailure = "No channels succeeded for recipient userId=" + recipientUserId;
                    }
                }
            } catch (Exception ex) {
                failureCount++;
                if (firstFailure == null) {
                    firstFailure = "Recipient userId=" + recipientUserId + " failed: " + rootCauseMessage(ex);
                }
            }
        }

        String status = failureCount == 0 ? "DELIVERED" : (successCount > 0 ? "PARTIAL_FAILURE" : "FAILED");
        saveVitalAlertEvent(
                patientId,
                patientUserId,
                metricType,
                measuredValue,
                alertLevel,
                status,
                recipientUserIds.size(),
                successCount,
                failureCount,
                firstFailure
        );
    }

    private Set<Long> resolveAlertRecipientUserIds(User patientUser, Long patientUserId) {
        Set<Long> recipientUserIds = new HashSet<>();
        LocalDateTime now = LocalDateTime.now();

        List<CaregiverPatientLink> caregiverLinks = patientCaregiverRepository.findByPatientUser(patientUser);
        for (CaregiverPatientLink link : caregiverLinks) {
            if (link == null || link.getCaregiverUser() == null || link.getCaregiverUser().getId() == null) {
                continue;
            }
            if (link.getStatus() != CaregiverPatientLink.LinkStatus.ACTIVE) {
                continue;
            }
            if (link.getExpiresAt() != null && link.getExpiresAt().isBefore(now)) {
                continue;
            }
            recipientUserIds.add(link.getCaregiverUser().getId());
        }

        List<FamilyMemberLink> familyLinks = familyMemberLinkRepository.findActiveFamilyMembersByPatient(patientUserId, now);
        for (FamilyMemberLink link : familyLinks) {
            if (link != null && link.getFamilyUser() != null && link.getFamilyUser().getId() != null) {
                recipientUserIds.add(link.getFamilyUser().getId());
            }
        }

        return recipientUserIds;
    }

    private String buildPatientDisplayName(Patient patient) {
        String first = patient.getFirstName() == null ? "" : patient.getFirstName().trim();
        String last = patient.getLastName() == null ? "" : patient.getLastName().trim();
        String fullName = (first + " " + last).trim();
        if (!fullName.isEmpty()) {
            return fullName;
        }
        if (patient.getUser() != null && patient.getUser().getName() != null && !patient.getUser().getName().isBlank()) {
            return patient.getUser().getName().trim();
        }
        return "Patient";
    }

    private void saveVitalAlertEvent(
            Long patientId,
            Long patientUserId,
            String metricType,
            String measuredValue,
            String alertLevel,
            String status,
            int recipientCount,
            int successCount,
            int failureCount,
            String failureReason
    ) {
        try {
            VitalAlertEvent event = VitalAlertEvent.builder()
                    .patientId(patientId)
                    .patientUserId(patientUserId)
                    .metricType(metricType)
                    .measuredValue(measuredValue)
                    .alertLevel(alertLevel)
                    .status(status)
                    .recipientCount(recipientCount)
                    .successCount(successCount)
                    .failureCount(failureCount)
                    .failureReason(failureReason)
                    .occurredAt(Instant.now())
                    .build();
            vitalAlertEventRepository.save(event);
        } catch (Exception ex) {
            LOG.warn(
                    "Unable to persist vital alert event audit trail for patientId={}, patientUserId={}, metricType={}, alertLevel={}",
                    patientId,
                    patientUserId,
                    metricType,
                    alertLevel,
                    ex
            );
        }
    }
}
