package com.careconnect.security;

import org.springframework.security.oauth2.jwt.Jwt;

/**
 * Shared JWT presence checks for patient-scoped API endpoints.
 */
public final class AuthRequestSupport {

    private AuthRequestSupport() {
    }

    public static void requireAuthenticated(Jwt jwt) throws UnauthorizedException {
        if (jwt == null) {
            throw new UnauthorizedException("Missing or invalid authentication token");
        }
    }
}
