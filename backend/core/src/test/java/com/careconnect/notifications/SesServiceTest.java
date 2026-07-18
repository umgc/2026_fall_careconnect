package com.careconnect.notifications;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import software.amazon.awssdk.services.ses.SesClient;
import software.amazon.awssdk.services.ses.model.SendEmailRequest;
import software.amazon.awssdk.services.ses.model.SendEmailResponse;
import software.amazon.awssdk.services.ses.model.SesException;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link SesService}.
 *
 * <p>Uses Mockito to mock the AWS {@link SesClient} so that no real AWS calls
 * are made. Each public method is tested for both its success path (correct
 * request construction and returned message ID) and its exception path
 * (AWS SDK exceptions propagate to callers).
 */
class SesServiceTest {

    private static final String FROM_ADDRESS = "no-reply@careconnect.com";
    private static final String MESSAGE_ID = "ses-msg-id-12345";

    private SesClient sesClient;
    private SesService sesService;

    @BeforeEach
    void setUp() {
        sesClient = mock(SesClient.class);
        sesService = new SesService(sesClient, FROM_ADDRESS);
    }

    // ==========================================
    // Helper
    // ==========================================

    private void stubSendEmail() {
        SendEmailResponse response = SendEmailResponse.builder()
                .messageId(MESSAGE_ID)
                .build();
        when(sesClient.sendEmail(any(SendEmailRequest.class))).thenReturn(response);
    }

    private void stubSendEmailThrows() {
        when(sesClient.sendEmail(any(SendEmailRequest.class)))
                .thenThrow(SesException.builder().message("SES error").build());
    }

    // ==========================================
    // sendEmail
    // ==========================================

    @Test
    void sendEmail_success_returnsMessageId() {
        stubSendEmail();

        String result = sesService.sendEmail("user@example.com", "Subject", "<p>html</p>", "text");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendEmail_success_buildsCorrectRequest() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendEmail("user@example.com", "Subject", "<p>html</p>", "text body");

        verify(sesClient).sendEmail(captor.capture());
        SendEmailRequest req = captor.getValue();
        assertEquals(FROM_ADDRESS, req.source());
        assertEquals(List.of("user@example.com"), req.destination().toAddresses());
        assertEquals("Subject", req.message().subject().data());
        assertEquals("<p>html</p>", req.message().body().html().data());
        assertEquals("text body", req.message().body().text().data());
    }

    @Test
    void sendEmail_nullHtmlBody_defaultsToEmptyString() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendEmail("user@example.com", "Subject", null, "text");

        verify(sesClient).sendEmail(captor.capture());
        assertEquals("", captor.getValue().message().body().html().data());
    }

    @Test
    void sendEmail_nullTextBody_defaultsToEmptyString() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendEmail("user@example.com", "Subject", "<p>html</p>", null);

        verify(sesClient).sendEmail(captor.capture());
        assertEquals("", captor.getValue().message().body().text().data());
    }

    @Test
    void sendEmail_sesException_propagates() {
        stubSendEmailThrows();

        assertThrows(SesException.class,
                () -> sesService.sendEmail("user@example.com", "Subj", "<p>h</p>", "t"));
    }

    // ==========================================
    // sendEmailToMultiple
    // ==========================================

    @Test
    void sendEmailToMultiple_success_returnsMessageId() {
        stubSendEmail();
        List<String> recipients = List.of("a@test.com", "b@test.com", "c@test.com");

        String result = sesService.sendEmailToMultiple(recipients, "Subj", "<p>h</p>", "t");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendEmailToMultiple_success_buildsCorrectRequest() {
        stubSendEmail();
        List<String> recipients = List.of("a@test.com", "b@test.com");
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendEmailToMultiple(recipients, "Subject", "<p>html</p>", "text");

        verify(sesClient).sendEmail(captor.capture());
        SendEmailRequest req = captor.getValue();
        assertEquals(recipients, req.destination().toAddresses());
        assertEquals(FROM_ADDRESS, req.source());
    }

    @Test
    void sendEmailToMultiple_nullBodies_defaultToEmpty() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendEmailToMultiple(List.of("a@test.com"), "Subj", null, null);

        verify(sesClient).sendEmail(captor.capture());
        SendEmailRequest req = captor.getValue();
        assertEquals("", req.message().body().html().data());
        assertEquals("", req.message().body().text().data());
    }

    @Test
    void sendEmailToMultiple_sesException_propagates() {
        stubSendEmailThrows();

        assertThrows(SesException.class,
                () -> sesService.sendEmailToMultiple(List.of("a@test.com"), "Subj", "<p>h</p>", "t"));
    }

    // ==========================================
    // sendTemplatedEmail
    // ==========================================

    @Test
    void sendTemplatedEmail_throwsUnsupportedOperationException() {
        Map<String, String> data = Map.of("key", "value");

        UnsupportedOperationException ex = assertThrows(UnsupportedOperationException.class,
                () -> sesService.sendTemplatedEmail("user@example.com", "template", data));

        assertTrue(ex.getMessage().contains("not yet implemented"));
    }

    @Test
    void sendTemplatedEmail_doesNotCallSesClient() {
        Map<String, String> data = Map.of("key", "value");

        try {
            sesService.sendTemplatedEmail("user@example.com", "template", data);
        } catch (UnsupportedOperationException ignored) {
            // Expected
        }

        verify(sesClient, never()).sendEmail(any(SendEmailRequest.class));
    }

    // ==========================================
    // sendPaymentConfirmation
    // ==========================================

    @Test
    void sendPaymentConfirmation_success_returnsMessageId() {
        stubSendEmail();

        String result = sesService.sendPaymentConfirmation(
                "user@example.com", "Alice", "99.99", "TXN-001");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendPaymentConfirmation_success_buildsCorrectSubjectAndContent() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendPaymentConfirmation("user@example.com", "Alice", "99.99", "TXN-001");

        verify(sesClient).sendEmail(captor.capture());
        SendEmailRequest req = captor.getValue();
        assertEquals("Payment Confirmation - CareConnect", req.message().subject().data());
        assertTrue(req.message().body().html().data().contains("Alice"));
        assertTrue(req.message().body().html().data().contains("$99.99"));
        assertTrue(req.message().body().html().data().contains("TXN-001"));
        assertTrue(req.message().body().text().data().contains("Alice"));
        assertTrue(req.message().body().text().data().contains("$99.99"));
        assertTrue(req.message().body().text().data().contains("TXN-001"));
    }

    @Test
    void sendPaymentConfirmation_sesException_propagates() {
        stubSendEmailThrows();

        assertThrows(SesException.class,
                () -> sesService.sendPaymentConfirmation("user@example.com", "Alice", "99.99", "TXN-001"));
    }

    // ==========================================
    // sendMedicationReminder
    // ==========================================

    @Test
    void sendMedicationReminder_success_returnsMessageId() {
        stubSendEmail();

        String result = sesService.sendMedicationReminder(
                "user@example.com", "Bob", "Aspirin", "100mg", "8:00 AM");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendMedicationReminder_success_buildsCorrectSubjectAndContent() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendMedicationReminder("user@example.com", "Bob", "Aspirin", "100mg", "8:00 AM");

        verify(sesClient).sendEmail(captor.capture());
        SendEmailRequest req = captor.getValue();
        assertEquals("Medication Reminder - Aspirin", req.message().subject().data());
        assertTrue(req.message().body().html().data().contains("Bob"));
        assertTrue(req.message().body().html().data().contains("Aspirin"));
        assertTrue(req.message().body().html().data().contains("100mg"));
        assertTrue(req.message().body().html().data().contains("8:00 AM"));
        assertTrue(req.message().body().text().data().contains("Bob"));
    }

    @Test
    void sendMedicationReminder_sesException_propagates() {
        stubSendEmailThrows();

        assertThrows(SesException.class,
                () -> sesService.sendMedicationReminder("user@example.com", "Bob", "Aspirin", "100mg", "8:00 AM"));
    }

    // ==========================================
    // sendAppointmentReminder
    // ==========================================

    @Test
    void sendAppointmentReminder_success_returnsMessageId() {
        stubSendEmail();

        String result = sesService.sendAppointmentReminder(
                "user@example.com", "Carol", "Checkup", "2026-04-01 10:00", "Room 101");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendAppointmentReminder_success_buildsCorrectSubjectAndContent() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendAppointmentReminder(
                "user@example.com", "Carol", "Checkup", "2026-04-01 10:00", "Room 101");

        verify(sesClient).sendEmail(captor.capture());
        SendEmailRequest req = captor.getValue();
        assertEquals("Appointment Reminder", req.message().subject().data());
        assertTrue(req.message().body().html().data().contains("2026-04-01 10:00"));
    }

    @Test
    void sendAppointmentReminder_sesException_propagates() {
        stubSendEmailThrows();

        assertThrows(SesException.class,
                () -> sesService.sendAppointmentReminder(
                        "user@example.com", "Carol", "Checkup", "2026-04-01 10:00", "Room 101"));
    }

    // ==========================================
    // sendCaregiverMessage
    // ==========================================

    @Test
    void sendCaregiverMessage_normalPriority_returnsMessageId() {
        stubSendEmail();

        String result = sesService.sendCaregiverMessage(
                "user@example.com", "Dr. Smith", "Jane", "Please check vitals.", "normal");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendCaregiverMessage_normalPriority_subjectWithoutUrgentTag() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendCaregiverMessage(
                "user@example.com", "Dr. Smith", "Jane", "Please check vitals.", "normal");

        verify(sesClient).sendEmail(captor.capture());
        String subject = captor.getValue().message().subject().data();
        assertEquals("Message from Dr. Smith", subject);
    }

    @Test
    void sendCaregiverMessage_urgentPriority_subjectContainsUrgentTag() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendCaregiverMessage(
                "user@example.com", "Dr. Smith", "Jane", "Emergency!", "urgent");

        verify(sesClient).sendEmail(captor.capture());
        String subject = captor.getValue().message().subject().data();
        assertEquals("Message from Dr. Smith [URGENT]", subject);
    }

    @Test
    void sendCaregiverMessage_htmlContainsRecipientAndSenderAndMessage() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendCaregiverMessage(
                "user@example.com", "Dr. Smith", "Jane", "Check vitals.", "normal");

        verify(sesClient).sendEmail(captor.capture());
        String html = captor.getValue().message().body().html().data();
        assertTrue(html.contains("Dr. Smith"));
        assertTrue(html.contains("Jane"));
        assertTrue(html.contains("Check vitals."));
    }

    @Test
    void sendCaregiverMessage_urgentPriority_usesRedHeaderColor() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendCaregiverMessage(
                "user@example.com", "Dr. Smith", "Jane", "Urgent note", "urgent");

        verify(sesClient).sendEmail(captor.capture());
        String html = captor.getValue().message().body().html().data();
        assertTrue(html.contains("#F44336"));
    }

    @Test
    void sendCaregiverMessage_normalPriority_usesGreenHeaderColor() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendCaregiverMessage(
                "user@example.com", "Dr. Smith", "Jane", "Normal note", "normal");

        verify(sesClient).sendEmail(captor.capture());
        String html = captor.getValue().message().body().html().data();
        assertTrue(html.contains("#4CAF50"));
    }

    @Test
    void sendCaregiverMessage_messageWithNewlines_convertedToBrInHtml() {
        stubSendEmail();
        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);

        sesService.sendCaregiverMessage(
                "user@example.com", "Dr. Smith", "Jane", "Line1\nLine2", "normal");

        verify(sesClient).sendEmail(captor.capture());
        String html = captor.getValue().message().body().html().data();
        assertTrue(html.contains("Line1<br>Line2"));
    }

    @Test
    void sendCaregiverMessage_sesException_propagates() {
        stubSendEmailThrows();

        assertThrows(SesException.class,
                () -> sesService.sendCaregiverMessage(
                        "user@example.com", "Dr. Smith", "Jane", "msg", "normal"));
    }
}
