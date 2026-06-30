package com.careconnect.controller;

import com.careconnect.dto.confirmation.ConfirmationDtos.ConfirmationItemResponse;
import com.careconnect.dto.confirmation.ConfirmationDtos.ResolveConfirmationRequest;
import com.careconnect.model.User;
import com.careconnect.model.confirmation.ConfirmationSourceType;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;
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

@RestController @RequestMapping("/v1/api/confirmations") @RequiredArgsConstructor
@Tag(name = "Confirmation Service", description = "Review and confirm/dismiss AI-generated content and side effects")
public class ConfirmationController {

    private final ConfirmationService confirmationService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

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
        authorizationService.requirePermission(currentUser, Permission.USE_AI_FEATURES);
        if (sourceType != null) {
            return ResponseEntity.ok(
                confirmationService.getPendingItemsBySourceType(
                    ConfirmationSourceType.valueOf(sourceType)));
        }
        return ResponseEntity.ok(confirmationService.getPendingItems());
    }

    @RequirePermission(Permission.USE_AI_FEATURES)

    @GetMapping("/{id}")
    @Operation(summary = "Get confirmation item details")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Item retrieved"),
        @ApiResponse(responseCode = "404", description = "Item not found")
    })
    public ResponseEntity<ConfirmationItemResponse> getItem(@PathVariable Long id) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requirePermission(currentUser, Permission.USE_AI_FEATURES);
        return ResponseEntity.ok(confirmationService.getItem(id));
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
        authorizationService.requirePermission(currentUser, Permission.USE_AI_FEATURES);
        String note = request != null ? request.getNote() : null;
        var confirmed = confirmationService.confirm(id, currentUser.getId(), note);
        return ResponseEntity.ok(confirmationService.getItem(confirmed.getId()));
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
        authorizationService.requirePermission(currentUser, Permission.USE_AI_FEATURES);
        String note = request != null ? request.getNote() : null;
        var dismissed = confirmationService.dismiss(id, currentUser.getId(), note);
        return ResponseEntity.ok(confirmationService.getItem(dismissed.getId()));
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
