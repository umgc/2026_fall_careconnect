package com.careconnect.notifications;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.lang.reflect.Field;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ReminderDispatcherTest {

    @Mock
    private SesService sesService;
    @Mock
    private SnsService snsService;

    private ReminderDispatcher dispatcher;

    @BeforeEach
    void setUp() {
        dispatcher = new ReminderDispatcher(sesService, snsService);
    }

    /**
     * Sets a private field on the dispatcher via reflection.
     */
    private void setField(String name, Object value) throws Exception {
        Field field = ReminderDispatcher.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(dispatcher, value);
    }

    @Test
    void sendDemoReminder_remindersDisabled_doesNothing() throws Exception {
        setField("remindersEnabled", false);
        setField("demoEmail", "test@example.com");
        setField("demoPhone", "+15551234567");

        dispatcher.sendDemoReminder();

        verify(sesService, never()).sendEmail(anyString(), anyString(), anyString(), anyString());
        verify(snsService, never()).publishSms(anyString(), anyString());
    }

    @Test
    void sendDemoReminder_noAddressesConfigured_doesNothing() throws Exception {
        setField("remindersEnabled", true);
        setField("demoEmail", "");
        setField("demoPhone", "");

        dispatcher.sendDemoReminder();

        verify(sesService, never()).sendEmail(anyString(), anyString(), anyString(), anyString());
        verify(snsService, never()).publishSms(anyString(), anyString());
    }

    @Test
    void sendDemoReminder_nullAddresses_doesNothing() throws Exception {
        setField("remindersEnabled", true);
        setField("demoEmail", null);
        setField("demoPhone", null);

        dispatcher.sendDemoReminder();

        verify(sesService, never()).sendEmail(anyString(), anyString(), anyString(), anyString());
        verify(snsService, never()).publishSms(anyString(), anyString());
    }

    @Test
    void sendDemoReminder_emailConfigured_sendsEmail() throws Exception {
        setField("remindersEnabled", true);
        setField("demoEmail", "patient@example.com");
        setField("demoPhone", "");

        when(sesService.sendEmail(
                eq("patient@example.com"),
                eq("Reminder: Upcoming Appointment"),
                anyString(),
                eq("This is a demo reminder for your upcoming appointment.")))
                .thenReturn("msg-123");

        dispatcher.sendDemoReminder();

        verify(sesService).sendEmail(
                eq("patient@example.com"),
                eq("Reminder: Upcoming Appointment"),
                anyString(),
                eq("This is a demo reminder for your upcoming appointment."));
        verify(snsService, never()).publishSms(anyString(), anyString());
    }

    @Test
    void sendDemoReminder_phoneConfigured_sendsSms() throws Exception {
        setField("remindersEnabled", true);
        setField("demoEmail", "");
        setField("demoPhone", "+15551234567");

        when(snsService.publishSms("+15551234567",
                "This is a demo reminder for your upcoming appointment.")).thenReturn("sms-123");

        dispatcher.sendDemoReminder();

        verify(sesService, never()).sendEmail(anyString(), anyString(), anyString(), anyString());
        verify(snsService).publishSms("+15551234567",
                "This is a demo reminder for your upcoming appointment.");
    }

    @Test
    void sendDemoReminder_bothConfigured_sendsBoth() throws Exception {
        setField("remindersEnabled", true);
        setField("demoEmail", "patient@example.com");
        setField("demoPhone", "+15551234567");

        when(sesService.sendEmail(
                eq("patient@example.com"),
                eq("Reminder: Upcoming Appointment"),
                anyString(),
                eq("This is a demo reminder for your upcoming appointment.")))
                .thenReturn("email-123");
        when(snsService.publishSms("+15551234567",
                "This is a demo reminder for your upcoming appointment.")).thenReturn("sms-123");

        dispatcher.sendDemoReminder();

        verify(sesService).sendEmail(
                eq("patient@example.com"),
                eq("Reminder: Upcoming Appointment"),
                anyString(),
                eq("This is a demo reminder for your upcoming appointment."));
        verify(snsService).publishSms("+15551234567",
                "This is a demo reminder for your upcoming appointment.");
    }

    @Test
    void sendDemoReminder_emailThrowsException_stillSendsSms() throws Exception {
        setField("remindersEnabled", true);
        setField("demoEmail", "patient@example.com");
        setField("demoPhone", "+15551234567");

        when(sesService.sendEmail(anyString(), anyString(), anyString(), anyString()))
                .thenThrow(new RuntimeException("SES error"));
        when(snsService.publishSms("+15551234567",
                "This is a demo reminder for your upcoming appointment.")).thenReturn("sms-123");

        dispatcher.sendDemoReminder();

        verify(snsService).publishSms("+15551234567",
                "This is a demo reminder for your upcoming appointment.");
    }

    @Test
    void sendDemoReminder_smsThrowsException_doesNotPropagate() throws Exception {
        setField("remindersEnabled", true);
        setField("demoEmail", "");
        setField("demoPhone", "+15551234567");

        when(snsService.publishSms(anyString(), anyString()))
                .thenThrow(new RuntimeException("SNS error"));

        // Should not throw -- exception is caught internally.
        dispatcher.sendDemoReminder();
    }
}
