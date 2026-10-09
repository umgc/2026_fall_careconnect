package com.careconnect.service.ehr.athena;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class AthenaFhirExceptionTest {

    @Test
    void preservesClassificationAndMessage() {
        AthenaFhirException exception = new AthenaFhirException(
                AthenaFhirException.Kind.SCOPE_DENIED, "scope not granted");

        assertThat(exception.getKind()).isEqualTo(AthenaFhirException.Kind.SCOPE_DENIED);
        assertThat(exception).hasMessage("scope not granted");
        assertThat(exception.getCause()).isNull();
    }

    @Test
    void preservesCauseWithoutAddingUpstreamPayload() {
        IllegalStateException cause = new IllegalStateException("transport failed");

        AthenaFhirException exception = new AthenaFhirException(
                AthenaFhirException.Kind.UNAVAILABLE, "athena is unavailable", cause);

        assertThat(exception.getKind()).isEqualTo(AthenaFhirException.Kind.UNAVAILABLE);
        assertThat(exception).hasMessage("athena is unavailable").hasCause(cause);
    }
}
