package com.careconnect.security;

import com.careconnect.exception.AppException;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.ConsentGrantRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

import java.time.Instant;
import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Patient-level isolation for the EHR read surface (Epic caregiver-consent access model, mirroring
 * {@link MedicareAccessPolicy}): only the patient, or an assigned caregiver holding the patient's
 * EHR_VIEW consent, and every refusal is the same 404.
 * <p>
 * Test IDs: TC-EHR-AUTHZ-001 to 013. What a refusal looks like over HTTP is
 * {@link EpicAccessPolicyHttpTest}; the same rules against real repository rows are
 * {@link EpicAccessPolicyJpaTest}.
 * <p>
 * Most cases here are negative on purpose: a guard is only as good as the requests it turns away.
 */
class EpicAccessPolicyTest {

    private static final long PATIENT = 100L;
    private static final long OTHER_PATIENT = 200L;
    private static final long CAREGIVER = 300L;

    private CaregiverPatientLinkRepository links;
    private ConsentGrantRepository consents;
    private EpicAccessPolicy policy;

    @BeforeEach
    void setUp() {
        links = mock(CaregiverPatientLinkRepository.class);
        consents = mock(ConsentGrantRepository.class);
        policy = new EpicAccessPolicy(links, consents);
    }

    private void linked(final long patient, final boolean isLinked) {
        when(links.existsActiveNonExpiredLinkByUserIds(eq(CAREGIVER), eq(patient), any(LocalDateTime.class)))
                .thenReturn(isLinked);
    }

    private void consented(final String scope, final boolean granted) {
        when(consents.existsActiveGrant(eq(PATIENT), eq(CAREGIVER), eq(scope), any(Instant.class)))
                .thenReturn(granted);
    }

    private static User user(final long id, final Role role) {
        return User.builder().id(id).role(role).build();
    }

    private User caregiverWithPermission(final boolean hasPermission) {
        final User caregiver = mock(User.class);
        when(caregiver.getId()).thenReturn(CAREGIVER);
        when(caregiver.isCaregiver()).thenReturn(true);
        when(caregiver.hasPermission(Permission.VIEW_ASSIGNED_PATIENTS)).thenReturn(hasPermission);
        return caregiver;
    }

    private void assertRefused(final User caller, final Long patientUserId) {
        assertThatThrownBy(() -> policy.requireEhrReadAccess(caller, patientUserId))
                .isInstanceOf(AppException.class)
                .hasMessage(EpicAccessPolicy.NOT_FOUND_MESSAGE)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Nested
    @DisplayName("refused, as a 404")
    class Refused {

        @Test
        @DisplayName("TC-EHR-AUTHZ-001 a patient asking for another patient's EHR data")
        void otherPatient() {
            assertRefused(user(PATIENT, Role.PATIENT), OTHER_PATIENT);
        }

        @Test
        @DisplayName("TC-EHR-AUTHZ-002 a caregiver with no link to the patient, without querying consent")
        void caregiverNotAssigned() {
            linked(PATIENT, false);

            assertRefused(caregiverWithPermission(true), PATIENT);
            verify(consents, never()).existsActiveGrant(anyLong(), anyLong(), any(), any());
        }

        @Test
        @DisplayName("TC-EHR-AUTHZ-003 an assigned caregiver the patient has not given EHR_VIEW consent")
        void caregiverWithoutConsent() {
            linked(PATIENT, true);
            consented(EpicAccessPolicy.SCOPE_EHR_VIEW, false);

            assertRefused(caregiverWithPermission(true), PATIENT);
        }

        @Test
        @DisplayName("TC-EHR-AUTHZ-004 an assigned caregiver holding only another scope's consent, such as Ask AI's AI_RETRIEVAL")
        void caregiverWithOtherScopeConsentOnly() {
            linked(PATIENT, true);
            consented("AI_RETRIEVAL", true);
            consented(EpicAccessPolicy.SCOPE_EHR_VIEW, false);

            assertRefused(caregiverWithPermission(true), PATIENT);
        }

        @Test
        @DisplayName("TC-EHR-AUTHZ-005 a caregiver with EHR_VIEW consent but no active link, for example after it expired")
        void caregiverWithConsentButNoLink() {
            linked(PATIENT, false);
            consented(EpicAccessPolicy.SCOPE_EHR_VIEW, true);

            assertRefused(caregiverWithPermission(true), PATIENT);
        }

        @Test
        @DisplayName("TC-EHR-AUTHZ-006 a linked caregiver whose account lacks VIEW_ASSIGNED_PATIENTS, without querying the link")
        void caregiverWithoutPermission() {
            assertRefused(caregiverWithPermission(false), PATIENT);
            verify(links, never()).existsActiveNonExpiredLinkByUserIds(anyLong(), anyLong(), any());
        }

        @Test
        @DisplayName("TC-EHR-AUTHZ-007 an administrator, although requirePatientAccess would let one through")
        void administrator() {
            assertRefused(user(1L, Role.ADMIN), PATIENT);
        }

        @Test
        @DisplayName("TC-EHR-AUTHZ-008 a linked family member, although requirePatientAccess would let one through")
        void familyMember() {
            assertRefused(user(400L, Role.FAMILY_MEMBER), PATIENT);
            verify(links, never()).existsActiveNonExpiredLinkByUserIds(anyLong(), anyLong(), any());
        }

        @Test
        @DisplayName("TC-EHR-AUTHZ-009 no signed-in user")
        void noCaller() {
            assertRefused(null, PATIENT);
        }

        @Test
        @DisplayName("TC-EHR-AUTHZ-010 a caller whose account has no id")
        void callerWithoutId() {
            assertRefused(User.builder().role(Role.PATIENT).build(), PATIENT);
        }

        @Test
        @DisplayName("TC-EHR-AUTHZ-011 no patient named")
        void noPatient() {
            assertRefused(user(PATIENT, Role.PATIENT), null);
        }
    }

    @Nested
    @DisplayName("allowed")
    class Allowed {

        @Test
        @DisplayName("TC-EHR-AUTHZ-012 the patient reading their own EHR data")
        void patientSelf() {
            assertThatCode(() -> policy.requireEhrReadAccess(user(PATIENT, Role.PATIENT), PATIENT))
                    .doesNotThrowAnyException();
        }

        @Test
        @DisplayName("TC-EHR-AUTHZ-013 an assigned caregiver with an active link, the permission and the patient's EHR_VIEW consent")
        void assignedCaregiverWithConsent() {
            linked(PATIENT, true);
            consented(EpicAccessPolicy.SCOPE_EHR_VIEW, true);

            assertThatCode(() -> policy.requireEhrReadAccess(caregiverWithPermission(true), PATIENT))
                    .doesNotThrowAnyException();
            verify(consents).existsActiveGrant(
                    eq(PATIENT), eq(CAREGIVER), eq(EpicAccessPolicy.SCOPE_EHR_VIEW), any(Instant.class));
        }
    }
}
