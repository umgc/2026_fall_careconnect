-- Document Completion & Compliance Tracking: per-subject required-document
-- checklist status plus an immutable audit trail of every status transition.
-- A "subject" is either an employee (users.id, e.g. a caregiver being onboarded)
-- or a care circle (patients.id, the care recipient at its center).
CREATE TABLE document_requirement_statuses (
    id BIGSERIAL PRIMARY KEY,
    subject_type VARCHAR(32) NOT NULL,          -- EMPLOYEE | CARE_CIRCLE
    subject_id BIGINT NOT NULL,                 -- users.id (EMPLOYEE) or patients.id (CARE_CIRCLE)
    document_type VARCHAR(64) NOT NULL,
    status VARCHAR(32) NOT NULL,                -- MISSING | IN_PROGRESS | COMPLETE | REJECTED
    user_file_id BIGINT REFERENCES user_files(id),
    structured_entry_id BIGINT REFERENCES structured_document_entries(id),
    notes VARCHAR(1024),
    updated_by BIGINT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    CONSTRAINT uq_doc_requirement_subject UNIQUE (subject_type, subject_id, document_type)
);

CREATE INDEX idx_doc_requirement_subject ON document_requirement_statuses(subject_type, subject_id);
CREATE INDEX idx_doc_requirement_status ON document_requirement_statuses(status);

-- Immutable audit trail: who changed a document's compliance status, when and why.
CREATE TABLE document_status_history (
    id BIGSERIAL PRIMARY KEY,
    subject_type VARCHAR(32) NOT NULL,
    subject_id BIGINT NOT NULL,
    document_type VARCHAR(64) NOT NULL,
    previous_status VARCHAR(32),
    new_status VARCHAR(32) NOT NULL,
    changed_by BIGINT NOT NULL,
    reason VARCHAR(1024) NOT NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_doc_status_history_subject
    ON document_status_history(subject_type, subject_id, document_type);
