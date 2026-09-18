package com.careconnect.service;

import com.careconnect.dto.SubscriptionResponseDTO;
import com.careconnect.model.Plan;
import com.careconnect.model.Subscription;
import com.careconnect.model.User;
import com.careconnect.repository.PlanRepository;
import com.careconnect.repository.SubscriptionRepository;
import com.careconnect.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Enriches subscription records with plan details from the database.
 *
 * <p>All subscription data is sourced from the local database. Payment provider
 * integration (Google Pay, Apple Pay) is handled by the billing services and
 * writes to the database directly.
 */
@Service
public class SubscriptionEnrichmentService {

    private static final Logger LOG =
            LoggerFactory.getLogger(SubscriptionEnrichmentService.class);

    private static final String PREMIUM_PLAN_NAME = "Premium Monthly";
    private static final String STANDARD_PLAN_NAME = "Standard Monthly";
    private static final int PREMIUM_DEFAULT_PRICE_CENTS = 2999;

    private final SubscriptionRepository subscriptionRepository;
    private final UserRepository userRepository;
    private final PlanRepository planRepository;

    /**
     * Constructs a new {@code SubscriptionEnrichmentService}.
     */
    public SubscriptionEnrichmentService(
            SubscriptionRepository subscriptionRepository,
            UserRepository userRepository,
            PlanRepository planRepository) {
        this.subscriptionRepository = subscriptionRepository;
        this.userRepository = userRepository;
        this.planRepository = planRepository;
    }

    /**
     * Returns all subscriptions for a user, enriched with plan details.
     *
     * @param userId the user ID
     * @return list of enriched subscription DTOs
     */
    @Transactional(readOnly = true)
    public List<SubscriptionResponseDTO> getEnrichedUserSubscriptions(Long userId) {
        User user = resolveUser(userId);
        List<Subscription> subscriptions = subscriptionRepository.findByUser(user);
        LOG.debug("Found {} subscription(s) for user {}", subscriptions.size(), userId);
        return enrichSubscriptions(subscriptions);
    }

    /**
     * Returns only active subscriptions for a user, enriched with plan details.
     *
     * @param userId the user ID
     * @return list of enriched active subscription DTOs
     */
    @Transactional(readOnly = true)
    public List<SubscriptionResponseDTO> getEnrichedActiveUserSubscriptions(Long userId) {
        User user = resolveUser(userId);
        List<Subscription> active =
                subscriptionRepository.findByUser(user).stream()
                        .filter(s -> "ACTIVE".equalsIgnoreCase(s.getStatus()))
                        .sorted((a, b) -> b.getStartedAt().compareTo(a.getStartedAt()))
                        .limit(1)
                        .collect(Collectors.toList());

        LOG.debug("Found {} active subscription(s) for user {}", active.size(), userId);
        return enrichSubscriptions(active);
    }

    /**
     * Enriches a list of subscriptions with plan details from the database.
     *
     * @param subscriptions list of subscriptions to enrich
     * @return list of enriched subscription DTOs
     */
    @Transactional(readOnly = true)
    public List<SubscriptionResponseDTO> enrichSubscriptions(List<Subscription> subscriptions) {
        List<Plan> allPlans = planRepository.findAll();
        Map<String, Plan> plansByCode =
                allPlans.stream()
                        .filter(p -> p.getCode() != null)
                        .collect(Collectors.toMap(Plan::getCode, p -> p, (a, b) -> a));

        Plan premiumPlan = findPlanByName(allPlans, PREMIUM_PLAN_NAME);
        Plan standardPlan = findPlanByName(allPlans, STANDARD_PLAN_NAME);

        return subscriptions.stream()
                .map(sub -> buildDto(sub, plansByCode, premiumPlan, standardPlan))
                .collect(Collectors.toList());
    }

    // ----------------------------------------------------------
    // Private helpers
    // ----------------------------------------------------------

    private User resolveUser(Long userId) {
        return userRepository
                .findById(userId)
                .orElseThrow(
                        () -> new IllegalArgumentException("User not found with ID: " + userId));
    }

    private SubscriptionResponseDTO buildDto(
            Subscription sub,
            Map<String, Plan> plansByCode,
            Plan premiumPlan,
            Plan standardPlan) {

        SubscriptionResponseDTO dto = new SubscriptionResponseDTO(sub);

        // If plan already set on subscription, nothing more to do
        if (sub.getPlan() != null) {
            return dto;
        }

        // Try to resolve plan by price/product code
        String priceId = sub.getPriceId();
        if (priceId == null) {
            applyDefaultPlan(dto, premiumPlan);
            return dto;
        }

        Plan plan = plansByCode.get(priceId);
        if (plan != null) {
            applyPlan(dto, plan);
        } else if (premiumPlan != null) {
            applyPlan(dto, premiumPlan);
        } else if (standardPlan != null) {
            applyPlan(dto, standardPlan);
        } else {
            applyDefaultPlan(dto, null);
        }

        return dto;
    }

    private void applyPlan(SubscriptionResponseDTO dto, Plan plan) {
        dto.setPlanId(plan.getId());
        dto.setPlanName(plan.getName());
        dto.setPlanCode(plan.getCode());
        dto.setPriceCents(plan.getPriceCents());
    }

    private void applyDefaultPlan(SubscriptionResponseDTO dto, Plan fallback) {
        if (fallback != null) {
            applyPlan(dto, fallback);
        } else {
            dto.setPlanName(PREMIUM_PLAN_NAME);
            dto.setPriceCents(PREMIUM_DEFAULT_PRICE_CENTS);
        }
    }

    private Plan findPlanByName(List<Plan> plans, String name) {
        return plans.stream()
                .filter(p -> name.equals(p.getName()))
                .findFirst()
                .orElse(null);
    }
}
