package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.schedule.ScheduledVisitRequest;
import com.careconnect.dto.schedule.ScheduledVisitResponse;
import com.careconnect.dto.schedule.ScheduledVisitSummary;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.PatientRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.schedule.ScheduledVisitService;
import com.careconnect.util.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import jakarta.validation.Valid;

import java.time.LocalDate;
import java.util.List;

@RestController
@RequestMapping("/v1/api/scheduled-visits")
@RequiredArgsConstructor
@CrossOrigin(originPatterns = "*", allowCredentials = "true")
public class ScheduledVisitController {

    private final ScheduledVisitService scheduledVisitService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final PatientRepository patientRepository;

    /**
     * Create a new scheduled visit
     */
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/caregiver/{caregiverId}")
    public ResponseEntity<ScheduledVisitResponse> createScheduledVisit(
            @PathVariable Long caregiverId,
            @Valid @RequestBody ScheduledVisitRequest request
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        ScheduledVisitResponse response = scheduledVisitService.createScheduledVisit(caregiverId, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    /**
     * Get all scheduled visits for a caregiver
     */
    @RequirePermission(Permission.VIEW_TASKS)

    @GetMapping("/caregiver/{caregiverId}")
    public ResponseEntity<List<ScheduledVisitResponse>> getScheduledVisits(
            @PathVariable Long caregiverId
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        List<ScheduledVisitResponse> visits = scheduledVisitService.getScheduledVisits(caregiverId);
        return ResponseEntity.ok(visits);
    }

    /**
     * Get scheduled visits for a specific date
     */
    @RequirePermission(Permission.VIEW_TASKS)

    @GetMapping("/caregiver/{caregiverId}/date/{date}")
    public ResponseEntity<List<ScheduledVisitResponse>> getScheduledVisitsByDate(
            @PathVariable Long caregiverId,
            @PathVariable @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        List<ScheduledVisitResponse> visits = scheduledVisitService.getScheduledVisitsByDate(caregiverId, date);
        return ResponseEntity.ok(visits);
    }

    /**
     * Get scheduled visits between dates
     */
    @RequirePermission(Permission.VIEW_TASKS)

    @GetMapping("/caregiver/{caregiverId}/range")
    public ResponseEntity<List<ScheduledVisitResponse>> getScheduledVisitsBetweenDates(
            @PathVariable Long caregiverId,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        List<ScheduledVisitResponse> visits = scheduledVisitService
                .getScheduledVisitsBetweenDates(caregiverId, startDate, endDate);
        return ResponseEntity.ok(visits);
    }

    /**
     * Get scheduled visits between dates for a patient (patient self-service)
     */
    @RequirePermission(Permission.VIEW_TASKS)

    @GetMapping("/patient/{patientId}/range")
    public ResponseEntity<List<ScheduledVisitResponse>> getPatientVisitsBetweenDates(
            @PathVariable Long patientId,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        if (!currentUser.isAdmin()) {
            Patient patient = patientRepository.findById(patientId)
                    .orElseThrow(() -> new RuntimeException("Patient not found: " + patientId));
            if (!patient.getUser().getId().equals(currentUser.getId())) {
                throw new UnauthorizedException("You can only access your own visit schedule");
            }
        }
        List<ScheduledVisitResponse> visits = scheduledVisitService
                .getScheduledVisitsBetweenDatesForPatient(patientId, startDate, endDate);
        return ResponseEntity.ok(visits);
    }

    /**
     * Get visit summary statistics
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/caregiver/{caregiverId}/summary")
    public ResponseEntity<ScheduledVisitSummary> getVisitSummary(
            @PathVariable Long caregiverId
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        ScheduledVisitSummary summary = scheduledVisitService.getVisitSummary(caregiverId);
        return ResponseEntity.ok(summary);
    }

    /**
     * Get overdue visits
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/caregiver/{caregiverId}/overdue")
    public ResponseEntity<List<ScheduledVisitResponse>> getOverdueVisits(
            @PathVariable Long caregiverId
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        List<ScheduledVisitResponse> visits = scheduledVisitService.getOverdueVisits(caregiverId);
        return ResponseEntity.ok(visits);
    }

    /**
     * Get ready visits
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/caregiver/{caregiverId}/ready")
    public ResponseEntity<List<ScheduledVisitResponse>> getReadyVisits(
            @PathVariable Long caregiverId
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        List<ScheduledVisitResponse> visits = scheduledVisitService.getReadyVisits(caregiverId);
        return ResponseEntity.ok(visits);
    }

    /**
     * Get upcoming visits
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/caregiver/{caregiverId}/upcoming")
    public ResponseEntity<List<ScheduledVisitResponse>> getUpcomingVisits(
            @PathVariable Long caregiverId
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        List<ScheduledVisitResponse> visits = scheduledVisitService.getUpcomingVisits(caregiverId);
        return ResponseEntity.ok(visits);
    }

    /**
     * Get a specific scheduled visit
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/{visitId}")
    public ResponseEntity<ScheduledVisitResponse> getScheduledVisit(
            @PathVariable Long visitId
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        ScheduledVisitResponse visit = scheduledVisitService.getScheduledVisit(visitId);
        return ResponseEntity.ok(visit);
    }

    /**
     * Update a scheduled visit
     */
    @RequirePermission(Permission.UPDATE_TASKS)

    @PutMapping("/{visitId}")
    public ResponseEntity<ScheduledVisitResponse> updateScheduledVisit(
            @PathVariable Long visitId,
            @Valid @RequestBody ScheduledVisitRequest request
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        ScheduledVisitResponse response = scheduledVisitService.updateScheduledVisit(visitId, request);
        return ResponseEntity.ok(response);
    }

    /**
     * Cancel a scheduled visit
     */
    @RequirePermission(Permission.UPDATE_TASKS)

    @PutMapping("/{visitId}/cancel")
    public ResponseEntity<Void> cancelScheduledVisit(
            @PathVariable Long visitId
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        scheduledVisitService.cancelScheduledVisit(visitId);
        return ResponseEntity.noContent().build();
    }

    /**
     * Update visit status
     */
    @RequirePermission(Permission.UPDATE_TASKS)

    @PutMapping("/{visitId}/status")
    public ResponseEntity<ScheduledVisitResponse> updateVisitStatus(
            @PathVariable Long visitId,
            @RequestParam String status
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        ScheduledVisitResponse response = scheduledVisitService.updateVisitStatus(visitId, status);
        return ResponseEntity.ok(response);
    }

    /**
     * Delete a scheduled visit
     */
    @RequirePermission(Permission.DELETE_PATIENTS)

    @DeleteMapping("/{visitId}")
    public ResponseEntity<Void> deleteScheduledVisit(
            @PathVariable Long visitId
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        scheduledVisitService.deleteScheduledVisit(visitId);
        return ResponseEntity.noContent().build();
    }
}

