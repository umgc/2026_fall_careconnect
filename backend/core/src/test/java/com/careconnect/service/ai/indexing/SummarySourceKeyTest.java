package com.careconnect.service.ai.indexing;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class SummarySourceKeyTest {

    @Test
    void callKeysRoundTripAndLegacyNumericKeysRemainReplayable() {
        assertThat(SummarySourceKey.parseCallSummaryId(SummarySourceKey.call(42L)))
                .contains(42L);
        assertThat(SummarySourceKey.parseCallSummaryId("42")).contains(42L);
        assertThat(SummarySourceKey.parseVisitSummaryId(SummarySourceKey.visit(42L)))
                .contains(42L);
        assertThat(SummarySourceKey.parsePublicSummaryId(SummarySourceKey.call(42L)))
                .contains(42L);
        assertThat(SummarySourceKey.sourceKind(SummarySourceKey.call(42L)))
                .isEqualTo(SummarySourceKey.CALL_KIND);
    }

    @Test
    void visitMalformedAndOverflowKeysAreNotParsedAsCallSummaries() {
        assertThat(SummarySourceKey.parseCallSummaryId("visit-summary:42")).isEmpty();
        assertThat(SummarySourceKey.parseCallSummaryId("call-summary:not-a-number")).isEmpty();
        assertThat(SummarySourceKey.parseCallSummaryId(
                "call-summary:999999999999999999999999")).isEmpty();
    }
}
