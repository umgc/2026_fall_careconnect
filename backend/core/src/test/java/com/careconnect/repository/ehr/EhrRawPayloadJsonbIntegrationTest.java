package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrRawPayload;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Entity-mapping tests for {@code EhrRawPayload} on the H2 test database.
 * <p>
 * The field is a {@code String} annotated {@code @JdbcTypeCode(SqlTypes.JSON)}, chosen so the
 * response body is stored byte for byte and a mapping dispute can be re-derived from exactly
 * what the source sent. The risk that choice carries is that Hibernate might treat the String
 * as a value to serialise rather than as JSON already, storing a quoted string literal —
 * {@code "{\"resourceType\":...}"} — instead of a JSON object. That would still round-trip
 * through JPA and look correct from Java while being wrong in the database: unqueryable by
 * {@code ->>}, and a different shape than every other jsonb column in this schema.
 * <p>
 * That distinction CANNOT be tested here: src/test/resources/application-test.properties
 * boots H2 with 'CREATE DOMAIN JSONB AS TEXT', so the column is plain text in this suite and
 * any encoding round-trips cleanly. See EhrRawPayloadPostgresJsonbTest, which runs the real
 * check against PostgreSQL and is the only place the jsonb shape is actually verified.
 * No patient row is needed: the entity stores a bare {@code Long patientId} rather than a
 * {@code @ManyToOne}, and the foreign key is applied by {@code SchemaPatchRunner}, which does
 * not run in a slice test.
 * <p>
 * Test IDs TC-EHR-RAW-001 and 003 are permanent. Never renumber, never reuse.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class EhrRawPayloadJsonbIntegrationTest {

    private static final String PAYLOAD =
            "{\"resourceType\":\"Patient\",\"id\":\"-10000000006435\",\"active\":true}";

    @Autowired
    private EhrRawPayloadRepository repository;

    @Autowired
    private EntityManager entityManager;

    private EhrRawPayload.EhrRawPayloadBuilder payload() {
        return EhrRawPayload.builder()
                .patientId(7L)
                .sourceId(1L)
                .resourceType("Patient")
                .externalResourceId("-10000000006435")
                .payload(PAYLOAD)
                .retrievedAt(OffsetDateTime.now());
    }

    @Test
    @DisplayName("TC-EHR-RAW-001: payload round-trips through JPA unchanged")
    void payloadRoundTripsUnchanged() {
        EhrRawPayload saved = repository.save(payload().build());
        entityManager.flush();
        entityManager.clear();

        EhrRawPayload found = repository.findById(saved.getId()).orElseThrow();

        assertThat(found.getPayload()).isEqualTo(PAYLOAD);
        assertThat(found.getResourceType()).isEqualTo("Patient");
        assertThat(found.getPhotoStripped()).isFalse();
    }

    @Test
    @DisplayName("TC-EHR-RAW-003: payload_size_bytes is derived from the stored payload on insert")
    void payloadSizeBytesIsDerivedOnInsert() {
        EhrRawPayload saved = repository.save(payload().payloadSizeBytes(null).build());
        entityManager.flush();

        assertThat(saved.getPayloadSizeBytes())
                .isEqualTo(PAYLOAD.getBytes(StandardCharsets.UTF_8).length);
    }
}
