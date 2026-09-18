package com.careconnect.controller;

import com.careconnect.dto.PlanDTO;
import com.careconnect.dto.SubscriptionResponseDTO;
import com.careconnect.model.Plan;
import com.careconnect.model.Subscription;
import com.careconnect.repository.PlanRepository;
import com.careconnect.repository.SubscriptionRepository;
import com.careconnect.service.SubscriptionEnrichmentService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class SubscriptionControllerTest {

    private static final Long USER_ID = 1L;
    @Mock
    private SubscriptionEnrichmentService subscriptionEnrichmentService;
    @Mock
    private PlanRepository planRepository;
    @Mock
    private SubscriptionRepository subscriptionRepository;
    @InjectMocks
    private SubscriptionController controller;

    // ─── listPlans ────────────────────────────────────────────────────────────

    @Test
    void listPlans_returnsOkWithPlanList() throws Exception {
        Plan plan = Plan.builder()
                .id(1L)
                .name("Pro")
                .isActive(true)
                .priceCents(999)
                .billingPeriod("month")
                .build();
        when(planRepository.findByIsActiveTrue()).thenReturn(List.of(plan));

        ResponseEntity<List<PlanDTO>> response = controller.listPlans();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).nickname()).isEqualTo("Pro");
        assertThat(response.getBody().get(0).amount()).isEqualTo(999);
    }

    @Test
    void listPlans_emptyList_returnsOkWithEmptyList() throws Exception {
        when(planRepository.findByIsActiveTrue()).thenReturn(List.of());

        ResponseEntity<List<PlanDTO>> response = controller.listPlans();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }

    @Test
    void listPlans_nullFields_returnsDefaults() throws Exception {
        Plan plan = Plan.builder()
                .id(2L)
                .name("Basic")
                .isActive(null)
                .priceCents(null)
                .billingPeriod(null)
                .build();
        when(planRepository.findByIsActiveTrue()).thenReturn(List.of(plan));

        ResponseEntity<List<PlanDTO>> response = controller.listPlans();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        List<PlanDTO> body = response.getBody();
        assertThat(body).hasSize(1);
        assertThat(body.get(0).active()).isFalse();
        assertThat(body.get(0).amount()).isEqualTo(0);
        assertThat(body.get(0).interval()).isEqualTo("month");
    }

    // ─── cancelSubscription ──────────────────────────────────────────────────

    @Test
    void cancelSubscription_numericId_cancelsAndReturnsOk() throws Exception {
        Subscription sub = new Subscription();
        sub.setId(42L);
        sub.setStatus("ACTIVE");
        when(subscriptionRepository.findById(42L)).thenReturn(Optional.of(sub));
        when(subscriptionRepository.save(any())).thenReturn(sub);

        ResponseEntity<Object> response = controller.cancelSubscription("42");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("message", "Subscription cancelled successfully");
        assertThat(sub.getStatus()).isEqualTo("CANCELLED");
        assertThat(sub.getCurrentPeriodEnd()).isNull();
        verify(subscriptionRepository).save(sub);
    }

    @Test
    void cancelSubscription_stripeId_resolvesViaFindAllAndCancels() throws Exception {
        Subscription sub = new Subscription();
        sub.setId(10L);
        sub.setPaymentSubscriptionId("sub_abc");
        sub.setStatus("ACTIVE");
        when(subscriptionRepository.findAll()).thenReturn(List.of(sub));
        when(subscriptionRepository.findById(10L)).thenReturn(Optional.of(sub));
        when(subscriptionRepository.save(any())).thenReturn(sub);

        ResponseEntity<Object> response = controller.cancelSubscription("sub_abc");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(sub.getStatus()).isEqualTo("CANCELLED");
    }

    @Test
    void cancelSubscription_unresolvedId_returnsBadRequest() throws Exception {
        when(subscriptionRepository.findAll()).thenReturn(List.of());

        ResponseEntity<Object> response = controller.cancelSubscription("not-found");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("error").toString()).contains("Subscription not found");
    }

    @Test
    void cancelSubscription_numericIdNotInDb_returnsInternalServerError() throws Exception {
        when(subscriptionRepository.findById(999L)).thenReturn(Optional.empty());

        ResponseEntity<Object> response = controller.cancelSubscription("999");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body.get("error").toString()).contains("Failed to cancel subscription");
    }

    // ─── getUserSubscriptions ────────────────────────────────────────────────

    @Test
    void getUserSubscriptions_success_returnsOk() throws Exception {
        List<SubscriptionResponseDTO> dtos = List.of(new SubscriptionResponseDTO());
        when(subscriptionEnrichmentService.getEnrichedUserSubscriptions(USER_ID)).thenReturn(dtos);

        ResponseEntity<Object> response = controller.getUserSubscriptions(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(dtos);
    }

    @Test
    void getUserSubscriptions_exception_returnsBadRequest() throws Exception {
        when(subscriptionEnrichmentService.getEnrichedUserSubscriptions(USER_ID))
                .thenThrow(new RuntimeException("fail"));

        ResponseEntity<Object> response = controller.getUserSubscriptions(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("error", "fail");
    }

    // ─── getUserActiveSubscriptions ──────────────────────────────────────────

    @Test
    void getUserActiveSubscriptions_success_returnsOk() throws Exception {
        List<SubscriptionResponseDTO> dtos = List.of();
        when(subscriptionEnrichmentService.getEnrichedActiveUserSubscriptions(USER_ID)).thenReturn(dtos);

        ResponseEntity<Object> response = controller.getUserActiveSubscriptions(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(dtos);
    }

    @Test
    void getUserActiveSubscriptions_exception_returnsBadRequest() throws Exception {
        when(subscriptionEnrichmentService.getEnrichedActiveUserSubscriptions(USER_ID))
                .thenThrow(new RuntimeException("fail"));

        ResponseEntity<Object> response = controller.getUserActiveSubscriptions(USER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsEntry("error", "fail");
    }
}
