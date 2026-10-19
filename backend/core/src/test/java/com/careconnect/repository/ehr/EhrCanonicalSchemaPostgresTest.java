package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrSourceIdentity;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.TestPropertySource;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Proves the parts of the EHR canonical schema that {@code SchemaPatchRunner} applies and that no
 * other test reached: the {@code ehr_source} seed, the crosswalk and source-identity unique indexes,
 * the foreign keys and their {@code ON DELETE CASCADE}, the four source-identity columns added on
 * 2026-09-29, the {@code patient} timestamps reconciliation reads as its baseline, and the
 * zone-aware audit timestamps on the {@code ehr_*} tables.
 * <p>
 * PostgreSQL only, for the reason {@link EhrIdentityConflictConstraintPostgresTest} gives: on H2 the
 * patches never run, so every assertion here would pass or fail for the wrong reason. Opt-in, and
 * needs a database the application on this branch has already booted against:
 * <pre>
 *   EHR_IT_JDBC_URI=jdbc:postgresql://localhost:5433/careconnect_pr209 \
 *   EHR_IT_DB_USER=postgres EHR_IT_DB_PASSWORD=... \
 *   ./mvnw -Dtest=EhrCanonicalSchemaPostgresTest test
 * </pre>
 * Every test runs in the {@code @DataJpaTest} transaction and is rolled back. PostgreSQL aborts the
 * transaction on a constraint violation, so an expected violation is always the last statement.
 * <p>
 * Test IDs TC-EHR-SCH-001..010 are permanent. Never renumber, never reuse. 001..008 were added by
 * the Testing Lead on the PR #209 review (2026-09-29); 009 and 010 with the TIMESTAMPTZ conversion
 * the same review asked for (2026-09-30).
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@EnabledIfEnvironmentVariable(named = "EHR_IT_JDBC_URI", matches = ".+")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@TestPropertySource(properties = {
        "spring.datasource.url=${EHR_IT_JDBC_URI}",
        "spring.datasource.username=${EHR_IT_DB_USER}",
        "spring.datasource.password=${EHR_IT_DB_PASSWORD}",
        "spring.datasource.driver-class-name=org.postgresql.Driver",
        "spring.jpa.database-platform=org.hibernate.dialect.PostgreSQLDialect",
        "spring.jpa.hibernate.ddl-auto=none",
        // As src/main application.properties has it; src/test's copy shadows that file.
        "spring.jpa.properties.hibernate.jdbc.time_zone=UTC",
        "spring.flyway.enabled=false",
        "spring.sql.init.mode=never"
})
class EhrCanonicalSchemaPostgresTest {

    @Autowired
    private EntityManager entityManager;

    @Autowired
    private EhrSourceIdentityRepository sourceIdentityRepository;

    // ---- TC-EHR-SCH-001 ----

    @Test
    @DisplayName("TC-EHR-SCH-001: ehr_source holds the four seeded sources, each on FHIR R4")
    void ehrSourceIsSeededWithFourR4Sources() {
        @SuppressWarnings("unchecked")
        List<Object[]> rows = entityManager
                .createNativeQuery("select code, fhir_version from ehr_source"
                        + " where code in ('ATHENAHEALTH', 'MEDICARE', 'EPIC', 'ORACLE_HEALTH') order by code")
                .getResultList();

        assertThat(rows).extracting(r -> (String) r[0])
                .containsExactly("ATHENAHEALTH", "EPIC", "MEDICARE", "ORACLE_HEALTH");
        assertThat(rows).extracting(r -> (String) r[1]).containsOnly("R4");
    }

    // ---- TC-EHR-SCH-002 ----

    @Test
    @DisplayName("TC-EHR-SCH-002: one external patient id cannot be claimed twice by the same source")
    void duplicateExternalIdForOneSourceIsRejected() {
        long source = sourceId("ATHENAHEALTH");
        insertCrosswalk(newPatient(), source, "ext-sch-002");

        assertThatThrownBy(() -> insertCrosswalk(newPatient(), source, "ext-sch-002"))
                .hasMessageContaining("uq_ehr_crosswalk_source_external");
    }

    // ---- TC-EHR-SCH-003 ----

    @Test
    @DisplayName("TC-EHR-SCH-003: one patient cannot hold two crosswalk rows for the same source")
    void secondCrosswalkForOnePatientAndSourceIsRejected() {
        long source = sourceId("EPIC");
        long patient = newPatient();
        insertCrosswalk(patient, source, "ext-sch-003-a");

        assertThatThrownBy(() -> insertCrosswalk(patient, source, "ext-sch-003-b"))
                .hasMessageContaining("uq_ehr_crosswalk_patient_source");
    }

    // ---- TC-EHR-SCH-004 ----

    @Test
    @DisplayName("TC-EHR-SCH-004: a crosswalk row naming a source that is not registered is rejected")
    void crosswalkWithAnUnregisteredSourceIsRejected() {
        long unknownSource = ((Number) entityManager
                .createNativeQuery("select coalesce(max(id), 0) + 1000 from ehr_source")
                .getSingleResult()).longValue();

        assertThatThrownBy(() -> insertCrosswalk(newPatient(), unknownSource, "ext-sch-004"))
                .hasMessageContaining("fk_ehr_crosswalk_source");
    }

    // ---- TC-EHR-SCH-005 ----

    @Test
    @DisplayName("TC-EHR-SCH-005: one patient has at most one ehr_source_identity row per source")
    void secondSourceIdentityForOnePatientAndSourceIsRejected() {
        long source = sourceId("MEDICARE");
        long patient = newPatient();
        insertSourceIdentity(patient, source);

        assertThatThrownBy(() -> insertSourceIdentity(patient, source))
                .hasMessageContaining("uq_ehr_source_identity_patient_source");
    }

    // ---- TC-EHR-SCH-006 ----

    @Test
    @DisplayName("TC-EHR-SCH-006: deleting a patient removes its source identity, conflict and provenance rows")
    void deletingAPatientCascadesToItsReconciliationRows() {
        long source = sourceId("ORACLE_HEALTH");
        long patient = newPatient();
        insertSourceIdentity(patient, source);
        entityManager.createNativeQuery("insert into ehr_identity_conflict"
                        + " (patient_id, source_id, field_name, status, source_updated_at, detected_at,"
                        + "  resolved_at, resolved_by)"
                        + " values (:p, :s, 'phone', 'REJECTED', now(), now(), now(), 'SYSTEM')")
                .setParameter("p", patient).setParameter("s", source).executeUpdate();
        entityManager.createNativeQuery("insert into ehr_identity_field_provenance"
                        + " (patient_id, field_name, source_id, source_updated_at) values (:p, 'phone', :s, now())")
                .setParameter("p", patient).setParameter("s", source).executeUpdate();

        entityManager.createNativeQuery("delete from patient where id = :p")
                .setParameter("p", patient).executeUpdate();

        for (String table : List.of("ehr_source_identity", "ehr_identity_conflict", "ehr_identity_field_provenance")) {
            Number left = (Number) entityManager
                    .createNativeQuery("select count(*) from " + table + " where patient_id = :p")
                    .setParameter("p", patient).getSingleResult();
            assertThat(left.intValue()).as("%s rows left after the patient was deleted", table).isZero();
        }
    }

    // ---- TC-EHR-SCH-007 ----

    @Test
    @DisplayName("TC-EHR-SCH-007: member_id, gender, managing_org and language round-trip on ehr_source_identity")
    void sourceIdentityCarriesTheFourDeferredFieldsVerbatim() {
        Instant sourceUpdatedAt = Instant.now().truncatedTo(ChronoUnit.MICROS);
        EhrSourceIdentity saved = sourceIdentityRepository.saveAndFlush(EhrSourceIdentity.builder()
                .patientId(newPatient())
                .sourceId(sourceId("ATHENAHEALTH"))
                .sourceUpdatedAt(sourceUpdatedAt)
                .memberId("1S00-EXAMPLE-00")
                .gender("unknown")
                .managingOrg("Example Health Network")
                .language("en-US")
                .build());
        entityManager.clear();

        EhrSourceIdentity reloaded = sourceIdentityRepository.findById(saved.getId()).orElseThrow();
        assertThat(reloaded.getMemberId()).isEqualTo("1S00-EXAMPLE-00");
        assertThat(reloaded.getGender())
                .as("the FHIR code is stored verbatim; it is not mapped onto the Gender enum")
                .isEqualTo("unknown");
        assertThat(reloaded.getManagingOrg()).isEqualTo("Example Health Network");
        assertThat(reloaded.getLanguage()).isEqualTo("en-US");
        assertThat(reloaded.getSourceUpdatedAt()).isEqualTo(sourceUpdatedAt);
    }

    // ---- TC-EHR-SCH-008 ----

    /**
     * {@code patient.updated_at} is the reconciliation baseline of last resort (Assumption A1), and
     * {@code JpaPatientFieldAccessor.getPatientUpdatedAt} refuses a null one. JPA inserts get it from
     * {@code Auditable}; a row inserted by SQL -- the dev seed in {@code db/migration/mock_data.sql},
     * which runs after {@code SchemaPatchRunner}'s one-time backfill -- gets nothing. DEF-EHR-REC-02.
     */
    @Test
    @DisplayName("TC-EHR-SCH-008: a patient inserted by SQL without timestamps still has a reconciliation baseline")
    void patientInsertedBySqlStillHasAnUpdatedAt() {
        long patient = newPatient();

        Object[] stamps = (Object[]) entityManager
                .createNativeQuery("select created_at, updated_at from patient where id = :p")
                .setParameter("p", patient).getSingleResult();

        assertThat(stamps[0]).as("created_at").isNotNull();
        assertThat(stamps[1]).as("updated_at, the A1 baseline").isNotNull();
    }

    // ---- TC-EHR-SCH-009 ----

    @Test
    @DisplayName("TC-EHR-SCH-009: created_at and updated_at are timestamptz on all six ehr_* tables")
    void auditTimestampsAreZoneAwareOnEveryEhrTable() {
        @SuppressWarnings("unchecked")
        List<Object[]> columns = entityManager
                .createNativeQuery("select table_name, column_name, data_type from information_schema.columns"
                        + " where table_schema = current_schema()"
                        + " and table_name in ('ehr_source', 'ehr_patient_crosswalk', 'ehr_raw_payload',"
                        + " 'ehr_source_identity', 'ehr_identity_conflict', 'ehr_identity_field_provenance')"
                        + " and column_name in ('created_at', 'updated_at')")
                .getResultList();

        assertThat(columns).as("six tables, two columns each").hasSize(12);
        assertThat(columns)
                .allSatisfy(c -> assertThat(c[2]).as(c[0] + "." + c[1]).isEqualTo("timestamp with time zone"));
    }

    // ---- TC-EHR-SCH-010 ----

    /**
     * The behaviour the column type buys. {@code Auditable} stamps a {@code LocalDateTime}, and
     * Hibernate binds it with an explicit UTC offset (this class sets {@code hibernate.jdbc.time_zone}
     * as production does). A zone-aware column honours that offset. A zone-less one discards it and
     * keeps the UTC wall-clock reading, which this session -- whose zone is the JVM's, not UTC --
     * then reads back as local time: off by the JVM's UTC offset on any machine not running in UTC.
     */
    @Test
    @DisplayName("TC-EHR-SCH-010: a row stamped by Auditable holds the instant it was written, whatever the session zone")
    void auditableStampIsTheInstantItWasWritten() {
        EhrSourceIdentity saved = sourceIdentityRepository.saveAndFlush(EhrSourceIdentity.builder()
                .patientId(newPatient())
                .sourceId(sourceId("MEDICARE"))
                .sourceUpdatedAt(Instant.now().truncatedTo(ChronoUnit.MICROS))
                .build());

        Object[] skew = (Object[]) entityManager
                .createNativeQuery("select abs(extract(epoch from (clock_timestamp() - created_at))),"
                        + " abs(extract(epoch from (clock_timestamp() - updated_at)))"
                        + " from ehr_source_identity where id = :id")
                .setParameter("id", saved.getId()).getSingleResult();

        assertThat(((Number) skew[0]).doubleValue()).as("created_at skew from the database clock, seconds")
                .isLessThan(60.0);
        assertThat(((Number) skew[1]).doubleValue()).as("updated_at skew from the database clock, seconds")
                .isLessThan(60.0);
    }

    /** By native SQL on purpose, naming no timestamp column: the same shape as the dev seed insert. */
    private long newPatient() {
        return ((Number) entityManager
                .createNativeQuery("insert into patient (first_name, last_name) values ('Schema', 'Probe') returning id")
                .getSingleResult()).longValue();
    }

    private long sourceId(String code) {
        return ((Number) entityManager
                .createNativeQuery("select id from ehr_source where code = :c")
                .setParameter("c", code).getSingleResult()).longValue();
    }

    private void insertCrosswalk(long patient, long source, String externalId) {
        entityManager.createNativeQuery("insert into ehr_patient_crosswalk"
                        + " (patient_id, source_id, external_patient_id, created_at, updated_at)"
                        + " values (:p, :s, :e, now(), now())")
                .setParameter("p", patient).setParameter("s", source).setParameter("e", externalId)
                .executeUpdate();
        entityManager.flush();
    }

    private void insertSourceIdentity(long patient, long source) {
        entityManager.createNativeQuery("insert into ehr_source_identity"
                        + " (patient_id, source_id, source_updated_at, created_at, updated_at)"
                        + " values (:p, :s, now(), now(), now())")
                .setParameter("p", patient).setParameter("s", source).executeUpdate();
        entityManager.flush();
    }
}
