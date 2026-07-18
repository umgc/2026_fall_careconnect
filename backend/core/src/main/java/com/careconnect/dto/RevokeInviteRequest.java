package com.careconnect.dto;

/** Optional body for invite revocation; carries a human-readable reason. */
public record RevokeInviteRequest(
        String reason
) {}
