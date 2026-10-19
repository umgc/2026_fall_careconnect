package com.careconnect.dto;

public record SetupPasswordRequest(String username, String verificationToken, String newPassword) {
}
