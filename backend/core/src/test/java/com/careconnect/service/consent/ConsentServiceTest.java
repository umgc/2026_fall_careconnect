package com.careconnect.service.consent;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.careconnect.exception.AppException;
import com.careconnect.model.ConsentGrant;
import com.careconnect.repository.ConsentGrantRepository;

import java.time.Instant;
import java.util.List;

import com.careconnect.service.CaregiverPatientLinkService;
import org.springframework.http.HttpStatus;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
@DisplayName("ConsentService Tests")
class ConsentServiceTest {

    private static final Long PATIENT_USER_ID = 10L;
    private static final Long CAREGIVER_USER_ID = 20L;

    @Mock
    private ConsentGrantRepository consentGrantRepository;

    @Mock
    private CaregiverPatientLinkService caregiverPatientLinkService;

    private ConsentService service;

    @BeforeEach
    void setUp() {
        service = new ConsentService(consentGrantRepository, caregiverPatientLinkService);
    }

    @Test
    @DisplayName("TC-CONSENT-001 AI retrieval: the grant check is false when either id is null")
    void isAiRetrievalConsentGranted_falseWhenIdsMissing() {
        assertThat(service.isAiRetrievalConsentGranted(null, PATIENT_USER_ID)).isFalse();
        assertThat(service.isAiRetrievalConsentGranted(CAREGIVER_USER_ID, null)).isFalse();
    }

    @Test
    @DisplayName("TC-CONSENT-002 AI retrieval: the grant check asks the repository for an active AI_RETRIEVAL grant")
    void isAiRetrievalConsentGranted_delegatesToRepository() {
        when(consentGrantRepository.existsActiveGrant(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("AI_RETRIEVAL"), any(Instant.class)))
                .thenReturn(true);

        final boolean granted =
                service.isAiRetrievalConsentGranted(CAREGIVER_USER_ID, PATIENT_USER_ID);

        assertThat(granted).isTrue();
        verify(consentGrantRepository).existsActiveGrant(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("AI_RETRIEVAL"), any(Instant.class));
    }

    @Test
    @DisplayName("TC-CONSENT-003 AI retrieval: grant history delegates to existsByPatientUserIdAndGranteeUserIdAndScope")
    void hasAnyAiRetrievalGrantHistory_delegates() {
        when(consentGrantRepository.existsByPatientUserIdAndGranteeUserIdAndScope(
                PATIENT_USER_ID, CAREGIVER_USER_ID, ConsentGrant.SCOPE_AI_RETRIEVAL))
                .thenReturn(true);

        assertThat(service.hasAnyAiRetrievalGrantHistory(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .isTrue();
    }

    @Test
    @DisplayName("TC-CONSENT-004 AI retrieval: effective consent is true when an active grant exists")
    void isEffectiveAiRetrievalConsent_trueWhenExplicitGrant() {
        when(consentGrantRepository.existsActiveGrant(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("AI_RETRIEVAL"), any(Instant.class)))
                .thenReturn(true);

        assertThat(service.isEffectiveAiRetrievalConsent(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .isTrue();
    }

    @Test
    @DisplayName("TC-CONSENT-005 AI retrieval: effective consent falls back to the care-circle link when there is no grant history")
    void isEffectiveAiRetrievalConsent_fallsBackToCareCircle() {
        when(consentGrantRepository.existsActiveGrant(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("AI_RETRIEVAL"), any(Instant.class)))
                .thenReturn(false);
        when(consentGrantRepository.existsByPatientUserIdAndGranteeUserIdAndScope(
                PATIENT_USER_ID, CAREGIVER_USER_ID, ConsentGrant.SCOPE_AI_RETRIEVAL))
                .thenReturn(false);
        when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .thenReturn(true);

        assertThat(service.isEffectiveAiRetrievalConsent(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .isTrue();
    }

    @Test
    @DisplayName("TC-CONSENT-006 AI retrieval: effective consent stays false after a revoke, despite the link")
    void isEffectiveAiRetrievalConsent_falseAfterRevokeHistory() {
        when(consentGrantRepository.existsActiveGrant(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("AI_RETRIEVAL"), any(Instant.class)))
                .thenReturn(false);
        when(consentGrantRepository.existsByPatientUserIdAndGranteeUserIdAndScope(
                PATIENT_USER_ID, CAREGIVER_USER_ID, ConsentGrant.SCOPE_AI_RETRIEVAL))
                .thenReturn(true);

        assertThat(service.isEffectiveAiRetrievalConsent(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .isFalse();
    }

    @Test
    @DisplayName("TC-CONSENT-007 AI retrieval: granting persists an ACTIVE row when none exists")
    void grantAiRetrievalConsent_persistsActiveGrant() {
        when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .thenReturn(true);
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("AI_RETRIEVAL"), any(Instant.class)))
                .thenReturn(List.of());
        when(consentGrantRepository.save(any(ConsentGrant.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final ConsentGrant grant = service.grantAiRetrievalConsent(
                PATIENT_USER_ID, CAREGIVER_USER_ID, "CAREGIVER", null);

        assertThat(grant.getPatientUserId()).isEqualTo(PATIENT_USER_ID);
        assertThat(grant.getGranteeUserId()).isEqualTo(CAREGIVER_USER_ID);
        assertThat(grant.getGranteeRole()).isEqualTo("CAREGIVER");
        assertThat(grant.getScope()).isEqualTo(ConsentGrant.SCOPE_AI_RETRIEVAL);
        assertThat(grant.getStatus()).isEqualTo(ConsentGrant.STATUS_ACTIVE);
        assertThat(grant.getGrantedAt()).isNotNull();
    }

    @Test
    @DisplayName("TC-CONSENT-008 AI retrieval: a grant is rejected when the caregiver has no active care-circle link")
    void grantAiRetrievalConsent_requiresCareCircleLink() {
        when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .thenReturn(false);

        org.junit.jupiter.api.Assertions.assertThrows(
                com.careconnect.exception.AppException.class,
                () -> service.grantAiRetrievalConsent(
                        PATIENT_USER_ID, CAREGIVER_USER_ID, "CAREGIVER", null));

        verify(consentGrantRepository, times(0)).save(any());
    }

    @Test
    @DisplayName("TC-CONSENT-009 AI retrieval: granting again refreshes the ACTIVE grant instead of inserting a duplicate")
    void grantAiRetrievalConsent_refreshesExistingActiveGrant() {
        when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .thenReturn(true);
        final ConsentGrant existing = ConsentGrant.builder()
                .id(55L)
                .patientUserId(PATIENT_USER_ID)
                .granteeUserId(CAREGIVER_USER_ID)
                .granteeRole("CAREGIVER")
                .scope(ConsentGrant.SCOPE_AI_RETRIEVAL)
                .status(ConsentGrant.STATUS_ACTIVE)
                .grantedAt(Instant.parse("2026-01-01T00:00:00Z"))
                .build();
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("AI_RETRIEVAL"), any(Instant.class)))
                .thenReturn(List.of(existing));
        when(consentGrantRepository.save(any(ConsentGrant.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final Instant expiresAt = Instant.parse("2026-12-31T00:00:00Z");
        final ConsentGrant grant = service.grantAiRetrievalConsent(
                PATIENT_USER_ID, CAREGIVER_USER_ID, "CAREGIVER", expiresAt);

        assertThat(grant.getId()).isEqualTo(55L);
        assertThat(grant.getExpiresAt()).isEqualTo(expiresAt);
        assertThat(grant.getStatus()).isEqualTo(ConsentGrant.STATUS_ACTIVE);
        verify(consentGrantRepository, times(1)).save(existing);
    }

    @Test
    @DisplayName("TC-CONSENT-010 AI retrieval: granting without the required ids throws")
    void grantAiRetrievalConsent_throwsWhenIdsMissing() {
        org.assertj.core.api.Assertions.assertThatThrownBy(
                        () -> service.grantAiRetrievalConsent(null, CAREGIVER_USER_ID, "CAREGIVER", null))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("TC-CONSENT-011 AI retrieval: revoking revokes every active grant for the pair")
    void revokeAiRetrievalConsent_revokesActiveGrants() {
        final ConsentGrant active = ConsentGrant.builder()
                .id(1L)
                .patientUserId(PATIENT_USER_ID)
                .granteeUserId(CAREGIVER_USER_ID)
                .granteeRole("CAREGIVER")
                .scope(ConsentGrant.SCOPE_AI_RETRIEVAL)
                .status(ConsentGrant.STATUS_ACTIVE)
                .grantedAt(Instant.now())
                .build();
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("AI_RETRIEVAL"), any(Instant.class)))
                .thenReturn(List.of(active));

        final int revoked =
                service.revokeAiRetrievalConsent(PATIENT_USER_ID, CAREGIVER_USER_ID);

        assertThat(revoked).isEqualTo(1);
        assertThat(active.getStatus()).isEqualTo(ConsentGrant.STATUS_REVOKED);
        assertThat(active.getRevokedAt()).isNotNull();

        final ArgumentCaptor<List<ConsentGrant>> captor = ArgumentCaptor.forClass(List.class);
        verify(consentGrantRepository, times(1)).saveAll(captor.capture());
        assertThat(captor.getValue()).containsExactly(active);
    }

    @Test
    @DisplayName("TC-CONSENT-012 AI retrieval: revoking with no grant history writes a REVOKED sentinel to end the care-circle fallback")
    void revokeAiRetrievalConsent_writesSentinelWhenNoHistory() {
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("AI_RETRIEVAL"), any(Instant.class)))
                .thenReturn(List.of());
        when(consentGrantRepository.existsByPatientUserIdAndGranteeUserIdAndScope(
                PATIENT_USER_ID, CAREGIVER_USER_ID, ConsentGrant.SCOPE_AI_RETRIEVAL))
                .thenReturn(false);
        when(consentGrantRepository.save(any(ConsentGrant.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final int revoked =
                service.revokeAiRetrievalConsent(PATIENT_USER_ID, CAREGIVER_USER_ID);

        assertThat(revoked).isEqualTo(1);
        final ArgumentCaptor<ConsentGrant> captor = ArgumentCaptor.forClass(ConsentGrant.class);
        verify(consentGrantRepository).save(captor.capture());
        assertThat(captor.getValue().getStatus()).isEqualTo(ConsentGrant.STATUS_REVOKED);
        assertThat(captor.getValue().getRevokedAt()).isNotNull();
    }

    @Test
    @DisplayName("TC-CONSENT-013 AI retrieval: revoking without the required ids returns zero")
    void revokeAiRetrievalConsent_returnsZeroWhenIdsMissing() {
        assertThat(service.revokeAiRetrievalConsent(null, CAREGIVER_USER_ID)).isZero();
        assertThat(service.revokeAiRetrievalConsent(PATIENT_USER_ID, null)).isZero();
    }

    // ===== Medicare View (MEDICARE_VIEW) consent, PR #325 / WBS 6.2.56 =====
    // Test IDs TC-MCR-CONSENT-001 to 014, Software Test Plan §3.20.

    private ConsentGrant medicareGrant(final Long id, final Instant expiresAt) {
        return ConsentGrant.builder()
                .id(id)
                .patientUserId(PATIENT_USER_ID)
                .granteeUserId(CAREGIVER_USER_ID)
                .granteeRole("CAREGIVER")
                .scope(ConsentGrant.SCOPE_MEDICARE_VIEW)
                .status(ConsentGrant.STATUS_ACTIVE)
                .grantedAt(Instant.parse("2026-01-01T00:00:00Z"))
                .expiresAt(expiresAt)
                .build();
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-001 Medicare View check is false for a missing id and queries nothing")
    void isMedicareViewConsentGranted_falseWhenIdsMissing() {
        assertThat(service.isMedicareViewConsentGranted(null, PATIENT_USER_ID)).isFalse();
        assertThat(service.isMedicareViewConsentGranted(CAREGIVER_USER_ID, null)).isFalse();
        verifyNoInteractions(consentGrantRepository);
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-002 Medicare View check asks for an active MEDICARE_VIEW grant from the patient to the caregiver, never AI_RETRIEVAL")
    void isMedicareViewConsentGranted_queriesMedicareViewScope() {
        when(consentGrantRepository.existsActiveGrant(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("MEDICARE_VIEW"), any(Instant.class)))
                .thenReturn(true);

        assertThat(service.isMedicareViewConsentGranted(CAREGIVER_USER_ID, PATIENT_USER_ID)).isTrue();
        verify(consentGrantRepository, never()).existsActiveGrant(
                any(), any(), eq(ConsentGrant.SCOPE_AI_RETRIEVAL), any());
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-003 a linked caregiver with no MEDICARE_VIEW grant is not consented: no care-circle fallback (BR-02, DEF-MCR-29)")
    void isEffectiveMedicareViewConsent_noCareCircleFallback() {
        lenient().when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .thenReturn(true);
        when(consentGrantRepository.existsActiveGrant(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("MEDICARE_VIEW"), any(Instant.class)))
                .thenReturn(false);

        assertThat(service.isEffectiveMedicareViewConsent(CAREGIVER_USER_ID, PATIENT_USER_ID)).isFalse();
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-004 Medicare View effective consent is true with an active explicit grant")
    void isEffectiveMedicareViewConsent_trueWithExplicitGrant() {
        when(consentGrantRepository.existsActiveGrant(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("MEDICARE_VIEW"), any(Instant.class)))
                .thenReturn(true);

        assertThat(service.isEffectiveMedicareViewConsent(CAREGIVER_USER_ID, PATIENT_USER_ID)).isTrue();
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-005 granting persists one ACTIVE MEDICARE_VIEW row for the linked caregiver, role CAREGIVER")
    void grantMedicareViewConsent_persistsActiveGrant() {
        when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .thenReturn(true);
        when(consentGrantRepository.findStatusActiveGrants(PATIENT_USER_ID, CAREGIVER_USER_ID, "MEDICARE_VIEW"))
                .thenReturn(List.of());
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("MEDICARE_VIEW"), any(Instant.class)))
                .thenReturn(List.of());
        when(consentGrantRepository.save(any(ConsentGrant.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final Instant expiresAt = Instant.now().plusSeconds(3600);
        final ConsentGrant grant = service.grantMedicareViewConsent(
                PATIENT_USER_ID, CAREGIVER_USER_ID, null, expiresAt);

        assertThat(grant.getPatientUserId()).isEqualTo(PATIENT_USER_ID);
        assertThat(grant.getGranteeUserId()).isEqualTo(CAREGIVER_USER_ID);
        assertThat(grant.getGranteeRole()).isEqualTo("CAREGIVER");
        assertThat(grant.getScope()).isEqualTo(ConsentGrant.SCOPE_MEDICARE_VIEW);
        assertThat(grant.getStatus()).isEqualTo(ConsentGrant.STATUS_ACTIVE);
        assertThat(grant.getExpiresAt()).isEqualTo(expiresAt);
        assertThat(grant.getGrantedAt()).isNotNull();
        verify(consentGrantRepository, times(1)).save(any(ConsentGrant.class));
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-006 granting to a user with no active caregiver link is refused with 400 and writes nothing")
    void grantMedicareViewConsent_requiresCaregiverLink() {
        when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .thenReturn(false);

        assertThatThrownBy(() -> service.grantMedicareViewConsent(
                PATIENT_USER_ID, CAREGIVER_USER_ID, "CAREGIVER", null))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.BAD_REQUEST);

        verify(consentGrantRepository, never()).save(any());
        verify(consentGrantRepository, never()).saveAll(any());
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-007 granting again refreshes the ACTIVE grant in place and revokes duplicate ACTIVE rows")
    void grantMedicareViewConsent_refreshesAndRevokesDuplicates() {
        when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .thenReturn(true);
        final ConsentGrant primary = medicareGrant(55L, null);
        final ConsentGrant duplicate = medicareGrant(56L, null);
        when(consentGrantRepository.findStatusActiveGrants(PATIENT_USER_ID, CAREGIVER_USER_ID, "MEDICARE_VIEW"))
                .thenReturn(List.of(primary, duplicate));
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("MEDICARE_VIEW"), any(Instant.class)))
                .thenReturn(List.of(primary, duplicate));
        when(consentGrantRepository.save(any(ConsentGrant.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final Instant expiresAt = Instant.now().plusSeconds(86_400);
        final ConsentGrant grant = service.grantMedicareViewConsent(
                PATIENT_USER_ID, CAREGIVER_USER_ID, "CAREGIVER", expiresAt);

        assertThat(grant.getId()).isEqualTo(55L);
        assertThat(grant.getExpiresAt()).isEqualTo(expiresAt);
        assertThat(grant.getStatus()).isEqualTo(ConsentGrant.STATUS_ACTIVE);
        assertThat(duplicate.getStatus()).isEqualTo(ConsentGrant.STATUS_REVOKED);
        assertThat(duplicate.getRevokedAt()).isNotNull();
        verify(consentGrantRepository).save(primary);
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-008 a soft-expired ACTIVE row is revoked before a new grant is inserted")
    void grantMedicareViewConsent_revokesSoftExpiredRowFirst() {
        when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .thenReturn(true);
        final ConsentGrant expired = medicareGrant(60L, Instant.now().minusSeconds(60));
        when(consentGrantRepository.findStatusActiveGrants(PATIENT_USER_ID, CAREGIVER_USER_ID, "MEDICARE_VIEW"))
                .thenReturn(List.of(expired));
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("MEDICARE_VIEW"), any(Instant.class)))
                .thenReturn(List.of());
        when(consentGrantRepository.save(any(ConsentGrant.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final ConsentGrant grant = service.grantMedicareViewConsent(
                PATIENT_USER_ID, CAREGIVER_USER_ID, null, null);

        assertThat(expired.getStatus()).isEqualTo(ConsentGrant.STATUS_REVOKED);
        assertThat(expired.getRevokedAt()).isNotNull();
        assertThat(grant.getId()).isNull();
        assertThat(grant.getStatus()).isEqualTo(ConsentGrant.STATUS_ACTIVE);
        final ArgumentCaptor<List<ConsentGrant>> captor = ArgumentCaptor.forClass(List.class);
        verify(consentGrantRepository).saveAll(captor.capture());
        assertThat(captor.getValue()).containsExactly(expired);
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-009 a grant whose expiry is not in the future is refused with 400 and writes nothing (DEF-MCR-30)")
    void grantMedicareViewConsent_rejectsPastExpiry() {
        lenient().when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .thenReturn(true);

        assertThatThrownBy(() -> service.grantMedicareViewConsent(
                PATIENT_USER_ID, CAREGIVER_USER_ID, "CAREGIVER", Instant.now().minusSeconds(3600)))
                .isInstanceOf(AppException.class)
                .hasMessage("expiresAt must be in the future")
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.BAD_REQUEST);

        verify(consentGrantRepository, never()).save(any());
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-010 a grantee role other than CAREGIVER is refused with 400 and writes nothing (DEF-MCR-30)")
    void grantMedicareViewConsent_rejectsOtherRoles() {
        lenient().when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .thenReturn(true);

        for (final String role : List.of("ADMIN", "FAMILY_MEMBER", "caregiver", "C".repeat(40))) {
            assertThatThrownBy(() -> service.grantMedicareViewConsent(
                    PATIENT_USER_ID, CAREGIVER_USER_ID, role, null))
                    .isInstanceOf(AppException.class)
                    .hasMessage("granteeRole must be CAREGIVER")
                    .extracting(e -> ((AppException) e).getStatus())
                    .isEqualTo(HttpStatus.BAD_REQUEST);
        }

        verify(consentGrantRepository, never()).save(any());
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-011 granting Medicare View without a patient or grantee id throws")
    void grantMedicareViewConsent_throwsWhenIdsMissing() {
        assertThatThrownBy(() -> service.grantMedicareViewConsent(null, CAREGIVER_USER_ID, null, null))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.grantMedicareViewConsent(PATIENT_USER_ID, null, null, null))
                .isInstanceOf(IllegalArgumentException.class);
        verifyNoInteractions(consentGrantRepository);
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-012 revoking sets every active MEDICARE_VIEW grant for the pair to REVOKED and returns the count")
    void revokeMedicareViewConsent_revokesActiveGrants() {
        final ConsentGrant active = medicareGrant(1L, null);
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("MEDICARE_VIEW"), any(Instant.class)))
                .thenReturn(List.of(active));

        assertThat(service.revokeMedicareViewConsent(PATIENT_USER_ID, CAREGIVER_USER_ID)).isEqualTo(1);

        assertThat(active.getStatus()).isEqualTo(ConsentGrant.STATUS_REVOKED);
        assertThat(active.getRevokedAt()).isNotNull();
        final ArgumentCaptor<List<ConsentGrant>> captor = ArgumentCaptor.forClass(List.class);
        verify(consentGrantRepository).saveAll(captor.capture());
        assertThat(captor.getValue()).containsExactly(active);
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-013 revoking when nothing is active returns 0 and writes no sentinel row (DEF-MCR-29)")
    void revokeMedicareViewConsent_nothingActiveWritesNothing() {
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("MEDICARE_VIEW"), any(Instant.class)))
                .thenReturn(List.of());
        lenient().when(consentGrantRepository.existsByPatientUserIdAndGranteeUserIdAndScope(
                PATIENT_USER_ID, CAREGIVER_USER_ID, ConsentGrant.SCOPE_MEDICARE_VIEW))
                .thenReturn(false);

        assertThat(service.revokeMedicareViewConsent(PATIENT_USER_ID, CAREGIVER_USER_ID)).isZero();

        verify(consentGrantRepository, never()).save(any());
        verify(consentGrantRepository, never()).saveAll(any());
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-014 revoking Medicare View without a patient or grantee id returns 0 and queries nothing")
    void revokeMedicareViewConsent_returnsZeroWhenIdsMissing() {
        assertThat(service.revokeMedicareViewConsent(null, CAREGIVER_USER_ID)).isZero();
        assertThat(service.revokeMedicareViewConsent(PATIENT_USER_ID, null)).isZero();
        verifyNoInteractions(consentGrantRepository);
    }

    // ===== EHR-import self-consent and AI-retrieval edge paths (coverage gate, PR #325) =====
    // Characterize inherited behaviour of ConsentService, which PR #325 moved. Test IDs TC-CONSENT-014 to 019
    // and 042 to 046, Software Test Plan §3.20.

    private ConsentGrant grant(final Long id, final String scope, final Instant expiresAt) {
        return ConsentGrant.builder()
                .id(id)
                .patientUserId(PATIENT_USER_ID)
                .granteeUserId(CAREGIVER_USER_ID)
                .granteeRole("CAREGIVER")
                .scope(scope)
                .status(ConsentGrant.STATUS_ACTIVE)
                .grantedAt(Instant.parse("2026-01-01T00:00:00Z"))
                .expiresAt(expiresAt)
                .build();
    }

    @Test
    @DisplayName("TC-CONSENT-014 EHR import: recording self-consent without a patient id throws and writes nothing")
    void recordEhrImportConsent_requiresPatient() {
        assertThatThrownBy(() -> service.recordEhrImportConsent(null)).isInstanceOf(IllegalArgumentException.class);
        verifyNoInteractions(consentGrantRepository);
    }

    @Test
    @DisplayName("TC-CONSENT-015 EHR import: the first self-consent is one ACTIVE EHR_IMPORT row with the patient as grantee")
    void recordEhrImportConsent_persistsSelfGrant() {
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(PATIENT_USER_ID), eq(ConsentGrant.SCOPE_EHR_IMPORT), any(Instant.class)))
                .thenReturn(List.of());
        when(consentGrantRepository.save(any(ConsentGrant.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final ConsentGrant grant = service.recordEhrImportConsent(PATIENT_USER_ID);

        assertThat(grant.getPatientUserId()).isEqualTo(PATIENT_USER_ID);
        assertThat(grant.getGranteeUserId()).isEqualTo(PATIENT_USER_ID);
        assertThat(grant.getGranteeRole()).isEqualTo("PATIENT");
        assertThat(grant.getScope()).isEqualTo(ConsentGrant.SCOPE_EHR_IMPORT);
        assertThat(grant.getStatus()).isEqualTo(ConsentGrant.STATUS_ACTIVE);
        assertThat(grant.getGrantedAt()).isNotNull();
    }

    @Test
    @DisplayName("TC-CONSENT-016 EHR import: recording again refreshes the existing ACTIVE self-grant instead of inserting")
    void recordEhrImportConsent_refreshesExisting() {
        final ConsentGrant existing = grant(70L, ConsentGrant.SCOPE_EHR_IMPORT, null);
        existing.setRevokedAt(Instant.parse("2026-02-01T00:00:00Z"));
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(PATIENT_USER_ID), eq(ConsentGrant.SCOPE_EHR_IMPORT), any(Instant.class)))
                .thenReturn(List.of(existing));
        when(consentGrantRepository.save(existing)).thenReturn(existing);

        final ConsentGrant grant = service.recordEhrImportConsent(PATIENT_USER_ID);

        assertThat(grant).isSameAs(existing);
        assertThat(grant.getRevokedAt()).isNull();
        assertThat(grant.getStatus()).isEqualTo(ConsentGrant.STATUS_ACTIVE);
        assertThat(grant.getGrantedAt()).isAfter(Instant.parse("2026-01-01T00:00:00Z"));
        verify(consentGrantRepository, times(1)).save(existing);
    }

    @Test
    @DisplayName("TC-CONSENT-017 EHR import: revoking without a patient id returns 0 and queries nothing")
    void revokeEhrImportConsent_returnsZeroWhenIdMissing() {
        assertThat(service.revokeEhrImportConsent(null)).isZero();
        verifyNoInteractions(consentGrantRepository);
    }

    @Test
    @DisplayName("TC-CONSENT-018 EHR import: revoking sets every active self-grant to REVOKED and returns the count")
    void revokeEhrImportConsent_revokesActive() {
        final ConsentGrant active = grant(71L, ConsentGrant.SCOPE_EHR_IMPORT, null);
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(PATIENT_USER_ID), eq(ConsentGrant.SCOPE_EHR_IMPORT), any(Instant.class)))
                .thenReturn(List.of(active));

        assertThat(service.revokeEhrImportConsent(PATIENT_USER_ID)).isEqualTo(1);

        assertThat(active.getStatus()).isEqualTo(ConsentGrant.STATUS_REVOKED);
        assertThat(active.getRevokedAt()).isNotNull();
        verify(consentGrantRepository).saveAll(List.of(active));
    }

    @Test
    @DisplayName("TC-CONSENT-019 EHR import: revoking with nothing active returns 0 and writes nothing")
    void revokeEhrImportConsent_nothingActive() {
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(PATIENT_USER_ID), eq(ConsentGrant.SCOPE_EHR_IMPORT), any(Instant.class)))
                .thenReturn(List.of());

        assertThat(service.revokeEhrImportConsent(PATIENT_USER_ID)).isZero();

        verify(consentGrantRepository, never()).saveAll(any());
    }

    @Test
    @DisplayName("TC-CONSENT-042 AI retrieval: a soft-expired ACTIVE row is revoked before a new grant is inserted; an unexpired one is kept")
    void grantAiRetrievalConsent_revokesSoftExpiredRowFirst() {
        when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID)).thenReturn(true);
        final ConsentGrant expired = grant(80L, ConsentGrant.SCOPE_AI_RETRIEVAL, Instant.now().minusSeconds(60));
        final ConsentGrant live = grant(81L, ConsentGrant.SCOPE_AI_RETRIEVAL, Instant.now().plusSeconds(3600));
        when(consentGrantRepository.findStatusActiveGrants(PATIENT_USER_ID, CAREGIVER_USER_ID, "AI_RETRIEVAL"))
                .thenReturn(List.of(expired, live));
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("AI_RETRIEVAL"), any(Instant.class)))
                .thenReturn(List.of());
        when(consentGrantRepository.save(any(ConsentGrant.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.grantAiRetrievalConsent(PATIENT_USER_ID, CAREGIVER_USER_ID, "CAREGIVER", null);

        assertThat(expired.getStatus()).isEqualTo(ConsentGrant.STATUS_REVOKED);
        assertThat(live.getStatus()).isEqualTo(ConsentGrant.STATUS_ACTIVE);
        final ArgumentCaptor<List<ConsentGrant>> captor = ArgumentCaptor.forClass(List.class);
        verify(consentGrantRepository).saveAll(captor.capture());
        assertThat(captor.getValue()).containsExactly(expired);
    }

    @Test
    @DisplayName("TC-CONSENT-043 AI retrieval: granting again with duplicate ACTIVE rows keeps the first and revokes the rest")
    void grantAiRetrievalConsent_revokesDuplicateActiveRows() {
        when(caregiverPatientLinkService.hasAccessToPatient(CAREGIVER_USER_ID, PATIENT_USER_ID)).thenReturn(true);
        final ConsentGrant primary = grant(90L, ConsentGrant.SCOPE_AI_RETRIEVAL, null);
        final ConsentGrant duplicate = grant(91L, ConsentGrant.SCOPE_AI_RETRIEVAL, null);
        when(consentGrantRepository.findStatusActiveGrants(PATIENT_USER_ID, CAREGIVER_USER_ID, "AI_RETRIEVAL"))
                .thenReturn(List.of(primary, duplicate));
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("AI_RETRIEVAL"), any(Instant.class)))
                .thenReturn(List.of(primary, duplicate));
        when(consentGrantRepository.save(any(ConsentGrant.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        final ConsentGrant grant = service.grantAiRetrievalConsent(PATIENT_USER_ID, CAREGIVER_USER_ID, "CAREGIVER", null);

        assertThat(grant.getId()).isEqualTo(90L);
        assertThat(duplicate.getStatus()).isEqualTo(ConsentGrant.STATUS_REVOKED);
        assertThat(duplicate.getRevokedAt()).isNotNull();
        verify(consentGrantRepository).saveAll(List.of(duplicate));
    }

    @Test
    @DisplayName("TC-CONSENT-044 AI retrieval: grant history is false for a missing id and queries nothing")
    void hasAnyAiRetrievalGrantHistory_falseWhenIdsMissing() {
        assertThat(service.hasAnyAiRetrievalGrantHistory(null, PATIENT_USER_ID)).isFalse();
        assertThat(service.hasAnyAiRetrievalGrantHistory(CAREGIVER_USER_ID, null)).isFalse();
        verifyNoInteractions(consentGrantRepository);
    }

    @Test
    @DisplayName("TC-CONSENT-045 AI retrieval: effective consent is false for a missing id and asks nothing")
    void isEffectiveAiRetrievalConsent_falseWhenIdsMissing() {
        assertThat(service.isEffectiveAiRetrievalConsent(null, PATIENT_USER_ID)).isFalse();
        assertThat(service.isEffectiveAiRetrievalConsent(CAREGIVER_USER_ID, null)).isFalse();
        verifyNoInteractions(consentGrantRepository, caregiverPatientLinkService);
    }

    @Test
    @DisplayName("TC-CONSENT-046 AI retrieval: revoking with nothing active but grant history returns 0 and writes no sentinel")
    void revokeAiRetrievalConsent_historyWithoutActiveWritesNothing() {
        when(consentGrantRepository.findActiveGrants(
                eq(PATIENT_USER_ID), eq(CAREGIVER_USER_ID), eq("AI_RETRIEVAL"), any(Instant.class)))
                .thenReturn(List.of());
        when(consentGrantRepository.existsByPatientUserIdAndGranteeUserIdAndScope(
                PATIENT_USER_ID, CAREGIVER_USER_ID, ConsentGrant.SCOPE_AI_RETRIEVAL))
                .thenReturn(true);

        assertThat(service.revokeAiRetrievalConsent(PATIENT_USER_ID, CAREGIVER_USER_ID)).isZero();

        verify(consentGrantRepository, never()).save(any());
        verify(consentGrantRepository, never()).saveAll(any());
    }
}
