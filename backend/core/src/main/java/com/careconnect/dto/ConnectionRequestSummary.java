package com.careconnect.dto;

import com.careconnect.model.ConnectionRequest;

import java.time.Instant;

/**
 * What the API returns for a caregiver-patient connection request. The entity is
 * never returned directly: it embeds both {@code User} rows and carries the
 * request token.
 */
public record ConnectionRequestSummary(
        Long id,
        String caregiverName,
        String caregiverEmail,
        String patientName,
        String patientEmail,
        String relationshipType,
        String message,
        String status,
        Instant requestedAt) {

    public static ConnectionRequestSummary from(
            ConnectionRequest request, String caregiverName, String patientName) {
        return new ConnectionRequestSummary(
                request.getId(),
                caregiverName,
                request.getCaregiver().getEmail(),
                patientName,
                request.getPatient().getEmail(),
                request.getRelationshipType(),
                request.getMessage(),
                request.getStatus(),
                request.getRequestedAt());
    }
}
