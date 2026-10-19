package com.careconnect.service;

import com.careconnect.dto.SubscriptionResponseDTO;
import com.careconnect.model.Payment;
import com.careconnect.model.Plan;
import com.careconnect.model.Subscription;
import com.careconnect.model.User;
import com.careconnect.repository.PaymentRepository;
import com.careconnect.repository.PlanRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.repository.SubscriptionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class SubscriptionService {
    private final SubscriptionRepository subscriptionRepository;
    private final PaymentRepository paymentRepository;
    private final UserRepository userRepository;
    private final PlanRepository planRepository;

    public Plan createPlan(String code, String name, Integer priceCents, String billingPeriod, Boolean isActive) {
        Plan plan = new Plan();
        plan.setCode(code);
        plan.setName(name);
        plan.setPriceCents(priceCents);
        plan.setBillingPeriod(billingPeriod);
        plan.setIsActive(isActive != null ? isActive : true);
        return planRepository.save(plan);
    }

    public Plan getPlan(Long planId) {
        return planRepository.findById(planId)
                .orElseThrow(() -> new IllegalArgumentException("Plan not found with ID: " + planId));
    }

    @Transactional
    public void cancelSubscription(Long subscriptionId) {
        Subscription sub = subscriptionRepository.findById(subscriptionId)
                .orElseThrow(() -> new IllegalArgumentException("Subscription not found"));

        sub.setStatus("CANCELLED");
        sub.setCurrentPeriodEnd(null);
        subscriptionRepository.save(sub);
    }

    @Transactional
    public List<Subscription> getUserSubscriptions(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found with ID: " + userId));
        return subscriptionRepository.findByUser(user);
    }

    @Transactional
    public List<Subscription> getUserActiveSubscriptions(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found with ID: " + userId));
        return subscriptionRepository.findByUserAndStatus(user, "ACTIVE");
    }

    @Transactional
    public Subscription createSubscriptionForUser(Long userId, Long planId, String platform) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found with ID: " + userId));
        Plan plan = planRepository.findById(planId)
                .orElseThrow(() -> new IllegalArgumentException("Plan not found with ID: " + planId));

        Subscription subscription = new Subscription();
        subscription.setUser(user);
        subscription.setPlan(plan);
        subscription.setStatus("ACTIVE");
        subscription.setStartedAt(Instant.now());
        subscription.setCurrentPeriodEnd(Instant.now().plus(30, ChronoUnit.DAYS));
        subscription.setPaymentSubscriptionId(platform.toLowerCase() + "_" + System.currentTimeMillis());

        return subscriptionRepository.save(subscription);
    }

    @Transactional
    public SubscriptionResponseDTO createDirectSubscription(String customerId, String priceId) {
        User user = userRepository.findByPaymentCustomerId(customerId)
                .orElseThrow(() -> new IllegalArgumentException("User not found for customerId: " + customerId));

        List<Subscription> active = subscriptionRepository.findByUserAndStatus(user, "ACTIVE");
        for (Subscription existing : active) {
            if (priceId.equals(existing.getPriceId())) {
                return new SubscriptionResponseDTO(existing);
            }
            existing.setStatus("CANCELLED");
            subscriptionRepository.save(existing);
        }

        Plan plan = planRepository.findByCode(priceId);

        Subscription sub = new Subscription();
        sub.setUser(user);
        sub.setPaymentCustomerId(customerId);
        sub.setPriceId(priceId);
        sub.setPlan(plan);
        sub.setStatus("ACTIVE");
        sub.setStartedAt(Instant.now());
        sub.setCurrentPeriodEnd(Instant.now().plus(30, ChronoUnit.DAYS));
        sub.setExternalSubscriptionId("direct_" + System.currentTimeMillis());
        sub.setPaymentSubscriptionId("direct_" + System.currentTimeMillis());

        Subscription saved = subscriptionRepository.save(sub);
        return new SubscriptionResponseDTO(saved);
    }

    @Transactional
    public SubscriptionResponseDTO createSubscriptionByUserId(Long userId, String priceId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found with ID: " + userId));

        List<Subscription> active = subscriptionRepository.findByUserAndStatus(user, "ACTIVE");
        for (Subscription existing : active) {
            if (priceId.equals(existing.getPriceId())) {
                return new SubscriptionResponseDTO(existing);
            }
            existing.setStatus("CANCELLED");
            subscriptionRepository.save(existing);
        }

        Plan plan = planRepository.findByCode(priceId);

        Subscription sub = new Subscription();
        sub.setUser(user);
        sub.setPriceId(priceId);
        sub.setPlan(plan);
        sub.setStatus("ACTIVE");
        sub.setStartedAt(Instant.now());
        sub.setCurrentPeriodEnd(Instant.now().plus(30, ChronoUnit.DAYS));
        sub.setExternalSubscriptionId("direct_" + System.currentTimeMillis());
        sub.setPaymentSubscriptionId("direct_" + System.currentTimeMillis());

        Subscription saved = subscriptionRepository.save(sub);
        return new SubscriptionResponseDTO(saved);
    }
}
