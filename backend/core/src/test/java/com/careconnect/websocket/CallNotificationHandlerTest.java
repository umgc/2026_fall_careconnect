package com.careconnect.websocket;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.CallTelemetryService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.mockito.InjectMocks;

import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class CallNotificationHandlerTest {

    @Mock UserRepository                  userRepository;
    @Mock JwtTokenProvider                jwtTokenProvider;
    @Mock CallTelemetryService            callTelemetryService;
    @Mock CaregiverPatientLinkService     caregiverPatientLinkService;
    @Mock WebSocketSession                session;
    @Mock WebSocketSession                recipientSession;
    @Mock User                            user;
    @Mock User                            recipientUser;

    @InjectMocks CallNotificationHandler handler;

    //  helpers 

    /** Authenticate `sess` as `usr` (userId, email). Stubs are lenient so they
     *  can safely be declared even when not exercised by a particular code path. */
    private void authenticate(WebSocketSession sess, String sessionId,
                              User usr, Long userId, String email, String token) throws Exception {
        lenient().when(sess.getId()).thenReturn(sessionId);
        lenient().when(jwtTokenProvider.validateToken(token)).thenReturn(true);
        lenient().when(jwtTokenProvider.getEmailFromToken(token)).thenReturn(email);
        lenient().when(userRepository.findByEmail(email)).thenReturn(Optional.of(usr));
        lenient().when(usr.getId()).thenReturn(userId);
        lenient().when(usr.getEmail()).thenReturn(email);
        lenient().when(usr.getRole()).thenReturn(Role.PATIENT);

        final String json = "{\"type\":\"authenticate\",\"token\":\"" + token + "\"}";
        handler.handleTextMessage(sess, new TextMessage(json));
    }

    //  afterConnectionEstablished() 

    @Test
    void afterConnectionEstablished_sendsConnectionEstablishedMessage() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);
        verify(session).sendMessage(any(TextMessage.class));
    }

    //  handleTextMessage()  exception in JSON parsing 

    @Test
    void handleTextMessage_invalidJson_catchesExceptionAndSendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session, new TextMessage("not-valid-json{{{"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void handleTextMessage_invalidJson_sendMessageThrows_doesNotPropagate() throws Exception {
        when(session.getId()).thenReturn("s1");
        doThrow(new RuntimeException("io-err")).when(session).sendMessage(any());
        handler.handleTextMessage(session, new TextMessage("not-valid-json{{{"));
        // No exception escapes
    }

    //  authenticate  token null / invalid 

    @Test
    void authenticate_nullToken_sendsAuthFailedAndClosesSession() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session, new TextMessage("{\"type\":\"authenticate\"}"));
        verify(session, atLeastOnce()).sendMessage(any(TextMessage.class));
        verify(session).close(any(CloseStatus.class));
    }

    @Test
    void authenticate_invalidToken_sendsAuthFailedAndClosesSession() throws Exception {
        when(session.getId()).thenReturn("s1");
        when(jwtTokenProvider.validateToken("bad-token")).thenReturn(false);
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"authenticate\",\"token\":\"bad-token\"}"));
        verify(session, atLeastOnce()).sendMessage(any(TextMessage.class));
        verify(session).close(any(CloseStatus.class));
    }

    @Test
    void authenticate_userNotFound_sendsAuthFailedAndClosesSession() throws Exception {
        when(session.getId()).thenReturn("s1");
        when(jwtTokenProvider.validateToken("t")).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken("t")).thenReturn("x@x.com");
        when(userRepository.findByEmail("x@x.com")).thenReturn(Optional.empty());
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"authenticate\",\"token\":\"t\"}"));
        verify(session, atLeastOnce()).sendMessage(any(TextMessage.class));
        verify(session).close(any(CloseStatus.class));
    }

    @Test
    void authenticate_validToken_sendsAuthSuccessAndStoresSession() throws Exception {
        when(session.getId()).thenReturn("s1");
        when(user.getId()).thenReturn(1L);
        when(user.getEmail()).thenReturn("u@u.com");
        when(user.getRole()).thenReturn(Role.PATIENT);
        when(jwtTokenProvider.validateToken("tok")).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken("tok")).thenReturn("u@u.com");
        when(userRepository.findByEmail("u@u.com")).thenReturn(Optional.of(user));

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"authenticate\",\"token\":\"tok\"}"));
        verify(session, atLeastOnce()).sendMessage(any(TextMessage.class));
    }

    //  join-user-room 

    @Test
    void joinUserRoom_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"join-user-room\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void joinUserRoom_authenticated_sendsUserJoined() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"join-user-room\"}"));
        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    //  send-video-call-invitation 

    @Test
    void callInvitation_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\",\"recipientId\":\"2\",\"callId\":\"c1\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void callInvitation_recipientNotFound_sendsError() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\",\"recipientId\":\"99\",\"callId\":\"c1\"}"));
        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void callInvitation_recipientOnline_sendsInvitationAndConfirmation() throws Exception {
        // Authenticate sender
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");

        // Authenticate recipient so their session is stored
        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientUser.getName()).thenReturn("Bob");
        when(recipientSession.isOpen()).thenReturn(true);

        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\"}"));

        verify(recipientSession, atLeast(1)).sendMessage(any(TextMessage.class));
        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void callInvitation_recipientOffline_sendsFailureToSender() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));
        when(recipientUser.getEmail()).thenReturn("r@r.com");

        // recipientUser session is NOT registered  offline
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\"}"));

        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    // getUserDisplayName  null/empty name  email branch

    @Test
    void callInvitation_senderNameNull_usesEmail() throws Exception {
        // Authenticate sender (name=null  falls back to email in getUserDisplayName)
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn(null);

        // Authenticate recipient so the online path is taken and getUserDisplayName is exercised
        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientUser.getName()).thenReturn(null);
        when(recipientUser.getEmail()).thenReturn("r@r.com");
        when(recipientSession.isOpen()).thenReturn(true);

        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\"}"));
        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    //  send-sms-notification 

    @Test
    void smsNotification_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-sms-notification\",\"recipientId\":\"2\",\"message\":\"hi\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void smsNotification_recipientNotFound_sendsError() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-sms-notification\","
                        + "\"recipientId\":\"99\",\"message\":\"hi\"}"));
        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void smsNotification_recipientOnline_deliversSmsAndConfirms() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");
        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientUser.getName()).thenReturn("Bob");
        when(recipientSession.isOpen()).thenReturn(true);
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-sms-notification\","
                        + "\"recipientId\":\"2\",\"message\":\"hi\"}"));

        verify(recipientSession, atLeast(1)).sendMessage(any(TextMessage.class));
        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void smsNotification_recipientOffline_sendsFailureToSender() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));
        when(recipientUser.getEmail()).thenReturn("r@r.com");

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-sms-notification\","
                        + "\"recipientId\":\"2\",\"message\":\"hi\"}"));
        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    //  accept-call 

    @Test
    void acceptCall_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"accept-call\",\"callId\":\"c1\",\"senderId\":\"2\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void acceptCall_authenticated_senderOnline_notifiesSender() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientSession.isOpen()).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"accept-call\",\"callId\":\"c1\",\"senderId\":\"2\"}"));
        verify(recipientSession, atLeast(1)).sendMessage(any(TextMessage.class));
    }

    @Test
    void acceptCall_authenticated_senderOffline_noNotification() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");

        // sender "99" has no registered session
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"accept-call\",\"callId\":\"c1\",\"senderId\":\"99\"}"));
        // Only the authentication success message is sent
        verify(session, atMost(2)).sendMessage(any(TextMessage.class));
    }

    //  decline-call 

    @Test
    void declineCall_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"decline-call\",\"callId\":\"c1\",\"senderId\":\"2\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void declineCall_authenticated_senderOnline_notifiesSender() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientSession.isOpen()).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"decline-call\",\"callId\":\"c1\","
                        + "\"senderId\":\"2\",\"reason\":\"busy\"}"));
        verify(recipientSession, atLeast(1)).sendMessage(any(TextMessage.class));
    }

    @Test
    void declineCall_authenticated_senderOffline_noNotification() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"decline-call\",\"callId\":\"c1\",\"senderId\":\"99\"}"));
        verify(session, atMost(2)).sendMessage(any(TextMessage.class));
    }

    //  end-call 

    @Test
    void endCall_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"end-call\",\"callId\":\"c1\",\"otherPartyId\":\"2\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void endCall_authenticated_otherPartyOnline_doesNotNotifyOtherParty() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientSession.isOpen()).thenReturn(true);
        clearInvocations(recipientSession);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"end-call\",\"callId\":\"c1\",\"otherPartyId\":\"2\"}"));
        verify(recipientSession, never()).sendMessage(any(TextMessage.class));
    }

    @Test
    void endCall_authenticated_otherPartyOffline_noNotification() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"end-call\",\"callId\":\"c1\",\"otherPartyId\":\"99\"}"));
        verify(session, atMost(2)).sendMessage(any(TextMessage.class));
    }

    //  heartbeat 

    @Test
    void heartbeat_sendsHeartbeatResponse() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"heartbeat\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    //  unknown type 

    @Test
    void unknownType_logsWarningAndSendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"some-unknown-type\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    //  afterConnectionClosed() 

    @Test
    void afterConnectionClosed_withAuthenticatedUser_removesEntries() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        // User should be gone  getOnlineUsers returns empty
        assertThat(handler.getOnlineUsers()).doesNotContainKey("1");
    }

    @Test
    void afterConnectionClosed_withNoUser_doesNotThrow() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionClosed(session, CloseStatus.NORMAL);
        // Just verifying no exception
    }

    //  handleTransportError() 

    @Test
    void handleTransportError_withAuthenticatedUser_logsUserEmail() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        handler.handleTransportError(session, new RuntimeException("err"));
        // No exception expected
    }

    @Test
    void handleTransportError_withNoUser_logsUnknown() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTransportError(session, new RuntimeException("err"));
        // No exception expected
    }

    //  sendNotificationToUser() (public) 

    @Test
    void sendNotificationToUser_sessionOpen_sendsMessage() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(true);

        handler.sendNotificationToUser("1", Map.of("type", "test"));

        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void sendNotificationToUser_sessionNotOpen_skips() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(false);

        handler.sendNotificationToUser("1", Map.of("type", "test"));

        // Only the auth-success message was sent
        verify(session, atMost(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void sendNotificationToUser_sendThrows_doesNotPropagate() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(true);
        doThrow(new RuntimeException("io")).when(session).sendMessage(any());

        // Must not propagate
        handler.sendNotificationToUser("1", Map.of("type", "test"));
    }

    @Test
    void sendNotificationToUser_unknownUser_skips() throws Exception {
        handler.sendNotificationToUser("999", Map.of("type", "test"));
        // No interaction with session
        verifyNoInteractions(session);
    }

    //  getOnlineUsers() 

    @Test
    void getOnlineUsers_returnsMapOfIdToEmail() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");

        final Map<String, String> online = handler.getOnlineUsers();

        assertThat(online).containsEntry("1", "u@u.com");
    }

    //  sendCallInvitation() & sendSMSNotification() 

    @Test
    void sendCallInvitation_delegatesToSendNotificationToUser() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(true);

        handler.sendCallInvitation("1", Map.of("type", "call-invite"));

        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void sendSMSNotification_delegatesToSendNotificationToUser() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(true);

        handler.sendSMSNotification("1", Map.of("type", "sms"));

        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    //  getUserDisplayName  preferred name, email-like, role fallback 

    @Test
    void callInvitation_callerNameProvided_usesCallerName() throws Exception {
        // Sender must be CAREGIVER to avoid patient-to-patient block
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");
        when(user.getRole()).thenReturn(Role.CAREGIVER);

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientUser.getName()).thenReturn("Bob");
        when(recipientSession.isOpen()).thenReturn(true);
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\","
                        + "\"callerName\":\"Dr. Smith\"}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(2)).sendMessage(captor.capture());
        boolean found = captor.getAllValues().stream()
                .anyMatch(m -> m.getPayload().contains("Dr. Smith"));
        assertThat(found).isTrue();
    }

    @Test
    void callInvitation_callerNameIsEmail_fallsBackToUserName() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");
        when(user.getRole()).thenReturn(Role.CAREGIVER);

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientUser.getName()).thenReturn("Bob");
        when(recipientSession.isOpen()).thenReturn(true);
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\","
                        + "\"callerName\":\"user@example.com\"}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(2)).sendMessage(captor.capture());
        boolean found = captor.getAllValues().stream()
                .anyMatch(m -> m.getPayload().contains("incoming-video-call")
                        && m.getPayload().contains("Alice"));
        assertThat(found).isTrue();
    }

    @Test
    void callInvitation_callerNameEmpty_fallsBackToUserName() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");
        when(user.getRole()).thenReturn(Role.CAREGIVER);

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientUser.getName()).thenReturn("Bob");
        when(recipientSession.isOpen()).thenReturn(true);
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\","
                        + "\"callerName\":\"  \"}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(2)).sendMessage(captor.capture());
        boolean found = captor.getAllValues().stream()
                .anyMatch(m -> m.getPayload().contains("incoming-video-call")
                        && m.getPayload().contains("Alice"));
        assertThat(found).isTrue();
    }

    @Test
    void callInvitation_emptyNameWithRole_usesCapitalizedRoleForSender() throws Exception {
        // When user.getName() is empty, getUserDisplayName falls back to role
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("");
        when(user.getRole()).thenReturn(Role.PATIENT);

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientUser.getName()).thenReturn("Bob");
        when(recipientUser.getRole()).thenReturn(Role.CAREGIVER);
        when(recipientSession.isOpen()).thenReturn(true);
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        // Patient calling caregiver  needs link
        when(caregiverPatientLinkService.hasAccessToPatient(2L, 1L)).thenReturn(true);
        when(caregiverPatientLinkService.isPatientVideoCallsEnabled(2L, 1L)).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\"}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(2)).sendMessage(captor.capture());
        // senderName should fall back to capitalized role "Patient"
        boolean found = captor.getAllValues().stream()
                .anyMatch(m -> m.getPayload().contains("Patient"));
        assertThat(found).isTrue();
    }

    @Test
    void callInvitation_nullNameWithRole_usesCapitalizedRole() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn(null);
        when(user.getRole()).thenReturn(Role.CAREGIVER);

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientUser.getName()).thenReturn("Bob");
        when(recipientSession.isOpen()).thenReturn(true);
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\"}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(2)).sendMessage(captor.capture());
        boolean found = captor.getAllValues().stream()
                .anyMatch(m -> m.getPayload().contains("Caregiver"));
        assertThat(found).isTrue();
    }

    //  CALL-017: patient-to-patient calls blocked 

    @Test
    void callInvitation_patientToPatient_sendsCallInvitationFailed() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getRole()).thenReturn(Role.PATIENT);

        when(recipientUser.getId()).thenReturn(2L);
        when(recipientUser.getEmail()).thenReturn("r@r.com");
        when(recipientUser.getRole()).thenReturn(Role.PATIENT);
        when(recipientUser.getName()).thenReturn("Bob");
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\"}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(captor.capture());
        String payload = captor.getValue().getPayload();
        assertThat(payload).contains("call-invitation-failed");
        assertThat(payload).contains("Patient-to-patient");
    }

    //  CALL-016: patient-to-caregiver  no link 

    @Test
    void callInvitation_patientToCaregiver_noLink_sendsCallInvitationFailed() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getRole()).thenReturn(Role.PATIENT);

        when(recipientUser.getId()).thenReturn(2L);
        when(recipientUser.getEmail()).thenReturn("r@r.com");
        when(recipientUser.getRole()).thenReturn(Role.CAREGIVER);
        when(recipientUser.getName()).thenReturn("Dr. Jones");
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        when(caregiverPatientLinkService.hasAccessToPatient(2L, 1L)).thenReturn(false);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\"}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(captor.capture());
        String payload = captor.getValue().getPayload();
        assertThat(payload).contains("call-invitation-failed");
        assertThat(payload).contains("No active caregiver-patient link");
    }

    //  CALL-016: patient-to-caregiver  link exists but calls disabled 

    @Test
    void callInvitation_patientToCaregiver_callsDisabled_sendsCallInvitationFailed()
            throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getRole()).thenReturn(Role.PATIENT);

        when(recipientUser.getId()).thenReturn(2L);
        when(recipientUser.getEmail()).thenReturn("r@r.com");
        when(recipientUser.getRole()).thenReturn(Role.CAREGIVER);
        when(recipientUser.getName()).thenReturn("Dr. Jones");
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        when(caregiverPatientLinkService.hasAccessToPatient(2L, 1L)).thenReturn(true);
        when(caregiverPatientLinkService.isPatientVideoCallsEnabled(2L, 1L)).thenReturn(false);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\"}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(captor.capture());
        String payload = captor.getValue().getPayload();
        assertThat(payload).contains("call-invitation-failed");
        assertThat(payload).contains("disabled patient-initiated calls");
    }

    //  CALL-016: patient-to-caregiver  link and calls enabled 

    @Test
    void callInvitation_patientToCaregiver_linkedAndEnabled_sendsInvitation() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getRole()).thenReturn(Role.PATIENT);
        when(user.getName()).thenReturn("PatientA");

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientUser.getRole()).thenReturn(Role.CAREGIVER);
        when(recipientUser.getName()).thenReturn("Dr. Jones");
        when(recipientSession.isOpen()).thenReturn(true);
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        when(caregiverPatientLinkService.hasAccessToPatient(2L, 1L)).thenReturn(true);
        when(caregiverPatientLinkService.isPatientVideoCallsEnabled(2L, 1L)).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\"}"));

        verify(recipientSession, atLeast(1)).sendMessage(any(TextMessage.class));
    }

    //  caregiver-to-patient  no link check required 

    @Test
    void callInvitation_caregiverToPatient_noLinkCheckRequired() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getRole()).thenReturn(Role.CAREGIVER);
        when(user.getName()).thenReturn("Dr. Jones");

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientUser.getRole()).thenReturn(Role.PATIENT);
        when(recipientUser.getName()).thenReturn("PatientA");
        when(recipientSession.isOpen()).thenReturn(true);
        when(userRepository.findById(2L)).thenReturn(Optional.of(recipientUser));

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"send-video-call-invitation\","
                        + "\"recipientId\":\"2\",\"callId\":\"c1\"}"));

        verify(recipientSession, atLeast(1)).sendMessage(any(TextMessage.class));
        // Link service should NOT have been consulted
        verify(caregiverPatientLinkService, never()).hasAccessToPatient(any(), any());
    }

    //  sentiment-channel-state 

    @Test
    void sentimentChannelState_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"sentiment-channel-state\","
                        + "\"channel\":\"text\",\"otherPartyId\":\"2\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void sentimentChannelState_invalidChannel_sendsError() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"sentiment-channel-state\","
                        + "\"channel\":\"invalid\",\"otherPartyId\":\"2\"}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(captor.capture());
        String payload = captor.getValue().getPayload();
        assertThat(payload).contains("Invalid channel");
    }

    @Test
    void sentimentChannelState_missingOtherPartyId_sendsError() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"sentiment-channel-state\","
                        + "\"channel\":\"text\"}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeast(2)).sendMessage(captor.capture());
        String payload = captor.getValue().getPayload();
        assertThat(payload).contains("otherPartyId is required");
    }

    @Test
    void sentimentChannelState_textChannel_otherPartyOnline_sendsState() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientSession.isOpen()).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"sentiment-channel-state\","
                        + "\"channel\":\"text\",\"otherPartyId\":\"2\","
                        + "\"callId\":\"c1\",\"muted\":false}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(2)).sendMessage(captor.capture());
        String payload = captor.getValue().getPayload();
        assertThat(payload).contains("sentiment-channel-state");
        assertThat(payload).contains("AWAITING");
    }

    @Test
    void sentimentChannelState_voiceChannel_muted_sendsState() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientSession.isOpen()).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"sentiment-channel-state\","
                        + "\"channel\":\"voice\",\"otherPartyId\":\"2\","
                        + "\"callId\":\"c1\",\"muted\":true}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(2)).sendMessage(captor.capture());
        String payload = captor.getValue().getPayload();
        assertThat(payload).contains("MUTED");
    }

    @Test
    void sentimentChannelState_videoChannel_withCaptureMode_includesCaptureMode() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientSession.isOpen()).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"sentiment-channel-state\","
                        + "\"channel\":\"video\",\"otherPartyId\":\"2\","
                        + "\"callId\":\"c1\",\"muted\":false,"
                        + "\"captureMode\":\"continuous\"}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(2)).sendMessage(captor.capture());
        String payload = captor.getValue().getPayload();
        assertThat(payload).contains("continuous");
    }

    @Test
    void sentimentChannelState_otherPartyOffline_doesNotThrow() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"sentiment-channel-state\","
                        + "\"channel\":\"text\",\"otherPartyId\":\"99\","
                        + "\"callId\":\"c1\",\"muted\":false}"));
        // No exception; no message sent to non-existent party
    }

    //  telemetry recording 

    @Test
    void handleTextMessage_recordsTelemetryOnSuccess() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"heartbeat\"}"));

        verify(callTelemetryService).recordWebSocketEvent(
                any(), eq("WS_HEARTBEAT"), any(), any(), any(), eq("SUCCESS"), any());
    }

    @Test
    void handleTextMessage_recordsTelemetryOnError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session, new TextMessage("{{{bad-json"));

        verify(callTelemetryService).recordWebSocketEvent(
                any(), any(), any(), any(), any(), eq("ERROR"), any());
    }

    //  decline-call  default reason 

    @Test
    void declineCall_noReasonProvided_usesDefaultDeclined() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");

        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");
        when(recipientSession.isOpen()).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"decline-call\",\"callId\":\"c1\",\"senderId\":\"2\"}"));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(recipientSession, atLeast(1)).sendMessage(captor.capture());
        String payload = captor.getValue().getPayload();
        assertThat(payload).contains("declined");
    }

    //  getOnlineUsers  empty 

    @Test
    void getOnlineUsers_noAuthenticatedUsers_returnsEmptyMap() {
        assertThat(handler.getOnlineUsers()).isEmpty();
    }

    //  afterConnectionClosed  multiple users 

    @Test
    void afterConnectionClosed_removesOnlyDisconnectedUser() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok2");

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        Map<String, String> online = handler.getOnlineUsers();
        assertThat(online).doesNotContainKey("1");
        assertThat(online).containsKey("2");
    }

    @Test
    void afterConnectionClosed_oldSessionDoesNotRemoveReplacementSession() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        authenticate(recipientSession, "s2", user, 1L, "u@u.com", "tok2");
        when(recipientSession.isOpen()).thenReturn(true);

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);
        handler.sendNotificationToUser("1", Map.of("type", "test"));

        assertThat(handler.isUserOnline("1")).isTrue();
        verify(recipientSession, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void authenticate_crossAccountRebind_detachesPriorIdentityAtomically() throws Exception {
        authenticate(session, "s1", user, 1L, "first@test.com", "first-token");
        when(session.isOpen()).thenReturn(true);
        assertThat(handler.isUserOnline("1")).isTrue();

        authenticate(session, "s1", recipientUser, 2L, "second@test.com", "second-token");

        assertThat(handler.isUserOnline("1")).isFalse();
        assertThat(handler.isUserOnline("2")).isTrue();
        handler.sendNotificationToUser("1", Map.of("type", "must-not-deliver"));
        verify(session, times(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void rebindThenCloseRace_oldSocketCannotRemoveReplacement() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        authenticate(recipientSession, "s2", user, 1L, "u@u.com", "tok2");
        when(recipientSession.isOpen()).thenReturn(true);

        // Cross-account rebind on the replacement socket, then stale close of the first socket.
        authenticate(recipientSession, "s2", recipientUser, 2L, "r@r.com", "tok3");
        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        assertThat(handler.isUserOnline("1")).isFalse();
        assertThat(handler.isUserOnline("2")).isTrue();
        handler.sendNotificationToUser("2", Map.of("type", "still-online"));
        verify(recipientSession, atLeast(3)).sendMessage(any(TextMessage.class));
    }

    @Test
    void handleTextMessage_exception_sendsRedactedPublicError() throws Exception {
        when(session.getId()).thenReturn("s1");
        ArgumentCaptor<TextMessage> errorCaptor = ArgumentCaptor.forClass(TextMessage.class);

        handler.handleTextMessage(session, new TextMessage("not-valid-json{{{"));

        verify(session).sendMessage(errorCaptor.capture());
        String payload = errorCaptor.getValue().getPayload();
        assertThat(payload).contains("\"code\":\"INTERNAL_ERROR\"");
        assertThat(payload).contains("Unable to process message");
        assertThat(payload).doesNotContain("JsonParseException");
        assertThat(payload).doesNotContain("Unexpected character");
    }
}
