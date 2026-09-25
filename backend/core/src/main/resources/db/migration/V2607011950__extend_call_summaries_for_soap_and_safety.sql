-- Extend call_summaries for v2 SOAP fields (Team A locked schema, 2026-06-16)
-- and Call or Visit Summaries safety-engineering fields (FR-SUM-3/4/5/9, REQ-SC-1/5/6/7/8).
-- Adds per-item confirmation/dismissal audit table (REQ-SC-5/6, team TDD 6.2.2).

ALTER TABLE call_summaries
    ADD COLUMN IF NOT EXISTS risk_level VARCHAR(16);

ALTER TABLE call_summaries
    ADD COLUMN IF NOT EXISTS caregiver_visibility VARCHAR(16) NOT NULL DEFAULT 'on_consent';

ALTER TABLE call_summaries
    ADD COLUMN IF NOT EXISTS summary_confidence DECIMAL(3,2);

ALTER TABLE call_summaries
    ADD COLUMN IF NOT EXISTS summarization_engine VARCHAR(128);

ALTER TABLE call_summaries
    ADD COLUMN IF NOT EXISTS transcript_available BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_call_summary_risk_level
    ON call_summaries (risk_level);

CREATE INDEX IF NOT EXISTS idx_call_summary_caregiver_visibility
    ON call_summaries (caregiver_visibility);

CREATE TABLE IF NOT EXISTS call_summary_item_decisions (
    id BIGSERIAL PRIMARY KEY,
    summary_id BIGINT NOT NULL,
    item_id VARCHAR(120) NOT NULL,
    item_type VARCHAR(32) NOT NULL,
    decision VARCHAR(24) NOT NULL,
    destination VARCHAR(32),
    decided_by_user_id BIGINT,
    decided_at TIMESTAMP NOT NULL,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_summary_item_decisions_summary
        FOREIGN KEY (summary_id) REFERENCES call_summaries (id) ON DELETE CASCADE,
    CONSTRAINT fk_summary_item_decisions_user
        FOREIGN KEY (decided_by_user_id) REFERENCES users (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_summary_item_decisions_summary
    ON call_summary_item_decisions (summary_id);

CREATE INDEX IF NOT EXISTS idx_summary_item_decisions_summary_item
    ON call_summary_item_decisions (summary_id, item_id);

CREATE INDEX IF NOT EXISTS idx_summary_item_decisions_user_decided_at
    ON call_summary_item_decisions (decided_by_user_id, decided_at DESC);

CREATE TRIGGER tr_call_summary_item_decisions_immutable
    BEFORE UPDATE OR DELETE ON call_summary_item_decisions
    FOR EACH ROW EXECUTE FUNCTION reject_update_delete_immutable();
