package com.careconnect.controller;

import java.util.Map;
import java.util.List;

import com.careconnect.model.Subscription;
import com.careconnect.model.Plan;
import com.careconnect.repository.PlanRepository;
import com.careconnect.repository.SubscriptionRepository;
import com.careconnect.dto.PlanDTO;
import com.careconnect.dto.SubscriptionResponseDTO;
import com.careconnect.service.SubscriptionEnrichmentService;
import com.careconnect.service.SubscriptionService;
import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.UnauthorizedException;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v3/api/subscriptions")
public class SubscriptionController {

    private static final String ERROR_KEY = "error";

    private final SubscriptionEnrichmentService subscriptionEnrichmentService;
    private final SubscriptionService subscriptionService;
    private final PlanRepository planRepository;
    private final SubscriptionRepository subscriptionRepository;

    public SubscriptionController(
            SubscriptionEnrichmentService subscriptionEnrichmentService,
            PlanRepository planRepository,
            SubscriptionRepository subscriptionRepository,
            SubscriptionService subscriptionService
    ) {
        this.subscriptionEnrichmentService = subscriptionEnrichmentService;
        this.planRepository = planRepository;
        this.subscriptionRepository = subscriptionRepository;
        this.subscriptionService = subscriptionService;
    }

    /**
     * Resolves a subscription ID string to a numeric database ID.
     * Accepts either a numeric ID or an external subscription ID string.
     */
    private Long resolveSubscriptionId(String id) {
        try {
            return Long.parseLong(id);
        } catch (NumberFormatException e) {
            Subscription sub = subscriptionRepository.findAll().stream()
                    .filter(s -> id.equals(s.getExternalSubscriptionId()) || id.equals(s.getPaymentSubscriptionId()))
                    .findFirst()
                    .orElse(null);
            return sub != null ? sub.getId() : null;
        }
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/plans")
    public ResponseEntity<List<PlanDTO>> listPlans() {
        List<Plan> activePlans = planRepository.findByIsActiveTrue();
        List<PlanDTO> dtos = activePlans.stream()
                .map(p -> new PlanDTO(
                        String.valueOf(p.getId()),
                        p.getIsActive() != null && p.getIsActive(),
                        p.getPriceCents() != null ? p.getPriceCents() : 0,
                        "usd",
                        p.getBillingPeriod() != null ? p.getBillingPeriod().toLowerCase() : "month",
                        1,
                        String.valueOf(p.getId()),
                        p.getName()
                ))
                .toList();
        return ResponseEntity.ok(dtos);
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @PostMapping("/{id}/cancel")
    public ResponseEntity<Object> cancelSubscription(@PathVariable String id) throws UnauthorizedException {
        try {
            Long subscriptionId = resolveSubscriptionId(id);
            if (subscriptionId == null) {
                return ResponseEntity.badRequest().body(Map.of(ERROR_KEY, "Subscription not found: " + id));
            }

            Subscription sub = subscriptionRepository.findById(subscriptionId)
                    .orElseThrow(() -> new IllegalArgumentException("Subscription not found"));

            sub.setStatus("CANCELLED");
            sub.setCurrentPeriodEnd(null);
            subscriptionRepository.save(sub);

            return ResponseEntity.ok().body(Map.of(
                    "message", "Subscription cancelled successfully",
                    "subscriptionId", id
            ));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of(ERROR_KEY, "Failed to cancel subscription: " + e.getMessage()));
        }
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/user/{userId}")
    public ResponseEntity<Object> getUserSubscriptions(@PathVariable Long userId) throws UnauthorizedException {
        try {
            List<SubscriptionResponseDTO> subscriptionDTOs = subscriptionEnrichmentService.getEnrichedUserSubscriptions(userId);
            return ResponseEntity.ok(subscriptionDTOs);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of(ERROR_KEY, e.getMessage()));
        }
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @GetMapping("/user/{userId}/active")
    public ResponseEntity<Object> getUserActiveSubscriptions(@PathVariable Long userId) throws UnauthorizedException {
        try {
            List<SubscriptionResponseDTO> subscriptionDTOs = subscriptionEnrichmentService.getEnrichedActiveUserSubscriptions(userId);
            return ResponseEntity.ok(subscriptionDTOs);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of(ERROR_KEY, e.getMessage()));
        }
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @PostMapping("/create-direct")
    public ResponseEntity<Object> createDirectSubscription(
            @RequestParam String customerId,
            @RequestParam String priceId) {
        try {
            SubscriptionResponseDTO result = subscriptionService.createDirectSubscription(customerId, priceId);
            return ResponseEntity.ok(result);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of(ERROR_KEY, e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of(ERROR_KEY, "Failed to create subscription: " + e.getMessage()));
        }
    }

    @RequirePermission(Permission.VIEW_ASSIGNED_PATIENTS)
    @PostMapping("/create-by-user")
    public ResponseEntity<Object> createSubscriptionByUser(
            @RequestParam Long userId,
            @RequestParam String priceId) {
        try {
            SubscriptionResponseDTO result = subscriptionService.createSubscriptionByUserId(userId, priceId);
            return ResponseEntity.ok(result);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of(ERROR_KEY, e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of(ERROR_KEY, "Failed to create subscription: " + e.getMessage()));
        }
    }
}
