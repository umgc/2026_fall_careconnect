package com.careconnect.indexing;

/**
 * Body of the {@code CLINICAL_NOTE_INDEXED} event payload (Task 4.1).
 * Emitted after a {@code patient_note} row is created or updated.
 *
 * @param noteId       persisted {@code patient_note.id}; used as
 *                     {@code retrieval_index_chunk.source_record_id}
 * @param patientId    patient scope key for RBAC / indexing
 * @param contentHash  SHA-256 of note body + AI summary for idempotent re-index
 *                     (see {@link com.careconnect.util.ContentHashUtil#clinicalNoteContentHash})
 * @param consentScope caregiver visibility label
 */
public record ClinicalNoteIndexedPayload(
        Long noteId,
        Long patientId,
        String contentHash,
        String consentScope
) {
}
