package com.careconnect.notifications.dto;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import org.junit.jupiter.api.Test;

class DemoNotificationRequestTest {

    @Test
    void defaultConstructor_allFieldsAreNull() {
        DemoNotificationRequest request = new DemoNotificationRequest();

        assertNull(request.getToEmail());
        assertNull(request.getToPhone());
        assertNull(request.getSubject());
        assertNull(request.getMessage());
        assertNull(request.getAmount());
        assertNull(request.getRecipientName());
    }

    @Test
    void setAndGetToEmail() {
        DemoNotificationRequest request = new DemoNotificationRequest();
        request.setToEmail("user@example.com");
        assertEquals("user@example.com", request.getToEmail());
    }

    @Test
    void setAndGetToPhone() {
        DemoNotificationRequest request = new DemoNotificationRequest();
        request.setToPhone("+15551234567");
        assertEquals("+15551234567", request.getToPhone());
    }

    @Test
    void setAndGetSubject() {
        DemoNotificationRequest request = new DemoNotificationRequest();
        request.setSubject("Test Subject");
        assertEquals("Test Subject", request.getSubject());
    }

    @Test
    void setAndGetMessage() {
        DemoNotificationRequest request = new DemoNotificationRequest();
        request.setMessage("Hello World");
        assertEquals("Hello World", request.getMessage());
    }

    @Test
    void setAndGetAmount() {
        DemoNotificationRequest request = new DemoNotificationRequest();
        request.setAmount("99.99");
        assertEquals("99.99", request.getAmount());
    }

    @Test
    void setAndGetRecipientName() {
        DemoNotificationRequest request = new DemoNotificationRequest();
        request.setRecipientName("John Doe");
        assertEquals("John Doe", request.getRecipientName());
    }

    @Test
    void setAllFields_gettersReturnCorrectValues() {
        DemoNotificationRequest request = new DemoNotificationRequest();
        request.setToEmail("admin@example.com");
        request.setToPhone("+15559876543");
        request.setSubject("Appointment");
        request.setMessage("Your appointment is tomorrow");
        request.setAmount("150.00");
        request.setRecipientName("Jane Smith");

        assertEquals("admin@example.com", request.getToEmail());
        assertEquals("+15559876543", request.getToPhone());
        assertEquals("Appointment", request.getSubject());
        assertEquals("Your appointment is tomorrow", request.getMessage());
        assertEquals("150.00", request.getAmount());
        assertEquals("Jane Smith", request.getRecipientName());
    }

    @Test
    void setField_overwritesPreviousValue() {
        DemoNotificationRequest request = new DemoNotificationRequest();
        request.setToEmail("first@example.com");
        request.setToEmail("second@example.com");
        assertEquals("second@example.com", request.getToEmail());
    }

    @Test
    void setField_canSetToNull() {
        DemoNotificationRequest request = new DemoNotificationRequest();
        request.setToEmail("user@example.com");
        request.setToEmail(null);
        assertNull(request.getToEmail());
    }

    @Test
    void setField_canSetToEmptyString() {
        DemoNotificationRequest request = new DemoNotificationRequest();
        request.setToEmail("");
        assertEquals("", request.getToEmail());
    }
}
