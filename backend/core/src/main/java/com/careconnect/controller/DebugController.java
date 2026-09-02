package com.careconnect.controller;

import com.careconnect.model.Plan;
import com.careconnect.model.User;
import com.careconnect.repository.PlanRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.SubscriptionEnrichmentService;
import com.careconnect.util.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

/**
 * Debug controller providing administrative endpoints for plan inspection,
 * subscription diagnostics, and configuration verification.
 *
 * <p>All endpoints require admin-level authorization.
 */
@RestController
@RequestMapping("/v1/api/debug")
@RequiredArgsConstructor
public class DebugController {

    private static final String MESSAGE_KEY = "message";
    private static final String PREMIUM_PLAN_NAME = "Premium Monthly";
    private static final String STANDARD_PLAN_NAME = "Standard Monthly";
    private static final String ERROR_KEY = "error";
    private static final int PREMIUM_DEFAULT_PRICE_CENTS = 2999;
    private static final String DEFAULT_BILLING_PERIOD = "MONTH";
    private static final String LEGACY_PRICE_ID = "price_1RmqWxELoozGI1YxQql5rsvN";

    private final PlanRepository planRepository;
    private final SubscriptionEnrichmentService subscriptionEnrichmentService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Value("${subscription.premium-price-ids:price_1RmqWxELoozGI1YxQql5rsvN}")
    private String premiumPriceIds;

    @Value("${subscription.standard-price-ids:price_standard}")
    private String standardPriceIds;

    /**
     * Returns all plans currently stored in the database.
     *
     * @return map containing the list of plans and total count
     * @throws UnauthorizedException if the caller does not have admin privileges
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/plans")
    public ResponseEntity<Map<String, Object>> getAllPlans() throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdmin(currentUser);
        List<Plan> plans = planRepository.findAll();
        return ResponseEntity.ok(Map.of(
                "plans", plans,
                "count", plans.size()));
    }

    /**
     * Attempts to match a legacy Stripe price ID to an existing plan in the database.
     *
     * @return diagnostic map showing exact match, premium plan, standard plan,
     * suggested mapping, and price ID membership
     * @throws UnauthorizedException if the caller does not have admin privileges
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/plans/match")
    public ResponseEntity<Map<String, Object>> matchPlanToPrice() throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdmin(currentUser);

        Plan exactPlan = planRepository.findByCode(LEGACY_PRICE_ID);

        List<Plan> premiumPlans = planRepository.findByName(PREMIUM_PLAN_NAME);
        Plan premiumPlan = premiumPlans.isEmpty() ? null : premiumPlans.get(0);

        List<Plan> standardPlans = planRepository.findByName(STANDARD_PLAN_NAME);
        Plan standardPlan = standardPlans.isEmpty() ? null : standardPlans.get(0);

        Plan manualMapping = new Plan();
        manualMapping.setCode(LEGACY_PRICE_ID);
        manualMapping.setName(PREMIUM_PLAN_NAME);
        manualMapping.setPriceCents(PREMIUM_DEFAULT_PRICE_CENTS);
        manualMapping.setBillingPeriod(DEFAULT_BILLING_PERIOD);
        manualMapping.setIsActive(true);

        boolean isPremiumPriceId =
                Arrays.asList(premiumPriceIds.split(",")).contains(LEGACY_PRICE_ID);
        boolean isStandardPriceId =
                Arrays.asList(standardPriceIds.split(",")).contains(LEGACY_PRICE_ID);

        return ResponseEntity.ok(Map.of(
                "priceId", LEGACY_PRICE_ID,
                "exactMatch", exactPlan != null ? exactPlan : "No match found",
                "premiumPlan", premiumPlan != null ? premiumPlan : "No Premium Monthly found",
                "standardPlan", standardPlan != null ? standardPlan : "No Standard Monthly found",
                "suggestedMapping", manualMapping,
                "isPremiumPriceId", isPremiumPriceId,
                "isStandardPriceId", isStandardPriceId,
                "configuredPremiumPriceIds", premiumPriceIds,
                "configuredStandardPriceIds", standardPriceIds));
    }

    /**
     * Creates a plan mapping for the legacy Stripe price ID if one does not already exist.
     *
     * @return result map describing whether a mapping was created or already existed
     * @throws UnauthorizedException if the caller does not have admin privileges
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/plans/create-mapping")
    public ResponseEntity<Map<String, Object>> createPriceMapping() throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdmin(currentUser);

        Plan existingPlan = planRepository.findByCode(LEGACY_PRICE_ID);
        if (existingPlan != null) {
            return ResponseEntity.ok(Map.of(
                    MESSAGE_KEY, "Mapping already exists",
                    "plan", existingPlan));
        }

        List<Plan> premiumPlans = planRepository.findByName(PREMIUM_PLAN_NAME);

        if (!premiumPlans.isEmpty()) {
            Plan premiumPlan = premiumPlans.get(0);
            Plan newPlan = new Plan();
            newPlan.setCode(LEGACY_PRICE_ID);
            newPlan.setName(premiumPlan.getName());
            newPlan.setPriceCents(premiumPlan.getPriceCents());
            newPlan.setBillingPeriod(premiumPlan.getBillingPeriod());
            newPlan.setIsActive(true);

            Plan savedPlan = planRepository.save(newPlan);
            return ResponseEntity.ok(Map.of(
                    MESSAGE_KEY, "Created new plan mapping based on existing Premium Monthly",
                    "originalPlan", premiumPlan,
                    "newPlan", savedPlan));
        } else {
            Plan newPlan = new Plan();
            newPlan.setCode(LEGACY_PRICE_ID);
            newPlan.setName(PREMIUM_PLAN_NAME);
            newPlan.setPriceCents(PREMIUM_DEFAULT_PRICE_CENTS);
            newPlan.setBillingPeriod(DEFAULT_BILLING_PERIOD);
            newPlan.setIsActive(true);

            Plan savedPlan = planRepository.save(newPlan);
            return ResponseEntity.ok(Map.of(
                    MESSAGE_KEY, "Created new Premium Monthly plan",
                    "plan", savedPlan));
        }
    }

    /**
     * Returns the current subscription price ID configuration values.
     *
     * @return map of configured premium and standard price ID strings
     * @throws UnauthorizedException if the caller does not have admin privileges
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/config")
    public ResponseEntity<Map<String, Object>> getConfiguration() throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdmin(currentUser);
        return ResponseEntity.ok(Map.of(
                "premiumPriceIds", premiumPriceIds,
                "standardPriceIds", standardPriceIds,
                "premiumPriceIdsList", Arrays.asList(premiumPriceIds.split(",")),
                "standardPriceIdsList", Arrays.asList(standardPriceIds.split(","))));
    }

    /**
     * Returns enriched subscription records for a given user ID.
     *
     * @param userId the user ID to look up
     * @return list of enriched subscription DTOs or an error map
     * @throws UnauthorizedException if the caller does not have admin privileges
     */
    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/subscriptions/user/{userId}")
    public ResponseEntity<Object> getEnrichedUserSubscriptions(@PathVariable Long userId)
            throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireAdmin(currentUser);
        try {
            return ResponseEntity.ok(
                    subscriptionEnrichmentService.getEnrichedUserSubscriptions(userId));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of(
                    ERROR_KEY, "Failed to get subscriptions: " + e.getMessage()));
        }
    }
}
