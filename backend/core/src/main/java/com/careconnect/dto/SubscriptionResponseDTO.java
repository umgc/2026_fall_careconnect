package com.careconnect.dto;

import com.careconnect.model.Plan;
import com.careconnect.model.Subscription;

import java.time.Instant;

public class SubscriptionResponseDTO {
    private Long id;
    private String paymentSubscriptionId;
    private String paymentCustomerId;
    private String priceId;
    private Long userId;
    private Long planId;
    private String planName;
    private String planCode;
    private Integer priceCents;
    private String status;
    private Instant startedAt;
    private Instant currentPeriodEnd;

    public SubscriptionResponseDTO() {
    }

    public SubscriptionResponseDTO(Subscription subscription) {
        this.id = subscription.getId();
        this.paymentSubscriptionId = subscription.getPaymentSubscriptionId();
        this.paymentCustomerId = subscription.getPaymentCustomerId();
        this.priceId = subscription.getPriceId();

        // Safely extract user ID
        if (subscription.getUser() != null) {
            this.userId = subscription.getUser().getId();
        }

        // Safely extract plan details
        if (subscription.getPlan() != null) {
            Plan plan = subscription.getPlan();
            this.planId = plan.getId();
            this.planName = plan.getName();
            this.planCode = plan.getCode();
            this.priceCents = plan.getPriceCents();
        }

        this.status = subscription.getStatus();
        this.startedAt = subscription.getStartedAt();
        this.currentPeriodEnd = subscription.getCurrentPeriodEnd();
    }

    // Getters and setters
    public Long getId() {
        return id;
    }

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

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public Long getPlanId() {
        return planId;
    }

    public void setPlanId(Long planId) {
        this.planId = planId;
    }

    public String getPlanName() {
        return planName;
    }

    public void setPlanName(String planName) {
        this.planName = planName;
    }

    public String getPlanCode() {
        return planCode;
    }

    public void setPlanCode(String planCode) {
        this.planCode = planCode;
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

    public Integer getPriceCents() {
        return priceCents;
    }

    public void setPriceCents(Integer priceCents) {
        this.priceCents = priceCents;
    }
}
