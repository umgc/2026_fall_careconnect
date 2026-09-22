package com.careconnect.service;

import com.careconnect.dto.MoodPainLogRequest;
import com.careconnect.dto.MoodPainLogResponse;
import com.careconnect.dto.MoodPainAnalyticsDTO;
import com.careconnect.exception.AppException;
import com.careconnect.model.MoodPainLog;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.MoodPainLogRepository;
import com.careconnect.repository.PatientRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Objects;
import java.util.stream.Collectors;
import java.util.List;
import java.util.Objects;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class MoodPainLogService {

    private final MoodPainLogRepository moodPainLogRepository;
    private final PatientRepository patientRepository;

    /**
     * Create a new mood pain log entry for a patient
     */
    public MoodPainLogResponse createMoodPainLog(User currentUser, MoodPainLogRequest request) {
        // Find the patient associated with the current user
        Patient patient = patientRepository.findByUser(currentUser)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));

        // Validate the request
        validateMoodPainLogRequest(request);

        // Create the mood pain log entry
        MoodPainLog moodPainLog = MoodPainLog.builder()
                .patient(patient)
                .moodValue(request.getMoodValue())
                .painValue(request.getPainValue())
                .note(request.getNote())
                .timestamp(request.getTimestamp())
                .build();

        MoodPainLog savedLog = moodPainLogRepository.save(moodPainLog);
        return convertToResponse(savedLog);
    }

    /**
     * Get all mood pain logs for a patient
     */
    public List<MoodPainLogResponse> getMoodPainLogs(User currentUser) {
        Patient patient = patientRepository.findByUser(currentUser)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));

        List<MoodPainLog> logs = moodPainLogRepository.findByPatientOrderByTimestampDesc(patient);
        return logs.stream()
                .map(this::convertToResponse)
                .collect(Collectors.toList());
    }

    /**
     * Get mood pain logs with pagination
     */
    public Page<MoodPainLogResponse> getMoodPainLogsWithPagination(User currentUser, int page, int size) {
        Patient patient = patientRepository.findByUser(currentUser)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));

        Pageable pageable = PageRequest.of(page, size);
        Page<MoodPainLog> logs = moodPainLogRepository.findByPatientOrderByTimestampDesc(patient, pageable);

        return logs.map(this::convertToResponse);
    }

    /**
     * Get mood pain logs within a date range
     */
    public List<MoodPainLogResponse> getMoodPainLogsByDateRange(
            User currentUser,
            LocalDateTime startDate,
            LocalDateTime endDate) {

        Patient patient = patientRepository.findByUser(currentUser)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));

        List<MoodPainLog> logs = moodPainLogRepository.findByPatientAndTimestampBetween(
                patient, startDate, endDate);

        return logs.stream()
                .map(this::convertToResponse)
                .collect(Collectors.toList());
    }

    /**
     * Get the most recent mood pain log for a patient
     */
    public MoodPainLogResponse getLatestMoodPainLog(User currentUser) {
        Patient patient = patientRepository.findByUser(currentUser)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));

        MoodPainLog latestLog = moodPainLogRepository.findFirstByPatientOrderByTimestampDesc(patient);

        if (latestLog == null) {
            throw new AppException(HttpStatus.NOT_FOUND, "No mood pain logs found for this patient");
        }

        return convertToResponse(latestLog);
    }

    /**
     * Update an existing mood pain log entry
     */
    public MoodPainLogResponse updateMoodPainLog(User currentUser, Long logId, MoodPainLogRequest request) {
        Patient patient = patientRepository.findByUser(currentUser)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));

        MoodPainLog existingLog = moodPainLogRepository.findById(logId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Mood pain log not found"));

        // Verify the log belongs to the current patient
        if (!existingLog.getPatient().getId().equals(patient.getId())) {
            throw new AppException(HttpStatus.FORBIDDEN, "You don't have permission to update this log");
        }

        // Validate the request
        validateMoodPainLogRequest(request);

        // Update the log
        existingLog.setMoodValue(request.getMoodValue());
        existingLog.setPainValue(request.getPainValue());
        existingLog.setNote(request.getNote());
        existingLog.setTimestamp(request.getTimestamp());

        MoodPainLog updatedLog = moodPainLogRepository.save(existingLog);
        return convertToResponse(updatedLog);
    }

    /**
     * Delete a mood pain log entry
     */
    public void deleteMoodPainLog(User currentUser, Long logId) {
        Patient patient = patientRepository.findByUser(currentUser)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));

        MoodPainLog existingLog = moodPainLogRepository.findById(logId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Mood pain log not found"));

        // Verify the log belongs to the current patient
        if (!existingLog.getPatient().getId().equals(patient.getId())) {
            throw new AppException(HttpStatus.FORBIDDEN, "You don't have permission to delete this log");
        }

        moodPainLogRepository.delete(existingLog);
    }

    /**
     * Get mood pain logs for a specific patient (for caregivers to view)
     */
    public List<MoodPainLogResponse> getMoodPainLogsForPatient(Long patientId) {
        Patient patient = patientRepository.findById(patientId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));

        List<MoodPainLog> logs = moodPainLogRepository.findByPatientOrderByTimestampDesc(patient);
        return logs.stream()
                .map(this::convertToResponse)
                .collect(Collectors.toList());
    }

    /**
     * Get detailed mood and pain analytics for a patient
     */
    public MoodPainAnalyticsDTO getMoodPainAnalytics(User currentUser, LocalDateTime startDate, LocalDateTime endDate) {
        Patient patient = patientRepository.findByUser(currentUser)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient profile not found"));

        List<MoodPainLog> logs = moodPainLogRepository.findByPatientAndTimestampBetween(patient, startDate, endDate);

        if (logs.isEmpty()) {
            return MoodPainAnalyticsDTO.builder()
                    .periodStart(startDate)
                    .periodEnd(endDate)
                    .totalEntries(0)
                    .moodEntries(0)
                    .painEntries(0)
                    .timeSeries(Collections.emptyList())
                    .build();
        }

        // Calculate statistics
        List<Integer> moodValues = logs.stream()
                .map(MoodPainLog::getMoodValue)
                .filter(Objects::nonNull)
                .collect(Collectors.toList());

        List<Integer> painValues = logs.stream()
                .map(MoodPainLog::getPainValue)
                .filter(Objects::nonNull)
                .collect(Collectors.toList());

        Double avgMood = moodValues.isEmpty() ? null :
                moodValues.stream().mapToInt(Integer::intValue).average().orElse(0.0);
        Double avgPain = painValues.isEmpty() ? null :
                painValues.stream().mapToInt(Integer::intValue).average().orElse(0.0);

        Integer minMood = moodValues.isEmpty() ? null : Collections.min(moodValues);
        Integer maxMood = moodValues.isEmpty() ? null : Collections.max(moodValues);
        Integer minPain = painValues.isEmpty() ? null : Collections.min(painValues);
        Integer maxPain = painValues.isEmpty() ? null : Collections.max(painValues);

        // Calculate trends (simple linear regression slope)
        Double moodTrend = calculateTrend(logs, true);  // true for mood
        Double painTrend = calculateTrend(logs, false); // false for pain

        // Create time series data
        List<MoodPainAnalyticsDTO.MoodPainTimeSeriesPoint> timeSeries = logs.stream()
                .map(log -> MoodPainAnalyticsDTO.MoodPainTimeSeriesPoint.builder()
                        .timestamp(log.getTimestamp())
                        .moodValue(log.getMoodValue())
                        .painValue(log.getPainValue())
                        .note(log.getNote())
                        .build())
                .collect(Collectors.toList());

        return MoodPainAnalyticsDTO.builder()
                .periodStart(startDate)
                .periodEnd(endDate)
                .avgMood(avgMood)
                .avgPain(avgPain)
                .totalEntries(logs.size())
                .moodEntries(moodValues.size())
                .painEntries(painValues.size())
                .moodTrend(moodTrend)
                .painTrend(painTrend)
                .minMood(minMood)
                .maxMood(maxMood)
                .minPain(minPain)
                .maxPain(maxPain)
                .timeSeries(timeSeries)
                .build();
    }

    /**
     * Calculate trend using simple linear regression
     */
    private Double calculateTrend(List<MoodPainLog> logs, boolean isMood) {
        List<MoodPainLog> validLogs = logs.stream()
                .filter(log -> isMood ? log.getMoodValue() != null : log.getPainValue() != null)
                .sorted(Comparator.comparing(MoodPainLog::getTimestamp))
                .collect(Collectors.toList());

        if (validLogs.size() < 2) {
            return null;
        }

        int n = validLogs.size();
        double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;

        for (int i = 0; i < n; i++) {
            double x = i; // time index
            double y = isMood ? validLogs.get(i).getMoodValue() : validLogs.get(i).getPainValue();

            sumX += x;
            sumY += y;
            sumXY += x * y;
            sumX2 += x * x;
        }

        // Calculate slope (trend)
        double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
        return slope;
    }

    /**
     * Validate mood pain log request
     */
    private void validateMoodPainLogRequest(MoodPainLogRequest request) {
        if (request.getMoodValue() == null || request.getMoodValue() < 1 || request.getMoodValue() > 10) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Mood value must be between 1 and 10");
        }

        if (request.getPainValue() == null || request.getPainValue() < 0 || request.getPainValue() > 10) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Pain value must be between 0 and 10");
        }

        if (request.getTimestamp() == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Timestamp is required");
        }

        // Validate timestamp is not in the future
        if (request.getTimestamp().isAfter(LocalDateTime.now())) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Timestamp cannot be in the future");
        }
    }

    /**
     * Convert MoodPainLog entity to response DTO
     */
    private MoodPainLogResponse convertToResponse(MoodPainLog log) {
        return MoodPainLogResponse.builder()
                .id(log.getId())
                .patientId(log.getPatient().getId())
                .moodValue(log.getMoodValue())
                .painValue(log.getPainValue())
                .note(log.getNote())
                .timestamp(log.getTimestamp())
                .createdAt(log.getCreatedAt())
                .updatedAt(log.getUpdatedAt())
                .build();
    }
}
