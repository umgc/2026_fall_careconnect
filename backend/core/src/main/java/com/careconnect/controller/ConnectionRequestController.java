package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.model.ConnectionRequest;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ConnectionRequestService;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import com.careconnect.dto.ConnectionRequestDto;


import java.util.Collections;
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
            description = "Create a new connection request from caregiver to patient by email"
    )
    public ResponseEntity<?> createConnectionRequest(@RequestBody ConnectionRequestDto request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireCaregiver(currentUser);
        try {
            ConnectionRequest createdRequest = connectionRequestService.createRequest(
                    request.getCaregiverId(),
                    request.getPatientEmail(),
                    request.getRelationshipType(),
                    request.getMessage()
            );

            return ResponseEntity.ok(Map.of(
                    "message", "Connection request sent successfully",
                    "requestId", createdRequest.getId()
            ));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)


    @GetMapping("/process")
    @Operation(
            summary = "Process connection request",
            description = "Process a patient's response to a connection request",
            security = {} // No auth needed for this endpoint
    )
    public ResponseEntity<?> processConnectionRequest(
            @RequestParam String token,
            @RequestParam boolean accept) {
        try {
            connectionRequestService.processResponse(token, accept);
            return ResponseEntity.ok(Map.of(
                    "message", accept ?
                            "Connection request accepted successfully" :
                            "Connection request rejected successfully"
            ));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)


    @GetMapping("/pending/patient/{patientId}")
    @Operation(
            summary = "Get pending requests for patient",
            description = "Get all pending connection requests for a patient"
    )
    public ResponseEntity<List<ConnectionRequest>> getPendingForPatient(@PathVariable Long patientId) {
        try {
            List<ConnectionRequest> requests = connectionRequestService.getPendingRequestsForPatient(patientId);
            return ResponseEntity.ok(requests);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Collections.emptyList());
        }
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)


    @GetMapping("/pending/caregiver/{caregiverId}")
    @Operation(
            summary = "Get pending requests by caregiver",
            description = "Get all pending connection requests sent by a caregiver"
    )
    public ResponseEntity<List<ConnectionRequest>> getPendingByCaregiver(@PathVariable Long caregiverId) {
        try {
            List<ConnectionRequest> requests = connectionRequestService.getPendingRequestsByCaregiver(caregiverId);
            return ResponseEntity.ok(requests);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Collections.emptyList());
        }
    }
}