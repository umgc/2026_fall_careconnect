package com.careconnect.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.Statement;

/**
 * Applies one-time schema patches via plain JDBC at startup.
 * Runs before JPA initialisation (@Order(1)) and has no JPA dependency,
 * so it avoids coupling schema changes to Flyway/JPA startup order.
 *
 * Each patch is idempotent: safe to execute on every restart.
 */
@Slf4j
@Component
@Order(1)
public class SchemaPatchRunner implements CommandLineRunner {

    private final DataSource dataSource;

    public SchemaPatchRunner(DataSource dataSource) {
        this.dataSource = dataSource;
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
            "V75a � add session_id column to telemetry_events",
            "ALTER TABLE telemetry_events ADD COLUMN IF NOT EXISTS session_id VARCHAR(64)"
        );
        applyPatch(
            "V75b � index session_id on telemetry_events",
            "CREATE INDEX IF NOT EXISTS idx_telemetry_events_session_id_time " +
            "ON telemetry_events (session_id, event_time DESC) " +
            "WHERE session_id IS NOT NULL"
        );
        applyCallSessionPatches();
        applyRetrievalIndexChunkPatches();
        applyUspsMailpiecePatches();
        seedDemoScheduledVisits();
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
                foreignKeyIfMissing("fk_call_participants_session", "call_participants",
                        "call_session_id", "call_sessions", "id", " ON DELETE CASCADE") +
                foreignKeyIfMissing("fk_call_participants_user", "call_participants",
                        "user_id", "users", "id", "") +
                foreignKeyIfMissing("fk_call_participants_invited_by", "call_participants",
                        "invited_by_user_id", "users", "id", "")
            );
            verifyConstraints("call session", 5,
                    "fk_call_sessions_patient", "fk_call_sessions_created_by",
                    "fk_call_participants_session", "fk_call_participants_user",
                    "fk_call_participants_invited_by");
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
        ensureConcurrentIndex(
            "V2607182130b – concurrent retrieval replay index",
            "idx_retrieval_summary_replay",
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_retrieval_summary_replay " +
            "  ON retrieval_index_chunk " +
            "    (citation_replay_after, patient_id, source_record_id) " +
            "  WHERE migration_status = 'ACTIVE'"
        );
        ensureConcurrentIndex(
            "V2607182130c – concurrent retrieval replay claim index",
            "idx_retrieval_summary_replay_claim",
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_retrieval_summary_replay_claim " +
            "  ON retrieval_index_chunk " +
            "    (citation_replay_claimed_until, citation_replay_after, " +
            "     patient_id, source_record_id) " +
            "  WHERE migration_status = 'ACTIVE'"
        );
        applyRequiredPatch(
            "V2607182105 – add retrieval source ownership discriminator",
            "ALTER TABLE retrieval_index_chunk " +
            "  ADD COLUMN IF NOT EXISTS source_kind VARCHAR(40) NULL"
        );
        ensureConcurrentIndex(
            "V2607182105b – concurrent retrieval source identity index",
            "idx_retrieval_chunk_source_identity",
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_retrieval_chunk_source_identity " +
            "  ON retrieval_index_chunk (patient_id, source_kind, source_record_id)"
        );
        applyRequiredPatch(
            "V2607071921b – retrieval_index_chunk patient FK",
            "DO $$ BEGIN " +
            "  ALTER TABLE retrieval_index_chunk " +
            "    ADD CONSTRAINT fk_retrieval_chunk_patient " +
            "    FOREIGN KEY (patient_id) REFERENCES patient (id); " +
            "EXCEPTION WHEN duplicate_object THEN NULL; END $$"
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
        ensureConcurrentIndex(
            "V2607071921c – concurrent retrieval FTS index",
            "idx_retrieval_chunk_fts",
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_retrieval_chunk_fts " +
            "ON retrieval_index_chunk USING GIN (search_vector)"
        );
        ensureConcurrentIndex(
            "V2607071921c – concurrent retrieval embedding index",
            "idx_retrieval_chunk_embedding",
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_retrieval_chunk_embedding " +
            "ON retrieval_index_chunk USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)"
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
        verifyRequiredRetrievalSchema();
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
            stmt.execute(sql);
            log.info("Required schema patch applied: {}", name);
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Required schema patch could not be applied: " + name,
                    e);
        }
    }

    private void ensureConcurrentIndex(
            final String name,
            final String indexName,
            final String createSql) {
        final String statusSql = """
                SELECT i.indisvalid AND i.indisready
                FROM pg_index i
                JOIN pg_class c ON c.oid = i.indexrelid
                WHERE c.relname = '%s'
                """.formatted(indexName.replace("'", "''"));
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement()) {
            conn.setAutoCommit(true);
            boolean exists = false;
            boolean healthy = false;
            try (var result = stmt.executeQuery(statusSql)) {
                if (result.next()) {
                    exists = true;
                    healthy = result.getBoolean(1);
                }
            }
            if (exists && !healthy) {
                log.warn("Rebuilding invalid retrieval index: {}", indexName);
                stmt.execute("DROP INDEX CONCURRENTLY IF EXISTS " + indexName);
            }
            if (!healthy) {
                stmt.execute(createSql);
            }
            try (var result = stmt.executeQuery(statusSql)) {
                if (!result.next() || !result.getBoolean(1)) {
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

    private static String foreignKeyIfMissing(
            final String constraint,
            final String table,
            final String column,
            final String referencedTable,
            final String referencedColumn,
            final String suffix) {
        return "DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint " +
                "WHERE conname = '" + constraint + "' AND contype = 'f') THEN " +
                "ALTER TABLE " + table + " ADD CONSTRAINT " + constraint +
                " FOREIGN KEY (" + column + ") REFERENCES " + referencedTable +
                " (" + referencedColumn + ")" + suffix + "; END IF; END $$;";
    }

    private void verifyConstraints(
            final String group,
            final int expected,
            final String... constraints) {
        final String names = java.util.Arrays.stream(constraints)
                .map(name -> "'" + name.replace("'", "''") + "'")
                .collect(java.util.stream.Collectors.joining(","));
        final String sql = "SELECT COUNT(*) FROM pg_constraint " +
                "WHERE contype = 'f' AND convalidated AND conname IN (" + names + ")";
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             var result = stmt.executeQuery(sql)) {
            if (!result.next() || result.getInt(1) != expected) {
                throw new IllegalStateException(
                        "Required " + group + " constraints verification failed");
            }
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Required " + group + " constraints verification failed", e);
        }
    }

    private void verifyRequiredRetrievalSchema() {
        final String sql = """
                SELECT
                  (SELECT COUNT(*)
                   FROM information_schema.columns
                   WHERE table_name = 'retrieval_index_chunk'
                     AND column_name IN (
                       'id',
                       'patient_id',
                       'record_type',
                       'source_record_id',
                       'source_kind',
                       'chunk_text',
                       'chunk_metadata',
                       'search_vector',
                       'embedding',
                       'indexed_at',
                       'consent_scope',
                       'citation_replay_after',
                       'citation_replay_attempts',
                       'citation_replay_claimed_until',
                       'citation_replay_claim_token',
                       'migration_status')) AS column_count,
                  (SELECT COUNT(*)
                   FROM pg_index i
                   JOIN pg_class idx ON idx.oid = i.indexrelid
                   JOIN pg_class tbl ON tbl.oid = i.indrelid
                   WHERE tbl.relname = 'retrieval_index_chunk'
                     AND i.indisvalid AND i.indisready
                     AND idx.relname IN (
                       'idx_retrieval_chunk_fts',
                       'idx_retrieval_chunk_embedding',
                       'idx_retrieval_chunk_source_identity',
                       'idx_retrieval_summary_replay',
                       'idx_retrieval_summary_replay_claim')) AS index_count
                """;
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             var result = stmt.executeQuery(sql)) {
            if (!result.next()
                    || result.getInt("column_count") != 16
                    || result.getInt("index_count") != 5) {
                throw new IllegalStateException(
                        "Required retrieval schema verification failed");
            }
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Required retrieval schema verification failed",
                    e);
        }
        verifyConstraints(
                "retrieval",
                1,
                "fk_retrieval_chunk_patient");
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
}
