package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;

import com.careconnect.dto.evv.EvvLocationRequest;
import com.careconnect.dto.evv.EvvLocationResponse;
import com.careconnect.model.User;
import com.careconnect.model.evv.EvvLocationRole;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.evv.EvvLocationService;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/v1/api/evv/locations")
@RequiredArgsConstructor
@Tag(name = "EVV Locations", description = "EVV check-in and check-out location management")
public class EvvLocationController {

    private final EvvLocationService locationService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    /**
     * Save or update an EVV location (check-in or check-out)
     * Supports both GPS coordinates and patient address
     */
    @RequirePermission(Permission.CREATE_TASKS)

    @PostMapping
    @Operation(summary = "Save EVV location",
            description = "Save or update check-in/check-out location for an EVV record. " +
                    "Supports GPS coordinates or patient address snapshot.")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Location saved successfully"),
            @ApiResponse(responseCode = "201", description = "Location created successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request data"),
            @ApiResponse(responseCode = "404", description = "EVV record or patient not found")
    })
    public ResponseEntity<EvvLocationResponse> saveLocation(@Valid @RequestBody EvvLocationRequest request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        // Perform custom validation
        request.validate();

        // Save the location (upsert)
        EvvLocationResponse response = locationService.saveLocation(request);

        // Return 201 for new, 200 for update (we can't easily tell which, so return 200)
        return ResponseEntity.ok(response);
    }

    /**
     * Get all locations for an EVV record
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/records/{evvRecordId}")
    @Operation(summary = "Get locations for EVV record",
            description = "Retrieve all locations (check-in and check-out) for a specific EVV record")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Locations retrieved successfully"),
            @ApiResponse(responseCode = "404", description = "EVV record not found")
    })
    public ResponseEntity<List<EvvLocationResponse>> getLocationsForRecord(
            @PathVariable Long evvRecordId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        List<EvvLocationResponse> locations = locationService.getLocationsForRecord(evvRecordId);
        return ResponseEntity.ok(locations);
    }

    /**
     * Get a specific location by role
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)

    @GetMapping("/records/{evvRecordId}/{role}")
    @Operation(summary = "Get specific location by role",
            description = "Retrieve check-in or check-out location for an EVV record")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Location retrieved successfully"),
            @ApiResponse(responseCode = "404", description = "Location not found")
    })
    public ResponseEntity<EvvLocationResponse> getLocationByRole(
            @PathVariable Long evvRecordId,
            @PathVariable EvvLocationRole role) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        EvvLocationResponse location = locationService.getLocationByRole(evvRecordId, role);
        return ResponseEntity.ok(location);
    }

    /**
     * Delete a location
     */
    @RequirePermission(Permission.DELETE_PATIENTS)

    @DeleteMapping("/records/{evvRecordId}/{role}")
    @Operation(summary = "Delete location",
            description = "Delete a check-in or check-out location for an EVV record")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "204", description = "Location deleted successfully"),
            @ApiResponse(responseCode = "404", description = "Location not found")
    })
    public ResponseEntity<Void> deleteLocation(
            @PathVariable Long evvRecordId,
            @PathVariable EvvLocationRole role) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdminOrCaregiver(currentUser);
        locationService.deleteLocation(evvRecordId, role);
        return ResponseEntity.noContent().build();
    }
}

