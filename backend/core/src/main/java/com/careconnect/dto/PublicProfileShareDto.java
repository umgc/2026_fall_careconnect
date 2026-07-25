package com.careconnect.dto;

/**
 * Limited public view of a patient profile resolved via an opaque share token.
 * Intentionally omits patient id, user id, and sensitive clinical fields.
 */
public record PublicProfileShareDto(
        String status,
        String firstName,
        String lastName,
        String preferredCommunicationMethod,
        String message
) {
    public static PublicProfileShareDto invalid(String status, String message) {
        return new PublicProfileShareDto(status, null, null, null, message);
    }
}
