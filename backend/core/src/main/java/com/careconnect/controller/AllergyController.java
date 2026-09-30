package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.AllergyDTO;
import com.careconnect.model.User;
import com.careconnect.model.Patient;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.security.Role;
import com.careconnect.service.AllergyService;
import com.careconnect.service.CaregiverService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/v1/api/allergies")
@RequiredArgsConstructor
public class AllergyController {

    private final AllergyService allergyService;
    private final UserRepository userRepository;
    private final PatientRepository patientRepository;
    private final CaregiverService caregiverService;

    /**
     * Create a new allergy for a patient
     */
    @RequirePermission(Permission.RECORD_HEALTH_DATA)

    @PostMapping
    public ResponseEntity<?> createAllergy(@RequestBody AllergyDTO allergyDTO) {
        try {
            // Check authorization
            if (!hasAccessToPatient(allergyDTO.patientId())) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to manage allergies for this patient"));
            }

            AllergyDTO created = allergyService.createAllergy(allergyDTO);

            return ResponseEntity.status(HttpStatus.CREATED)
                    .body(Map.of(
                            "data", created,
                            "message", "Allergy created successfully"
                    ));

        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to create allergy"));
        }
    }

    /**
     * Update an existing allergy
     */
    @RequirePermission(Permission.RECORD_HEALTH_DATA)

    @PutMapping("/{id}")
    public ResponseEntity<?> updateAllergy(@PathVariable Long id, @RequestBody AllergyDTO allergyDTO) {
        try {
            // Get existing allergy to check patient access
            Optional<AllergyDTO> existingOpt = allergyService.getAllergy(id);
            if (existingOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Allergy not found"));
            }

            // Check authorization
            if (!hasAccessToPatient(existingOpt.get().patientId())) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to manage allergies for this patient"));
            }

            AllergyDTO updated = allergyService.updateAllergy(id, allergyDTO);

            return ResponseEntity.ok(Map.of(
                    "data", updated,
                    "message", "Allergy updated successfully"
            ));

        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to update allergy"));
        }
    }

    /**
     * Get all allergies for a patient
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)

    @GetMapping("/patient/{patientId}")
    public ResponseEntity<?> getAllergiesForPatient(@PathVariable Long patientId) {
        try {
            // Check authorization
            if (!hasAccessToPatient(patientId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to view allergies for this patient"));
            }

            List<AllergyDTO> allergies = allergyService.getAllergiesForPatient(patientId);

            return ResponseEntity.ok(Map.of(
                    "data", allergies,
                    "message", "Allergies retrieved successfully"
            ));

        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to retrieve allergies"));
        }
    }

    /**
     * Get active allergies for a patient
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)

    @GetMapping("/patient/{patientId}/active")
    public ResponseEntity<?> getActiveAllergiesForPatient(@PathVariable Long patientId) {
        try {
            // Check authorization
            if (!hasAccessToPatient(patientId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to view allergies for this patient"));
            }

            List<AllergyDTO> allergies = allergyService.getActiveAllergiesForPatient(patientId);

            return ResponseEntity.ok(Map.of(
                    "data", allergies,
                    "message", "Active allergies retrieved successfully"
            ));

        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to retrieve active allergies"));
        }
    }

    /**
     * Deactivate an allergy (soft delete)
     */
    @RequirePermission(Permission.RECORD_HEALTH_DATA)

    @PatchMapping("/{id}/deactivate")
    public ResponseEntity<?> deactivateAllergy(@PathVariable Long id) {
        try {
            // Get existing allergy to check patient access
            Optional<AllergyDTO> existingOpt = allergyService.getAllergy(id);
            if (existingOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Allergy not found"));
            }

            // Check authorization
            if (!hasAccessToPatient(existingOpt.get().patientId())) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to manage allergies for this patient"));
            }

            allergyService.deactivateAllergy(id);

            return ResponseEntity.ok(Map.of(
                    "message", "Allergy deactivated successfully"
            ));

        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to deactivate allergy"));
        }
    }

    /**
     * Permanently delete an allergy
     */
    @RequirePermission(Permission.RECORD_HEALTH_DATA)

    @DeleteMapping("/{id}")
    public ResponseEntity<?> deleteAllergy(@PathVariable Long id) {
        try {
            // Get existing allergy to check patient access
            Optional<AllergyDTO> existingOpt = allergyService.getAllergy(id);
            if (existingOpt.isEmpty()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "Allergy not found"));
            }

            // Check authorization
            if (!hasAccessToPatient(existingOpt.get().patientId())) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                        .body(Map.of("error", "Not authorized to manage allergies for this patient"));
            }

            allergyService.deleteAllergy(id);

            return ResponseEntity.ok(Map.of(
                    "message", "Allergy deleted successfully"
            ));

        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to delete allergy"));
        }
    }

    /**
     * Check if current user has access to manage allergies for the given patient
     */
    private boolean hasAccessToPatient(Long patientId) {
        try {
            Authentication auth = SecurityContextHolder.getContext().getAuthentication();
            String userEmail = auth.getName();

            User currentUser = userRepository.findByEmail(userEmail)
                    .orElseThrow(() -> new IllegalStateException("User not found"));

            Optional<Patient> patientOpt = patientRepository.findById(patientId);
            if (patientOpt.isEmpty()) {
                return false;
            }

            Patient patient = patientOpt.get();
            User patientUser = patient.getUser();

            // Check access based on role
            if (currentUser.getRole() == Role.PATIENT) {
                // Patient can only manage their own allergies
                return currentUser.getId().equals(patientUser.getId());
            } else if (currentUser.getRole() == Role.CAREGIVER) {
                // Check if user is a caregiver for this patient
                return caregiverService.hasAccessToPatient(currentUser.getId(), patientId);
            } else if (currentUser.getRole() == Role.FAMILY_MEMBER) {
                // Check if user is a family member for this patient
                return caregiverService.hasAccessToPatient(currentUser.getId(), patientId);
            } else if (currentUser.getRole() == Role.ADMIN) {
                // Admins can manage allergies for any patient
                return true;
            }

            return false;
        } catch (Exception e) {
            return false;
        }
    }
}
