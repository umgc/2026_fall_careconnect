package com.careconnect.dto;

import lombok.Data;

@Data
public class SubscriptionCancelRequestDTO {
    private Long subscriptionId;

    public Long getSubscriptionId() {
        return this.subscriptionId;
    }
}