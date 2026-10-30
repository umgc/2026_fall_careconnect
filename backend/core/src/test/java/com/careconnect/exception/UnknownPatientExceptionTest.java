package com.careconnect.exception;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class UnknownPatientExceptionTest {

    @Test
    void defaultConstructorUsesPatientNotFoundMessage() {
        assertThat(new UnknownPatientException()).hasMessage("Patient not found");
    }

    @Test
    void messageConstructorPreservesMessage() {
        assertThat(new UnknownPatientException("missing")).hasMessage("missing");
    }

    @Test
    void messageAndCauseConstructorPreservesBoth() {
        RuntimeException cause = new RuntimeException("root cause");

        assertThat(new UnknownPatientException("missing", cause))
                .hasMessage("missing")
                .hasCause(cause);
    }

    @Test
    void causeConstructorPreservesCause() {
        RuntimeException cause = new RuntimeException("root cause");

        assertThat(new UnknownPatientException(cause)).hasCause(cause);
    }
}
