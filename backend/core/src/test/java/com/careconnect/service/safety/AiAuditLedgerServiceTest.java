package com.careconnect.service.safety;

import com.careconnect.model.safety.AiAuditLedger;
import com.careconnect.model.safety.AuditEventType;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.repository.safety.AiAuditLedgerRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
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

    @InjectMocks
    private AiAuditLedgerService service;

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
        assertThat(saved.getPayload()).containsKey("query");
    }

    @Test
    void log_doesNotThrowWhenRepositoryFails() {
        when(repository.save(any())).thenThrow(new RuntimeException("DB unavailable"));

        assertThatCode(() ->
                service.log(AuditEventType.VALIDATION, AuditSourceFeature.SUMMARY,
                        null, null, null, null))
                .doesNotThrowAnyException();
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
        service.logQuery(AuditSourceFeature.ASK_AI, 1L, 2L, "s1", Map.of());
        ArgumentCaptor<AiAuditLedger> c = ArgumentCaptor.forClass(AiAuditLedger.class);
        verify(repository).save(c.capture());
        assertThat(c.getValue().getEventType()).isEqualTo("QUERY");
    }

    @Test
    void logResponse_setsResponseEventType() {
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        service.logResponse(AuditSourceFeature.ASK_AI, 1L, 2L, "s1", Map.of());
        ArgumentCaptor<AiAuditLedger> c = ArgumentCaptor.forClass(AiAuditLedger.class);
        verify(repository).save(c.capture());
        assertThat(c.getValue().getEventType()).isEqualTo("RESPONSE");
    }

    @Test
    void logValidation_setsValidationEventType() {
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        service.logValidation(AuditSourceFeature.SUMMARY, 1L, 2L, "s1", Map.of());
        ArgumentCaptor<AiAuditLedger> c = ArgumentCaptor.forClass(AiAuditLedger.class);
        verify(repository).save(c.capture());
        assertThat(c.getValue().getEventType()).isEqualTo("VALIDATION");
    }

    @Test
    void logConfirmation_setsConfirmationEventType() {
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        service.logConfirmation(AuditSourceFeature.CONFIRMATION_SERVICE, 1L, 2L, "s1", Map.of());
        ArgumentCaptor<AiAuditLedger> c = ArgumentCaptor.forClass(AiAuditLedger.class);
        verify(repository).save(c.capture());
        assertThat(c.getValue().getEventType()).isEqualTo("CONFIRMATION");
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
