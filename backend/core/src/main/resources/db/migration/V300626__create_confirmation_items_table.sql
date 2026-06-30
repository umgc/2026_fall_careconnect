CREATE TABLE IF NOT EXISTS confirmation_items (
    id              BIGSERIAL PRIMARY KEY,
    source_type     VARCHAR(32)  NOT NULL,
    status          VARCHAR(16)  NOT NULL DEFAULT 'PENDING',
    payload         TEXT         NOT NULL,
    reference_id    VARCHAR(120),
    requested_by    BIGINT       NOT NULL,
    resolved_by     BIGINT,
    resolved_at     TIMESTAMP,
    resolution_note VARCHAR(500),
    created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_confirmation_items_status       ON confirmation_items (status);
CREATE INDEX idx_confirmation_items_source_type  ON confirmation_items (source_type);
CREATE INDEX idx_confirmation_items_requested_by ON confirmation_items (requested_by);
