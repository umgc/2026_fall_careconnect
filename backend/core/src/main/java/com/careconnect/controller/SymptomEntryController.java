package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.SymptomEntryDTO;
import com.careconnect.service.SymptomEntryService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.util.SecurityUtil;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/v1/api/symptoms-entry")
@RequiredArgsConstructor
public class SymptomEntryController {

    private final SymptomEntryService symptomEntryService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    /**
     * Create a new symptom entry
     */
    @RequirePermission(Permission.RECORD_HEALTH_DATA)

    @PostMapping
    public ResponseEntity<?> createSymptom(@RequestBody SymptomEntryDTO dto) {
        try {
            SymptomEntryDTO created = symptomEntryService.createSymptom(dto);
            return ResponseEntity.status(HttpStatus.CREATED)
                    .body(Map.of("data", created, "message", "Symptom created successfully"));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to create symptom"));
        }
    }

    /**
     * Get all symptoms for a patient
     */
    @RequirePermission(Permission.VIEW_HEALTH_DATA)

    @GetMapping("/patient/{patientId}")
    public ResponseEntity<?> getSymptoms(@PathVariable Long patientId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePatientAccess(currentUser, patientId);
        try {
            List<SymptomEntryDTO> list = symptomEntryService.getSymptomsForPatient(patientId);
            return ResponseEntity.ok(Map.of("data", list, "message", "Symptoms retrieved successfully"));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to fetch symptoms"));
        }
    }

    /**
     * Delete a symptom by ID
     */
    @RequirePermission(Permission.RECORD_HEALTH_DATA)

    @DeleteMapping("/{id}")
    public ResponseEntity<?> deleteSymptom(@PathVariable Long id) {
        try {
            symptomEntryService.deleteSymptom(id);
            return ResponseEntity.ok(Map.of("message", "Symptom deleted successfully"));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to delete symptom"));
        }
    }
}
