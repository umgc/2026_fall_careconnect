package com.careconnect.model;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;


@Entity
@Table(name = "subscriptions")
@Getter
@Setter
@NoArgsConstructor
public class Subscription {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true)
    private String paymentSubscriptionId;

    private String paymentCustomerId;

    private String priceId;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "plan_id")
    private Plan plan;

    private String status; // ACTIVE, CANCELLED, etc.
    private Instant startedAt;
    private Instant currentPeriodEnd;
    @Enumerated(EnumType.STRING)
    private BillingPlatform platform;

    private String externalSubscriptionId;

    private Instant lastValidatedAt;
    // Platform-agnostic fields (stored above)

    // Explicit getter methods for compatibility
    public Long getId() {
        return id;
    }

    // Explicit setter methods for compatibility
    public void setId(Long id) {
        this.id = id;
    }

    public String getPaymentSubscriptionId() {
        return paymentSubscriptionId;
    }

    public void setPaymentSubscriptionId(String paymentSubscriptionId) {
        this.paymentSubscriptionId = paymentSubscriptionId;
    }

    public String getPaymentCustomerId() {
        return paymentCustomerId;
    }

    public void setPaymentCustomerId(String paymentCustomerId) {
        this.paymentCustomerId = paymentCustomerId;
    }

    public String getPriceId() {
        return priceId;
    }

    public void setPriceId(String priceId) {
        this.priceId = priceId;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Plan getPlan() {
        return plan;
    }

    public void setPlan(Plan plan) {
        this.plan = plan;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public Instant getStartedAt() {
        return startedAt;
    }

    public void setStartedAt(Instant startedAt) {
        this.startedAt = startedAt;
    }

    public Instant getCurrentPeriodEnd() {
        return currentPeriodEnd;
    }

    public void setCurrentPeriodEnd(Instant currentPeriodEnd) {
        this.currentPeriodEnd = currentPeriodEnd;
    }
}
