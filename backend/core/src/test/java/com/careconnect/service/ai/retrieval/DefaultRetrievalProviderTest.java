package com.careconnect.service.ai.retrieval;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class DefaultRetrievalProviderTest {

    @Test
    @DisplayName("DefaultRetrievalSourceExclusionProvider returns empty exclusions")
    void defaultSourceExclusionsEmpty() {
        DefaultRetrievalSourceExclusionProvider provider = new DefaultRetrievalSourceExclusionProvider();
        assertThat(provider.getExcludedSourceTypes(1L)).isEmpty();
    }

    @Test
    @DisplayName("DefaultRetrievalConsentProvider fails closed for caregivers")
    void defaultConsentFailsClosed() {
        DefaultRetrievalConsentProvider provider = new DefaultRetrievalConsentProvider();
        assertThat(provider.isCaregiverConsentGranted(10L, 20L)).isFalse();
    }
}
