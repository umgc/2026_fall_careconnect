package com.careconnect.dto;

import java.time.LocalDate;

/** Safe admin-facing user summary (no credentials or tokens). */
public record AdminUserSummaryDTO(
    Long id,
    String name,
    String email,
    String role,
    boolean emailVerified,
    LocalDate lastLoginDate) {}
