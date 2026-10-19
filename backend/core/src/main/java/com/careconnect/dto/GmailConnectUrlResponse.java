package com.careconnect.dto;

/**
 * Authenticated Gmail OAuth entry point for external browsers (no JWT cookie required).
 */
public record GmailConnectUrlResponse(String url) {
}
