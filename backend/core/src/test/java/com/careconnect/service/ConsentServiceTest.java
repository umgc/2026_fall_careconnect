package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.model.ConsentGrant;
import com.careconnect.repository.ConsentGrantRepository;
import java.time.Instant;
import java.util.List;
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

    private ConsentService service;

    @BeforeEach
    void setUp() {
        service = new ConsentService(consentGrantRepository);
    }

    @Test
    @DisplayName("returns false when either id is null")
    void isAiRetrievalConsentGranted_falseWhenIdsMissing() {
        assertThat(service.isAiRetrievalConsentGranted(null, PATIENT_USER_ID)).isFalse();
        assertThat(service.isAiRetrievalConsentGranted(CAREGIVER_USER_ID, null)).isFalse();
    }

    @Test
    @DisplayName("delegates to repository for active grant lookup")
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
    @DisplayName("hasAnyAiRetrievalGrantHistory delegates to existsBy...")
    void hasAnyAiRetrievalGrantHistory_delegates() {
        when(consentGrantRepository.existsByPatientUserIdAndGranteeUserIdAndScope(
                PATIENT_USER_ID, CAREGIVER_USER_ID, ConsentGrant.SCOPE_AI_RETRIEVAL))
                .thenReturn(true);

        assertThat(service.hasAnyAiRetrievalGrantHistory(CAREGIVER_USER_ID, PATIENT_USER_ID))
                .isTrue();
    }

    @Test
    @DisplayName("grants consent and persists an ACTIVE row when none exists")
    void grantAiRetrievalConsent_persistsActiveGrant() {
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
    @DisplayName("refresh existing ACTIVE grant instead of inserting a duplicate")
    void grantAiRetrievalConsent_refreshesExistingActiveGrant() {
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
    @DisplayName("throws when granting without required ids")
    void grantAiRetrievalConsent_throwsWhenIdsMissing() {
        org.assertj.core.api.Assertions.assertThatThrownBy(
                        () -> service.grantAiRetrievalConsent(null, CAREGIVER_USER_ID, "CAREGIVER", null))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("revokes all active grants for the tuple")
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
    @DisplayName("returns zero when revoking without required ids")
    void revokeAiRetrievalConsent_returnsZeroWhenIdsMissing() {
        assertThat(service.revokeAiRetrievalConsent(null, CAREGIVER_USER_ID)).isZero();
        assertThat(service.revokeAiRetrievalConsent(PATIENT_USER_ID, null)).isZero();
    }
}
