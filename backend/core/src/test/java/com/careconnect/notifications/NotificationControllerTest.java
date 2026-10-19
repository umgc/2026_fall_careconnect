package com.careconnect.notifications;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.notifications.dto.DemoNotificationRequest;

import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class NotificationControllerTest {

    @Mock
    private SesService sesService;
    @Mock
    private SnsService snsService;

    private NotificationController controller;

    @BeforeEach
    void setUp() {
        controller = new NotificationController(sesService, snsService);
    }

    // ── payment ──────────────────────────────────────────────────────────────

    @Test
    void sendPaymentNotification_emailAndPhone_success() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("test@example.com");
        req.setToPhone("+15551234567");
        req.setRecipientName("Alice");
        req.setAmount("49.99");

        when(sesService.sendPaymentConfirmation(eq("test@example.com"), eq("Alice"),
                eq("49.99"), anyString())).thenReturn("email-id-1");
        when(snsService.sendPaymentConfirmationSms("+15551234567", "Alice", "49.99"))
                .thenReturn("sms-id-1");

        ResponseEntity<?> response = controller.sendPaymentNotification(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("Payment notifications sent successfully", response.getBody());
        verify(sesService).sendPaymentConfirmation(eq("test@example.com"), eq("Alice"),
                eq("49.99"), anyString());
        verify(snsService).sendPaymentConfirmationSms("+15551234567", "Alice", "49.99");
    }

    @Test
    void sendPaymentNotification_emailOnly_noSmsSent() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("test@example.com");
        req.setRecipientName("Bob");
        req.setAmount("10.00");

        when(sesService.sendPaymentConfirmation(eq("test@example.com"), eq("Bob"),
                eq("10.00"), anyString())).thenReturn("email-id-2");

        ResponseEntity<?> response = controller.sendPaymentNotification(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        verify(snsService, never()).sendPaymentConfirmationSms(anyString(), anyString(), anyString());
    }

    @Test
    void sendPaymentNotification_nullFields_usesDefaults() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("test@example.com");

        when(sesService.sendPaymentConfirmation(eq("test@example.com"), eq("Valued Customer"),
                eq("0.00"), anyString())).thenReturn("email-id-3");

        ResponseEntity<?> response = controller.sendPaymentNotification(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        verify(sesService).sendPaymentConfirmation(eq("test@example.com"), eq("Valued Customer"),
                eq("0.00"), anyString());
    }

    @Test
    void sendPaymentNotification_exception_returns500() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("test@example.com");

        when(sesService.sendPaymentConfirmation(anyString(), anyString(), anyString(), anyString()))
                .thenThrow(new RuntimeException("SES down"));

        ResponseEntity<?> response = controller.sendPaymentNotification(req);

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());
        assertTrue(response.getBody().toString().contains("SES down"));
    }

    // ── message ──────────────────────────────────────────────────────────────

    @Test
    void sendMessageNotification_emailAndPhone_success() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("user@example.com");
        req.setToPhone("+15559876543");
        req.setRecipientName("Charlie");
        req.setMessage("Hello there");

        when(sesService.sendCaregiverMessage("user@example.com", "CareConnect System",
                "Charlie", "Hello there", "normal")).thenReturn("email-id");
        when(snsService.sendCaregiverMessageSms("+15559876543", "CareConnect",
                "Hello there", false)).thenReturn("sms-id");

        ResponseEntity<?> response = controller.sendMessageNotification(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("Message notifications sent successfully", response.getBody());
    }

    @Test
    void sendMessageNotification_nullFields_usesDefaults() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("user@example.com");

        when(sesService.sendCaregiverMessage("user@example.com", "CareConnect System",
                "Recipient", "You have a new message", "normal")).thenReturn("email-id");

        ResponseEntity<?> response = controller.sendMessageNotification(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
    }

    @Test
    void sendMessageNotification_exception_returns500() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("user@example.com");

        when(sesService.sendCaregiverMessage(anyString(), anyString(), anyString(),
                anyString(), anyString())).thenThrow(new RuntimeException("connection refused"));

        ResponseEntity<?> response = controller.sendMessageNotification(req);

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());
        assertTrue(response.getBody().toString().contains("connection refused"));
    }

    // ── medication reminder ──────────────────────────────────────────────────

    @Test
    void sendMedicationReminder_emailAndPhone_success() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("patient@example.com");
        req.setToPhone("+15550001111");
        req.setRecipientName("Dana");
        req.setSubject("Aspirin");
        req.setAmount("100mg");
        req.setMessage("8:00 AM");

        when(sesService.sendMedicationReminder("patient@example.com", "Dana",
                "Aspirin", "100mg", "8:00 AM")).thenReturn("email-id");
        when(snsService.sendMedicationReminderSms("+15550001111", "Dana",
                "Aspirin", "100mg")).thenReturn("sms-id");

        ResponseEntity<?> response = controller.sendMedicationReminder(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("Medication reminder notifications sent successfully", response.getBody());
    }

    @Test
    void sendMedicationReminder_nullFields_usesDefaults() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("patient@example.com");

        when(sesService.sendMedicationReminder("patient@example.com", "Patient",
                "Medication", "As prescribed", "Now")).thenReturn("email-id");

        ResponseEntity<?> response = controller.sendMedicationReminder(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
    }

    @Test
    void sendMedicationReminder_exception_returns500() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("patient@example.com");

        when(sesService.sendMedicationReminder(anyString(), anyString(), anyString(),
                anyString(), anyString())).thenThrow(new RuntimeException("timeout"));

        ResponseEntity<?> response = controller.sendMedicationReminder(req);

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());
        assertTrue(response.getBody().toString().contains("timeout"));
    }

    // ── appointment reminder ─────────────────────────────────────────────────

    @Test
    void sendAppointmentReminder_emailAndPhone_success() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("patient@example.com");
        req.setToPhone("+15552223333");
        req.setRecipientName("Eve");
        req.setSubject("Checkup");
        req.setMessage("2026-04-01 10:00");
        req.setAmount("Main Clinic");

        when(sesService.sendAppointmentReminder("patient@example.com", "Eve",
                "Checkup", "2026-04-01 10:00", "Main Clinic")).thenReturn("email-id");
        when(snsService.sendAppointmentReminderSms("+15552223333", "Eve",
                "Checkup", "2026-04-01 10:00")).thenReturn("sms-id");

        ResponseEntity<?> response = controller.sendAppointmentReminder(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("Appointment reminder notifications sent successfully", response.getBody());
    }

    @Test
    void sendAppointmentReminder_nullFields_usesDefaults() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("patient@example.com");

        when(sesService.sendAppointmentReminder("patient@example.com", "Patient",
                "Appointment", "Today", "Clinic")).thenReturn("email-id");

        ResponseEntity<?> response = controller.sendAppointmentReminder(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
    }

    @Test
    void sendAppointmentReminder_exception_returns500() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToPhone("+15552223333");

        when(snsService.sendAppointmentReminderSms(anyString(), anyString(), anyString(),
                anyString())).thenThrow(new RuntimeException("SNS error"));

        ResponseEntity<?> response = controller.sendAppointmentReminder(req);

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());
        assertTrue(response.getBody().toString().contains("SNS error"));
    }

    // ── emergency alert ──────────────────────────────────────────────────────

    @Test
    void sendEmergencyAlert_emailAndPhone_success() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("nurse@example.com");
        req.setToPhone("+15554445555");
        req.setRecipientName("Frank");
        req.setSubject("Fall Detected");
        req.setMessage("Room 204");

        when(sesService.sendEmail(eq("nurse@example.com"), eq("EMERGENCY ALERT - Fall Detected"),
                isNull(), anyString())).thenReturn("email-id");
        when(snsService.sendEmergencyAlertSms("+15554445555", "Frank",
                "Fall Detected", "Room 204")).thenReturn("sms-id");

        ResponseEntity<?> response = controller.sendEmergencyAlert(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("Emergency alert notifications sent successfully", response.getBody());
    }

    @Test
    void sendEmergencyAlert_nullFields_usesDefaults() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToPhone("+15554445555");

        when(snsService.sendEmergencyAlertSms("+15554445555", "Patient",
                "Emergency", "Unknown location")).thenReturn("sms-id");

        ResponseEntity<?> response = controller.sendEmergencyAlert(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        verify(sesService, never()).sendEmail(anyString(), anyString(), any(), anyString());
    }

    @Test
    void sendEmergencyAlert_exception_returns500() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("nurse@example.com");

        when(sesService.sendEmail(anyString(), anyString(), any(), anyString()))
                .thenThrow(new RuntimeException("SES failure"));

        ResponseEntity<?> response = controller.sendEmergencyAlert(req);

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());
        assertTrue(response.getBody().toString().contains("SES failure"));
    }

    // ── caregiver message ────────────────────────────────────────────────────

    @Test
    void sendCaregiverMessage_emailAndPhone_success() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("patient@example.com");
        req.setToPhone("+15556667777");
        req.setRecipientName("Grace");
        req.setSubject("Dr. Smith");
        req.setMessage("Please take your medication");
        req.setAmount("normal");

        when(sesService.sendCaregiverMessage("patient@example.com", "Dr. Smith",
                "Grace", "Please take your medication", "normal")).thenReturn("email-id");
        when(snsService.sendCaregiverMessageSms("+15556667777", "Dr. Smith",
                "Please take your medication", false)).thenReturn("sms-id");

        ResponseEntity<?> response = controller.sendCaregiverMessage(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("Caregiver message notifications sent successfully", response.getBody());
    }

    @Test
    void sendCaregiverMessage_urgent_setsUrgentFlag() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("patient@example.com");
        req.setToPhone("+15556667777");
        req.setRecipientName("Grace");
        req.setSubject("Dr. Smith");
        req.setMessage("Urgent update");
        req.setAmount("urgent");

        when(sesService.sendCaregiverMessage("patient@example.com", "Dr. Smith",
                "Grace", "Urgent update", "urgent")).thenReturn("email-id");
        when(snsService.sendCaregiverMessageSms("+15556667777", "Dr. Smith",
                "Urgent update", true)).thenReturn("sms-id");

        ResponseEntity<?> response = controller.sendCaregiverMessage(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        verify(sesService).sendCaregiverMessage("patient@example.com", "Dr. Smith",
                "Grace", "Urgent update", "urgent");
        verify(snsService).sendCaregiverMessageSms("+15556667777", "Dr. Smith",
                "Urgent update", true);
    }

    @Test
    void sendCaregiverMessage_nullFields_usesDefaults() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("patient@example.com");

        when(sesService.sendCaregiverMessage("patient@example.com", "Caregiver",
                "Recipient", "New message from caregiver", "normal")).thenReturn("email-id");

        ResponseEntity<?> response = controller.sendCaregiverMessage(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
    }

    @Test
    void sendCaregiverMessage_exception_returns500() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("patient@example.com");

        when(sesService.sendCaregiverMessage(anyString(), anyString(), anyString(),
                anyString(), anyString())).thenThrow(new RuntimeException("auth error"));

        ResponseEntity<?> response = controller.sendCaregiverMessage(req);

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());
        assertTrue(response.getBody().toString().contains("auth error"));
    }

    // ── bulk ─────────────────────────────────────────────────────────────────

    @Test
    void sendBulkNotifications_returnsNotImplemented() {
        List<DemoNotificationRequest> requests = List.of(new DemoNotificationRequest());

        ResponseEntity<?> response = controller.sendBulkNotifications(requests);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("Bulk notifications not yet implemented", response.getBody());
    }

    // ── topic ────────────────────────────────────────────────────────────────

    @Test
    void sendTopicNotification_returnsNotImplemented() {
        DemoNotificationRequest req = new DemoNotificationRequest();

        ResponseEntity<?> response = controller.sendTopicNotification("caregivers", req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("Topic notifications not yet implemented", response.getBody());
    }

    // ── edge cases ───────────────────────────────────────────────────────────

    @Test
    void sendPaymentNotification_emptyEmail_noEmailSent() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("");
        req.setToPhone("+15551234567");
        req.setAmount("25.00");

        when(snsService.sendPaymentConfirmationSms("+15551234567", "Customer", "25.00"))
                .thenReturn("sms-id");

        ResponseEntity<?> response = controller.sendPaymentNotification(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        verify(sesService, never()).sendPaymentConfirmation(anyString(), anyString(),
                anyString(), anyString());
    }

    @Test
    void sendPaymentNotification_emptyPhone_noSmsSent() {
        DemoNotificationRequest req = new DemoNotificationRequest();
        req.setToEmail("test@example.com");
        req.setToPhone("");

        when(sesService.sendPaymentConfirmation(eq("test@example.com"), eq("Valued Customer"),
                eq("0.00"), anyString())).thenReturn("email-id");

        ResponseEntity<?> response = controller.sendPaymentNotification(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        verify(snsService, never()).sendPaymentConfirmationSms(anyString(), anyString(), anyString());
    }

    @Test
    void sendPaymentNotification_noEmailNoPhone_stillReturnsOk() {
        DemoNotificationRequest req = new DemoNotificationRequest();

        ResponseEntity<?> response = controller.sendPaymentNotification(req);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        verify(sesService, never()).sendPaymentConfirmation(anyString(), anyString(),
                anyString(), anyString());
        verify(snsService, never()).sendPaymentConfirmationSms(anyString(), anyString(), anyString());
    }
}
