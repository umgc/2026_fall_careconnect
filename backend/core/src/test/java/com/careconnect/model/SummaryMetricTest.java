package com.careconnect.model;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class SummaryMetricTest {

    // ─── No-arg constructor ───────────────────────────────────────────────────

    @Test
    void noArgConstructor_createsInstanceWithNullFields() throws Exception {
        final SummaryMetric m = new SummaryMetric();

        assertThat(m).isNotNull();
        assertThat(m.getId()).isNull();
        assertThat(m.getPatient()).isNull();
        assertThat(m.getPeriodStart()).isNull();
        assertThat(m.getPeriodEnd()).isNull();
        assertThat(m.getAdherenceRate()).isNull();
        assertThat(m.getAvgHeartRate()).isNull();
    }

    // ─── All-args constructor ─────────────────────────────────────────────────

    @Test
    void allArgsConstructor_setsAllFields() throws Exception {
        final Patient patient = new Patient();
        final Instant start = Instant.now().minusSeconds(3600);
        final Instant end = Instant.now();

        final SummaryMetric m = new SummaryMetric(1L, patient, start, end, 0.85, 72.5);

        assertThat(m.getId()).isEqualTo(1L);
        assertThat(m.getPatient()).isSameAs(patient);
        assertThat(m.getPeriodStart()).isEqualTo(start);
        assertThat(m.getPeriodEnd()).isEqualTo(end);
        assertThat(m.getAdherenceRate()).isEqualTo(0.85);
        assertThat(m.getAvgHeartRate()).isEqualTo(72.5);
    }

    // ─── Builder ──────────────────────────────────────────────────────────────

    @Test
    void builder_allFields_setsCorrectly() throws Exception {
        final Patient patient = new Patient();
        final Instant start = Instant.now().minusSeconds(3600);
        final Instant end = Instant.now();

        final SummaryMetric m = SummaryMetric.builder()
                .id(1L)
                .patient(patient)
                .periodStart(start)
                .periodEnd(end)
                .adherenceRate(0.85)
                .avgHeartRate(72.5)
                .build();

        assertThat(m.getId()).isEqualTo(1L);
        assertThat(m.getPatient()).isSameAs(patient);
        assertThat(m.getPeriodStart()).isEqualTo(start);
        assertThat(m.getPeriodEnd()).isEqualTo(end);
        assertThat(m.getAdherenceRate()).isEqualTo(0.85);
        assertThat(m.getAvgHeartRate()).isEqualTo(72.5);
    }

    @Test
    void builder_defaults_allNull() throws Exception {
        final SummaryMetric m = SummaryMetric.builder().build();

        assertThat(m.getId()).isNull();
        assertThat(m.getPatient()).isNull();
        assertThat(m.getPeriodStart()).isNull();
        assertThat(m.getPeriodEnd()).isNull();
        assertThat(m.getAdherenceRate()).isNull();
        assertThat(m.getAvgHeartRate()).isNull();
    }

    // ─── Setters ──────────────────────────────────────────────────────────────

    @Test
    void setters_updateAllFields() throws Exception {
        final SummaryMetric m = new SummaryMetric();
        final Patient patient = new Patient();
        final Instant now = Instant.now();

        m.setId(10L);
        m.setPatient(patient);
        m.setPeriodStart(now.minusSeconds(86400));
        m.setPeriodEnd(now);
        m.setAdherenceRate(0.90);
        m.setAvgHeartRate(75.0);

        assertThat(m.getId()).isEqualTo(10L);
        assertThat(m.getPatient()).isSameAs(patient);
        assertThat(m.getPeriodStart()).isEqualTo(now.minusSeconds(86400));
        assertThat(m.getPeriodEnd()).isEqualTo(now);
        assertThat(m.getAdherenceRate()).isEqualTo(0.90);
        assertThat(m.getAvgHeartRate()).isEqualTo(75.0);
    }

    // ─── equals and hashCode (@Data + @EqualsAndHashCode) ─────────────────────

    @Test
    void equals_sameFields_returnsTrue() throws Exception {
        final Patient patient = new Patient();
        final Instant start = Instant.parse("2025-01-01T00:00:00Z");
        final Instant end = Instant.parse("2025-01-02T00:00:00Z");

        final SummaryMetric m1 = SummaryMetric.builder()
                .id(1L).patient(patient).periodStart(start).periodEnd(end)
                .adherenceRate(0.85).avgHeartRate(72.5).build();
        final SummaryMetric m2 = SummaryMetric.builder()
                .id(1L).patient(patient).periodStart(start).periodEnd(end)
                .adherenceRate(0.85).avgHeartRate(72.5).build();

        assertThat(m1).isEqualTo(m2);
        assertThat(m1.hashCode()).isEqualTo(m2.hashCode());
    }

    @Test
    void equals_differentId_returnsNotEqual() throws Exception {
        final SummaryMetric m1 = SummaryMetric.builder().id(1L).build();
        final SummaryMetric m2 = SummaryMetric.builder().id(2L).build();

        assertThat(m1).isNotEqualTo(m2);
    }

    @Test
    void equals_differentAdherenceRate_returnsNotEqual() throws Exception {
        final SummaryMetric m1 = SummaryMetric.builder().adherenceRate(0.5).build();
        final SummaryMetric m2 = SummaryMetric.builder().adherenceRate(0.9).build();

        assertThat(m1).isNotEqualTo(m2);
    }

    @Test
    void equals_null_returnsFalse() throws Exception {
        final SummaryMetric m = SummaryMetric.builder().id(1L).build();
        assertThat(m).isNotEqualTo(null);
    }

    @Test
    void equals_differentType_returnsFalse() throws Exception {
        final SummaryMetric m = SummaryMetric.builder().id(1L).build();
        assertThat(m).isNotEqualTo("not a SummaryMetric");
    }

    @Test
    void equals_self_returnsTrue() throws Exception {
        final SummaryMetric m = SummaryMetric.builder().id(1L).build();
        assertThat(m).isEqualTo(m);
    }

    @Test
    void hashCode_consistentForSameObject() throws Exception {
        final SummaryMetric m = SummaryMetric.builder().id(1L).adherenceRate(0.5).build();
        assertThat(m.hashCode()).isEqualTo(m.hashCode());
    }

    // ─── toString (@Data) ─────────────────────────────────────────────────────

    @Test
    void toString_containsFieldNames() throws Exception {
        final SummaryMetric m = SummaryMetric.builder()
                .id(1L)
                .adherenceRate(0.85)
                .avgHeartRate(72.5)
                .build();

        final String str = m.toString();
        assertThat(str).contains("SummaryMetric");
        assertThat(str).contains("id=1");
        assertThat(str).contains("adherenceRate=0.85");
        assertThat(str).contains("avgHeartRate=72.5");
    }

    @Test
    void toString_nullFields_handlesGracefully() throws Exception {
        final SummaryMetric m = new SummaryMetric();
        final String str = m.toString();
        assertThat(str).contains("SummaryMetric");
        assertThat(str).contains("id=null");
    }

    // ─── canEqual (@EqualsAndHashCode) ────────────────────────────────────────

    @Test
    void canEqual_sameType_returnsTrue() throws Exception {
        final SummaryMetric m1 = new SummaryMetric();
        final SummaryMetric m2 = new SummaryMetric();
        assertThat(m1.canEqual(m2)).isTrue();
    }

    @Test
    void canEqual_differentType_returnsFalse() throws Exception {
        final SummaryMetric m = new SummaryMetric();
        assertThat(m.canEqual("string")).isFalse();
    }

    // ─── Auditable inherited fields ───────────────────────────────────────────

    @Test
    void auditableFields_gettersAndSetters() throws Exception {
        final SummaryMetric m = new SummaryMetric();
        final LocalDateTime now = LocalDateTime.now();

        m.setCreatedAt(now.minusDays(1));
        m.setUpdatedAt(now);

        assertThat(m.getCreatedAt()).isEqualTo(now.minusDays(1));
        assertThat(m.getUpdatedAt()).isEqualTo(now);
    }

    @Test
    void onCreate_setsTimestamps() throws Exception {
        final SummaryMetric m = new SummaryMetric();
        assertThat(m.getCreatedAt()).isNull();
        assertThat(m.getUpdatedAt()).isNull();

        m.onCreate();

        assertThat(m.getCreatedAt()).isNotNull();
        assertThat(m.getUpdatedAt()).isNotNull();
    }

    @Test
    void onUpdate_setsUpdatedAt() throws Exception {
        final SummaryMetric m = new SummaryMetric();
        m.onCreate();
        final LocalDateTime originalCreatedAt = m.getCreatedAt();

        m.onUpdate();

        assertThat(m.getCreatedAt()).isEqualTo(originalCreatedAt);
        assertThat(m.getUpdatedAt()).isNotNull();
    }

    // ─── getGeneratedAt (derived from Auditable.createdAt) ───────────────────

    @Test
    void getGeneratedAt_returnsCreatedAtAsInstant() throws Exception {
        final SummaryMetric m = new SummaryMetric();
        final LocalDateTime createdAt = LocalDateTime.of(2026, 10, 10, 9, 30);
        m.setCreatedAt(createdAt);

        assertThat(m.getGeneratedAt())
                .isEqualTo(createdAt.atZone(java.time.ZoneId.systemDefault()).toInstant());
    }

    @Test
    void getGeneratedAt_nullCreatedAt_returnsNull() throws Exception {
        assertThat(new SummaryMetric().getGeneratedAt()).isNull();
    }
}
