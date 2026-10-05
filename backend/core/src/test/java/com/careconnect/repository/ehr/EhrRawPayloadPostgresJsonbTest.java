package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrRawPayload;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;

import java.time.OffsetDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Verifies that {@code EhrRawPayload.payload} lands in PostgreSQL as a real jsonb object.
 * <p>
 * The field is a {@code String} annotated {@code @JdbcTypeCode(SqlTypes.JSON)}, chosen so the
 * response body is stored byte for byte and a mapping dispute can be re-derived from exactly
 * what the source sent. The risk is that Hibernate treats the String as a value to serialise
 * rather than as JSON already, storing a quoted string literal instead of an object. That
 * would still round-trip through JPA and look correct from Java while being wrong in the
 * database: unqueryable with {@code ->>}, and a different shape from every other jsonb column
 * in this schema.
 * <p>
 * <strong>Why this test exists separately.</strong> The normal test profile boots H2 with
 * {@code CREATE DOMAIN JSONB AS TEXT} (see src/test/resources/application-test.properties), so
 * the column is plain text throughout the rest of the suite and any encoding round-trips
 * cleanly. No H2 test in this repository can detect this class of bug.
 * <p>
 * <strong>How to run it.</strong> Opt-in, because it needs a real PostgreSQL with the
 * {@code ehr_raw_payload} table already created:
 * <pre>
 *   EHR_IT_JDBC_URI=jdbc:postgresql://localhost:5433/cc_canonical \
 *   EHR_IT_DB_USER=postgres EHR_IT_DB_PASSWORD=... \
 *   ./mvnw -Dtest=EhrRawPayloadPostgresJsonbTest test
 * </pre>
 * Without {@code EHR_IT_JDBC_URI} set the class is skipped, so CI stays green rather than
 * failing on a database it does not have. The target database must also contain at least one
 * {@code patient} row: {@code SchemaPatchRunner} applies
 * {@code fk_ehr_raw_payload_patient}, so an arbitrary patient id will not insert.
 * <p>
 * Test IDs TC-EHR-RAW-002 and TC-EHR-RAW-007 are permanent. Never renumber, never reuse.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@EnabledIfEnvironmentVariable(named = "EHR_IT_JDBC_URI", matches = ".+")
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
class EhrRawPayloadPostgresJsonbTest {

    private static final String PAYLOAD =
            "{\"resourceType\":\"Patient\",\"id\":\"-10000000006435\",\"active\":true}";

    @Autowired
    private EhrRawPayloadRepository repository;

    @Autowired
    private EntityManager entityManager;

    @Test
    @DisplayName("TC-EHR-RAW-002: payload is stored as a jsonb object, not a quoted string")
    void payloadIsStoredAsJsonObjectNotQuotedString() {
        final Long patientId = ((Number) entityManager
                .createNativeQuery("select id from patient order by id limit 1")
                .getSingleResult()).longValue();

        // Resolved by code rather than assumed to be id 1: fk_ehr_raw_payload_source needs a real row.
        final Long sourceId = ((Number) entityManager
                .createNativeQuery("select id from ehr_source where code = 'ATHENAHEALTH'")
                .getSingleResult()).longValue();

        EhrRawPayload saved = repository.save(EhrRawPayload.builder()
                .patientId(patientId)
                .sourceId(sourceId)
                .resourceType("Patient")
                .externalResourceId("-10000000006435")
                .payload(PAYLOAD)
                .retrievedAt(OffsetDateTime.now())
                .build());
        entityManager.flush();

        Object jsonType = entityManager
                .createNativeQuery("select jsonb_typeof(payload) from ehr_raw_payload where id = :id")
                .setParameter("id", saved.getId())
                .getSingleResult();

        // 'string' here would mean Hibernate double-encoded the payload.
        assertThat(String.valueOf(jsonType)).isEqualTo("object");

        Object resourceType = entityManager
                .createNativeQuery("select payload ->> 'resourceType' from ehr_raw_payload where id = :id")
                .setParameter("id", saved.getId())
                .getSingleResult();

        // Only reachable if the column really holds an object: ->> on a JSON string returns null.
        assertThat(String.valueOf(resourceType)).isEqualTo("Patient");
    }

    @Test
    @DisplayName("TC-EHR-RAW-007: the retention queries find the patient and delete only their payloads before the cutoff")
    void retentionDeleteRemovesOnlyRowsBeforeCutoff() {
        final Long patientId = ((Number) entityManager
                .createNativeQuery("select id from patient order by id limit 1")
                .getSingleResult()).longValue();
        final Long sourceId = ((Number) entityManager
                .createNativeQuery("select id from ehr_source where code = 'ATHENAHEALTH'")
                .getSingleResult()).longValue();

        // A cutoff older than anything a real sync could have stored, so the statement cannot
        // touch rows this test did not create even if the target database is not empty.
        final OffsetDateTime cutoff = OffsetDateTime.parse("2001-01-01T00:00:00Z");
        final Long expired = repository.save(payloadRetrievedAt(patientId, sourceId, cutoff.minusDays(1))).getId();
        final Long kept = repository.save(payloadRetrievedAt(patientId, sourceId, cutoff.plusDays(1))).getId();
        entityManager.flush();

        // Step one of the purge: the patient is reported once, with patient.dob exactly as stored.
        final Object storedDob = entityManager
                .createNativeQuery("select dob from patient where id = :id")
                .setParameter("id", patientId)
                .getSingleResult();
        assertThat(repository.findPatientsWithPayloadRetrievedBefore(cutoff))
                .singleElement()
                .satisfies(found -> {
                    assertThat(found.getPatientId()).isEqualTo(patientId);
                    assertThat(found.getDob()).isEqualTo(storedDob);
                });

        // Step two: a patient not in the list is left alone, then the listed one is purged.
        assertThat(repository.deleteRetrievedBeforeForPatients(cutoff, List.of(-1L))).isZero();
        final int deleted = repository.deleteRetrievedBeforeForPatients(cutoff, List.of(patientId));
        entityManager.clear();

        assertThat(deleted).isEqualTo(1);
        assertThat(repository.existsById(expired)).isFalse();
        assertThat(repository.existsById(kept)).isTrue();
    }

    private static EhrRawPayload payloadRetrievedAt(
            final Long patientId, final Long sourceId, final OffsetDateTime retrievedAt) {
        return EhrRawPayload.builder()
                .patientId(patientId)
                .sourceId(sourceId)
                .resourceType("Patient")
                .payload(PAYLOAD)
                .retrievedAt(retrievedAt)
                .build();
    }
}
