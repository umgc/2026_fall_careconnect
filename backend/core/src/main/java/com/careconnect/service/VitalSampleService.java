package com.careconnect.service;

import com.careconnect.dto.VitalSampleDTO;
import com.careconnect.dto.WearableReadingIngestionRequest;
import com.careconnect.dto.WearableReadingIngestionResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.VitalSample;
import com.careconnect.model.WearableMetric;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.VitalSampleRepository;
import com.careconnect.repository.WearableMetricRepository;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.Period;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class VitalSampleService {

    private static final Logger LOG = LoggerFactory.getLogger(VitalSampleService.class);

    private final VitalSampleRepository vitalSampleRepository;
    private final PatientRepository patientRepository;
    private final WearableMetricRepository wearableMetricRepository;
    private final CaregiverService caregiverService;

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
            Long patientId = vitalSample.getPatient().getId();
            
            // Check heart rate alerts
            if (vitalSample.getHeartRate() != null) {
                String alertLevel = determineHeartRateAlert(vitalSample.getHeartRate());
                if (!"NORMAL".equals(alertLevel)) {
                    sendVitalAlertIfEnabled(
                        patientId, 
                        "Heart Rate", 
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
                        patientId, 
                        "Blood Oxygen (SpO2)", 
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
                        patientId, 
                        "Blood Pressure", 
                        bpValue + " mmHg", 
                        alertLevel
                    );
                }
            }
            
            // Check mood alerts (severe depression or anxiety)
            if (vitalSample.getMoodValue() != null && vitalSample.getMoodValue() <= 2) {
                sendVitalAlertIfEnabled(
                    patientId, 
                    "Mood", 
                    "Low mood score: " + vitalSample.getMoodValue(), 
                    "HIGH"
                );
            }
            
            // Check pain alerts (severe pain)
            if (vitalSample.getPainValue() != null && vitalSample.getPainValue() >= 8) {
                sendVitalAlertIfEnabled(
                    patientId, 
                    "Pain Level", 
                    "High pain score: " + vitalSample.getPainValue(), 
                    "HIGH"
                );
            }
            
        } catch (Exception e) {
            // Log error but don't fail the vital recording
            System.err.println("Error sending vital alerts: " + e.getMessage());
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
        if (heartRate < 60) return "LOW";
        if (heartRate > 120) return "CRITICAL";
        if (heartRate > 100) return "HIGH";
        return "NORMAL";
    }
    
    private String determineSpO2Alert(Double spo2) {
        if (spo2 == null) return "NORMAL";
        if (spo2 < 90) return "CRITICAL";
        if (spo2 < 95) return "HIGH";
        return "NORMAL";
    }
    
    private String determineBPAlert(Integer systolic, Integer diastolic) {
        if (systolic != null && systolic > 180) return "CRITICAL";
        if (diastolic != null && diastolic > 110) return "CRITICAL";
        if (systolic != null && systolic > 140) return "HIGH";
        if (diastolic != null && diastolic > 90) return "HIGH";
        if (systolic != null && systolic < 90) return "LOW";
        if (diastolic != null && diastolic < 60) return "LOW";
        return "NORMAL";
    }
    
    /**
     * Helper method to send vital alerts only if Firebase is enabled
     */
    private void sendVitalAlertIfEnabled(Long patientId, String type, String value, String alertLevel) {
        // Firebase notification logic removed
    }
}
