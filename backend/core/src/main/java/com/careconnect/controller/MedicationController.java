package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.MedicationDTO;
import com.careconnect.dto.MedicationPhotoExtractionResponse;
import com.careconnect.service.MedicationPhotoExtractionService;
import com.careconnect.service.MedicationService;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.util.SecurityUtil;

import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.Set;

@RestController
@RequestMapping("/v3/api/patients")
@Tag(name = "Medication Management", description = "Endpoints for managing patient medications")
public class MedicationController {

    private static final Set<String> MEDICATION_PHOTO_TYPES = Set.of(MediaType.IMAGE_JPEG_VALUE, MediaType.IMAGE_PNG_VALUE);
    private static final long MEDICATION_PHOTO_MAX_BYTES = 10L * 1024 * 1024;

    @Autowired
    private MedicationService medicationService;

    @Autowired
    private MedicationPhotoExtractionService medicationPhotoExtractionService;

    @Autowired
    private SecurityUtil securityUtil;

    @Autowired
    private AuthorizationService authorizationService;

    // ================================================================
    // 1. Fetch all medications for a patient
    // ================================================================
    @GetMapping("/{patientId}/medications")
    public ResponseEntity<List<MedicationDTO>> getAllMedications(@PathVariable Long patientId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        List<MedicationDTO> allMeds = medicationService.getAllMedicationsForPatient(patientId);
        return ResponseEntity.ok(allMeds);
    }

    // ================================================================
    // 1.1 Fetch only active medications
    // ================================================================
    @GetMapping("/{patientId}/medications/active")
    public ResponseEntity<List<MedicationDTO>> getActiveMedications(@PathVariable Long patientId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        List<MedicationDTO> activeMeds = medicationService.getActiveMedicationsForPatient(patientId);
        return ResponseEntity.ok(activeMeds);
    }

    // ================================================================
    // 1.2 Fetch pending medications (approval_status = 'PENDING')
    // ================================================================
    @GetMapping("/{patientId}/medications/pending")
    public ResponseEntity<List<MedicationDTO>> getPendingMedications(@PathVariable Long patientId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        List<MedicationDTO> pending = medicationService.getPendingMedications(patientId);
        return ResponseEntity.ok(pending);
    }

    // ================================================================
    // 2. Add a new medication (creates record as PENDING)
    // ================================================================
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/{patientId}/medications")
    public ResponseEntity<MedicationDTO> addMedication(
            @PathVariable Long patientId,
            @RequestBody MedicationDTO newMedication) throws UnauthorizedException {

        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        MedicationDTO createdMedication = medicationService.addMedication(patientId, newMedication);
        return ResponseEntity.ok(createdMedication);
    }

    // ================================================================
    // 2.1 Extract draft medication fields from a label photo (F-01).
    //     The image is processed in memory only and never stored.
    // ================================================================
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping(value = "/{patientId}/medications/extract-photo", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> extractMedicationPhoto(
            @PathVariable Long patientId,
            @RequestParam("image") MultipartFile image) throws UnauthorizedException {

        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        if (image == null || image.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "message", "Please provide a photo of the medication label."
            ));
        }
        if (image.getSize() > MEDICATION_PHOTO_MAX_BYTES) {
            return ResponseEntity.badRequest().body(Map.of(
                    "message", "The photo is too large. Please use a photo under 10 MB."
            ));
        }
        String contentType = image.getContentType();
        if (contentType == null || !MEDICATION_PHOTO_TYPES.contains(contentType)) {
            return ResponseEntity.badRequest().body(Map.of(
                    "message", "Please use a JPEG or PNG photo."
            ));
        }
        byte[] imageBytes;
        try {
            imageBytes = image.getBytes();
        } catch (IOException e) {
            return ResponseEntity.badRequest().body(Map.of(
                    "message", "The photo could not be read. Please enter the medication manually."
            ));
        }
        MedicationPhotoExtractionResponse extraction = medicationPhotoExtractionService.extract(imageBytes);
        return ResponseEntity.ok(extraction);
    }

    // ================================================================
    // 3. Approve a medication (sets isActive=true, approval_status='APPROVED')
    // ================================================================
    @RequirePermission(Permission.UPDATE_TASKS)

    @PutMapping("/{patientId}/medications/{medicationId}/approve")
    public ResponseEntity<?> approveMedication(
            @PathVariable Long patientId,
            @PathVariable Long medicationId) throws UnauthorizedException {

        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        MedicationDTO approvedMedication = medicationService.approveMedication(patientId, medicationId);
        return ResponseEntity.ok(Map.of(
                "message", "Medication approved successfully",
                "approvedMedication", approvedMedication
        ));
    }

    // ================================================================
    // 4. Remove (soft delete) medication and trigger notification (Patient-side)
    // ================================================================
    @RequirePermission(Permission.DELETE_PATIENTS)

    @DeleteMapping("/{patientId}/medications/{medicationId}")
    public ResponseEntity<?> deleteMedication(
            @PathVariable Long patientId,
            @PathVariable Long medicationId) throws UnauthorizedException {

        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        medicationService.deactivateMedication(patientId, medicationId);
        return ResponseEntity.ok(Map.of(
                "message", "Medication removed and notification sent"
        ));
    }

    // ================================================================
    // 5. Hard delete medication (Caregiver-side)
    // ================================================================
    @RequirePermission(Permission.DELETE_PATIENTS)

    @DeleteMapping("/{patientId}/medications/{medicationId}/caregiver/{caregiverId}")
    public ResponseEntity<?> deleteMedicationByCaregiver(
            @PathVariable Long patientId,
            @PathVariable Long medicationId,
            @PathVariable Long caregiverId) throws UnauthorizedException {

        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        medicationService.hardDeleteMedication(patientId, medicationId, caregiverId);
        return ResponseEntity.ok(Map.of(
                "message", "Medication deleted successfully"
        ));
    }
}
