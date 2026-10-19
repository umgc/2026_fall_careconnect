package com.careconnect.dto;

import lombok.Data;

import java.time.Instant;

@Data
public class BillingVerifyResponse {
    private boolean success;
    private String platform;
    private String externalSubscriptionId;
    private String externalTransactionId;
    private String status; // ACTIVE, CANCELLED, EXPIRED
    private Instant purchaseDate;
    private Instant expiryDate;
    private String message;
}
