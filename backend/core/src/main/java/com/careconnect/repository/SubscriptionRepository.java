package com.careconnect.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import com.careconnect.model.Subscription;
import com.careconnect.model.User;

import java.util.List;
import java.util.Optional;

public interface SubscriptionRepository extends JpaRepository<Subscription, Long> {
    Optional<Subscription> findByPaymentSubscriptionId(String stripeId);

    List<Subscription> findByUser(User user);

    List<Subscription> findByPaymentCustomerId(String paymentCustomerId);

    List<Subscription> findByUserAndStatus(User user, String status);
}
