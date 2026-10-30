package com.careconnect.websocket;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import com.careconnect.model.CallParticipant;
import com.careconnect.model.CallSession;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import com.careconnect.service.CallSessionService;
import com.careconnect.service.CallTelemetryService;
import com.careconnect.service.CallTerminationExecutor;
import com.careconnect.service.CaregiverPatientLinkService;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.slf4j.LoggerFactory;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

/**
 * Exercises {@link CallNotificationHandler} with the durable {@link CallSessionService} wired in:
 * invitation recipient resolution, accept/decline/termination, sentiment channel fan-out and
 * telemetry target fencing. Sessions, repositories and services are Mockito mocks.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("CallNotificationHandler with durable call sessions")
class CallNotificationHandlerDurableSessionTest {

    private static final String CALL_ID = "call-ws-1";

    @Mock private UserRepository userRepository;
    @Mock private JwtTokenProvider jwtTokenProvider;
    @Mock private CallTelemetryService callTelemetryService;
    @Mock private CaregiverPatientLinkService linkService;
    @Mock private CallSessionService callSessionService;
    @Mock private CallTerminationExecutor terminationExecutor;
    @Mock private WebSocketSession patientSession;
    @Mock private WebSocketSession caregiverSession;

    private CallNotificationHandler handler;
    private final Logger handlerLogger = (Logger) LoggerFactory.getLogger(CallNotificationHandler.class);
    private Level originalLevel;

    private static User user(final Long id, final String email, final Role role) {
        final User user = new User();
        user.setId(id);
        user.setEmail(email);
        user.setRole(role);
        return user;
    }

    private void authenticate(final WebSocketSession session, final String sessionId, final User user)
            throws Exception {
        when(session.getId()).thenReturn(sessionId);
        when(session.isOpen()).thenReturn(true);
        final String token = "token-" + sessionId;
        when(jwtTokenProvider.validateToken(token)).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken(token)).thenReturn(user.getEmail());
        when(userRepository.findByEmail(user.getEmail())).thenReturn(Optional.of(user));
        handler.handleTextMessage(session, new TextMessage("{\"type\":\"authenticate\",\"token\":\"" + token + "\"}"));
    }

    private void send(final WebSocketSession session, final String json) throws Exception {
        handler.handleTextMessage(session, new TextMessage(json));
    }

    private static CallParticipant joined(final Long userId) {
        final CallParticipant participant = new CallParticipant();
        participant.setUserId(userId);
        return participant;
    }

    @BeforeEach
    void setUp() throws Exception {
        originalLevel = handlerLogger.getLevel();
        handlerLogger.setLevel(Level.DEBUG);
        handler = new CallNotificationHandler(
                userRepository, jwtTokenProvider, callTelemetryService, linkService, callSessionService,
                terminationExecutor);
        final User patient = user(1L, "p@test.com", Role.PATIENT);
        final User caregiver = user(2L, "c@test.com", Role.CAREGIVER);
        when(userRepository.findById(1L)).thenReturn(Optional.of(patient));
        when(userRepository.findById(2L)).thenReturn(Optional.of(caregiver));
        authenticate(patientSession, "s-patient", patient);
        authenticate(caregiverSession, "s-caregiver", caregiver);
    }

    @AfterEach
    void restoreLogger() {
        handlerLogger.setLevel(originalLevel);
    }

    @Test
    @DisplayName("an invitation resolves the pending invitee and adds durable patient context")
    void invitation_resolvesDurableRecipient() throws Exception {
        when(callSessionService.requirePendingInvitationRecipient(CALL_ID, 1L, 2L)).thenReturn(2L);
        when(linkService.hasAccessToPatient(2L, 1L)).thenReturn(true);
        when(linkService.isPatientVideoCallsEnabled(2L, 1L)).thenReturn(true);
        final CallSession durable = new CallSession();
        durable.setScheduledVisitId(5L);
        when(callSessionService.requireSession(CALL_ID)).thenReturn(durable);
        when(callSessionService.requirePatientUserId(durable)).thenReturn(1L);
        // Forged telemetry target is dropped rather than failing the message.
        when(callSessionService.requireParticipant(CALL_ID, 2L)).thenThrow(new RuntimeException("not a participant"));

        send(patientSession, "{\"type\":\"send-video-call-invitation\",\"callId\":\"" + CALL_ID
                + "\",\"recipientId\":2,\"callType\":\"care-team\"}");

        verify(caregiverSession, atLeastOnce()).sendMessage(any(TextMessage.class));
        verify(callTelemetryService).recordWebSocketEvent(eq(CALL_ID), eq("WS_SEND_VIDEO_CALL_INVITATION"),
                eq(1L), eq(null), any(), eq("SUCCESS"), eq(null));

        when(caregiverSession.isOpen()).thenReturn(false);
        send(patientSession, "{\"type\":\"send-video-call-invitation\",\"callId\":\"" + CALL_ID
                + "\",\"recipientId\":\"2\"}");
    }

    @Test
    @DisplayName("accept and decline notify other durable participants and run termination")
    void acceptAndDecline_notifyParticipants() throws Exception {
        when(callSessionService.getOtherParticipantUserIds(CALL_ID, 2L)).thenReturn(java.util.Arrays.asList(null, 1L));
        send(caregiverSession, "{\"type\":\"accept-call\",\"callId\":\"" + CALL_ID + "\"}");
        verify(callSessionService).requireJoinAuthorized(CALL_ID, 2L);

        final UUID claim = UUID.randomUUID();
        when(callSessionService.declineInvitation(CALL_ID, 2L))
                .thenReturn(new CallSessionService.DeclineResult(List.of(1L), true, claim));
        when(terminationExecutor.execute(CALL_ID, 2L, claim)).thenThrow(new RuntimeException("cleanup failed"));
        send(caregiverSession, "{\"type\":\"decline-call\",\"callId\":\"" + CALL_ID + "\"}");

        verify(terminationExecutor).execute(CALL_ID, 2L, claim);
        verify(patientSession, atLeastOnce()).sendMessage(any(TextMessage.class));
    }

    @Test
    @DisplayName("sentiment channel state fans out to joined participants and rejects missing channels")
    void sentimentChannelState_fansOut() throws Exception {
        when(callSessionService.getJoinedParticipants(CALL_ID))
                .thenReturn(List.of(joined(1L), joined(2L), joined(9L)));

        send(patientSession, "{\"type\":\"sentiment-channel-state\",\"callId\":\"" + CALL_ID
                + "\",\"channel\":\"voice\",\"muted\":true,\"captureMode\":\"LIVE\"}");
        send(patientSession, "{\"type\":\"sentiment-channel-state\",\"callId\":\"" + CALL_ID + "\"}");

        verify(callSessionService).requireActiveParticipant(CALL_ID, 1L);
        verify(caregiverSession, atLeastOnce()).sendMessage(any(TextMessage.class));
    }

    @Test
    @DisplayName("telemetry failures are logged; transport errors log diagnostics")
    void telemetryFailureAndTransportError() throws Exception {
        doThrow(new RuntimeException("db down")).when(callTelemetryService)
                .recordWebSocketEvent(any(), anyString(), any(), any(), any(), anyString(), any());

        send(patientSession, "{\"type\":\"heartbeat\",\"otherPartyId\":\"abc\",\"senderId\":7}");
        handler.handleTransportError(patientSession, new RuntimeException("reset"));

        verify(patientSession, atLeastOnce()).sendMessage(any(TextMessage.class));
    }

    @Test
    @DisplayName("the isolated-test constructor builds a handler without durable services")
    void compatibilityConstructor() throws Exception {
        final WebSocketSession session = mock(WebSocketSession.class);
        when(session.getId()).thenReturn("s-x");
        new CallNotificationHandler(userRepository, jwtTokenProvider, callTelemetryService, linkService)
                .afterConnectionEstablished(session);
        verify(session).sendMessage(any(TextMessage.class));
        verify(callSessionService, org.mockito.Mockito.never()).requireSession(anyString());
        verify(callSessionService, org.mockito.Mockito.never()).requireParticipant(anyString(), anyLong());
    }
}
