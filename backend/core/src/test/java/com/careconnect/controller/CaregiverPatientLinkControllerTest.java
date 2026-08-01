package com.careconnect.controller;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.util.SecurityUtil;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Optional;

import static org.mockito.Mockito.when;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(CaregiverPatientLinkController.class)
@AutoConfigureMockMvc(addFilters = false)
class CaregiverPatientLinkControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private CaregiverPatientLinkService linkService;

    @MockitoBean
    private UserRepository userRepository;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private AuthorizationService authorizationService;

    @AfterEach
    void tearDown() throws Exception {
        SecurityContextHolder.clearContext();
    }

    // ============================================================
    // HELPER METHODS
    // WHY: Simulates authenticated CareConnect user in RBAC tests
    // ============================================================
    private User buildUser(Long id, Role role, String email) {
        final User u = new User();
        u.setId(id);
        u.setRole(role);
        u.setEmail(email);
        return u;
    }

    private void mockSecurityContext(String email, User user) {
        final Authentication auth = Mockito.mock(Authentication.class);
        when(auth.getName()).thenReturn(email);
        final SecurityContext secCtx = Mockito.mock(SecurityContext.class);
        when(secCtx.getAuthentication()).thenReturn(auth);
        SecurityContextHolder.setContext(secCtx);
        when(userRepository.findByEmail(email)).thenReturn(Optional.of(user));
    }

    // ============================================================
    // TEST: Create Link - Admin Allowed
    // WHY: Verifies ADMIN bypasses caregiver ownership check
    // ============================================================
    @Test
    void adminShouldCreateLinkSuccessfully() throws Exception {

        final User admin = buildUser(1L, Role.ADMIN, "admin@test.com");
        mockSecurityContext("admin@test.com", admin);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/caregivers/2/patients")
                        .contentType("application/json")
                        .content("{}"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Create Link - Caregiver Creates Link For Themselves
    // WHY: Caregiver may link patients to their own account
    // ============================================================
    @Test
    void caregiverCanCreateLinkForSelf() throws Exception {

        final User caregiver = buildUser(5L, Role.CAREGIVER, "cg@test.com");
        mockSecurityContext("cg@test.com", caregiver);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/caregivers/5/patients")
                        .contentType("application/json")
                        .content("{}"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Create Link - Caregiver Unauthorized
    // WHY: Prevent caregiver linking patients for other caregivers
    // ============================================================
    @Test
    void caregiverShouldNotCreateLinkForOtherCaregiver() throws Exception {

        final User caregiver = buildUser(5L, Role.CAREGIVER, "cg@test.com");
        mockSecurityContext("cg@test.com", caregiver);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/caregivers/2/patients")
                        .contentType("application/json")
                        .content("{}"))
                .andExpect(status().isForbidden());
    }

    // ============================================================
    // TEST: Update Link - Admin Allowed
    // WHY: Verifies admin can successfully update any link
    // ============================================================
    @Test
    void adminCanUpdateLink() throws Exception {

        final User admin = buildUser(1L, Role.ADMIN, "admin@test.com");
        mockSecurityContext("admin@test.com", admin);

        mockMvc.perform(put("/v1/api/caregiver-patient-links/1")
                        .contentType("application/json")
                        .content("{}"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Update Link - Non Admin Forbidden
    // WHY: Only admins may modify links
    // ============================================================
    @Test
    void caregiverCannotUpdateLink() throws Exception {

        final User caregiver = buildUser(2L, Role.CAREGIVER, "cg@test.com");
        mockSecurityContext("cg@test.com", caregiver);

        mockMvc.perform(put("/v1/api/caregiver-patient-links/1")
                        .contentType("application/json")
                        .content("{}"))
                .andExpect(status().isForbidden());
    }

    // ============================================================
    // TEST: Suspend Link - Allowed for Admin
    // WHY: Admins are also permitted to suspend links
    // ============================================================
    @Test
    void adminCanSuspendLink() throws Exception {

        final User admin = buildUser(1L, Role.ADMIN, "admin@test.com");
        mockSecurityContext("admin@test.com", admin);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/1/suspend"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Suspend Link - Allowed for Caregiver
    // WHY: Caregivers are permitted to suspend links
    // ============================================================
    @Test
    void caregiverCanSuspendLink() throws Exception {

        final User caregiver = buildUser(2L, Role.CAREGIVER, "cg@test.com");
        mockSecurityContext("cg@test.com", caregiver);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/1/suspend"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Suspend Link - Patient Forbidden
    // WHY: Patients cannot suspend caregiver-patient links
    // ============================================================
    @Test
    void patientCannotSuspendLink() throws Exception {

        final User patient = buildUser(3L, Role.PATIENT, "patient@test.com");
        mockSecurityContext("patient@test.com", patient);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/1/suspend"))
                .andExpect(status().isForbidden());
    }

    // ============================================================
    // TEST: Reactivate Link - Admin Allowed
    // WHY: Admins may reactivate suspended links
    // ============================================================
    @Test
    void adminCanReactivateLink() throws Exception {

        final User admin = buildUser(1L, Role.ADMIN, "admin@test.com");
        mockSecurityContext("admin@test.com", admin);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/1/reactivate"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Reactivate Link - Caregiver Allowed
    // WHY: Caregivers may reactivate their own suspended links
    // ============================================================
    @Test
    void caregiverCanReactivateLink() throws Exception {

        final User caregiver = buildUser(2L, Role.CAREGIVER, "cg@test.com");
        mockSecurityContext("cg@test.com", caregiver);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/1/reactivate"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Reactivate Link - Patient Forbidden
    // WHY: Patients cannot reactivate links
    // ============================================================
    @Test
    void patientCannotReactivateLink() throws Exception {

        final User patient = buildUser(3L, Role.PATIENT, "patient@test.com");
        mockSecurityContext("patient@test.com", patient);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/1/reactivate"))
                .andExpect(status().isForbidden());
    }

    // ============================================================
    // TEST: Revoke Link - Admin Allowed
    // WHY: Verifies admin can permanently revoke a link (204)
    // ============================================================
    @Test
    void adminCanRevokeLink() throws Exception {

        final User admin = buildUser(1L, Role.ADMIN, "admin@test.com");
        mockSecurityContext("admin@test.com", admin);

        mockMvc.perform(delete("/v1/api/caregiver-patient-links/1"))
                .andExpect(status().isNoContent());
    }

    // ============================================================
    // TEST: Revoke Link - Non Admin Forbidden
    // WHY: Permanent deletion must be admin-only
    // ============================================================
    @Test
    void caregiverCannotRevokeLink() throws Exception {

        final User caregiver = buildUser(2L, Role.CAREGIVER, "cg@test.com");
        mockSecurityContext("cg@test.com", caregiver);

        mockMvc.perform(delete("/v1/api/caregiver-patient-links/1"))
                .andExpect(status().isForbidden());
    }

    // ============================================================
    // TEST: Get Patients By Caregiver - Owner Allowed
    // WHY: Caregiver may only see own patients
    // ============================================================
    @Test
    void caregiverCanViewOwnPatients() throws Exception {

        final User caregiver = buildUser(2L, Role.CAREGIVER, "cg@test.com");
        mockSecurityContext("cg@test.com", caregiver);

        when(linkService.getPatientsByCaregiver(2L))
                .thenReturn(List.of());

        mockMvc.perform(get("/v1/api/caregiver-patient-links/caregivers/2/patients"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Get Patients By Caregiver - Admin Allowed For Any
    // WHY: Admins can view patients for any caregiver
    // ============================================================
    @Test
    void adminCanViewAnyCaregiversPatients() throws Exception {

        final User admin = buildUser(1L, Role.ADMIN, "admin@test.com");
        mockSecurityContext("admin@test.com", admin);

        when(linkService.getPatientsByCaregiver(99L))
                .thenReturn(List.of());

        mockMvc.perform(get("/v1/api/caregiver-patient-links/caregivers/99/patients"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Get Patients By Caregiver - Caregiver Denied For Other
    // WHY: Caregiver cannot view another caregiver's patients
    // ============================================================
    @Test
    void caregiverCannotViewOthersCaregiverPatients() throws Exception {

        final User caregiver = buildUser(2L, Role.CAREGIVER, "cg@test.com");
        mockSecurityContext("cg@test.com", caregiver);

        mockMvc.perform(get("/v1/api/caregiver-patient-links/caregivers/99/patients"))
                .andExpect(status().isForbidden());
    }

    // ============================================================
    // TEST: Get Caregivers By Patient - Patient Views Own
    // WHY: Patient may view their own assigned caregivers
    // ============================================================
    @Test
    void patientCanViewOwnCaregivers() throws Exception {

        final User patient = buildUser(3L, Role.PATIENT, "patient@test.com");
        mockSecurityContext("patient@test.com", patient);

        when(linkService.getCaregiversByPatient(3L))
                .thenReturn(List.of());

        mockMvc.perform(get("/v1/api/caregiver-patient-links/patients/3/caregivers"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Get Caregivers By Patient - Patient Denied For Other
    // WHY: Patient cannot view another patient's caregivers
    // ============================================================
    @Test
    void patientCannotViewOthersCaregivers() throws Exception {

        final User patient = buildUser(3L, Role.PATIENT, "patient@test.com");
        mockSecurityContext("patient@test.com", patient);

        mockMvc.perform(get("/v1/api/caregiver-patient-links/patients/99/caregivers"))
                .andExpect(status().isForbidden());
    }

    // ============================================================
    // TEST: Get Caregivers By Patient - Admin Allowed For Any
    // WHY: Admin can view caregivers for any patient
    // ============================================================
    @Test
    void adminCanViewAnyPatientCaregivers() throws Exception {

        final User admin = buildUser(1L, Role.ADMIN, "admin@test.com");
        mockSecurityContext("admin@test.com", admin);

        when(linkService.getCaregiversByPatient(99L))
                .thenReturn(List.of());

        mockMvc.perform(get("/v1/api/caregiver-patient-links/patients/99/caregivers"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Has Access To Patient - No Auth Required
    // WHY: Access check endpoint has no role restriction
    // ============================================================
    @Test
    void hasAccessToPatientReturnsResult() throws Exception {

        final User admin = buildUser(1L, Role.ADMIN, "admin@test.com");
        mockSecurityContext("admin@test.com", admin);

        when(linkService.hasAccessToPatient(1L, 2L)).thenReturn(true);

        mockMvc.perform(get("/v1/api/caregiver-patient-links/caregivers/1/patients/2/access"))
                .andExpect(status().isOk())
                .andExpect(content().string("true"));
    }

    // ============================================================
    // TEST: Get All Links - Admin Only
    // WHY: Verifies system-wide link visibility is restricted
    // ============================================================
    @Test
    void adminCanViewAllLinks() throws Exception {

        final User admin = buildUser(1L, Role.ADMIN, "admin@test.com");
        mockSecurityContext("admin@test.com", admin);

        when(linkService.getAllLinks()).thenReturn(List.of());

        mockMvc.perform(get("/v1/api/caregiver-patient-links"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Get All Links - Non-Admin Forbidden
    // WHY: Caregivers cannot see system-wide link data
    // ============================================================
    @Test
    void caregiverCannotViewAllLinks() throws Exception {

        final User caregiver = buildUser(2L, Role.CAREGIVER, "cg@test.com");
        mockSecurityContext("cg@test.com", caregiver);

        mockMvc.perform(get("/v1/api/caregiver-patient-links"))
                .andExpect(status().isForbidden());
    }

    // ============================================================
    // TEST: Cleanup Expired Links - Admin Allowed
    // WHY: Admin can trigger cleanup of expired links
    // ============================================================
    @Test
    void adminCanCleanupLinks() throws Exception {

        final User admin = buildUser(1L, Role.ADMIN, "admin@test.com");
        mockSecurityContext("admin@test.com", admin);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/cleanup-expired"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Cleanup Expired Links - Non Admin Forbidden
    // WHY: Background maintenance must be restricted
    // ============================================================
    @Test
    void caregiverCannotCleanupLinks() throws Exception {

        final User caregiver = buildUser(2L, Role.CAREGIVER, "cg@test.com");
        mockSecurityContext("cg@test.com", caregiver);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/cleanup-expired"))
                .andExpect(status().isForbidden());
    }
    // ============================================================
    // TEST: Feature Toggle - Video Calls
    // WHY: Ensures caregivers/admins can toggle patient video access
    // ============================================================
    @Test
    void caregiverCanToggleVideoCalls() throws Exception {
        final User caregiver = buildUser(2L, Role.CAREGIVER, "cg@test.com");
        mockSecurityContext("cg@test.com", caregiver);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/1/patient-video-calls")
                        .contentType("application/json")
                        .content("{\"enabled\": true}"))
                .andExpect(status().isOk());
    }

    // ============================================================
    // TEST: Feature Toggle - Messaging
    // WHY: Ensures caregivers/admins can toggle patient messaging access
    // ============================================================
    @Test
    void caregiverCanToggleMessaging() throws Exception {
        final User caregiver = buildUser(2L, Role.CAREGIVER, "cg@test.com");
        mockSecurityContext("cg@test.com", caregiver);

        mockMvc.perform(post("/v1/api/caregiver-patient-links/1/patient-messaging")
                        .contentType("application/json")
                        .content("{\"enabled\": false}"))
                .andExpect(status().isOk());
    }
}