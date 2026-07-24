package com.careconnect.service.ai.retrieval;

import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.ConsentService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DefaultRetrievalConsentProviderTest {

    @Mock
    private ConsentService consentService;

    @Mock
    private CaregiverPatientLinkService caregiverPatientLinkService;

    @InjectMocks
    private DefaultRetrievalConsentProvider provider;

    @Test
    @DisplayName("grants consent when an explicit ConsentGrant is active")
    void grantsWhenConsentGrantActive() {
        when(consentService.isAiRetrievalConsentGranted(10L, 20L)).thenReturn(true);

        assertThat(provider.isCaregiverConsentGranted(10L, 20L)).isTrue();
        verify(consentService).isAiRetrievalConsentGranted(10L, 20L);
        verifyNoInteractions(caregiverPatientLinkService);
    }

    @Test
    @DisplayName("falls back to an active care-circle link when no ConsentGrant history exists")
    void grantsWhenActiveLinkExistsAndNoGrantHistory() {
        when(consentService.isAiRetrievalConsentGranted(10L, 20L)).thenReturn(false);
        when(consentService.hasAnyAiRetrievalGrantHistory(10L, 20L)).thenReturn(false);
        when(caregiverPatientLinkService.hasAccessToPatient(10L, 20L)).thenReturn(true);

        assertThat(provider.isCaregiverConsentGranted(10L, 20L)).isTrue();
        verify(caregiverPatientLinkService).hasAccessToPatient(10L, 20L);
    }

    @Test
    @DisplayName("denies consent after revoke even when care-circle link remains")
    void deniesWhenGrantHistoryExistsDespiteLink() {
        when(consentService.isAiRetrievalConsentGranted(10L, 20L)).thenReturn(false);
        when(consentService.hasAnyAiRetrievalGrantHistory(10L, 20L)).thenReturn(true);

        assertThat(provider.isCaregiverConsentGranted(10L, 20L)).isFalse();
        verifyNoInteractions(caregiverPatientLinkService);
    }

    @Test
    @DisplayName("denies consent when neither ConsentGrant nor active link exists")
    void deniesWhenNoActiveLink() {
        when(consentService.isAiRetrievalConsentGranted(10L, 20L)).thenReturn(false);
        when(consentService.hasAnyAiRetrievalGrantHistory(10L, 20L)).thenReturn(false);
        when(caregiverPatientLinkService.hasAccessToPatient(10L, 20L)).thenReturn(false);

        assertThat(provider.isCaregiverConsentGranted(10L, 20L)).isFalse();
    }

    @Test
    @DisplayName("denies consent when caregiver or patient id is null")
    void deniesWhenIdsNull() {
        assertThat(provider.isCaregiverConsentGranted(null, 20L)).isFalse();
        assertThat(provider.isCaregiverConsentGranted(10L, null)).isFalse();
        verifyNoInteractions(caregiverPatientLinkService);
        verifyNoInteractions(consentService);
    }
}
