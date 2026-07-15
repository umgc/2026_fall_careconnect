package com.careconnect.controller;

import com.careconnect.config.CareconnectTestConfig;
import com.careconnect.model.CallSummary;
import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CallSummaryService;
import com.careconnect.service.CallTelemetryService;
import com.careconnect.service.CallTranscriptService;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.security.oauth2.client.servlet.OAuth2ClientAutoConfiguration;
import org.springframework.boot.autoconfigure.security.oauth2.resource.servlet.OAuth2ResourceServerAutoConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Slice tests for {@link CallSummaryController} (WBS 3.11.6).
 *
 * <p>Covers the {@code GET /api/v3/summaries/{id}} contract:
 * 200 with body on found + authorized (via each of the four access paths),
 * 404 on not-found, 403 on unauthorized, 400 on a non-numeric id.
 */
@WebMvcTest(
        controllers = CallSummaryController.class,
        excludeAutoConfiguration = {
                OAuth2ClientAutoConfiguration.class,
                OAuth2ResourceServerAutoConfiguration.class
        }
)
@Import(CareconnectTestConfig.class)
@ActiveProfiles("test")
@DisplayName("CallSummaryController Tests")
class CallSummaryControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private CallSummaryService callSummaryService;

    @MockitoBean
    private CallTelemetryService callTelemetryService;

    @MockitoBean
    private CallTranscriptService callTranscriptService;

    @MockitoBean
    private UserRepository userRepository;

    private static final long SUMMARY_ID = 101L;
    private static final long CURRENT_USER_ID = 500L;
    private static final long OWNER_USER_ID = 999L;
    private static final String CALL_ID = "call-1";
    private static final String CURRENT_USER_EMAIL = "user";

    private User caregiverUser;

    @BeforeEach
    void setUp() {
        // @WithMockUser defaults username to "user"; findByEmail is called
        // with authentication.getName().
        caregiverUser = new User();
        caregiverUser.setId(CURRENT_USER_ID);
        caregiverUser.setRole(Role.CAREGIVER);
        caregiverUser.setEmail(CURRENT_USER_EMAIL);
        when(userRepository.findByEmail(CURRENT_USER_EMAIL))
                .thenReturn(Optional.of(caregiverUser));

        // Default: no access via any path unless the individual test
        // wires the specific path it's exercising.
        when(callTelemetryService.getTelemetryForCall(anyString()))
                .thenReturn(List.of());
        when(callTranscriptService.hasTranscriptAccess(anyString(), anyLong()))
                .thenReturn(false);
    }

    private Map<String, Object> exampleResponse() {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("callId", CALL_ID);
        response.put("status", "SUCCESS");
        response.put("generatedAt", LocalDateTime.of(2026, 7, 11, 12, 0));
        response.put("transcriptSegmentCount", 3);
        response.put("transcriptArchived", true);
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("headline", "Stable call");
        summary.put("overallAssessment", "Patient remained stable.");
        response.put("summary", summary);
        return response;
    }

    private CallSummary entityOwnedBy(final Long ownerUserId) {
        CallSummary entity = new CallSummary();
        entity.setId(SUMMARY_ID);
        entity.setCallId(CALL_ID);
        entity.setGeneratedByUserId(ownerUserId);
        return entity;
    }

    private CallTelemetryEvent telemetryEventFor(final Long actorUserId) {
        CallTelemetryEvent event = new CallTelemetryEvent();
        event.setActorUserId(actorUserId);
        return event;
    }

    // ---- 200 paths: each of the four authorization routes ----

    @Test
    @WithMockUser
    @DisplayName("returns 200 when caller is admin (regardless of ownership/participation)")
    void getSummaryById_admin_returns200() throws Exception {
        caregiverUser.setRole(Role.ADMIN);
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOwnedBy(OWNER_USER_ID)));
        when(callSummaryService.getSummaryById(SUMMARY_ID))
                .thenReturn(Optional.of(exampleResponse()));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.callId").value(CALL_ID));
    }

    @Test
    @WithMockUser
    @DisplayName("returns 200 when caller is a telemetry participant on the call")
    void getSummaryById_telemetryParticipant_returns200() throws Exception {
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOwnedBy(OWNER_USER_ID)));
        when(callTelemetryService.getTelemetryForCall(CALL_ID))
                .thenReturn(List.of(telemetryEventFor(CURRENT_USER_ID)));
        when(callSummaryService.getSummaryById(SUMMARY_ID))
                .thenReturn(Optional.of(exampleResponse()));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isOk());
    }

    @Test
    @WithMockUser
    @DisplayName("returns 200 when caller has transcript access to the call")
    void getSummaryById_transcriptAccess_returns200() throws Exception {
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOwnedBy(OWNER_USER_ID)));
        when(callTranscriptService.hasTranscriptAccess(CALL_ID, CURRENT_USER_ID))
                .thenReturn(true);
        when(callSummaryService.getSummaryById(SUMMARY_ID))
                .thenReturn(Optional.of(exampleResponse()));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isOk());
    }

    @Test
    @WithMockUser
    @DisplayName("returns 200 when caller is the summary owner (generatedByUserId matches)")
    void getSummaryById_summaryOwner_returns200() throws Exception {
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOwnedBy(CURRENT_USER_ID)));
        when(callSummaryService.getSummaryById(SUMMARY_ID))
                .thenReturn(Optional.of(exampleResponse()));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isOk());
    }

    // ---- Failure paths ----

    @Test
    @WithMockUser
    @DisplayName("returns 403 when caller has none of the four access paths")
    void getSummaryById_noAccess_returns403() throws Exception {
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOwnedBy(OWNER_USER_ID)));
        // Role is CAREGIVER (not ADMIN), no telemetry, no transcript, not owner.

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isForbidden());
    }

    @Test
    @WithMockUser
    @DisplayName("returns 404 when the summary does not exist")
    void getSummaryById_notFound_returns404() throws Exception {
        when(callSummaryService.getSummaryEntityById(999L))
                .thenReturn(Optional.empty());

        mockMvc.perform(get("/api/v3/summaries/{id}", 999L))
                .andExpect(status().isNotFound());
    }

    @Test
    @WithMockUser
    @DisplayName("returns 400 when the id path variable is not a valid Long")
    void getSummaryById_nonNumericId_returns400() throws Exception {
        mockMvc.perform(get("/api/v3/summaries/{id}", "not-a-number"))
                .andExpect(status().isBadRequest());
    }
}