package com.careconnect.service.safety;

import com.careconnect.model.safety.AiAuditLedger;
import com.careconnect.model.safety.AuditEventType;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.repository.safety.AiAuditLedgerRepository;
import com.careconnect.service.MedicalDataAnonymizer;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Map;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AiAuditLedgerServiceTest {

    @Mock
    private AiAuditLedgerRepository repository;

    // Real anonymizer so payload minimization is exercised end-to-end.
    private AiAuditLedgerService service;

    @BeforeEach
    void setUp() {
        service = new AiAuditLedgerService(repository, new MedicalDataAnonymizer());
    }

    // Event log tests

    @Test
    void log_persistsEntryWithCorrectFields() {
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.log(AuditEventType.QUERY, AuditSourceFeature.ASK_AI,
                42L, 7L, "sess-abc", Map.of("query", "What medications?"));

        ArgumentCaptor<AiAuditLedger> captor = ArgumentCaptor.forClass(AiAuditLedger.class);
        verify(repository).save(captor.capture());
        AiAuditLedger saved = captor.getValue();

        assertThat(saved.getEventType()).isEqualTo("QUERY");
        assertThat(saved.getSourceFeature()).isEqualTo("ASK_AI");
        assertThat(saved.getActorUserId()).isEqualTo(42L);
        assertThat(saved.getPatientId()).isEqualTo(7L);
        assertThat(saved.getSessionId()).isEqualTo("sess-abc");
        assertThat(saved.getPayload()).containsEntry("query", "What medications?");
    }

    @Test
    void log_doesNotThrowWhenRepositoryFails() {
        when(repository.save(any())).thenThrow(new RuntimeException("DB unavailable"));

        AiAuditLedger result = service.log(AuditEventType.VALIDATION, AuditSourceFeature.SUMMARY,
                42L, 7L, "sess-fail", Map.of("k", "v"));

        // On failure the service returns the unsaved entity rather than throwing
        assertThat(result).isNotNull();
        assertThat(result.getEventType()).isEqualTo("VALIDATION");
        assertThat(result.getSourceFeature()).isEqualTo("SUMMARY");
        assertThat(result.getActorUserId()).isEqualTo(42L);
        assertThat(result.getPatientId()).isEqualTo(7L);
        assertThat(result.getSessionId()).isEqualTo("sess-fail");
        assertThat(result.getPayload()).containsEntry("k", "v");
    }

    @Test
    void log_withNullArgs_doesNotThrow() {
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        assertThatCode(() ->
                service.log(AuditEventType.CONFIRMATION, AuditSourceFeature.CONFIRMATION_SERVICE,
                        null, null, null, null))
                .doesNotThrowAnyException();
    }

    // test helper methods 

    @Test
    void logQuery_setsQueryEventType() {
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        service.logQuery(AuditSourceFeature.ASK_AI, 1L, 2L, "s1", Map.of("q", "x"));
        ArgumentCaptor<AiAuditLedger> c = ArgumentCaptor.forClass(AiAuditLedger.class);
        verify(repository).save(c.capture());
        assertThat(c.getValue().getEventType()).isEqualTo("QUERY");
        assertThat(c.getValue().getSourceFeature()).isEqualTo("ASK_AI");
        assertThat(c.getValue().getActorUserId()).isEqualTo(1L);
        assertThat(c.getValue().getPatientId()).isEqualTo(2L);
        assertThat(c.getValue().getSessionId()).isEqualTo("s1");
        assertThat(c.getValue().getPayload()).containsEntry("q", "x");
    }

    @Test
    void logResponse_setsResponseEventType() {
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        service.logResponse(AuditSourceFeature.ASK_AI, 1L, 2L, "s1", Map.of());
        ArgumentCaptor<AiAuditLedger> c = ArgumentCaptor.forClass(AiAuditLedger.class);
        verify(repository).save(c.capture());
        assertThat(c.getValue().getEventType()).isEqualTo("RESPONSE");
        assertThat(c.getValue().getSourceFeature()).isEqualTo("ASK_AI");
    }

    @Test
    void logValidation_setsValidationEventType() {
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        service.logValidation(AuditSourceFeature.SUMMARY, 1L, 2L, "s1", Map.of());
        ArgumentCaptor<AiAuditLedger> c = ArgumentCaptor.forClass(AiAuditLedger.class);
        verify(repository).save(c.capture());
        assertThat(c.getValue().getEventType()).isEqualTo("VALIDATION");
        assertThat(c.getValue().getSourceFeature()).isEqualTo("SUMMARY");
    }

    @Test
    void logConfirmation_setsConfirmationEventType() {
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        service.logConfirmation(AuditSourceFeature.CONFIRMATION_SERVICE, 1L, 2L, "s1", Map.of());
        ArgumentCaptor<AiAuditLedger> c = ArgumentCaptor.forClass(AiAuditLedger.class);
        verify(repository).save(c.capture());
        assertThat(c.getValue().getEventType()).isEqualTo("CONFIRMATION");
        assertThat(c.getValue().getSourceFeature()).isEqualTo("CONFIRMATION_SERVICE");
    }

    // PHI minimization tests (WBS 3.15.6)

    @Test
    void log_redactsPhiInStringPayloadValues() {
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.log(AuditEventType.QUERY, AuditSourceFeature.ASK_AI, 42L, 7L, "s1",
                Map.of("query", "Is John Smith able to email jsmith@example.com about SSN 123-45-6789?"));

        ArgumentCaptor<AiAuditLedger> c = ArgumentCaptor.forClass(AiAuditLedger.class);
        verify(repository).save(c.capture());
        String stored = (String) c.getValue().getPayload().get("query");
        assertThat(stored)
                .doesNotContain("John Smith")
                .doesNotContain("jsmith@example.com")
                .doesNotContain("123-45-6789");
    }

    @Test
    void log_truncatesLongPayloadValuesToExcerpt() {
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        String longText = "a".repeat(2000);

        service.log(AuditEventType.RESPONSE, AuditSourceFeature.ASK_AI, 42L, 7L, "s1",
                Map.of("response", longText));

        ArgumentCaptor<AiAuditLedger> c = ArgumentCaptor.forClass(AiAuditLedger.class);
        verify(repository).save(c.capture());
        String stored = (String) c.getValue().getPayload().get("response");
        assertThat(stored).hasSizeLessThan(longText.length());
        assertThat(stored).endsWith("[truncated]");
        assertThat(stored).startsWith("a".repeat(AiAuditLedgerService.MAX_VALUE_LENGTH));
    }

    @Test
    void log_preservesNonStringPayloadValues() {
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.log(AuditEventType.VALIDATION, AuditSourceFeature.SUMMARY, 42L, 7L, "s1",
                Map.of("passed", Boolean.TRUE, "score", 3));

        ArgumentCaptor<AiAuditLedger> c = ArgumentCaptor.forClass(AiAuditLedger.class);
        verify(repository).save(c.capture());
        assertThat(c.getValue().getPayload())
                .containsEntry("passed", Boolean.TRUE)
                .containsEntry("score", 3);
    }

    // entity tests (creation and read-only)
    @Test
    void entity_onCreate_setsOccurredAtWhenNull() {
        AiAuditLedger entry = new AiAuditLedger();
        assertThat(entry.getOccurredAt()).isNull();
        entry.onCreate();
        assertThat(entry.getOccurredAt()).isNotNull();
    }

    @Test
    void entity_onUpdate_throwsUnsupportedOperation() {
        AiAuditLedger entry = new AiAuditLedger();
        assertThatThrownBy(entry::onUpdate)
                .isInstanceOf(UnsupportedOperationException.class)
                .hasMessageContaining("immutable");
    }

    @Test
    void entity_onRemove_throwsUnsupportedOperation() {
        AiAuditLedger entry = new AiAuditLedger();
        assertThatThrownBy(entry::onRemove)
                .isInstanceOf(UnsupportedOperationException.class)
                .hasMessageContaining("immutable");
    }
}
