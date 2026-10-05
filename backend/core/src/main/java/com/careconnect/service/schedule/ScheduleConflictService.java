package com.careconnect.service.schedule;

import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.stream.Collectors;

/**
 * Service to detect scheduling conflicts for caregivers and patients
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ScheduleConflictService {

    private static final int DAILY_VISIT_LIMIT = 8;
    private final ScheduledVisitRepository scheduledVisitRepository;

    /**
     * Detect overlapping visits for the same caregiver
     */
    public List<ScheduledVisit> detectCaregiverConflicts(
            Long caregiverId,
            LocalDate date,
            LocalTime startTime,
            Integer durationMinutes) {
        LocalTime endTime = startTime.plusMinutes(durationMinutes);

        // Convert times to minutes for easier calculation
        int startMinutes = startTime.getHour() * 60 + startTime.getMinute();
        int endMinutes = endTime.getHour() * 60 + endTime.getMinute();

        log.debug("Checking caregiver {} conflicts on {} from {} to {}",
                caregiverId, date, startTime, endTime);

        List<ScheduledVisit> existingVisits = scheduledVisitRepository
                .findByCaregiverIdAndScheduledDate(caregiverId, date);

        return existingVisits.stream()
                .filter(visit -> visit.getStatus() != null && !visit.getStatus().equals("Cancelled"))
                .filter(visit -> {
                    int visitStartMinutes = visit.getScheduledTime().getHour() * 60 +
                            visit.getScheduledTime().getMinute();
                    int visitEndMinutes = visitStartMinutes + visit.getDurationMinutes();

                    // Check if time ranges overlap
                    return startMinutes < visitEndMinutes && endMinutes > visitStartMinutes;
                })
                .collect(Collectors.toList());
    }

    /**
     * Detect overlapping visits for the same patient
     */
    public List<ScheduledVisit> detectPatientConflicts(
            Long patientId,
            LocalDate date,
            LocalTime startTime,
            Integer durationMinutes) {
        LocalTime endTime = startTime.plusMinutes(durationMinutes);

        int startMinutes = startTime.getHour() * 60 + startTime.getMinute();
        int endMinutes = endTime.getHour() * 60 + endTime.getMinute();

        log.debug("Checking patient {} conflicts on {} from {} to {}",
                patientId, date, startTime, endTime);

        List<ScheduledVisit> patientVisits = scheduledVisitRepository
                .findByPatientId(patientId);

        return patientVisits.stream()
                .filter(visit -> visit.getScheduledDate().equals(date))
                .filter(visit -> visit.getStatus() != null && !visit.getStatus().equals("Cancelled"))
                .filter(visit -> {
                    int visitStartMinutes = visit.getScheduledTime().getHour() * 60 +
                            visit.getScheduledTime().getMinute();
                    int visitEndMinutes = visitStartMinutes + visit.getDurationMinutes();

                    return startMinutes < visitEndMinutes && endMinutes > visitStartMinutes;
                })
                .collect(Collectors.toList());
    }

    /**
     * Check if caregiver exceeds daily visit limit
     */
    public boolean exceedsDailyLimit(Long caregiverId, LocalDate date) {
        long visitCount = scheduledVisitRepository
                .countByCaregiverIdAndScheduledDateAndStatusNot(caregiverId, date, "Cancelled");

        log.debug("Caregiver {} has {} visits on {}", caregiverId, visitCount, date);
        return visitCount >= DAILY_VISIT_LIMIT;
    }

    /**
     * Check if caregiver exceeds daily visit limit (with custom limit)
     */
    public boolean exceedsDailyLimit(Long caregiverId, LocalDate date, int limit) {
        long visitCount = scheduledVisitRepository
                .countByCaregiverIdAndScheduledDateAndStatusNot(caregiverId, date, "Cancelled");

        return visitCount >= limit;
    }

    /**
     * Get total duration of visits for a caregiver on a specific date
     */
    public int getTotalDurationForDay(Long caregiverId, LocalDate date) {
        List<ScheduledVisit> visits = scheduledVisitRepository
                .findByCaregiverIdAndScheduledDate(caregiverId, date);

        return visits.stream()
                .filter(visit -> visit.getStatus() != null && !visit.getStatus().equals("Cancelled"))
                .mapToInt(ScheduledVisit::getDurationMinutes)
                .sum();
    }

    /**
     * Check if adding a visit would exceed maximum daily hours (e.g., 10 hours)
     */
    public boolean exceedsDailyHours(Long caregiverId, LocalDate date, int newVisitDuration, int maxHours) {
        int totalCurrentDuration = getTotalDurationForDay(caregiverId, date);
        int maxMinutes = maxHours * 60;

        return (totalCurrentDuration + newVisitDuration) > maxMinutes;
    }

    /**
     * Find nearest available slot for a caregiver on a specific date
     */
    public LocalTime findNextAvailableSlot(Long caregiverId, LocalDate date, int durationMinutes) {
        List<ScheduledVisit> visits = scheduledVisitRepository
                .findByCaregiverIdAndScheduledDate(caregiverId, date);

        visits.sort((a, b) -> {
            int aTime = a.getScheduledTime().getHour() * 60 + a.getScheduledTime().getMinute();
            int bTime = b.getScheduledTime().getHour() * 60 + b.getScheduledTime().getMinute();
            return Integer.compare(aTime, bTime);
        });

        // Start checking from 8 AM
        LocalTime currentSlot = LocalTime.of(8, 0);

        for (ScheduledVisit visit : visits) {
            LocalTime visitEnd = visit.getScheduledTime().plusMinutes(visit.getDurationMinutes());

            // If current slot fits before this visit, return it
            if (currentSlot.plusMinutes(durationMinutes).isBefore(visit.getScheduledTime())) {
                return currentSlot;
            }

            // Move to after this visit
            currentSlot = visitEnd;
        }

        // Check if the final slot is before 6 PM
        if (currentSlot.plusMinutes(durationMinutes).isBefore(LocalTime.of(18, 0))) {
            return currentSlot;
        }

        // No available slot found
        return null;
    }

    /**
     * Get conflict summary for a visit request
     */
    public ConflictSummary analyzeConflicts(
            Long caregiverId,
            Long patientId,
            LocalDate date,
            LocalTime startTime,
            Integer durationMinutes) {
        ConflictSummary summary = new ConflictSummary();

        // Check caregiver conflicts
        List<ScheduledVisit> caregiverConflicts = detectCaregiverConflicts(
                caregiverId, date, startTime, durationMinutes);
        if (!caregiverConflicts.isEmpty()) {
            summary.setCaregiverConflicts(caregiverConflicts);
            summary.addWarning("Caregiver has " + caregiverConflicts.size() +
                    " overlapping visit(s) at this time");
        }

        // Check patient conflicts
        List<ScheduledVisit> patientConflicts = detectPatientConflicts(
                patientId, date, startTime, durationMinutes);
        if (!patientConflicts.isEmpty()) {
            summary.setPatientConflicts(patientConflicts);
            summary.addWarning("Patient has " + patientConflicts.size() +
                    " overlapping visit(s) at this time");
        }

        // Check daily limit
        if (exceedsDailyLimit(caregiverId, date)) {
            summary.setExceedsDailyLimit(true);
            summary.addWarning("Caregiver already has max visits (" + DAILY_VISIT_LIMIT + ") scheduled for this day");
        }

        // Check daily hours
        if (exceedsDailyHours(caregiverId, date, durationMinutes, 10)) {
            summary.setExceedsDailyHours(true);
            summary.addWarning("Adding this visit would exceed 10 working hours for the day");
        }

        return summary;
    }

    /**
     * Helper class to store conflict analysis results
     */
    public static class ConflictSummary {
        private List<ScheduledVisit> caregiverConflicts;
        private List<ScheduledVisit> patientConflicts;
        private boolean exceedsDailyLimit;
        private boolean exceedsDailyHours;
        private java.util.List<String> warnings;

        public ConflictSummary() {
            this.caregiverConflicts = new java.util.ArrayList<>();
            this.patientConflicts = new java.util.ArrayList<>();
            this.warnings = new java.util.ArrayList<>();
        }

        public boolean hasConflicts() {
            return (caregiverConflicts != null && !caregiverConflicts.isEmpty()) ||
                    (patientConflicts != null && !patientConflicts.isEmpty());
        }

        public boolean hasWarnings() {
            return !warnings.isEmpty();
        }

        public void addWarning(String warning) {
            this.warnings.add(warning);
        }

        // Getters and Setters
        public List<ScheduledVisit> getCaregiverConflicts() {
            return caregiverConflicts;
        }

        public void setCaregiverConflicts(List<ScheduledVisit> caregiverConflicts) {
            this.caregiverConflicts = caregiverConflicts;
        }

        public List<ScheduledVisit> getPatientConflicts() {
            return patientConflicts;
        }

        public void setPatientConflicts(List<ScheduledVisit> patientConflicts) {
            this.patientConflicts = patientConflicts;
        }

        public boolean isExceedsDailyLimit() {
            return exceedsDailyLimit;
        }

        public void setExceedsDailyLimit(boolean exceedsDailyLimit) {
            this.exceedsDailyLimit = exceedsDailyLimit;
        }

        public boolean isExceedsDailyHours() {
            return exceedsDailyHours;
        }

        public void setExceedsDailyHours(boolean exceedsDailyHours) {
            this.exceedsDailyHours = exceedsDailyHours;
        }

        public java.util.List<String> getWarnings() {
            return warnings;
        }
    }
}