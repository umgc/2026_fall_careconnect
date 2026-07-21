package com.careconnect.controller;

import com.careconnect.dto.CaregiverPatientLinkResponse;
import com.careconnect.dto.confirmation.ConfirmationDtos.ConfirmationItemResponse;
import com.careconnect.dto.confirmation.ConfirmationDtos.ResolveConfirmationRequest;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.confirmation.ConfirmationService;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Objects;
import java.util.stream.Collectors;

@RestController @RequestMapping("/v1/api/confirmations") @RequiredArgsConstructor
@Tag(name = "Confirmation Service", description = "Review and confirm/dismiss AI-generated content and side effects")
public class ConfirmationController {

    private final ConfirmationService confirmationService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final CaregiverPatientLinkService caregiverPatientLinkService;

    /**
     * A confirmation item is a review surface for a patient's care. Access is by patient scope:
     * items carrying a patientId use requirePatientAccess; items without one (older callers not
     * yet passing a patientId) are restricted to admins and caregivers.
     */
    private void authorizeReview(User user, ConfirmationItemResponse item) throws UnauthorizedException {
        if (item.getPatientId() != null) {
            authorizationService.requirePatientAccess(user, item.getPatientId());
        } else {
            authorizationService.requireAdminOrCaregiver(user);
        }
    }

    private List<Long> accessiblePatientIds(Long caregiverUserId) {
        return caregiverPatientLinkService.getPatientsByCaregiver(caregiverUserId).stream()
                .map(CaregiverPatientLinkResponse::patientUserId)
                .filter(Objects::nonNull)
                .collect(Collectors.toList());
    }

    @RequirePermission(Permission.USE_AI_FEATURES)
    @GetMapping("/pending")
    @Operation(summary = "List pending confirmation items",
               description = "Returns all PENDING confirmation items, optionally filtered by source type")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Pending items retrieved"),
        @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<List<ConfirmationItemResponse>> listPending(
            @RequestParam(required = false) String sourceType) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();

        List<ConfirmationItemResponse> items;
        if (currentUser != null && currentUser.isAdmin()) {
            items = sourceType != null
                    ? confirmationService.getPendingItemsBySourceType(ConfirmationService.parseSourceType(sourceType))
                    : confirmationService.getPendingItems();
        } else if (currentUser != null && currentUser.isCaregiver()) {
            items = confirmationService.getPendingItemsForPatients(accessiblePatientIds(currentUser.getId()));
            if (sourceType != null) {
                items = items.stream()
                        .filter(i -> sourceType.equalsIgnoreCase(i.getSourceType()))
                        .collect(Collectors.toList());
            }
        } else {
            items = List.of();
        }
        return ResponseEntity.ok(items);
    }

    @RequirePermission(Permission.USE_AI_FEATURES)
    @GetMapping("/{id}")
    @Operation(summary = "Get confirmation item details")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Item retrieved"),
        @ApiResponse(responseCode = "404", description = "Item not found")
    })
    public ResponseEntity<ConfirmationItemResponse> getItem(@PathVariable Long id) throws UnauthorizedException {
        ConfirmationItemResponse item = confirmationService.getItem(id);
        authorizeReview(securityUtil.resolveCurrentUser(), item);
        return ResponseEntity.ok(item);
    }

    @RequirePermission(Permission.USE_AI_FEATURES)
    @PostMapping("/{id}/confirm")
    @Operation(summary = "Confirm an item",
               description = "Mark a PENDING item as CONFIRMED")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Item confirmed"),
        @ApiResponse(responseCode = "400", description = "Item not in PENDING status"),
        @ApiResponse(responseCode = "404", description = "Item not found")
    })
    public ResponseEntity<ConfirmationItemResponse> confirmItem(
            @PathVariable Long id,
            @RequestBody(required = false) ResolveConfirmationRequest request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizeReview(currentUser, confirmationService.getItem(id));
        String note = request != null ? request.getNote() : null;
        var confirmed = confirmationService.confirm(id, currentUser.getId(), note);
        return ResponseEntity.ok(confirmationService.toResponse(confirmed));
    }

    @RequirePermission(Permission.USE_AI_FEATURES)
    @PostMapping("/{id}/dismiss")
    @Operation(summary = "Dismiss an item",
               description = "Mark a PENDING item as DISMISSED")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Item dismissed"),
        @ApiResponse(responseCode = "400", description = "Item not in PENDING status"),
        @ApiResponse(responseCode = "404", description = "Item not found")
    })
    public ResponseEntity<ConfirmationItemResponse> dismissItem(
            @PathVariable Long id,
            @RequestBody(required = false) ResolveConfirmationRequest request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizeReview(currentUser, confirmationService.getItem(id));
        String note = request != null ? request.getNote() : null;
        var dismissed = confirmationService.dismiss(id, currentUser.getId(), note);
        return ResponseEntity.ok(confirmationService.toResponse(dismissed));
    }

    @RequirePermission(Permission.USE_AI_FEATURES)
    @GetMapping("/user/{userId}")
    @Operation(summary = "Get confirmation items for a user",
               description = "Returns all confirmation items requested by a specific user")
    public ResponseEntity<List<ConfirmationItemResponse>> getItemsByUser(
            @PathVariable Long userId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireSelfOrAdmin(currentUser, userId);
        return ResponseEntity.ok(confirmationService.getItemsByUser(userId));
    }
}
