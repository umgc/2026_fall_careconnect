package com.careconnect.service.schedule;

// Pattern-setter test demonstrating the TESTING_NORMS.md fixture approach.
// Complements ScheduleConflictServiceTest (which uses inline helpers) by
// showing how to use ScheduledVisitFixtures for readable, reusable setups.
//
// Brice: copy this structure when adding coverage for EVV and auth modules.
// Key rules from TESTING_NORMS.md:
//   - Always import from testsupport/fixtures — never build ScheduledVisit inline.
//   - Mock every repository call; never use a live database.
//   - Arrange / Act / Assert comments in every non-trivial test body.

import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import com.careconnect.testsupport.fixtures.ScheduledVisitFixtures;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.time.LocalTime;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;

/**
 * Fixture-pattern demonstration for {@link ScheduleConflictService}.
 *
 * <p>Scenario focus: conflict detection when a high-priority visit competes
 * for the same time window, and daily-limit accumulation across multiple
 * fixture-built visits. These scenarios extend coverage by exercising the
 * fixture library rather than the ad-hoc {@code createVisit()} helper used
 * in {@link ScheduleConflictServiceTest}.
 */
@DisplayName("ScheduleConflictService — fixture pattern")
class ScheduleConflictFixturePatternTest {

    @Mock
    private ScheduledVisitRepository scheduledVisitRepository;

    @InjectMocks
    private ScheduleConflictService conflictService;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    // ========================================================================
    // Priority does not override conflict detection
    // ========================================================================

    @Nested
    @DisplayName("High-priority visit conflict detection")
    class HighPriorityConflict {

        @Test
        @DisplayName("high-priority visit still conflicts when time windows overlap")
        void highPriorityVisitConflictsWhenWindowsOverlap() {
            // Arrange: an existing scheduled visit is already on the books.
            ScheduledVisit existing = ScheduledVisitFixtures.basicScheduledVisit();
            when(scheduledVisitRepository
                    .findByCaregiverIdAndScheduledDate(
                            ScheduledVisitFixtures.DEFAULT_CAREGIVER_ID,
                            ScheduledVisitFixtures.DEFAULT_DATE))
                    .thenReturn(List.of(existing));

            // Act: attempt to schedule a high-priority visit at the same time.
            // highPriorityVisit() has an identical 10:00-11:00 window to
            // basicScheduledVisit() — priority must not suppress detection.
            ScheduledVisit urgent = ScheduledVisitFixtures.highPriorityVisit();
            List<ScheduledVisit> conflicts = conflictService.detectCaregiverConflicts(
                    urgent.getCaregiverId(),
                    ScheduledVisitFixtures.DEFAULT_DATE,
                    urgent.getScheduledTime(),
                    urgent.getDurationMinutes());

            // Assert: conflict detected regardless of priority level.
            assertEquals(1, conflicts.size(),
                    "Urgent priority must not bypass caregiver conflict detection.");
            assertEquals(existing.getId(), conflicts.get(0).getId());
        }

        @Test
        @DisplayName("high-priority visit does not conflict when scheduled after existing visit")
        void highPriorityVisitNoConflictWhenAfterExisting() {
            // Arrange: existing visit ends at 11:00.
            ScheduledVisit existing = ScheduledVisitFixtures.basicScheduledVisit();
            when(scheduledVisitRepository
                    .findByCaregiverIdAndScheduledDate(
                            ScheduledVisitFixtures.DEFAULT_CAREGIVER_ID,
                            ScheduledVisitFixtures.DEFAULT_DATE))
                    .thenReturn(List.of(existing));

            // Act: schedule the urgent visit in the afternoon — no overlap.
            ScheduledVisit urgent = ScheduledVisitFixtures.highPriorityVisit();
            urgent.setScheduledTime(LocalTime.of(11, 0));  // starts exactly when existing ends

            List<ScheduledVisit> conflicts = conflictService.detectCaregiverConflicts(
                    urgent.getCaregiverId(),
                    ScheduledVisitFixtures.DEFAULT_DATE,
                    urgent.getScheduledTime(),
                    urgent.getDurationMinutes());

            // Assert: adjacent visits do not conflict.
            assertTrue(conflicts.isEmpty(),
                    "Visits that start exactly when another ends must not conflict.");
        }
    }

    // ========================================================================
    // Daily limit accumulation via fixture-built visit lists
    // ========================================================================

    @Nested
    @DisplayName("Daily duration accumulation using fixture visits")
    class DailyDurationFixtureAccumulation {

        @Test
        @DisplayName("total duration sums basic and afternoon fixture visits")
        void totalDurationSumsBasicAndAfternoonVisits() {
            // Arrange: two non-overlapping visits from the fixture library.
            ScheduledVisit morning   = ScheduledVisitFixtures.basicScheduledVisit();    // 60 min
            ScheduledVisit afternoon = ScheduledVisitFixtures.afternoonVisit(2L);       // 60 min
            // cancelledVisit must not be counted.
            ScheduledVisit cancelled = ScheduledVisitFixtures.cancelledVisit(3L);

            when(scheduledVisitRepository
                    .findByCaregiverIdAndScheduledDate(
                            ScheduledVisitFixtures.DEFAULT_CAREGIVER_ID,
                            ScheduledVisitFixtures.DEFAULT_DATE))
                    .thenReturn(List.of(morning, afternoon, cancelled));

            // Act
            int total = conflictService.getTotalDurationForDay(
                    ScheduledVisitFixtures.DEFAULT_CAREGIVER_ID,
                    ScheduledVisitFixtures.DEFAULT_DATE);

            // Assert: 60 + 60 = 120; cancelled visit (60 min) excluded.
            assertEquals(120, total,
                    "Cancelled visits must not contribute to daily duration.");
        }

        @Test
        @DisplayName("exceedsDailyLimit returns false for two fixture visits")
        void exceedsDailyLimitFalseForTwoFixtureVisits() {
            // Arrange: two active visits — well below the 8-visit daily limit.
            when(scheduledVisitRepository
                    .countByCaregiverIdAndScheduledDateAndStatusNot(
                            ScheduledVisitFixtures.DEFAULT_CAREGIVER_ID,
                            ScheduledVisitFixtures.DEFAULT_DATE,
                            "Cancelled"))
                    .thenReturn(2L);

            // Act + Assert
            assertFalse(conflictService.exceedsDailyLimit(
                    ScheduledVisitFixtures.DEFAULT_CAREGIVER_ID,
                    ScheduledVisitFixtures.DEFAULT_DATE),
                    "Two visits must not exceed the default daily limit of 8.");
        }

        @Test
        @DisplayName("analyzeConflicts flags caregiver conflict using overlappingVisit fixture")
        void analyzeConflictsFlagsCaregiverConflictFromFixture() {
            // Arrange: an existing visit blocks the caregiver's 10:00 slot.
            ScheduledVisit existing = ScheduledVisitFixtures.basicScheduledVisit();
            when(scheduledVisitRepository
                    .findByCaregiverIdAndScheduledDate(
                            ScheduledVisitFixtures.DEFAULT_CAREGIVER_ID,
                            ScheduledVisitFixtures.DEFAULT_DATE))
                    .thenReturn(List.of(existing));
            when(scheduledVisitRepository
                    .findByPatientId(ScheduledVisitFixtures.DEFAULT_PATIENT_ID))
                    .thenReturn(List.of());
            when(scheduledVisitRepository
                    .countByCaregiverIdAndScheduledDateAndStatusNot(
                            ScheduledVisitFixtures.DEFAULT_CAREGIVER_ID,
                            ScheduledVisitFixtures.DEFAULT_DATE,
                            "Cancelled"))
                    .thenReturn(1L);

            // Act: the overlapping fixture starts 30 min into the existing window.
            ScheduledVisit incoming = ScheduledVisitFixtures.overlappingVisit(2L);
            ScheduleConflictService.ConflictSummary summary = conflictService.analyzeConflicts(
                    incoming.getCaregiverId(),
                    incoming.getPatientId(),
                    ScheduledVisitFixtures.DEFAULT_DATE,
                    incoming.getScheduledTime(),
                    incoming.getDurationMinutes());

            // Assert: summary reflects caregiver conflict and at least one warning.
            assertTrue(summary.hasConflicts(),
                    "analyzeConflicts must detect the caregiver time overlap.");
            assertFalse(summary.getCaregiverConflicts().isEmpty(),
                    "Caregiver conflict list must be populated.");
            assertTrue(summary.hasWarnings(),
                    "A caregiver conflict must produce at least one warning.");
        }
    }
}
