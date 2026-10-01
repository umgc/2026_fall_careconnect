package com.careconnect.service.schedule;

import com.careconnect.dto.schedule.ScheduledVisitRequest;
import com.careconnect.dto.schedule.ScheduledVisitResponse;
import com.careconnect.dto.schedule.ScheduledVisitSummary;
import com.careconnect.dto.schedule.ScheduledVisitAuditResponse;
import com.careconnect.dto.schedule.AuditDiffResponse;
import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.model.schedule.ScheduledVisitAudit;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import com.careconnect.repository.schedule.ScheduledVisitAuditRepository;
import com.careconnect.service.VisitSummaryService;
import com.careconnect.service.schedule.ScheduleConflictService;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class ScheduledVisitService {

    private final ScheduledVisitRepository scheduledVisitRepository;
    private final ScheduledVisitAuditRepository scheduledVisitAuditRepository;
    private final PatientRepository patientRepository;
    private final ScheduleConflictService conflictService;
    private final ObjectMapper objectMapper;
    private final VisitSummaryService visitSummaryService;

    @Transactional
    public ScheduledVisitResponse createScheduledVisit(Long caregiverId, ScheduledVisitRequest request) {
        log.info("Creating scheduled visit for caregiver {} and patient {}", caregiverId, request.getPatientId());

        // 1. Check for conflicts
        ScheduleConflictService.ConflictSummary conflicts = conflictService.analyzeConflicts(
                caregiverId,
                request.getPatientId(),
                request.getScheduledDate(),
                request.getScheduledTime(),
                request.getDurationMinutes());

        // 2. Enforce conflict prevention
        // Patient conflicts: ALWAYS block (patient cannot have overlapping visits)
        if (conflicts.getPatientConflicts() != null && !conflicts.getPatientConflicts().isEmpty()) {
            log.warn("Patient conflict detected - cannot schedule visit at same time");
            throw new IllegalArgumentException(
                    "Patient already has a scheduled visit during this time. " +
                            "Overlapping visits: " + formatConflictingVisits(conflicts.getPatientConflicts())
            );
        }

        // Caregiver conflicts: WARN but allow (caregiver may get assistance)
        boolean hasCaregiverConflicts = conflicts.getCaregiverConflicts() != null &&
                !conflicts.getCaregiverConflicts().isEmpty();
        if (hasCaregiverConflicts) {
            log.warn("Caregiver conflict warning - has {} overlapping visits",
                    conflicts.getCaregiverConflicts().size());
        }

        // Daily limit: Allow with warning
        if (conflicts.isExceedsDailyLimit()) {
            log.warn("Caregiver exceeds daily visit limit for date {}", request.getScheduledDate());
        }

        // Daily hours: Allow with warning  
        if (conflicts.isExceedsDailyHours()) {
            log.warn("Caregiver exceeds daily hours limit for date {}", request.getScheduledDate());
        }

        // 3. Create the visit
        ScheduledVisit visit = new ScheduledVisit();
        visit.setCaregiverId(caregiverId);
        visit.setPatientId(request.getPatientId());
        visit.setServiceType(request.getServiceType());
        visit.setScheduledDate(request.getScheduledDate());
        visit.setScheduledTime(request.getScheduledTime());
        visit.setDurationMinutes(request.getDurationMinutes());
        visit.setPriority(request.getPriority());
        visit.setNotes(request.getNotes());
        visit.setStatus("Scheduled");

        // 4. Set conflict flags if any warnings
        if (hasCaregiverConflicts || conflicts.isExceedsDailyLimit() || conflicts.isExceedsDailyHours()) {
            visit.setConflictFlag(true);
            visit.setConflictWarning(String.join("; ", conflicts.getWarnings()));
        }

        ScheduledVisit savedVisit = scheduledVisitRepository.save(visit);
        log.info("Visit created successfully with ID {}", savedVisit.getId());

        // 5. Create audit entry
        String currentUser = getCurrentUsername();
        createAuditEntry(
                savedVisit.getId(),
                "CREATED",
                null,
                null,
                serializeVisit(savedVisit),
                currentUser);

        String patientName = getPatientName(savedVisit.getPatientId());
        return new ScheduledVisitResponse(savedVisit, patientName);
    }

    @Transactional(readOnly = true)
    public List<ScheduledVisitResponse> getScheduledVisits(Long caregiverId) {
        List<ScheduledVisit> visits = scheduledVisitRepository.findByCaregiverId(caregiverId);
        return visits.stream()
                .map(visit -> new ScheduledVisitResponse(visit, getPatientName(visit.getPatientId())))
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<ScheduledVisitResponse> getScheduledVisitsByDate(Long caregiverId, LocalDate date) {
        List<ScheduledVisit> visits = scheduledVisitRepository.findByCaregiverIdAndScheduledDate(caregiverId, date);
        return visits.stream()
                .map(visit -> new ScheduledVisitResponse(visit, getPatientName(visit.getPatientId())))
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<ScheduledVisitResponse> getScheduledVisitsBetweenDates(
            Long caregiverId,
            LocalDate startDate,
            LocalDate endDate) {
        List<ScheduledVisit> visits = scheduledVisitRepository
                .findByCaregiverIdAndScheduledDateBetween(caregiverId, startDate, endDate);
        return visits.stream()
                .map(visit -> new ScheduledVisitResponse(visit, getPatientName(visit.getPatientId())))
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<ScheduledVisitResponse> getScheduledVisitsBetweenDatesForPatient(
            Long patientId,
            LocalDate startDate,
            LocalDate endDate) {
        List<ScheduledVisit> visits = scheduledVisitRepository
                .findByPatientIdAndScheduledDateBetween(patientId, startDate, endDate);
        return visits.stream()
                .map(visit -> new ScheduledVisitResponse(visit, getPatientName(visit.getPatientId())))
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public ScheduledVisitSummary getVisitSummary(Long caregiverId) {
        LocalDate today = LocalDate.now();
        LocalTime currentTime = LocalTime.now();
        LocalTime readyThreshold = currentTime.plusMinutes(30);

        long overdue = scheduledVisitRepository.countOverdueVisits(caregiverId, today, currentTime);
        long ready = scheduledVisitRepository.countReadyVisits(caregiverId, today, readyThreshold);
        long upcoming = scheduledVisitRepository.countUpcomingVisits(caregiverId, today, readyThreshold);
        long totalToday = scheduledVisitRepository.countTodayVisits(caregiverId, today);

        return new ScheduledVisitSummary(overdue, ready, upcoming, totalToday);
    }

    @Transactional(readOnly = true)
    public List<ScheduledVisitResponse> getOverdueVisits(Long caregiverId) {
        LocalDate today = LocalDate.now();
        LocalTime currentTime = LocalTime.now();

        List<ScheduledVisit> visits = scheduledVisitRepository
                .findOverdueVisits(caregiverId, today, currentTime);

        return visits.stream()
                .map(visit -> new ScheduledVisitResponse(visit, getPatientName(visit.getPatientId())))
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<ScheduledVisitResponse> getReadyVisits(Long caregiverId) {
        LocalDate today = LocalDate.now();
        LocalTime currentTime = LocalTime.now();
        LocalTime readyThreshold = currentTime.plusMinutes(30);

        List<ScheduledVisit> visits = scheduledVisitRepository
                .findReadyVisits(caregiverId, today, readyThreshold);

        return visits.stream()
                .map(visit -> new ScheduledVisitResponse(visit, getPatientName(visit.getPatientId())))
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<ScheduledVisitResponse> getUpcomingVisits(Long caregiverId) {
        LocalDate today = LocalDate.now();
        LocalTime currentTime = LocalTime.now();
        LocalTime readyThreshold = currentTime.plusMinutes(30);

        List<ScheduledVisit> visits = scheduledVisitRepository
                .findUpcomingVisits(caregiverId, today, readyThreshold);

        return visits.stream()
                .map(visit -> new ScheduledVisitResponse(visit, getPatientName(visit.getPatientId())))
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public ScheduledVisitResponse getScheduledVisit(Long visitId) {
        ScheduledVisit visit = scheduledVisitRepository.findById(visitId)
                .orElseThrow(() -> new RuntimeException("Scheduled visit not found with id: " + visitId));

        String patientName = getPatientName(visit.getPatientId());
        return new ScheduledVisitResponse(visit, patientName);
    }

    @Transactional
    public ScheduledVisitResponse updateScheduledVisit(Long visitId, ScheduledVisitRequest request) {
        log.info("Updating scheduled visit {}", visitId);

        ScheduledVisit existingVisit = scheduledVisitRepository.findById(visitId)
                .orElseThrow(() -> new RuntimeException("Scheduled visit not found with id: " + visitId));

        // Store old values for audit trail
        Long oldPatientId = existingVisit.getPatientId();
        String oldServiceType = existingVisit.getServiceType();
        LocalDate oldScheduledDate = existingVisit.getScheduledDate();
        LocalTime oldScheduledTime = existingVisit.getScheduledTime();
        Integer oldDurationMinutes = existingVisit.getDurationMinutes();
        String oldPriority = existingVisit.getPriority();
        String oldNotes = existingVisit.getNotes();
        String oldStatus = existingVisit.getStatus();

        String currentUser = getCurrentUsername();

        // 1. Check for conflicts with new schedule
        ScheduleConflictService.ConflictSummary conflicts = conflictService.analyzeConflicts(
                existingVisit.getCaregiverId(),
                request.getPatientId(),
                request.getScheduledDate(),
                request.getScheduledTime(),
                request.getDurationMinutes());

        if (conflicts.hasConflicts()) {
            log.warn("Conflicts detected for updated visit: {}", conflicts.getWarnings());
        }

        // 2. Update the visit
        existingVisit.setPatientId(request.getPatientId());
        existingVisit.setServiceType(request.getServiceType());
        existingVisit.setScheduledDate(request.getScheduledDate());
        existingVisit.setScheduledTime(request.getScheduledTime());
        existingVisit.setDurationMinutes(request.getDurationMinutes());
        existingVisit.setPriority(request.getPriority());
        existingVisit.setNotes(request.getNotes());

        // 3. Set conflict flags
        if (conflicts.hasConflicts()) {
            existingVisit.setConflictFlag(true);
            existingVisit.setConflictWarning(String.join("; ", conflicts.getWarnings()));
        } else {
            existingVisit.setConflictFlag(false);
            existingVisit.setConflictWarning(null);
        }

        ScheduledVisit updatedVisit = scheduledVisitRepository.save(existingVisit);
        log.info("Visit {} updated successfully", visitId);

        // 4. Create audit entries for changed fields
        if (!oldPatientId.equals(request.getPatientId())) {
            createAuditEntry(visitId, "UPDATED", "patientId",
                    String.valueOf(oldPatientId), String.valueOf(request.getPatientId()), currentUser);
        }

        if (!oldServiceType.equals(request.getServiceType())) {
            createAuditEntry(visitId, "UPDATED", "serviceType",
                    oldServiceType, request.getServiceType(), currentUser);
        }

        if (!oldScheduledDate.equals(request.getScheduledDate())) {
            createAuditEntry(visitId, "UPDATED", "scheduledDate",
                    oldScheduledDate.toString(), request.getScheduledDate().toString(), currentUser);
        }

        if (!oldScheduledTime.equals(request.getScheduledTime())) {
            createAuditEntry(visitId, "UPDATED", "scheduledTime",
                    oldScheduledTime.toString(), request.getScheduledTime().toString(), currentUser);
        }

        if (!oldDurationMinutes.equals(request.getDurationMinutes())) {
            createAuditEntry(visitId, "UPDATED", "durationMinutes",
                    String.valueOf(oldDurationMinutes), String.valueOf(request.getDurationMinutes()), currentUser);
        }

        if (!oldPriority.equals(request.getPriority())) {
            createAuditEntry(visitId, "UPDATED", "priority",
                    oldPriority, request.getPriority(), currentUser);
        }

        if ((oldNotes == null && request.getNotes() != null) ||
                (oldNotes != null && !oldNotes.equals(request.getNotes()))) {
            createAuditEntry(visitId, "UPDATED", "notes",
                    oldNotes != null ? oldNotes : "", request.getNotes() != null ? request.getNotes() : "",
                    currentUser);
        }

        String patientName = getPatientName(updatedVisit.getPatientId());
        return new ScheduledVisitResponse(updatedVisit, patientName);
    }

    @Transactional
    public void cancelScheduledVisit(Long visitId) {
        ScheduledVisit visit = scheduledVisitRepository.findById(visitId)
                .orElseThrow(() -> new RuntimeException("Scheduled visit not found with id: " + visitId));

        visit.markCancelled();
        scheduledVisitRepository.save(visit);
    }

    @Transactional
    public ScheduledVisitResponse updateVisitStatus(Long visitId, String status) {
        ScheduledVisit visit = scheduledVisitRepository.findById(visitId)
                .orElseThrow(() -> new RuntimeException("Scheduled visit not found with id: " + visitId));

        visit.setStatus(status);
        ScheduledVisit updatedVisit = scheduledVisitRepository.save(visit);

        if ("Completed".equalsIgnoreCase(status)) {
            try {
                visitSummaryService.generateAndStoreSummary(
                        updatedVisit.getId(), updatedVisit.getCaregiverId());
            } catch (Exception e) {
                log.warn(
                        "Visit summary generation failed for visit {}: {}",
                        updatedVisit.getId(), e.getMessage(), e);
            }
        }

        String patientName = getPatientName(updatedVisit.getPatientId());
        return new ScheduledVisitResponse(updatedVisit, patientName);
    }

    @Transactional
    public void deleteScheduledVisit(Long visitId) {
        log.info("Deleting scheduled visit {}", visitId);

        ScheduledVisit visit = scheduledVisitRepository.findById(visitId)
                .orElseThrow(() -> new RuntimeException("Scheduled visit not found with id: " + visitId));

        // Create audit entry for deletion
        String currentUser = getCurrentUsername();
        try {
            String visitJson = serializeVisit(visit);
            createAuditEntry(
                    visitId,
                    "DELETED",
                    "full_record",
                    visitJson,
                    "",
                    currentUser);
        } catch (Exception e) {
            log.error("Error serializing visit for audit", e);
            createAuditEntry(
                    visitId,
                    "DELETED",
                    "full_record",
                    "Unable to serialize",
                    "",
                    currentUser);
        }

        // Delete the visit
        scheduledVisitRepository.deleteById(visitId);
        log.info("Visit {} deleted successfully", visitId);
    }

    @Transactional(readOnly = true)
    public AuditDiffResponse getVisitAuditDetails(Long visitId, Long auditId) {
        // Verify visit exists
        scheduledVisitRepository.findById(visitId)
                .orElseThrow(() -> new RuntimeException("Scheduled visit not found with id: " + visitId));

        ScheduledVisitAudit currentAudit = scheduledVisitAuditRepository.findById(auditId)
                .orElseThrow(() -> new RuntimeException("Audit entry not found with id: " + auditId));

        // Verify audit belongs to this visit
        if (!currentAudit.getVisitId().equals(visitId)) {
            throw new RuntimeException("Audit entry does not belong to this visit");
        }

        // Get the state before this change
        List<ScheduledVisitAudit> priorAudits = scheduledVisitAuditRepository
                .findByVisitIdAndChangedAtBeforeOrderByChangedAtDesc(visitId, currentAudit.getChangedAt());

        ScheduledVisit beforeVisit = reconstructVisitFromAuditHistory(visitId, priorAudits);
        ScheduledVisit afterVisit = reconstructVisitFromCurrentState(visitId, currentAudit);

        ScheduledVisitResponse before = beforeVisit != null
                ? new ScheduledVisitResponse(beforeVisit, getPatientName(beforeVisit.getPatientId()))
                : null;
        ScheduledVisitResponse after = afterVisit != null
                ? new ScheduledVisitResponse(afterVisit, getPatientName(afterVisit.getPatientId()))
                : null;

        AuditDiffResponse response = new AuditDiffResponse();
        response.setBefore(before);
        response.setAfter(after);
        response.setChangedField(currentAudit.getChangedField());
        response.setAction(currentAudit.getAction());
        response.setChangedBy(currentAudit.getChangedBy());
        response.setChangedAt(currentAudit.getChangedAt());

        return response;
    }

    @Transactional(readOnly = true)
    public List<ScheduledVisitAuditResponse> getVisitAuditHistory(Long visitId) {
        // Verify visit exists
        scheduledVisitRepository.findById(visitId)
                .orElseThrow(() -> new RuntimeException("Scheduled visit not found with id: " + visitId));

        List<ScheduledVisitAudit> auditEntries = scheduledVisitAuditRepository
                .findByVisitIdOrderByChangedAtDesc(visitId);

        return auditEntries.stream()
                .map(this::convertToAuditResponse)
                .collect(Collectors.toList());
    }

    /**
     * Create an audit entry for visit changes
     */
    private void createAuditEntry(Long visitId, String action, String changedField,
                                  String oldValue, String newValue, String changedBy) {
        ScheduledVisitAudit audit = new ScheduledVisitAudit();
        audit.setVisitId(visitId);
        audit.setAction(action);
        audit.setChangedField(changedField);
        audit.setOldValue(oldValue);
        audit.setNewValue(newValue);
        audit.setChangedBy(changedBy);
        audit.setChangedAt(LocalDateTime.now());

        scheduledVisitAuditRepository.save(audit);
    }

    /**
     * Convert ScheduledVisitAudit to Response DTO
     */
    private ScheduledVisitAuditResponse convertToAuditResponse(ScheduledVisitAudit audit) {
        ScheduledVisitAuditResponse response = new ScheduledVisitAuditResponse();
        response.setId(audit.getId());
        response.setVisitId(audit.getVisitId());
        response.setAction(audit.getAction());
        response.setChangedField(audit.getChangedField());
        response.setOldValue(audit.getOldValue());
        response.setNewValue(audit.getNewValue());
        response.setChangedBy(audit.getChangedBy());
        response.setChangedAt(audit.getChangedAt());
        return response;
    }

    /**
     * Get current logged-in username
     */
    private String getCurrentUsername() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        return authentication != null ? authentication.getName() : "SYSTEM";
    }

    /**
     * Reconstruct visit state from prior audit history
     */
    private ScheduledVisit reconstructVisitFromAuditHistory(Long visitId, List<ScheduledVisitAudit> priorAudits) {
        if (priorAudits.isEmpty()) {
            return null;
        }

        ScheduledVisit reconstructed = new ScheduledVisit();
        reconstructed.setId(visitId);

        // Apply all prior changes
        for (ScheduledVisitAudit audit : priorAudits) {
            applyAuditToVisit(reconstructed, audit);
        }

        return reconstructed;
    }

    /**
     * Get current state of visit with latest audit applied
     */
    private ScheduledVisit reconstructVisitFromCurrentState(Long visitId, ScheduledVisitAudit latestAudit) {
        ScheduledVisit visit = scheduledVisitRepository.findById(visitId)
                .orElseThrow(() -> new RuntimeException("Visit not found"));
        return visit;
    }

    /**
     * Apply an audit change to a reconstructed visit
     */
    private void applyAuditToVisit(ScheduledVisit visit, ScheduledVisitAudit audit) {
        switch (audit.getChangedField()) {
            case "patientId":
                visit.setPatientId(Long.parseLong(audit.getNewValue()));
                break;
            case "serviceType":
                visit.setServiceType(audit.getNewValue());
                break;
            case "scheduledDate":
                visit.setScheduledDate(LocalDate.parse(audit.getNewValue()));
                break;
            case "scheduledTime":
                visit.setScheduledTime(LocalTime.parse(audit.getNewValue()));
                break;
            case "durationMinutes":
                visit.setDurationMinutes(Integer.parseInt(audit.getNewValue()));
                break;
            case "priority":
                visit.setPriority(audit.getNewValue());
                break;
            case "notes":
                visit.setNotes(audit.getNewValue());
                break;
        }
    }

    /**
     * Analyze conflicts for a visit
     */
    public ScheduleConflictService.ConflictSummary analyzeConflicts(
            Long caregiverId,
            Long patientId,
            LocalDate date,
            LocalTime startTime,
            Integer durationMinutes) {
        return conflictService.analyzeConflicts(caregiverId, patientId, date, startTime, durationMinutes);
    }

    /**
     * Serialize visit to JSON
     */
    private String serializeVisit(ScheduledVisit visit) {
        try {
            return objectMapper.writeValueAsString(visit);
        } catch (Exception e) {
            log.warn("Failed to serialize visit", e);
            return visit.toString();
        }
    }

    /**
     * Get patient name by ID
     */
    private String getPatientName(Long patientId) {
        if (patientId == null) {
            return "Unknown";
        }
        return patientRepository.findById(patientId)
                .map(patient -> {
                    String firstName = patient.getFirstName() != null ? patient.getFirstName() : "";
                    String lastName = patient.getLastName() != null ? patient.getLastName() : "";
                    return (firstName + " " + lastName).trim();
                })
                .orElse("Unknown");
    }

    /**
     * Format conflicting visits for error message
     */
    private String formatConflictingVisits(List<ScheduledVisit> visits) {
        if (visits == null || visits.isEmpty()) {
            return "none";
        }
        return visits.stream()
                .map(v -> String.format("%s-%s (%s)",
                        v.getScheduledTime(),
                        v.getScheduledTime().plusMinutes(v.getDurationMinutes()),
                        v.getServiceType()))
                .collect(Collectors.joining(", "));
    }
}
