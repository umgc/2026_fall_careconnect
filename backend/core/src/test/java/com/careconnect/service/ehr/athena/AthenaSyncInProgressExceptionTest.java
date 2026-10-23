package com.careconnect.service.ehr.athena;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class AthenaSyncInProgressExceptionTest {

    @Test
    void communicatesThatAConcurrentSyncIsRejected() {
        AthenaSyncInProgressException exception = new AthenaSyncInProgressException();

        assertThat(exception).hasMessage("an athenahealth sync is already running for this user");
        assertThat(exception.getCause()).isNull();
    }
}
