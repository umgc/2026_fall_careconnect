package com.careconnect.dto;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import com.careconnect.model.User;

// import io.swagger.v3.oas.annotations.media.Schema;

// @Schema(description = "API view of a Stripe subscription")
public record SubscriptionDto(
        String id,
        String customerId,
        String priceId,
        String status,
        String planId,
        int quantity,
        Long currentPeriodEnd) {
}
