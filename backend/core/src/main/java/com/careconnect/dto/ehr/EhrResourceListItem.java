package com.careconnect.dto.ehr;

/**
 * One lightweight row in the Unified Health Data list (GET /api/ehr/resources). It is the
 * single-resource read's shape (see EpicOAuthController#resource) minus the raw FHIR {@code resource}
 * node — the screen builds the record card from these flattened fields and opens the detail view via
 * {@code resourceType} + {@code resourceId}. Contract: Cononical_0 v1.2 §6.
 */
public record EhrResourceListItem(
        String resourceType,
        String resourceId,
        String category,
        String title,
        String status,
        String occurredAt,
        String lastSyncedAt,
        String source) {
}
