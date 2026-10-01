package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.*;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FamilyMemberService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * Controller for managing temporary and permanent links between users.
 * This controller provides endpoints for creating, managing, and monitoring
 * temporary links between caregivers and patients, as well as between
 * patients and family members.
 */
@RestController
@RequestMapping("/v1/api/link-management")
public class LinkManagementController {

    @Autowired
    private CaregiverPatientLinkService caregiverPatientLinkService;

    @Autowired
    private FamilyMemberService familyMemberService;

    @Autowired
    private UserRepository userRepository;

    // Helper method to get current user
    private User getCurrentUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        Long currentUserId = Long.parseLong(authentication.getName());
        return userRepository.findById(currentUserId)
                .orElseThrow(() -> new RuntimeException("User not authenticated"));
    }

    /**
     * Create a temporary caregiver-patient link with expiration
     */
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/caregiver-patient/temporary")
    public ResponseEntity<CaregiverPatientLinkResponse> createTemporaryCaregiverPatientLink(
            @RequestBody CreateTemporaryLinkRequest request) {

        User currentUser = getCurrentUser();

        // Only caregivers and admins can create temporary links
        if (currentUser.getRole() != Role.CAREGIVER && currentUser.getRole() != Role.ADMIN) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }

        CreateLinkRequest linkRequest = new CreateLinkRequest(
                request.targetUserId(),
                "TEMPORARY",
                request.expiresAt(),
                request.notes()
        );

        CaregiverPatientLinkResponse response = caregiverPatientLinkService.createLink(
                currentUser.getId(), linkRequest, currentUser.getId());

        return ResponseEntity.ok(response);
    }

    /**
     * Create a temporary family member link with expiration
     */
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/family-member/temporary")
    public ResponseEntity<FamilyMemberLinkResponse> createTemporaryFamilyMemberLink(
            @RequestBody CreateTemporaryFamilyLinkRequest request) {

        User currentUser = getCurrentUser();

        // Only patients and caregivers can create temporary family links
        if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }

        FamilyMemberLinkResponse response = familyMemberService.createTemporaryLink(
                request.familyUserId(),
                request.patientUserId(),
                request.relationship(),
                request.expiresAt(),
                request.notes(),
                currentUser.getId()
        );

        return ResponseEntity.ok(response);
    }

    /**
     * Extend the expiration of a temporary link
     */
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/extend-expiration/{linkId}")
    public ResponseEntity<Map<String, Object>> extendLinkExpiration(
            @PathVariable Long linkId,
            @RequestBody ExtendExpirationRequest request) {

        User currentUser = getCurrentUser();

        // Only admins and caregivers can extend link expiration
        if (currentUser.getRole() != Role.ADMIN && currentUser.getRole() != Role.CAREGIVER) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }

        try {
            // For caregiver-patient links
            if (request.linkType().equalsIgnoreCase("CAREGIVER_PATIENT")) {
                UpdateLinkRequest updateRequest = new UpdateLinkRequest(
                        null, null, request.newExpiresAt(), null);
                CaregiverPatientLinkResponse response = caregiverPatientLinkService.updateLink(
                        linkId, updateRequest, currentUser.getId());
                return ResponseEntity.ok(Map.of("success", true, "link", response));
            }
            // For family member links
            else if (request.linkType().equalsIgnoreCase("FAMILY_MEMBER")) {
                UpdateLinkRequest updateRequest = new UpdateLinkRequest(
                        null, null, request.newExpiresAt(), null);
                FamilyMemberLinkResponse response = familyMemberService.updateFamilyMemberLink(
                        linkId, updateRequest, currentUser.getId());
                return ResponseEntity.ok(Map.of("success", true, "link", response));
            } else {
                return ResponseEntity.badRequest().body(Map.of("error", "Invalid link type"));
            }
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get all temporary links that are about to expire (within next 24 hours)
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/expiring-soon")
    public ResponseEntity<Map<String, Object>> getExpiringSoonLinks() {
        User currentUser = getCurrentUser();

        // Only admins and caregivers can view expiring links
        if (currentUser.getRole() != Role.ADMIN && currentUser.getRole() != Role.CAREGIVER) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }

        LocalDateTime tomorrow = LocalDateTime.now().plusDays(1);

        // Get caregiver-patient links for current user or all if admin
        List<CaregiverPatientLinkResponse> caregiverPatientLinks;
        if (currentUser.getRole() == Role.ADMIN) {
            caregiverPatientLinks = caregiverPatientLinkService.getAllLinks().stream()
                    .filter(link -> link.expiresAt() != null &&
                            link.expiresAt().isBefore(tomorrow) &&
                            link.status().equals("ACTIVE"))
                    .toList();
        } else {
            caregiverPatientLinks = caregiverPatientLinkService.getPatientsByCaregiver(currentUser.getId())
                    .stream()
                    .filter(link -> link.expiresAt() != null &&
                            link.expiresAt().isBefore(tomorrow) &&
                            link.status().equals("ACTIVE"))
                    .toList();
        }

        return ResponseEntity.ok(Map.of(
                "caregiverPatientLinks", caregiverPatientLinks,
                "totalExpiring", caregiverPatientLinks.size()
        ));
    }

    /**
     * Bulk cleanup of expired links
     */
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping("/cleanup-expired")
    public ResponseEntity<Map<String, Object>> cleanupExpiredLinks() {
        User currentUser = getCurrentUser();

        // Only admins can perform bulk cleanup
        if (currentUser.getRole() != Role.ADMIN) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }

        try {
            caregiverPatientLinkService.cleanupExpiredLinks();
            familyMemberService.cleanupExpiredFamilyMemberLinks();

            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "Expired links cleaned up successfully"
            ));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Get summary of all links for a user
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/summary")
    public ResponseEntity<Map<String, Object>> getLinkSummary() {
        User currentUser = getCurrentUser();

        Map<String, Object> summary = Map.of(
                "userId", currentUser.getId(),
                "userRole", currentUser.getRole().name(),
                "caregiverPatientLinks", getCaregiverPatientLinksForUser(currentUser),
                "familyMemberLinks", getFamilyMemberLinksForUser(currentUser)
        );

        return ResponseEntity.ok(summary);
    }

    private List<CaregiverPatientLinkResponse> getCaregiverPatientLinksForUser(User user) {
        switch (user.getRole()) {
            case CAREGIVER:
                return caregiverPatientLinkService.getPatientsByCaregiver(user.getId());
            case PATIENT:
                return caregiverPatientLinkService.getCaregiversByPatient(user.getId());
            case ADMIN:
                return caregiverPatientLinkService.getAllLinks();
            default:
                return List.of();
        }
    }

    private List<FamilyMemberLinkResponse> getFamilyMemberLinksForUser(User user) {
        switch (user.getRole()) {
            case PATIENT:
                return familyMemberService.getFamilyMembersByPatient(user.getId());
            case FAMILY_MEMBER:
                return familyMemberService.getPatientsByFamilyMember(user.getId());
            case ADMIN:
                // Admin would need a method to get all family member links
                // This could be added to FamilyMemberService if needed
                return List.of();
            default:
                return List.of();
        }
    }

    // DTOs for the new endpoints
    public record CreateTemporaryLinkRequest(
            Long targetUserId,
            LocalDateTime expiresAt,
            String notes
    ) {
    }

    public record CreateTemporaryFamilyLinkRequest(
            Long familyUserId,
            Long patientUserId,
            String relationship,
            LocalDateTime expiresAt,
            String notes
    ) {
    }

    public record ExtendExpirationRequest(
            String linkType, // "CAREGIVER_PATIENT" or "FAMILY_MEMBER"
            LocalDateTime newExpiresAt
    ) {
    }
}
