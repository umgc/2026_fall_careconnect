package com.careconnect.service;

import com.careconnect.model.Plan;
import com.careconnect.repository.PlanRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * Stripe checkout is no longer used. Apple Pay and Google Pay are the payment methods.
 * This stub remains so any residual references compile.
 */
@Service
@RequiredArgsConstructor
public class StripeCheckoutService {
    private final PlanRepository planRepository;

    public List<Plan> getAvailablePlans() {
        return planRepository.findByIsActiveTrue();
    }

    public Plan createPlan(String code, String name, Integer priceCents, String billingPeriod, Boolean isActive) {
        Plan plan = new Plan();
        plan.setCode(code);
        plan.setName(name);
        plan.setPriceCents(priceCents);
        plan.setBillingPeriod(billingPeriod);
        plan.setIsActive(isActive != null ? isActive : true);
        return planRepository.save(plan);
    }
}
