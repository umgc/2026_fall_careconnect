package com.careconnect.service;

import com.careconnect.dto.SubscriptionResponseDTO;
import com.careconnect.model.Plan;
import com.careconnect.model.Subscription;
import com.careconnect.model.User;
import com.careconnect.repository.PaymentRepository;
import com.careconnect.repository.PlanRepository;
import com.careconnect.repository.SubscriptionRepository;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class SubscriptionServiceDirectCoverageTest {

    @Mock private SubscriptionRepository subscriptionRepository;
    @Mock private PaymentRepository paymentRepository;
    @Mock private UserRepository userRepository;
    @Mock private PlanRepository planRepository;

    private SubscriptionService service;
    private User user;

    @BeforeEach
    void setUp() {
        service = new SubscriptionService(subscriptionRepository, paymentRepository, userRepository, planRepository);
        user = User.builder().id(1L).build();
        when(userRepository.findByPaymentCustomerId("cus_1")).thenReturn(Optional.of(user));
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(subscriptionRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        Plan plan = new Plan();
        plan.setCode("price_new");
        when(planRepository.findByCode("price_new")).thenReturn(plan);
    }

    private Subscription active(String priceId) {
        Subscription s = new Subscription();
        s.setUser(user);
        s.setPriceId(priceId);
        s.setStatus("ACTIVE");
        return s;
    }

    @Test
    void directSubscriptionReplacesOtherActivePlans() {
        Subscription old = active("price_old");
        when(subscriptionRepository.findByUserAndStatus(user, "ACTIVE")).thenReturn(List.of(old));
        SubscriptionResponseDTO dto = service.createDirectSubscription("cus_1", "price_new");
        assertThat(dto.getPriceId()).isEqualTo("price_new");
        assertThat(old.getStatus()).isEqualTo("CANCELLED");

        SubscriptionResponseDTO byUser = service.createSubscriptionByUserId(1L, "price_new");
        assertThat(byUser.getPriceId()).isEqualTo("price_new");
    }

    @Test
    void directSubscriptionReturnsExistingMatchingPlan() {
        when(subscriptionRepository.findByUserAndStatus(user, "ACTIVE")).thenReturn(List.of(active("price_new")));
        assertThat(service.createDirectSubscription("cus_1", "price_new").getPriceId()).isEqualTo("price_new");
        assertThat(service.createSubscriptionByUserId(1L, "price_new").getPriceId()).isEqualTo("price_new");
    }
}
