package com.careconnect.controller;

import com.careconnect.model.Patient;
import com.careconnect.repository.PatientRepository;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.Role;
import com.careconnect.dto.evv.*;
import com.careconnect.model.User;
import com.careconnect.model.evv.EvvRecord;
import com.careconnect.model.evv.EvvCorrection;
import com.careconnect.model.evv.EvvOfflineQueue;
import com.careconnect.repository.evv.EvvRecordRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.evv.EvvService;
import com.careconnect.service.evv.EvvSubmissionService;
import com.careconnect.service.evv.HhaExchangeBatchSubmissionService;
import com.careconnect.service.evv.EvvOfflineSyncService;
import com.careconnect.util.SecurityUtil;
import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/v1/api/evv") @RequiredArgsConstructor
public class EvvController {
    private final EvvService evvService;
    private final EvvSubmissionService submitter;
    private final HhaExchangeBatchSubmissionService hhaExchangeSubmitter;
    private final EvvOfflineSyncService offlineSyncService;
    private final EvvRecordRepository evvRecordRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final PatientRepository patientRepository;

    private static final Long DEFAULT_USER_ID = 1L;

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/records")
    public ResponseEntity<EvvRecord> create(@Valid @RequestBody EvvRecordRequestDto req) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        return ResponseEntity.ok(evvService.createRecord(req, DEFAULT_USER_ID));
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/records/{id}/review")
    public ResponseEntity<EvvRecord> review(@PathVariable Long id, @RequestBody EvvReviewRequest action) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        var rec = evvService.review(id, action.isApprove(), DEFAULT_USER_ID, action.getComment());
        if (action.isApprove()) submitter.queueForSubmission(rec, DEFAULT_USER_ID);
        return ResponseEntity.ok(rec);
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/records/offline")
    public ResponseEntity<EvvRecord> createOfflineRecord(@Valid @RequestBody EvvRecordRequestDto req,
                                                         @RequestHeader("X-Device-ID") String deviceId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        return ResponseEntity.ok(evvService.createOfflineRecord(req, DEFAULT_USER_ID, deviceId));
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/records/correct")
    public ResponseEntity<EvvRecord> correctRecord(@Valid @RequestBody EvvCorrectionRequestDto req) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        return ResponseEntity.ok(evvService.correctRecord(req, DEFAULT_USER_ID));
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/records/eor-approve")
    public ResponseEntity<EvvRecord> approveEor(@RequestBody EorApprovalRequestDto req) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        return ResponseEntity.ok(evvService.approveEor(req, DEFAULT_USER_ID));
    }

    @RequirePermission(Permission.VIEW_TASKS)


    @GetMapping("/records/search")
    public ResponseEntity<Page<EvvRecord>> searchRecords(EvvSearchRequestDto searchRequest) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        if (currentUser.isPatient()) {
            Patient patient = patientRepository.findByUser(currentUser)
                .orElseThrow(() -> new UnauthorizedException("Patient record not found"));
            searchRequest.setPatientId(patient.getId());
        } else {
            authorizationService.requireAdminOrCaregiver(currentUser);
        }
        return ResponseEntity.ok(evvService.searchRecords(searchRequest));
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)


    @GetMapping("/records/pending-eor-approvals")
    public ResponseEntity<List<EvvRecord>> getPendingEorApprovals() throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        return ResponseEntity.ok(evvService.getPendingEorApprovals());
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)


    @GetMapping("/corrections/pending")
    public ResponseEntity<List<EvvCorrection>> getPendingCorrections() throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        return ResponseEntity.ok(evvService.getPendingCorrections());
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/corrections/{id}/approve")
    public ResponseEntity<EvvCorrection> approveCorrection(@PathVariable Long id,
                                                           @RequestParam(required = false) String comment) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        return ResponseEntity.ok(evvService.approveCorrection(id, DEFAULT_USER_ID, comment));
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)


    @GetMapping("/offline/queue")
    public ResponseEntity<List<EvvOfflineQueue>> getOfflineQueue() throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        return ResponseEntity.ok(evvService.getOfflineQueue(DEFAULT_USER_ID));
    }

    @RequirePermission(Permission.CREATE_TASKS)


    @PostMapping("/offline/sync")
    public ResponseEntity<String> syncOfflineData() throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        offlineSyncService.syncCaregiverOfflineData(DEFAULT_USER_ID);
        return ResponseEntity.ok("Offline data sync initiated");
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)


    @GetMapping("/offline/status")
    public ResponseEntity<List<EvvOfflineQueue>> getOfflineStatus() throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        return ResponseEntity.ok(offlineSyncService.getOfflineQueueStatus(DEFAULT_USER_ID));
    }

    /**
     * Returns approved EVV records eligible for manual HHAExchange submission.
     * Caregivers see only their own records; admins/supervisors see all approved records.
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/records/hhaexchange-eligible")
    public ResponseEntity<List<EvvRecord>> getHhaExchangeEligibleRecords() throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        // Only VA-state APPROVED records are eligible for HHAExchange submission.
        return ResponseEntity.ok(evvRecordRepository.findByStatusAndStateCode("APPROVED", "VA"));
    }

    /**
     * Returns the HHAExchange JSON payload for the supplied record IDs without submitting.
     * Used by the UI to download the payload for audit / debugging purposes.
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @PostMapping("/records/hhaexchange-payload")
    public ResponseEntity<?> getHhaExchangePayload(
            @RequestBody List<Long> recordIds) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        try {
            Object payload = hhaExchangeSubmitter.buildPayload(recordIds);
            return ResponseEntity.ok(payload);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "Failed to build payload: " + e.getMessage()));
        }
    }

    /**
     * Returns the HHAExchange JSON payload as a downloadable string for the supplied record IDs.
     * Used by the UI to download the payload for audit / debugging purposes.
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @PostMapping("/records/hhaexchange-payload-json")
    public ResponseEntity<String> getHhaExchangePayloadJson(
            @RequestBody List<Long> recordIds) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        try {
            String jsonPayload = hhaExchangeSubmitter.getPayloadJson(recordIds);
            return ResponseEntity.ok()
                    .header(HttpHeaders.CONTENT_DISPOSITION,
                            "attachment; filename=\"hhaexchange-payload.json\"")
                    .header(HttpHeaders.CONTENT_TYPE, "application/json")
                    .body(jsonPayload);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    /**
     * Triggers manual HHAExchange submission for the supplied record IDs.
     * Only VA-state APPROVED records are actually forwarded to the aggregator;
     * others are silently excluded (see {@link HhaExchangeBatchSubmissionService#submitBatch}).
     */
    @RequirePermission(Permission.CREATE_TASKS)
    @PostMapping("/records/submit-to-hhaexchange")
    public ResponseEntity<Map<String, Object>> submitToHhaExchange(
            @RequestBody List<Long> recordIds) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        try {
            hhaExchangeSubmitter.submitBatch(recordIds, currentUser.getId());
            return ResponseEntity.ok(Map.of("success", true, "submitted", recordIds.size()));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest()
                    .body(Map.of("success", false, "error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.internalServerError()
                    .body(Map.of("success", false, "error", e.getMessage()));
        }
    }
}