package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;


@Entity
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Payment {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "subscription_id")
    private Subscription subscription;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    private User user;

    private Integer amountCents;
    private String status; // SUCCEEDED, FAILED, PENDING
    private Instant attemptedAt;

    // Platform-agnostic fields for native billing
    @Enumerated(EnumType.STRING)
    private com.careconnect.model.BillingPlatform platform; // APPLE, GOOGLE, STRIPE, OTHER

    private String platformPurchaseToken; // Apple receipt or Google purchase token
    private String platformPayerId; // e.g., Apple or Google account identifier
    private String externalTransactionId; // platform-specific transaction / order id

    private String stripeSessionId;
    private String stripePaymentIntentId;
    private String stripeInvoiceId;

    public void setAmountCents(Integer amountCents) {
        this.amountCents = amountCents;
    }

    public void setStripeSessionId(String stripeSessionId) {
        this.stripeSessionId = stripeSessionId;
    }

    public void setStripePaymentIntentId(String stripePaymentIntentId) {
        this.stripePaymentIntentId = stripePaymentIntentId;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }
}