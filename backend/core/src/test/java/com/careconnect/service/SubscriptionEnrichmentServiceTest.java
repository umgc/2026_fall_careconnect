package com.careconnect.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.careconnect.dto.SubscriptionResponseDTO;
import com.careconnect.model.Plan;
import com.careconnect.model.Subscription;
import com.careconnect.model.User;
import com.careconnect.repository.PlanRepository;
import com.careconnect.repository.SubscriptionRepository;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.Collections;
import java.util.List;
import java.util.Optional;

/**
 * Unit tests for {@link SubscriptionEnrichmentService}.
 *
 * <p>All external dependencies (repositories) are mocked with Mockito, so no database
 * is needed. The service is instantiated directly via its constructor.</p>
 *
 * <p>Tests are grouped by the public method they exercise:</p>
 * <ul>
 *   <li>{@link SubscriptionEnrichmentService#getEnrichedUserSubscriptions}</li>
 *   <li>{@link SubscriptionEnrichmentService#getEnrichedActiveUserSubscriptions}</li>
 *   <li>{@link SubscriptionEnrichmentService#enrichSubscriptions}</li>
 * </ul>
 */
class SubscriptionEnrichmentServiceTest {

    // ─── Mocked dependencies ──────────────────────────────────────────────────

    @Mock
    private SubscriptionRepository subscriptionRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private PlanRepository planRepository;

    // The service under test
    private SubscriptionEnrichmentService service;

    // ─── Setup ────────────────────────────────────────────────────────────────

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);

        service = new SubscriptionEnrichmentService(
                subscriptionRepository,
                userRepository,
                planRepository);

        // Safe lenient defaults
        lenient().when(planRepository.findAll()).thenReturn(Collections.emptyList());
    }

    // ─── Object-building helpers ──────────────────────────────────────────────

    /**
     * Creates a User with the given ID.
     */
    private User buildUser(Long id) {
        return User.builder()
                .id(id)
                .email("user" + id + "@example.com")
                .password("pw")
                .build();
    }

    /**
     * Creates a Subscription with the given fields.
     */
    private Subscription buildSubscription(
            Long id, User user, String stripeSubId, String status, String priceId) {
        final Subscription sub = new Subscription();
        sub.setId(id);
        sub.setUser(user);
        sub.setPaymentSubscriptionId(stripeSubId);
        sub.setStatus(status);
        sub.setPriceId(priceId);
        return sub;
    }

    /**
     * Creates a Plan with the given fields.
     */
    private Plan buildPlan(Long id, String code, String name, Integer priceCents) {
        final Plan plan = new Plan();
        plan.setId(id);
        plan.setCode(code);
        plan.setName(name);
        plan.setPriceCents(priceCents);
        plan.setBillingPeriod("MONTH");
        plan.setIsActive(true);
        return plan;
    }

    // ==========================================================================
    // getEnrichedUserSubscriptions
    // ==========================================================================

    @Test
    @DisplayName("getEnrichedUserSubscriptions: throws IllegalArgumentException when user does not exist")
    void testGetEnrichedUserSubscriptions_userNotFound() {
        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        assertThrows(
                IllegalArgumentException.class,
                () -> service.getEnrichedUserSubscriptions(99L));
    }

    @Test
    @DisplayName("getEnrichedUserSubscriptions: returns enriched list for user with subscriptions")
    void testGetEnrichedUserSubscriptions_returnsEnrichedList() {
        final User user = buildUser(1L);
        final Subscription sub = buildSubscription(1L, user, null, "ACTIVE", null);

        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(subscriptionRepository.findByUser(user)).thenReturn(List.of(sub));

        final List<SubscriptionResponseDTO> result = service.getEnrichedUserSubscriptions(1L);

        assertNotNull(result);
        assertEquals(1, result.size());
        assertEquals("ACTIVE", result.get(0).getStatus());
    }

    @Test
    @DisplayName("getEnrichedUserSubscriptions: returns empty list when user has no subscriptions")
    void testGetEnrichedUserSubscriptions_noSubscriptions() {
        final User user = buildUser(2L);

        when(userRepository.findById(2L)).thenReturn(Optional.of(user));
        when(subscriptionRepository.findByUser(user)).thenReturn(Collections.emptyList());

        final List<SubscriptionResponseDTO> result = service.getEnrichedUserSubscriptions(2L);

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getEnrichedUserSubscriptions: returns all subscriptions regardless of status")
    void testGetEnrichedUserSubscriptions_returnsAllStatuses() {
        final User user = buildUser(3L);
        final Subscription activeSub = buildSubscription(1L, user, null, "ACTIVE", null);
        final Subscription cancelledSub = buildSubscription(2L, user, null, "CANCELLED", null);

        when(userRepository.findById(3L)).thenReturn(Optional.of(user));
        when(subscriptionRepository.findByUser(user)).thenReturn(List.of(activeSub, cancelledSub));

        final List<SubscriptionResponseDTO> result = service.getEnrichedUserSubscriptions(3L);

        assertNotNull(result);
        assertEquals(2, result.size());
    }

    // ==========================================================================
    // getEnrichedActiveUserSubscriptions
    // ==========================================================================

    @Test
    @DisplayName("getEnrichedActiveUserSubscriptions: throws IllegalArgumentException when user does not exist")
    void testGetEnrichedActiveUserSubscriptions_userNotFound() {
        when(userRepository.findById(77L)).thenReturn(Optional.empty());

        assertThrows(
                IllegalArgumentException.class,
                () -> service.getEnrichedActiveUserSubscriptions(77L));
    }

    @Test
    @DisplayName("getEnrichedActiveUserSubscriptions: returns only ACTIVE subscriptions")
    void testGetEnrichedActiveUserSubscriptions_returnsActiveOnly() {
        final User user = buildUser(20L);
        final Subscription activeSub = buildSubscription(20L, user, null, "ACTIVE", null);
        final Subscription cancelledSub = buildSubscription(21L, user, null, "CANCELLED", null);

        when(userRepository.findById(20L)).thenReturn(Optional.of(user));
        when(subscriptionRepository.findByUser(user)).thenReturn(List.of(activeSub, cancelledSub));

        final List<SubscriptionResponseDTO> result = service.getEnrichedActiveUserSubscriptions(20L);

        assertNotNull(result);
        assertEquals(1, result.size());
        assertEquals("ACTIVE", result.get(0).getStatus());
    }

    @Test
    @DisplayName("getEnrichedActiveUserSubscriptions: returns empty list when no active subscriptions exist")
    void testGetEnrichedActiveUserSubscriptions_noneActive_returnsEmpty() {
        final User user = buildUser(22L);
        final Subscription cancelledSub = buildSubscription(23L, user, null, "CANCELLED", null);

        when(userRepository.findById(22L)).thenReturn(Optional.of(user));
        when(subscriptionRepository.findByUser(user)).thenReturn(List.of(cancelledSub));

        final List<SubscriptionResponseDTO> result = service.getEnrichedActiveUserSubscriptions(22L);

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getEnrichedActiveUserSubscriptions: returns empty list when user has no subscriptions at all")
    void testGetEnrichedActiveUserSubscriptions_noSubscriptions() {
        final User user = buildUser(24L);

        when(userRepository.findById(24L)).thenReturn(Optional.of(user));
        when(subscriptionRepository.findByUser(user)).thenReturn(Collections.emptyList());

        final List<SubscriptionResponseDTO> result = service.getEnrichedActiveUserSubscriptions(24L);

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    // ==========================================================================
    // enrichSubscriptions
    // ==========================================================================

    @Test
    @DisplayName("enrichSubscriptions: returns empty list when given an empty input list")
    void testEnrichSubscriptions_emptyList() {
        final List<SubscriptionResponseDTO> result = service.enrichSubscriptions(Collections.emptyList());

        assertNotNull(result);
        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("enrichSubscriptions: builds DTO from the plan already linked to the subscription")
    void testEnrichSubscriptions_subscriptionHasPlan() {
        final Plan plan = buildPlan(1L, "premium_code", "Premium Plan", 3000);
        final Subscription sub = new Subscription();
        sub.setId(30L);
        sub.setStatus("ACTIVE");
        sub.setPlan(plan);

        when(planRepository.findAll()).thenReturn(List.of(plan));

        final List<SubscriptionResponseDTO> result = service.enrichSubscriptions(List.of(sub));

        assertEquals(1, result.size());
        assertEquals("Premium Plan", result.get(0).getPlanName());
        assertEquals("premium_code", result.get(0).getPlanCode());
        assertEquals(3000, result.get(0).getPriceCents());
    }

    @Test
    @DisplayName("enrichSubscriptions: resolves plan from the plans-by-code map when priceId matches a plan code")
    void testEnrichSubscriptions_resolvesPlanByCode() {
        final String priceId = "price_premium_test";
        final Plan plan = buildPlan(2L, priceId, "Premium Plan", 3000);
        final Subscription sub = new Subscription();
        sub.setId(31L);
        sub.setStatus("ACTIVE");
        sub.setPriceId(priceId);

        when(planRepository.findAll()).thenReturn(List.of(plan));

        final List<SubscriptionResponseDTO> result = service.enrichSubscriptions(List.of(sub));

        assertEquals(1, result.size());
        assertEquals(2L, result.get(0).getPlanId());
        assertEquals("Premium Plan", result.get(0).getPlanName());
        assertEquals(3000, result.get(0).getPriceCents());
    }

    @Test
    @DisplayName("enrichSubscriptions: falls back to Premium Monthly when priceId does not match any plan code")
    void testEnrichSubscriptions_unknownPriceId_fallsToPremiumPlan() {
        final Plan premiumPlan = buildPlan(5L, "premium_code", "Premium Monthly", 3000);
        final Subscription sub = new Subscription();
        sub.setId(32L);
        sub.setStatus("ACTIVE");
        sub.setPriceId("price_unknown_xyz");

        when(planRepository.findAll()).thenReturn(List.of(premiumPlan));

        final List<SubscriptionResponseDTO> result = service.enrichSubscriptions(List.of(sub));

        assertEquals(1, result.size());
        assertEquals("Premium Monthly", result.get(0).getPlanName());
        assertEquals(5L, result.get(0).getPlanId());
        assertEquals(3000, result.get(0).getPriceCents());
    }

    @Test
    @DisplayName("enrichSubscriptions: falls back to Standard Monthly when no Premium Monthly exists and priceId is unmatched")
    void testEnrichSubscriptions_unknownPriceId_fallsToStandardPlan() {
        final Plan standardPlan = buildPlan(6L, "std_code", "Standard Monthly", 2000);
        final Subscription sub = new Subscription();
        sub.setId(33L);
        sub.setStatus("ACTIVE");
        sub.setPriceId("price_unknown_xyz");

        when(planRepository.findAll()).thenReturn(List.of(standardPlan));

        final List<SubscriptionResponseDTO> result = service.enrichSubscriptions(List.of(sub));

        assertEquals(1, result.size());
        assertEquals("Standard Monthly", result.get(0).getPlanName());
        assertEquals(6L, result.get(0).getPlanId());
        assertEquals(2000, result.get(0).getPriceCents());
    }

    @Test
    @DisplayName("enrichSubscriptions: uses hardcoded Premium Monthly defaults when no plans exist in DB and priceId is unmatched")
    void testEnrichSubscriptions_noPlanInDb_usesHardcodedDefaults() {
        final Subscription sub = new Subscription();
        sub.setId(34L);
        sub.setStatus("ACTIVE");
        sub.setPriceId("price_unknown_xyz");

        when(planRepository.findAll()).thenReturn(Collections.emptyList());

        final List<SubscriptionResponseDTO> result = service.enrichSubscriptions(List.of(sub));

        assertEquals(1, result.size());
        assertEquals("Premium Monthly", result.get(0).getPlanName());
        assertEquals(2999, result.get(0).getPriceCents());
        assertNull(result.get(0).getPlanId(), "No DB plan means planId should be null");
    }

    @Test
    @DisplayName("enrichSubscriptions: uses hardcoded Premium Monthly defaults when priceId is null and no plans exist")
    void testEnrichSubscriptions_nullPriceId_noPlanInDb_usesHardcodedDefaults() {
        final Subscription sub = new Subscription();
        sub.setId(35L);
        sub.setStatus("ACTIVE");
        sub.setPriceId(null);

        when(planRepository.findAll()).thenReturn(Collections.emptyList());

        final List<SubscriptionResponseDTO> result = service.enrichSubscriptions(List.of(sub));

        assertEquals(1, result.size());
        assertEquals("Premium Monthly", result.get(0).getPlanName());
        assertEquals(2999, result.get(0).getPriceCents());
        assertNull(result.get(0).getPlanId());
    }

    @Test
    @DisplayName("enrichSubscriptions: falls back to Premium Monthly when priceId is null but a Premium Monthly exists in DB")
    void testEnrichSubscriptions_nullPriceId_premiumPlanExists_usesPremiumPlan() {
        final Plan premiumPlan = buildPlan(7L, "premium_code", "Premium Monthly", 3000);
        final Subscription sub = new Subscription();
        sub.setId(36L);
        sub.setStatus("ACTIVE");
        sub.setPriceId(null);

        when(planRepository.findAll()).thenReturn(List.of(premiumPlan));

        final List<SubscriptionResponseDTO> result = service.enrichSubscriptions(List.of(sub));

        assertEquals(1, result.size());
        assertEquals("Premium Monthly", result.get(0).getPlanName());
        assertEquals(7L, result.get(0).getPlanId());
        assertEquals(3000, result.get(0).getPriceCents());
    }

    @Test
    @DisplayName("enrichSubscriptions: enriches multiple subscriptions correctly")
    void testEnrichSubscriptions_multipleSubscriptions() {
        final Plan premiumPlan = buildPlan(1L, "premium_code", "Premium Plan", 3000);
        final Plan standardPlan = buildPlan(2L, "standard_code", "Standard Plan", 2000);

        final Subscription sub1 = new Subscription();
        sub1.setId(40L);
        sub1.setStatus("ACTIVE");
        sub1.setPriceId("premium_code");

        final Subscription sub2 = new Subscription();
        sub2.setId(41L);
        sub2.setStatus("ACTIVE");
        sub2.setPriceId("standard_code");

        when(planRepository.findAll()).thenReturn(List.of(premiumPlan, standardPlan));

        final List<SubscriptionResponseDTO> result = service.enrichSubscriptions(List.of(sub1, sub2));

        assertEquals(2, result.size());
        assertEquals("Premium Plan", result.get(0).getPlanName());
        assertEquals("Standard Plan", result.get(1).getPlanName());
    }

    @Test
    @DisplayName("enrichSubscriptions: preserves subscription status in DTO")
    void testEnrichSubscriptions_preservesStatus() {
        final Subscription sub = new Subscription();
        sub.setId(42L);
        sub.setStatus("CANCELLED");
        sub.setPriceId(null);

        when(planRepository.findAll()).thenReturn(Collections.emptyList());

        final List<SubscriptionResponseDTO> result = service.enrichSubscriptions(List.of(sub));

        assertEquals(1, result.size());
        assertEquals("CANCELLED", result.get(0).getStatus());
    }
}
