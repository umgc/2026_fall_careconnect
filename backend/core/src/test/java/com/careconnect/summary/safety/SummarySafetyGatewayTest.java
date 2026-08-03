package com.careconnect.summary.safety;

import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import com.careconnect.model.confirmation.ConfirmationSourceType;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.service.confirmation.ConfirmationService;
import com.careconnect.service.safety.AiAuditLedgerService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

/**
 * Fast unit-level tests around {@link SummarySafetyGateway}. All external services are
 * mocked; this catches contract-level mistakes (wrong source enum, missing correlation
 * key, JSON shape drift, ledger swallow semantics) without touching a database.
 *
 * <p>Atomicity (transaction propagation) is NOT tested here — that requires real beans
 * and a real DB, and is covered by {@code SummarySafetyAtomicityIT}.
 */
class SummarySafetyGatewayTest {

    private ConfirmationService confirmationService;
    private AiAuditLedgerService auditLedgerService;
    private ObjectMapper objectMapper;
    private SummarySafetyGateway gateway;

    @BeforeEach
    void setUp() {
        confirmationService = mock(ConfirmationService.class);
        auditLedgerService = mock(AiAuditLedgerService.class);
        objectMapper = new ObjectMapper();
        gateway = new SummarySafetyGateway(confirmationService, auditLedgerService, objectMapper);
    }

    // ── gateConfirmables ──────────────────────────────────────────────────

    @Test
    void gateConfirmables_createsOneItemPerConfirmable_withSummaryIdAsReferenceId() {
        SummarySafetyContext context = new SummarySafetyContext(
                42L, 100L, 200L, "sess-1",
                List.of(
                        new SummarySafetyContext.Confirmable("ACTION_ITEM", "Took aspirin", "81mg daily"),
                        new SummarySafetyContext.Confirmable("CARE_INSTRUCTION", "Elevate leg", null)
                )
        );

        gateway.gateConfirmables(context);

        ArgumentCaptor<String> refIdCaptor = ArgumentCaptor.forClass(String.class);
        verify(confirmationService, times(2)).createItem(
                eq(ConfirmationSourceType.SUMMARY),
                any(String.class),
                refIdCaptor.capture(),
                eq(100L)
        );
        assertThat(refIdCaptor.getAllValues()).containsOnly("42");
    }

    @Test
    void gateConfirmables_serializesHeadlineTypeDetailAndSummaryId() throws Exception {
        SummarySafetyContext context = new SummarySafetyContext(
                42L, 100L, 200L, null,
                List.of(new SummarySafetyContext.Confirmable("ACTION_ITEM", "Took aspirin", "81mg daily"))
        );

        gateway.gateConfirmables(context);

        ArgumentCaptor<String> payloadCaptor = ArgumentCaptor.forClass(String.class);
        verify(confirmationService).createItem(any(), payloadCaptor.capture(), any(), any());
        JsonNode payload = objectMapper.readTree(payloadCaptor.getValue());
        assertThat(payload.get("headline").asText()).isEqualTo("Took aspirin");
        assertThat(payload.get("type").asText()).isEqualTo("ACTION_ITEM");
        assertThat(payload.get("detail").asText()).isEqualTo("81mg daily");
        assertThat(payload.get("summaryId").asLong()).isEqualTo(42L);
    }

    @Test
    void gateConfirmables_tolerates_nullDetailAndHeadline() throws Exception {
        SummarySafetyContext context = new SummarySafetyContext(
                42L, 100L, 200L, null,
                List.of(new SummarySafetyContext.Confirmable("CONDITION", null, null))
        );

        gateway.gateConfirmables(context);

        ArgumentCaptor<String> payloadCaptor = ArgumentCaptor.forClass(String.class);
        verify(confirmationService).createItem(any(), payloadCaptor.capture(), any(), any());
        JsonNode payload = objectMapper.readTree(payloadCaptor.getValue());
        assertThat(payload.get("headline").asText()).isEmpty();
        assertThat(payload.get("detail").asText()).isEmpty();
    }

    @Test
    void gateConfirmables_propagatesFailureFromCreateItem() {
        SummarySafetyContext context = new SummarySafetyContext(
                42L, 100L, 200L, "sess-1",
                List.of(new SummarySafetyContext.Confirmable("ACTION_ITEM", "x", "y"))
        );
        doThrow(new RuntimeException("gate failed"))
                .when(confirmationService).createItem(any(), any(), any(), any());

        assertThatThrownBy(() -> gateway.gateConfirmables(context))
                .isInstanceOf(RuntimeException.class)
                .hasMessage("gate failed");
    }

    @Test
    void gateConfirmables_emptyList_doesNotCreateAnyItem() {
        SummarySafetyContext context = new SummarySafetyContext(
                42L, 100L, 200L, "sess-1", List.of()
        );

        gateway.gateConfirmables(context);

        verify(confirmationService, never()).createItem(any(), any(), any(), any());
    }

    // ── logExtractionResponse ─────────────────────────────────────────────

    @Test
    void logExtractionResponse_emitsRESPONSE_SUMMARY_withCorrelationAttributes() {
        SummarySafetyContext context = new SummarySafetyContext(
                42L, 100L, 200L, "sess-1", List.of()
        );

        gateway.logExtractionResponse(context, 3);

        verify(auditLedgerService).logResponse(
                eq(AuditSourceFeature.SUMMARY),
                eq(100L),
                eq(200L),
                eq("sess-1"),
                anyMap()
        );
    }

    @Test
    void logExtractionResponse_swallowsLedgerFailure_neverThrowsToCaller() {
        SummarySafetyContext context = new SummarySafetyContext(
                42L, 100L, 200L, "sess-1", List.of()
        );
        doThrow(new RuntimeException("ledger disk full"))
                .when(auditLedgerService).logResponse(any(), any(), any(), any(), any());

        gateway.logExtractionResponse(context, 3);   // does NOT throw

        verify(auditLedgerService, times(1)).logResponse(any(), any(), any(), any(), any());
        verify(confirmationService, never()).createItem(any(), any(), any(), any());
    }
}
