package com.careconnect.service;


import lombok.RequiredArgsConstructor;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.careconnect.repository.PaymentRepository;
import com.careconnect.model.Payment;
import com.careconnect.repository.SubscriptionRepository;
import com.careconnect.model.Subscription;

import java.time.Instant;

@Service
@RequiredArgsConstructor
public class PaymentService {
    @Autowired
    private PaymentRepository paymentRepository;
    @Autowired
    private SubscriptionRepository subscriptionRepository;

    public void savePayment(Payment payment) {
        if (payment.getSubscription() != null && payment.getSubscription().getId() != null) {
            // ensure subscription exists
            Subscription s = subscriptionRepository.findById(payment.getSubscription().getId()).orElse(null);
            if (s != null) payment.setSubscription(s);
        }
        if (payment.getAttemptedAt() == null) payment.setAttemptedAt(Instant.now());
        paymentRepository.save(payment);
    }

    public Payment getByStripeSessionId(String sessionId) {
        return paymentRepository.findByStripeSessionId(sessionId);
    }
}