-- V2607142100__create_usps_mailpiece.sql
--
-- Task 3.14.5 (#122) — Canonical USPS mailpiece persistence for Ask AI.
-- Parsed digests remaining TTL-cached in usps_digest_cache; durable rows
-- live here so IndexWorker can emit USPS_MAIL chunks into
-- retrieval_index_chunk (pgvector + FTS already provisioned).
--
-- Prod contract (application-prod.properties): Flyway is disabled; schema is
-- applied via SchemaPatchRunner + Hibernate ddl-auto=update. This script is
-- the source of truth and is mirrored in SchemaPatchRunner (idempotent
-- CREATE TABLE IF NOT EXISTS + guarded FK/unique, same pattern as
-- retrieval_index_chunk). Entity uses bare Long patientId (no @ManyToOne),
-- so Hibernate will not create the FK documented here — SchemaPatchRunner must.
--
-- Ownership: Team E (USPS / mail agent).
-- Related: RetrievalRecordType.USPS_MAIL, indexing_outbox, V2607071921.

CREATE TABLE IF NOT EXISTS usps_mailpiece (
    id              BIGSERIAL       PRIMARY KEY,
    patient_id      BIGINT          NOT NULL,
    user_id         VARCHAR(120)    NULL,
    source_key      VARCHAR(160)    NOT NULL,
    external_id     VARCHAR(120)    NULL,
    sender          VARCHAR(512)    NULL,
    summary         TEXT            NULL,
    image_ref       VARCHAR(1024)   NULL,
    received_at     TIMESTAMPTZ     NULL,
    digest_date     DATE            NULL,
    ocr_text        TEXT            NULL,
    content_hash    VARCHAR(80)     NOT NULL,
    consent_scope   VARCHAR(40)     NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- Guarded: entity has no @ManyToOne, so Hibernate ddl-auto will not create this FK.
DO $$ BEGIN
    ALTER TABLE usps_mailpiece
        ADD CONSTRAINT fk_usps_mailpiece_patient
        FOREIGN KEY (patient_id) REFERENCES patient (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Guarded unique: safe on re-run even if @UniqueConstraint already applied via Hibernate.
DO $$ BEGIN
    ALTER TABLE usps_mailpiece
        ADD CONSTRAINT uq_usps_mailpiece_patient_source_key
        UNIQUE (patient_id, source_key);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_usps_mailpiece_patient_digest_date
    ON usps_mailpiece (patient_id, digest_date);

CREATE INDEX IF NOT EXISTS idx_usps_mailpiece_patient_content_hash
    ON usps_mailpiece (patient_id, content_hash);

COMMENT ON TABLE usps_mailpiece IS
    'Canonical USPS Informed Delivery mailpiece rows (Task 3.14.5). Scoped by patient_id; source_key is digestDate|externalId.';

COMMENT ON COLUMN usps_mailpiece.source_key IS
    'Stable natural key: digestDate|externalId (idempotent upsert across re-fetch).';

COMMENT ON COLUMN usps_mailpiece.image_ref IS
    'HTTPS URL or short cid: key only — large data: URLs are not persisted.';

COMMENT ON COLUMN usps_mailpiece.content_hash IS
    'SHA-256 of normalized sender|summary|imageFingerprint|digestDate|externalId for idempotent re-index.';

COMMENT ON COLUMN usps_mailpiece.consent_scope IS
    'Caregiver visibility at persist time: on_consent, auto, or hidden.';
