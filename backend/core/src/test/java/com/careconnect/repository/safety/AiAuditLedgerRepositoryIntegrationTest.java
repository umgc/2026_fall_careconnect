package com.careconnect.repository.safety;

import com.careconnect.model.safety.AiAuditLedger;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.context.ActiveProfiles;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Persistence tests for the AI audit ledger against the configured H2 test
 * database (the test JDBC URL maps the PostgreSQL `jsonb` domain to TEXT, so
 * the entity's JSON payload round-trips). Verifies the entity maps correctly
 * and the derived finders run against a real database.
 *
 * NOTE: the DB-level immutability trigger (V44) is PostgreSQL-specific and is
 * not exercised here — Flyway is disabled in the test profile. The app-level
 * @PreUpdate / @PreRemove guards are covered in AiAuditLedgerServiceTest.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class AiAuditLedgerRepositoryIntegrationTest {

    @Autowired
    private AiAuditLedgerRepository repository;

    private AiAuditLedger entry(String eventType, String sourceFeature,
                                Long actorId, Long patientId, String sessionId,
                                Map<String, Object> payload) {
        return AiAuditLedger.builder()
                .eventType(eventType)
                .sourceFeature(sourceFeature)
                .actorUserId(actorId)
                .patientId(patientId)
                .sessionId(sessionId)
                .payload(payload)
                .build();
    }

    @Test
    void persistsAndReadsBackAllFieldsIncludingJsonPayload() {
        AiAuditLedger saved = repository.save(entry(
                "QUERY", "ASK_AI", 42L, 7L, "sess-1",
                Map.of("query", "What meds?")));

        AiAuditLedger found = repository.findById(saved.getId()).orElseThrow();

        assertThat(found.getEventType()).isEqualTo("QUERY");
        assertThat(found.getSourceFeature()).isEqualTo("ASK_AI");
        assertThat(found.getActorUserId()).isEqualTo(42L);
        assertThat(found.getPatientId()).isEqualTo(7L);
        assertThat(found.getSessionId()).isEqualTo("sess-1");
        assertThat(found.getOccurredAt()).isNotNull(); // set by @PrePersist onCreate
        assertThat(found.getPayload()).containsEntry("query", "What meds?");
    }

    @Test
    void findByPatientId_returnsOnlyMatchingRows() {
        repository.save(entry("QUERY", "ASK_AI", 1L, 100L, "s", Map.of()));
        repository.save(entry("RESPONSE", "ASK_AI", 1L, 100L, "s", Map.of()));
        repository.save(entry("QUERY", "ASK_AI", 1L, 999L, "s", Map.of()));

        List<AiAuditLedger> forPatient = repository.findByPatientIdOrderByOccurredAtDesc(100L);

        assertThat(forPatient).hasSize(2)
                .allSatisfy(e -> assertThat(e.getPatientId()).isEqualTo(100L));
    }

    @Test
    void findByEventTypeAndSourceFeature_filtersCorrectly() {
        repository.save(entry("QUERY", "ASK_AI", 1L, 1L, "s", Map.of()));
        repository.save(entry("QUERY", "ASK_AI", 1L, 2L, "s", Map.of()));
        repository.save(entry("RESPONSE", "ASK_AI", 1L, 3L, "s", Map.of()));

        List<AiAuditLedger> queries = repository.findByEventTypeAndSourceFeatureOrderByOccurredAtDesc(
                "QUERY", "ASK_AI");

        assertThat(queries).hasSize(2)
                .allSatisfy(e -> assertThat(e.getEventType()).isEqualTo("QUERY"));
    }

    @Test
    void findBySessionId_returnsSessionEventsInOrder() {
        repository.save(entry("QUERY", "ASK_AI", 1L, 1L, "sess-x", Map.of()));
        repository.save(entry("RESPONSE", "ASK_AI", 1L, 1L, "sess-x", Map.of()));
        repository.save(entry("QUERY", "ASK_AI", 1L, 1L, "sess-y", Map.of()));

        List<AiAuditLedger> events = repository.findBySessionIdOrderByOccurredAtAsc("sess-x");

        assertThat(events).hasSize(2)
                .allSatisfy(e -> assertThat(e.getSessionId()).isEqualTo("sess-x"));
    }

    @Test
    void findByPatientId_paged_boundsResultSizeAndReportsTotal() {
        for (int i = 0; i < 5; i++) {
            repository.save(entry("QUERY", "ASK_AI", 1L, 100L, "s" + i, Map.of("i", i)));
        }

        Page<AiAuditLedger> firstPage =
                repository.findByPatientIdOrderByOccurredAtDesc(100L, PageRequest.of(0, 2));

        assertThat(firstPage.getContent()).hasSize(2);
        assertThat(firstPage.getTotalElements()).isEqualTo(5);
        assertThat(firstPage.getTotalPages()).isEqualTo(3);
        assertThat(firstPage.hasNext()).isTrue();
    }

    @Test
    void findByActorUserId_paged_boundsResultSize() {
        for (int i = 0; i < 4; i++) {
            repository.save(entry("QUERY", "ASK_AI", 55L, 1L, "s" + i, Map.of()));
        }

        Page<AiAuditLedger> page =
                repository.findByActorUserIdOrderByOccurredAtDesc(55L, PageRequest.of(0, 3));

        assertThat(page.getContent()).hasSize(3);
        assertThat(page.getTotalElements()).isEqualTo(4);
        assertThat(page.getContent())
                .allSatisfy(e -> assertThat(e.getActorUserId()).isEqualTo(55L));
    }

    @Test
    void findByEventTypeAndSourceFeature_paged_filtersAndBounds() {
        repository.save(entry("QUERY", "ASK_AI", 1L, 1L, "s", Map.of()));
        repository.save(entry("QUERY", "ASK_AI", 1L, 2L, "s", Map.of()));
        repository.save(entry("RESPONSE", "ASK_AI", 1L, 3L, "s", Map.of()));

        Page<AiAuditLedger> page = repository.findByEventTypeAndSourceFeatureOrderByOccurredAtDesc(
                "QUERY", "ASK_AI", PageRequest.of(0, 10));

        assertThat(page.getTotalElements()).isEqualTo(2);
        assertThat(page.getContent())
                .allSatisfy(e -> assertThat(e.getEventType()).isEqualTo("QUERY"));
    }
}
