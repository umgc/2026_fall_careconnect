package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.model.Caregiver;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.CaregiverService;
import com.careconnect.dto.CaregiverRegistration;
import com.careconnect.dto.PatientRegistration;
import com.careconnect.exception.AppException;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpStatus;
import com.careconnect.dto.PatientWithLinkDto;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;


import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/v1/api/caregivers")
public class CaregiverController {

    @Autowired
    private CaregiverService caregiverService;

    @Autowired
    private CaregiverService auth; // Using caregiverService as auth for now

    @Autowired
    private CaregiverPatientLinkService caregiverPatientLinkService;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private PatientRepository patientRepository;

    @Autowired
    private CaregiverRepository caregiverRepository;

    @Autowired
    private SecurityUtil securityUtil;

    @Autowired
    private AuthorizationService authorizationService;

    // 1. List patients under a caregiver, with optional filtering
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/{caregiverId}/patients")
    public ResponseEntity<List<PatientWithLinkDto>> getPatientsByCaregiver(
            @PathVariable("caregiverId") Long caregiverId,
            @RequestParam(required = false) String email,
            @RequestParam(required = false) String name) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        List<PatientWithLinkDto> patients = caregiverService.getPatientsByCaregiver(caregiverId, email, name);
        return ResponseEntity.ok(patients);
    }

    // 2. Get caregiver details
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/{caregiverId}")
    public ResponseEntity<Caregiver> getCaregiver(@PathVariable Long caregiverId, HttpServletRequest request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        Caregiver caregiver = caregiverService.getCaregiverById(caregiverId);
        return ResponseEntity.ok(caregiver);
    }

    @RequirePermission(Permission.CREATE_PATIENTS)


    @PostMapping
    public ResponseEntity<Caregiver> registerCaregiver(@RequestBody CaregiverRegistration reg) {
        Caregiver caregiver = auth.registerCaregiver(reg);
        return ResponseEntity.status(HttpStatus.CREATED).body(caregiver);
    }

    @RequirePermission(Permission.UPDATE_PATIENTS)


    @PutMapping("/{caregiverId}")
    public ResponseEntity<Caregiver> updateCaregiver(@PathVariable Long caregiverId, @RequestBody Caregiver updatedCaregiver) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        Caregiver caregiver = caregiverService.updateCaregiver(caregiverId, updatedCaregiver);
        return ResponseEntity.ok(caregiver);
    }

    @RequirePermission(Permission.CREATE_PATIENTS)


    @PostMapping("/{caregiverId}/patients")
    public ResponseEntity<Patient> registerPatient(
            @PathVariable Long caregiverId,
            @RequestBody PatientRegistration reg) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        reg.setCaregiverId(caregiverId);
        Patient patient = auth.registerPatient(reg);
        return ResponseEntity.ok(patient);
    }

    /**
     * Add an existing patient to a caregiver's care list by email
     */
    @RequirePermission(Permission.CREATE_PATIENTS)

    @PostMapping("/{caregiverId}/patients/add")
    @Operation(summary = "Add existing patient to caregiver",
            description = "Link an existing patient to the caregiver's care list using patient's email")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Patient successfully added to caregiver"),
            @ApiResponse(responseCode = "404", description = "Patient with given email not found"),
            @ApiResponse(responseCode = "400", description = "Patient already linked to this caregiver"),
            @ApiResponse(responseCode = "202", description = "Patient not found, invitation email sent")
    })
    public ResponseEntity<?> addPatient(
            @PathVariable Long caregiverId,
            @RequestBody Map<String, String> request) throws UnauthorizedException {

        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        String patientEmail = request.get("email");

        if (patientEmail == null || patientEmail.trim().isEmpty()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Patient email is required");
        }

        // Verify caregiver exists
        Caregiver caregiver = caregiverRepository.findById(caregiverId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Caregiver not found"));

        // Look up patient by email in the User table
        User patientUser = userRepository.findByEmailAndRole(patientEmail, Role.PATIENT)
                .orElse(null);

        // If patient doesn't exist, send an invitation email
        if (patientUser == null) {
            // TODO: Send invitation email to the patient email address
            // The email should invite them to register as a patient and link with this caregiver
            return ResponseEntity.status(HttpStatus.ACCEPTED)
                    .body(Map.of(
                            "message", "Patient not found. An invitation email will be sent to " + patientEmail,
                            "action", "invitation_sent"
                    ));
        }

        // Get the Patient entity
        Patient patient = patientRepository.findByUser(patientUser)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND,
                        "Patient record not found for user"));

        // Check if link already exists
        boolean linkExists = caregiverPatientLinkService.hasActiveLink(
                caregiver.getUser().getId(),
                patientUser.getId()
        );

        if (linkExists) {
            throw new AppException(HttpStatus.BAD_REQUEST,
                    "Patient is already linked to this caregiver");
        }

        // Create the caregiver-patient link using the permanent link method
        caregiverPatientLinkService.createPermanentLink(
                caregiver.getUser().getId(),
                patientUser.getId(),
                "Patient added by caregiver"
        );

        return ResponseEntity.ok(Map.of(
                "message", "Patient successfully added to caregiver",
                "patientId", patient.getId(),
                "patientEmail", patientEmail,
                "patientName", patient.getFirstName() + " " + patient.getLastName()
        ));
    }

    /**
     * Get a specific patient under a caregiver's care
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/{caregiverId}/patients/{patientId}")
    public ResponseEntity<?> getPatientForCaregiver(
            @PathVariable Long caregiverId,
            @PathVariable Long patientId) throws UnauthorizedException {

        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);

        // Check if the caregiver has access to this patient using entity IDs
        if (!caregiverService.caregiverHasAccessToPatient(caregiverId, patientId)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body("Caregiver does not have access to this patient");
        }

        // If authorized, get the patient details with link information
        PatientWithLinkDto patientDto = caregiverService.getPatientWithLinkById(caregiverId, patientId);
        if (patientDto == null) {
            return ResponseEntity.notFound().build();
        }

        return ResponseEntity.ok(patientDto);
    }
}