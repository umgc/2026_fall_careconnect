-- A chat message can be a share card: a patient shares one kind of their data (MEDICARE, HEALTH) with a
-- linked caregiver. The card holds only what it opens, never the data; who may see the data is
-- checked when the card is opened.
--
-- Both columns are nullable, so production (no Flyway) gets them from Hibernate ddl-auto=update.
-- Safe to rerun.

ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS share_kind       VARCHAR(32),
    ADD COLUMN IF NOT EXISTS share_patient_id BIGINT;
