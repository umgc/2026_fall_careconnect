package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.ConnectionRequestSummary;
import com.careconnect.model.ConnectionRequest;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ConnectionRequestService;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import com.careconnect.dto.ConnectionRequestDto;


import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/v1/api/connection-requests")
@RequiredArgsConstructor
@Tag(name = "Connection Requests", description = "Manage caregiver-patient connection requests")
public class ConnectionRequestController {

    private final ConnectionRequestService connectionRequestService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @RequirePermission(Permission.CREATE_TASKS)
    @PostMapping("/create")
    @Operation(
            summary = "Create connection request",
            description = "Ask a patient, by email, to accept the calling caregiver. The caregiver "
                    + "gets no access until the patient accepts."
    )
    public ResponseEntity<?> createConnectionRequest(@RequestBody ConnectionRequestDto request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireCaregiver(currentUser);

        try {
            // The requester is always the caller; a caregiverId in the body is ignored so a
            // caregiver cannot send requests in someone else's name.
            ConnectionRequest createdRequest = connectionRequestService.createRequest(
                    currentUser.getId(),
                    request.getPatientEmail(),
                    request.getRelationshipType(),
                    request.getMessage()
            );

            return ResponseEntity.ok(Map.of(
                    "message", "Connection request sent successfully",
                    "requestId", createdRequest.getId()
            ));
        } catch (IllegalArgumentException | IllegalStateException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    @GetMapping("/incoming")
    @Operation(summary = "Pending requests for me", description = "Pending connection requests addressed to the calling patient")
    public ResponseEntity<List<ConnectionRequestSummary>> getIncoming() {
        User currentUser = securityUtil.resolveCurrentUser();
        if (!currentUser.isPatient()) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.ok(connectionRequestService.getPendingRequestsForPatient(currentUser).stream()
                .map(connectionRequestService::toSummary)
                .toList());
    }

    @GetMapping("/outgoing")
    @Operation(summary = "Pending requests I sent", description = "Pending connection requests sent by the calling caregiver")
    public ResponseEntity<List<ConnectionRequestSummary>> getOutgoing() {
        User currentUser = securityUtil.resolveCurrentUser();
        if (!currentUser.isCaregiver()) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        return ResponseEntity.ok(connectionRequestService.getPendingRequestsByCaregiver(currentUser).stream()
                .map(connectionRequestService::toSummary)
                .toList());
    }

    @PostMapping("/{requestId}/accept")
    @Operation(summary = "Accept a request", description = "The calling patient accepts one of their pending requests")
    public ResponseEntity<?> accept(@PathVariable Long requestId) {
        return respond(requestId, true);
    }

    @PostMapping("/{requestId}/reject")
    @Operation(summary = "Decline a request", description = "The calling patient declines one of their pending requests")
    public ResponseEntity<?> reject(@PathVariable Long requestId) {
        return respond(requestId, false);
    }

    private ResponseEntity<?> respond(Long requestId, boolean accept) {
        User currentUser = securityUtil.resolveCurrentUser();
        if (!currentUser.isPatient()) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        try {
            connectionRequestService.respond(requestId, currentUser, accept);
            return ResponseEntity.ok(Map.of(
                    "message", accept
                            ? "Connection request accepted successfully"
                            : "Connection request rejected successfully"
            ));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", e.getMessage()));
        } catch (IllegalStateException e) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", e.getMessage()));
        }
    }
}
