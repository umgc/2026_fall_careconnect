package com.careconnect.controller;

import com.careconnect.model.User;
import com.careconnect.service.GoogleHealthOAuthService;
import com.careconnect.util.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.util.Map;

@RestController
@RequestMapping("/v1/api/wearables/google-health")
@RequiredArgsConstructor
public class GoogleHealthWearableController {

    private final GoogleHealthOAuthService googleHealthOAuthService;
    private final SecurityUtil securityUtil;

    @GetMapping("/auth-url")
    public ResponseEntity<?> authUrl(@RequestParam(required = false) String returnUrl) {
        User currentUser = securityUtil.resolveCurrentUser();
        if (currentUser == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "Authentication required"));
        }

        String authUrl = googleHealthOAuthService.buildAuthorizationUrl(
                String.valueOf(currentUser.getId()),
                returnUrl
        );
        return ResponseEntity.ok(Map.of("authUrl", authUrl));
    }

    @GetMapping("/start")
    public ResponseEntity<?> start(@RequestParam(required = false) String returnUrl) {
        User currentUser = securityUtil.resolveCurrentUser();
        if (currentUser == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "Authentication required"));
        }

        String authUrl = googleHealthOAuthService.buildAuthorizationUrl(
                String.valueOf(currentUser.getId()),
                returnUrl
        );

        return ResponseEntity.status(HttpStatus.FOUND)
                .location(URI.create(authUrl))
                .build();
    }

    @GetMapping("/status")
    public ResponseEntity<?> status() {
        User currentUser = securityUtil.resolveCurrentUser();
        if (currentUser == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "Authentication required"));
        }

        boolean connected = googleHealthOAuthService.isConnected(String.valueOf(currentUser.getId()));
        return ResponseEntity.ok(Map.of("connected", connected));
    }

    @DeleteMapping("/disconnect")
    public ResponseEntity<?> disconnect() {
        User currentUser = securityUtil.resolveCurrentUser();
        if (currentUser == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "Authentication required"));
        }

        googleHealthOAuthService.disconnect(String.valueOf(currentUser.getId()));
        return ResponseEntity.ok(Map.of("message", "Google Health disconnected"));
    }

    @GetMapping("/exercise")
    public ResponseEntity<?> exerciseData(
            @RequestParam(required = false) Integer pageSize,
            @RequestParam(required = false) String pageToken,
            @RequestParam(required = false) String filter
    ) {
        return dataPoints("exercise", pageSize, pageToken, filter);
    }

    @GetMapping("/data-types/{dataType}/data-points")
    public ResponseEntity<?> dataPoints(
            @PathVariable String dataType,
            @RequestParam(required = false) Integer pageSize,
            @RequestParam(required = false) String pageToken,
            @RequestParam(required = false) String filter
    ) {
        User currentUser = securityUtil.resolveCurrentUser();
        if (currentUser == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "Authentication required"));
        }

        try {
            Map<String, Object> response = googleHealthOAuthService.listDataPoints(
                    String.valueOf(currentUser.getId()),
                    dataType,
                    pageSize,
                    pageToken,
                    filter
            );

            return ResponseEntity.ok(Map.of(
                    "data", response,
                    "dataType", dataType,
                    "message", "Google Health data retrieved successfully"
            ));
        } catch (IllegalArgumentException ex) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("error", ex.getMessage()));
        } catch (IllegalStateException ex) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("error", ex.getMessage()));
        }
    }
}
