-- WBS 3.15.7: add a data-source exclusion flag for uploaded documents.
--
-- The user_ai_config table is created by Hibernate (ddl-auto) in dev/test and
-- has no prior Flyway migration, so create it defensively before adding the
-- column. Existing rows / older configs default to include (backward compatible).

CREATE TABLE IF NOT EXISTS user_ai_config (
    id                              BIGSERIAL PRIMARY KEY,
    user_id                         BIGINT       NOT NULL,
    patient_id                      BIGINT,
    preferred_ai_provider           VARCHAR(32),
    openai_model                    VARCHAR(64),
    deepseek_model                  VARCHAR(64),
    max_tokens                      INTEGER,
    temperature                     DOUBLE PRECISION,
    conversation_history_limit      INTEGER,
    system_prompt                   TEXT,
    include_vitals_by_default       BOOLEAN DEFAULT TRUE,
    include_medications_by_default  BOOLEAN DEFAULT TRUE,
    include_notes_by_default        BOOLEAN DEFAULT TRUE,
    include_mood_pain_by_default    BOOLEAN DEFAULT TRUE,
    include_allergies_by_default    BOOLEAN DEFAULT TRUE,
    include_documents_by_default    BOOLEAN DEFAULT TRUE,
    is_active                       BOOLEAN DEFAULT TRUE
);

ALTER TABLE user_ai_config
    ADD COLUMN IF NOT EXISTS include_documents_by_default BOOLEAN DEFAULT TRUE;
