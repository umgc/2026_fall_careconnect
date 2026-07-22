package com.careconnect.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.annotation.Order;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ScriptUtils;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.Statement;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;

/**
 * Applies one-time schema patches via plain JDBC after the application context starts.
 * Production keeps Hibernate DDL and Flyway disabled, so this runner is the sole DDL
 * owner; required production changes additionally use a bounded PostgreSQL advisory lock.
 *
 * Each patch is idempotent: safe to execute on every restart.
 */
@Slf4j
@Component
@Order(1)
public class SchemaPatchRunner implements CommandLineRunner {

    private static final String PRODUCTION_SCHEMA_LOCK =
            "hashtextextended('careconnect:production-schema', 0)";
    private static final Pattern POSTGRES_TEXT_CAST = Pattern.compile(
            "::(?:character varying|varchar|text)(?:\\(\\d+\\))?");
    private static final Pattern QUOTED_NUMBER = Pattern.compile("'(\\d+)'");

    private final DataSource dataSource;
    private final SchemaPatchLedger patchLedger;

    @Autowired
    public SchemaPatchRunner(DataSource dataSource) {
        this(dataSource, new SchemaPatchLedger(dataSource, applicationVersion()));
    }

    SchemaPatchRunner(
            final DataSource dataSource,
            final SchemaPatchLedger patchLedger) {
        this.dataSource = dataSource;
        this.patchLedger = patchLedger;
    }

    @Override
    public void run(String... args) {
        applyPatch(
            "V55 – allow NULL file_data for S3 storage",
            "ALTER TABLE user_files ALTER COLUMN file_data DROP NOT NULL"
        );
        applyPatch(
            "V55b – create evv_outbox table",
            "CREATE TABLE IF NOT EXISTS evv_outbox (" +
            "  id            BIGSERIAL PRIMARY KEY," +
            "  evv_record_id BIGINT NOT NULL REFERENCES evv_record(id)," +
            "  destination   VARCHAR(64) NOT NULL," +
            "  payload       JSONB NOT NULL," +
            "  status        VARCHAR(32) NOT NULL DEFAULT 'READY'," +
            "  attempts      INT NOT NULL DEFAULT 0," +
            "  last_error    TEXT," +
            "  created_at    TIMESTAMP WITH TIME ZONE DEFAULT now()," +
            "  updated_at    TIMESTAMP WITH TIME ZONE DEFAULT now()" +
            ")"
        );
        applyPatch(
            "V55c – index on evv_outbox(status)",
            "CREATE INDEX IF NOT EXISTS idx_outbox_status ON evv_outbox(status)"
        );
        applyPatch(
            "V62a – create risk_types table",
            "CREATE TABLE IF NOT EXISTS risk_types (" +
            "  id BIGSERIAL PRIMARY KEY," +
            "  name VARCHAR(100) NOT NULL UNIQUE" +
            ")"
        );
        applyPatch(
            "V62b – seed predefined risk types",
            "INSERT INTO risk_types (name) VALUES " +
            "('Aspiration Pneumonia')," +
            "('Elopement')," +
            "('Fall with Injury')," +
            "('Self-Harm')," +
            "('Seizures') " +
            "ON CONFLICT (name) DO NOTHING"
        );
        applyPatch(
            "V70a – rename stripe_customer_id → payment_customer_id on users",
            "ALTER TABLE users RENAME COLUMN stripe_customer_id TO payment_customer_id"
        );
        applyPatch(
            "V70b – rename stripe_customer_id → payment_customer_id on subscriptions",
            "ALTER TABLE subscriptions RENAME COLUMN stripe_customer_id TO payment_customer_id"
        );
        applyPatch(
            "V71 – rename stripe_subscription_id → payment_subscription_id on subscriptions",
            "ALTER TABLE subscriptions RENAME COLUMN stripe_subscription_id TO payment_subscription_id"
        );
        applyPatch(
            "V72 – drop NOT NULL on payment_subscription_id",
            "ALTER TABLE subscriptions ALTER COLUMN payment_subscription_id DROP NOT NULL"
        );
        applyPatch(
            "V72b – drop NOT NULL on stripe_subscription_id if column still exists",
            "ALTER TABLE subscriptions ALTER COLUMN stripe_subscription_id DROP NOT NULL"
        );
        applyPatch(
            "V73 – add transcription_status to call_recordings",
            "ALTER TABLE call_recordings ADD COLUMN IF NOT EXISTS transcription_status VARCHAR(20) NULL"
        );
        applyPatch(
            "V74 – update mock user addresses to Falls Church, VA",
            "UPDATE patient SET city = 'Falls Church', state = 'VA', zip = '22046' " +
            "WHERE user_id = (SELECT id FROM users WHERE email = 'patient@careconnect.com') " +
            "AND city IN ('Springfield', 'Chicago');" +
            "UPDATE caregiver SET city = 'Falls Church', state = 'VA', zip = '22046' " +
            "WHERE user_id IN (SELECT id FROM users WHERE email IN ('caregiver@careconnect.com', 'sarah.mitchell@careconnect.com')) " +
            "AND city IN ('Springfield', 'Chicago')"
        );
        applyPatch(
            "V75 – align user_files.file_category CHECK constraint with typed category model",
            // Recreate the constraint so the employment / home-care intake categories are
            // accepted. Superset of the previous allow-list (legacy HIRING_DOCUMENT retained
            // for backward compatibility), so all existing rows remain valid. Idempotent.
            "ALTER TABLE user_files DROP CONSTRAINT IF EXISTS user_files_file_category_check;" +
            "ALTER TABLE user_files ADD CONSTRAINT user_files_file_category_check CHECK (" +
            "file_category IN (" +
            "  'PROFILE_IMAGE','MEDICAL_RECORD','CLINICAL_NOTE','PRESCRIPTION','LAB_RESULT'," +
            "  'INSURANCE_DOCUMENT','CONSENT_FORM','CARE_PLAN'," +
            "  'EMPLOYMENT_APPLICATION','ONBOARDING_FORM','BACKGROUND_CHECK','CERTIFICATION'," +
            "  'REFERENCE','EMPLOYMENT_CONTRACT','TAX_FORM','WORK_AUTHORIZATION','EMERGENCY_CONTACT'," +
            "  'HIRING_DOCUMENT','OTHER_DOCUMENT'" +
            "))"
        );
        applyPatch(
            "V75a - add session_id column to telemetry_events",
            "ALTER TABLE telemetry_events ADD COLUMN IF NOT EXISTS session_id VARCHAR(64)"
        );
        applyPatch(
            "V75b - index session_id on telemetry_events",
            "CREATE INDEX IF NOT EXISTS idx_telemetry_events_session_id_time " +
            "ON telemetry_events (session_id, event_time DESC) " +
            "WHERE session_id IS NOT NULL"
        );
        if (isPostgreSql()) {
            withProductionSchemaMigrationLock(() -> {
                patchLedger.initialize();
                applyCatalogPatch("2607190000-call-transcript-summary-base");
                applyCatalogPatch("2607032251-call-summaries-patient-id");
                applyCatalogPatch("2607190001-transcript-archive-base");
                applyCallSessionPatches();
                applyCallSummaryIdempotencyPatch();
                applyTranscriptArchiveStoragePatch();
                applyRetrievalIndexChunkPatches();
                // Fail-closed coverage: every catalog entry is applied exactly once via the ledger.
                applyOutstandingCatalogPatches();
            });
            // Concurrent index builds must not hold the startup advisory lock.
            // Verify only after those indexes exist — mid-lock verify would fail greenfield boots.
            ensureRetrievalConcurrentIndexes();
            verifyRequiredRetrievalSchema();
        } else {
            applyCallSessionPatches();
            applyRetrievalIndexChunkPatches();
            applyH2TranscriptArchiveLifecycleTables();
            applyH2AiHeldItemTables();
        }
        applyUspsMailpiecePatches();
        seedDemoScheduledVisits();
    }

    /** Durable purge fencing and post-commit object deletion for transcript archives. */
    private void applyTranscriptArchiveStoragePatch() {
        applyCatalogPatch("2607191300-transcript-archive-purge");
    }

    /**
     * H2/integration-test parity for Tier-2 HITL hold tables (production applies via catalog).
     */
    private void applyH2AiHeldItemTables() {
        applyRequiredPatch(
            "H2 – ai_held_item",
            "CREATE TABLE IF NOT EXISTS ai_held_item ("
                + "  id UUID PRIMARY KEY,"
                + "  patient_id BIGINT NOT NULL,"
                + "  requester_user_id BIGINT NOT NULL,"
                + "  session_id UUID,"
                + "  audit_id UUID NOT NULL,"
                + "  request_id UUID,"
                + "  source_surface VARCHAR(32) NOT NULL,"
                + "  status VARCHAR(24) NOT NULL,"
                + "  tier SMALLINT NOT NULL DEFAULT 2,"
                + "  trigger_codes CLOB NOT NULL,"
                + "  query_text_hash VARCHAR(64),"
                + "  draft_answer CLOB NOT NULL,"
                + "  final_answer CLOB,"
                + "  citations_json CLOB NOT NULL,"
                + "  validation_findings_json CLOB,"
                + "  reviewer_user_id BIGINT,"
                + "  reviewed_at TIMESTAMP,"
                + "  review_notes VARCHAR(500),"
                + "  delivery_status VARCHAR(32) NOT NULL,"
                + "  expires_at TIMESTAMP,"
                + "  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,"
                + "  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP"
                + ")");
        applyRequiredPatch(
            "H2 – ai_held_item patient status index",
            "CREATE INDEX IF NOT EXISTS idx_held_patient_status "
                + "ON ai_held_item (patient_id, status)");
        applyRequiredPatch(
            "H2 – ai_safety_audit_event",
            "CREATE TABLE IF NOT EXISTS ai_safety_audit_event ("
                + "  id UUID PRIMARY KEY,"
                + "  audit_id UUID NOT NULL,"
                + "  held_item_id UUID,"
                + "  event_type VARCHAR(40) NOT NULL,"
                + "  actor_user_id BIGINT,"
                + "  payload_json CLOB,"
                + "  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP"
                + ")");
    }

    /**
     * H2/integration-test parity for purge fencing tables that production applies via the
     * catalog. Keep definitions aligned with V2607191300 without PostgreSQL-only types.
     */
    private void applyH2TranscriptArchiveLifecycleTables() {
        applyRequiredPatch(
            "H2 – transcript archive lifecycle",
            "CREATE TABLE IF NOT EXISTS call_transcript_archive_lifecycle ("
                + "  call_id VARCHAR(120) PRIMARY KEY,"
                + "  generation BIGINT NOT NULL DEFAULT 0,"
                + "  purged BOOLEAN NOT NULL DEFAULT FALSE,"
                + "  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,"
                + "  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP"
                + ")");
        applyRequiredPatch(
            "H2 – transcript archive deletion outbox",
            "CREATE TABLE IF NOT EXISTS transcript_archive_deletion_outbox ("
                + "  id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,"
                + "  storage_key VARCHAR(512) NOT NULL,"
                + "  attempts INTEGER NOT NULL DEFAULT 0,"
                + "  next_attempt_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,"
                + "  claimed_until TIMESTAMP,"
                + "  claim_token UUID,"
                + "  last_error VARCHAR(1000),"
                + "  dead_lettered_at TIMESTAMP,"
                + "  terminal_error VARCHAR(1000),"
                + "  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,"
                + "  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,"
                + "  CONSTRAINT uq_transcript_archive_deletion_key UNIQUE (storage_key)"
                + ")");
    }

    /** Production parity for Flyway migration V2607190010. */
    private void applyCallSummaryIdempotencyPatch() {
        applyCatalogPatch("2607190010-call-summary-idempotency");
        ensureIndex(
                "V2607190010 – call summary generation idempotency index",
                "uq_call_summary_generation_snapshot",
                false,
                "CREATE UNIQUE INDEX uq_call_summary_generation_snapshot "
                        + "ON call_summaries "
                        + "(call_id, transcript_snapshot_version, model_config_version) "
                        + "WHERE transcript_snapshot_version IS NOT NULL "
                        + "AND model_config_version IS NOT NULL",
                "CREATE UNIQUE INDEX uq_call_summary_generation_snapshot "
                        + "ON call_summaries "
                        + "(call_id, transcript_snapshot_version, model_config_version) "
                        + "WHERE transcript_snapshot_version IS NOT NULL "
                        + "AND model_config_version IS NOT NULL");
        verifyCallSummaryIdempotencySchema();
    }

    /** Durable call authorization and patient ownership (reference migration V2607182230). */
    private void applyCallSessionPatches() {
        applyRequiredPatch(
            "V2607182230a – create call_sessions",
            "CREATE TABLE IF NOT EXISTS call_sessions (" +
            "  id BIGSERIAL PRIMARY KEY," +
            "  call_id VARCHAR(120) NOT NULL," +
            "  patient_id BIGINT NOT NULL REFERENCES patient(id)," +
            "  created_by_user_id BIGINT NOT NULL REFERENCES users(id)," +
            "  scheduled_visit_id BIGINT NULL," +
            "  chime_meeting_id VARCHAR(255) NULL," +
            "  status VARCHAR(24) NOT NULL DEFAULT 'CREATED'," +
            "  ended_at TIMESTAMP NULL," +
            "  created_at TIMESTAMP NOT NULL DEFAULT now()," +
            "  updated_at TIMESTAMP NOT NULL DEFAULT now()," +
            "  CONSTRAINT uq_call_sessions_call_id UNIQUE (call_id)" +
            ")"
        );
        applyRequiredPatch(
            "V2607182230b – create call_participants",
            "CREATE TABLE IF NOT EXISTS call_participants (" +
            "  id BIGSERIAL PRIMARY KEY," +
            "  call_session_id BIGINT NOT NULL REFERENCES call_sessions(id) ON DELETE CASCADE," +
            "  user_id BIGINT NOT NULL REFERENCES users(id)," +
            "  invited_by_user_id BIGINT NULL REFERENCES users(id)," +
            "  status VARCHAR(24) NOT NULL DEFAULT 'INVITED'," +
            "  joined_at TIMESTAMP NULL," +
            "  left_at TIMESTAMP NULL," +
            "  created_at TIMESTAMP NOT NULL DEFAULT now()," +
            "  updated_at TIMESTAMP NOT NULL DEFAULT now()," +
            "  CONSTRAINT uq_call_participants_session_user UNIQUE (call_session_id, user_id)" +
            ")"
        );
        applyRequiredPatch(
            "V2607182230c – call session authorization indexes",
            "CREATE INDEX IF NOT EXISTS idx_call_sessions_patient_id " +
            "  ON call_sessions(patient_id);" +
            "CREATE INDEX IF NOT EXISTS idx_call_sessions_creator " +
            "  ON call_sessions(created_by_user_id);" +
            "CREATE INDEX IF NOT EXISTS idx_call_participants_user " +
            "  ON call_participants(user_id, status);" +
            "CREATE INDEX IF NOT EXISTS idx_call_participants_session " +
            "  ON call_participants(call_session_id, status)"
        );
        if (isPostgreSql()) {
            applyRequiredPatch(
                "V2607182230d – repair call session foreign keys",
                foreignKeyIfMissing("fk_call_sessions_patient", "call_sessions",
                        "patient_id", "patient", "id", "") +
                foreignKeyIfMissing("fk_call_sessions_created_by", "call_sessions",
                        "created_by_user_id", "users", "id", "") +
                foreignKeyIfMissing("fk_call_sessions_scheduled_visit", "call_sessions",
                        "scheduled_visit_id", "scheduled_visits", "id", "") +
                foreignKeyIfMissing("fk_call_participants_session", "call_participants",
                        "call_session_id", "call_sessions", "id", " ON DELETE CASCADE") +
                foreignKeyIfMissing("fk_call_participants_user", "call_participants",
                        "user_id", "users", "id", "") +
                foreignKeyIfMissing("fk_call_participants_invited_by", "call_participants",
                        "invited_by_user_id", "users", "id", "")
            );
            verifyForeignKeyCount(
                    "call session patient", "call_sessions", "patient_id",
                    "patient", "id", 'a', 1);
            verifyForeignKeyCount(
                    "call session creator", "call_sessions", "created_by_user_id",
                    "users", "id", 'a', 1);
            verifyForeignKeyCount(
                    "call session visit", "call_sessions", "scheduled_visit_id",
                    "scheduled_visits", "id", 'a', 1);
            verifyForeignKeyCount(
                    "call participant session", "call_participants", "call_session_id",
                    "call_sessions", "id", 'c', 1);
            verifyForeignKeyCount(
                    "call participant user", "call_participants", "user_id",
                    "users", "id", 'a', 1);
            verifyForeignKeyCount(
                    "call participant inviter", "call_participants", "invited_by_user_id",
                    "users", "id", 'a', 1);
            applyRequiredPatch(
                "V2607190015 – harden call lifecycle statuses",
                "ALTER TABLE call_sessions DROP CONSTRAINT IF EXISTS ck_call_sessions_status;" +
                "ALTER TABLE call_sessions ADD CONSTRAINT ck_call_sessions_status CHECK " +
                "(status IN ('CREATED','ACTIVE','TERMINATING','ENDED','CANCELLED'));" +
                "ALTER TABLE call_participants DROP CONSTRAINT IF EXISTS ck_call_participants_status;" +
                "ALTER TABLE call_participants ADD CONSTRAINT ck_call_participants_status CHECK " +
                "(status IN ('INVITED','JOINED','LEFT','DECLINED','EXPIRED'))"
            );
            applyRequiredSqlResource(
                    "V2607190200 – recoverable call termination",
                    "db/migration/V2607190200__add_recoverable_call_termination.sql");
            ensureIndex(
                    "V2607190200 – call termination retry index",
                    "idx_call_sessions_termination_retry",
                    false,
                    "CREATE INDEX idx_call_sessions_termination_retry "
                            + "ON call_sessions "
                            + "(termination_next_retry_at, termination_lease_until) "
                            + "WHERE status = 'TERMINATING'",
                    "CREATE INDEX idx_call_sessions_termination_retry "
                            + "ON call_sessions "
                            + "(termination_next_retry_at, termination_lease_until) "
                            + "WHERE status = 'TERMINATING'");
            verifyForeignKeyCount(
                    "call termination claimant", "call_sessions",
                    "termination_claimed_by_user_id", "users", "id", 'a', 1);
            verifyCallTerminationSchema();
        }
    }

    /**
     * Tasks 1.5 / 1.6 — pgvector extension and shared Ask AI retrieval index table.
     * Task 4.2 — search_vector trigger + backfill. Task 4.4 — optional partial index for
     * NULL-embedding backfill scans (idx_retrieval_chunk_embedding_null_backfill).
     * Mirrors db/migration reference SQL (applied via SchemaPatchRunner in all envs; not Flyway at ECS deploy).
     */
    private void applyRetrievalIndexChunkPatches() {
        if (!isPostgreSql()) {
            log.info("Skipping PostgreSQL retrieval schema patches for non-PostgreSQL datasource");
            return;
        }
        applyRequiredPatch(
            "V2607071920 – enable pgvector extension",
            "CREATE EXTENSION IF NOT EXISTS vector"
        );
        applyRequiredPatch(
            "V2607071921a – create retrieval_index_chunk table",
            "CREATE TABLE IF NOT EXISTS retrieval_index_chunk (" +
            "  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid()," +
            "  patient_id        BIGINT        NOT NULL," +
            "  record_type       VARCHAR(40)   NOT NULL," +
            "  source_record_id  VARCHAR(120)  NOT NULL," +
            "  source_kind       VARCHAR(40)   NULL," +
            "  chunk_text        TEXT          NOT NULL," +
            "  chunk_metadata    JSONB         NULL," +
            "  search_vector     TSVECTOR      NULL," +
            "  embedding         vector(1536)  NULL," +
            "  indexed_at        TIMESTAMPTZ   NOT NULL DEFAULT now()," +
            "  consent_scope     VARCHAR(40)   NULL," +
            "  citation_replay_after TIMESTAMPTZ NULL," +
            "  citation_replay_attempts INTEGER NOT NULL DEFAULT 0," +
            "  citation_replay_claimed_until TIMESTAMPTZ NULL," +
            "  migration_status VARCHAR(24) NOT NULL DEFAULT 'ACTIVE'" +
            ")"
        );
        applyRequiredPatch(
            "V2607182130 – typed retrieval replay and migration state",
            "ALTER TABLE retrieval_index_chunk ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid();" +
            "ALTER TABLE retrieval_index_chunk ADD COLUMN IF NOT EXISTS patient_id BIGINT;" +
            "ALTER TABLE retrieval_index_chunk ADD COLUMN IF NOT EXISTS record_type VARCHAR(40);" +
            "ALTER TABLE retrieval_index_chunk ADD COLUMN IF NOT EXISTS source_record_id VARCHAR(120);" +
            "ALTER TABLE retrieval_index_chunk ADD COLUMN IF NOT EXISTS source_kind VARCHAR(40) NULL;" +
            "ALTER TABLE retrieval_index_chunk ADD COLUMN IF NOT EXISTS chunk_text TEXT;" +
            "ALTER TABLE retrieval_index_chunk ADD COLUMN IF NOT EXISTS chunk_metadata JSONB NULL;" +
            "ALTER TABLE retrieval_index_chunk ADD COLUMN IF NOT EXISTS search_vector TSVECTOR NULL;" +
            "ALTER TABLE retrieval_index_chunk ADD COLUMN IF NOT EXISTS embedding vector(1536) NULL;" +
            "ALTER TABLE retrieval_index_chunk ADD COLUMN IF NOT EXISTS indexed_at TIMESTAMPTZ DEFAULT now();" +
            "ALTER TABLE retrieval_index_chunk ADD COLUMN IF NOT EXISTS consent_scope VARCHAR(40) NULL;" +
            "ALTER TABLE retrieval_index_chunk " +
            "  ADD COLUMN IF NOT EXISTS citation_replay_after TIMESTAMPTZ NULL;" +
            "ALTER TABLE retrieval_index_chunk " +
            "  ADD COLUMN IF NOT EXISTS citation_replay_attempts INTEGER NOT NULL DEFAULT 0;" +
            "ALTER TABLE retrieval_index_chunk " +
            "  ADD COLUMN IF NOT EXISTS citation_replay_claimed_until TIMESTAMPTZ NULL;" +
            "ALTER TABLE retrieval_index_chunk " +
            "  ADD COLUMN IF NOT EXISTS citation_replay_claim_token UUID NULL;" +
            "ALTER TABLE retrieval_index_chunk " +
            "  ADD COLUMN IF NOT EXISTS migration_status VARCHAR(24) NOT NULL DEFAULT 'ACTIVE';" +
            "UPDATE retrieval_index_chunk SET migration_status = 'QUARANTINED', " +
            "citation_replay_claimed_until = NULL, citation_replay_claim_token = NULL " +
            "WHERE source_kind IS NULL " +
            "AND record_type IN ('CALL_SUMMARY','VISIT_SUMMARY','SUMMARY_ACTION_ITEM'," +
            "'SUMMARY_APPOINTMENT','SUMMARY_CARE_INSTRUCTION','SUMMARY_CONDITION'," +
            "'SUMMARY_SOAP','SUMMARY_CLINICAL_OBSERVATION') AND migration_status = 'ACTIVE'"
        );
        applyRequiredPatch(
            "V2607182105 – add retrieval source ownership discriminator",
            "ALTER TABLE retrieval_index_chunk " +
            "  ADD COLUMN IF NOT EXISTS source_kind VARCHAR(40) NULL"
        );
        applyRequiredPatch(
            "V2607071921b – retrieval_index_chunk patient FK",
            foreignKeyIfMissing(
                    "fk_retrieval_chunk_patient", "retrieval_index_chunk",
                    "patient_id", "patient", "id", "")
        );
        applyRequiredPatch(
            "V2607071921c – retrieval_index_chunk indexes",
            "CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_patient_id " +
            "  ON retrieval_index_chunk (patient_id);" +
            "CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_patient_record_type " +
            "  ON retrieval_index_chunk (patient_id, record_type);" +
            "CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_source " +
            "  ON retrieval_index_chunk (source_record_id, record_type)"
        );
        applyRequiredPatch(
            "V2607071921d – retrieval_index_chunk FTS search_vector trigger",
            "CREATE OR REPLACE FUNCTION retrieval_index_chunk_search_vector_trigger() " +
            "RETURNS TRIGGER AS $$ " +
            "BEGIN " +
            "  NEW.search_vector := to_tsvector('english', COALESCE(NEW.chunk_text, '')); " +
            "  RETURN NEW; " +
            "END; " +
            "$$ LANGUAGE plpgsql;" +
            "DROP TRIGGER IF EXISTS trg_retrieval_index_chunk_search_vector ON retrieval_index_chunk;" +
            "CREATE TRIGGER trg_retrieval_index_chunk_search_vector " +
            "  BEFORE INSERT OR UPDATE OF chunk_text ON retrieval_index_chunk " +
            "  FOR EACH ROW EXECUTE FUNCTION retrieval_index_chunk_search_vector_trigger()"
        );
        applyRequiredPatch(
            "V2607121930 – backfill retrieval_index_chunk search_vector (Task 4.2)",
            "UPDATE retrieval_index_chunk " +
            "SET search_vector = to_tsvector('english', COALESCE(chunk_text, '')) " +
            "WHERE search_vector IS NULL"
        );
        applyRequiredPatch(
            "V2607032257 – create indexing_outbox",
            "CREATE TABLE IF NOT EXISTS indexing_outbox (" +
            "  id BIGSERIAL PRIMARY KEY," +
            "  event_type VARCHAR(64) NOT NULL," +
            "  payload_json TEXT NOT NULL," +
            "  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP," +
            "  processed_at TIMESTAMP NULL," +
            "  attempt_count INTEGER NOT NULL DEFAULT 0," +
            "  last_error TEXT NULL" +
            ");" +
            "CREATE INDEX IF NOT EXISTS idx_indexing_outbox_unprocessed " +
            "  ON indexing_outbox (created_at) WHERE processed_at IS NULL;" +
            "CREATE INDEX IF NOT EXISTS idx_indexing_outbox_event_type " +
            "  ON indexing_outbox (event_type)"
        );
        applyRequiredPatch(
            "V2607122000 – indexing_outbox claimed_at lease column",
            "ALTER TABLE indexing_outbox " +
            "  ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ NULL;" +
            "CREATE INDEX IF NOT EXISTS idx_indexing_outbox_claimable " +
            "  ON indexing_outbox (id ASC) WHERE processed_at IS NULL"
        );
        applyRequiredPatch(
            "V2607161317 – partial index for embedding backfill scans (Task 4.4, optional DBA follow-up)",
            "CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_embedding_null_backfill " +
            "  ON retrieval_index_chunk (indexed_at ASC NULLS LAST, id ASC) " +
            "  WHERE embedding IS NULL " +
            "    AND chunk_text IS NOT NULL " +
            "    AND TRIM(BOTH FROM chunk_text) <> ''"
        );
        applyCatalogPatch("2607191400-summary-citation-replay");
        applyCatalogPatch("2607191500-summary-chunk-ownership-correction");
        ensureIndex(
                "V2607190100 – fair source replay claim index",
                "idx_summary_replay_claim_fair",
                false,
                "CREATE INDEX idx_summary_replay_claim_fair "
                        + "ON summary_citation_replay_source "
                        + "(replay_after ASC NULLS FIRST, attempts ASC, patient_id, "
                        + "source_kind, source_record_id) "
                        + "WHERE migration_status = 'ACTIVE' AND claim_token IS NULL",
                "CREATE INDEX idx_summary_replay_claim_fair "
                        + "ON summary_citation_replay_source "
                        + "(replay_after ASC NULLS FIRST, attempts ASC, patient_id, "
                        + "source_kind, source_record_id) "
                        + "WHERE migration_status = 'ACTIVE' AND claim_token IS NULL");
        ensureIndex(
                "V2607190100 – expired source replay claim index",
                "idx_summary_replay_expired_claim",
                false,
                "CREATE INDEX idx_summary_replay_expired_claim "
                        + "ON summary_citation_replay_source "
                        + "(claimed_until, replay_after ASC NULLS FIRST, patient_id, "
                        + "source_kind, source_record_id) "
                        + "WHERE migration_status = 'ACTIVE' AND claim_token IS NOT NULL",
                "CREATE INDEX idx_summary_replay_expired_claim "
                        + "ON summary_citation_replay_source "
                        + "(claimed_until, replay_after ASC NULLS FIRST, patient_id, "
                        + "source_kind, source_record_id) "
                        + "WHERE migration_status = 'ACTIVE' AND claim_token IS NOT NULL");
        verifyForeignKeyCount(
                "retrieval chunk patient", "retrieval_index_chunk", "patient_id",
                "patient", "id", 'a', 1);
        verifyForeignKeyCount(
                "summary replay patient", "summary_citation_replay_source", "patient_id",
                "patient", "id", 'a', 1);
        // Full retrieval schema verify (including concurrent indexes) runs after unlock.
    }

    /**
     * Tasks 3.14.5 / 3.14.6 — canonical USPS mailpiece table + importance columns.
     * Mirrors V2607142100 and V2607142130. Prod uses SchemaPatchRunner (Flyway off);
     * Task 3.14.5 (#122) — canonical USPS mailpiece table.
     * Mirrors db/migration V2607142100. Prod uses SchemaPatchRunner (Flyway off);
     * entity stores bare Long patientId (no @ManyToOne), so FK must be applied here.
     */
    private void applyUspsMailpiecePatches() {
        applyPatch(
            "V2607142100a – create usps_mailpiece table",
            "CREATE TABLE IF NOT EXISTS usps_mailpiece (" +
            "  id              BIGSERIAL       PRIMARY KEY," +
            "  patient_id      BIGINT          NOT NULL," +
            "  user_id         VARCHAR(120)    NULL," +
            "  source_key      VARCHAR(160)    NOT NULL," +
            "  external_id     VARCHAR(120)    NULL," +
            "  sender          VARCHAR(512)    NULL," +
            "  summary         TEXT            NULL," +
            "  image_ref       VARCHAR(1024)   NULL," +
            "  received_at     TIMESTAMPTZ     NULL," +
            "  digest_date     DATE            NULL," +
            "  ocr_text        TEXT            NULL," +
            "  content_hash    VARCHAR(80)     NOT NULL," +
            "  consent_scope   VARCHAR(40)     NULL," +
            "  created_at      TIMESTAMPTZ     NOT NULL DEFAULT now()," +
            "  updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now()" +
            ")"
        );
        applyPatch(
            "V2607142100b – usps_mailpiece patient FK",
            "DO $$ BEGIN " +
            "  ALTER TABLE usps_mailpiece " +
            "    ADD CONSTRAINT fk_usps_mailpiece_patient " +
            "    FOREIGN KEY (patient_id) REFERENCES patient (id); " +
            "EXCEPTION WHEN duplicate_object THEN NULL; END $$"
        );
        applyPatch(
            "V2607142100c – usps_mailpiece unique (patient_id, source_key)",
            "DO $$ BEGIN " +
            "  ALTER TABLE usps_mailpiece " +
            "    ADD CONSTRAINT uq_usps_mailpiece_patient_source_key " +
            "    UNIQUE (patient_id, source_key); " +
            "EXCEPTION WHEN duplicate_object THEN NULL; END $$"
        );
        applyPatch(
            "V2607142100d – usps_mailpiece indexes",
            "CREATE INDEX IF NOT EXISTS idx_usps_mailpiece_patient_digest_date " +
            "  ON usps_mailpiece (patient_id, digest_date);" +
            "CREATE INDEX IF NOT EXISTS idx_usps_mailpiece_patient_content_hash " +
            "  ON usps_mailpiece (patient_id, content_hash)"
        );
        applyPatch(
            "V2607142130a – usps_mailpiece importance classification columns",
            "ALTER TABLE usps_mailpiece " +
            "  ADD COLUMN IF NOT EXISTS importance_level VARCHAR(16) NULL;" +
            "ALTER TABLE usps_mailpiece " +
            "  ADD COLUMN IF NOT EXISTS importance_confidence NUMERIC(3, 2) NULL;" +
            "ALTER TABLE usps_mailpiece " +
            "  ADD COLUMN IF NOT EXISTS classification_method VARCHAR(32) NULL;" +
            "ALTER TABLE usps_mailpiece " +
            "  ADD COLUMN IF NOT EXISTS classification_engine VARCHAR(128) NULL;" +
            "ALTER TABLE usps_mailpiece " +
            "  ADD COLUMN IF NOT EXISTS importance_reasoning TEXT NULL;" +
            "ALTER TABLE usps_mailpiece " +
            "  ADD COLUMN IF NOT EXISTS importance_category VARCHAR(40) NULL;" +
            "ALTER TABLE usps_mailpiece " +
            "  ADD COLUMN IF NOT EXISTS classified_at TIMESTAMPTZ NULL"
        );
        applyPatch(
            "V2607142130b – usps_mailpiece importance index",
            "CREATE INDEX IF NOT EXISTS idx_usps_mailpiece_patient_importance " +
            "  ON usps_mailpiece (patient_id, importance_level, digest_date)"
        );
    }

    /**
     * Inserts demo scheduled visits for the demo accounts if the table is empty.
     * Uses sub-selects on email so IDs don't need to be hardcoded.
     * Safe to run on every restart — the WHERE NOT EXISTS guard makes it idempotent.
     */
    private void seedDemoScheduledVisits() {
        String sql =
            "INSERT INTO scheduled_visits " +
            "  (caregiver_id, patient_id, service_type, scheduled_date, scheduled_time, " +
            "   duration_minutes, priority, status, created_at, updated_at) " +
            "SELECT " +
            "  (SELECT c.id FROM caregiver c JOIN users u ON c.user_id = u.id WHERE u.email = 'caregiver@careconnect.com' LIMIT 1), " +
            "  (SELECT p.id FROM patient p JOIN users u ON p.user_id = u.id WHERE u.email = 'patient@careconnect.com' LIMIT 1), " +
            "  svc, sdate, stime, dur, 'Normal', 'Scheduled', NOW(), NOW() " +
            "FROM (VALUES " +
            "  ('Medication Management', CURRENT_DATE + 1, TIME '09:00:00', 45) " +
            ") AS v(svc, sdate, stime, dur) " +
            "WHERE NOT EXISTS (SELECT 1 FROM scheduled_visits LIMIT 1)";

        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement()) {
            conn.setAutoCommit(true);
            // Remove any previously seeded demo visits for the demo caregiver account
            stmt.executeUpdate(
                "DELETE FROM scheduled_visits WHERE caregiver_id = " +
                "(SELECT c.id FROM caregiver c JOIN users u ON c.user_id = u.id " +
                " WHERE u.email = 'caregiver@careconnect.com' LIMIT 1)"
            );
            int rows = stmt.executeUpdate(sql);
            if (rows > 0) {
                log.info("Demo scheduled visits seeded: {} rows", rows);
            } else {
                log.warn("Demo scheduled visits seed inserted 0 rows — caregiver or patient account may be missing");
            }
        } catch (Exception e) {
            log.warn("Could not seed demo scheduled visits: {}", e.getMessage());
        }
    }

    private void applyPatch(String name, String sql) {
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement()) {
            conn.setAutoCommit(true);   // DDL must commit; HikariCP pool default is auto-commit=false
            stmt.execute(sql);
            log.info("Schema patch applied: {}", name);
        } catch (Exception e) {
            // PostgreSQL raises 42703 / 42P16 when the column constraint is already absent —
            // treat that as success; log anything else as a warning.
            String msg = e.getMessage() != null ? e.getMessage() : "";
            if (msg.contains("42P16") || msg.contains("already") || msg.contains("does not exist")) {
                log.debug("Schema patch skipped (already applied): {}", name);
            } else {
                log.warn("Schema patch '{}' could not be applied: {}", name, msg);
            }
        }
    }

    private void applyRequiredPatch(String name, String sql) {
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement()) {
            conn.setAutoCommit(true);
            configureDdlTimeouts(stmt);
            stmt.execute(sql);
            log.info("Required schema patch applied: {}", name);
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Required schema patch could not be applied: " + name,
                    e);
        }
    }

    /**
     * Builds large retrieval indexes outside the production migration advisory lock so peer
     * nodes are not blocked beyond the lock wait timeout during CONCURRENTLY DDL.
     */
    private void ensureRetrievalConcurrentIndexes() {
        ensureConcurrentIndex(
            "V2607182130b – concurrent retrieval replay index",
            "idx_retrieval_summary_replay",
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_retrieval_summary_replay " +
            "  ON retrieval_index_chunk " +
            "    (citation_replay_after, patient_id, source_record_id) " +
            "  WHERE migration_status = 'ACTIVE'",
            "CREATE INDEX idx_retrieval_summary_replay "
                    + "ON retrieval_index_chunk "
                    + "(citation_replay_after, patient_id, source_record_id) "
                    + "WHERE migration_status = 'ACTIVE'"
        );
        ensureConcurrentIndex(
            "V2607182130c – concurrent retrieval replay claim index",
            "idx_retrieval_summary_replay_claim",
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_retrieval_summary_replay_claim " +
            "  ON retrieval_index_chunk " +
            "    (citation_replay_claimed_until, citation_replay_after, " +
            "     patient_id, source_record_id) " +
            "  WHERE migration_status = 'ACTIVE'",
            "CREATE INDEX idx_retrieval_summary_replay_claim "
                    + "ON retrieval_index_chunk "
                    + "(citation_replay_claimed_until, citation_replay_after, "
                    + "patient_id, source_record_id) "
                    + "WHERE migration_status = 'ACTIVE'"
        );
        ensureConcurrentIndex(
            "V2607182105b – concurrent retrieval source identity index",
            "idx_retrieval_chunk_source_identity",
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_retrieval_chunk_source_identity " +
            "  ON retrieval_index_chunk (patient_id, source_kind, source_record_id)",
            "CREATE INDEX idx_retrieval_chunk_source_identity "
                    + "ON retrieval_index_chunk (patient_id, source_kind, source_record_id)"
        );
        ensureConcurrentIndex(
            "V2607071921c – concurrent retrieval FTS index",
            "idx_retrieval_chunk_fts",
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_retrieval_chunk_fts " +
            "ON retrieval_index_chunk USING GIN (search_vector)",
            "CREATE INDEX idx_retrieval_chunk_fts "
                    + "ON retrieval_index_chunk USING GIN (search_vector)"
        );
        ensureConcurrentIndex(
            "V2607071921c – concurrent retrieval embedding index",
            "idx_retrieval_chunk_embedding",
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_retrieval_chunk_embedding " +
            "ON retrieval_index_chunk USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)",
            "CREATE INDEX idx_retrieval_chunk_embedding "
                    + "ON retrieval_index_chunk USING ivfflat "
                    + "(embedding vector_cosine_ops) WITH (lists = 100)"
        );
    }

    private void ensureConcurrentIndex(
            final String name,
            final String indexName,
            final String createSql,
            final String expectedDefinition) {
        ensureIndex(name, indexName, true, createSql, expectedDefinition);
    }

    private void ensureIndex(
            final String name,
            final String indexName,
            final boolean concurrent,
            final String createSql,
            final String expectedDefinition) {
        final String statusSql = """
                SELECT i.indisvalid AND i.indisready, pg_get_indexdef(i.indexrelid),
                       current_schema()
                FROM pg_index i
                JOIN pg_class c ON c.oid = i.indexrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE c.relname = '%s'
                  AND n.nspname = current_schema()
                """.formatted(indexName.replace("'", "''"));
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement()) {
            conn.setAutoCommit(true);
            configureDdlTimeouts(stmt);
            boolean exists = false;
            boolean healthy = false;
            try (var result = stmt.executeQuery(statusSql)) {
                if (result.next()) {
                    exists = true;
                    healthy = result.getBoolean(1)
                            && normalizeIndexDefinition(
                                    result.getString(2), result.getString(3))
                                    .equals(normalizeIndexDefinition(
                                            expectedDefinition, result.getString(3)));
                }
            }
            if (exists && !healthy) {
                log.warn("Rebuilding invalid or drifted schema index: {}", indexName);
                stmt.execute("DROP INDEX " + (concurrent ? "CONCURRENTLY " : "")
                        + "IF EXISTS " + indexName);
            }
            if (!healthy) {
                stmt.execute(createSql);
            }
            try (var result = stmt.executeQuery(statusSql)) {
                if (!result.next()
                        || !result.getBoolean(1)
                        || !normalizeIndexDefinition(result.getString(2), result.getString(3))
                                .equals(normalizeIndexDefinition(
                                        expectedDefinition, result.getString(3)))) {
                    throw new IllegalStateException(
                            "Index is not ready and valid: " + indexName);
                }
            }
            log.info("Required concurrent index ready: {}", name);
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Required concurrent index could not be prepared: " + name, e);
        }
    }

    static String normalizeIndexDefinition(final String definition, final String schema) {
        String normalized = definition.toLowerCase(Locale.ROOT);
        normalized = normalized.replace("\"", "");
        normalized = normalized.replace(" concurrently", "");
        normalized = normalized.replace(" if not exists", "");
        normalized = normalized.replace(" using btree", "");
        normalized = normalized.replace(" asc", "");
        if (schema != null && !schema.isBlank()) {
            normalized = normalized.replace(schema.toLowerCase(Locale.ROOT) + ".", "");
        }
        normalized = POSTGRES_TEXT_CAST.matcher(normalized).replaceAll("");
        normalized = QUOTED_NUMBER.matcher(normalized).replaceAll("$1");
        return normalized.replaceAll("[\\s()]+", "");
    }

    private void applyRequiredSqlResource(final String name, final String path) {
        try (Connection conn = dataSource.getConnection()) {
            conn.setAutoCommit(false);
            try (Statement stmt = conn.createStatement()) {
                configureDdlTimeouts(stmt);
            }
            try {
                ScriptUtils.executeSqlScript(conn, new ClassPathResource(path));
                conn.commit();
                log.info("Required schema patch applied: {}", name);
            } catch (Exception e) {
                try {
                    conn.rollback();
                } catch (Exception rollbackFailure) {
                    e.addSuppressed(rollbackFailure);
                }
                throw e;
            }
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Required schema patch could not be applied: " + name, e);
        }
    }

    static void configureDdlTimeouts(final Statement stmt) throws Exception {
        final String database = stmt.getConnection().getMetaData().getDatabaseProductName();
        if (database != null
                && database.toLowerCase(java.util.Locale.ROOT).contains("postgresql")) {
            stmt.execute("SET lock_timeout = '5s'");
            stmt.execute("SET statement_timeout = '5min'");
        }
    }

    private void withProductionSchemaMigrationLock(final Runnable work) {
        // Peers must outwait locked DDL (statement_timeout up to 5min) on rolling deploys.
        final long deadline = System.nanoTime()
                + TimeUnit.MINUTES.toNanos(10);
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement()) {
            conn.setAutoCommit(true);
            configureDdlTimeouts(stmt);
            boolean acquired = false;
            while (System.nanoTime() < deadline) {
                try (var result = stmt.executeQuery(
                        "SELECT pg_try_advisory_lock(" + PRODUCTION_SCHEMA_LOCK + ")")) {
                    acquired = result.next() && result.getBoolean(1);
                }
                if (acquired) {
                    break;
                }
                Thread.sleep(200L);
            }
            if (!acquired) {
                throw new IllegalStateException(
                        "Timed out waiting for production schema migration lock");
            }
            try {
                work.run();
            } finally {
                stmt.executeQuery(
                        "SELECT pg_advisory_unlock(" + PRODUCTION_SCHEMA_LOCK + ")")
                        .close();
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(
                    "Interrupted waiting for production schema migration lock", e);
        } catch (Exception e) {
            if (e instanceof IllegalStateException illegalState) {
                throw illegalState;
            }
            throw new IllegalStateException(
                    "Unable to coordinate production schema migration", e);
        }
    }

    private static String foreignKeyIfMissing(
            final String constraint,
            final String table,
            final String column,
            final String referencedTable,
            final String referencedColumn,
            final String suffix) {
        return "DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint c " +
                "WHERE c.conrelid = '" + table + "'::regclass " +
                "AND c.confrelid = '" + referencedTable + "'::regclass " +
                "AND c.contype = 'f' " +
                "AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute " +
                "WHERE attrelid = '" + table + "'::regclass AND attname = '" +
                column + "')]::smallint[] " +
                "AND c.confkey = ARRAY[(SELECT attnum FROM pg_attribute " +
                "WHERE attrelid = '" + referencedTable + "'::regclass AND attname = '" +
                referencedColumn + "')]::smallint[] " +
                "AND c.confdeltype = '" + (suffix.contains("CASCADE") ? "c" : "a") +
                "') THEN " +
                "ALTER TABLE " + table + " ADD CONSTRAINT " + constraint +
                " FOREIGN KEY (" + column + ") REFERENCES " + referencedTable +
                " (" + referencedColumn + ")" + suffix + "; END IF; END $$;";
    }

    private void verifyForeignKeyCount(
            final String group,
            final String table,
            final String column,
            final String referencedTable,
            final String referencedColumn,
            final char deleteAction,
            final int expected) {
        final String sql = "SELECT COUNT(*) FROM pg_constraint c "
                + "WHERE c.conrelid = '" + table + "'::regclass "
                + "AND c.confrelid = '" + referencedTable + "'::regclass "
                + "AND c.contype = 'f' AND c.convalidated "
                + "AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute "
                + "WHERE attrelid = '" + table + "'::regclass AND attname = '"
                + column + "')]::smallint[] "
                + "AND c.confkey = ARRAY[(SELECT attnum FROM pg_attribute "
                + "WHERE attrelid = '" + referencedTable + "'::regclass AND attname = '"
                + referencedColumn + "')]::smallint[] "
                + "AND c.confdeltype = '" + deleteAction + "'";
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             var result = stmt.executeQuery(sql)) {
            if (!result.next() || result.getInt(1) != expected) {
                throw new IllegalStateException(
                        "Required " + group + " foreign key count verification failed");
            }
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Required " + group + " foreign key count verification failed", e);
        }
    }

    private void verifyCallTerminationSchema() {
        final String sql = """
                SELECT
                  (SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = current_schema()
                     AND table_name = 'call_sessions'
                     AND column_name IN (
                       'termination_claim_id',
                       'termination_claimed_by_user_id',
                       'termination_lease_until',
                       'termination_attempt_count',
                       'termination_next_retry_at',
                       'termination_last_error',
                       'termination_notify_user_ids')) AS column_count,
                  (SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = current_schema()
                     AND table_name = 'call_sessions'
                     AND column_name = 'termination_attempt_count'
                     AND is_nullable = 'NO'
                     AND column_default LIKE '%0%') AS attempt_default_count,
                  (SELECT COUNT(*) FROM pg_constraint c
                   WHERE c.conrelid = 'call_sessions'::regclass
                     AND c.contype = 'c'
                     AND c.convalidated
                     AND pg_get_constraintdef(c.oid)
                       LIKE '%termination_attempt_count >= 0%') AS check_count,
                  (SELECT COUNT(*) FROM pg_index i
                   JOIN pg_class idx ON idx.oid = i.indexrelid
                   JOIN pg_class tbl ON tbl.oid = i.indrelid
                   JOIN pg_namespace n ON n.oid = tbl.relnamespace
                   WHERE n.nspname = current_schema()
                     AND tbl.relname = 'call_sessions'
                     AND idx.relname = 'idx_call_sessions_termination_retry'
                     AND i.indisvalid AND i.indisready
                     AND POSITION(
                       '(termination_next_retry_at, termination_lease_until)'
                       IN pg_get_indexdef(i.indexrelid)) > 0
                     AND POSITION(
                       'status = ''TERMINATING'''
                       IN pg_get_indexdef(i.indexrelid)) > 0) AS index_count
                """;
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             var result = stmt.executeQuery(sql)) {
            if (!result.next()
                    || result.getInt("column_count") != 7
                    || result.getInt("attempt_default_count") != 1
                    || result.getInt("check_count") != 1
                    || result.getInt("index_count") != 1) {
                throw new IllegalStateException(
                        "Required recoverable call termination schema verification failed");
            }
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Required recoverable call termination schema verification failed", e);
        }
    }

    private void verifyCallSummaryIdempotencySchema() {
        final String sql = """
                SELECT
                  (SELECT COUNT(*) FROM information_schema.columns
                   WHERE table_schema = current_schema()
                     AND table_name = 'call_summaries'
                     AND data_type = 'character varying'
                     AND is_nullable = 'YES'
                     AND (
                       (column_name = 'transcript_snapshot_version'
                         AND character_maximum_length = 80)
                       OR
                       (column_name = 'model_config_version'
                         AND character_maximum_length = 160)
                     )) AS column_count,
                  (SELECT COUNT(*) FROM pg_index i
                   JOIN pg_class idx ON idx.oid = i.indexrelid
                   JOIN pg_class tbl ON tbl.oid = i.indrelid
                   JOIN pg_namespace n ON n.oid = tbl.relnamespace
                   WHERE n.nspname = current_schema()
                     AND tbl.relname = 'call_summaries'
                     AND idx.relname = 'uq_call_summary_generation_snapshot'
                     AND i.indisunique AND i.indisvalid AND i.indisready
                     AND POSITION(
                       '(call_id, transcript_snapshot_version, model_config_version)'
                       IN pg_get_indexdef(i.indexrelid)) > 0
                     AND POSITION(
                       'transcript_snapshot_version IS NOT NULL'
                       IN pg_get_indexdef(i.indexrelid)) > 0
                     AND POSITION(
                       'model_config_version IS NOT NULL'
                       IN pg_get_indexdef(i.indexrelid)) > 0) AS index_count
                """;
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             var result = stmt.executeQuery(sql)) {
            if (!result.next()
                    || result.getInt("column_count") != 2
                    || result.getInt("index_count") != 1) {
                throw new IllegalStateException(
                        "Required call summary idempotency schema verification failed");
            }
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Required call summary idempotency schema verification failed", e);
        }
    }

    private void verifyRequiredRetrievalSchema() {
        final String sql = """
                WITH expected_columns(table_name, column_name, data_type, not_null, default_part) AS (
                  VALUES
                    ('retrieval_index_chunk','id','uuid',true,'gen_random_uuid()'),
                    ('retrieval_index_chunk','patient_id','bigint',true,NULL),
                    ('retrieval_index_chunk','record_type','character varying(40)',true,NULL),
                    ('retrieval_index_chunk','source_record_id','character varying(120)',true,NULL),
                    ('retrieval_index_chunk','source_kind','character varying(40)',false,NULL),
                    ('retrieval_index_chunk','chunk_text','text',true,NULL),
                    ('retrieval_index_chunk','chunk_metadata','jsonb',false,NULL),
                    ('retrieval_index_chunk','search_vector','tsvector',false,NULL),
                    ('retrieval_index_chunk','embedding','vector(1536)',false,NULL),
                    ('retrieval_index_chunk','indexed_at','timestamp with time zone',true,'now()'),
                    ('retrieval_index_chunk','consent_scope','character varying(40)',false,NULL),
                    ('retrieval_index_chunk','citation_replay_after','timestamp with time zone',false,NULL),
                    ('retrieval_index_chunk','citation_replay_attempts','integer',true,'0'),
                    ('retrieval_index_chunk','citation_replay_claimed_until','timestamp with time zone',false,NULL),
                    ('retrieval_index_chunk','citation_replay_claim_token','uuid',false,NULL),
                    ('retrieval_index_chunk','migration_status','character varying(24)',true,'''ACTIVE'''),
                    ('summary_citation_replay_source','patient_id','bigint',true,NULL),
                    ('summary_citation_replay_source','source_kind','character varying(40)',true,NULL),
                    ('summary_citation_replay_source','source_record_id','character varying(120)',true,NULL),
                    ('summary_citation_replay_source','replay_after','timestamp with time zone',false,NULL),
                    ('summary_citation_replay_source','attempts','integer',true,'0'),
                    ('summary_citation_replay_source','claimed_until','timestamp with time zone',false,NULL),
                    ('summary_citation_replay_source','claim_token','uuid',false,NULL),
                    ('summary_citation_replay_source','migration_status','character varying(24)',true,'''ACTIVE'''),
                    ('summary_citation_replay_source','created_at','timestamp with time zone',true,'now()'),
                    ('summary_citation_replay_source','updated_at','timestamp with time zone',true,'now()')
                ),
                actual_columns AS (
                  SELECT t.relname AS table_name, a.attname AS column_name,
                         format_type(a.atttypid, a.atttypmod) AS data_type,
                         a.attnotnull AS not_null,
                         pg_get_expr(d.adbin, d.adrelid) AS default_expression
                  FROM pg_attribute a
                  JOIN pg_class t ON t.oid = a.attrelid
                  JOIN pg_namespace n ON n.oid = t.relnamespace
                  LEFT JOIN pg_attrdef d
                    ON d.adrelid = a.attrelid AND d.adnum = a.attnum
                  WHERE n.nspname = current_schema()
                    AND t.relname IN (
                      'retrieval_index_chunk','summary_citation_replay_source')
                    AND a.attnum > 0 AND NOT a.attisdropped
                ),
                expected_constraints(table_name, constraint_name, constraint_type, definition_part) AS (
                  VALUES
                    ('retrieval_index_chunk','retrieval_index_chunk_pkey','p','PRIMARY KEY (id)'),
                    ('retrieval_index_chunk',NULL,'f','FOREIGN KEY (patient_id) REFERENCES patient(id)'),
                    ('retrieval_index_chunk','ck_retrieval_migration_status','c','migration_status'),
                    ('retrieval_index_chunk','ck_retrieval_replay_attempts','c','citation_replay_attempts >= 0'),
                    ('retrieval_index_chunk','ck_retrieval_source_kind','c','source_kind'),
                    ('retrieval_index_chunk','ck_retrieval_replay_lease_token','c','citation_replay_claimed_until'),
                    ('summary_citation_replay_source','pk_summary_citation_replay_source','p','PRIMARY KEY (patient_id, source_kind, source_record_id)'),
                    ('summary_citation_replay_source',NULL,'f','FOREIGN KEY (patient_id) REFERENCES patient(id)'),
                    ('summary_citation_replay_source','ck_summary_replay_status','c','migration_status'),
                    ('summary_citation_replay_source','ck_summary_replay_attempts','c','attempts >= 0'),
                    ('summary_citation_replay_source','ck_summary_replay_source_kind','c','source_kind'),
                    ('summary_citation_replay_source','ck_summary_replay_lease_token','c','claimed_until')
                ),
                expected_indexes(index_name, table_name, definition_part) AS (
                  VALUES
                    ('idx_retrieval_chunk_fts','retrieval_index_chunk','USING gin (search_vector)'),
                    ('idx_retrieval_chunk_embedding','retrieval_index_chunk','vector_cosine_ops'),
                    ('idx_retrieval_chunk_source_identity','retrieval_index_chunk','patient_id, source_kind, source_record_id'),
                    ('idx_summary_replay_claim_fair','summary_citation_replay_source','replay_after'),
                    ('idx_summary_replay_expired_claim','summary_citation_replay_source','claimed_until')
                )
                SELECT
                  (SELECT COUNT(*)
                   FROM expected_columns e
                   LEFT JOIN actual_columns a USING (table_name, column_name)
                   WHERE a.column_name IS NULL
                      OR a.data_type <> e.data_type
                      OR a.not_null <> e.not_null
                      OR (e.default_part IS NOT NULL AND
                          POSITION(e.default_part IN COALESCE(a.default_expression,'')) = 0)
                  ) AS column_issues,
                  (SELECT COUNT(*)
                   FROM expected_constraints e
                   WHERE NOT EXISTS (
                     SELECT 1
                     FROM pg_constraint c
                     JOIN pg_class t ON t.oid = c.conrelid
                     JOIN pg_namespace n ON n.oid = t.relnamespace
                     WHERE n.nspname = current_schema()
                       AND t.relname = e.table_name
                       AND (e.constraint_name IS NULL OR c.conname = e.constraint_name)
                       AND c.contype::text = e.constraint_type
                       AND c.convalidated
                       AND POSITION(e.definition_part IN pg_get_constraintdef(c.oid)) > 0
                   )) AS constraint_issues,
                  (SELECT COUNT(*)
                   FROM expected_indexes e
                   WHERE NOT EXISTS (
                     SELECT 1
                     FROM pg_index i
                     JOIN pg_class idx ON idx.oid = i.indexrelid
                     JOIN pg_class tbl ON tbl.oid = i.indrelid
                     JOIN pg_namespace n ON n.oid = tbl.relnamespace
                     WHERE n.nspname = current_schema()
                       AND tbl.relname = e.table_name
                       AND idx.relname = e.index_name
                       AND i.indisvalid AND i.indisready
                       AND POSITION(e.definition_part IN pg_get_indexdef(i.indexrelid)) > 0
                   )) AS index_issues,
                  (SELECT COUNT(*)
                   FROM pg_trigger tr
                   JOIN pg_class t ON t.oid = tr.tgrelid
                   JOIN pg_namespace n ON n.oid = t.relnamespace
                   WHERE n.nspname = current_schema()
                     AND t.relname = 'retrieval_index_chunk'
                     AND tr.tgname = 'trg_retrieval_index_chunk_search_vector'
                     AND tr.tgenabled <> 'D'
                     AND NOT tr.tgisinternal) AS trigger_count
                """;
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             var result = stmt.executeQuery(sql)) {
            if (!result.next()
                    || result.getInt("column_issues") != 0
                    || result.getInt("constraint_issues") != 0
                    || result.getInt("index_issues") != 0
                    || result.getInt("trigger_count") != 1) {
                throw new IllegalStateException(
                        "Required retrieval schema verification failed");
            }
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Required retrieval schema verification failed",
                    e);
        }
    }

    private boolean isPostgreSql() {
        try (Connection conn = dataSource.getConnection()) {
            return conn.getMetaData()
                    .getDatabaseProductName()
                    .toLowerCase(java.util.Locale.ROOT)
                    .contains("postgresql");
        } catch (Exception e) {
            throw new IllegalStateException("Unable to identify database for schema patches", e);
        }
    }

    private void applyCatalogPatch(final String patchId) {
        patchLedger.apply(SchemaPatchCatalog.patch(patchId));
    }

    /**
     * Applies every catalog patch in declaration order. Already-ledgered entries are no-ops, so
     * this closes the gap when new catalog IDs are registered but not yet called earlier in
     * {@link #run()}.
     */
    void applyOutstandingCatalogPatches() {
        for (final SchemaPatchLedger.Patch patch : SchemaPatchCatalog.PATCHES) {
            applyCatalogPatch(patch.id());
        }
    }

    /** Catalog IDs the runner guarantees to apply under the production migration lock. */
    static List<String> catalogPatchIdsAppliedByRunner() {
        return SchemaPatchCatalog.PATCHES.stream().map(SchemaPatchLedger.Patch::id).toList();
    }

    private static String applicationVersion() {
        final Package applicationPackage = SchemaPatchRunner.class.getPackage();
        final String version = applicationPackage.getImplementationVersion();
        return version == null || version.isBlank() ? "development" : version;
    }
}
