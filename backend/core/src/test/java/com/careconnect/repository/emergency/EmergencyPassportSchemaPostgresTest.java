package com.careconnect.repository.emergency;

import com.careconnect.model.emergency.BloodType;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.TestPropertySource;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Proves the parts of the CC-12 Increment 1 schema that {@code SchemaPatchRunner} applies: the
 * foreign keys to {@code patient} and their {@code ON DELETE CASCADE}, the {@code is_public}
 * database default, and the zone-aware audit timestamps.
 * <p>
 * PostgreSQL only, for the reason {@code EhrCanonicalSchemaPostgresTest} gives: on H2 the patches
 * never run. Opt-in, and needs a database the application on this branch has already booted
 * against:
 * <pre>
 *   EHR_IT_JDBC_URI=jdbc:postgresql://localhost:5433/careconnect \
 *   EHR_IT_DB_USER=postgres EHR_IT_DB_PASSWORD=... \
 *   ./mvnw -Dtest=EmergencyPassportSchemaPostgresTest test
 * </pre>
 * Every test runs in the {@code @DataJpaTest} transaction and is rolled back. PostgreSQL aborts the
 * transaction on a constraint violation, so an expected violation is always the last statement.
 * <p>
 * Test IDs TC-EMG-036…040 (the author's) and TC-EMG-050…053 (the Testing Lead's) are permanent,
 * Test Plan §3.23. Never renumber, never reuse.
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
class EmergencyPassportSchemaPostgresTest {

    @Autowired
    private EntityManager entityManager;

    @Test
    @DisplayName("TC-EMG-036: a profile for a patient that does not exist is rejected")
    void profileForUnknownPatientIsRejected() {
        assertThatThrownBy(() -> insertProfile(unknownPatient()))
                .hasMessageContaining("fk_emergency_passport_profile_patient");
    }

    @Test
    @DisplayName("TC-EMG-037: a visibility row for a patient that does not exist is rejected")
    void visibilityForUnknownPatientIsRejected() {
        assertThatThrownBy(() -> insertVisibility(unknownPatient(), "ALLERGIES"))
                .hasMessageContaining("fk_emergency_passport_visibility_patient");
    }

    @Test
    @DisplayName("TC-EMG-038: a visibility row inserted by SQL without is_public is hidden")
    void isPublicDefaultsToFalseInTheDatabase() {
        long patient = newPatient();
        insertVisibility(patient, "BLOOD_TYPE");

        Object isPublic = entityManager
                .createNativeQuery("select is_public from emergency_passport_field_visibility where patient_id = :p")
                .setParameter("p", patient).getSingleResult();
        assertThat(isPublic).isEqualTo(false);
    }

    @Test
    @DisplayName("TC-EMG-039: deleting a patient removes their passport profile and visibility rows")
    void deletingAPatientCascades() {
        long patient = newPatient();
        insertProfile(patient);
        insertVisibility(patient, "ALLERGIES");

        entityManager.createNativeQuery("delete from patient where id = :p")
                .setParameter("p", patient).executeUpdate();

        for (String table : List.of("emergency_passport_profile", "emergency_passport_field_visibility")) {
            Number left = (Number) entityManager
                    .createNativeQuery("select count(*) from " + table + " where patient_id = :p")
                    .setParameter("p", patient).getSingleResult();
            assertThat(left.intValue()).as("%s rows left after the patient was deleted", table).isZero();
        }
    }

    @Test
    @DisplayName("TC-EMG-040: created_at and updated_at on both passport tables are TIMESTAMPTZ")
    void auditTimestampsAreZoneAware() {
        @SuppressWarnings("unchecked")
        List<Object[]> columns = entityManager
                .createNativeQuery("select table_name, column_name, data_type from information_schema.columns"
                        + " where table_schema = current_schema()"
                        + " and table_name in ('emergency_passport_profile', 'emergency_passport_field_visibility')"
                        + " and column_name in ('created_at', 'updated_at')")
                .getResultList();

        assertThat(columns).hasSize(4);
        assertThat(columns).extracting(c -> (String) c[2]).containsOnly("timestamp with time zone");
    }

    @Test
    @DisplayName("TC-EMG-050: a second profile for the same patient is rejected by uq_emergency_passport_profile_patient")
    void secondProfileIsRejectedByTheDatabase() {
        long patient = newPatient();
        insertProfile(patient);

        assertThatThrownBy(() -> insertProfile(patient))
                .hasMessageContaining("uq_emergency_passport_profile_patient");
    }

    @Test
    @DisplayName("TC-EMG-051: a second row for the same patient and field is rejected by "
            + "uq_emergency_passport_visibility_patient_field")
    void secondVisibilityRowIsRejectedByTheDatabase() {
        long patient = newPatient();
        insertVisibility(patient, "ALLERGIES");

        assertThatThrownBy(() -> insertVisibility(patient, "ALLERGIES"))
                .hasMessageContaining("uq_emergency_passport_visibility_patient_field");
    }

    @Test
    @DisplayName("TC-EMG-052: a visibility row inserted by SQL with is_public NULL is rejected, so hidden has one meaning")
    void explicitNullIsPublicIsRejected() {
        long patient = newPatient();

        assertThatThrownBy(() -> {
            entityManager.createNativeQuery("insert into emergency_passport_field_visibility"
                            + " (patient_id, field_key, is_public, created_at, updated_at)"
                            + " values (:p, 'MEDICATIONS', null, now(), now())")
                    .setParameter("p", patient).executeUpdate();
            entityManager.flush();
        }).hasMessageContaining("is_public");
    }

    @Test
    @DisplayName("TC-EMG-053: every blood type name fits blood_type in the database, AB_NEGATIVE included")
    void everyBloodTypeNameFitsTheColumn() {
        // H2 types this column as a native ENUM, so only PostgreSQL shows the VARCHAR(16) length holds.
        for (BloodType bloodType : BloodType.values()) {
            long patient = newPatient();
            entityManager.createNativeQuery("insert into emergency_passport_profile"
                            + " (patient_id, blood_type, created_at, updated_at) values (:p, :b, now(), now())")
                    .setParameter("p", patient).setParameter("b", bloodType.name()).executeUpdate();
            Object stored = entityManager
                    .createNativeQuery("select blood_type from emergency_passport_profile where patient_id = :p")
                    .setParameter("p", patient).getSingleResult();
            assertThat(stored).as("blood type %s", bloodType).isEqualTo(bloodType.name());
        }
    }

    private long newPatient() {
        return ((Number) entityManager
                .createNativeQuery("insert into patient (first_name, last_name) values ('Passport', 'Probe') returning id")
                .getSingleResult()).longValue();
    }

    private long unknownPatient() {
        return ((Number) entityManager
                .createNativeQuery("select coalesce(max(id), 0) + 1000 from patient")
                .getSingleResult()).longValue();
    }

    private void insertProfile(long patient) {
        entityManager.createNativeQuery("insert into emergency_passport_profile"
                        + " (patient_id, created_at, updated_at) values (:p, now(), now())")
                .setParameter("p", patient).executeUpdate();
        entityManager.flush();
    }

    private void insertVisibility(long patient, String field) {
        entityManager.createNativeQuery("insert into emergency_passport_field_visibility"
                        + " (patient_id, field_key, created_at, updated_at) values (:p, :f, now(), now())")
                .setParameter("p", patient).setParameter("f", field).executeUpdate();
        entityManager.flush();
    }
}
