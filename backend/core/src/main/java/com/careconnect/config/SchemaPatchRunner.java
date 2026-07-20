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
 * so it avoids the Flyway ↔ entityManagerFactory circular-dependency issue.
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
        seedDemoScheduledVisits();
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
