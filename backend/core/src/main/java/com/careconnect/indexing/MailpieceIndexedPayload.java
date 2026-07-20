package com.careconnect.indexing;

import java.time.LocalDate;

/**
 * Body of the {@code MAILPIECE_INDEXED} event payload (Task 3.14.5 / #122).
 * Emitted after a {@code usps_mailpiece} row is upserted with a new or
 * changed {@code content_hash}.
 *
 * @param mailpieceId  persisted {@code usps_mailpiece.id}; used as
 *                     {@code retrieval_index_chunk.source_record_id}
 * @param patientId    patient scope key for RBAC / indexing
 * @param sourceKey    natural key {@code digestDate|externalId}
 * @param contentHash  SHA-256 for idempotent re-index
 * @param sender       normalized sender (may be null)
 * @param summary      normalized summary (may be null)
 * @param digestDate   digest calendar date (may be null)
 * @param consentScope caregiver visibility label
 */
public record MailpieceIndexedPayload(
        Long mailpieceId,
        Long patientId,
        String sourceKey,
        String contentHash,
        String sender,
        String summary,
        LocalDate digestDate,
        String consentScope
) {
}
