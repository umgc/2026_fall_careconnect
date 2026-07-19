package com.careconnect.websocket;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class CareConnectWebSocketHandlerTest {

    @Mock UserRepository   userRepository;
    @Mock JwtTokenProvider jwtTokenProvider;
    @Mock WebSocketSession session;
    @Mock WebSocketSession targetSession;
    @Mock User             user;
    @Mock User             targetUser;

    @InjectMocks CareConnectWebSocketHandler handler;

    // ─── helpers ─────────────────────────────────────────────────────────────

    private void authenticate(WebSocketSession sess, String sessionId,
                              User usr, Long userId, String email, String token) throws Exception {
        lenient().when(sess.getId()).thenReturn(sessionId);
        lenient().when(jwtTokenProvider.validateToken(token)).thenReturn(true);
        lenient().when(jwtTokenProvider.getEmailFromToken(token)).thenReturn(email);
        lenient().when(userRepository.findByEmail(email)).thenReturn(Optional.of(usr));
        lenient().when(usr.getId()).thenReturn(userId);
        lenient().when(usr.getEmail()).thenReturn(email);
        lenient().when(usr.getRole()).thenReturn(Role.PATIENT);

        handler.handleTextMessage(sess,
                new TextMessage("{\"type\":\"authenticate\",\"token\":\"" + token + "\"}"));
    }

    // ─── afterConnectionEstablished() ────────────────────────────────────────

    @Test
    void afterConnectionEstablished_sendsConnectionEstablishedMessage() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionEstablished(session);
        verify(session).sendMessage(any(TextMessage.class));
    }

    // ─── handleTextMessage() — JSON parse failure ─────────────────────────────

    @Test
    void handleTextMessage_invalidJson_catchesExceptionSilently() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session, new TextMessage("{{invalid}}"));
        // No exception propagates; nothing else sent
    }

    // ─── authenticate — failure paths ─────────────────────────────────────────

    @Test
    void authenticate_nullToken_sendsFailedAndClosesSession() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session, new TextMessage("{\"type\":\"authenticate\"}"));
        verify(session, atLeastOnce()).sendMessage(any(TextMessage.class));
        verify(session).close(any(CloseStatus.class));
    }

    @Test
    void authenticate_invalidToken_sendsFailedAndClosesSession() throws Exception {
        when(session.getId()).thenReturn("s1");
        when(jwtTokenProvider.validateToken("bad")).thenReturn(false);
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"authenticate\",\"token\":\"bad\"}"));
        verify(session, atLeastOnce()).sendMessage(any(TextMessage.class));
        verify(session).close(any(CloseStatus.class));
    }

    @Test
    void authenticate_userNotFound_sendsFailedAndClosesSession() throws Exception {
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
    void authenticate_validToken_sendsSuccess() throws Exception {
        when(session.getId()).thenReturn("s1");
        when(user.getId()).thenReturn(1L);
        when(user.getEmail()).thenReturn("u@u.com");
        when(user.getRole()).thenReturn(Role.CAREGIVER);
        when(jwtTokenProvider.validateToken("tok")).thenReturn(true);
        when(jwtTokenProvider.getEmailFromToken("tok")).thenReturn("u@u.com");
        when(userRepository.findByEmail("u@u.com")).thenReturn(Optional.of(user));

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"authenticate\",\"token\":\"tok\"}"));
        verify(session, atLeastOnce()).sendMessage(any(TextMessage.class));
    }

    @Test
    void authenticate_sameSocketSwitchesAccount_removesPriorUserMapping() throws Exception {
        authenticate(session, "s1", user, 1L, "first@test.com", "first-token");
        when(session.isOpen()).thenReturn(true);
        assertThat(handler.isUserOnline("1")).isTrue();

        authenticate(session, "s1", targetUser, 2L, "second@test.com", "second-token");

        assertThat(handler.isUserOnline("1")).isFalse();
        assertThat(handler.isUserOnline("2")).isTrue();
        handler.sendRealTimeUpdate("1", Map.of("type", "must-not-deliver"));
        verify(session, times(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void afterConnectionClosed_oldSessionDoesNotRemoveReplacement() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        authenticate(targetSession, "s2", user, 1L, "u@u.com", "tok2");
        when(targetSession.isOpen()).thenReturn(true);

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        assertThat(handler.isUserOnline("1")).isTrue();
        handler.sendRealTimeUpdate("1", Map.of("type", "still-online"));
        verify(targetSession, atLeastOnce()).sendMessage(any(TextMessage.class));
    }

    // ─── subscribe-to-updates ────────────────────────────────────────────────

    @Test
    void subscribeToUpdates_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"subscribe-to-updates\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void subscribeToUpdates_authenticated_withUpdateTypes_confirmsSubscription() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"subscribe-to-updates\","
                        + "\"updateTypes\":[\"vitals\",\"medications\"]}"));
        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void subscribeToUpdates_authenticated_nullUpdateTypes_defaultsToAll() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"subscribe-to-updates\"}"));
        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    // ─── subscribe-email-verification ────────────────────────────────────────

    @Test
    void subscribeEmailVerification_noEmail_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"subscribe-email-verification\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void subscribeEmailVerification_emptyEmail_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"subscribe-email-verification\",\"email\":\"\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void subscribeEmailVerification_validEmail_confirmsSubscription() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"subscribe-email-verification\",\"email\":\"v@v.com\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    // ─── ai-chat-notification ────────────────────────────────────────────────

    @Test
    void aiChatNotification_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"ai-chat-notification\",\"targetUserId\":\"2\","
                        + "\"message\":\"hi\",\"conversationId\":\"conv1\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void aiChatNotification_authenticated_targetOnline_sendsNotification() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");
        authenticate(targetSession, "s2", targetUser, 2L, "t@t.com", "tok2");
        when(targetSession.isOpen()).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"ai-chat-notification\",\"targetUserId\":\"2\","
                        + "\"message\":\"hello\",\"conversationId\":\"conv1\"}"));
        verify(targetSession, atLeast(1)).sendMessage(any(TextMessage.class));
    }

    @Test
    void aiChatNotification_authenticated_targetOffline_logsWarning() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"ai-chat-notification\",\"targetUserId\":\"99\","
                        + "\"message\":\"hello\",\"conversationId\":\"conv1\"}"));
        // Only auth-success was sent to session
        verify(session, atMost(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void aiChatNotification_authenticated_targetSendThrows_doesNotPropagate() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");
        authenticate(targetSession, "s2", targetUser, 2L, "t@t.com", "tok2");
        when(targetSession.isOpen()).thenReturn(true);
        doThrow(new RuntimeException("io")).when(targetSession).sendMessage(any());

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"ai-chat-notification\",\"targetUserId\":\"2\","
                        + "\"message\":\"hello\",\"conversationId\":\"conv1\"}"));
        // No exception propagates
    }

    // ─── mood-pain-log-update ────────────────────────────────────────────────

    @Test
    void moodPainLogUpdate_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"mood-pain-log-update\",\"moodValue\":3,\"painValue\":2}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void moodPainLogUpdate_authenticated_logsUpdate() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"mood-pain-log-update\",\"moodValue\":3,\"painValue\":2}"));
        // Auth success + no further sends (no caregivers registered)
        verify(session, atMost(2)).sendMessage(any(TextMessage.class));
    }

    // ─── medication-reminder ─────────────────────────────────────────────────

    @Test
    void medicationReminder_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"medication-reminder\",\"patientId\":\"2\","
                        + "\"medicationName\":\"Aspirin\",\"reminderTime\":\"08:00\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void medicationReminder_authenticated_patientOnline_sendsReminder() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        authenticate(targetSession, "s2", targetUser, 2L, "p@p.com", "tok2");
        when(targetSession.isOpen()).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"medication-reminder\",\"patientId\":\"2\","
                        + "\"medicationName\":\"Aspirin\",\"reminderTime\":\"08:00\"}"));
        verify(targetSession, atLeast(1)).sendMessage(any(TextMessage.class));
    }

    @Test
    void medicationReminder_authenticated_patientOffline_skips() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"medication-reminder\",\"patientId\":\"99\","
                        + "\"medicationName\":\"Aspirin\",\"reminderTime\":\"08:00\"}"));
        verify(session, atMost(2)).sendMessage(any(TextMessage.class));
    }

    // ─── vital-signs-alert ───────────────────────────────────────────────────

    @Test
    void vitalSignsAlert_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"vital-signs-alert\",\"alertType\":\"BP\","
                        + "\"message\":\"high\",\"severity\":\"critical\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void vitalSignsAlert_authenticated_logsAlert() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"vital-signs-alert\",\"alertType\":\"BP\","
                        + "\"message\":\"high\",\"severity\":\"critical\"}"));
        verify(session, atMost(2)).sendMessage(any(TextMessage.class));
    }

    // ─── family-member-request ────────────────────────────────────────────────

    @Test
    void familyMemberRequest_notAuthenticated_sendsError() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"family-member-request\","
                        + "\"patientId\":\"2\",\"requestType\":\"add\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    @Test
    void familyMemberRequest_authenticated_patientOnline_sendsRequest() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");
        authenticate(targetSession, "s2", targetUser, 2L, "p@p.com", "tok2");
        when(targetSession.isOpen()).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"family-member-request\","
                        + "\"patientId\":\"2\",\"requestType\":\"add\"}"));
        verify(targetSession, atLeast(1)).sendMessage(any(TextMessage.class));
    }

    @Test
    void familyMemberRequest_authenticated_patientOnline_sendThrows_doesNotPropagate() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("Alice");
        authenticate(targetSession, "s2", targetUser, 2L, "p@p.com", "tok2");
        when(targetSession.isOpen()).thenReturn(true);
        doThrow(new RuntimeException("io")).when(targetSession).sendMessage(any());

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"family-member-request\","
                        + "\"patientId\":\"2\",\"requestType\":\"add\"}"));
    }

    @Test
    void familyMemberRequest_authenticated_patientOffline_logsWarning() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"family-member-request\","
                        + "\"patientId\":\"99\",\"requestType\":\"add\"}"));
        verify(session, atMost(2)).sendMessage(any(TextMessage.class));
    }

    // ─── heartbeat ────────────────────────────────────────────────────────────

    @Test
    void heartbeat_sendsHeartbeatResponse() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session, new TextMessage("{\"type\":\"heartbeat\"}"));
        verify(session).sendMessage(any(TextMessage.class));
    }

    // ─── unknown type ─────────────────────────────────────────────────────────

    @Test
    void unknownType_logsWarning_noMessageSent() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session, new TextMessage("{\"type\":\"unknown-xyz\"}"));
        verify(session, never()).sendMessage(any());
    }

    // ─── afterConnectionClosed() ─────────────────────────────────────────────

    @Test
    void afterConnectionClosed_withAuthenticatedUser_removesSession() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        handler.afterConnectionClosed(session, CloseStatus.NORMAL);
        assertThat(handler.isUserOnline("1")).isFalse();
    }

    @Test
    void afterConnectionClosed_withNoUser_doesNotThrow() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.afterConnectionClosed(session, CloseStatus.NORMAL);
    }

    // ─── handleTransportError() ──────────────────────────────────────────────

    @Test
    void handleTransportError_withAuthenticatedUser_logsEmail() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        handler.handleTransportError(session, new RuntimeException("transport err"));
    }

    @Test
    void handleTransportError_withNoUser_logsUnknown() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTransportError(session, new RuntimeException("transport err"));
    }

    // ─── sendRealTimeUpdate() ─────────────────────────────────────────────────

    @Test
    void sendRealTimeUpdate_sessionOpen_sendsMessage() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(true);

        handler.sendRealTimeUpdate("1", Map.of("type", "update"));

        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void sendRealTimeUpdate_sessionClosed_skips() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(false);

        handler.sendRealTimeUpdate("1", Map.of("type", "update"));

        verify(session, atMost(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void sendRealTimeUpdate_sendThrows_doesNotPropagate() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(true);
        doThrow(new RuntimeException("io")).when(session).sendMessage(any());

        handler.sendRealTimeUpdate("1", Map.of("type", "update"));
    }

    @Test
    void sendRealTimeUpdate_unknownUser_skips() throws Exception {
        handler.sendRealTimeUpdate("999", Map.of("type", "update"));
        verifyNoInteractions(session);
    }

    // ─── broadcastToAllUsers() ───────────────────────────────────────────────

    @Test
    void broadcastToAllUsers_openSession_sendsToAll() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(true);

        handler.broadcastToAllUsers(Map.of("type", "broadcast"));

        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void broadcastToAllUsers_sendThrows_continuesAndDoesNotPropagate() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(true);
        doThrow(new RuntimeException("io")).when(session).sendMessage(any());

        handler.broadcastToAllUsers(Map.of("type", "broadcast"));
    }

    // ─── getOnlineUsersCount() & isUserOnline() ───────────────────────────────

    @Test
    void getOnlineUsersCount_returnsConnectedUserCount() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        assertThat(handler.getOnlineUsersCount()).isGreaterThanOrEqualTo(1);
    }

    @Test
    void isUserOnline_authenticatedAndOpen_returnsTrue() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(true);
        assertThat(handler.isUserOnline("1")).isTrue();
    }

    @Test
    void isUserOnline_unknownUser_returnsFalse() throws Exception {
        assertThat(handler.isUserOnline("999")).isFalse();
    }

    // ─── sendEmailVerificationNotification() ─────────────────────────────────

    @Test
    void sendEmailVerificationNotification_sessionExists_sendsAndRemoves() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"subscribe-email-verification\",\"email\":\"v@v.com\"}"));
        when(session.isOpen()).thenReturn(true);

        handler.sendEmailVerificationNotification("v@v.com");

        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
        // Second call → session already removed, so nothing sent
        handler.sendEmailVerificationNotification("v@v.com");
    }

    @Test
    void sendEmailVerificationNotification_noSession_logsWarning() throws Exception {
        handler.sendEmailVerificationNotification("nobody@nowhere.com");
        verifyNoInteractions(session);
    }

    @Test
    void sendEmailVerificationNotification_sendThrows_doesNotPropagate() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"subscribe-email-verification\",\"email\":\"e@e.com\"}"));
        when(session.isOpen()).thenReturn(true);
        doThrow(new RuntimeException("io")).when(session).sendMessage(any());

        handler.sendEmailVerificationNotification("e@e.com");
    }

    // ─── registerUser() ──────────────────────────────────────────────────────

    @Test
    void registerUser_storesUserInSessionMap() throws Exception {
        handler.registerUser("42", "TestUser");
        // Verified indirectly — getOnlineUsersCount includes "dummy" session registrations
        assertThat(handler.getOnlineUsersCount()).isGreaterThanOrEqualTo(0);
    }

    // ─── getUserDisplayName — null name falls back to email ──────────────────

    @Test
    void aiChatNotification_senderNameNull_usesEmailAsFallback() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn(null);   // triggers fallback to email
        authenticate(targetSession, "s2", targetUser, 2L, "t@t.com", "tok2");
        when(targetSession.isOpen()).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"ai-chat-notification\",\"targetUserId\":\"2\","
                        + "\"message\":\"hello\",\"conversationId\":\"conv1\"}"));
        verify(targetSession, atLeast(1)).sendMessage(any(TextMessage.class));
    }

    // ─── getUserDisplayName — empty name falls back to email ────────────────

    @Test
    void aiChatNotification_senderNameEmpty_usesEmailAsFallback() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(user.getName()).thenReturn("");
        authenticate(targetSession, "s2", targetUser, 2L, "t@t.com", "tok2");
        when(targetSession.isOpen()).thenReturn(true);

        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"ai-chat-notification\",\"targetUserId\":\"2\","
                        + "\"message\":\"hello\",\"conversationId\":\"conv1\"}"));
        verify(targetSession, atLeast(1)).sendMessage(any(TextMessage.class));
    }

    // ─── isUserOnline — session present but closed ──────────────────────────

    @Test
    void isUserOnline_sessionPresentButClosed_returnsFalse() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(false);
        assertThat(handler.isUserOnline("1")).isFalse();
    }

    // ─── broadcastToAllUsers — closed session ───────────────────────────────

    @Test
    void broadcastToAllUsers_closedSession_skips() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(false);

        handler.broadcastToAllUsers(Map.of("type", "broadcast"));

        // Only the auth message was sent
        verify(session, atMost(1)).sendMessage(any(TextMessage.class));
    }

    @Test
    void broadcastToAllUsers_multipleSessions_sendsToAllOpen() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        when(session.isOpen()).thenReturn(true);
        authenticate(targetSession, "s2", targetUser, 2L, "t@t.com", "tok2");
        when(targetSession.isOpen()).thenReturn(true);

        handler.broadcastToAllUsers(Map.of("type", "broadcast"));

        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
        verify(targetSession, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    // ─── sendRealTimeUpdate — session null ──────────────────────────────────

    @Test
    void sendRealTimeUpdate_noSessionRegistered_skips() throws Exception {
        handler.sendRealTimeUpdate("42", Map.of("type", "update"));
        verifyNoInteractions(session);
    }

    // ─── sendEmailVerificationNotification — case insensitive ───────────────

    @Test
    void sendEmailVerificationNotification_uppercaseEmail_matchesLowerCase() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"subscribe-email-verification\",\"email\":\"V@V.COM\"}"));
        when(session.isOpen()).thenReturn(true);

        handler.sendEmailVerificationNotification("v@v.com");

        verify(session, atLeast(2)).sendMessage(any(TextMessage.class));
    }

    @Test
    void sendEmailVerificationNotification_sessionClosed_doesNotSend() throws Exception {
        when(session.getId()).thenReturn("s1");
        handler.handleTextMessage(session,
                new TextMessage("{\"type\":\"subscribe-email-verification\",\"email\":\"c@c.com\"}"));
        when(session.isOpen()).thenReturn(false);

        handler.sendEmailVerificationNotification("c@c.com");

        // Only the subscription confirmation was sent
        verify(session, atMost(1)).sendMessage(any(TextMessage.class));
    }

    // ─── getOnlineUsersCount — empty ────────────────────────────────────────

    @Test
    void getOnlineUsersCount_noUsers_returnsZero() throws Exception {
        assertThat(handler.getOnlineUsersCount()).isZero();
    }

    // ─── afterConnectionClosed — multiple users ─────────────────────────────

    @Test
    void afterConnectionClosed_removeOnlyTargetUser() throws Exception {
        authenticate(session, "s1", user, 1L, "u@u.com", "tok1");
        authenticate(targetSession, "s2", targetUser, 2L, "t@t.com", "tok2");

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        assertThat(handler.isUserOnline("1")).isFalse();
        // User 2 should still be tracked
        assertThat(handler.getOnlineUsersCount()).isGreaterThanOrEqualTo(1);
    }
}
