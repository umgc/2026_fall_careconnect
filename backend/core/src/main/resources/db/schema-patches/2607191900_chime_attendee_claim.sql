ALTER TABLE call_participants
    ADD COLUMN IF NOT EXISTS chime_external_user_id VARCHAR(64),
    ADD COLUMN IF NOT EXISTS chime_attendee_id VARCHAR(255),
    ADD COLUMN IF NOT EXISTS chime_join_token TEXT,
    ADD COLUMN IF NOT EXISTS attendee_claim_token UUID,
    ADD COLUMN IF NOT EXISTS attendee_claimed_until TIMESTAMPTZ;

COMMENT ON COLUMN call_participants.chime_external_user_id IS
    'Opaque pseudonymous Chime externalUserId for this durable participant';
COMMENT ON COLUMN call_participants.chime_attendee_id IS
    'Chime attendee id persisted after successful create/list';
COMMENT ON COLUMN call_participants.chime_join_token IS
    'Chime join token persisted after successful create/list';
COMMENT ON COLUMN call_participants.attendee_claim_token IS
    'Lease token fencing in-flight attendee creation ownership';
COMMENT ON COLUMN call_participants.attendee_claimed_until IS
    'UTC lease expiry for attendee creation claim';
