package com.careconnect.controller;

import com.careconnect.dto.NotificationSettingDTO;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.NotificationSettingService;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/api/notification-settings")
@Tag(name = "Notification Settings", description = "Manage notification preferences for users")
public class NotificationSettingController {

    @Autowired
    private SecurityUtil securityUtil;

    @Autowired
    private AuthorizationService authorizationService;

    @Autowired
    private NotificationSettingService notificationSettingService;

    @GetMapping("/{userId}")
    @Operation(summary = "Get notification settings for a user")
    public ResponseEntity<NotificationSettingDTO> getSettings(@PathVariable Long userId) throws UnauthorizedException {
        // Authorization is enforced by requireSelfOrAdmin below (a user reads their own settings,
        // an admin reads anyone's). No @RequirePermission here: the previous VIEW_ASSIGNED_PATIENTS
        // guard was a caregiver permission that wrongly blocked patients from reading their own
        // settings (AccessDeniedException -> 500).
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireSelfOrAdmin(currentUser, userId);

        return ResponseEntity.ok(notificationSettingService.getByUserId(userId));
    }

    @PostMapping
    @Operation(summary = "Create or update notification settings for a user")
    public ResponseEntity<NotificationSettingDTO> createOrUpdate(@RequestBody NotificationSettingDTO dto) throws UnauthorizedException {
        // Same as getSettings: requireSelfOrAdmin is the gate. The previous CREATE_TASKS guard was
        // unrelated to notification settings and blocked users from saving their own preferences.
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireSelfOrAdmin(currentUser, dto.userId());

        return ResponseEntity.ok(notificationSettingService.createOrUpdate(dto));
    }
}
