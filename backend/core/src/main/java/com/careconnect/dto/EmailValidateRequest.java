package com.careconnect.dto;

public record EmailValidateRequest(String email, boolean smtpProbe) {
    public EmailValidateRequest {
        if (email == null) {
            email = "";
        }
    }
}
