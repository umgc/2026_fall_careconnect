package com.careconnect.controller;

import com.careconnect.dto.CreateProfileShareRequest;
import com.careconnect.dto.CreateProfileShareResponse;
import com.careconnect.dto.PublicProfileShareDto;
import com.careconnect.dto.RevokeProfileShareRequest;
import com.careconnect.model.User;
import com.careconnect.security.Role;
import com.careconnect.service.ProfileShareTokenService;
import com.careconnect.util.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * Profile share-token endpoints.
 *
 *   POST   /v1/api/patients/me/profile-share              create  (patient/admin)
 *   DELETE /v1/api/patients/me/profile-share/{tokenId}    revoke  (patient/admin)
 *   GET    /v1/api/profile-share/{token}                  resolve (public)
 */
@RestController
@RequestMapping("/v1/api")
@RequiredArgsConstructor
public class ProfileShareController {

    private final ProfileShareTokenService profileShareTokenService;
    private final SecurityUtil securityUtil;

    @PostMapping("/patients/me/profile-share")
    public ResponseEntity<CreateProfileShareResponse> create(
            @RequestBody(required = false) CreateProfileShareRequest request) {

        User currentUser = requirePatientOrAdmin();
        CreateProfileShareResponse response = profileShareTokenService.create(request, currentUser);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @DeleteMapping("/patients/me/profile-share/{tokenId}")
    public ResponseEntity<Void> revoke(
            @PathVariable Long tokenId,
            @RequestBody(required = false) RevokeProfileShareRequest request) {

        User currentUser = requirePatientOrAdmin();
        profileShareTokenService.revoke(tokenId, request, currentUser);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/profile-share/{token}")
    public ResponseEntity<PublicProfileShareDto> resolve(@PathVariable String token) {
        return ResponseEntity.ok(profileShareTokenService.resolve(token));
    }

    private User requirePatientOrAdmin() {
        User currentUser = securityUtil.resolveCurrentUser();
        if (currentUser == null) {
            throw new com.careconnect.exception.AppException(HttpStatus.UNAUTHORIZED, "Authentication required");
        }
        if (currentUser.getRole() != Role.PATIENT && currentUser.getRole() != Role.ADMIN) {
            throw new com.careconnect.exception.AppException(HttpStatus.FORBIDDEN,
                    "Only patients or admins can manage profile share links");
        }
        return currentUser;
    }
}
