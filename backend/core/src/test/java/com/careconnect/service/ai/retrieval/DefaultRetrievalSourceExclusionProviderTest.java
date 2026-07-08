package com.careconnect.service.ai.retrieval;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class DefaultRetrievalSourceExclusionProviderTest {

    @Test
    @DisplayName("returns empty exclusions until patient preference persistence exists")
    void returnsEmptyExclusions() {
        DefaultRetrievalSourceExclusionProvider provider = new DefaultRetrievalSourceExclusionProvider();

        assertThat(provider.getExcludedSourceTypes(1L)).isEmpty();
    }
}
