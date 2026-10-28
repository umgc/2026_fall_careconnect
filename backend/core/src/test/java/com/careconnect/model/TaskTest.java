package com.careconnect.model;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class TaskTest {

    @Test
    void recurrenceAnchorIsOptionalAndRetainedByTheEntity() {
        final Task task = Task.builder().date("2025-02-28").recurrenceAnchorDate("2024-02-29").build();
        assertThat(task.getRecurrenceAnchorDate()).isEqualTo("2024-02-29");
        task.setRecurrenceAnchorDate(null);
        assertThat(task.getRecurrenceAnchorDate()).isNull();
    }

    // ─── No-arg constructor ───────────────────────────────────────────────────

    @Test
    void noArgConstructor_createsInstance() throws Exception {
        final Task t = new Task();

        assertThat(t).isNotNull();
        assertThat(t.getId()).isNull();
        assertThat(t.getPatient()).isNull();
        assertThat(t.getName()).isNull();
        assertThat(t.isCompleted()).isFalse();
        assertThat(t.getNotifications()).isNotNull().isEmpty(); // @Builder.Default initialises to empty list in no-arg ctor
    }

    // ─── Builder defaults ─────────────────────────────────────────────────────

    @Test
    void builder_defaults_initializesNotificationsList() throws Exception {
        final Task t = Task.builder().name("Test task").build();

        assertThat(t.getNotifications()).isNotNull().isEmpty();
    }

    // ─── Builder all fields ───────────────────────────────────────────────────

    @Test
    void builder_allFields() throws Exception {
        final Patient patient = new Patient();

        final Task t = Task.builder()
                .id(1L)
                .patient(patient)
                .name("Take medication")
                .description("Blood pressure medication")
                .date("2026-01-15")
                .timeOfDay("08:00 AM")
                .isCompleted(false)
                .taskType("Medication")
                .frequency("daily")
                .taskInterval(1)
                .doCount(30)
                .daysOfWeek("MON,WED,FRI")
                .createdAt(1000000L)
                .parentTaskId(null)
                .build();

        assertThat(t.getId()).isEqualTo(1L);
        assertThat(t.getPatient()).isSameAs(patient);
        assertThat(t.getName()).isEqualTo("Take medication");
        assertThat(t.getDescription()).isEqualTo("Blood pressure medication");
        assertThat(t.getDate()).isEqualTo("2026-01-15");
        assertThat(t.getTimeOfDay()).isEqualTo("08:00 AM");
        assertThat(t.isCompleted()).isFalse();
        assertThat(t.getTaskType()).isEqualTo("Medication");
        assertThat(t.getFrequency()).isEqualTo("daily");
        assertThat(t.getTaskInterval()).isEqualTo(1);
        assertThat(t.getDoCount()).isEqualTo(30);
        assertThat(t.getDaysOfWeek()).isEqualTo("MON,WED,FRI");
        assertThat(t.getCreatedAt()).isEqualTo(1000000L);
        assertThat(t.getParentTaskId()).isNull();
    }

    // ─── Setters ──────────────────────────────────────────────────────────────

    @Test
    void setters_updateFields() throws Exception {
        final Task t = new Task();
        final Patient patient = new Patient();

        t.setId(2L);
        t.setPatient(patient);
        t.setName("New task");
        t.setCompleted(true);
        t.setTaskType("Exercise");
        t.setFrequency("weekly");
        t.setParentTaskId(5L);

        assertThat(t.getId()).isEqualTo(2L);
        assertThat(t.getPatient()).isSameAs(patient);
        assertThat(t.getName()).isEqualTo("New task");
        assertThat(t.isCompleted()).isTrue();
        assertThat(t.getTaskType()).isEqualTo("Exercise");
        assertThat(t.getFrequency()).isEqualTo("weekly");
        assertThat(t.getParentTaskId()).isEqualTo(5L);
    }
}
