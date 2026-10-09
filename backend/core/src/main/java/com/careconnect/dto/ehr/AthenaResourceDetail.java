package com.careconnect.dto.ehr;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * One record from {@code GET /api/athena/resources/{type}/{id}}: the list item's flattened fields
 * plus the stored FHIR resource, so the client can show fields the flattened ones do not cover.
 * Inline attachment data has already been removed from {@code resource}.
 */
public record AthenaResourceDetail(
        String resourceType,
        String resourceId,
        String category,
        String title,
        String status,
        String occurredAt,
        String lastSyncedAt,
        String source,
        JsonNode resource) {
}
