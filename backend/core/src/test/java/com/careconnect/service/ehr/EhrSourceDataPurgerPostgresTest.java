package com.careconnect.service.ehr;

import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.TestPropertySource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Proves {@link EhrSourceDataPurger} against real PostgreSQL: disconnecting one source deletes that
 * source's rows from every table the A1-Q1 unlink rule names, and leaves another source's rows and the
 * retrieval audit log alone.
 * <p>
 * PostgreSQL only and opt-in, like the other {@code *PostgresTest} classes, and needs a database the
 * application on this branch has already booted against (so the canonical tables, their seed and
 * {@code ehr_resource} exist). Every test runs in the {@code @DataJpaTest} transaction and is rolled
 * back:
 * <pre>
 *   EHR_IT_JDBC_URI=jdbc:postgresql://localhost:5432/careconnect \
 *   EHR_IT_DB_USER=postgres EHR_IT_DB_PASSWORD=... \
 *   ./mvnw -Dtest=EhrSourceDataPurgerPostgresTest test
 * </pre>
 */
@DataJpaTest
@Import(EhrSourceDataPurger.class)
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
        "spring.jpa.properties.hibernate.jdbc.time_zone=UTC",
        "spring.flyway.enabled=false",
        "spring.sql.init.mode=never"
})
class EhrSourceDataPurgerPostgresTest {

    /** ehr_resource.user_id has no foreign key, so any id no real user holds will do. */
    private static final long USER_ID = 990_000_001L;

    @Autowired
    private EntityManager entityManager;

    @Autowired
    private EhrSourceDataPurger purger;

    private long patient;
    private long athena;
    private long epic;

    @BeforeEach
    void seedTwoSources() {
        patient = ((Number) entityManager
                .createNativeQuery("insert into patient (first_name, last_name) values ('Purge', 'Probe') returning id")
                .getSingleResult()).longValue();
        athena = sourceId("ATHENAHEALTH");
        epic = sourceId("EPIC");
        seed(athena, "ATHENAHEALTH");
        seed(epic, "EPIC");
    }

    /** One row per table for {@code source}, all belonging to the probe patient. */
    private void seed(final long source, final String code) {
        exec("insert into ehr_patient_crosswalk (patient_id, source_id, external_patient_id, created_at, updated_at)"
                + " values (:p, :s, :e, now(), now())", source, "ext-" + code);
        exec("insert into ehr_raw_payload (patient_id, source_id, resource_type, external_resource_id, payload,"
                + " payload_size_bytes, photo_stripped, retrieved_at, created_at, updated_at)"
                + " values (:p, :s, 'Condition', :e, cast('{}' as jsonb), 2, false, now(), now(), now())", source, "c-1");
        exec("insert into ehr_source_identity (patient_id, source_id, source_updated_at, given_name, created_at,"
                + " updated_at) values (:p, :s, now(), :e, now(), now())", source, "Probe");
        exec("insert into ehr_identity_conflict (patient_id, source_id, field_name, status, resolved_by,"
                + " source_updated_at, detected_at, resolved_at, created_at, updated_at)"
                + " values (:p, :s, :e, 'ACCEPTED', 'SYSTEM', now(), now(), now(), now(), now())", source, "phone");
        entityManager.createNativeQuery("insert into ehr_audit_event (patient_id, source, resource_type, outcome,"
                        + " event_time) values (:p, :c, 'Condition', 'SUCCESS', now())")
                .setParameter("p", patient).setParameter("c", code).executeUpdate();
        entityManager.createNativeQuery("insert into ehr_resource (user_id, source, resource_type, resource_fhir_id,"
                        + " last_synced_at, created_at) values (:u, :c, 'Condition', 'c-1', now(), now())")
                .setParameter("u", USER_ID).setParameter("c", code).executeUpdate();
    }

    @Test
    @DisplayName("disconnecting athena deletes its rows in every A1-Q1 table and nothing else")
    void purgesOnlyTheDisconnectedSource() {
        // Act
        final EhrSourceDataPurger.Purged purged = purger.purge(USER_ID, patient, athena, "ATHENAHEALTH");

        // Assert: one athena row gone from each table.
        assertThat(purged).isEqualTo(new EhrSourceDataPurger.Purged(1, 1, 1, 1, 1));
        for (final String table : new String[] {"ehr_patient_crosswalk", "ehr_raw_payload", "ehr_source_identity",
                "ehr_identity_conflict"}) {
            assertThat(count(table, athena)).as(table + " athena rows").isZero();
            assertThat(count(table, epic)).as(table + " epic rows").isEqualTo(1);
        }
        assertThat(mirrorRows("ATHENAHEALTH")).isZero();
        assertThat(mirrorRows("EPIC")).isEqualTo(1);
        // The audit log is kept for both sources.
        assertThat(auditRows("ATHENAHEALTH")).isEqualTo(1);
        assertThat(auditRows("EPIC")).isEqualTo(1);
    }

    private long sourceId(final String code) {
        return ((Number) entityManager.createNativeQuery("select id from ehr_source where code = :c")
                .setParameter("c", code).getSingleResult()).longValue();
    }

    private void exec(final String sql, final long source, final String text) {
        entityManager.createNativeQuery(sql)
                .setParameter("p", patient).setParameter("s", source).setParameter("e", text)
                .executeUpdate();
    }

    /** Table names come from the fixed list in the test, never from input, so they are not bound. */
    private long count(final String table, final long source) {
        return ((Number) entityManager.createNativeQuery(
                "select count(*) from " + table + " where patient_id = :p and source_id = :s")
                .setParameter("p", patient).setParameter("s", source).getSingleResult()).longValue();
    }

    private long mirrorRows(final String code) {
        return ((Number) entityManager.createNativeQuery(
                "select count(*) from ehr_resource where user_id = :u and source = :c")
                .setParameter("u", USER_ID).setParameter("c", code).getSingleResult()).longValue();
    }

    private long auditRows(final String code) {
        return ((Number) entityManager.createNativeQuery(
                "select count(*) from ehr_audit_event where patient_id = :p and source = :c")
                .setParameter("p", patient).setParameter("c", code).getSingleResult()).longValue();
    }
}
