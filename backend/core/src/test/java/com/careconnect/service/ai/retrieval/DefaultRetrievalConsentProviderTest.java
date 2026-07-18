package com.careconnect.service.ai.retrieval;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class DefaultRetrievalConsentProviderTest {

    @Test
    @DisplayName("fails closed for caregivers until consent persistence exists")
    void failsClosedForCaregivers() {
        DefaultRetrievalConsentProvider provider = new DefaultRetrievalConsentProvider();

        assertThat(provider.isCaregiverConsentGranted(10L, 20L)).isFalse();
    }
}
