package com.careconnect.controller;

import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.http.ResponseEntity;
import org.springframework.beans.factory.annotation.Autowired;
import com.careconnect.dto.BillingVerifyRequest;
import com.careconnect.dto.BillingVerifyResponse;
import com.careconnect.service.AppleBillingService;
import com.careconnect.service.GoogleBillingService;
import com.careconnect.repository.PlanRepository;
import org.springframework.web.bind.annotation.RequestHeader;
import com.careconnect.security.JwtTokenProvider;

@RestController
@RequestMapping("/v1/api/billing")
public class BillingController {

    private final AppleBillingService appleBillingService;
    private final GoogleBillingService googleBillingService;
    private final com.careconnect.service.PaymentService paymentService;
    private final com.careconnect.repository.SubscriptionRepository subscriptionRepository;
    private final com.careconnect.repository.UserRepository userRepository;
    private final PlanRepository planRepository;
    private final JwtTokenProvider jwtTokenProvider;

    @Autowired
    public BillingController(AppleBillingService appleBillingService,
                             GoogleBillingService googleBillingService,
                             com.careconnect.service.PaymentService paymentService,
                             com.careconnect.repository.SubscriptionRepository subscriptionRepository,
                             com.careconnect.repository.UserRepository userRepository,
                             PlanRepository planRepository,
                             JwtTokenProvider jwtTokenProvider) {
        this.appleBillingService = appleBillingService;
        this.googleBillingService = googleBillingService;
        this.paymentService = paymentService;
        this.subscriptionRepository = subscriptionRepository;
        this.userRepository = userRepository;
        this.planRepository = planRepository;
        this.jwtTokenProvider = jwtTokenProvider;
    }

    private com.careconnect.model.User resolveUserFromToken(String authHeader) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) return null;
        try {
            String token = authHeader.substring(7);
            if (jwtTokenProvider.validateToken(token)) {
                String email = jwtTokenProvider.getEmailFromToken(token);
                return userRepository.findByEmail(email).orElse(null);
            }
        } catch (Exception ignored) {
            // ignore invalid token
        }
        return null;
    }

    private com.careconnect.model.User resolveUser(String authHeader, Long requestUserId) {
        com.careconnect.model.User user = resolveUserFromToken(authHeader);
        if (user == null && requestUserId != null) {
            user = userRepository.findById(requestUserId).orElse(null);
        }
        return user;
    }

    private String mapProductIdToPlanCode(String productId) {
        if (productId == null) return null;
        switch (productId) {
            case "standard_monthly":
                return "plan_standard_monthly";
            case "premium_monthly":
                return "plan_premium_monthly";
            case "free_monthly":
                return "plan_free";
            default:
                return productId;
        }
    }

    private void cancelOtherActiveSubscriptions(com.careconnect.model.User user, String externalSubscriptionId) {
        subscriptionRepository.findByUserAndStatus(user, "ACTIVE").stream()
                .filter(s -> s.getExternalSubscriptionId() == null ||
                        !s.getExternalSubscriptionId().equals(externalSubscriptionId))
                .forEach(s -> {
                    // Cancel on Google Play if this was a Google subscription
                    if (com.careconnect.model.BillingPlatform.GOOGLE.equals(s.getPlatform())
                            && s.getPriceId() != null
                            && s.getPaymentSubscriptionId() != null) {
                        googleBillingService.cancelSubscription(s.getPriceId(), s.getPaymentSubscriptionId());
                    }
                    s.setStatus("CANCELLED");
                    subscriptionRepository.save(s);
                });
    }

    private com.careconnect.model.Subscription findOrCreateSubscription(String externalSubscriptionId) {
        if (externalSubscriptionId != null) {
            return subscriptionRepository.findAll().stream()
                    .filter(s -> externalSubscriptionId.equals(s.getExternalSubscriptionId()))
                    .findFirst()
                    .orElse(new com.careconnect.model.Subscription());
        }
        return new com.careconnect.model.Subscription();
    }

    private void saveSubscription(com.careconnect.model.User user,
                                  com.careconnect.model.BillingPlatform platform,
                                  BillingVerifyRequest request,
                                  BillingVerifyResponse resp,
                                  com.careconnect.model.Payment payment) {
        cancelOtherActiveSubscriptions(user, resp.getExternalSubscriptionId());
        com.careconnect.model.Subscription sub = findOrCreateSubscription(resp.getExternalSubscriptionId());
        String planCode = mapProductIdToPlanCode(request.getProductId());
        com.careconnect.model.Plan plan = planCode != null ? planRepository.findByCode(planCode) : null;
        sub.setUser(user);
        sub.setPlatform(platform);
        sub.setExternalSubscriptionId(resp.getExternalSubscriptionId());
        sub.setPaymentSubscriptionId(resp.getExternalSubscriptionId() != null ?
                resp.getExternalSubscriptionId() : platform.name().toLowerCase() + "_" + System.currentTimeMillis());
        sub.setPriceId(planCode);
        sub.setPlan(plan);
        sub.setStatus(resp.getStatus());
        sub.setStartedAt(resp.getPurchaseDate());
        sub.setCurrentPeriodEnd(resp.getExpiryDate());
        sub.setLastValidatedAt(java.time.Instant.now());
        subscriptionRepository.save(sub);
        payment.setSubscription(sub);
        paymentService.savePayment(payment);
    }

    private com.careconnect.model.Payment buildPayment(com.careconnect.model.BillingPlatform platform,
                                                       BillingVerifyRequest request,
                                                       BillingVerifyResponse resp) {
        return com.careconnect.model.Payment.builder()
                .platform(platform)
                .platformPurchaseToken(request.getReceipt())
                .platformPayerId(resp.getExternalTransactionId())
                .externalTransactionId(resp.getExternalTransactionId())
                .status(resp.isSuccess() ? "SUCCEEDED" : "FAILED")
                .amountCents(null)
                .attemptedAt(resp.getPurchaseDate())
                .build();
    }

    @PostMapping("/verify/apple")
    public ResponseEntity<?> verifyApple(@RequestBody BillingVerifyRequest request,
                                         @RequestHeader(value = "Authorization", required = false) String authHeader) {
        try {
            BillingVerifyResponse resp = appleBillingService.verifyReceipt(request);
            com.careconnect.model.Payment p = buildPayment(com.careconnect.model.BillingPlatform.APPLE, request, resp);
            paymentService.savePayment(p);
            com.careconnect.model.User user = resolveUser(authHeader, request.getUserId());
            if (user != null) saveSubscription(user, com.careconnect.model.BillingPlatform.APPLE, request, resp, p);
            return ResponseEntity.ok(resp);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(java.util.Map.of("error", e.getMessage()));
        }
    }

    @PostMapping("/verify/google")
    public ResponseEntity<?> verifyGoogle(@RequestBody BillingVerifyRequest request,
                                          @RequestHeader(value = "Authorization", required = false) String authHeader) {
        try {
            BillingVerifyResponse resp = googleBillingService.verifyReceipt(request);
            com.careconnect.model.Payment p = buildPayment(com.careconnect.model.BillingPlatform.GOOGLE, request, resp);
            paymentService.savePayment(p);
            com.careconnect.model.User user = resolveUser(authHeader, request.getUserId());
            if (user != null) saveSubscription(user, com.careconnect.model.BillingPlatform.GOOGLE, request, resp, p);
            return ResponseEntity.ok(resp);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(java.util.Map.of("error", e.getMessage()));
        }
    }

    @PostMapping("/webhook/apple")
    public ResponseEntity<?> appleWebhook(@RequestBody String body, @RequestHeader(value = "Authorization", required = false) String auth) {
        return ResponseEntity.ok(java.util.Map.of("message", "apple webhook received"));
    }

    @PostMapping("/webhook/google")
    public ResponseEntity<?> googleWebhook(@RequestBody String body, @RequestHeader(value = "Authorization", required = false) String auth) {
        return ResponseEntity.ok(java.util.Map.of("message", "google webhook received"));
    }
}
