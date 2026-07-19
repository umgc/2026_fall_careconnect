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
    @Mock private CallRecordingService callRecordingService;
    @Mock private ChimeService chimeService;
    @Mock private CallNotificationHandler notificationHandler;

    private CallTerminationReconciler reconciler;

    @BeforeEach
    void setUp() {
        reconciler = new CallTerminationReconciler(
                callSessionService,
                callRecordingService,
                chimeService,
                notificationHandler);
    }

    @Test
    void reconcileDueTerminations_claimsAndCompletesWithUuidFence() {
        final UUID claimId = UUID.randomUUID();
        when(callSessionService.findDueTerminationIds(25)).thenReturn(List.of(10L));
        when(callSessionService.claimDueTermination(10L))
                .thenReturn(new CallSessionService.TerminationClaim(
                        "call-1", claimId, List.of(7L)));
        when(callSessionService.completeTermination("call-1", claimId)).thenReturn(true);

        reconciler.reconcileDueTerminations();

        verify(callRecordingService).stopRecording("call-1");
        verify(chimeService).endMeeting("call-1");
        verify(callSessionService).completeTermination("call-1", claimId);
        verify(notificationHandler).sendNotificationToUser(
                "7",
                java.util.Map.of(
                        "type", "call-ended",
                        "callId", "call-1",
                        "endedBy", "SYSTEM"));
    }

    @Test
    void reconcile_recordsFailureForClaimOwner() {
        final UUID claimId = UUID.randomUUID();
        final RuntimeException failure = new RuntimeException("delete failed");
        when(callSessionService.claimDueTermination(10L))
                .thenReturn(new CallSessionService.TerminationClaim(
                        "call-1", claimId, List.of()));
        when(callRecordingService.stopRecording("call-1")).thenThrow(failure);

        reconciler.reconcile(10L);

        verify(callSessionService).recordTerminationFailure("call-1", claimId, failure);
        verify(chimeService, never()).endMeeting("call-1");
    }

    @Test
    void reconcile_skipsCandidateLostToAnotherNode() {
        reconciler.reconcile(10L);

        verify(callRecordingService, never()).stopRecording("call-1");
        verify(chimeService, never()).endMeeting("call-1");
    }
}
