package com.careconnect.model.ehr;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Test IDs TC-EHR-AUD-001..002 are permanent. Never renumber, never reuse.
 */
class EhrAuditEventTest {

    @Test
    @DisplayName("TC-EHR-AUD-001: onCreate defaults eventTime when unset")
    void onCreate_defaultsEventTimeWhenUnset() {
        final EhrAuditEvent event = EhrAuditEvent.builder()
                .patientId(7L)
                .source("MEDICARE")
                .resourceType("Patient")
                .outcome(EhrRetrievalOutcome.SUCCESS)
                .build();

        event.onCreate();

        assertThat(event.getEventTime()).isNotNull();
    }

    @Test
    @DisplayName("TC-EHR-AUD-002: onCreate preserves caller-supplied eventTime")
    void onCreate_preservesCallerSuppliedEventTime() {
        final OffsetDateTime supplied = OffsetDateTime.now().minusHours(2);
        final EhrAuditEvent event = EhrAuditEvent.builder()
                .patientId(7L)
                .source("MEDICARE")
                .resourceType("Patient")
                .outcome(EhrRetrievalOutcome.SUCCESS)
                .eventTime(supplied)
                .build();

        event.onCreate();

        assertThat(event.getEventTime()).isEqualTo(supplied);
    }
}
