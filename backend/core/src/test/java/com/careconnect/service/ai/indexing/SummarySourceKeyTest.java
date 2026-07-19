package com.careconnect.service.ai.indexing;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class SummarySourceKeyTest {

    @Test
    void callKeysRoundTripAndLegacyNumericKeysRemainReplayable() {
        assertThat(SummarySourceKey.parseCallSummaryId(SummarySourceKey.call(42L)))
                .contains(42L);
        assertThat(SummarySourceKey.parseCallSummaryId("42")).contains(42L);
    }

    @Test
    void visitMalformedAndOverflowKeysAreNotParsedAsCallSummaries() {
        assertThat(SummarySourceKey.parseCallSummaryId("visit-summary:42")).isEmpty();
        assertThat(SummarySourceKey.parseCallSummaryId("call-summary:not-a-number")).isEmpty();
        assertThat(SummarySourceKey.parseCallSummaryId(
                "call-summary:999999999999999999999999")).isEmpty();
    }
}
