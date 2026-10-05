package com.careconnect.controller;

import com.careconnect.dto.BillingQuoteRequest;
import com.careconnect.dto.BillingQuoteResponse;
import com.careconnect.model.BillingPlatform;
import com.careconnect.model.Plan;
import com.careconnect.model.Subscription;
import com.careconnect.model.User;
import com.careconnect.repository.PlanRepository;
import com.careconnect.repository.SubscriptionRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.PaymentService;
import com.careconnect.service.TaxCalculationService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class BillingQuoteControllerTest {

    @Mock
    private PlanRepository planRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private TaxCalculationService taxCalculationService;
    @Mock
    private PaymentService paymentService;
    @Mock
    private SubscriptionRepository subscriptionRepository;

    @InjectMocks
    private BillingQuoteController controller;

    // ---- Helper builders -------------------------------------------------------

    private Plan buildPlan(Long id, String name, int priceCents) {
        Plan plan = new Plan();
        plan.setId(id);
        plan.setName(name);
        plan.setPriceCents(priceCents);
        return plan;
    }

    private User buildUser(Long id, String state) {
        User user = new User();
        user.setId(id);
        user.setState(state);
        return user;
    }

    // ---- getQuote --------------------------------------------------------------

    @Test
    void getQuote_successWithStateProvided() {
        Plan plan = buildPlan(1L, "Premium Monthly", 2000);
        when(planRepository.findById(1L)).thenReturn(Optional.of(plan));
        when(taxCalculationService.getTaxRateByState("CA")).thenReturn(0.0725);
        when(taxCalculationService.calculateTaxCents(2000L, 0.0725)).thenReturn(145L);

        BillingQuoteRequest request = BillingQuoteRequest.builder()
                .tierId(1L)
                .state("CA")
                .build();

        ResponseEntity<BillingQuoteResponse> response = controller.getQuote(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        BillingQuoteResponse body = response.getBody();
        assertThat(body).isNotNull();
        assertThat(body.getTierId()).isEqualTo(1L);
        assertThat(body.getTierName()).isEqualTo("Premium Monthly");
        assertThat(body.getSubtotalCents()).isEqualTo(2000L);
        assertThat(body.getTaxCents()).isEqualTo(145L);
        assertThat(body.getTotalCents()).isEqualTo(2145L);
        assertThat(body.getCurrency()).isEqualTo("USD");
        assertThat(body.getTaxRate()).isEqualTo(0.0725);
        assertThat(body.getTaxJurisdiction()).isEqualTo("CA");
        assertThat(body.getErrorMessage()).isNull();
    }

    @Test
    void getQuote_tierNotFound_returnsBadRequest() {
        when(planRepository.findById(99L)).thenReturn(Optional.empty());

        BillingQuoteRequest request = BillingQuoteRequest.builder()
                .tierId(99L)
                .state("CA")
                .build();

        ResponseEntity<BillingQuoteResponse> response = controller.getQuote(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().getErrorMessage()).isEqualTo("Tier not found");
    }

    @Test
    void getQuote_stateNullFallsBackToUserState() {
        Plan plan = buildPlan(1L, "Basic", 1000);
        User user = buildUser(5L, "NY");
        when(planRepository.findById(1L)).thenReturn(Optional.of(plan));
        when(userRepository.findById(5L)).thenReturn(Optional.of(user));
        when(taxCalculationService.getTaxRateByState("NY")).thenReturn(0.04);
        when(taxCalculationService.calculateTaxCents(1000L, 0.04)).thenReturn(40L);

        BillingQuoteRequest request = BillingQuoteRequest.builder()
                .tierId(1L)
                .userId(5L)
                .build();

        ResponseEntity<BillingQuoteResponse> response = controller.getQuote(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody().getTaxJurisdiction()).isEqualTo("NY");
        assertThat(response.getBody().getTotalCents()).isEqualTo(1040L);
    }

    @Test
    void getQuote_stateEmptyFallsBackToUserState() {
        Plan plan = buildPlan(1L, "Basic", 1000);
        User user = buildUser(5L, "TX");
        when(planRepository.findById(1L)).thenReturn(Optional.of(plan));
        when(userRepository.findById(5L)).thenReturn(Optional.of(user));
        when(taxCalculationService.getTaxRateByState("TX")).thenReturn(0.0625);
        when(taxCalculationService.calculateTaxCents(1000L, 0.0625)).thenReturn(63L);

        BillingQuoteRequest request = BillingQuoteRequest.builder()
                .tierId(1L)
                .userId(5L)
                .state("  ")
                .build();

        ResponseEntity<BillingQuoteResponse> response = controller.getQuote(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody().getTaxJurisdiction()).isEqualTo("TX");
    }

    @Test
    void getQuote_stateNullUserIdNull_returnsBadRequest() {
        Plan plan = buildPlan(1L, "Basic", 1000);
        when(planRepository.findById(1L)).thenReturn(Optional.of(plan));

        BillingQuoteRequest request = BillingQuoteRequest.builder()
                .tierId(1L)
                .build();

        ResponseEntity<BillingQuoteResponse> response = controller.getQuote(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody().getErrorMessage())
                .isEqualTo("State not provided and user address not found");
        assertThat(response.getBody().getTierId()).isEqualTo(1L);
        assertThat(response.getBody().getTierName()).isEqualTo("Basic");
    }

    @Test
    void getQuote_stateNullUserNotFound_returnsBadRequest() {
        Plan plan = buildPlan(1L, "Basic", 1000);
        when(planRepository.findById(1L)).thenReturn(Optional.of(plan));
        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        BillingQuoteRequest request = BillingQuoteRequest.builder()
                .tierId(1L)
                .userId(99L)
                .build();

        ResponseEntity<BillingQuoteResponse> response = controller.getQuote(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody().getErrorMessage())
                .isEqualTo("State not provided and user address not found");
    }

    @Test
    void getQuote_stateNullUserHasNoState_returnsBadRequest() {
        Plan plan = buildPlan(1L, "Basic", 1000);
        User user = buildUser(5L, null);
        when(planRepository.findById(1L)).thenReturn(Optional.of(plan));
        when(userRepository.findById(5L)).thenReturn(Optional.of(user));

        BillingQuoteRequest request = BillingQuoteRequest.builder()
                .tierId(1L)
                .userId(5L)
                .build();

        ResponseEntity<BillingQuoteResponse> response = controller.getQuote(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody().getErrorMessage())
                .isEqualTo("State not provided and user address not found");
    }

    @Test
    void getQuote_exceptionThrown_returnsBadRequestWithMessage() {
        when(planRepository.findById(1L)).thenThrow(new RuntimeException("DB down"));

        BillingQuoteRequest request = BillingQuoteRequest.builder()
                .tierId(1L)
                .state("CA")
                .build();

        ResponseEntity<BillingQuoteResponse> response = controller.getQuote(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody().getErrorMessage())
                .contains("Error calculating quote: DB down");
    }

    // ---- processGooglePayment --------------------------------------------------

    @Test
    void processGooglePayment_success() {
        Plan plan = buildPlan(2L, "Pro", 5000);
        User user = buildUser(10L, "CA");
        when(planRepository.findById(2L)).thenReturn(Optional.of(plan));
        when(taxCalculationService.getTaxRateByState("CA")).thenReturn(0.0725);
        when(taxCalculationService.calculateTaxCents(5000L, 0.0725)).thenReturn(363L);
        when(userRepository.findById(10L)).thenReturn(Optional.of(user));

        Map<String, Object> paymentRequest = new HashMap<>();
        paymentRequest.put("token", "google_tok_123");
        paymentRequest.put("tierId", 2);
        paymentRequest.put("state", "CA");
        paymentRequest.put("userId", 10);

        ResponseEntity<Map<String, Object>> response = controller.processGooglePayment(paymentRequest);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        Map<String, Object> body = response.getBody();
        assertThat(body).isNotNull();
        assertThat(body.get("success")).isEqualTo(true);
        assertThat((String) body.get("message")).contains("GOOGLE Pay payment processed");
        assertThat(body.get("planName")).isEqualTo("Pro");
        assertThat(body.get("currency")).isEqualTo("USD");
        assertThat(body.get("status")).isEqualTo("ACTIVE");

        verify(subscriptionRepository).save(any(Subscription.class));
        verify(paymentService).savePayment(any());
    }

    @Test
    void processGooglePayment_emptyToken_returnsBadRequest() {
        Map<String, Object> paymentRequest = new HashMap<>();
        paymentRequest.put("token", "");
        paymentRequest.put("tierId", 1);
        paymentRequest.put("state", "CA");

        ResponseEntity<Map<String, Object>> response = controller.processGooglePayment(paymentRequest);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody().get("message")).isEqualTo("Payment token is required");
    }

    @Test
    void processGooglePayment_nullToken_returnsBadRequest() {
        Map<String, Object> paymentRequest = new HashMap<>();
        paymentRequest.put("token", null);
        paymentRequest.put("tierId", 1);
        paymentRequest.put("state", "CA");

        ResponseEntity<Map<String, Object>> response = controller.processGooglePayment(paymentRequest);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody().get("message")).isEqualTo("Payment token is required");
    }

    @Test
    void processGooglePayment_invalidTier_returnsBadRequest() {
        when(planRepository.findById(999L)).thenReturn(Optional.empty());

        Map<String, Object> paymentRequest = new HashMap<>();
        paymentRequest.put("token", "google_tok_123");
        paymentRequest.put("tierId", 999);
        paymentRequest.put("state", "CA");

        ResponseEntity<Map<String, Object>> response = controller.processGooglePayment(paymentRequest);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody().get("message")).isEqualTo("Invalid subscription tier");
    }

    @Test
    void processGooglePayment_noUserIdProvided_successWithoutUser() {
        Plan plan = buildPlan(1L, "Basic", 1000);
        when(planRepository.findById(1L)).thenReturn(Optional.of(plan));
        when(taxCalculationService.getTaxRateByState("CA")).thenReturn(0.0725);
        when(taxCalculationService.calculateTaxCents(1000L, 0.0725)).thenReturn(73L);

        Map<String, Object> paymentRequest = new HashMap<>();
        paymentRequest.put("token", "google_tok_456");
        paymentRequest.put("tierId", 1);
        paymentRequest.put("state", "CA");

        ResponseEntity<Map<String, Object>> response = controller.processGooglePayment(paymentRequest);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody().get("success")).isEqualTo(true);
        verify(subscriptionRepository).save(any(Subscription.class));
    }

    @Test
    void processGooglePayment_defaultState_usesCA() {
        Plan plan = buildPlan(1L, "Basic", 1000);
        when(planRepository.findById(1L)).thenReturn(Optional.of(plan));
        when(taxCalculationService.getTaxRateByState("CA")).thenReturn(0.0725);
        when(taxCalculationService.calculateTaxCents(1000L, 0.0725)).thenReturn(73L);

        Map<String, Object> paymentRequest = new HashMap<>();
        paymentRequest.put("token", "google_tok_789");
        paymentRequest.put("tierId", 1);
        // No state key - should default to "CA"

        ResponseEntity<Map<String, Object>> response = controller.processGooglePayment(paymentRequest);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(taxCalculationService).getTaxRateByState("CA");
    }

    @Test
    void processGooglePayment_exceptionThrown_returnsBadRequest() {
        when(planRepository.findById(1L)).thenThrow(new RuntimeException("Connection lost"));

        Map<String, Object> paymentRequest = new HashMap<>();
        paymentRequest.put("token", "google_tok_err");
        paymentRequest.put("tierId", 1);
        paymentRequest.put("state", "CA");

        ResponseEntity<Map<String, Object>> response = controller.processGooglePayment(paymentRequest);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat((String) response.getBody().get("message"))
                .contains("Payment processing failed");
    }

    // ---- processApplePayment ---------------------------------------------------

    @Test
    void processApplePayment_success() {
        Plan plan = buildPlan(3L, "Family", 7000);
        User user = buildUser(20L, "NY");
        when(planRepository.findById(3L)).thenReturn(Optional.of(plan));
        when(taxCalculationService.getTaxRateByState("NY")).thenReturn(0.04);
        when(taxCalculationService.calculateTaxCents(7000L, 0.04)).thenReturn(280L);
        when(userRepository.findById(20L)).thenReturn(Optional.of(user));

        Map<String, Object> paymentRequest = new HashMap<>();
        paymentRequest.put("token", "apple_tok_abc");
        paymentRequest.put("tierId", 3);
        paymentRequest.put("state", "NY");
        paymentRequest.put("userId", 20);

        ResponseEntity<Map<String, Object>> response = controller.processApplePayment(paymentRequest);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        Map<String, Object> body = response.getBody();
        assertThat(body.get("success")).isEqualTo(true);
        assertThat((String) body.get("message")).contains("APPLE Pay payment processed");
        assertThat(body.get("planName")).isEqualTo("Family");

        verify(subscriptionRepository).save(any(Subscription.class));
        verify(paymentService).savePayment(any());
    }

    @Test
    void processApplePayment_invalidTier_returnsBadRequest() {
        when(planRepository.findById(999L)).thenReturn(Optional.empty());

        Map<String, Object> paymentRequest = new HashMap<>();
        paymentRequest.put("token", "apple_tok_xyz");
        paymentRequest.put("tierId", 999);

        ResponseEntity<Map<String, Object>> response = controller.processApplePayment(paymentRequest);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody().get("message")).isEqualTo("Invalid subscription tier");
    }

    @Test
    void processApplePayment_userIdZero_noUserSet() {
        Plan plan = buildPlan(1L, "Basic", 1000);
        when(planRepository.findById(1L)).thenReturn(Optional.of(plan));
        when(taxCalculationService.getTaxRateByState("CA")).thenReturn(0.0725);
        when(taxCalculationService.calculateTaxCents(1000L, 0.0725)).thenReturn(73L);

        Map<String, Object> paymentRequest = new HashMap<>();
        paymentRequest.put("token", "apple_tok_zero");
        paymentRequest.put("tierId", 1);
        paymentRequest.put("state", "CA");
        paymentRequest.put("userId", 0);

        ResponseEntity<Map<String, Object>> response = controller.processApplePayment(paymentRequest);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(userRepository, never()).findById(anyLong());
    }

    @Test
    void processApplePayment_userNotFoundInRepo_successWithoutUser() {
        Plan plan = buildPlan(1L, "Basic", 1000);
        when(planRepository.findById(1L)).thenReturn(Optional.of(plan));
        when(taxCalculationService.getTaxRateByState("CA")).thenReturn(0.0725);
        when(taxCalculationService.calculateTaxCents(1000L, 0.0725)).thenReturn(73L);
        when(userRepository.findById(999L)).thenReturn(Optional.empty());

        Map<String, Object> paymentRequest = new HashMap<>();
        paymentRequest.put("token", "apple_tok_nf");
        paymentRequest.put("tierId", 1);
        paymentRequest.put("state", "CA");
        paymentRequest.put("userId", 999);

        ResponseEntity<Map<String, Object>> response = controller.processApplePayment(paymentRequest);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody().get("success")).isEqualTo(true);
    }
}
