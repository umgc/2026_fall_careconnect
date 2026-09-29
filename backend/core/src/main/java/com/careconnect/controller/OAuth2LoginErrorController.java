package com.careconnect.controller;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.web.WebAttributes;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Reports why an OAuth2 sign-in failed.
 * <p>
 * Spring Security redirects a failed {@code oauth2Login} to {@code /login?error}. Nothing in
 * this application served that path, so the browser fell through to {@code /error}, which is
 * also unmapped — the visible result was a blank white page with no indication of what went
 * wrong. A real failure (CMS returning 401 to the token exchange, say) could only be found by
 * reading the server log.
 */
@RestController
@Slf4j
public class OAuth2LoginErrorController {

    @GetMapping("/login")
    public ResponseEntity<String> loginResult(final HttpServletRequest request) {
        final HttpSession session = request.getSession(false);
        final Object attribute = session == null
                ? null
                : session.getAttribute(WebAttributes.AUTHENTICATION_EXCEPTION);

        if (!(attribute instanceof AuthenticationException failure)) {
            return ResponseEntity.ok()
                    .contentType(MediaType.APPLICATION_JSON)
                    .body("{\"status\":\"no sign-in failure recorded\"}");
        }

        String errorCode = "unknown";
        String description = "";
        if (failure instanceof OAuth2AuthenticationException oauthFailure) {
            errorCode = String.valueOf(oauthFailure.getError().getErrorCode());
            description = String.valueOf(oauthFailure.getError().getDescription());
        }

        log.warn("OAuth2 sign-in failed: code={} message={}", errorCode, failure.getMessage());

        return ResponseEntity.status(401)
                .contentType(MediaType.APPLICATION_JSON)
                .body("{\"error\":\"oauth2 sign-in failed\""
                        + ",\"code\":\"" + quote(errorCode) + "\""
                        + ",\"description\":\"" + quote(description) + "\""
                        + ",\"message\":\"" + quote(failure.getMessage()) + "\"}");
    }

    private static String quote(final String value) {
        return String.valueOf(value).replace('"', '\'');
    }
}
