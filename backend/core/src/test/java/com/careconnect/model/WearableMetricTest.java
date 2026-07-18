package com.careconnect.model;

import com.careconnect.model.WearableMetric.MetricType;
import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

class WearableMetricTest {

    // ─── No-arg constructor ───────────────────────────────────────────────────

    @Test
    void noArgConstructor_createsInstance() throws Exception {
        final WearableMetric wm = new WearableMetric();

        assertThat(wm).isNotNull();
        assertThat(wm.getId()).isNull();
        assertThat(wm.getPatient()).isNull();
        assertThat(wm.getMetric()).isNull();
        assertThat(wm.getMetricValue()).isNull();
        assertThat(wm.getRecordedAt()).isNull();
    }

    // ─── Builder all fields ───────────────────────────────────────────────────

    @Test
    void builder_allFields() throws Exception {
        final User patient = new User();
        final Instant now = Instant.now();

        final WearableMetric wm = WearableMetric.builder()
                .id(1L)
                .patient(patient)
                .metric(MetricType.HEART_RATE)
                .metricValue(72.5)
                .recordedAt(now)
                .build();

        assertThat(wm.getId()).isEqualTo(1L);
        assertThat(wm.getPatient()).isSameAs(patient);
        assertThat(wm.getMetric()).isEqualTo(MetricType.HEART_RATE);
        assertThat(wm.getMetricValue()).isEqualTo(72.5);
        assertThat(wm.getRecordedAt()).isEqualTo(now);
    }

    // ─── Setters ──────────────────────────────────────────────────────────────

    @Test
    void setters_updateFields() throws Exception {
        final WearableMetric wm = new WearableMetric();
        final Instant now = Instant.now();

        wm.setId(2L);
        wm.setMetric(MetricType.SPO2);
        wm.setMetricValue(98.0);
        wm.setRecordedAt(now);

        assertThat(wm.getId()).isEqualTo(2L);
        assertThat(wm.getMetric()).isEqualTo(MetricType.SPO2);
        assertThat(wm.getMetricValue()).isEqualTo(98.0);
        assertThat(wm.getRecordedAt()).isEqualTo(now);
    }

    // ─── MetricType enum ──────────────────────────────────────────────────────

    @Test
    void metricType_allValues() throws Exception {
        assertThat(MetricType.values()).containsExactly(
                MetricType.HEART_RATE, MetricType.SPO2, MetricType.TEMPERATURE,
                MetricType.BLOOD_PRESSURE_SYS, MetricType.BLOOD_PRESSURE_DIA, MetricType.WEIGHT,
                MetricType.STEPS);
    }

    // ─── equals() and hashCode() ──────────────────────────────────────────────

    @Test
    void equals_sameFields_returnsTrue() throws Exception {
        final Instant now = Instant.now();
        final WearableMetric w1 = WearableMetric.builder()
                .id(1L).metric(MetricType.HEART_RATE).metricValue(72.0).recordedAt(now).build();
        final WearableMetric w2 = WearableMetric.builder()
                .id(1L).metric(MetricType.HEART_RATE).metricValue(72.0).recordedAt(now).build();

        assertThat(w1).isEqualTo(w2);
        assertThat(w1.hashCode()).isEqualTo(w2.hashCode());
    }
}
