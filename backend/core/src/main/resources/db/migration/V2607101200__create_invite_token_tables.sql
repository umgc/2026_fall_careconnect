-- =============================================================================
-- V2607101200__create_invite_token_tables.sql
--
-- Issue #53: Care-circle scoped invite tokens and lifecycle endpoints.
--
-- Adds two tables:
--   1. invite_token        - one token per invite, scoped to a family_member_link
--   2. invite_token_audit  - immutable audit trail of every lifecycle event
--
-- Design notes:
--   * invite_token is a SEPARATE table (not columns on family_member_link) so the
--     audit trail survives even after a link is accepted/revoked, and so a link
--     can have a history of multiple tokens (old revoked, new issued).
--   * token_hash stores a one-way hash of the raw token (BCrypt via TokenHashService),
--     NEVER the raw token. The raw token only ever lives in the create response / URL.
--   * token_lookup is a fast, non-secret index key (first 12 chars of the raw UUID)
--     used to find the row before verifying the hash, so we don't table-scan.
--   * FKs reference the existing `users` and `family_member_link` tables.
-- =============================================================================

CREATE TABLE invite_token
(
    id                  BIGSERIAL PRIMARY KEY,

    -- Optimistic-lock version (JPA @Version). Prevents double-accept races:
    -- concurrent updates to the same row make the second commit fail.
    version             BIGINT       NOT NULL DEFAULT 0,

    -- Fast, non-secret lookup key (prefix of the raw token). Indexed, unique.
    token_lookup        VARCHAR(32)  NOT NULL,

    -- One-way hash of the full raw token. Verified with TokenHashService.
    token_hash          VARCHAR(255) NOT NULL,

    -- Scope: the care-circle link this invite belongs to.
    link_id             BIGINT       NOT NULL,

    -- Denormalized link type captured at issue time (PERMANENT/TEMPORARY/EMERGENCY).
    link_type           VARCHAR(30)  NOT NULL,

    -- Lifecycle: PENDING -> ACCEPTED | EXPIRED | REVOKED
    status              VARCHAR(20)  NOT NULL DEFAULT 'PENDING',

    -- Optional email the invite was addressed to (enables email-match on accept).
    invited_email       VARCHAR(255),

    -- Optional human-readable reason shown in the "Who invited me?" context (issue #59).
    invite_reason       VARCHAR(500),

    -- Audit: who created the invite.
    created_by_user_id  BIGINT       NOT NULL,

    -- Expiration metadata.
    expires_at          TIMESTAMP    NOT NULL,

    -- Acceptance metadata.
    accepted_by_user_id BIGINT,
    accepted_at         TIMESTAMP,

    -- Revocation metadata.
    revoked_by_user_id  BIGINT,
    revoked_at          TIMESTAMP,
    revoke_reason       VARCHAR(500),

    created_at          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_invite_token_link
        FOREIGN KEY (link_id) REFERENCES family_member_link (id) ON DELETE CASCADE,
    CONSTRAINT fk_invite_token_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_invite_token_accepted_by
        FOREIGN KEY (accepted_by_user_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_invite_token_revoked_by
        FOREIGN KEY (revoked_by_user_id) REFERENCES users (id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX idx_invite_token_lookup ON invite_token (token_lookup);
CREATE INDEX idx_invite_token_link        ON invite_token (link_id);
CREATE INDEX idx_invite_token_status      ON invite_token (status);
-- Partial index to make the scheduled expiry sweep cheap.
CREATE INDEX idx_invite_token_expires     ON invite_token (expires_at) WHERE status = 'PENDING';

-- Enforce "at most one PENDING invite per link" at the DATABASE level. The
-- application also checks this (existsActivePendingToken), but that check and
-- the insert are not atomic: two concurrent creates could both pass the check
-- and insert. This unique partial index makes the second insert fail, closing
-- the race. The service catches the resulting integrity violation and maps it
-- to a 409.
CREATE UNIQUE INDEX idx_invite_token_one_pending_per_link
    ON invite_token (link_id) WHERE status = 'PENDING';


CREATE TABLE invite_token_audit
(
    id             BIGSERIAL PRIMARY KEY,
    token_id       BIGINT      NOT NULL,
    event_type     VARCHAR(40) NOT NULL,   -- CREATED, VIEWED, ACCEPTED, EXPIRED, REVOKED
    actor_user_id  BIGINT,                 -- NULL for system/anonymous events
    actor_ip       VARCHAR(45),            -- IPv4 or IPv6
    detail         VARCHAR(1000),          -- freeform context (JSON or text)
    occurred_at    TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_invite_audit_token
        FOREIGN KEY (token_id) REFERENCES invite_token (id) ON DELETE CASCADE
);

CREATE INDEX idx_invite_audit_token    ON invite_token_audit (token_id);
CREATE INDEX idx_invite_audit_occurred ON invite_token_audit (occurred_at DESC);
