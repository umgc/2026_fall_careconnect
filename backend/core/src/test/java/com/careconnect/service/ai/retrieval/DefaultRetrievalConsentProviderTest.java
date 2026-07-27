package com.careconnect.service.ai.retrieval;

import com.careconnect.service.CaregiverPatientLinkService;
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
    private CaregiverPatientLinkService caregiverPatientLinkService;

    @InjectMocks
    private DefaultRetrievalConsentProvider provider;

    @Test
    @DisplayName("grants consent when an active care-circle link exists")
    void grantsWhenActiveLinkExists() {
        when(caregiverPatientLinkService.hasAccessToPatient(10L, 20L)).thenReturn(true);

        assertThat(provider.isCaregiverConsentGranted(10L, 20L)).isTrue();
        verify(caregiverPatientLinkService).hasAccessToPatient(10L, 20L);
    }

    @Test
    @DisplayName("denies consent when no active care-circle link exists")
    void deniesWhenNoActiveLink() {
        when(caregiverPatientLinkService.hasAccessToPatient(10L, 20L)).thenReturn(false);

        assertThat(provider.isCaregiverConsentGranted(10L, 20L)).isFalse();
    }

    @Test
    @DisplayName("denies consent when caregiver or patient id is null")
    void deniesWhenIdsNull() {
        assertThat(provider.isCaregiverConsentGranted(null, 20L)).isFalse();
        assertThat(provider.isCaregiverConsentGranted(10L, null)).isFalse();
        verifyNoInteractions(caregiverPatientLinkService);
    }
}
