package com.careconnect.security;

import com.careconnect.model.User;

/**
 * Shared authentication checks for patient-scoped API endpoints.
 *
 * <p>{@code JwtAuthenticationFilter} sets a {@code UserDetails} principal, so an
 * {@code @AuthenticationPrincipal Jwt} parameter is always null. Check the resolved
 * current user instead.
 */
public final class AuthRequestSupport {

    private AuthRequestSupport() {
    }

    public static User requireAuthenticated(User currentUser) throws UnauthorizedException {
        if (currentUser == null) {
            throw new UnauthorizedException("Missing or invalid authentication token");
        }
        return currentUser;
    }
}
