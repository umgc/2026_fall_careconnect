package com.careconnect.dto;

import com.careconnect.model.Plan;
import com.careconnect.model.Subscription;
import com.careconnect.model.User;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SubscriptionResponseDTOTest {

    private static final Instant NOW = Instant.parse("2026-01-15T10:00:00Z");
    private static final Instant END = Instant.parse("2026-02-15T10:00:00Z");
    @Mock
    private Subscription mockSubscription;
    @Mock
    private User mockUser;
    @Mock
    private Plan mockPlan;

    // ─── No-arg constructor ───────────────────────────────────────────────────

    @Test
    void noArgConstructor_createsInstance() throws Exception {
        final SubscriptionResponseDTO dto = new SubscriptionResponseDTO();

        assertThat(dto).isNotNull();
        assertThat(dto.getId()).isNull();
        assertThat(dto.getPaymentSubscriptionId()).isNull();
        assertThat(dto.getUserId()).isNull();
        assertThat(dto.getPlanId()).isNull();
    }

    // ─── Subscription constructor: user and plan both present ─────────────────

    @Test
    void subscriptionConstructor_withUserAndPlan_mapsAllFields() throws Exception {
        when(mockSubscription.getId()).thenReturn(1L);
        when(mockSubscription.getPaymentSubscriptionId()).thenReturn("sub_abc");
        when(mockSubscription.getPaymentCustomerId()).thenReturn("cus_xyz");
        when(mockSubscription.getPriceId()).thenReturn("price_123");
        when(mockSubscription.getUser()).thenReturn(mockUser);
        when(mockUser.getId()).thenReturn(10L);
        when(mockSubscription.getPlan()).thenReturn(mockPlan);
        when(mockPlan.getId()).thenReturn(5L);
        when(mockPlan.getName()).thenReturn("Premium");
        when(mockPlan.getCode()).thenReturn("PREMIUM");
        when(mockPlan.getPriceCents()).thenReturn(999);
        when(mockSubscription.getStatus()).thenReturn("ACTIVE");
        when(mockSubscription.getStartedAt()).thenReturn(NOW);
        when(mockSubscription.getCurrentPeriodEnd()).thenReturn(END);

        final SubscriptionResponseDTO dto = new SubscriptionResponseDTO(mockSubscription);

        assertThat(dto.getId()).isEqualTo(1L);
        assertThat(dto.getPaymentSubscriptionId()).isEqualTo("sub_abc");
        assertThat(dto.getPaymentCustomerId()).isEqualTo("cus_xyz");
        assertThat(dto.getPriceId()).isEqualTo("price_123");
        assertThat(dto.getUserId()).isEqualTo(10L);
        assertThat(dto.getPlanId()).isEqualTo(5L);
        assertThat(dto.getPlanName()).isEqualTo("Premium");
        assertThat(dto.getPlanCode()).isEqualTo("PREMIUM");
        assertThat(dto.getPriceCents()).isEqualTo(999);
        assertThat(dto.getStatus()).isEqualTo("ACTIVE");
        assertThat(dto.getStartedAt()).isEqualTo(NOW);
        assertThat(dto.getCurrentPeriodEnd()).isEqualTo(END);
    }

    // ─── Subscription constructor: user null ──────────────────────────────────

    @Test
    void subscriptionConstructor_userNull_userIdIsNull() throws Exception {
        when(mockSubscription.getId()).thenReturn(2L);
        when(mockSubscription.getPaymentSubscriptionId()).thenReturn("sub_def");
        when(mockSubscription.getPaymentCustomerId()).thenReturn(null);
        when(mockSubscription.getPriceId()).thenReturn(null);
        when(mockSubscription.getUser()).thenReturn(null);
        when(mockSubscription.getPlan()).thenReturn(mockPlan);
        when(mockPlan.getId()).thenReturn(3L);
        when(mockPlan.getName()).thenReturn("Basic");
        when(mockPlan.getCode()).thenReturn("BASIC");
        when(mockPlan.getPriceCents()).thenReturn(499);
        when(mockSubscription.getStatus()).thenReturn("CANCELLED");
        when(mockSubscription.getStartedAt()).thenReturn(NOW);
        when(mockSubscription.getCurrentPeriodEnd()).thenReturn(null);

        final SubscriptionResponseDTO dto = new SubscriptionResponseDTO(mockSubscription);

        assertThat(dto.getUserId()).isNull();
        assertThat(dto.getPlanId()).isEqualTo(3L);
    }

    // ─── Subscription constructor: plan null ──────────────────────────────────

    @Test
    void subscriptionConstructor_planNull_planFieldsAreNull() throws Exception {
        when(mockSubscription.getId()).thenReturn(3L);
        when(mockSubscription.getPaymentSubscriptionId()).thenReturn("sub_ghi");
        when(mockSubscription.getPaymentCustomerId()).thenReturn(null);
        when(mockSubscription.getPriceId()).thenReturn(null);
        when(mockSubscription.getUser()).thenReturn(mockUser);
        when(mockUser.getId()).thenReturn(20L);
        when(mockSubscription.getPlan()).thenReturn(null);
        when(mockSubscription.getStatus()).thenReturn("ACTIVE");
        when(mockSubscription.getStartedAt()).thenReturn(NOW);
        when(mockSubscription.getCurrentPeriodEnd()).thenReturn(END);

        final SubscriptionResponseDTO dto = new SubscriptionResponseDTO(mockSubscription);

        assertThat(dto.getUserId()).isEqualTo(20L);
        assertThat(dto.getPlanId()).isNull();
        assertThat(dto.getPlanName()).isNull();
        assertThat(dto.getPlanCode()).isNull();
        assertThat(dto.getPriceCents()).isNull();
    }

    // ─── Setters ──────────────────────────────────────────────────────────────

    @Test
    void setters_updateAllFields() throws Exception {
        final SubscriptionResponseDTO dto = new SubscriptionResponseDTO();

        dto.setId(99L);
        dto.setPaymentSubscriptionId("sub_new");
        dto.setPaymentCustomerId("cus_new");
        dto.setPriceId("price_new");
        dto.setUserId(7L);
        dto.setPlanId(8L);
        dto.setPlanName("Enterprise");
        dto.setPlanCode("ENT");
        dto.setPriceCents(1999);
        dto.setStatus("ACTIVE");
        dto.setStartedAt(NOW);
        dto.setCurrentPeriodEnd(END);

        assertThat(dto.getId()).isEqualTo(99L);
        assertThat(dto.getPaymentSubscriptionId()).isEqualTo("sub_new");
        assertThat(dto.getPaymentCustomerId()).isEqualTo("cus_new");
        assertThat(dto.getPriceId()).isEqualTo("price_new");
        assertThat(dto.getUserId()).isEqualTo(7L);
        assertThat(dto.getPlanId()).isEqualTo(8L);
        assertThat(dto.getPlanName()).isEqualTo("Enterprise");
        assertThat(dto.getPlanCode()).isEqualTo("ENT");
        assertThat(dto.getPriceCents()).isEqualTo(1999);
        assertThat(dto.getStatus()).isEqualTo("ACTIVE");
        assertThat(dto.getStartedAt()).isEqualTo(NOW);
        assertThat(dto.getCurrentPeriodEnd()).isEqualTo(END);
    }
}
