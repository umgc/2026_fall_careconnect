package com.careconnect.dto;

public record ChangePasswordRequest(String currentPassword, String newPassword) {
}
