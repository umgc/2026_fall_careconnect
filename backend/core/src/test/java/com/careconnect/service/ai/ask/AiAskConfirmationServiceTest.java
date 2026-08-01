package com.careconnect.service.ai.ask;

import com.careconnect.dto.ai.AiAskConfirmationRequest;
import com.careconnect.model.User;
import com.careconnect.model.ai.ask.AiAskConfirmationDecision;
import com.careconnect.repository.ai.ask.AiAskConfirmationDecisionRepository;
import com.careconnect.security.Role;
import com.careconnect.service.ai.audit.AiAskAuditService;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import com.careconnect.service.ai.retrieval.ScopeDenialReason;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AiAskConfirmationServiceTest {

    @Mock
    private AiAskConfirmationDecisionRepository decisionRepository;
    @Mock
    private AiAskAuditService askAuditService;
    @Mock
    private RetrievalScopeService retrievalScopeService;

    private AiAskConfirmationService service;

    @BeforeEach
    void setUp() {
        service = new AiAskConfirmationService(
                decisionRepository, askAuditService, retrievalScopeService, 12L);
    }

    @Test
    void recordDecision_enforcesPatientScopeBeforeSave() throws Exception {
        final User caller = user(9L);
        final UUID sessionId = UUID.randomUUID();
        final UUID requestId = UUID.randomUUID();
        final AiAskConfirmationRequest request = new AiAskConfirmationRequest(
                sessionId, 42L, requestId, null, "APPROVE_ONCE");
        when(decisionRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        final AiAskConfirmationDecision saved = service.recordDecision(caller, request);

        verify(retrievalScopeService).assertCanAsk(eq(caller), eq(42L), isNull());
        assertThat(saved.getDecision()).isEqualTo(AiAskConfirmationService.APPROVE_ONCE);
        assertThat(saved.getPatientId()).isEqualTo(42L);
        assertThat(saved.getCallerUserId()).isEqualTo(9L);
    }

    @Test
    void recordDecision_rejectsForbiddenScope() throws Exception {
        final User caller = user(9L);
        final AiAskConfirmationRequest request = new AiAskConfirmationRequest(
                UUID.randomUUID(), 99L, null, null, "DECLINE");
        doThrow(ForbiddenScopeException.of(
                        ScopeDenialReason.PATIENT_OUT_OF_SCOPE, 99L, 9L, "denied", null))
                .when(retrievalScopeService)
                .assertCanAsk(eq(caller), eq(99L), isNull());

        assertThatThrownBy(() -> service.recordDecision(caller, request))
                .isInstanceOf(ForbiddenScopeException.class);
        verify(decisionRepository, never()).save(any());
    }

    @Test
    void recordDecision_isIdempotentForSameRequestAndDecision() throws Exception {
        final User caller = user(9L);
        final UUID requestId = UUID.randomUUID();
        final AiAskConfirmationDecision existing = AiAskConfirmationDecision.builder()
                .id(UUID.randomUUID())
                .sessionId(UUID.randomUUID())
                .patientId(42L)
                .callerUserId(9L)
                .requestId(requestId)
                .decision(AiAskConfirmationService.APPROVE_ONCE)
                .createdAt(Instant.now())
                .build();
        when(decisionRepository.findFirstByRequestIdAndCallerUserIdAndDecisionOrderByCreatedAtDesc(
                        requestId, 9L, AiAskConfirmationService.APPROVE_ONCE))
                .thenReturn(Optional.of(existing));

        final AiAskConfirmationDecision result = service.recordDecision(
                caller,
                new AiAskConfirmationRequest(
                        existing.getSessionId(), 42L, requestId, null, "approve-once"));

        assertThat(result).isSameAs(existing);
        verify(decisionRepository, never()).save(any());
        verify(retrievalScopeService).assertCanAsk(eq(caller), eq(42L), isNull());
    }

    @Test
    void hasTerminalDecisionForRequest_trueWhenAnyDecisionExists() {
        final UUID requestId = UUID.randomUUID();
        when(decisionRepository.existsByRequestIdAndCallerUserIdAndDecision(
                        eq(requestId), eq(9L), anyString()))
                .thenAnswer(invocation ->
                        AiAskConfirmationService.DECLINE.equals(invocation.getArgument(2)));

        assertThat(service.hasTerminalDecisionForRequest(requestId, 9L)).isTrue();
    }

    @Test
    void hasActiveSessionApproval_queriesRepository() {
        final UUID sessionId = UUID.randomUUID();
        when(decisionRepository
                        .findFirstBySessionIdAndPatientIdAndCallerUserIdAndDecisionOrderByCreatedAtDesc(
                                sessionId, 42L, 9L, AiAskConfirmationService.APPROVE_SESSION))
                .thenReturn(Optional.of(AiAskConfirmationDecision.builder()
                        .id(UUID.randomUUID())
                        .sessionId(sessionId)
                        .patientId(42L)
                        .callerUserId(9L)
                        .decision(AiAskConfirmationService.APPROVE_SESSION)
                        .createdAt(Instant.now())
                        .build()));

        assertThat(service.hasActiveSessionApproval(sessionId, 42L, 9L)).isTrue();
    }

    @Test
    void hasActiveSessionApproval_falseWhenOlderThanTtl() {
        final UUID sessionId = UUID.randomUUID();
        when(decisionRepository
                        .findFirstBySessionIdAndPatientIdAndCallerUserIdAndDecisionOrderByCreatedAtDesc(
                                sessionId, 42L, 9L, AiAskConfirmationService.APPROVE_SESSION))
                .thenReturn(Optional.of(AiAskConfirmationDecision.builder()
                        .id(UUID.randomUUID())
                        .sessionId(sessionId)
                        .patientId(42L)
                        .callerUserId(9L)
                        .decision(AiAskConfirmationService.APPROVE_SESSION)
                        .createdAt(Instant.now().minus(java.time.Duration.ofHours(13)))
                        .build()));

        assertThat(service.hasActiveSessionApproval(sessionId, 42L, 9L)).isFalse();
    }

    @Test
    void hasCallSummarySessionApproval_ignoresAskTtl() {
        final String callId = "call-ttl";
        final UUID sessionId = AiAskConfirmationService.callSummarySessionId(callId);
        when(decisionRepository
                        .findFirstBySessionIdAndPatientIdAndCallerUserIdAndDecisionOrderByCreatedAtDesc(
                                sessionId, 42L, 9L, AiAskConfirmationService.APPROVE_SESSION))
                .thenReturn(Optional.of(AiAskConfirmationDecision.builder()
                        .id(UUID.randomUUID())
                        .sessionId(sessionId)
                        .patientId(42L)
                        .callerUserId(9L)
                        .decision(AiAskConfirmationService.APPROVE_SESSION)
                        .createdAt(Instant.now().minus(java.time.Duration.ofDays(30)))
                        .build()));

        assertThat(service.hasCallSummarySessionApproval(callId, 42L, 9L)).isTrue();
        assertThat(service.hasActiveSessionApproval(sessionId, 42L, 9L)).isFalse();
    }

    @Test
    void installCallSummarySessionApproval_skipsAssertCanAskAndPersists() throws Exception {
        final User caller = user(9L);
        when(decisionRepository
                        .findFirstBySessionIdAndPatientIdAndCallerUserIdAndDecisionOrderByCreatedAtDesc(
                                any(), eq(42L), eq(9L), eq(AiAskConfirmationService.APPROVE_SESSION)))
                .thenReturn(Optional.empty());
        when(decisionRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        final AiAskConfirmationDecision saved =
                service.installCallSummarySessionApproval(caller, 42L, "call-42");

        assertThat(saved.getDecision()).isEqualTo(AiAskConfirmationService.APPROVE_SESSION);
        assertThat(saved.getSessionId())
                .isEqualTo(AiAskConfirmationService.callSummarySessionId("call-42"));
        verify(retrievalScopeService, never()).assertCanAsk(any(), any(), any());
        verify(decisionRepository).save(any());
    }

    @Test
    void hasActiveSessionApproval_falseForNullArgsOrMissingRow() {
        assertThat(service.hasActiveSessionApproval(null, 42L, 9L)).isFalse();
        assertThat(service.hasActiveSessionApproval(UUID.randomUUID(), null, 9L)).isFalse();
        assertThat(service.hasActiveSessionApproval(UUID.randomUUID(), 42L, null)).isFalse();

        final UUID sessionId = UUID.randomUUID();
        when(decisionRepository
                        .findFirstBySessionIdAndPatientIdAndCallerUserIdAndDecisionOrderByCreatedAtDesc(
                                sessionId, 42L, 9L, AiAskConfirmationService.APPROVE_SESSION))
                .thenReturn(Optional.empty());
        assertThat(service.hasActiveSessionApproval(sessionId, 42L, 9L)).isFalse();
    }

    @Test
    void hasActiveSessionApproval_neverExpiresWhenTtlDisabled() {
        final AiAskConfirmationService noTtl = new AiAskConfirmationService(
                decisionRepository, askAuditService, retrievalScopeService, 0L);
        final UUID sessionId = UUID.randomUUID();
        when(decisionRepository
                        .findFirstBySessionIdAndPatientIdAndCallerUserIdAndDecisionOrderByCreatedAtDesc(
                                sessionId, 42L, 9L, AiAskConfirmationService.APPROVE_SESSION))
                .thenReturn(Optional.of(AiAskConfirmationDecision.builder()
                        .id(UUID.randomUUID())
                        .sessionId(sessionId)
                        .patientId(42L)
                        .callerUserId(9L)
                        .decision(AiAskConfirmationService.APPROVE_SESSION)
                        .createdAt(Instant.now().minus(java.time.Duration.ofDays(40)))
                        .build()));

        assertThat(noTtl.hasActiveSessionApproval(sessionId, 42L, 9L)).isTrue();
        assertThat(noTtl.isAskSessionApprovalExpired(null)).isTrue();
        assertThat(noTtl.isAskSessionApprovalExpired(AiAskConfirmationDecision.builder()
                        .createdAt(null)
                        .build()))
                .isTrue();
    }

    @Test
    void callSummarySessionId_rejectsBlank() {
        assertThatThrownBy(() -> AiAskConfirmationService.callSummarySessionId("  "))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("callId");
        assertThatThrownBy(() -> AiAskConfirmationService.callSummarySessionId(null))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void hasCallSummarySessionApproval_falseForBlankInputs() {
        assertThat(service.hasCallSummarySessionApproval(null, 42L, 9L)).isFalse();
        assertThat(service.hasCallSummarySessionApproval(" ", 42L, 9L)).isFalse();
        assertThat(service.hasCallSummarySessionApproval("call", null, 9L)).isFalse();
        assertThat(service.hasCallSummarySessionApproval("call", 42L, null)).isFalse();
    }

    @Test
    void installCallSummarySessionApproval_validatesArgsAndReturnsExisting() {
        assertThatThrownBy(() -> service.installCallSummarySessionApproval(null, 42L, "c1"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.installCallSummarySessionApproval(user(9L), null, "c1"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.installCallSummarySessionApproval(user(9L), 42L, " "))
                .isInstanceOf(IllegalArgumentException.class);

        final AiAskConfirmationDecision existing = AiAskConfirmationDecision.builder()
                .id(UUID.randomUUID())
                .sessionId(AiAskConfirmationService.callSummarySessionId("call-dup"))
                .patientId(42L)
                .callerUserId(9L)
                .decision(AiAskConfirmationService.APPROVE_SESSION)
                .createdAt(Instant.now())
                .build();
        when(decisionRepository
                        .findFirstBySessionIdAndPatientIdAndCallerUserIdAndDecisionOrderByCreatedAtDesc(
                                any(), eq(42L), eq(9L), eq(AiAskConfirmationService.APPROVE_SESSION)))
                .thenReturn(Optional.of(existing));

        assertThat(service.installCallSummarySessionApproval(user(9L), 42L, "call-dup"))
                .isSameAs(existing);
        verify(decisionRepository, never()).save(any());
    }

    @Test
    void hasDecision_and_hasTerminal_handleNullsAndMisses() {
        assertThat(service.hasDecision(null, 9L, "APPROVE_ONCE")).isFalse();
        assertThat(service.hasDecision(UUID.randomUUID(), null, "APPROVE_ONCE")).isFalse();
        assertThat(service.hasDecision(UUID.randomUUID(), 9L, " ")).isFalse();
        assertThat(service.hasTerminalDecisionForRequest(null, 9L)).isFalse();
        assertThat(service.hasTerminalDecisionForRequest(UUID.randomUUID(), null)).isFalse();

        final UUID requestId = UUID.randomUUID();
        when(decisionRepository.existsByRequestIdAndCallerUserIdAndDecision(
                        eq(requestId), eq(9L), anyString()))
                .thenReturn(false);
        assertThat(service.hasTerminalDecisionForRequest(requestId, 9L)).isFalse();
        assertThat(service.hasDecision(requestId, 9L, "approve once")).isFalse();
    }

    @Test
    void recordDecision_rejectsInvalidInputAndAppendsAudit() throws Exception {
        assertThatThrownBy(() -> service.recordDecision(null, null))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.recordDecision(
                        user(9L),
                        new AiAskConfirmationRequest(null, 42L, null, null, "APPROVE_ONCE")))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.recordDecision(
                        user(9L),
                        new AiAskConfirmationRequest(
                                UUID.randomUUID(), 42L, null, null, "NOPE")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("APPROVE_ONCE");

        final UUID auditId = UUID.randomUUID();
        final UUID sessionId = UUID.randomUUID();
        when(decisionRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        org.mockito.Mockito.doThrow(new RuntimeException("audit down"))
                .when(askAuditService)
                .appendStandaloneEvent(any(), anyString(), any(), any());

        final AiAskConfirmationDecision saved = service.recordDecision(
                user(9L),
                new AiAskConfirmationRequest(sessionId, 42L, null, auditId, "DECLINE"));

        assertThat(saved.getDecision()).isEqualTo(AiAskConfirmationService.DECLINE);
        verify(askAuditService).appendStandaloneEvent(
                eq(auditId), eq("CONFIRMATION_DECLINE"), eq(9L), any());
    }

    private static User user(final Long id) {
        final User user = new User();
        user.setId(id);
        user.setRole(Role.CAREGIVER);
        return user;
    }
}
