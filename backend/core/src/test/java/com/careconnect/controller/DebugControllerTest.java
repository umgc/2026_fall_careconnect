package com.careconnect.controller;

import com.careconnect.model.Plan;
import com.careconnect.model.User;
import com.careconnect.repository.PlanRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.SubscriptionEnrichmentService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@ExtendWith(MockitoExtension.class)
        /*
         * MockitoExtension enables strict stubbing.
         * This ensures no unused mocks or argument mismatches exist.
         */
class DebugControllerTest {

    private MockMvc mockMvc;

    @Mock
    private PlanRepository planRepository;
    /*
     * Mocked to isolate controller logic.
     * We do not hit the database.
     */

    @Mock
    private SubscriptionEnrichmentService subscriptionEnrichmentService;
    /*
     * Mocked to prevent real transactional logic from executing.
     */

    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private DebugController controller;
    /*
     * Injects mocks into controller constructor.
     */

    @BeforeEach
    void setUp() throws Exception {
        mockMvc = MockMvcBuilders
                .standaloneSetup(controller)
                .build();
        /*
         * standaloneSetup keeps the test lightweight.
         */

        // Inject @Value properties manually since Spring context isn't loaded
        ReflectionTestUtils.setField(controller,
                "premiumPriceIds",
                "price_1RmqWxELoozGI1YxQql5rsvN,price_other");

        ReflectionTestUtils.setField(controller,
                "standardPriceIds",
                "price_standard");
        /*
         * Required because @Value fields are not injected
         * when using standaloneSetup.
         */

        // Stub security calls that every endpoint requires
        when(securityUtil.resolveCurrentUser()).thenReturn(new User());
        /*
         * Every controller method calls resolveCurrentUser() and requireAdmin().
         * requireAdmin() is void and does nothing by default on a mock,
         * so only resolveCurrentUser() needs an explicit stub.
         */
    }

    @Test
    void getAllPlans_shouldReturnPlansAndCount() throws Exception {

        when(planRepository.findAll())
                .thenReturn(List.of(new Plan(), new Plan()));

        mockMvc.perform(get("/v1/api/debug/plans"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(2));
        /*
         * Ensures:
         * - Plans are returned
         * - Count matches list size
         */
    }

    @Test
    void matchPlanToPrice_shouldReturnMatchingInfo() throws Exception {

        final Plan premium = new Plan();
        premium.setName("Premium Monthly");

        when(planRepository.findByCode("price_1RmqWxELoozGI1YxQql5rsvN"))
                .thenReturn(null);

        when(planRepository.findByName("Premium Monthly"))
                .thenReturn(List.of(premium));

        when(planRepository.findByName("Standard Monthly"))
                .thenReturn(List.of());

        mockMvc.perform(get("/v1/api/debug/plans/match"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isPremiumPriceId").value(true));
        /*
         * Validates:
         * - Price ID matching logic works
         * - Premium ID is recognized from config
         */
    }

    @Test
    void createPriceMapping_shouldReturnExistingMapping() throws Exception {

        final Plan existing = new Plan();
        existing.setCode("price_1RmqWxELoozGI1YxQql5rsvN");

        when(planRepository.findByCode("price_1RmqWxELoozGI1YxQql5rsvN"))
                .thenReturn(existing);

        mockMvc.perform(get("/v1/api/debug/plans/create-mapping"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message")
                        .value("Mapping already exists"));
        /*
         * Ensures controller does not create duplicate mapping.
         */
    }

    @Test
    void createPriceMapping_shouldClonePremiumPlan() throws Exception {

        when(planRepository.findByCode("price_1RmqWxELoozGI1YxQql5rsvN"))
                .thenReturn(null);

        final Plan premium = new Plan();
        premium.setName("Premium Monthly");
        premium.setPriceCents(3000);
        premium.setBillingPeriod("MONTH");

        when(planRepository.findByName("Premium Monthly"))
                .thenReturn(List.of(premium));

        when(planRepository.save(any()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        mockMvc.perform(get("/v1/api/debug/plans/create-mapping"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message")
                        .value("Created new plan mapping based on existing Premium Monthly"));
        /*
         * Ensures:
         * - Existing Premium Plan is cloned
         * - save() is invoked
         */
    }

    @Test
    void createPriceMapping_shouldCreateNewPlan_whenNoPremiumPlanExists() throws Exception {

        when(planRepository.findByCode("price_1RmqWxELoozGI1YxQql5rsvN"))
                .thenReturn(null);

        when(planRepository.findByName("Premium Monthly"))
                .thenReturn(List.of());

        when(planRepository.save(any()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        mockMvc.perform(get("/v1/api/debug/plans/create-mapping"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message")
                        .value("Created new Premium Monthly plan"));
        /*
         * Ensures:
         * - A brand-new Premium Plan is created when none exists
         * - save() is invoked
         */
    }

    @Test
    void getConfiguration_shouldReturnConfigValues() throws Exception {

        mockMvc.perform(get("/v1/api/debug/config"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.premiumPriceIds").exists())
                .andExpect(jsonPath("$.standardPriceIdsList").isArray());
        /*
         * Validates:
         * - @Value fields are exposed correctly
         * - Split lists are returned as arrays
         */
    }

    @Test
    void getEnrichedUserSubscriptions_shouldReturnData() throws Exception {

        when(subscriptionEnrichmentService.getEnrichedUserSubscriptions(1L))
                .thenReturn(List.of());

        mockMvc.perform(get("/v1/api/debug/subscriptions/user/1"))
                .andExpect(status().isOk());
        /*
         * Ensures successful service delegation.
         */
    }

    @Test
    void getEnrichedUserSubscriptions_shouldReturnBadRequest_whenException() throws Exception {

        when(subscriptionEnrichmentService.getEnrichedUserSubscriptions(1L))
                .thenThrow(new RuntimeException("Failure"));

        mockMvc.perform(get("/v1/api/debug/subscriptions/user/1"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").exists());
        /*
         * Ensures exception is translated into HTTP 400.
         */
    }
}
