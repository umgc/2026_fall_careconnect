package com.careconnect.ehr.reconciliation.jpa;

import com.careconnect.ehr.reconciliation.AbstractIdentityReconciliationContractTest;
import com.careconnect.ehr.reconciliation.IdentityConflictAuditWriter;
import com.careconnect.ehr.reconciliation.IdentityReconciler;
import com.careconnect.ehr.reconciliation.PatientFieldAccessor;
import com.careconnect.ehr.reconciliation.RecencyWinsIdentityReconciler;
import com.careconnect.ehr.reconciliation.RecordedDecision;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrConflictStatus;
import com.careconnect.model.ehr.EhrIdentityConflict;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrIdentityConflictRepository;
import com.careconnect.repository.ehr.EhrIdentityFieldProvenanceRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.TestPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.Objects;

/**
 * Runs the entire identity-reconciliation contract against real PostgreSQL, with all four JPA
 * implementations wired in place of the in-memory fakes.
 *
 * <p>This is the test the JPA work was for. {@code InMemoryContractTest} proves the contract is
 * <em>satisfiable</em>; it cannot prove this codebase satisfies it, and by construction it never
 * touches the constraints that carry most of the design —
 * {@code ck_ehr_identity_conflict_pending_dob}, {@code ck_ehr_identity_conflict_resolution},
 * {@code uq_ehr_identity_conflict_open}, the {@code NOT NULL} columns, or the row lock on
 * {@code ehr_identity_field_provenance}. Every one of those is exercised here, because the same
 * sixteen scenarios now run through code that has to satisfy them.
 *
 * <p>It already earned its place: building it exposed that
 * {@code IdentityConflictAuditWriter.recordDecision} had no {@code sourceUpdatedAt} parameter while
 * {@code ehr_identity_conflict.source_updated_at} is {@code NOT NULL}. No implementation could have
 * satisfied both. The in-memory fake hid it by storing null, which costs nothing in a
 * {@code HashMap} and is rejected outright by the database.
 *
 * <p>Committing rather than rolling back, for the same reason as the other tests in this package:
 * the contract's concurrency scenario needs two genuinely independent transactions, which a
 * rollback-per-test arrangement cannot produce. Each scenario gets its own throwaway patient, and
 * {@code ON DELETE CASCADE} from {@code patient} clears the conflict and provenance rows with it.
 *
 * <pre>
 *   EHR_IT_JDBC_URI=jdbc:postgresql://localhost:5433/cc_phase2 \
 *   EHR_IT_DB_USER=postgres EHR_IT_DB_PASSWORD=... \
 *   ./mvnw -Dtest=JpaContractPostgresTest test
 * </pre>
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@EnabledIfEnvironmentVariable(named = "EHR_IT_JDBC_URI", matches = ".+")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Transactional(propagation = Propagation.NOT_SUPPORTED)
@TestPropertySource(properties = {
        "spring.datasource.url=${EHR_IT_JDBC_URI}",
        "spring.datasource.username=${EHR_IT_DB_USER}",
        "spring.datasource.password=${EHR_IT_DB_PASSWORD}",
        "spring.datasource.driver-class-name=org.postgresql.Driver",
        "spring.jpa.database-platform=org.hibernate.dialect.PostgreSQLDialect",
        "spring.jpa.hibernate.ddl-auto=none",
        "spring.flyway.enabled=false",
        "spring.sql.init.mode=never"
})
class JpaContractPostgresTest extends AbstractIdentityReconciliationContractTest {

    @PersistenceContext
    private EntityManager entityManager;

    @Autowired
    private PatientRepository patientRepository;

    @Autowired
    private EhrIdentityFieldProvenanceRepository provenanceRepository;

    @Autowired
    private EhrIdentityConflictRepository conflictRepository;

    @Autowired
    private PlatformTransactionManager transactionManager;

    private TransactionTemplate tx;
    private IdentityReconciler reconciler;
    private JpaPatientFieldAccessor patientAccessor;
    private JpaIdentityConflictAuditWriter auditWriter;

    /** Patients created by the scenario under way, deleted after it. */
    private final List<Long> createdPatientIds = new ArrayList<>();

    /** Source code to {@code ehr_source.id}, resolved once per JVM and reused across scenarios. */
    private static final Map<String, Long> SOURCE_IDS = new ConcurrentHashMap<>();

    @BeforeEach
    void setUp() {
        tx = new TransactionTemplate(transactionManager);
        patientAccessor = new JpaPatientFieldAccessor(patientRepository);
        auditWriter = new JpaIdentityConflictAuditWriter(conflictRepository);
        reconciler = new RecencyWinsIdentityReconciler(
                new JpaIdentityFieldProvenanceStore(provenanceRepository, entityManager),
                patientAccessor,
                auditWriter,
                new SpringTransactionRunner(transactionManager));
    }

    @AfterEach
    void deleteCreatedPatients() {
        for (Long id : createdPatientIds) {
            tx.executeWithoutResult(status -> entityManager
                    .createNativeQuery("delete from patient where id = :id")
                    .setParameter("id", id)
                    .executeUpdate());
        }
        createdPatientIds.clear();
    }

    @Override
    protected IdentityReconciler reconciler() {
        return reconciler;
    }

    /**
     * Wrapped so the contract's own direct calls — which the scenarios make outside any transaction,
     * to seed a starting value or read a result — still satisfy
     * {@code JpaPatientFieldAccessor.applyValue}'s transaction requirement. The reconciler's own
     * calls come through {@code SpringTransactionRunner} and are already inside one; this only
     * covers the test's setup and assertion calls.
     */
    @Override
    protected PatientFieldAccessor patientAccessor() {
        return new PatientFieldAccessor() {
            @Override
            public java.util.Optional<String> getCurrentValue(Long patientId, String fieldName) {
                return tx.execute(status -> patientAccessor.getCurrentValue(patientId, fieldName));
            }

            @Override
            public Instant getPatientUpdatedAt(Long patientId) {
                return tx.execute(status -> patientAccessor.getPatientUpdatedAt(patientId));
            }

            @Override
            public void applyValue(Long patientId, String fieldName, String newValue) {
                tx.executeWithoutResult(status -> patientAccessor.applyValue(patientId, fieldName, newValue));
                // A seeded starting value must not also move the A1 baseline: the scenarios set
                // patient.updated_at explicitly via seedPatientUpdatedAt, and Auditable's @PreUpdate
                // would otherwise overwrite that with now() and invalidate the scenario's premise.
                Instant seeded = seededUpdatedAt.get(patientId);
                if (seeded != null) {
                    writeUpdatedAt(patientId, seeded);
                }
            }
        };
    }

    @Override
    protected IdentityConflictAuditWriter auditWriter() {
        return new IdentityConflictAuditWriter() {
            @Override
            public void recordDecision(Long patientId, Long sourceId, String fieldName,
                                       String canonicalValueBefore, String incomingValue,
                                       Instant sourceUpdatedAt, Outcome outcome, ResolvedBy resolvedBy,
                                       Instant detectedAndResolvedAt) {
                tx.executeWithoutResult(status -> auditWriter.recordDecision(patientId, sourceId,
                        fieldName, canonicalValueBefore, incomingValue, sourceUpdatedAt, outcome,
                        resolvedBy, detectedAndResolvedAt));
            }

            @Override
            public void openPendingConflict(Long patientId, Long sourceId, String fieldName,
                                            String canonicalValueBefore, String incomingValue,
                                            Instant sourceUpdatedAt, Instant detectedAt) {
                tx.executeWithoutResult(status -> auditWriter.openPendingConflict(patientId, sourceId,
                        fieldName, canonicalValueBefore, incomingValue, sourceUpdatedAt, detectedAt));
            }

            @Override
            public java.util.Optional<PendingConflict> currentPendingConflict(Long patientId, String fieldName) {
                return tx.execute(status -> auditWriter.currentPendingConflict(patientId, fieldName));
            }

            @Override
            public boolean patientHasDeclined(Long patientId, String fieldName, String incomingValue) {
                return Boolean.TRUE.equals(
                        tx.execute(status -> auditWriter.patientHasDeclined(patientId, fieldName, incomingValue)));
            }

            @Override
            public void resolvePendingConflict(Long patientId, String fieldName, Outcome outcome,
                                               ResolvedBy resolvedBy, Instant resolvedAt) {
                tx.executeWithoutResult(status -> auditWriter.resolvePendingConflict(patientId,
                        fieldName, outcome, resolvedBy, resolvedAt));
            }
        };
    }

    private final Map<Object, Instant> seededUpdatedAt = new ConcurrentHashMap<>();

    @Override
    protected void seedPatientUpdatedAt(Long patientId, Instant instant) {
        seededUpdatedAt.put(patientId, instant);
        writeUpdatedAt(patientId, instant);
    }

    private void writeUpdatedAt(Long patientId, Instant instant) {
        LocalDateTime asLocal = LocalDateTime.ofInstant(instant, ZoneId.systemDefault());
        tx.executeWithoutResult(status -> entityManager
                .createNativeQuery("update patient set updated_at = :ts where id = :id")
                .setParameter("ts", asLocal)
                .setParameter("id", Objects.requireNonNull(patientId, "patientId"))
                .executeUpdate());
    }

    /**
     * Finalized rows only. A {@code PENDING} row is an open question, not a decision, and the
     * contract's assertions count decisions.
     */
    @Override
    protected List<RecordedDecision> decisionsFor(Long patientId, String fieldName) {
        return tx.execute(status -> conflictRepository
                .findByPatientIdOrderByDetectedAtDesc(Objects.requireNonNull(patientId, "patientId"))
                .stream()
                .filter(row -> row.getFieldName().equals(fieldName))
                .filter(row -> row.getStatus() != EhrConflictStatus.PENDING)
                .map(JpaContractPostgresTest::toRecordedDecision)
                .toList());
    }

    private static RecordedDecision toRecordedDecision(EhrIdentityConflict row) {
        return new RecordedDecision(
                row.getFieldName(),
                row.getCanonicalValueBefore(),
                row.getIncomingValue(),
                row.getStatus() == EhrConflictStatus.ACCEPTED
                        ? IdentityConflictAuditWriter.Outcome.ACCEPTED
                        : IdentityConflictAuditWriter.Outcome.REJECTED,
                switch (row.getResolvedBy()) {
                    case PATIENT -> IdentityConflictAuditWriter.ResolvedBy.PATIENT;
                    case SYSTEM -> IdentityConflictAuditWriter.ResolvedBy.SYSTEM;
                });
    }

    @Override
    protected Long freshPatientId() {
        Long id = tx.execute(status -> {
            // Every field left null on purpose. The contract's scenarios establish a starting value
            // by reconciling one in and relying on the fill-empty path; pre-populating any field
            // turns that first reconcile into a disagreement judged against a brand-new
            // patient.updated_at, which nothing older can beat. The in-memory fake's patient starts
            // with no fields at all, and this one has to match it to be running the same contract.
            return patientRepository.save(new Patient()).getId();
        });
        createdPatientIds.add(id);
        return id;
    }

    /**
     * Resolves a source code to its {@code ehr_source.id}, creating the row if this database has not
     * seen that source. The contract names sources the adapters will really use
     * ({@code ATHENAHEALTH}, {@code EPIC}, {@code ORACLE_HEALTH}), and every conflict and provenance
     * row carries a foreign key to one — so unlike the in-memory fakes, the code cannot stand in for
     * the id here.
     */
    @Override
    protected Long sourceId(String sourceCode) {
        return SOURCE_IDS.computeIfAbsent(sourceCode, code -> tx.execute(status -> {
            entityManager.createNativeQuery(
                            "INSERT INTO ehr_source (code, display_name, fhir_version, enabled, created_at, updated_at) "
                                    + "VALUES (:code, :code, 'R4', true, now(), now()) "
                                    + "ON CONFLICT (code) DO NOTHING")
                    .setParameter("code", code)
                    .executeUpdate();
            return ((Number) entityManager
                    .createNativeQuery("select id from ehr_source where code = :code")
                    .setParameter("code", code)
                    .getSingleResult()).longValue();
        }));
    }
}
