package com.careconnect.dto;

public record ImapConnectRequest(
        String userId,
        String email,
        String appPassword,
        String imapHost,
        Integer imapPort
) {}
