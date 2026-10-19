package com.careconnect.service.ai.audit;

import com.careconnect.dto.ai.AiCitation;
import com.careconnect.model.ai.audit.AiAskAuditDeliverySupplement;
import com.careconnect.model.ai.audit.AiAskAuditEvent;
import com.careconnect.model.ai.audit.AiAskAuditRecord;
import com.careconnect.repository.ai.audit.AiAskAuditDeliverySupplementRepository;
import com.careconnect.repository.ai.audit.AiAskAuditEventRepository;
import com.careconnect.repository.ai.audit.AiAskAuditRecordRepository;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AiAskAuditServiceTest {

    @Mock
    private AiAskAuditRecordRepository recordRepository;
    @Mock
    private AiAskAuditEventRepository eventRepository;
    @Mock
    private AiAskAuditDeliverySupplementRepository deliveryRepository;

    private AiAskAuditService service;

    @BeforeEach
    void setUp() {
        service = new AiAskAuditService(
                recordRepository,
                eventRepository,
                deliveryRepository,
                new ObjectMapper());
        org.mockito.Mockito.lenient().when(recordRepository.save(any(AiAskAuditRecord.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        org.mockito.Mockito.lenient().when(eventRepository.save(any(AiAskAuditEvent.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        org.mockito.Mockito.lenient().when(deliveryRepository.save(any(AiAskAuditDeliverySupplement.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
    }

    @Test
    @DisplayName("startRequest appends REQUEST_STARTED with hash-only query")
    void startRequest_appendsStarted() {
        final AiAskAuditService.AuditSession session = service.startRequest(
                new AiAskAuditService.StartRequestCommand(
                        null,
                        null,
                        UUID.randomUUID(),
                        42L,
                        7L,
                        "CAREGIVER",
                        "TEXT",
                        "en-US",
                        "secret patient query",
                        null));

        assertThat(session.auditId()).isNotNull();
        assertThat(session.queryTextHash()).isEqualTo(
                AiAskAuditService.hashText("secret patient query", 42L));
        assertThat(session.queryTextHash()).doesNotContain("secret");

        final ArgumentCaptor<AiAskAuditEvent> eventCaptor =
                ArgumentCaptor.forClass(AiAskAuditEvent.class);
        verify(eventRepository).save(eventCaptor.capture());
        assertThat(eventCaptor.getValue().getEventType())
                .isEqualTo(AiAskAuditService.REQUEST_STARTED);
    }

    @Test
    @DisplayName("finalizeRecord inserts immutable row once")
    void finalizeRecord_insertsOnce() {
        final AiAskAuditService.AuditSession session = service.startRequest(
                new AiAskAuditService.StartRequestCommand(
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        42L,
                        7L,
                        "PATIENT",
                        "TEXT",
                        "en-US",
                        "metformin",
                        null));
        when(recordRepository.existsById(session.auditId())).thenReturn(false);

        service.finalizeRecord(
                session,
                AiAskAuditService.FinalizeCommand.delivered(
                        "Patient takes metformin",
                        List.of(),
                        Map.of("level", 1),
                        List.of(),
                        Map.of("chunksRetrieved", 1),
                        Map.of("patientId", 42L),
                        "model-1",
                        120));

        final ArgumentCaptor<AiAskAuditRecord> recordCaptor =
                ArgumentCaptor.forClass(AiAskAuditRecord.class);
        verify(recordRepository).save(recordCaptor.capture());
        assertThat(recordCaptor.getValue().getDeliveryStatus()).isEqualTo("DELIVERED");
        assertThat(recordCaptor.getValue().getAnswerTextHash())
                .isEqualTo(AiAskAuditService.hashText("Patient takes metformin", 42L));

        when(recordRepository.existsById(session.auditId())).thenReturn(true);
        service.finalizeRecord(
                session,
                AiAskAuditService.FinalizeCommand.delivered(
                        "ignored",
                        List.of(),
                        Map.of(),
                        List.of(),
                        Map.of(),
                        Map.of(),
                        "model-1",
                        1));
        verify(recordRepository).save(any());
    }

    @Test
    @DisplayName("appendStandaloneEvent continues sequence from repository max")
    void appendStandaloneEvent_continuesSequence() {
        final UUID auditId = UUID.randomUUID();
        when(eventRepository.findMaxSequence(auditId)).thenReturn(4);

        service.appendStandaloneEvent(
                auditId,
                AiAskAuditService.HITL_RELEASED,
                99L,
                Map.of("edited", true));

        final ArgumentCaptor<AiAskAuditEvent> eventCaptor =
                ArgumentCaptor.forClass(AiAskAuditEvent.class);
        verify(eventRepository).save(eventCaptor.capture());
        assertThat(eventCaptor.getValue().getEventSequence()).isEqualTo(5);
        assertThat(eventCaptor.getValue().getEventType())
                .isEqualTo(AiAskAuditService.HITL_RELEASED);
    }

    @Test
    @DisplayName("appendStandaloneEvent retries after unique sequence collision")
    void appendStandaloneEvent_retriesOnUniqueViolation() {
        final UUID auditId = UUID.randomUUID();
        when(eventRepository.findMaxSequence(auditId)).thenReturn(2, 3);
        when(eventRepository.save(any(AiAskAuditEvent.class)))
                .thenThrow(new DataIntegrityViolationException("uq_ai_ask_audit_event_seq"))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.appendStandaloneEvent(
                auditId,
                AiAskAuditService.HITL_EXPIRED,
                null,
                Map.of());

        verify(eventRepository, org.mockito.Mockito.times(2)).save(any(AiAskAuditEvent.class));
        verify(eventRepository, org.mockito.Mockito.times(2)).findMaxSequence(auditId);
    }

    @Test
    @DisplayName("NO_RECORDS finalize emits NO_RECORDS terminal event not ERROR")
    void finalizeRecord_noRecords_terminalEvent() {
        final AiAskAuditService.AuditSession session = service.startRequest(
                new AiAskAuditService.StartRequestCommand(
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        42L,
                        7L,
                        "PATIENT",
                        "TEXT",
                        "en-US",
                        "metformin",
                        null));
        when(recordRepository.existsById(session.auditId())).thenReturn(false);
        org.mockito.Mockito.clearInvocations(eventRepository);

        service.finalizeRecord(
                session,
                AiAskAuditService.FinalizeCommand.noRecords(
                        Map.of("chunksRetrieved", 0),
                        Map.of("patientId", 42L),
                        12));

        final ArgumentCaptor<AiAskAuditEvent> eventCaptor =
                ArgumentCaptor.forClass(AiAskAuditEvent.class);
        verify(eventRepository).save(eventCaptor.capture());
        assertThat(eventCaptor.getValue().getEventType())
                .isEqualTo(AiAskAuditService.NO_RECORDS);
        assertThat(AiAskAuditService.terminalEventType(
                AiAskAuditService.FinalizeCommand.noRecords(Map.of(), Map.of(), 1)))
                .isEqualTo(AiAskAuditService.NO_RECORDS);
    }

    @Test
    @DisplayName("finalizeRecord stores citation excerpt hashes only")
    void finalizeRecord_redactsCitationExcerpts() {
        final AiAskAuditService.AuditSession session = service.startRequest(
                new AiAskAuditService.StartRequestCommand(
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        42L,
                        7L,
                        "PATIENT",
                        "TEXT",
                        "en-US",
                        "metformin",
                        null));
        when(recordRepository.existsById(session.auditId())).thenReturn(false);
        final String excerpt = "Patient takes metformin 500mg twice daily";
        final AiCitation citation = new AiCitation(
                "C1",
                RetrievalRecordType.MEDICATION,
                "MEDICATION",
                "med-1",
                UUID.randomUUID(),
                "Medication list",
                excerpt,
                Instant.parse("2026-01-01T00:00:00Z"),
                "/medications/med-1",
                0.9,
                Map.of("note", "phi-metadata"));

        service.finalizeRecord(
                session,
                AiAskAuditService.FinalizeCommand.delivered(
                        "answer",
                        List.of(citation),
                        Map.of("level", 1),
                        List.of(),
                        Map.of("chunksRetrieved", 1),
                        Map.of("patientId", 42L),
                        "model-1",
                        50));

        final ArgumentCaptor<AiAskAuditRecord> recordCaptor =
                ArgumentCaptor.forClass(AiAskAuditRecord.class);
        verify(recordRepository).save(recordCaptor.capture());
        final String citationsJson = recordCaptor.getValue().getCitationsJson();
        assertThat(citationsJson).doesNotContain(excerpt);
        assertThat(citationsJson).doesNotContain("phi-metadata");
        assertThat(citationsJson).contains("excerptHash");
        assertThat(citationsJson).contains(
                AiAskAuditService.hashText(excerpt, 42L));
        assertThat(citationsJson).contains("\"excerptLength\":" + excerpt.length());
    }

    @Test
    @DisplayName("recordHitlDeliverySupplement redacts map citation excerpts")
    void recordHitlDeliverySupplement_redactsExcerpts() {
        final UUID auditId = UUID.randomUUID();
        final String excerpt = "Secret clinical note text";
        service.recordHitlDeliverySupplement(
                auditId,
                "DELIVERED",
                "final",
                42L,
                List.of(Map.of(
                        "citationId", "C1",
                        "excerpt", excerpt,
                        "title", "Note")),
                99L);

        final ArgumentCaptor<AiAskAuditDeliverySupplement> captor =
                ArgumentCaptor.forClass(AiAskAuditDeliverySupplement.class);
        verify(deliveryRepository).save(captor.capture());
        assertThat(captor.getValue().getCitationsJson()).doesNotContain(excerpt);
        assertThat(captor.getValue().getCitationsJson())
                .contains(AiAskAuditService.hashText(excerpt, 42L));
    }

    @Test
    @DisplayName("null audit id is a no-op")
    void appendStandaloneEvent_nullAuditId_noop() {
        service.appendStandaloneEvent(null, AiAskAuditService.HITL_EXPIRED, null, Map.of());
        verify(eventRepository, never()).save(any());
    }

    @Test
    @DisplayName("appendStandaloneEvent exhausts unique-violation retries")
    void appendStandaloneEvent_exhaustsRetriesOnUniqueViolation() {
        final UUID auditId = UUID.randomUUID();
        when(eventRepository.findMaxSequence(auditId)).thenReturn(1);
        when(eventRepository.save(any()))
                .thenThrow(new org.springframework.dao.DataIntegrityViolationException("uq"));

        service.appendStandaloneEvent(
                auditId, AiAskAuditService.HITL_EXPIRED, 9L, Map.of("k", "v"));

        verify(eventRepository, org.mockito.Mockito.times(3)).save(any());
    }

    @Test
    @DisplayName("appendEvent and finalize fail soft on repository errors")
    void appendEvent_and_finalize_failSoftOnRepositoryErrors() {
        final AiAskAuditService.AuditSession session = service.startRequest(
                new AiAskAuditService.StartRequestCommand(
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        UUID.randomUUID(),
                        42L,
                        7L,
                        "PATIENT",
                        "TEXT",
                        "en-US",
                        "metformin",
                        null));
        when(eventRepository.save(any())).thenThrow(new RuntimeException("event down"));
        when(recordRepository.existsById(session.auditId())).thenReturn(false);
        when(recordRepository.save(any())).thenThrow(new RuntimeException("record down"));

        service.appendEvent(session, AiAskAuditService.GOVERNANCE_BLOCKED, 7L, Map.of());
        service.finalizeRecord(
                session,
                AiAskAuditService.FinalizeCommand.error("RATE_LIMITED", Map.of("patientId", 42L), 5));
    }

    @Test
    @DisplayName("terminalEventType covers held/error defaults")
    void terminalEventType_heldAndErrorDefaults() {
        assertThat(AiAskAuditService.terminalEventType(null)).isEqualTo(AiAskAuditService.ERROR);
        assertThat(AiAskAuditService.terminalEventType(
                AiAskAuditService.FinalizeCommand.held(
                        UUID.randomUUID(),
                        "draft",
                        List.of(),
                        List.of(),
                        "[]",
                        Map.of(),
                        Map.of(),
                        "model",
                        1)))
                .isEqualTo(AiAskAuditService.HELD);
        assertThat(AiAskAuditService.terminalEventType(
                AiAskAuditService.FinalizeCommand.error("X", Map.of(), 1)))
                .isEqualTo(AiAskAuditService.ERROR);
    }

    @Test
    @DisplayName("recordHitlDeliverySupplement keeps precomputed excerptHash")
    void recordHitlDeliverySupplement_preservesExistingExcerptHash() {
        final UUID auditId = UUID.randomUUID();
        service.recordHitlDeliverySupplement(
                auditId,
                "DELIVERED",
                "final",
                42L,
                List.of(Map.of(
                        "citationId", "C1",
                        "excerptHash", "abc123",
                        "excerptLength", 12)),
                99L);

        final ArgumentCaptor<AiAskAuditDeliverySupplement> captor =
                ArgumentCaptor.forClass(AiAskAuditDeliverySupplement.class);
        verify(deliveryRepository).save(captor.capture());
        assertThat(captor.getValue().getCitationsJson()).contains("abc123");
        assertThat(captor.getValue().getCitationsJson()).doesNotContain("\"excerpt\"");
    }

    @Test
    @DisplayName("recordHitlDeliverySupplement null audit id is a no-op")
    void recordHitlDeliverySupplement_nullAuditId_noop() {
        service.recordHitlDeliverySupplement(null, "DELIVERED", "x", 1L, List.of(), 2L);
        verify(deliveryRepository, never()).save(any());
    }

    @Test
    @DisplayName("appendEvent null session is a no-op")
    void appendEvent_nullSession_noop() {
        service.appendEvent(null, AiAskAuditService.GOVERNANCE_BLOCKED, 1L, Map.of());
        verify(eventRepository, never()).save(any());
    }

    @Test
    @DisplayName("finalizeRecord null args is a no-op")
    void finalizeRecord_nullArgs_noop() {
        service.finalizeRecord(null, null);
        verify(recordRepository, never()).save(any());
    }

    @Test
    @DisplayName("appendStandaloneEvent fails soft on non-unique errors")
    void appendStandaloneEvent_nonUniqueFailure_failsSoft() {
        final UUID auditId = UUID.randomUUID();
        when(eventRepository.findMaxSequence(auditId)).thenReturn(0);
        when(eventRepository.save(any())).thenThrow(new RuntimeException("db down"));

        service.appendStandaloneEvent(auditId, AiAskAuditService.HITL_EXPIRED, null, Map.of());

        verify(eventRepository, org.mockito.Mockito.times(1)).save(any());
    }

    @Test
    @DisplayName("terminalEventType unknown status without error defaults to DELIVERED")
    void terminalEventType_unknownWithoutError_delivered() {
        assertThat(AiAskAuditService.terminalEventType(
                new AiAskAuditService.FinalizeCommand(
                        "WEIRD",
                        1,
                        false,
                        null,
                        null,
                        null,
                        List.of(),
                        Map.of(),
                        List.of(),
                        null,
                        Map.of(),
                        Map.of(),
                        null,
                        null,
                        1)))
                .isEqualTo(AiAskAuditService.DELIVERED);
    }

    @Test
    @DisplayName("recordHitlDeliverySupplement fails soft on save error")
    void recordHitlDeliverySupplement_saveFailsSoft() {
        when(deliveryRepository.save(any())).thenThrow(new RuntimeException("down"));
        service.recordHitlDeliverySupplement(
                UUID.randomUUID(), "DELIVERED", "ans", 42L, List.of(), 1L);
    }
}
