package com.careconnect.dto;

import jakarta.validation.constraints.NotBlank;

/** Request body for POST /v1/api/admin/users/{userId}/role. */
public record UpdateUserRoleRequest(@NotBlank String role) {}
