package com.careconnect.service.ehr;

import ca.uhn.fhir.parser.IParser;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.repository.ehr.EhrAuditEventRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import jakarta.persistence.EntityManager;
import org.hl7.fhir.r4.model.Bundle;
import org.hl7.fhir.r4.model.Coverage;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

import static com.careconnect.service.ehr.EhrService.ctxR4;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * {@link MedicareRecordCache} on a real PostgreSQL, where {@code ehr_raw_payload.payload} is jsonb.
 * PostgreSQL stores jsonb with its own key order and spacing, so the payload read back is not the text
 * HAPI wrote; the cache compares JSON, not text, to decide whether a resource changed. The H2 suite
 * keeps payloads as text and cannot show this.
 * <p>
 * Opt-in like the other EHR PostgreSQL tests: skipped unless {@code EHR_IT_JDBC_URI} is set, against a
 * database this branch has booted once (it needs {@code ehr_source} MEDICARE and a {@code patient} row).
 * Each test runs in a rolled-back transaction.
 * <p>
 * Test ID TC-MCR-CACHE-033 is permanent (Testing Lead, 2026-10-06, PR #272 review). Never renumber,
 * never reuse.
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
class MedicareRecordCachePostgresTest {

    private static final IParser PARSER = ctxR4.newJsonParser();

    @Autowired
    private EhrRawPayloadRepository rawPayloads;
    @Autowired
    private EhrSourceIdentityRepository identities;
    @Autowired
    private EhrAuditEventRepository auditEvents;
    @Autowired
    private EntityManager entityManager;

    private static List<Coverage> coverageFixture() {
        try (InputStream in = MedicareRecordCachePostgresTest.class
                .getResourceAsStream("/fixtures/bluebutton-synthetic/coverage-bundle.json")) {
            final List<Coverage> out = new ArrayList<>();
            PARSER.parseResource(Bundle.class, in).getEntry().forEach(e -> out.add((Coverage) e.getResource()));
            return out;
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private long count(final Long patientId, final Long sourceId) {
        return ((Number) entityManager.createNativeQuery(
                        "select count(*) from ehr_raw_payload where patient_id = :p and source_id = :s and resource_type = 'Coverage'")
                .setParameter("p", patientId).setParameter("s", sourceId).getSingleResult()).longValue();
    }

    @Test
    @DisplayName("TC-MCR-CACHE-033: on PostgreSQL jsonb, a refresh that returns unchanged resources adds no rows, and a changed one adds exactly one")
    void unchangedResourcesAddNoRowsOnJsonb() {
        final Long patientId = ((Number) entityManager
                .createNativeQuery("select id from patient order by id limit 1").getSingleResult()).longValue();
        final Long sourceId = ((Number) entityManager
                .createNativeQuery("select id from ehr_source where code = 'MEDICARE'").getSingleResult()).longValue();
        entityManager.createNativeQuery("delete from ehr_raw_payload where patient_id = :p and source_id = :s")
                .setParameter("p", patientId).setParameter("s", sourceId).executeUpdate();
        entityManager.createNativeQuery("delete from ehr_audit_event where patient_id = :p and source = 'MEDICARE'")
                .setParameter("p", patientId).executeUpdate();

        final MedicareService medicare = mock(MedicareService.class);
        final MedicareConnectionService connections = mock(MedicareConnectionService.class);
        final EhrPatientCrosswalk crosswalk = new EhrPatientCrosswalk();
        crosswalk.setPatientId(patientId);
        crosswalk.setSourceId(sourceId);
        when(connections.requireAccessToken(crosswalk)).thenReturn("synthetic-token-not-a-secret");
        when(medicare.requestMedicareCoverageInfo(anyString())).thenReturn(coverageFixture());
        final MedicareRecordCache cache = new MedicareRecordCache(medicare, connections, mock(EhrService.class),
                rawPayloads, identities, auditEvents, new EhrAuditLogger(auditEvents));

        cache.coverage(crosswalk, null);
        entityManager.flush();
        entityManager.clear();
        assertThat(count(patientId, sourceId)).isEqualTo(3);
        final EhrRawPayload stored = rawPayloads
                .findByPatientIdAndSourceIdAndResourceTypeOrderByRetrievedAtDescIdDesc(patientId, sourceId, "Coverage").get(0);
        final String written = PARSER.encodeResourceToString(
                coverageFixture().stream().filter(c -> c.getIdElement().getIdPart().equals(stored.getExternalResourceId()))
                        .findFirst().orElseThrow());
        assertThat(stored.getPayload()).as("jsonb hands back different text than HAPI wrote").isNotEqualTo(written);

        // A day later Blue Button sends the same three, then one with a changed status.
        entityManager.createNativeQuery("update ehr_audit_event set event_time = event_time - interval '2 days' "
                + "where patient_id = :p and source = 'MEDICARE'").setParameter("p", patientId).executeUpdate();
        when(medicare.requestMedicareCoverageInfo(anyString(), any(Date.class))).thenReturn(coverageFixture());
        cache.coverage(crosswalk, null);
        entityManager.flush();
        entityManager.clear();
        assertThat(count(patientId, sourceId)).as("unchanged resources add no row").isEqualTo(3);

        entityManager.createNativeQuery("update ehr_audit_event set event_time = event_time - interval '2 days' "
                + "where patient_id = :p and source = 'MEDICARE'").setParameter("p", patientId).executeUpdate();
        final List<Coverage> changed = coverageFixture();
        changed.get(0).setStatus(Coverage.CoverageStatus.CANCELLED);
        when(medicare.requestMedicareCoverageInfo(anyString(), any(Date.class))).thenReturn(changed);
        final List<String> served = cache.coverage(crosswalk, null).resources().stream()
                .map(r -> r.path("id").asText() + ":" + r.path("status").asText()).toList();
        entityManager.flush();
        assertThat(count(patientId, sourceId)).as("one changed resource adds one row").isEqualTo(4);
        assertThat(served).hasSize(3).contains("part-a--20140000008325:cancelled");
    }
}
