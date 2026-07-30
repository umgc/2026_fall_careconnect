package com.careconnect.controller;

import com.careconnect.service.GoogleHealthOAuthService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

@RestController
@RequestMapping("/oauth/google-health")
@RequiredArgsConstructor
public class GoogleHealthOAuthCallbackController {

    private final GoogleHealthOAuthService googleHealthOAuthService;

    @GetMapping("/callback")
    public ResponseEntity<Void> callback(
            @RequestParam(required = false) String code,
            @RequestParam(required = false) String state,
            @RequestParam(required = false) String error
    ) {
        String defaultReturnUrl = googleHealthOAuthService.defaultReturnUrl();

        if (error != null && !error.isBlank()) {
            String target = appendQuery(defaultReturnUrl, "googleHealthError",
                    URLEncoder.encode(error, StandardCharsets.UTF_8));
            return ResponseEntity.status(HttpStatus.FOUND)
                    .location(URI.create(target))
                    .build();
        }

        if (code == null || code.isBlank() || state == null || state.isBlank()) {
            String target = appendQuery(defaultReturnUrl, "googleHealthError", "missing_callback_params");
            return ResponseEntity.status(HttpStatus.FOUND)
                    .location(URI.create(target))
                    .build();
        }

        try {
            GoogleHealthOAuthService.OAuthCallbackResult result =
                    googleHealthOAuthService.handleCallback(code, state);

            String returnUrl = (result.returnUrl() == null || result.returnUrl().isBlank())
                    ? defaultReturnUrl
                    : result.returnUrl();

            String target = appendQuery(returnUrl, "googleHealth", "connected");
            return ResponseEntity.status(HttpStatus.FOUND)
                    .location(URI.create(target))
                    .build();
        } catch (Exception e) {
            String target = appendQuery(defaultReturnUrl, "googleHealthError",
                    URLEncoder.encode(e.getMessage(), StandardCharsets.UTF_8));
            return ResponseEntity.status(HttpStatus.FOUND)
                    .location(URI.create(target))
                    .build();
        }
    }

    private String appendQuery(String baseUrl, String key, String value) {
        String separator = baseUrl.contains("?") ? "&" : "?";
        return baseUrl + separator + key + "=" + value;
    }
}
