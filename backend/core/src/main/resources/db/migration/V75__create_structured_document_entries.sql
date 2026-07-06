-- Home Care Document Digitization: structured form entries captured from
-- uploaded onboarding documents. The original file (user_files) stays linked
-- as supporting evidence; captured fields are stored as JSON for searchability.
CREATE TABLE structured_document_entries (
    id BIGSERIAL PRIMARY KEY,
    user_file_id BIGINT NOT NULL REFERENCES user_files(id),
    document_type VARCHAR(64) NOT NULL,
    patient_id BIGINT,
    employee_user_id BIGINT,
    fields_json TEXT,
    created_by BIGINT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    -- Patient or employee context is required before saving
    CONSTRAINT chk_structured_entry_context
        CHECK (patient_id IS NOT NULL OR employee_user_id IS NOT NULL)
);

-- One *active* structured entry per uploaded file (soft-deleted rows exempt);
-- doubles as the lookup index for user_file_id.
CREATE UNIQUE INDEX uq_structured_entries_active_user_file
    ON structured_document_entries(user_file_id)
    WHERE is_active;

CREATE INDEX idx_structured_entries_patient ON structured_document_entries(patient_id);
CREATE INDEX idx_structured_entries_employee ON structured_document_entries(employee_user_id);
