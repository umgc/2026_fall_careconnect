package com.careconnect.security;

/**
 * Exception thrown when a user attempts an action they are not authorized to perform.
 * <p>
 * This exception indicates that:
 * - User is authenticated (they have a valid account and session)
 * - User lacks the required permission or role for the requested action
 * <p>
 * This should map to HTTP 403 Forbidden in REST API responses.
 * <p>
 * Differentiation:
 * - UnauthorizedException (403) = Authenticated but lacks permission
 * - AuthenticationException (401) = Not authenticated or invalid credentials
 *
 * @author CareConnect Team
 * @version 1.0
 */
public class UnauthorizedException extends Exception {

    /**
     * Constructs a new UnauthorizedException with the specified detail message.
     *
     * @param message The detail message explaining why authorization was denied
     * @example throw new UnauthorizedException("User does not have CREATE_TASKS permission");
     */
    public UnauthorizedException(String message) {
        super(message);
    }

    /**
     * Constructs a new UnauthorizedException with the specified detail message and cause.
     *
     * @param message The detail message
     * @param cause   The cause of this exception
     * @example throw new UnauthorizedException("Authorization check failed", originalException);
     */
    public UnauthorizedException(String message, Throwable cause) {
        super(message, cause);
    }

    /**
     * Constructs a new UnauthorizedException for a specific user and permission.
     * Convenience method for common use case.
     *
     * @param userEmail  The email of the user who was denied
     * @param permission The permission that was required
     * @return A new UnauthorizedException with formatted message
     * @example throw UnauthorizedException.forPermission("user@example.com", Permission.CREATE_TASKS);
     */
    public static UnauthorizedException forPermission(String userEmail, Permission permission) {
        return new UnauthorizedException(
                String.format("User '%s' does not have permission: %s (%s)",
                        userEmail,
                        permission.name(),
                        permission.getDescription())
        );
    }

    /**
     * Constructs a new UnauthorizedException for a specific role requirement.
     *
     * @param userEmail    The email of the user who was denied
     * @param requiredRole The role that was required
     * @param actualRole   The role the user actually has
     * @return A new UnauthorizedException with formatted message
     * @example throw UnauthorizedException.forRole("user@example.com", Role.ADMIN, user.getRole());
     */
    public static UnauthorizedException forRole(String userEmail, Role requiredRole, Role actualRole) {
        return new UnauthorizedException(
                String.format("User '%s' requires role '%s' but has role '%s'",
                        userEmail,
                        requiredRole.getDisplayName(),
                        actualRole.getDisplayName())
        );
    }
}