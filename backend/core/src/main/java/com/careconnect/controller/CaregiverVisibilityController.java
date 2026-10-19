package com.careconnect.controller;

import com.careconnect.dto.visibility.VisibilityDtos.VisibilityRequest;
import com.careconnect.dto.visibility.VisibilityDtos.VisibilityResponse;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.visibility.CaregiverVisibilityService;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * WBS 3.15.5: caregiver summary visibility is default-deny
 * Access status is default-deny unless explicitly GRANTed
 */
@RestController
@RequestMapping("/v1/api/caregiver-visibility")
@RequiredArgsConstructor
@Tag(name = "Caregiver Visibility",
        description = "Default-deny caregiver access to patient summaries, with review gate and grant/revoke")
public class CaregiverVisibilityController {

    private final CaregiverVisibilityService visibilityService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    /**
     * Status is visible to the caregiver in question, the patient (consent owner), or an admin.
     */
    private void requireStatusViewer(User user, Long caregiverUserId, Long patientUserId)
            throws UnauthorizedException {
        if (user != null && (user.isAdmin()
                || user.getId().equals(caregiverUserId)
                || user.getId().equals(patientUserId))) {
            return;
        }
        throw new UnauthorizedException("Not authorized to view this visibility status");
    }

    @RequirePermission(Permission.USE_AI_FEATURES)
    @GetMapping("/status")
    @Operation(summary = "Get caregiver visibility status for a patient (default-deny)")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Status retrieved"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<VisibilityResponse> getStatus(
            @RequestParam Long caregiverUserId,
            @RequestParam Long patientUserId) throws UnauthorizedException {
        requireStatusViewer(securityUtil.resolveCurrentUser(), caregiverUserId, patientUserId);
        return ResponseEntity.ok(visibilityService.getStatus(caregiverUserId, patientUserId));
    }

    @RequirePermission(Permission.USE_AI_FEATURES)
    @PostMapping("/review")
    @Operation(summary = "Submit a caregiver for the pre-share review gate",
            description = "Records the request as PENDING_REVIEW and queues a confirmation item for a reviewer")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Submitted for review"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<VisibilityResponse> submitForReview(
            @Valid @RequestBody VisibilityRequest request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireSelfOrAdmin(currentUser, request.getCaregiverUserId());
        return ResponseEntity.ok(visibilityService.submitForReview(
                request.getCaregiverUserId(), request.getPatientUserId(), currentUser.getId()));
    }

    @RequirePermission(Permission.USE_AI_FEATURES)
    @PostMapping("/grant")
    @Operation(summary = "Grant caregiver access to a patient's summaries (approves the review gate)")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Access granted"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<VisibilityResponse> grant(
            @Valid @RequestBody VisibilityRequest request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireSelfOrAdmin(currentUser, request.getPatientUserId());
        return ResponseEntity.ok(visibilityService.grant(
                request.getCaregiverUserId(), request.getPatientUserId(), currentUser.getId()));
    }

    @RequirePermission(Permission.USE_AI_FEATURES)
    @PostMapping("/revoke")
    @Operation(summary = "Revoke caregiver access to a patient's summaries")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Access revoked"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<VisibilityResponse> revoke(
            @Valid @RequestBody VisibilityRequest request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireSelfOrAdmin(currentUser, request.getPatientUserId());
        return ResponseEntity.ok(visibilityService.revoke(
                request.getCaregiverUserId(), request.getPatientUserId(), currentUser.getId()));
    }
}
