package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrAuditEvent;
import com.careconnect.model.ehr.EhrRetrievalOutcome;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.context.ActiveProfiles;

import java.time.OffsetDateTime;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Persistence tests for the EHR retrieval audit trail against the configured H2 test
 * database (the test JDBC URL maps the PostgreSQL `jsonb` domain to TEXT, so the
 * entity's details payload round-trips). Verifies the entity mapping, the enum
 * outcome column, and the {@code @PrePersist} timestamp default through a real
 * persistence cycle rather than a direct method call.
 * <p>
 * Test IDs TC-EHR-AUD-003..007 are permanent. Never renumber, never reuse.
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
    @DisplayName("TC-EHR-AUD-003: persists and reads back all fields including json details")
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
    @DisplayName("TC-EHR-AUD-004: persists system-initiated failure without actor or count")
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
    @DisplayName("TC-EHR-AUD-005: PrePersist defaults eventTime when caller supplies none")
    void prePersistDefaultsEventTimeWhenCallerSuppliesNone() {
        OffsetDateTime before = OffsetDateTime.now().minusSeconds(1);

        EhrAuditEvent saved = repository.save(attempt().build());

        assertThat(repository.findById(saved.getId()).orElseThrow().getEventTime())
                .isNotNull()
                .isAfter(before);
    }

    @Test
    @DisplayName("TC-EHR-AUD-006: persists and reads back the RETRY outcome")
    void persistsAndReadsBackRetryOutcome() {
        EhrAuditEvent saved = repository.save(attempt()
                .outcome(EhrRetrievalOutcome.RETRY)
                .details(Map.of("attempt", 1))
                .build());

        EhrAuditEvent found = repository.findById(saved.getId()).orElseThrow();

        assertThat(found.getOutcome()).isEqualTo(EhrRetrievalOutcome.RETRY);
    }

    @Test
    @DisplayName("TC-EHR-AUD-007: missing source violates the not-null constraint")
    void missingSource_violatesNotNullConstraint() {
        EhrAuditEvent event = attempt()
                .source(null)
                .build();

        assertThatThrownBy(() -> repository.saveAndFlush(event))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasRootCauseInstanceOf(java.sql.SQLException.class);
    }
}
