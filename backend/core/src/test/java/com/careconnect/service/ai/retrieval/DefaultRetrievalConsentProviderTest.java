package com.careconnect.service.ai.retrieval;

import com.careconnect.service.consent.ConsentService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DefaultRetrievalConsentProviderTest {

    @Mock
    private ConsentService consentService;

    @InjectMocks
    private DefaultRetrievalConsentProvider provider;

    @Test
    @DisplayName("TC-CONSENT-040 the Ask AI retrieval consent provider delegates to ConsentService.isEffectiveAiRetrievalConsent")
    void delegatesToEffectiveConsent() {
        when(consentService.isEffectiveAiRetrievalConsent(10L, 20L)).thenReturn(true);

        assertThat(provider.isCaregiverConsentGranted(10L, 20L)).isTrue();
        verify(consentService).isEffectiveAiRetrievalConsent(10L, 20L);
    }

    @Test
    @DisplayName("TC-CONSENT-041 the Ask AI retrieval consent provider propagates a denial")
    void propagatesDenial() {
        when(consentService.isEffectiveAiRetrievalConsent(10L, 20L)).thenReturn(false);

        assertThat(provider.isCaregiverConsentGranted(10L, 20L)).isFalse();
    }
}
