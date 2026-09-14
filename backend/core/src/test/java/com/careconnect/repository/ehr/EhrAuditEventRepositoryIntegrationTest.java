package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrAuditEvent;
import com.careconnect.model.ehr.EhrRetrievalOutcome;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

import java.time.OffsetDateTime;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Persistence tests for the EHR retrieval audit trail against the configured H2 test
 * database (the test JDBC URL maps the PostgreSQL `jsonb` domain to TEXT, so the
 * entity's details payload round-trips). Verifies the entity mapping, the enum
 * outcome column, and the {@code @PrePersist} timestamp default through a real
 * persistence cycle rather than a direct method call.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class EhrAuditEventRepositoryIntegrationTest {

    @Autowired
    private EhrAuditEventRepository repository;

    private EhrAuditEvent.EhrAuditEventBuilder attempt() {
        return EhrAuditEvent.builder()
                .patientId(7L)
                .source("MEDICARE")
                .resourceType("Coverage")
                .outcome(EhrRetrievalOutcome.SUCCESS);
    }

    @Test
    void persistsAndReadsBackAllFieldsIncludingJsonDetails() {
        EhrAuditEvent saved = repository.save(attempt()
                .actorUserId(42L)
                .recordCount(3)
                .details(Map.of("latencyMs", 412))
                .build());

        EhrAuditEvent found = repository.findById(saved.getId()).orElseThrow();

        assertThat(found.getPatientId()).isEqualTo(7L);
        assertThat(found.getSource()).isEqualTo("MEDICARE");
        assertThat(found.getResourceType()).isEqualTo("Coverage");
        assertThat(found.getOutcome()).isEqualTo(EhrRetrievalOutcome.SUCCESS);
        assertThat(found.getActorUserId()).isEqualTo(42L);
        assertThat(found.getRecordCount()).isEqualTo(3);
        assertThat(found.getDetails()).containsEntry("latencyMs", 412);
    }

    @Test
    void persistsSystemInitiatedFailureWithoutActorOrCount() {
        EhrAuditEvent saved = repository.save(attempt()
                .resourceType("Patient")
                .outcome(EhrRetrievalOutcome.FAILURE)
                .details(Map.of("errorCode", "ERR-MCR-05"))
                .build());

        EhrAuditEvent found = repository.findById(saved.getId()).orElseThrow();

        assertThat(found.getOutcome()).isEqualTo(EhrRetrievalOutcome.FAILURE);
        assertThat(found.getActorUserId()).isNull();
        assertThat(found.getRecordCount()).isNull();
        assertThat(found.getDetails()).containsEntry("errorCode", "ERR-MCR-05");
    }

    @Test
    void prePersistDefaultsEventTimeWhenCallerSuppliesNone() {
        OffsetDateTime before = OffsetDateTime.now().minusSeconds(1);

        EhrAuditEvent saved = repository.save(attempt().build());

        assertThat(repository.findById(saved.getId()).orElseThrow().getEventTime())
                .isNotNull()
                .isAfter(before);
    }
}
