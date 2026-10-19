package com.careconnect.service.ehr.athena;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class AthenaLinkResultTest {

    @Test
    void linkedResultContainsOnlyTheLinkedChartIdentifier() {
        AthenaLinkResult result = AthenaLinkResult.linked("athena-42");

        assertThat(result.state()).isEqualTo(AthenaLinkResult.State.LINKED);
        assertThat(result.athenaPatientId()).isEqualTo("athena-42");
        assertThat(result.isLinked()).isTrue();
    }

    @Test
    void nonLinkedResultHasNoChartIdentifier() {
        AthenaLinkResult result = AthenaLinkResult.of(AthenaLinkResult.State.AMBIGUOUS_MATCH);

        assertThat(result.state()).isEqualTo(AthenaLinkResult.State.AMBIGUOUS_MATCH);
        assertThat(result.athenaPatientId()).isNull();
        assertThat(result.isLinked()).isFalse();
    }
}
