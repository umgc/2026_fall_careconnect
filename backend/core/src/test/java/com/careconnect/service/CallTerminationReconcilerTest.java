package com.careconnect.service;

import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.websocket.CallNotificationHandler;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CallTerminationReconcilerTest {

    @Mock private CallSessionService callSessionService;
    @Mock private CallTerminationExecutor callTerminationExecutor;
    @Mock private CallNotificationHandler notificationHandler;

    private CallTerminationReconciler reconciler;

    @BeforeEach
    void setUp() {
        reconciler = new CallTerminationReconciler(
                callSessionService,
                callTerminationExecutor,
                notificationHandler);
    }

    @Test
    void reconcileDueTerminations_claimsAndCompletesWithUuidFence() {
        final UUID claimId = UUID.randomUUID();
        when(callSessionService.findDueTerminationIds(25)).thenReturn(List.of(10L));
        when(callSessionService.claimDueTermination(10L))
                .thenReturn(new CallSessionService.TerminationClaim(
                        "call-1", claimId, List.of(7L)));
        when(callTerminationExecutor.execute("call-1", null, claimId)).thenReturn(true);

        reconciler.reconcileDueTerminations();

        verify(callTerminationExecutor).execute("call-1", null, claimId);
        verify(notificationHandler).sendNotificationToUser(
                "7",
                java.util.Map.of(
                        "type", "call-ended",
                        "callId", "call-1",
                        "endedBy", "SYSTEM",
                        "status", "ended"));
    }

    @Test
    void reconcileDueTerminations_claimFailureDoesNotAbortBatch() {
        final UUID claimId = UUID.randomUUID();
        when(callSessionService.findDueTerminationIds(25)).thenReturn(List.of(10L, 11L));
        when(callSessionService.claimDueTermination(10L))
                .thenThrow(new IllegalStateException("claim failed"));
        when(callSessionService.claimDueTermination(11L))
                .thenReturn(new CallSessionService.TerminationClaim(
                        "call-2", claimId, List.of()));
        when(callTerminationExecutor.execute("call-2", null, claimId)).thenReturn(true);

        reconciler.reconcileDueTerminations();

        verify(callSessionService).claimDueTermination(11L);
        verify(callTerminationExecutor).execute("call-2", null, claimId);
    }

    @Test
    void reconcile_skipsCandidateLostToAnotherNode() {
        reconciler.reconcile(10L);

        verify(callTerminationExecutor, never()).execute(
                org.mockito.ArgumentMatchers.any(),
                org.mockito.ArgumentMatchers.any(),
                org.mockito.ArgumentMatchers.any());
    }

    @Test
    void reconcile_skipsNotificationWhenExecutorDoesNotFenceEnded() {
        final UUID claimId = UUID.randomUUID();
        when(callSessionService.claimDueTermination(10L))
                .thenReturn(new CallSessionService.TerminationClaim(
                        "call-1", claimId, List.of(7L)));
        when(callTerminationExecutor.execute("call-1", null, claimId)).thenReturn(false);

        reconciler.reconcile(10L);

        verify(callTerminationExecutor).execute("call-1", null, claimId);
        verify(notificationHandler, never()).sendNotificationToUser(
                org.mockito.ArgumentMatchers.any(),
                org.mockito.ArgumentMatchers.any());
    }
}
