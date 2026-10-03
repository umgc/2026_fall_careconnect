package com.careconnect.security;

import com.careconnect.exception.NotFoundException;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.ConsentGrantRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
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
 * Patient-level isolation for Medicare data (WBS 6.2.37; SRS FR-MCR-16, FR-MCR-17, BR-02,
 * NFR-DEG-03): only the patient, or an assigned caregiver holding the patient's MEDICARE_VIEW
 * consent, and every refusal is the same 404.
 * <p>
 * Most cases here are negative on purpose. The criterion asks for isolation "demonstrated through
 * negative tests", and a guard is only as good as the requests it turns away.
 */
class MedicareAccessPolicyTest {

    private static final long PATIENT = 100L;
    private static final long OTHER_PATIENT = 200L;
    private static final long CAREGIVER = 300L;

    private CaregiverPatientLinkRepository links;
    private ConsentGrantRepository consents;
    private MedicareAccessPolicy policy;

    @BeforeEach
    void setUp() {
        links = mock(CaregiverPatientLinkRepository.class);
        consents = mock(ConsentGrantRepository.class);
        policy = new MedicareAccessPolicy(links, consents);
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
        assertThatThrownBy(() -> policy.requireMedicareAccess(caller, patientUserId))
                .isInstanceOf(NotFoundException.class)
                .hasMessage(MedicareAccessPolicy.NOT_FOUND_MESSAGE);
    }

    @Nested
    @DisplayName("refused, as a 404")
    class Refused {

        @Test
        @DisplayName("a patient asking for another patient's Medicare data")
        void otherPatient() {
            assertRefused(user(PATIENT, Role.PATIENT), OTHER_PATIENT);
        }

        @Test
        @DisplayName("a caregiver with no link to the patient, without querying consent")
        void caregiverNotAssigned() {
            linked(PATIENT, false);

            assertRefused(caregiverWithPermission(true), PATIENT);
            verify(consents, never()).existsActiveGrant(anyLong(), anyLong(), any(), any());
        }

        @Test
        @DisplayName("a caregiver linked to a different patient")
        void caregiverAssignedElsewhere() {
            linked(OTHER_PATIENT, true);
            linked(PATIENT, false);

            assertRefused(caregiverWithPermission(true), PATIENT);
        }

        @Test
        @DisplayName("an assigned caregiver the patient has not given MEDICARE_VIEW consent")
        void caregiverWithoutConsent() {
            linked(PATIENT, true);
            consented(MedicareAccessPolicy.SCOPE_MEDICARE_VIEW, false);

            assertRefused(caregiverWithPermission(true), PATIENT);
        }

        @Test
        @DisplayName("an assigned caregiver holding only another scope's consent, such as Ask AI's AI_RETRIEVAL")
        void caregiverWithOtherScopeConsentOnly() {
            linked(PATIENT, true);
            consented("AI_RETRIEVAL", true);
            consented(MedicareAccessPolicy.SCOPE_MEDICARE_VIEW, false);

            assertRefused(caregiverWithPermission(true), PATIENT);
        }

        @Test
        @DisplayName("a caregiver with MEDICARE_VIEW consent but no active link, for example after it expired")
        void caregiverWithConsentButNoLink() {
            linked(PATIENT, false);
            consented(MedicareAccessPolicy.SCOPE_MEDICARE_VIEW, true);

            assertRefused(caregiverWithPermission(true), PATIENT);
        }

        @Test
        @DisplayName("a linked caregiver whose account lacks VIEW_ASSIGNED_PATIENTS, without querying the link")
        void caregiverWithoutPermission() {
            assertRefused(caregiverWithPermission(false), PATIENT);
            verify(links, never()).existsActiveNonExpiredLinkByUserIds(anyLong(), anyLong(), any());
        }

        @Test
        @DisplayName("an administrator, although requirePatientAccess would let one through")
        void administrator() {
            assertRefused(user(1L, Role.ADMIN), PATIENT);
        }

        @Test
        @DisplayName("a linked family member, although requirePatientAccess would let one through")
        void familyMember() {
            assertRefused(user(400L, Role.FAMILY_MEMBER), PATIENT);
            verify(links, never()).existsActiveNonExpiredLinkByUserIds(anyLong(), anyLong(), any());
        }

        @Test
        @DisplayName("no signed-in user")
        void noCaller() {
            assertRefused(null, PATIENT);
        }

        @Test
        @DisplayName("a caller whose account has no id")
        void callerWithoutId() {
            assertRefused(User.builder().role(Role.PATIENT).build(), PATIENT);
        }

        @Test
        @DisplayName("no patient named")
        void noPatient() {
            assertRefused(user(PATIENT, Role.PATIENT), null);
        }
    }

    @Test
    @DisplayName("every refusal reads the same, so a caller cannot tell which rule refused it")
    void refusalsAreIndistinguishable() {
        when(links.existsActiveNonExpiredLinkByUserIds(anyLong(), anyLong(), any())).thenReturn(false);
        final List<String> messages = new ArrayList<>();
        for (final Runnable refused : List.<Runnable>of(
                () -> policy.requireMedicareAccess(user(PATIENT, Role.PATIENT), OTHER_PATIENT),
                () -> policy.requireMedicareAccess(caregiverWithPermission(true), PATIENT),
                () -> policy.requireMedicareAccess(user(1L, Role.ADMIN), PATIENT),
                () -> policy.requireMedicareAccess(null, PATIENT))) {
            try {
                refused.run();
            } catch (NotFoundException e) {
                messages.add(e.getMessage());
            }
        }
        assertThat(messages).hasSize(4).containsOnly(MedicareAccessPolicy.NOT_FOUND_MESSAGE);
    }

    @Nested
    @DisplayName("allowed")
    class Allowed {

        @Test
        @DisplayName("the patient reading their own Medicare data")
        void patientSelf() {
            assertThatCode(() -> policy.requireMedicareAccess(user(PATIENT, Role.PATIENT), PATIENT))
                    .doesNotThrowAnyException();
        }

        @Test
        @DisplayName("an assigned caregiver with an active link, the permission and the patient's MEDICARE_VIEW consent")
        void assignedCaregiverWithConsent() {
            linked(PATIENT, true);
            consented(MedicareAccessPolicy.SCOPE_MEDICARE_VIEW, true);

            assertThatCode(() -> policy.requireMedicareAccess(caregiverWithPermission(true), PATIENT))
                    .doesNotThrowAnyException();
            verify(consents).existsActiveGrant(
                    eq(PATIENT), eq(CAREGIVER), eq(MedicareAccessPolicy.SCOPE_MEDICARE_VIEW), any(Instant.class));
        }
    }
}
