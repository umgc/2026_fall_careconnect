package com.careconnect.controller;

import com.careconnect.dto.CaregiverPatientLinkResponse;
import com.careconnect.dto.FamilyMemberLinkResponse;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.util.SecurityUtil;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FamilyMemberService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(LinkManagementController.class)
@DisplayName("LinkManagementController Tests")
class LinkManagementControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private CaregiverPatientLinkService caregiverPatientLinkService;

    @MockitoBean
    private FamilyMemberService familyMemberService;

    @MockitoBean
    private UserRepository userRepository;

    @MockitoBean
    private SecurityUtil securityUtil;

    @MockitoBean
    private AuthorizationService authorizationService;

    private User user(Long id, Role role) {
        final User u = new User();
        u.setId(id);
        u.setRole(role);
        u.setEmail("u" + id + "@test.com");
        return u;
    }

    private CaregiverPatientLinkResponse caregiverLink(Long id, String status, LocalDateTime expiresAt) {
        return new CaregiverPatientLinkResponse(
                id, 2L, "Care Giver", "care@test.com", 1L, "Pat Ient", "pat@test.com",
                status, "TEMPORARY", false, false, LocalDateTime.now().minusDays(1), expiresAt, "note",
                "admin", "ACTIVE".equals(status), expiresAt != null && expiresAt.isBefore(LocalDateTime.now())
        );
    }

    private FamilyMemberLinkResponse familyLink(Long id) {
        return new FamilyMemberLinkResponse(
                id, 3L, "Fam Mem", "family@test.com", 1L, "Pat Ient", "Sibling",
                "ACTIVE", LocalDateTime.now().minusDays(1), "admin"
        );
    }

    @Nested
    @DisplayName("POST /caregiver-patient/temporary")
    class CreateTemporaryCaregiverPatientLink {

        @Test
        @WithMockUser(username = "10")
        @DisplayName("Caregiver can create temporary caregiver-patient link")
        void caregiverCannotCreateTemporaryLinkDirectly() throws Exception {
            // Arrange
            when(userRepository.findById(10L)).thenReturn(Optional.of(user(10L, Role.CAREGIVER)));

            final LinkManagementController.CreateTemporaryLinkRequest body =
                    new LinkManagementController.CreateTemporaryLinkRequest(1L, LocalDateTime.now().plusDays(3), "Temp access");

            // Act + Assert
            mockMvc.perform(post("/v1/api/link-management/caregiver-patient/temporary")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isForbidden());

            // Assert: caregivers must send a connection request the patient accepts
            verify(caregiverPatientLinkService, never()).createLink(any(), any(), any());
        }

        @Test
        @WithMockUser(username = "11")
        @DisplayName("Patient is forbidden from creating caregiver-patient temporary link")
        void patientForbidden() throws Exception {
            // Arrange
            when(userRepository.findById(11L)).thenReturn(Optional.of(user(11L, Role.PATIENT)));

            final LinkManagementController.CreateTemporaryLinkRequest body =
                    new LinkManagementController.CreateTemporaryLinkRequest(2L, LocalDateTime.now().plusDays(2), "Nope");

            // Act + Assert
            mockMvc.perform(post("/v1/api/link-management/caregiver-patient/temporary")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isForbidden());

            // Assert
            verifyNoInteractions(caregiverPatientLinkService);
        }
    }

    @Nested
    @DisplayName("POST /family-member/temporary")
    class CreateTemporaryFamilyMemberLink {

        @Test
        @WithMockUser(username = "12")
        @DisplayName("Patient can create temporary family member link")
        void patientCreatesTemporaryFamilyLink() throws Exception {
            // Arrange
            when(userRepository.findById(12L)).thenReturn(Optional.of(user(12L, Role.PATIENT)));
            when(familyMemberService.createTemporaryLink(eq(3L), eq(1L), eq("Sibling"), any(), eq("Visit help"), eq(12L)))
                    .thenReturn(familyLink(200L));

            final LinkManagementController.CreateTemporaryFamilyLinkRequest body =
                    new LinkManagementController.CreateTemporaryFamilyLinkRequest(
                            3L, 1L, "Sibling", LocalDateTime.now().plusDays(7), "Visit help");

            // Act + Assert
            mockMvc.perform(post("/v1/api/link-management/family-member/temporary")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.id").value(200));

            // Assert
            verify(familyMemberService).createTemporaryLink(eq(3L), eq(1L), eq("Sibling"), any(), eq("Visit help"), eq(12L));
        }

        @Test
        @WithMockUser(username = "13")
        @DisplayName("Family member is forbidden from creating temporary family member links")
        void familyMemberForbidden() throws Exception {
            // Arrange
            when(userRepository.findById(13L)).thenReturn(Optional.of(user(13L, Role.FAMILY_MEMBER)));

            final LinkManagementController.CreateTemporaryFamilyLinkRequest body =
                    new LinkManagementController.CreateTemporaryFamilyLinkRequest(
                            3L, 1L, "Sibling", LocalDateTime.now().plusDays(7), "Nope");

            // Act + Assert
            mockMvc.perform(post("/v1/api/link-management/family-member/temporary")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isForbidden());

            // Assert
            verifyNoInteractions(familyMemberService);
        }
    }

    @Nested
    @DisplayName("POST /extend-expiration/{linkId}")
    class ExtendLinkExpiration {

        @Test
        @WithMockUser(username = "14")
        @DisplayName("Admin can extend caregiver-patient link expiration")
        void adminExtendsCaregiverPatientLink() throws Exception {
            // Arrange
            when(userRepository.findById(14L)).thenReturn(Optional.of(user(14L, Role.ADMIN)));
            when(caregiverPatientLinkService.updateLink(eq(500L), any(), eq(14L)))
                    .thenReturn(caregiverLink(500L, "ACTIVE", LocalDateTime.now().plusDays(10)));

            final LinkManagementController.ExtendExpirationRequest body =
                    new LinkManagementController.ExtendExpirationRequest("CAREGIVER_PATIENT", LocalDateTime.now().plusDays(10));

            // Act + Assert
            mockMvc.perform(post("/v1/api/link-management/extend-expiration/500")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.success").value(true));

            // Assert
            verify(caregiverPatientLinkService).updateLink(eq(500L), any(), eq(14L));
        }

        @Test
        @WithMockUser(username = "15")
        @DisplayName("Invalid link type returns 400")
        void invalidLinkTypeReturns400() throws Exception {
            // Arrange
            when(userRepository.findById(15L)).thenReturn(Optional.of(user(15L, Role.ADMIN)));

            final LinkManagementController.ExtendExpirationRequest body =
                    new LinkManagementController.ExtendExpirationRequest("UNKNOWN", LocalDateTime.now().plusDays(1));

            // Act + Assert
            mockMvc.perform(post("/v1/api/link-management/extend-expiration/501")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Invalid link type"));
        }

        @Test
        @WithMockUser(username = "151")
        @DisplayName("Caregiver can extend family-member link expiration")
        void caregiverExtendsFamilyMemberLink() throws Exception {
            // Arrange
            when(userRepository.findById(151L)).thenReturn(Optional.of(user(151L, Role.CAREGIVER)));
            when(familyMemberService.updateFamilyMemberLink(eq(901L), any(), eq(151L)))
                    .thenReturn(familyLink(901L));

            final LinkManagementController.ExtendExpirationRequest body =
                    new LinkManagementController.ExtendExpirationRequest("FAMILY_MEMBER", LocalDateTime.now().plusDays(4));

            // Act + Assert
            mockMvc.perform(post("/v1/api/link-management/extend-expiration/901")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.success").value(true));

            // Assert
            verify(familyMemberService).updateFamilyMemberLink(eq(901L), any(), eq(151L));
        }

        @Test
        @WithMockUser(username = "16")
        @DisplayName("Non-admin/caregiver cannot extend expiration")
        void patientForbidden() throws Exception {
            // Arrange
            when(userRepository.findById(16L)).thenReturn(Optional.of(user(16L, Role.PATIENT)));

            final LinkManagementController.ExtendExpirationRequest body =
                    new LinkManagementController.ExtendExpirationRequest("CAREGIVER_PATIENT", LocalDateTime.now().plusDays(2));

            // Act + Assert
            mockMvc.perform(post("/v1/api/link-management/extend-expiration/502")
                            .with(csrf())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(objectMapper.writeValueAsString(body)))
                    .andExpect(status().isForbidden());

            // Assert
            verifyNoInteractions(caregiverPatientLinkService, familyMemberService);
        }
    }

    @Nested
    @DisplayName("GET /expiring-soon")
    class GetExpiringSoonLinks {

        @Test
        @WithMockUser(username = "17")
        @DisplayName("Admin gets filtered expiring links")
        void adminGetsFilteredLinks() throws Exception {
            // Arrange
            when(userRepository.findById(17L)).thenReturn(Optional.of(user(17L, Role.ADMIN)));
            when(caregiverPatientLinkService.getAllLinks()).thenReturn(List.of(
                    caregiverLink(1L, "ACTIVE", LocalDateTime.now().plusHours(2)),
                    caregiverLink(2L, "SUSPENDED", LocalDateTime.now().plusHours(3)),
                    caregiverLink(3L, "ACTIVE", LocalDateTime.now().plusDays(3))
            ));

            // Act + Assert
            mockMvc.perform(get("/v1/api/link-management/expiring-soon"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.totalExpiring").value(1));

            // Assert
            verify(caregiverPatientLinkService).getAllLinks();
        }

        @Test
        @WithMockUser(username = "18")
        @DisplayName("Family member cannot access expiring-soon endpoint")
        void familyMemberForbidden() throws Exception {
            // Arrange
            when(userRepository.findById(18L)).thenReturn(Optional.of(user(18L, Role.FAMILY_MEMBER)));

            // Act + Assert
            mockMvc.perform(get("/v1/api/link-management/expiring-soon"))
                    .andExpect(status().isForbidden());

            // Assert
            verifyNoInteractions(caregiverPatientLinkService);
        }

        @Test
        @WithMockUser(username = "181")
        @DisplayName("Caregiver gets their own expiring links")
        void caregiverGetsOwnExpiringLinks() throws Exception {
            // Arrange
            when(userRepository.findById(181L)).thenReturn(Optional.of(user(181L, Role.CAREGIVER)));
            when(caregiverPatientLinkService.getPatientsByCaregiver(181L)).thenReturn(List.of(
                    caregiverLink(11L, "ACTIVE", LocalDateTime.now().plusHours(5)),
                    caregiverLink(12L, "ACTIVE", LocalDateTime.now().plusDays(2)),
                    caregiverLink(13L, "SUSPENDED", LocalDateTime.now().plusHours(2))
            ));

            // Act + Assert
            mockMvc.perform(get("/v1/api/link-management/expiring-soon"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.totalExpiring").value(1));

            // Assert
            verify(caregiverPatientLinkService).getPatientsByCaregiver(181L);
        }
    }

    @Nested
    @DisplayName("POST /cleanup-expired")
    class CleanupExpiredLinks {

        @Test
        @WithMockUser(username = "19")
        @DisplayName("Admin can cleanup expired links")
        void adminCanCleanup() throws Exception {
            // Arrange
            when(userRepository.findById(19L)).thenReturn(Optional.of(user(19L, Role.ADMIN)));

            // Act + Assert
            mockMvc.perform(post("/v1/api/link-management/cleanup-expired").with(csrf()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.success").value(true));

            // Assert
            verify(caregiverPatientLinkService).cleanupExpiredLinks();
            verify(familyMemberService).cleanupExpiredFamilyMemberLinks();
        }

        @Test
        @WithMockUser(username = "20")
        @DisplayName("Service exception during cleanup returns 400")
        void cleanupExceptionReturns400() throws Exception {
            // Arrange
            when(userRepository.findById(20L)).thenReturn(Optional.of(user(20L, Role.ADMIN)));
            doThrow(new RuntimeException("cleanup failed")).when(caregiverPatientLinkService).cleanupExpiredLinks();

            // Act + Assert
            mockMvc.perform(post("/v1/api/link-management/cleanup-expired").with(csrf()))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("cleanup failed"));
        }

        @Test
        @WithMockUser(username = "201")
        @DisplayName("Non-admin cannot cleanup expired links")
        void nonAdminForbidden() throws Exception {
            // Arrange
            when(userRepository.findById(201L)).thenReturn(Optional.of(user(201L, Role.CAREGIVER)));

            // Act + Assert
            mockMvc.perform(post("/v1/api/link-management/cleanup-expired").with(csrf()))
                    .andExpect(status().isForbidden());

            // Assert
            verifyNoInteractions(caregiverPatientLinkService, familyMemberService);
        }
    }

    @Nested
    @DisplayName("GET /summary")
    class GetSummary {

        @Test
        @WithMockUser(username = "21")
        @DisplayName("Caregiver summary includes caregiver-patient links")
        void caregiverSummary() throws Exception {
            // Arrange
            when(userRepository.findById(21L)).thenReturn(Optional.of(user(21L, Role.CAREGIVER)));
            when(caregiverPatientLinkService.getPatientsByCaregiver(21L))
                    .thenReturn(List.of(caregiverLink(701L, "ACTIVE", LocalDateTime.now().plusDays(1))));

            // Act + Assert
            mockMvc.perform(get("/v1/api/link-management/summary"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.userId").value(21))
                    .andExpect(jsonPath("$.userRole").value("CAREGIVER"))
                    .andExpect(jsonPath("$.caregiverPatientLinks[0].id").value(701))
                    .andExpect(jsonPath("$.familyMemberLinks").isArray());
        }

        @Test
        @WithMockUser(username = "22")
        @DisplayName("Patient summary includes caregivers and family members")
        void patientSummary() throws Exception {
            // Arrange
            when(userRepository.findById(22L)).thenReturn(Optional.of(user(22L, Role.PATIENT)));
            when(caregiverPatientLinkService.getCaregiversByPatient(22L))
                    .thenReturn(List.of(caregiverLink(702L, "ACTIVE", LocalDateTime.now().plusDays(1))));
            when(familyMemberService.getFamilyMembersByPatient(22L))
                    .thenReturn(List.of(familyLink(801L)));

            // Act + Assert
            mockMvc.perform(get("/v1/api/link-management/summary"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.userRole").value("PATIENT"))
                    .andExpect(jsonPath("$.caregiverPatientLinks[0].id").value(702))
                    .andExpect(jsonPath("$.familyMemberLinks[0].id").value(801));
        }

        @Test
        @WithMockUser(username = "23")
        @DisplayName("Admin summary includes all caregiver links and empty family links")
        void adminSummary() throws Exception {
            // Arrange
            when(userRepository.findById(23L)).thenReturn(Optional.of(user(23L, Role.ADMIN)));
            when(caregiverPatientLinkService.getAllLinks())
                    .thenReturn(List.of(caregiverLink(703L, "ACTIVE", LocalDateTime.now().plusDays(1))));

            // Act + Assert
            mockMvc.perform(get("/v1/api/link-management/summary"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.userRole").value("ADMIN"))
                    .andExpect(jsonPath("$.caregiverPatientLinks[0].id").value(703))
                    .andExpect(jsonPath("$.familyMemberLinks").isArray());
        }

        @Test
        @WithMockUser(username = "231")
        @DisplayName("Family member summary includes patient links and no caregiver links")
        void familyMemberSummary() throws Exception {
            // Arrange
            when(userRepository.findById(231L)).thenReturn(Optional.of(user(231L, Role.FAMILY_MEMBER)));
            when(familyMemberService.getPatientsByFamilyMember(231L))
                    .thenReturn(List.of(familyLink(901L)));

            // Act + Assert
            mockMvc.perform(get("/v1/api/link-management/summary"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.userRole").value("FAMILY_MEMBER"))
                    .andExpect(jsonPath("$.caregiverPatientLinks").isArray())
                    .andExpect(jsonPath("$.familyMemberLinks[0].id").value(901));
        }
    }

    @Nested
    @DisplayName("Current user lookup failures")
    class CurrentUserLookupFailures {

        @Test
        @WithMockUser(username = "999")
        @DisplayName("Unknown user id returns 500 via global exception handler")
        void unknownUserIdReturns500() throws Exception {
            // Arrange
            when(userRepository.findById(999L)).thenReturn(Optional.empty());

            // Act + Assert
            mockMvc.perform(get("/v1/api/link-management/summary"))
                    .andExpect(status().isInternalServerError())
                    .andExpect(jsonPath("$.error").value("An unexpected error occurred"));

            // Assert
            verifyNoInteractions(caregiverPatientLinkService, familyMemberService);
        }

        @Test
        @WithMockUser(username = "not-a-number")
        @DisplayName("Non-numeric principal returns 500 via global exception handler")
        void nonNumericPrincipalReturns500() throws Exception {
            // Act + Assert
            mockMvc.perform(get("/v1/api/link-management/summary"))
                    .andExpect(status().isInternalServerError())
                    .andExpect(jsonPath("$.error").value("An unexpected error occurred"));

            // Assert
            verifyNoInteractions(userRepository, caregiverPatientLinkService, familyMemberService);
        }
    }
}
