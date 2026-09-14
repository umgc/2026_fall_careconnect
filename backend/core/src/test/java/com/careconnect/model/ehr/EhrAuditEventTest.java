package com.careconnect.model.ehr;

import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class EhrAuditEventTest {

    @Test
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
