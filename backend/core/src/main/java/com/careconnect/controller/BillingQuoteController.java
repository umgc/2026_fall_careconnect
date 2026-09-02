package com.careconnect.controller;

import com.careconnect.dto.BillingQuoteRequest;
import com.careconnect.dto.BillingQuoteResponse;
import com.careconnect.model.BillingPlatform;
import com.careconnect.model.Payment;
import com.careconnect.model.Plan;
import com.careconnect.model.Subscription;
import com.careconnect.model.User;
import com.careconnect.repository.PlanRepository;
import com.careconnect.repository.SubscriptionRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.PaymentService;
import com.careconnect.service.TaxCalculationService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.HashMap;
import java.util.Map;

/**
 * REST controller providing billing quote and payment processing endpoints.
 *
 * <p>Supports tax-aware billing quotes and wallet-style payment submission
 * for both Google Pay and Apple Pay platforms.
 */
@RestController
@RequestMapping("/v1/api/billing")
@Tag(name = "Billing", description = "Billing and subscription endpoints")
public class BillingQuoteController {

    private static final String DEFAULT_STATE = "CA";
    private static final String CURRENCY_USD = "USD";
    private static final int SUBSCRIPTION_PERIOD_DAYS = 30;
    private static final String KEY_SUCCESS = "success";
    private static final String KEY_MESSAGE = "message";
    private static final String KEY_USER_ID = "userId";


    @Autowired
    private PlanRepository planRepository;
    @Autowired
    private UserRepository userRepository;
    @Autowired
    private TaxCalculationService taxCalculationService;
    @Autowired
    private PaymentService paymentService;
    @Autowired
    private SubscriptionRepository subscriptionRepository;

    /**
     * Calculates a billing quote with tax breakdown for a given subscription tier.
     *
     * @param request the billing quote request containing tier ID and optional state
     * @return a {@link BillingQuoteResponse} with subtotal, tax, and total amounts
     */
    @PostMapping("/quote")
    @Operation(
            summary = "Get billing quote with tax breakdown",
            description =
                    "Calculate subtotal, taxes, and total for a subscription tier"
                            + " based on user's address/state",
            requestBody =
            @io.swagger.v3.oas.annotations.parameters.RequestBody(
                    description = "Billing quote request with tier ID and optional state",
                    required = true,
                    content =
                    @Content(
                            mediaType = "application/json",
                            schema = @Schema(implementation = BillingQuoteRequest.class),
                            examples =
                            @ExampleObject(
                                    name = "Quote Request Example",
                                    value =
                                            """
                                                    {
                                                        "tierId": 3,
                                                        "userId": 123,
                                                        "state": "CA"
                                                    }
                                                    """))))
    @ApiResponses(
            value = {
                    @ApiResponse(
                            responseCode = "200",
                            description = "Quote calculated",
                            content =
                            @Content(
                                    mediaType = "application/json",
                                    examples =
                                    @ExampleObject(
                                            value =
                                                    """
                                                            {
                                                                "tierId": 3,
                                                                "tierName": "Premium Monthly",
                                                                "subtotalCents": 2999,
                                                                "taxCents": 217,
                                                                "totalCents": 3216,
                                                                "currency": "USD",
                                                                "taxRate": 0.0725,
                                                                "taxJurisdiction": "CA"
                                                            }
                                                            """))),
                    @ApiResponse(responseCode = "400", description = "Invalid request or missing data")
            })
    public ResponseEntity<BillingQuoteResponse> getQuote(
            @RequestBody BillingQuoteRequest request) {
        try {
            Plan plan = planRepository.findById(request.getTierId()).orElse(null);
            if (plan == null) {
                return ResponseEntity.badRequest().body(
                        BillingQuoteResponse.builder().errorMessage("Tier not found").build());
            }

            String state = resolveState(request);
            if (state == null || state.trim().isEmpty()) {
                return ResponseEntity.badRequest().body(
                        BillingQuoteResponse.builder()
                                .tierId(request.getTierId())
                                .tierName(plan.getName())
                                .errorMessage("State not provided and user address not found")
                                .build());
            }

            long subtotalCents = plan.getPriceCents().longValue();
            double taxRate = taxCalculationService.getTaxRateByState(state);
            long taxCents = taxCalculationService.calculateTaxCents(subtotalCents, taxRate);
            long totalCents = subtotalCents + taxCents;

            BillingQuoteResponse response =
                    BillingQuoteResponse.builder()
                            .tierId(plan.getId())
                            .tierName(plan.getName())
                            .subtotalCents(subtotalCents)
                            .taxCents(taxCents)
                            .totalCents(totalCents)
                            .currency(CURRENCY_USD)
                            .taxRate(taxRate)
                            .taxJurisdiction(state)
                            .build();

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(
                    BillingQuoteResponse.builder()
                            .errorMessage("Error calculating quote: " + e.getMessage())
                            .build());
        }
    }

    /**
     * Processes a Google Pay payment and persists the resulting subscription.
     *
     * @param paymentRequest map containing token, tierId, state, and optional userId
     * @return result map with transaction ID, subscription ID, and status
     */
    @PostMapping("/pay/google")
    @Operation(
            summary = "Process Google Pay payment",
            description = "Accept a Google Pay token, record Payment and Subscription in DB")
    @ApiResponse(responseCode = "200", description = "Payment processed successfully")
    @ApiResponse(responseCode = "400", description = "Invalid payment request")
    public ResponseEntity<Map<String, Object>> processGooglePayment(
            @RequestBody Map<String, Object> paymentRequest) {
        return processWalletPayment(paymentRequest, BillingPlatform.GOOGLE);
    }

    /**
     * Processes an Apple Pay payment and persists the resulting subscription.
     *
     * @param paymentRequest map containing token, tierId, state, and optional userId
     * @return result map with transaction ID, subscription ID, and status
     */
    @PostMapping("/pay/apple")
    @Operation(
            summary = "Process Apple Pay payment",
            description = "Accept an Apple Pay token, record Payment and Subscription in DB")
    @ApiResponse(responseCode = "200", description = "Payment processed successfully")
    @ApiResponse(responseCode = "400", description = "Invalid payment request")
    public ResponseEntity<Map<String, Object>> processApplePayment(
            @RequestBody Map<String, Object> paymentRequest) {
        return processWalletPayment(paymentRequest, BillingPlatform.APPLE);
    }

    // ----------------------------------------------------------
    // Private helpers
    // ----------------------------------------------------------

    private String resolveState(BillingQuoteRequest request) {
        String state = request.getState();
        if ((state == null || state.trim().isEmpty()) && request.getUserId() != null) {
            User user = userRepository.findById(request.getUserId()).orElse(null);
            if (user != null && user.getState() != null) {
                state = user.getState();
            }
        }
        return state;
    }

    private ResponseEntity<Map<String, Object>> processWalletPayment(
            Map<String, Object> paymentRequest, BillingPlatform platform) {
        try {
            String token = (String) paymentRequest.get("token");
            long tierId = ((Number) paymentRequest.get("tierId")).longValue();
            String state = (String) paymentRequest.getOrDefault("state", DEFAULT_STATE);
            Long userId =
                    paymentRequest.containsKey(KEY_USER_ID) && paymentRequest.get(KEY_USER_ID) != null
                            ? ((Number) paymentRequest.get(KEY_USER_ID)).longValue()

                            : null;

            if (token == null || token.isEmpty()) {
                return ResponseEntity.badRequest().body(
                        Map.of(KEY_SUCCESS, false, KEY_MESSAGE, "Payment token is required"));
            }

            Plan plan = planRepository.findById(tierId).orElse(null);
            if (plan == null) {
                return ResponseEntity.badRequest().body(
                        Map.of(KEY_SUCCESS, false, KEY_MESSAGE, "Invalid subscription tier"));
            }

            long subtotalCents = plan.getPriceCents().longValue();
            double taxRate = taxCalculationService.getTaxRateByState(state);
            long taxCents = taxCalculationService.calculateTaxCents(subtotalCents, taxRate);
            long totalCents = subtotalCents + taxCents;

            String transactionId = platform.name().toLowerCase() + "_" + System.currentTimeMillis();

            User user = null;
            if (userId != null && userId > 0) {
                user = userRepository.findById(userId).orElse(null);
            }

            Subscription subscription = buildSubscription(transactionId, platform, plan, user);
            subscriptionRepository.save(subscription);

            Payment payment =
                    Payment.builder()
                            .platform(platform)
                            .platformPurchaseToken(token)
                            .externalTransactionId(transactionId)
                            .amountCents((int) totalCents)
                            .status("SUCCEEDED")
                            .attemptedAt(Instant.now())
                            .subscription(subscription)
                            .user(user)
                            .build();
            paymentService.savePayment(payment);

            Map<String, Object> result = new HashMap<>();
            result.put(KEY_SUCCESS, true);
            result.put(KEY_MESSAGE, platform.name() + " Pay payment processed successfully");
            result.put("transactionId", transactionId);
            result.put("subscriptionId", subscription.getId());
            result.put("amount", totalCents / 100.0);
            result.put("planName", plan.getName());
            result.put("currency", CURRENCY_USD);
            result.put("status", "ACTIVE");
            return ResponseEntity.ok(result);

        } catch (Exception e) {
            return ResponseEntity.badRequest().body(
                    Map.of(KEY_SUCCESS, false,
                            KEY_MESSAGE, "Payment processing failed: " + e.getMessage()));

        }
    }

    private Subscription buildSubscription(
            String transactionId, BillingPlatform platform, Plan plan, User user) {
        Subscription subscription = new Subscription();
        subscription.setPaymentSubscriptionId(transactionId);
        subscription.setPlatform(platform);
        subscription.setExternalSubscriptionId(transactionId);
        subscription.setStatus("ACTIVE");
        subscription.setStartedAt(Instant.now());
        subscription.setCurrentPeriodEnd(
                Instant.now().plus(SUBSCRIPTION_PERIOD_DAYS, ChronoUnit.DAYS));
        subscription.setPlan(plan);
        if (user != null) {
            subscription.setUser(user);
        }
        return subscription;
    }
}
