package com.careconnect.service;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import com.careconnect.dto.PlanDTO;

import java.util.List;
import java.util.Collections;

/**
 * Stripe is no longer used as the payment processor.
 * Apple Pay and Google Pay are processed via BillingQuoteController.
 * This stub remains so that any @Autowired(required=false) references compile.
 */
@Service
@ConditionalOnProperty(name = "careconnect.stripe.enabled", havingValue = "true", matchIfMissing = false)
public class StripeService {

    public List<PlanDTO> listPlans() {
        return Collections.emptyList();
    }

    public String listProducts() {
        return "{}";
    }

    public String listSubscriptions(String customerId) {
        return "{}";
    }

    public String getSubscription(String subscriptionId) {
        return "{}";
    }

    public java.util.Map<String, Object> createCustomer(String name, String email) {
        return java.util.Map.of("id", "cus_stub_" + System.currentTimeMillis(), "success", true);
    }

    public java.util.Map<String, Object> createSubscription(String customerId, String priceId) {
        return java.util.Map.of("id", "sub_stub_" + System.currentTimeMillis(), "success", true);
    }

    public String getCustomerActiveSubscriptions(String customerId) {
        return "{}";
    }
}
