package com.careconnect.controller;

import com.careconnect.config.CareconnectTestConfig;
import com.careconnect.exception.AppException;
import com.careconnect.model.CallSummary;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CallSessionService;
import com.careconnect.service.CallSummaryService;
import com.careconnect.service.consent.CaregiverVisibilityCheck;
import com.careconnect.service.consent.CaregiverVisibilityService;
import com.careconnect.service.consent.CaregiverVisibilityStatus;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
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
import org.springframework.http.HttpStatus;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Slice tests for {@link CallSummaryController} (WBS 3.11.6 + TC-E-SUM-009).
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
    private CallSessionService callSessionService;

    @MockitoBean
    private UserRepository userRepository;

    @MockitoBean
    private CaregiverVisibilityService caregiverVisibilityService;

    private static final long SUMMARY_ID = 101L;
    private static final long CURRENT_USER_ID = 500L;
    private static final long OWNER_USER_ID = 999L;
    private static final long PATIENT_ID = 77L;
    private static final String CALL_ID = "call-1";
    private static final String CURRENT_USER_EMAIL = "user";

    private User caregiverUser;

    @BeforeEach
    void setUp() {
        caregiverUser = new User();
        caregiverUser.setId(CURRENT_USER_ID);
        caregiverUser.setRole(Role.CAREGIVER);
        caregiverUser.setEmail(CURRENT_USER_EMAIL);
        when(userRepository.findByEmail(CURRENT_USER_EMAIL))
                .thenReturn(Optional.of(caregiverUser));
        doThrow(new AppException(HttpStatus.FORBIDDEN, "User has no historical call access"))
                .when(callSessionService)
                .requireHistoricalParticipant(anyString(), anyLong());
        doThrow(new AppException(HttpStatus.FORBIDDEN, "Access denied"))
                .when(callSessionService)
                .requirePatientEntityAccess(any(), anyLong());
        // TC-E-SUM-009 default: on_consent gate is a no-op (status=NONE).
        when(caregiverVisibilityService.getStatus(anyLong(), anyLong()))
                .thenReturn(CaregiverVisibilityCheck.none());
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
        entity.setPatientId(PATIENT_ID);
        return entity;
    }

    private CallSummary entityOnConsentOwnedBy(final Long ownerUserId, final Long patientId) {
        CallSummary entity = entityOwnedBy(ownerUserId);
        entity.setCaregiverVisibility("on_consent");
        entity.setPatientId(patientId);
        return entity;
    }

    private void grantHistoricalAccess() {
        org.mockito.Mockito.doReturn(new com.careconnect.model.CallSession())
                .when(callSessionService)
                .requireHistoricalParticipant(CALL_ID, CURRENT_USER_ID);
    }

    @Test
    @WithMockUser
    @DisplayName("returns 200 when caller is admin")
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
    @DisplayName("returns 200 when caller is a durable historical participant")
    void getSummaryById_historicalParticipant_returns200() throws Exception {
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOwnedBy(OWNER_USER_ID)));
        grantHistoricalAccess();
        when(callSummaryService.getSummaryById(SUMMARY_ID))
                .thenReturn(Optional.of(exampleResponse()));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isOk());
    }

    @Test
    @WithMockUser
    @DisplayName("returns 200 when caller has current patient relationship")
    void getSummaryById_patientRelationship_returns200() throws Exception {
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOwnedBy(OWNER_USER_ID)));
        doNothing().when(callSessionService)
                .requirePatientEntityAccess(caregiverUser, PATIENT_ID);
        when(callSummaryService.getSummaryById(SUMMARY_ID))
                .thenReturn(Optional.of(exampleResponse()));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isOk());

        verify(callSessionService).requirePatientEntityAccess(caregiverUser, PATIENT_ID);
    }

    @Test
    @WithMockUser
    @DisplayName("denies summary when only a forged telemetry target would have granted access")
    void getSummaryById_forgedTelemetryTarget_returns403() throws Exception {
        final CallSummary summary = entityOwnedBy(OWNER_USER_ID);
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(summary));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isForbidden());

        verify(callSessionService).requireHistoricalParticipant(CALL_ID, CURRENT_USER_ID);
        verify(callSessionService).requirePatientEntityAccess(eq(caregiverUser), eq(PATIENT_ID));
        verify(callSummaryService, never()).getSummaryById(SUMMARY_ID);
    }

    @Test
    @WithMockUser
    @DisplayName("returns 403 when caller is only the summary generator without durable access")
    void getSummaryById_summaryOwnerAlone_returns403() throws Exception {
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOwnedBy(CURRENT_USER_ID)));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isForbidden());
    }

    @Test
    @WithMockUser
    @DisplayName("returns 403 when caller has none of the allowed access paths")
    void getSummaryById_noAccess_returns403() throws Exception {
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOwnedBy(OWNER_USER_ID)));

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

    @Test
    @WithMockUser
    @DisplayName("TC-E-SUM-009: caregiver reads on_consent summary without consent → 403")
    void getSummaryById_onConsentSummary_caregiverWithoutConsent_returns403()
            throws Exception {
        final Long patientId = 700L;
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOnConsentOwnedBy(OWNER_USER_ID, patientId)));
        grantHistoricalAccess();
        when(caregiverVisibilityService.getStatus(CURRENT_USER_ID, patientId))
                .thenReturn(new CaregiverVisibilityCheck(
                        CaregiverVisibilityStatus.PENDING_REVIEW, false));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isForbidden());
    }

    @Test
    @WithMockUser
    @DisplayName("TC-E-SUM-009: registered caregiver whose service returns canView=true → 200")
    void getSummaryById_onConsentSummary_caregiverStatusRegisteredWithCanView_returns200()
            throws Exception {
        final Long patientId = 700L;
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOnConsentOwnedBy(OWNER_USER_ID, patientId)));
        grantHistoricalAccess();
        when(caregiverVisibilityService.getStatus(CURRENT_USER_ID, patientId))
                .thenReturn(new CaregiverVisibilityCheck(
                        CaregiverVisibilityStatus.PENDING_REVIEW, true));
        when(callSummaryService.getSummaryById(SUMMARY_ID))
                .thenReturn(Optional.of(exampleResponse()));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isOk());
    }

    @Test
    @WithMockUser
    @DisplayName("TC-E-SUM-009: non-caregiver (status=NONE) with durable access bypasses gate → 200")
    void getSummaryById_onConsentSummary_nonCaregiverStatusNone_bypassesGate()
            throws Exception {
        final Long patientId = 700L;
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOnConsentOwnedBy(OWNER_USER_ID, patientId)));
        grantHistoricalAccess();
        when(caregiverVisibilityService.getStatus(CURRENT_USER_ID, patientId))
                .thenReturn(new CaregiverVisibilityCheck(
                        CaregiverVisibilityStatus.NONE, true));
        when(callSummaryService.getSummaryById(SUMMARY_ID))
                .thenReturn(Optional.of(exampleResponse()));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isOk());
    }

    @Test
    @WithMockUser
    @DisplayName("TC-E-SUM-009: admin bypasses on_consent gate → 200 (even with denied consent)")
    void getSummaryById_onConsentSummary_adminBypassesGate() throws Exception {
        caregiverUser.setRole(Role.ADMIN);
        final Long patientId = 700L;
        when(callSummaryService.getSummaryEntityById(SUMMARY_ID))
                .thenReturn(Optional.of(entityOnConsentOwnedBy(OWNER_USER_ID, patientId)));
        when(caregiverVisibilityService.getStatus(CURRENT_USER_ID, patientId))
                .thenReturn(new CaregiverVisibilityCheck(
                        CaregiverVisibilityStatus.REVOKED, false));
        when(callSummaryService.getSummaryById(SUMMARY_ID))
                .thenReturn(Optional.of(exampleResponse()));

        mockMvc.perform(get("/api/v3/summaries/{id}", SUMMARY_ID))
                .andExpect(status().isOk());
    }
}
