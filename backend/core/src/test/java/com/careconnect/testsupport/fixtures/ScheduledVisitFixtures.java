package com.careconnect.testsupport.fixtures;

// Shared test fixtures for shift scheduling scenarios.
// All DB and network dependencies must be mocked by callers — these
// fixtures produce detached entity objects with no persistence context.

import com.careconnect.model.schedule.ScheduledVisit;

import java.time.LocalDate;
import java.time.LocalTime;

/**
 * Factory for {@link ScheduledVisit} test fixtures.
 *
 * <p>Use these builders instead of inline object construction so every test
 * starts from a consistent, well-named baseline. Mutate fields on the returned
 * object only when the deviation is semantically meaningful to the scenario
 * being tested.
 *
 * <p>Canonical date/time values are intentionally fixed to a single weekday
 * (2026-03-17, Tuesday) so tests that rely on date arithmetic produce
 * reproducible results regardless of when they run.
 */
public final class ScheduledVisitFixtures {

    /** Canonical caregiver ID used across all default fixtures. */
    public static final Long DEFAULT_CAREGIVER_ID = 1L;

    /** Canonical patient ID used across all default fixtures. */
    public static final Long DEFAULT_PATIENT_ID = 10L;

    /** Fixed test date — a Tuesday, avoids weekend edge cases. */
    public static final LocalDate DEFAULT_DATE = LocalDate.of(2026, 3, 17);

    private ScheduledVisitFixtures() { }

    /**
     * Returns a standard morning scheduled visit suitable for most conflict
     * detection tests.
     *
     * <p>Default values: caregiver=1, patient=10, 10:00–11:00 (60 min),
     * serviceType="General Care", priority="Normal", status="Scheduled".
     *
     * <p>Use this when the test scenario does not depend on specific time,
     * priority, or service type — it gives you a clean non-conflicting baseline.
     */
    public static ScheduledVisit basicScheduledVisit() {
        ScheduledVisit visit = new ScheduledVisit();
        visit.setId(1L);
        visit.setCaregiverId(DEFAULT_CAREGIVER_ID);
        visit.setPatientId(DEFAULT_PATIENT_ID);
        visit.setScheduledDate(DEFAULT_DATE);
        visit.setScheduledTime(LocalTime.of(10, 0));
        visit.setDurationMinutes(60);
        visit.setServiceType("General Care");
        visit.setPriority("Normal");
        visit.setStatus("Scheduled");
        return visit;
    }

    /**
     * Returns {@link #basicScheduledVisit()} with the given ID assigned.
     *
     * <p>Use when you need to distinguish multiple visits in the same scenario
     * (e.g., verifying that conflict detection returns the correct visit ID).
     */
    public static ScheduledVisit visitWithId(Long id) {
        ScheduledVisit visit = basicScheduledVisit();
        visit.setId(id);
        return visit;
    }

    /**
     * Returns a visit that overlaps with {@link #basicScheduledVisit()} by
     * 30 minutes (10:30–11:30).
     *
     * <p>Use when the test needs to assert that the conflict detector returns
     * exactly one conflicting visit against the basic fixture.
     *
     * @param id the entity ID to assign; use a value different from 1L to
     *           avoid collisions with basicScheduledVisit
     */
    public static ScheduledVisit overlappingVisit(Long id) {
        // Arrange: starts 30 minutes into the basic visit window — guaranteed overlap.
        ScheduledVisit visit = basicScheduledVisit();
        visit.setId(id);
        visit.setScheduledTime(LocalTime.of(10, 30));
        visit.setDurationMinutes(60);
        return visit;
    }

    /**
     * Returns an afternoon visit that does NOT overlap with
     * {@link #basicScheduledVisit()} (14:00–15:00).
     *
     * <p>Use when you need a second visit for the same caregiver/patient on
     * the same day without triggering a time conflict — for example, to set up
     * a daily-limit scenario without introducing a scheduling collision.
     */
    public static ScheduledVisit afternoonVisit(Long id) {
        ScheduledVisit visit = basicScheduledVisit();
        visit.setId(id);
        visit.setScheduledTime(LocalTime.of(14, 0));
        return visit;
    }

    /**
     * Returns a high-priority ("Urgent") EVV shift visit, useful for testing
     * that priority level does not bypass conflict detection rules.
     *
     * <p>Time window is identical to {@link #basicScheduledVisit()} so placing
     * this visit alongside the basic one will always produce a conflict.
     */
    public static ScheduledVisit highPriorityVisit() {
        ScheduledVisit visit = basicScheduledVisit();
        visit.setId(2L);
        visit.setPriority("Urgent");
        visit.setServiceType("EVV");
        return visit;
    }

    /**
     * Returns a visit with status "Cancelled".
     *
     * <p>Use when the test verifies that cancelled visits are excluded from
     * conflict detection or duration aggregation.
     */
    public static ScheduledVisit cancelledVisit(Long id) {
        ScheduledVisit visit = basicScheduledVisit();
        visit.setId(id);
        visit.setStatus("Cancelled");
        return visit;
    }
}
