package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.*;
import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/v1/api/caregiver-patient-links")
public class CaregiverPatientLinkController {

    @Autowired
    private CaregiverPatientLinkService linkService;

    @Autowired
    private UserRepository userRepository;

    // Helper method to get current user
    private User getCurrentUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        String email = authentication.getName();
        // Find user by email instead of parsing name as an ID
        return userRepository.findByEmail(email)
                .orElseThrow(() -> new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated"));
    }

    // 1. Create a new caregiver-patient link
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/caregivers/{caregiverId}/patients")
    public ResponseEntity<CaregiverPatientLinkResponse> createLink(
            @PathVariable Long caregiverId,
            @RequestBody CreateLinkRequest request) {
        
        User currentUser = getCurrentUser();
        
        // Only admins and the caregiver themselves can create links
        if (currentUser.getRole() != Role.ADMIN && !currentUser.getId().equals(caregiverId)) {
            throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
        }

        CaregiverPatientLinkResponse response = linkService.createLink(caregiverId, request, currentUser.getId());
        return ResponseEntity.ok(response);
    }

    // 2. Update a link (suspend, reactivate, change type, etc.)
    @RequirePermission(Permission.UPDATE_TASKS)

    @PutMapping("/{linkId}")
    public ResponseEntity<CaregiverPatientLinkResponse> updateLink(
            @PathVariable Long linkId,
            @RequestBody UpdateLinkRequest request) {
        
        User currentUser = getCurrentUser();
        
        // Only admins can update links for now (can be enhanced with more granular permissions)
        if (currentUser.getRole() != Role.ADMIN) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only admins can update links");
        }

        CaregiverPatientLinkResponse response = linkService.updateLink(linkId, request, currentUser.getId());
        return ResponseEntity.ok(response);
    }

    // 3. Temporarily suspend a link
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/{linkId}/suspend")
    public ResponseEntity<CaregiverPatientLinkResponse> suspendLink(@PathVariable Long linkId) {
        User currentUser = getCurrentUser();
        
        // Only admins and caregivers can suspend links
        if (currentUser.getRole() != Role.ADMIN && currentUser.getRole() != Role.CAREGIVER) {
            throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
        }

        // Pass the user's email as the identifier
        CaregiverPatientLinkResponse response = linkService.suspendLink(linkId, currentUser.getEmail());
        return ResponseEntity.ok(response);
    }

    // 4. Reactivate a suspended link
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/{linkId}/reactivate")
    public ResponseEntity<CaregiverPatientLinkResponse> reactivateLink(@PathVariable Long linkId) {
        User currentUser = getCurrentUser();
        
        // Only admins and caregivers can reactivate links
        if (currentUser.getRole() != Role.ADMIN && currentUser.getRole() != Role.CAREGIVER) {
            throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
        }

        CaregiverPatientLinkResponse response = linkService.reactivateLink(linkId, currentUser.getId());
        return ResponseEntity.ok(response);
    }

    // 5. Permanently revoke a link
    @RequirePermission(Permission.DELETE_PATIENTS)

    @DeleteMapping("/{linkId}")
    public ResponseEntity<Void> revokeLink(@PathVariable Long linkId) {
        User currentUser = getCurrentUser();
        
        // Only admins can permanently revoke links
        if (currentUser.getRole() != Role.ADMIN) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only admins can permanently revoke links");
        }

        linkService.revokeLink(linkId, currentUser.getId());
        return ResponseEntity.noContent().build();
    }

    // 6. Get all patients linked to a caregiver
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/caregivers/{caregiverId}/patients")
    public ResponseEntity<List<CaregiverPatientLinkResponse>> getPatientsByCaregiver(@PathVariable Long caregiverId) {
        User currentUser = getCurrentUser();
        
        // Caregiver can see their own patients, admins can see all
        if (currentUser.getRole() != Role.ADMIN && !currentUser.getId().equals(caregiverId)) {
            throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
        }

        List<CaregiverPatientLinkResponse> links = linkService.getPatientsByCaregiver(caregiverId);
        return ResponseEntity.ok(links);
    }

    // 7. Get all caregivers linked to a patient
    @RequirePermission(Permission.VIEW_MESSAGES)
    @GetMapping("/patients/{patientId}/caregivers")
    public ResponseEntity<List<CaregiverPatientLinkResponse>> getCaregiversByPatient(@PathVariable Long patientId) {
        User currentUser = getCurrentUser();

        boolean isAdmin = currentUser.getRole() == Role.ADMIN;
        boolean isSelfPatient = currentUser.getId().equals(patientId);
        boolean isLinkedCaregiver = currentUser.getRole() == Role.CAREGIVER
                && linkService.hasAccessToPatient(currentUser.getId(), patientId);

        // Admins, the patient, or caregivers actively linked to the patient can view this list
        if (!isAdmin && !isSelfPatient && !isLinkedCaregiver) {
            throw new AppException(HttpStatus.FORBIDDEN, "Access denied");
        }

        List<CaregiverPatientLinkResponse> links = linkService.getCaregiversByPatient(patientId);
        return ResponseEntity.ok(links);
    }

    // 8. Check if caregiver has access to patient
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/caregivers/{caregiverId}/patients/{patientId}/access")
    public ResponseEntity<Boolean> hasAccessToPatient(
            @PathVariable Long caregiverId,
            @PathVariable Long patientId) {
        
        boolean hasAccess = linkService.hasAccessToPatient(caregiverId, patientId);
        return ResponseEntity.ok(hasAccess);
    }

    // 9. Get all links (admin only)
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping
    public ResponseEntity<List<CaregiverPatientLinkResponse>> getAllLinks() {
        User currentUser = getCurrentUser();
        
        if (currentUser.getRole() != Role.ADMIN) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only admins can view all links");
        }

        List<CaregiverPatientLinkResponse> links = linkService.getAllLinks();
        return ResponseEntity.ok(links);
    }

    // 10. Cleanup expired links (admin only)
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/cleanup-expired")
    public ResponseEntity<Void> cleanupExpiredLinks() {
        User currentUser = getCurrentUser();
        
        if (currentUser.getRole() != Role.ADMIN) {
            throw new AppException(HttpStatus.FORBIDDEN, "Only admins can cleanup expired links");
        }

        linkService.cleanupExpiredLinks();
        return ResponseEntity.ok().build();
    }

    // 11. Caregiver toggle: allow/disallow patient-initiated video calls for this link
    @PostMapping("/{linkId}/patient-video-calls")
    public ResponseEntity<CaregiverPatientLinkResponse> setPatientVideoCalls(
            @PathVariable Long linkId,
            @RequestBody Map<String, Object> request
    ) {
        User currentUser = getCurrentUser();
        Object enabledRaw = request.get("enabled");
        boolean enabled = enabledRaw instanceof Boolean
                ? (Boolean) enabledRaw
                : Boolean.parseBoolean(String.valueOf(enabledRaw));

        CaregiverPatientLinkResponse response = linkService.setPatientVideoCallsEnabled(
                linkId,
                enabled,
                currentUser.getId(),
                currentUser.getRole()
        );
        return ResponseEntity.ok(response);
    }

    // 12. Caregiver toggle: allow/disallow patient-initiated messaging for this link
    @PostMapping("/{linkId}/patient-messaging")
    public ResponseEntity<CaregiverPatientLinkResponse> setPatientMessaging(
            @PathVariable Long linkId,
            @RequestBody Map<String, Object> request
    ) {
        User currentUser = getCurrentUser();
        Object enabledRaw = request.get("enabled");
        boolean enabled = enabledRaw instanceof Boolean
                ? (Boolean) enabledRaw
                : Boolean.parseBoolean(String.valueOf(enabledRaw));

        CaregiverPatientLinkResponse response = linkService.setPatientMessagingEnabled(
                linkId,
                enabled,
                currentUser.getId(),
                currentUser.getRole()
        );
        return ResponseEntity.ok(response);
    }
    // 13. Grant feature access for a care circle link (WBS 3.10.1 / Ticket 505)
    @RequirePermission(Permission.UPDATE_TASKS)
    @PostMapping("/{linkId}/permissions/grant")
    public ResponseEntity<CaregiverPatientLinkResponse> grantFeatureAccess(
            @PathVariable Long linkId,
            @RequestBody Map<String, Object> request
    ) {
        User currentUser = getCurrentUser();
        String feature = (String) request.get("permission");

        if (feature == null || feature.isBlank()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Permission/feature name is required");
        }

        CaregiverPatientLinkResponse response = linkService.grantPermission(
                linkId,
                feature,
                currentUser.getId()
        );
        return ResponseEntity.ok(response);
    }

    // 14. Revoke feature access for a care circle link (WBS 3.10.1 / Ticket 505)
    @RequirePermission(Permission.UPDATE_TASKS)
    @PostMapping("/{linkId}/permissions/revoke")
    public ResponseEntity<CaregiverPatientLinkResponse> revokeFeatureAccess(
            @PathVariable Long linkId,
            @RequestBody Map<String, Object> request
    ) {
        User currentUser = getCurrentUser();
        String feature = (String) request.get("permission");

        if (feature == null || feature.isBlank()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Permission/feature name is required");
        }

        CaregiverPatientLinkResponse response = linkService.revokePermission(
                linkId,
                feature,
                currentUser.getId()
        );
        return ResponseEntity.ok(response);
    }
}
