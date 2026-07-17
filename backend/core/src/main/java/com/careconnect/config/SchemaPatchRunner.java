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
        applyRetrievalIndexChunkPatches();
        applyUspsMailpiecePatches();
        seedDemoScheduledVisits();
    }

    /**
     * Tasks 1.5 / 1.6 — pgvector extension and shared Ask AI retrieval index table.
     * Mirrors db/migration V2607071920 and V2607071921 (applied via SchemaPatchRunner in all envs).
     */
    private void applyRetrievalIndexChunkPatches() {
        applyPatch(
            "V2607071920 – enable pgvector extension",
            "CREATE EXTENSION IF NOT EXISTS vector"
        );
        applyPatch(
            "V2607071921a – create retrieval_index_chunk table",
            "CREATE TABLE IF NOT EXISTS retrieval_index_chunk (" +
            "  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid()," +
            "  patient_id        BIGINT        NOT NULL," +
            "  record_type       VARCHAR(40)   NOT NULL," +
            "  source_record_id  VARCHAR(120)  NOT NULL," +
            "  chunk_text        TEXT          NOT NULL," +
            "  chunk_metadata    JSONB         NULL," +
            "  search_vector     TSVECTOR      NULL," +
            "  embedding         vector(1536)  NULL," +
            "  indexed_at        TIMESTAMPTZ   NOT NULL DEFAULT now()," +
            "  consent_scope     VARCHAR(40)   NULL" +
            ")"
        );
        applyPatch(
            "V2607071921b – retrieval_index_chunk patient FK",
            "DO $$ BEGIN " +
            "  ALTER TABLE retrieval_index_chunk " +
            "    ADD CONSTRAINT fk_retrieval_chunk_patient " +
            "    FOREIGN KEY (patient_id) REFERENCES patient (id); " +
            "EXCEPTION WHEN duplicate_object THEN NULL; END $$"
        );
        applyPatch(
            "V2607071921c – retrieval_index_chunk indexes",
            "CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_patient_id " +
            "  ON retrieval_index_chunk (patient_id);" +
            "CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_patient_record_type " +
            "  ON retrieval_index_chunk (patient_id, record_type);" +
            "CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_source " +
            "  ON retrieval_index_chunk (source_record_id, record_type);" +
            "CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_fts " +
            "  ON retrieval_index_chunk USING GIN (search_vector);" +
            "CREATE INDEX IF NOT EXISTS idx_retrieval_chunk_embedding " +
            "  ON retrieval_index_chunk USING ivfflat (embedding vector_cosine_ops) " +
            "  WITH (lists = 100)"
        );
        applyPatch(
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
        applyPatch(
            "V2607121930 – backfill retrieval_index_chunk search_vector (Task 4.2)",
            "UPDATE retrieval_index_chunk " +
            "SET search_vector = to_tsvector('english', COALESCE(chunk_text, '')) " +
            "WHERE search_vector IS NULL"
        );
        applyPatch(
            "V2607122000 – indexing_outbox claimed_at lease column",
            "ALTER TABLE indexing_outbox " +
            "  ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ NULL;" +
            "CREATE INDEX IF NOT EXISTS idx_indexing_outbox_claimable " +
            "  ON indexing_outbox (id ASC) WHERE processed_at IS NULL"
        );
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
}
