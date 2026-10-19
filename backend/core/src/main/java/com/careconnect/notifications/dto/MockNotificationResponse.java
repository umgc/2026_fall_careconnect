package com.careconnect.notifications.dto;

public class MockNotificationResponse {
    private String type;
    private String recipient;
    private String emailSubject;
    private String emailBody;
    private String smsText;

    public MockNotificationResponse() {
    }

    public MockNotificationResponse(String type, String recipient, String emailSubject, String emailBody, String smsText) {
        this.type = type;
        this.recipient = recipient;
        this.emailSubject = emailSubject;
        this.emailBody = emailBody;
        this.smsText = smsText;
    }

    // Getters and setters
    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    public String getRecipient() {
        return recipient;
    }

    public void setRecipient(String recipient) {
        this.recipient = recipient;
    }

    public String getEmailSubject() {
        return emailSubject;
    }

    public void setEmailSubject(String emailSubject) {
        this.emailSubject = emailSubject;
    }

    public String getEmailBody() {
        return emailBody;
    }

    public void setEmailBody(String emailBody) {
        this.emailBody = emailBody;
    }

    public String getSmsText() {
        return smsText;
    }

    public void setSmsText(String smsText) {
        this.smsText = smsText;
    }
}