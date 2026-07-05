package com.careconnect.controller;

import com.careconnect.dto.AcceptInviteResponse;
import com.careconnect.dto.CreateInviteRequest;
import com.careconnect.dto.CreateInviteResponse;
import com.careconnect.dto.InvitePreviewResponse;
import com.careconnect.dto.RevokeInviteRequest;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.Role;
import com.careconnect.service.InviteTokenService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

/**
 * Endpoints for the care-circle invite-token lifecycle (issue #53).
 *
 * Routes:
 *   POST   /v1/api/care-circle/{linkId}/invite              create  (permission-gated)
 *   GET    /v1/api/invite/{token}                           preview (public)
 *   POST   /v1/api/invite/{token}/accept                    accept  (authenticated)
 *   DELETE /v1/api/care-circle/{linkId}/invite/{tokenId}    revoke  (permission-gated)
 *
 * Kept as a dedicated controller (rather than folded into LinkManagementController)
 * so the public preview path stays clean and is easy to permit in SecurityConfig.
 */
@RestController
@RequestMapping("/v1/api")
public class InviteController {

    @Autowired
    private InviteTokenService inviteTokenService;

    @Autowired
    private UserRepository userRepository;

    private User getCurrentUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        Long currentUserId = Long.parseLong(authentication.getName());
        return userRepository.findById(currentUserId)
                .orElseThrow(() -> new RuntimeException("User not authenticated"));
    }

    /**
     * Create a unique invite token for an existing care-circle link.
     * Family members may not mint invites; patients/caregivers/admins can.
     */
    @RequirePermission(Permission.CREATE_TASKS)
    @PostMapping("/care-circle/{linkId}/invite")
    public ResponseEntity<CreateInviteResponse> createInvite(
            @PathVariable Long linkId,
            @RequestBody(required = false) CreateInviteRequest request,
            HttpServletRequest httpRequest) {

        User currentUser = getCurrentUser();
        if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }

        CreateInviteResponse response = inviteTokenService.createInvite(
                linkId, request, currentUser, extractIp(httpRequest));
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    /**
     * Public preview of an invite. No authentication required so an invitee can
     * see the link type / status / expiry before signing up. Expired and revoked
     * tokens return clear errors.
     */
    @GetMapping("/invite/{token}")
    public ResponseEntity<InvitePreviewResponse> previewInvite(
            @PathVariable String token,
            HttpServletRequest httpRequest) {

        return ResponseEntity.ok(
                inviteTokenService.previewInvite(token, extractIp(httpRequest)));
    }

    /** Accept an invite, binding the authenticated user into the care circle. */
    @PostMapping("/invite/{token}/accept")
    public ResponseEntity<AcceptInviteResponse> acceptInvite(
            @PathVariable String token,
            HttpServletRequest httpRequest) {

        User currentUser = getCurrentUser();
        return ResponseEntity.ok(
                inviteTokenService.acceptInvite(token, currentUser, extractIp(httpRequest)));
    }

    /** Revoke a pending invite token. Idempotent. */
    @RequirePermission(Permission.CREATE_TASKS)
    @DeleteMapping("/care-circle/{linkId}/invite/{tokenId}")
    public ResponseEntity<Void> revokeInvite(
            @PathVariable Long linkId,
            @PathVariable Long tokenId,
            @RequestBody(required = false) RevokeInviteRequest request,
            HttpServletRequest httpRequest) {

        User currentUser = getCurrentUser();
        if (currentUser.getRole() == Role.FAMILY_MEMBER) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }

        inviteTokenService.revokeInvite(linkId, tokenId, request, currentUser, extractIp(httpRequest));
        return ResponseEntity.noContent().build();
    }

    private String extractIp(HttpServletRequest req) {
        String xff = req.getHeader("X-Forwarded-For");
        if (xff != null && !xff.isBlank()) {
            return xff.split(",")[0].trim();
        }
        return req.getRemoteAddr();
    }
}
