package com.careconnect.service;

import com.careconnect.dto.CaregiverPatientLinkResponse;
import com.careconnect.websocket.CallNotificationHandler;
import com.careconnect.websocket.CareConnectWebSocketHandler;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class WebSocketNotificationServiceTest {

    @Mock
    private CallNotificationHandler callNotificationHandler;

    @Mock
    private CareConnectWebSocketHandler careConnectWebSocketHandler;

    @Mock
    private CaregiverPatientLinkService caregiverPatientLinkService;

    @InjectMocks
    private WebSocketNotificationService webSocketNotificationService;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
    }

    // ── registerUser ──

    @Test
    @DisplayName("registerUser_validInputs_callsHandlerRegisterUser")
    void registerUser_validInputs_callsHandlerRegisterUser() throws Exception {
        webSocketNotificationService.registerUser("user1", "John Doe");

        verify(careConnectWebSocketHandler).registerUser("user1", "John Doe");
    }

    // ── sendCallInvitation ──

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendCallInvitation_validParams_sendsNotification")
    void sendCallInvitation_validParams_sendsNotification() throws Exception {
        webSocketNotificationService.sendCallInvitation(
                "recipient1", "sender1", "Alice", "call123", true, "general");

        verify(callNotificationHandler).sendNotificationToUser(eq("recipient1"), any(Map.class));
    }

    // ── sendSMSNotification ──

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendSMSNotification_validParams_sendsNotification")
    void sendSMSNotification_validParams_sendsNotification() throws Exception {
        webSocketNotificationService.sendSMSNotification(
                "recipient1", "sender1", "Alice", "Hello!", "general");

        verify(callNotificationHandler).sendNotificationToUser(eq("recipient1"), any(Map.class));
    }

    // ── sendAIChatNotification ──

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendAIChatNotification_validParams_sendsRealTimeUpdate")
    void sendAIChatNotification_validParams_sendsRealTimeUpdate() throws Exception {
        webSocketNotificationService.sendAIChatNotification("user1", "conv123", "AI response here");

        verify(careConnectWebSocketHandler).sendRealTimeUpdate(eq("user1"), any(Map.class));
    }

    // ── sendMoodPainLogUpdate ──

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendMoodPainLogUpdate_validParams_sendsRealTimeUpdate")
    void sendMoodPainLogUpdate_validParams_sendsRealTimeUpdate() throws Exception {
        webSocketNotificationService.sendMoodPainLogUpdate("patient1", "John Doe", 7, 3);

        verify(careConnectWebSocketHandler).sendRealTimeUpdate(eq("patient1"), any(Map.class));
    }

    // ── sendMedicationReminder ──

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendMedicationReminder_validParams_sendsRealTimeUpdate")
    void sendMedicationReminder_validParams_sendsRealTimeUpdate() throws Exception {
        webSocketNotificationService.sendMedicationReminder("patient1", "Metformin", "08:00", "500mg");

        verify(careConnectWebSocketHandler).sendRealTimeUpdate(eq("patient1"), any(Map.class));
    }

    // ── sendVitalSignsAlert ──

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendVitalSignsAlert_multipleRecipients_sendsToAll")
    void sendVitalSignsAlert_multipleRecipients_sendsToAll() throws Exception {
        final String[] recipientIds = {"doc1", "doc2", "doc3"};

        webSocketNotificationService.sendVitalSignsAlert(
                "patient1", "John Doe", "heart-rate", "High heart rate", "HIGH", recipientIds);

        verify(careConnectWebSocketHandler, times(3)).sendRealTimeUpdate(anyString(), any(Map.class));
        verify(careConnectWebSocketHandler).sendRealTimeUpdate(eq("doc1"), any(Map.class));
        verify(careConnectWebSocketHandler).sendRealTimeUpdate(eq("doc2"), any(Map.class));
        verify(careConnectWebSocketHandler).sendRealTimeUpdate(eq("doc3"), any(Map.class));
    }

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendVitalSignsAlert_singleRecipient_sendsToOne")
    void sendVitalSignsAlert_singleRecipient_sendsToOne() throws Exception {
        final String[] recipientIds = {"doc1"};

        webSocketNotificationService.sendVitalSignsAlert(
                "patient1", "John Doe", "bp", "Low BP", "CRITICAL", recipientIds);

        verify(careConnectWebSocketHandler, times(1)).sendRealTimeUpdate(eq("doc1"), any(Map.class));
    }

    // ── sendFamilyMemberRequest ──

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendFamilyMemberRequest_validParams_sendsRealTimeUpdate")
    void sendFamilyMemberRequest_validParams_sendsRealTimeUpdate() throws Exception {
        webSocketNotificationService.sendFamilyMemberRequest(
                "patient1", "user2", "Jane Smith", "jane@example.com", "Daughter");

        verify(careConnectWebSocketHandler).sendRealTimeUpdate(eq("patient1"), any(Map.class));
    }

    // ── sendEmergencyAlert ──

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendEmergencyAlert_multipleContacts_sendsToAll")
    void sendEmergencyAlert_multipleContacts_sendsToAll() throws Exception {
        final String[] contactIds = {"contact1", "contact2"};

        webSocketNotificationService.sendEmergencyAlert(
                "patient1", "John Doe", "Fall detected!", contactIds);

        verify(careConnectWebSocketHandler, times(2)).sendRealTimeUpdate(anyString(), any(Map.class));
    }

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendEmergencyAlert_emptyContacts_sendsToNone")
    void sendEmergencyAlert_emptyContacts_sendsToNone() throws Exception {
        final String[] contactIds = {};

        webSocketNotificationService.sendEmergencyAlert(
                "patient1", "John Doe", "Fall detected!", contactIds);

        verify(careConnectWebSocketHandler, never()).sendRealTimeUpdate(anyString(), any(Map.class));
    }

    // ── sendAppointmentReminder ──

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendAppointmentReminder_validParams_sendsRealTimeUpdate")
    void sendAppointmentReminder_validParams_sendsRealTimeUpdate() throws Exception {
        webSocketNotificationService.sendAppointmentReminder(
                "patient1", "Checkup", "2026-03-01 10:00", "Dr. Smith");

        verify(careConnectWebSocketHandler).sendRealTimeUpdate(eq("patient1"), any(Map.class));
    }

    // ── broadcastSystemAnnouncement ──

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("broadcastSystemAnnouncement_validParams_broadcastsToAll")
    void broadcastSystemAnnouncement_validParams_broadcastsToAll() throws Exception {
        webSocketNotificationService.broadcastSystemAnnouncement(
                "Maintenance", "System will be down at midnight", "warning");

        verify(careConnectWebSocketHandler).broadcastToAllUsers(any(Map.class));
    }

    // ── isUserOnline ──

    @Test
    @DisplayName("isUserOnline_userOnline_returnsTrue")
    void isUserOnline_userOnline_returnsTrue() throws Exception {
        when(careConnectWebSocketHandler.isUserOnline("user1")).thenReturn(true);

        assertTrue(webSocketNotificationService.isUserOnline("user1"));
    }

    @Test
    @DisplayName("isUserOnline_userOffline_returnsFalse")
    void isUserOnline_userOffline_returnsFalse() throws Exception {
        when(careConnectWebSocketHandler.isUserOnline("user1")).thenReturn(false);

        assertFalse(webSocketNotificationService.isUserOnline("user1"));
    }

    // ── getOnlineUsersCount ──

    @Test
    @DisplayName("getOnlineUsersCount_someUsersOnline_returnsCount")
    void getOnlineUsersCount_someUsersOnline_returnsCount() throws Exception {
        when(careConnectWebSocketHandler.getOnlineUsersCount()).thenReturn(5);

        assertEquals(5, webSocketNotificationService.getOnlineUsersCount());
    }

    // ── getOnlineUsers ──

    @Test
    @DisplayName("getOnlineUsers_someUsersOnline_returnsMap")
    void getOnlineUsers_someUsersOnline_returnsMap() throws Exception {
        final Map<String, String> users = Map.of("1", "john@example.com", "2", "jane@example.com");
        when(callNotificationHandler.getOnlineUsers()).thenReturn(users);

        final Map<String, String> result = webSocketNotificationService.getOnlineUsers();

        assertEquals(2, result.size());
        assertEquals("john@example.com", result.get("1"));
    }

    // ── sendSOSCallToAllCaregivers ──

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendSOSCallToAllCaregivers_caregiversExist_sendsToAll")
    void sendSOSCallToAllCaregivers_caregiversExist_sendsToAll() throws Exception {
        final CaregiverPatientLinkResponse link1 = new CaregiverPatientLinkResponse(
                1L, 100L, "Nurse Alice", "alice@example.com",
                1L, "John Doe", "john@example.com",
                "ACTIVE", "PROFESSIONAL", false, false, LocalDateTime.now(), null, "", "admin", true, false);

        final CaregiverPatientLinkResponse link2 = new CaregiverPatientLinkResponse(
                2L, 200L, "Nurse Bob", "bob@example.com",
                1L, "John Doe", "john@example.com",
                "ACTIVE", "PROFESSIONAL", false, false, LocalDateTime.now(), null, "", "admin", true, false);

        when(caregiverPatientLinkService.getCaregiversByPatient(1L))
                .thenReturn(List.of(link1, link2));

        final int count = webSocketNotificationService.sendSOSCallToAllCaregivers(
                "1", "John Doe", "call123", "fall", "Home", "Fell in bathroom", true);

        assertEquals(2, count);
        verify(callNotificationHandler, times(2)).sendCallInvitation(anyString(), any(Map.class));
    }

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendSOSCallToAllCaregivers_noCaregiversFound_returnsZero")
    void sendSOSCallToAllCaregivers_noCaregiversFound_returnsZero() throws Exception {
        when(caregiverPatientLinkService.getCaregiversByPatient(1L))
                .thenReturn(List.of());

        final int count = webSocketNotificationService.sendSOSCallToAllCaregivers(
                "1", "John Doe", "call123", "fall", "Home", "Fell", true);

        assertEquals(0, count);
        verify(callNotificationHandler, never()).sendCallInvitation(anyString(), any(Map.class));
    }

    @Test
    @DisplayName("sendSOSCallToAllCaregivers_nullLocationAndInfo_usesDefaults")
    void sendSOSCallToAllCaregivers_nullLocationAndInfo_usesDefaults() throws Exception {
        final CaregiverPatientLinkResponse link = new CaregiverPatientLinkResponse(
                1L, 100L, "Nurse Alice", "alice@example.com",
                1L, "John Doe", "john@example.com",
                "ACTIVE", "PROFESSIONAL", false, false, LocalDateTime.now(), null, "", "admin", true, false);

        when(caregiverPatientLinkService.getCaregiversByPatient(1L))
                .thenReturn(List.of(link));

        final int count = webSocketNotificationService.sendSOSCallToAllCaregivers(
                "1", "John Doe", "call123", "medical", null, null, false);

        assertEquals(1, count);
    }

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("sendSOSCallToAllCaregivers_sendCallInvitationThrows_continuesAndCountsSuccesses")
    void sendSOSCallToAllCaregivers_sendCallInvitationThrows_continuesAndCountsSuccesses() throws Exception {
        final CaregiverPatientLinkResponse link1 = new CaregiverPatientLinkResponse(
                1L, 100L, "Nurse Alice", "alice@example.com",
                1L, "John Doe", "john@example.com",
                "ACTIVE", "PROFESSIONAL", false, false, LocalDateTime.now(), null, "", "admin", true, false);

        final CaregiverPatientLinkResponse link2 = new CaregiverPatientLinkResponse(
                2L, 200L, "Nurse Bob", "bob@example.com",
                1L, "John Doe", "john@example.com",
                "ACTIVE", "PROFESSIONAL", false, false, LocalDateTime.now(), null, "", "admin", true, false);

        when(caregiverPatientLinkService.getCaregiversByPatient(1L))
                .thenReturn(List.of(link1, link2));

        doThrow(new RuntimeException("Connection failed"))
                .when(callNotificationHandler).sendCallInvitation(eq("100"), any(Map.class));

        final int count = webSocketNotificationService.sendSOSCallToAllCaregivers(
                "1", "John Doe", "call123", "fall", "Home", "Info", true);

        assertEquals(1, count);
    }

    @Test
    @DisplayName("sendSOSCallToAllCaregivers_serviceThrowsException_throwsRuntimeException")
    void sendSOSCallToAllCaregivers_serviceThrowsException_throwsRuntimeException() throws Exception {
        when(caregiverPatientLinkService.getCaregiversByPatient(1L))
                .thenThrow(new RuntimeException("DB error"));

        final RuntimeException ex = assertThrows(RuntimeException.class,
                () -> webSocketNotificationService.sendSOSCallToAllCaregivers(
                        "1", "John Doe", "call123", "fall", "Home", "Info", true));

        assertTrue(ex.getMessage().contains("Failed to send SOS call"));
    }
}
