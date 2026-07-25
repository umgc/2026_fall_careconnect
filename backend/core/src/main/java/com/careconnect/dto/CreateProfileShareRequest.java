package com.careconnect.dto;

/**
 * Optional body for POST /v1/api/patients/me/profile-share.
 */
public record CreateProfileShareRequest(Integer ttlHours) {}
