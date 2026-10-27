package com.careconnect.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.careconnect.config.CareconnectTestConfig;
import com.careconnect.dto.conditiondetection.ConditionFlagsResponse;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.conditiondetection.ConditionFlagQueryService;
import com.careconnect.service.conditiondetection.ConditionScreeningCopy;
import com.careconnect.testsupport.fixtures.ConditionDetectionFixtures;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.security.oauth2.client.servlet.OAuth2ClientAutoConfiguration;
import org.springframework.boot.autoconfigure.security.oauth2.resource.servlet.OAuth2ResourceServerAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Import;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Slice tests for {@link ConditionFlagController}.
 *
 * <p>The query service and user repository are mocked: this suite validates the HTTP contract
 * and the {@code @PreAuthorize} role gate, not the flag logic (covered by
 * {@code ConditionFlagQueryServiceTest}). {@code @WebMvcTest} does not load the application's
 * {@code SecurityConfig}, so method security is not active by default; the nested
 * {@link MethodSecurity} configuration enables it so the annotation is genuinely enforced
 * instead of being assumed.</p>
 */
@WebMvcTest(
        controllers = ConditionFlagController.class,
        excludeAutoConfiguration = {
                OAuth2ClientAutoConfiguration.class,
                OAuth2ResourceServerAutoConfiguration.class
        }
)
@Import({CareconnectTestConfig.class, ConditionFlagControllerTest.MethodSecurity.class})
@ActiveProfiles("test")
@DisplayName("ConditionFlagController Tests")
class ConditionFlagControllerTest {

    private static final String CALL_ID = "call-1";
    private static final String URL = "/api/v3/calls/" + CALL_ID + "/condition-flags";
    /** {@code @WithMockUser} defaults to the username "user", which the controller looks up by email. */
    private static final String MOCK_USER_EMAIL = "user";

    /** Turns on {@code @PreAuthorize} processing, which the slice test omits. */
    @TestConfiguration
    @EnableMethodSecurity
    static class MethodSecurity {
    }

    @Autowired
    private MockMvc mockMvc;
    @MockitoBean
    private ConditionFlagQueryService queryService;
    @MockitoBean
    private UserRepository userRepository;

    private User currentUser;

    /** Defaults to a caregiver account; each test overrides the role via {@code @WithMockUser}. */
    @BeforeEach
    void setUp() throws Exception {
        currentUser = ConditionDetectionFixtures.user(500L, Role.CAREGIVER);
        currentUser.setEmail(MOCK_USER_EMAIL);
        when(userRepository.findByEmail(MOCK_USER_EMAIL)).thenReturn(Optional.of(currentUser));
        when(queryService.getFlags(any(), eq(CALL_ID))).thenReturn(new ConditionFlagsResponse(
                ConditionScreeningCopy.DISCLAIMER_EN,
                List.of(new ConditionFlagsResponse.ModelRun(
                        "kintsugi-dam-3.1", "Voice screening", "PATIENT_AUDIO", "COMPLETE", null,
                        "2026-10-07T12:30:15Z",
                        List.of(new ConditionFlagsResponse.Flag("DEPRESSION", 1, "MILD_TO_MODERATE", null))))));
    }

    /** Scenario: a patient token reaches the endpoint; method security must stop it first. */
    @Test
    @WithMockUser(roles = "PATIENT")
    @DisplayName("PATIENT role is forbidden and never reaches the service")
    void getConditionFlags_patientRole_returns403() throws Exception {
        // Act + Assert
        mockMvc.perform(get(URL)).andExpect(status().isForbidden());

        verifyNoInteractions(queryService);
    }

    /** Scenario: an unauthenticated request is rejected before the controller runs. */
    @Test
    @DisplayName("anonymous request is rejected")
    void getConditionFlags_anonymous_isRejected() throws Exception {
        mockMvc.perform(get(URL)).andExpect(status().is4xxClientError());

        verify(queryService, never()).getFlags(any(), any());
    }

    /** Scenario: each permitted role gets the JSON body; the same mock is reused for all three. */
    @Test
    @WithMockUser(roles = "CAREGIVER")
    @DisplayName("CAREGIVER role gets 200 with JSON body")
    void getConditionFlags_caregiver_returns200() throws Exception {
        assertOkBody();
        verify(queryService).getFlags(currentUser, CALL_ID);
    }

    /** Scenario: a family member with the role gets the same body as a caregiver. */
    @Test
    @WithMockUser(roles = "FAMILY_MEMBER")
    @DisplayName("FAMILY_MEMBER role gets 200 with JSON body")
    void getConditionFlags_familyMember_returns200() throws Exception {
        assertOkBody();
    }

    /** Scenario: an admin gets the same body; link checks happen in the service, not here. */
    @Test
    @WithMockUser(roles = "ADMIN")
    @DisplayName("ADMIN role gets 200 with JSON body")
    void getConditionFlags_admin_returns200() throws Exception {
        assertOkBody();
    }

    /** Scenario: the service refuses (no active link); the controller must not return 200. */
    @Test
    @WithMockUser(roles = "CAREGIVER")
    @DisplayName("service UnauthorizedException is not reported as success")
    void getConditionFlags_serviceRefuses_isNotOk() throws Exception {
        when(queryService.getFlags(any(), eq(CALL_ID))).thenThrow(new UnauthorizedException("no link"));

        mockMvc.perform(get(URL)).andExpect(status().is4xxClientError());
    }

    /** Scenario: the authenticated principal has no user row, so the request is unauthorized. */
    @Test
    @WithMockUser(roles = "CAREGIVER")
    @DisplayName("unknown principal returns 401")
    void getConditionFlags_unknownUser_returns401() throws Exception {
        when(userRepository.findByEmail(MOCK_USER_EMAIL)).thenReturn(Optional.empty());

        mockMvc.perform(get(URL)).andExpect(status().isUnauthorized());
    }

    private void assertOkBody() throws Exception {
        mockMvc.perform(get(URL))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.disclaimer").value(ConditionScreeningCopy.DISCLAIMER_EN))
                .andExpect(jsonPath("$.runs[0].modelId").value("kintsugi-dam-3.1"))
                .andExpect(jsonPath("$.runs[0].status").value("COMPLETE"))
                .andExpect(jsonPath("$.runs[0].completedAt").value("2026-10-07T12:30:15Z"))
                .andExpect(jsonPath("$.runs[0].flags[0].condition").value("DEPRESSION"))
                .andExpect(jsonPath("$.runs[0].flags[0].severityLevel").value(1))
                .andExpect(jsonPath("$.runs[0].flags[0].rawScore").doesNotExist());
    }
}
