package com.careconnect.indexing;

/**
 * Body of the {@code DOCUMENT_INDEXED} event payload (Task 4.1).
 * Emitted after an uploaded document's description and/or extracted plain text is available
 * for indexing. Scanned images without OCR may still index description-only; blank text
 * skips emit.
 *
 * @param fileId       persisted {@code user_files.id}; used as
 *                     {@code retrieval_index_chunk.source_record_id}
 * @param patientId    patient scope key for RBAC / indexing
 * @param contentHash  SHA-256 of indexed text for idempotent re-index
 * @param fileCategory typed file category (e.g. {@code MEDICAL_RECORD})
 * @param textExcerpt  description and/or extracted body text available for indexing
 * @param consentScope caregiver visibility label
 */
public record DocumentIndexedPayload(
        Long fileId,
        Long patientId,
        String contentHash,
        String fileCategory,
        String textExcerpt,
        String consentScope
) {
}
