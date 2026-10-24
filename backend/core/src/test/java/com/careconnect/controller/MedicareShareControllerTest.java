package com.careconnect.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.careconnect.dto.MedicareSharedWithMeResponse;
import com.careconnect.exception.AppException;
import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.ConsentGrant;
import com.careconnect.model.User;
import com.careconnect.security.Role;
import com.careconnect.service.consent.MedicareShareService;
import com.careconnect.util.SecurityUtil;

import java.time.Instant;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

@ExtendWith(MockitoExtension.class)
@DisplayName("MedicareShareController")
class MedicareShareControllerTest {

    private static final String URL = "/api/v3/consent/medicare-share";

    @Mock
    private MedicareShareService medicareShareService;
    @Mock
    private SecurityUtil securityUtil;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(
                        new MedicareShareController(medicareShareService, securityUtil))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
    }

    private static User user(final long id, final Role role, final String email) {
        final User user = new User();
        user.setId(id);
        user.setRole(role);
        user.setEmail(email);
        user.setName("Name " + id);
        return user;
    }

    private static ConsentGrant shareGrant() {
        return ConsentGrant.builder()
                .id(99L).patientUserId(10L).granteeUserId(30L)
                .granteeRole(ConsentGrant.GRANTEE_ROLE_SHARE_RECIPIENT)
                .scope(ConsentGrant.SCOPE_MEDICARE_VIEW).status(ConsentGrant.STATUS_ACTIVE)
                .grantedAt(Instant.parse("2026-10-20T12:00:00Z"))
                .expiresAt(Instant.parse("2027-01-18T12:00:00Z"))
                .build();
    }

    @Test
    @DisplayName("TC-CONSENT-059 CR-2: POST medicare-share by the patient is 201 with the share and emailSent")
    void share_createdForPatient() throws Exception {
        final User patient = user(10L, Role.PATIENT, "patient@example.com");
        final User recipient = user(30L, Role.FAMILY_MEMBER, "friend@example.com");
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);
        when(medicareShareService.shareMedicareRecords(patient, "friend@example.com"))
                .thenReturn(new MedicareShareService.ShareResult(shareGrant(), recipient, true));

        mockMvc.perform(post(URL)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"recipientEmail\":\"friend@example.com\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(99))
                .andExpect(jsonPath("$.recipientUserId").value(30))
                .andExpect(jsonPath("$.recipientEmail").value("friend@example.com"))
                .andExpect(jsonPath("$.scope").value("MEDICARE_VIEW"))
                .andExpect(jsonPath("$.emailSent").value(true));
    }

    @Test
    @DisplayName("TC-CONSENT-062 CR-2: POST medicare-share by a non-patient is 403 and shares nothing")
    void share_forbiddenForNonPatient() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, Role.CAREGIVER, "cg@example.com"));

        mockMvc.perform(post(URL)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"recipientEmail\":\"friend@example.com\"}"))
                .andExpect(status().isForbidden());

        verify(medicareShareService, never()).shareMedicareRecords(any(), any());
    }

    @Test
    @DisplayName("TC-CONSENT-063 CR-2: POST medicare-share with no signed-in user is 401")
    void share_unauthenticated() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);

        mockMvc.perform(post(URL)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"recipientEmail\":\"friend@example.com\"}"))
                .andExpect(status().isUnauthorized());

        verify(medicareShareService, never()).shareMedicareRecords(any(), any());
    }

    @Test
    @DisplayName("TC-CONSENT-064 CR-2: the service's 404 for an unregistered email reaches the client")
    void share_unknownEmailPassesThrough404() throws Exception {
        final User patient = user(10L, Role.PATIENT, "patient@example.com");
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);
        when(medicareShareService.shareMedicareRecords(eq(patient), any()))
                .thenThrow(new AppException(HttpStatus.NOT_FOUND, "No registered CareConnect user has that email"));

        mockMvc.perform(post(URL)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"recipientEmail\":\"nobody@example.com\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("TC-CONSENT-065 CR-2: GET medicare-share lists the patient's active shares")
    void list_returnsShares() throws Exception {
        final User patient = user(10L, Role.PATIENT, "patient@example.com");
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);
        when(medicareShareService.listActiveShares(10L)).thenReturn(List.of(
                new MedicareShareService.ShareResult(
                        shareGrant(), user(30L, Role.FAMILY_MEMBER, "friend@example.com"), false)));

        mockMvc.perform(get(URL))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].recipientEmail").value("friend@example.com"))
                .andExpect(jsonPath("$[0].expiresAt").exists());
    }

    @Test
    @DisplayName("TC-CONSENT-072 CR-2: DELETE medicare-share/{id} by the patient returns the revoked share")
    void revoke_returnsRevokedShare() throws Exception {
        final User patient = user(10L, Role.PATIENT, "patient@example.com");
        final ConsentGrant revoked = shareGrant();
        revoked.setStatus(ConsentGrant.STATUS_REVOKED);
        revoked.setRevokedAt(Instant.parse("2026-10-21T00:00:00Z"));
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);
        when(medicareShareService.revokeShare(10L, 99L)).thenReturn(
                new MedicareShareService.ShareResult(
                        revoked, user(30L, Role.FAMILY_MEMBER, "friend@example.com"), false));

        mockMvc.perform(delete(URL + "/99"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(99))
                .andExpect(jsonPath("$.status").value("REVOKED"));
    }

    @Test
    @DisplayName("TC-CONSENT-073 CR-2: DELETE medicare-share/{id} by a non-patient is 403 and revokes nothing")
    void revoke_forbiddenForNonPatient() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, Role.CAREGIVER, "cg@example.com"));

        mockMvc.perform(delete(URL + "/99")).andExpect(status().isForbidden());

        verify(medicareShareService, never()).revokeShare(any(), any());
    }

    @Test
    @DisplayName("TC-CONSENT-080 CR-2: GET medicare-share/received works for any signed-in role and lists the caller's shares")
    void received_listsSharesForAnyRole() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(30L, Role.FAMILY_MEMBER, "friend@example.com"));
        when(medicareShareService.listSharedWithMe(30L)).thenReturn(List.of(
                new MedicareSharedWithMeResponse(99L, 10L, 500L, "Pat Patient",
                        Instant.parse("2026-10-20T12:00:00Z"), Instant.parse("2027-01-18T12:00:00Z"))));

        mockMvc.perform(get(URL + "/received"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].shareId").value(99))
                .andExpect(jsonPath("$[0].patientId").value(500))
                .andExpect(jsonPath("$[0].patientName").value("Pat Patient"));
    }

    @Test
    @DisplayName("TC-CONSENT-081 CR-2: GET medicare-share/received with no signed-in user is 401")
    void received_unauthenticated() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);

        mockMvc.perform(get(URL + "/received")).andExpect(status().isUnauthorized());

        verify(medicareShareService, never()).listSharedWithMe(any());
    }

    @Test
    @DisplayName("TC-CONSENT-066 CR-2: GET medicare-share by a non-patient is 403")
    void list_forbiddenForNonPatient() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(20L, Role.CAREGIVER, "cg@example.com"));

        mockMvc.perform(get(URL)).andExpect(status().isForbidden());

        verify(medicareShareService, never()).listActiveShares(any());
    }
}
