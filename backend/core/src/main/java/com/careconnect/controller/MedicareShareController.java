package com.careconnect.controller;

import com.careconnect.dto.MedicareShareRequest;
import com.careconnect.dto.MedicareShareResponse;
import com.careconnect.dto.MedicareSharedWithMeResponse;
import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.security.Role;
import com.careconnect.service.consent.MedicareShareService;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;

import java.util.List;

import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * CR-2 (#305) patient-facing record sharing: share Medicare records with a registered user by
 * email (read-only, 90 days), list current shares, and revoke one by its id; plus the recipient's
 * "Shared with me" list.
 */
@RestController
@RequiredArgsConstructor
@RequestMapping({"/api/v3/consent/medicare-share", "/v1/api/v3/consent/medicare-share"})
@Tag(name = "Consent", description = "Patient consent grants and record sharing")
@SecurityRequirement(name = "bearerAuth")
public class MedicareShareController {

    private final MedicareShareService medicareShareService;
    private final SecurityUtil securityUtil;

    @PostMapping(
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    @Operation(summary = "Share the patient's Medicare records with a registered user by email")
    public ResponseEntity<MedicareShareResponse> share(
            @RequestBody final MedicareShareRequest request) {
        final User patient = requirePatientCaller();
        if (request == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "recipientEmail is required");
        }
        final MedicareShareService.ShareResult result =
                medicareShareService.shareMedicareRecords(patient, request.recipientEmail());
        return ResponseEntity.status(HttpStatus.CREATED).body(MedicareShareResponse.from(
                result.grant(), result.recipient(), result.emailSent()));
    }

    @GetMapping(produces = MediaType.APPLICATION_JSON_VALUE)
    @Operation(summary = "List the patient's active Medicare shares")
    public ResponseEntity<List<MedicareShareResponse>> list() {
        final User patient = requirePatientCaller();
        return ResponseEntity.ok(medicareShareService.listActiveShares(patient.getId()).stream()
                .map(r -> MedicareShareResponse.from(r.grant(), r.recipient(), null))
                .toList());
    }

    /**
     * The caller's "Shared with me" list. Any signed-in user may ask, since a share recipient can
     * hold any role; each user only ever sees shares made to them.
     */
    @GetMapping(value = "/received", produces = MediaType.APPLICATION_JSON_VALUE)
    @Operation(summary = "List Medicare records other patients have shared with the caller")
    public ResponseEntity<List<MedicareSharedWithMeResponse>> received() {
        final User caller = requireAuthenticatedCaller();
        return ResponseEntity.ok(medicareShareService.listSharedWithMe(caller.getId()));
    }

    @DeleteMapping(value = "/{shareId}", produces = MediaType.APPLICATION_JSON_VALUE)
    @Operation(summary = "Revoke one of the patient's Medicare shares")
    public ResponseEntity<MedicareShareResponse> revoke(@PathVariable final Long shareId) {
        final User patient = requirePatientCaller();
        final MedicareShareService.ShareResult result =
                medicareShareService.revokeShare(patient.getId(), shareId);
        return ResponseEntity.ok(MedicareShareResponse.from(result.grant(), result.recipient(), null));
    }

    private User requirePatientCaller() {
        final User caller = requireAuthenticatedCaller();
        if (caller.getRole() != Role.PATIENT) {
            throw new AppException(
                    HttpStatus.FORBIDDEN, "Only the patient may share their Medicare records");
        }
        return caller;
    }

    private User requireAuthenticatedCaller() {
        final User caller = securityUtil.resolveCurrentUser();
        if (caller == null || caller.getId() == null) {
            throw new AppException(HttpStatus.UNAUTHORIZED, "Authentication required");
        }
        return caller;
    }
}
