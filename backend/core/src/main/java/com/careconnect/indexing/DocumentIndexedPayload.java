package com.careconnect.indexing;

/**
 * Body of the {@code DOCUMENT_INDEXED} event payload (Task 4.1, description-only MVP).
 * Emitted after an uploaded document's extracted/description text is available for
 * indexing. Full OCR-backed indexing is future work; today {@code textExcerpt} is a
 * short description or caption rather than full document text. Blank descriptions
 * skip emit — do not read {@code DOCUMENT_INDEXED} as full-file ingest.
 *
 * @param fileId       persisted {@code user_files.id}; used as
 *                     {@code retrieval_index_chunk.source_record_id}
 * @param patientId    patient scope key for RBAC / indexing
 * @param contentHash  SHA-256 of {@code textExcerpt} for idempotent re-index
 * @param fileCategory typed file category (e.g. {@code MEDICAL_RECORD})
 * @param textExcerpt  short description/caption text available for indexing
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
