package com.careconnect.service;

import com.careconnect.dto.CaregiverPatientLinkResponse;
import com.careconnect.dto.CreateLinkRequest;
import com.careconnect.dto.UpdateLinkRequest;
import com.careconnect.exception.AppException;
import com.careconnect.model.Caregiver;
import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.CaregiverPatientLink.LinkStatus;
import com.careconnect.model.CaregiverPatientLink.LinkType;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.http.HttpStatus;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Extended unit tests for CaregiverPatientLinkService covering createLink,
 * updateLink, suspendLink, reactivateLink, revokeLink, getPatientsByCaregiver,
 * getCaregiversByPatient, setPatientVideoCallsEnabled, getAllLinks,
 * cleanupExpiredLinks, createPermanentLink, hasActiveLink.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("CaregiverPatientLinkService Extended Tests")
class CaregiverPatientLinkServiceExtendedTest {

    @Mock
    private CaregiverPatientLinkRepository linkRepo;
    @Mock
    private UserRepository userRepository;
    @Mock
    private PatientRepository patientRepository;
    @Mock
    private CaregiverRepository caregiverRepository;

    @InjectMocks
    private CaregiverPatientLinkService service;

    private User caregiverUser;
    private User patientUser;
    private User adminUser;
    private CaregiverPatientLink activeLink;

    @BeforeEach
    void setUp() {
        caregiverUser = buildUser(1L, "caregiver@test.com", Role.CAREGIVER);
        patientUser = buildUser(2L, "patient@test.com", Role.PATIENT);
        adminUser = buildUser(3L, "admin@test.com", Role.ADMIN);

        activeLink = buildLink(10L, caregiverUser, patientUser, LinkStatus.ACTIVE, null);

        // Default name lookups (no Patient/Caregiver profile → fall back to email)
        when(patientRepository.findByUser(any())).thenReturn(Optional.empty());
        when(caregiverRepository.findByUser(any())).thenReturn(Optional.empty());
    }

    // ──────────────────────────────────────────────────────────────────
    //  createLink
    // ──────────────────────────────────────────────────────────────────

    private User buildUser(Long id, String email, Role role) {
        User u = new User();
        u.setId(id);
        u.setEmail(email);
        u.setRole(role);
        u.setName(role.name().toLowerCase() + "-" + id);
        return u;
    }

    // ──────────────────────────────────────────────────────────────────
    //  updateLink
    // ──────────────────────────────────────────────────────────────────

    private CaregiverPatientLink buildLink(Long id, User caregiver, User patient,
                                           LinkStatus status, LocalDateTime expiresAt) {
        CaregiverPatientLink link = new CaregiverPatientLink();
        link.setId(id);
        link.setCaregiverUser(caregiver);
        link.setPatientUser(patient);
        link.setCreatedBy(caregiver);
        link.setLinkType(LinkType.PERMANENT);
        link.setStatus(status);
        link.setExpiresAt(expiresAt);
        return link;
    }

    // ──────────────────────────────────────────────────────────────────
    //  suspendLink / reactivateLink / revokeLink
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("createLink")
    class CreateLinkTests {

        @Test
        @DisplayName("creates link successfully when no duplicate exists")
        void createLink_noDuplicate_savesAndReturns() {
            when(userRepository.findById(1L)).thenReturn(Optional.of(caregiverUser));
            when(userRepository.findById(2L)).thenReturn(Optional.of(patientUser));
            when(userRepository.findById(99L)).thenReturn(Optional.of(adminUser)); // creator
            when(linkRepo.existsByCaregiverUserAndPatientUserAndStatus(
                    caregiverUser, patientUser, LinkStatus.ACTIVE)).thenReturn(false);
            when(linkRepo.save(any(CaregiverPatientLink.class))).thenAnswer(inv -> {
                CaregiverPatientLink l = inv.getArgument(0);
                l.setId(10L);
                return l;
            });

            CreateLinkRequest req = new CreateLinkRequest(2L, "PERMANENT", null, "test notes");
            CaregiverPatientLinkResponse response = service.createLink(1L, req, 99L);

            assertThat(response).isNotNull();
            verify(linkRepo).save(any(CaregiverPatientLink.class));
        }

        @Test
        @DisplayName("throws CONFLICT when active link already exists")
        void createLink_duplicateActive_throwsConflict() {
            when(userRepository.findById(1L)).thenReturn(Optional.of(caregiverUser));
            when(userRepository.findById(2L)).thenReturn(Optional.of(patientUser));
            when(userRepository.findById(99L)).thenReturn(Optional.of(adminUser));
            when(linkRepo.existsByCaregiverUserAndPatientUserAndStatus(
                    caregiverUser, patientUser, LinkStatus.ACTIVE)).thenReturn(true);

            CreateLinkRequest req = new CreateLinkRequest(2L, "PERMANENT", null, null);

            assertThatThrownBy(() -> service.createLink(1L, req, 99L))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("Active link already exists");
        }

        @Test
        @DisplayName("throws NOT_FOUND when caregiver user not found")
        void createLink_caregiverNotFound_throwsNotFound() {
            when(userRepository.findById(1L)).thenReturn(Optional.empty());

            CreateLinkRequest req = new CreateLinkRequest(2L, "PERMANENT", null, null);

            assertThatThrownBy(() -> service.createLink(1L, req, 99L))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("Caregiver not found");
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  getPatientsByCaregiver / getCaregiversByPatient
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("updateLink")
    class UpdateLinkTests {

        @Test
        @DisplayName("updates status and linkType when provided")
        void updateLink_updatesFields_savesLink() {
            when(linkRepo.findById(10L)).thenReturn(Optional.of(activeLink));
            when(linkRepo.save(any())).thenReturn(activeLink);

            UpdateLinkRequest req = new UpdateLinkRequest("SUSPENDED", "TEMPORARY", null, "updated");
            CaregiverPatientLinkResponse response = service.updateLink(10L, req, 1L);

            assertThat(response).isNotNull();
            assertThat(activeLink.getStatus()).isEqualTo(LinkStatus.SUSPENDED);
            assertThat(activeLink.getLinkType()).isEqualTo(LinkType.TEMPORARY);
        }

        @Test
        @DisplayName("throws NOT_FOUND when link does not exist")
        void updateLink_notFound_throwsNotFound() {
            when(linkRepo.findById(999L)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.updateLink(999L,
                    new UpdateLinkRequest(null, null, null, null), 1L))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("Link not found");
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  setPatientVideoCallsEnabled
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("suspendLink / reactivateLink / revokeLink")
    class StatusTransitionTests {

        @Test
        @DisplayName("suspendLink by userId sets status to SUSPENDED")
        void suspendLink_byUserId_setsSuspended() {
            when(linkRepo.findById(10L)).thenReturn(Optional.of(activeLink));
            when(userRepository.findById(1L)).thenReturn(Optional.of(caregiverUser));
            when(linkRepo.save(any())).thenReturn(activeLink);

            service.suspendLink(10L, "1");

            assertThat(activeLink.getStatus()).isEqualTo(LinkStatus.SUSPENDED);
        }

        @Test
        @DisplayName("suspendLink by email falls back to email lookup")
        void suspendLink_byEmail_lookupsByEmail() {
            when(linkRepo.findById(10L)).thenReturn(Optional.of(activeLink));
            when(userRepository.findByEmail("caregiver@test.com")).thenReturn(Optional.of(caregiverUser));
            when(linkRepo.save(any())).thenReturn(activeLink);

            service.suspendLink(10L, "caregiver@test.com");

            assertThat(activeLink.getStatus()).isEqualTo(LinkStatus.SUSPENDED);
        }

        @Test
        @DisplayName("reactivateLink sets status to ACTIVE for SUSPENDED link")
        void reactivateLink_fromSuspended_setsActive() {
            activeLink.setStatus(LinkStatus.SUSPENDED);
            when(linkRepo.findById(10L)).thenReturn(Optional.of(activeLink));
            when(linkRepo.save(any())).thenReturn(activeLink);

            service.reactivateLink(10L, 1L);

            assertThat(activeLink.getStatus()).isEqualTo(LinkStatus.ACTIVE);
        }

        @Test
        @DisplayName("reactivateLink throws BAD_REQUEST if link is not SUSPENDED")
        void reactivateLink_notSuspended_throwsBadRequest() {
            // activeLink is ACTIVE by default
            when(linkRepo.findById(10L)).thenReturn(Optional.of(activeLink));

            assertThatThrownBy(() -> service.reactivateLink(10L, 1L))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("Only suspended links can be reactivated");
        }

        @Test
        @DisplayName("revokeLink sets status to REVOKED")
        void revokeLink_setsRevoked() {
            when(linkRepo.findById(10L)).thenReturn(Optional.of(activeLink));
            when(linkRepo.save(any())).thenReturn(activeLink);

            service.revokeLink(10L, 1L);

            assertThat(activeLink.getStatus()).isEqualTo(LinkStatus.REVOKED);
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  getAllLinks / cleanupExpiredLinks
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("getPatientsByCaregiver / getCaregiversByPatient")
    class QueryTests {

        @Test
        @DisplayName("getPatientsByCaregiver returns list of patients for caregiver")
        void getPatientsByCaregiver_returnsLinks() {
            when(userRepository.findById(1L)).thenReturn(Optional.of(caregiverUser));
            when(linkRepo.findActivePatientsByCaregiver(eq(caregiverUser), any(LocalDateTime.class)))
                    .thenReturn(List.of(activeLink));

            List<CaregiverPatientLinkResponse> result = service.getPatientsByCaregiver(1L);

            assertThat(result).hasSize(1);
        }

        @Test
        @DisplayName("getPatientsByCaregiver throws NOT_FOUND for unknown caregiver")
        void getPatientsByCaregiver_unknownCaregiver_throws() {
            when(userRepository.findById(999L)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.getPatientsByCaregiver(999L))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("Caregiver not found");
        }

        @Test
        @DisplayName("getCaregiversByPatient returns list of caregivers for patient")
        void getCaregiversByPatient_returnsLinks() {
            when(userRepository.findById(2L)).thenReturn(Optional.of(patientUser));
            when(linkRepo.findActiveCaregiversByPatient(eq(patientUser), any(LocalDateTime.class)))
                    .thenReturn(List.of(activeLink));

            List<CaregiverPatientLinkResponse> result = service.getCaregiversByPatient(2L);

            assertThat(result).hasSize(1);
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  createPermanentLink
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("setPatientVideoCallsEnabled")
    class VideoCallsEnabledTests {

        @Test
        @DisplayName("admin can disable patient video calls")
        void setEnabled_admin_disablesCall() {
            when(linkRepo.findById(10L)).thenReturn(Optional.of(activeLink));
            when(linkRepo.save(any())).thenReturn(activeLink);

            service.setPatientVideoCallsEnabled(10L, false, 3L, Role.ADMIN);

            assertThat(activeLink.getNotes()).contains("[PATIENT_VIDEO_CALLS=OFF]");
        }

        @Test
        @DisplayName("owning caregiver can disable patient video calls")
        void setEnabled_owningCaregiver_disablesCall() {
            when(linkRepo.findById(10L)).thenReturn(Optional.of(activeLink));
            when(linkRepo.save(any())).thenReturn(activeLink);

            service.setPatientVideoCallsEnabled(10L, false, 1L, Role.CAREGIVER);

            assertThat(activeLink.getNotes()).contains("[PATIENT_VIDEO_CALLS=OFF]");
        }

        @Test
        @DisplayName("non-owning caregiver is FORBIDDEN")
        void setEnabled_nonOwningCaregiver_throws() {
            when(linkRepo.findById(10L)).thenReturn(Optional.of(activeLink));

            // actorUserId=5 doesn't own the link (caregiverUser.id=1)
            assertThatThrownBy(() -> service.setPatientVideoCallsEnabled(10L, false, 5L, Role.CAREGIVER))
                    .isInstanceOf(AppException.class)
                    .satisfies(ex -> assertThat(((AppException) ex).getStatus()).isEqualTo(HttpStatus.FORBIDDEN));
        }

        @Test
        @DisplayName("admin can re-enable patient video calls")
        void setEnabled_admin_enablesCall() {
            activeLink.setNotes("[PATIENT_VIDEO_CALLS=OFF]");
            when(linkRepo.findById(10L)).thenReturn(Optional.of(activeLink));
            when(linkRepo.save(any())).thenReturn(activeLink);

            service.setPatientVideoCallsEnabled(10L, true, 3L, Role.ADMIN);

            // Token should be removed
            String notes = activeLink.getNotes();
            assertThat(notes == null || !notes.contains("[PATIENT_VIDEO_CALLS=OFF]")).isTrue();
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  hasActiveLink
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("getAllLinks and cleanupExpiredLinks")
    class AdminTests {

        @Test
        @DisplayName("getAllLinks returns all links")
        void getAllLinks_returnsAll() {
            when(linkRepo.findAll()).thenReturn(List.of(activeLink));

            List<CaregiverPatientLinkResponse> result = service.getAllLinks();

            assertThat(result).hasSize(1);
        }

        @Test
        @DisplayName("cleanupExpiredLinks sets status to EXPIRED")
        void cleanupExpiredLinks_updatesExpiredLinks() {
            CaregiverPatientLink expiredLink = buildLink(20L, caregiverUser, patientUser, LinkStatus.ACTIVE,
                    LocalDateTime.now().minusDays(1));
            when(linkRepo.findExpiredActiveLinks(any(LocalDateTime.class)))
                    .thenReturn(List.of(expiredLink));
            when(linkRepo.save(any())).thenReturn(expiredLink);

            service.cleanupExpiredLinks();

            assertThat(expiredLink.getStatus()).isEqualTo(LinkStatus.EXPIRED);
            verify(linkRepo).save(expiredLink);
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  hasAccessToPatient / isPatientVideoCallsEnabled (already in
    //  CallPermissionServiceTest but testing directly for coverage)
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("createPermanentLink")
    class PermanentLinkTests {

        @Test
        @DisplayName("creates permanent link when none exists")
        void createPermanentLink_noExisting_saves() {
            when(userRepository.findById(1L)).thenReturn(Optional.of(caregiverUser));
            when(userRepository.findById(2L)).thenReturn(Optional.of(patientUser));
            when(linkRepo.existsActiveNonExpiredLink(eq(caregiverUser), eq(patientUser), any()))
                    .thenReturn(false);
            when(linkRepo.save(any())).thenAnswer(inv -> inv.getArgument(0));

            service.createPermanentLink(1L, 2L, "permanent link");

            verify(linkRepo).save(any(CaregiverPatientLink.class));
        }

        @Test
        @DisplayName("skips creation when permanent link already exists")
        void createPermanentLink_alreadyExists_skips() {
            when(userRepository.findById(1L)).thenReturn(Optional.of(caregiverUser));
            when(userRepository.findById(2L)).thenReturn(Optional.of(patientUser));
            when(linkRepo.existsActiveNonExpiredLink(eq(caregiverUser), eq(patientUser), any()))
                    .thenReturn(true);

            service.createPermanentLink(1L, 2L, "notes");

            verify(linkRepo, org.mockito.Mockito.never()).save(any());
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("hasActiveLink")
    class HasActiveLinkTests {

        @Test
        @DisplayName("returns true when active link exists")
        void hasActiveLink_exists_returnsTrue() {
            when(userRepository.findById(1L)).thenReturn(Optional.of(caregiverUser));
            when(userRepository.findById(2L)).thenReturn(Optional.of(patientUser));
            when(linkRepo.existsByCaregiverUserAndPatientUserAndStatus(
                    caregiverUser, patientUser, LinkStatus.ACTIVE)).thenReturn(true);

            assertThat(service.hasActiveLink(1L, 2L)).isTrue();
        }

        @Test
        @DisplayName("throws NOT_FOUND when caregiver not found")
        void hasActiveLink_caregiverNotFound_throws() {
            when(userRepository.findById(1L)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.hasActiveLink(1L, 2L))
                    .isInstanceOf(AppException.class)
                    .hasMessageContaining("Caregiver user not found");
        }
    }

    @Nested
    @DisplayName("hasAccessToPatient and isPatientVideoCallsEnabled")
    class PermissionMethodTests {

        @Test
        @DisplayName("hasAccessToPatient returns false when either user not found")
        void hasAccessToPatient_userNotFound_returnsFalse() {
            when(userRepository.findById(1L)).thenReturn(Optional.empty());

            assertThat(service.hasAccessToPatient(1L, 2L)).isFalse();
        }

        @Test
        @DisplayName("hasAccessToPatient returns true when active non-expired link exists")
        void hasAccessToPatient_activeLink_returnsTrue() {
            when(userRepository.findById(1L)).thenReturn(Optional.of(caregiverUser));
            when(userRepository.findById(2L)).thenReturn(Optional.of(patientUser));
            when(linkRepo.existsActiveNonExpiredLink(eq(caregiverUser), eq(patientUser), any()))
                    .thenReturn(true);

            assertThat(service.hasAccessToPatient(1L, 2L)).isTrue();
        }

        @Test
        @DisplayName("isPatientVideoCallsEnabled returns false when no link")
        void isPatientVideoCallsEnabled_noLink_returnsFalse() {
            when(userRepository.findById(1L)).thenReturn(Optional.of(caregiverUser));
            when(userRepository.findById(2L)).thenReturn(Optional.of(patientUser));
            when(linkRepo.findTopByCaregiverUserAndPatientUserAndStatusOrderByUpdatedAtDesc(
                    caregiverUser, patientUser, LinkStatus.ACTIVE))
                    .thenReturn(Optional.empty());

            assertThat(service.isPatientVideoCallsEnabled(1L, 2L)).isFalse();
        }

        @Test
        @DisplayName("isPatientVideoCallsEnabled returns true when link has no disable token")
        void isPatientVideoCallsEnabled_noToken_returnsTrue() {
            when(userRepository.findById(1L)).thenReturn(Optional.of(caregiverUser));
            when(userRepository.findById(2L)).thenReturn(Optional.of(patientUser));
            when(linkRepo.findTopByCaregiverUserAndPatientUserAndStatusOrderByUpdatedAtDesc(
                    caregiverUser, patientUser, LinkStatus.ACTIVE))
                    .thenReturn(Optional.of(activeLink));

            assertThat(service.isPatientVideoCallsEnabled(1L, 2L)).isTrue();
        }
    }
}
