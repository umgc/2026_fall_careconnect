package com.careconnect.service.schedule;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.repository.schedule.ScheduledVisitRepository;
import com.careconnect.service.schedule.ScheduleConflictService.ConflictSummary;

/**
 * Unit tests for {@link ScheduleConflictService}.
 *
 * <p>All repository dependencies are mocked with Mockito so the service's
 * business logic is validated in isolation.</p>
 */
class ScheduleConflictServiceTest {

    @Mock
    private ScheduledVisitRepository scheduledVisitRepository;

    @InjectMocks
    private ScheduleConflictService conflictService;

    private static final Long CAREGIVER_ID = 1L;
    private static final Long PATIENT_ID = 10L;
    private static final LocalDate TEST_DATE = LocalDate.of(2026, 3, 17);

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    // ========================================================================
    // Helper methods
    // ========================================================================

    private ScheduledVisit createVisit(
            Long id, LocalTime startTime, int durationMinutes, String status) {
        ScheduledVisit visit = new ScheduledVisit();
        visit.setId(id);
        visit.setCaregiverId(CAREGIVER_ID);
        visit.setPatientId(PATIENT_ID);
        visit.setScheduledDate(TEST_DATE);
        visit.setScheduledTime(startTime);
        visit.setDurationMinutes(durationMinutes);
        visit.setStatus(status);
        visit.setServiceType("General Care");
        visit.setPriority("Normal");
        return visit;
    }

    // ========================================================================
    // detectCaregiverConflicts
    // ========================================================================

    @Nested
    @DisplayName("detectCaregiverConflicts")
    class DetectCaregiverConflicts {

        @Test
        @DisplayName("should return overlapping visits when times overlap")
        void shouldReturnOverlappingVisits() {
            // Existing visit: 10:00 - 11:00
            ScheduledVisit existing = createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(existing));

            // New visit: 10:30 - 11:30 (overlaps with existing)
            List<ScheduledVisit> conflicts = conflictService.detectCaregiverConflicts(
                    CAREGIVER_ID, TEST_DATE, LocalTime.of(10, 30), 60);

            assertEquals(1, conflicts.size());
            assertEquals(1L, conflicts.get(0).getId());
        }

        @Test
        @DisplayName("should return empty list when no conflicts exist")
        void shouldReturnEmptyListWhenNoConflicts() {
            // Existing visit: 10:00 - 11:00
            ScheduledVisit existing = createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(existing));

            // New visit: 12:00 - 13:00 (no overlap)
            List<ScheduledVisit> conflicts = conflictService.detectCaregiverConflicts(
                    CAREGIVER_ID, TEST_DATE, LocalTime.of(12, 0), 60);

            assertTrue(conflicts.isEmpty());
        }

        @Test
        @DisplayName("should return empty list when no existing visits")
        void shouldReturnEmptyListWhenNoExistingVisits() {
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(Collections.emptyList());

            List<ScheduledVisit> conflicts = conflictService.detectCaregiverConflicts(
                    CAREGIVER_ID, TEST_DATE, LocalTime.of(10, 0), 60);

            assertTrue(conflicts.isEmpty());
        }

        @Test
        @DisplayName("should exclude cancelled visits from conflict detection")
        void shouldExcludeCancelledVisits() {
            ScheduledVisit cancelled = createVisit(1L, LocalTime.of(10, 0), 60, "Cancelled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(cancelled));

            List<ScheduledVisit> conflicts = conflictService.detectCaregiverConflicts(
                    CAREGIVER_ID, TEST_DATE, LocalTime.of(10, 0), 60);

            assertTrue(conflicts.isEmpty());
        }

        @Test
        @DisplayName("should exclude visits with null status")
        void shouldExcludeVisitsWithNullStatus() {
            ScheduledVisit nullStatus = createVisit(1L, LocalTime.of(10, 0), 60, null);
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(nullStatus));

            List<ScheduledVisit> conflicts = conflictService.detectCaregiverConflicts(
                    CAREGIVER_ID, TEST_DATE, LocalTime.of(10, 0), 60);

            assertTrue(conflicts.isEmpty());
        }

        @Test
        @DisplayName("should not conflict when new visit ends exactly at existing visit start")
        void shouldNotConflictWhenAdjacentBefore() {
            // Existing visit: 11:00 - 12:00
            ScheduledVisit existing = createVisit(1L, LocalTime.of(11, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(existing));

            // New visit: 10:00 - 11:00 (ends exactly when existing starts)
            List<ScheduledVisit> conflicts = conflictService.detectCaregiverConflicts(
                    CAREGIVER_ID, TEST_DATE, LocalTime.of(10, 0), 60);

            assertTrue(conflicts.isEmpty());
        }

        @Test
        @DisplayName("should not conflict when new visit starts exactly at existing visit end")
        void shouldNotConflictWhenAdjacentAfter() {
            // Existing visit: 10:00 - 11:00
            ScheduledVisit existing = createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(existing));

            // New visit: 11:00 - 12:00 (starts exactly when existing ends)
            List<ScheduledVisit> conflicts = conflictService.detectCaregiverConflicts(
                    CAREGIVER_ID, TEST_DATE, LocalTime.of(11, 0), 60);

            assertTrue(conflicts.isEmpty());
        }

        @Test
        @DisplayName("should detect conflict when new visit completely contains existing visit")
        void shouldDetectConflictWhenNewContainsExisting() {
            // Existing visit: 10:00 - 11:00
            ScheduledVisit existing = createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(existing));

            // New visit: 9:00 - 12:00 (contains existing)
            List<ScheduledVisit> conflicts = conflictService.detectCaregiverConflicts(
                    CAREGIVER_ID, TEST_DATE, LocalTime.of(9, 0), 180);

            assertEquals(1, conflicts.size());
        }

        @Test
        @DisplayName("should detect multiple overlapping visits")
        void shouldDetectMultipleOverlaps() {
            ScheduledVisit visit1 = createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled");
            ScheduledVisit visit2 = createVisit(2L, LocalTime.of(10, 30), 60, "In Progress");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(visit1, visit2));

            // New visit: 10:00 - 12:00 (overlaps both)
            List<ScheduledVisit> conflicts = conflictService.detectCaregiverConflicts(
                    CAREGIVER_ID, TEST_DATE, LocalTime.of(10, 0), 120);

            assertEquals(2, conflicts.size());
        }
    }

    // ========================================================================
    // detectPatientConflicts
    // ========================================================================

    @Nested
    @DisplayName("detectPatientConflicts")
    class DetectPatientConflicts {

        @Test
        @DisplayName("should return overlapping visits for the same patient")
        void shouldReturnOverlappingVisits() {
            ScheduledVisit existing = createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(List.of(existing));

            List<ScheduledVisit> conflicts = conflictService.detectPatientConflicts(
                    PATIENT_ID, TEST_DATE, LocalTime.of(10, 30), 60);

            assertEquals(1, conflicts.size());
        }

        @Test
        @DisplayName("should return empty list when no patient conflicts exist")
        void shouldReturnEmptyListWhenNoConflicts() {
            ScheduledVisit existing = createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(List.of(existing));

            List<ScheduledVisit> conflicts = conflictService.detectPatientConflicts(
                    PATIENT_ID, TEST_DATE, LocalTime.of(12, 0), 60);

            assertTrue(conflicts.isEmpty());
        }

        @Test
        @DisplayName("should return empty list when no visits for patient")
        void shouldReturnEmptyListWhenNoVisits() {
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(Collections.emptyList());

            List<ScheduledVisit> conflicts = conflictService.detectPatientConflicts(
                    PATIENT_ID, TEST_DATE, LocalTime.of(10, 0), 60);

            assertTrue(conflicts.isEmpty());
        }

        @Test
        @DisplayName("should exclude cancelled visits from patient conflict detection")
        void shouldExcludeCancelledVisits() {
            ScheduledVisit cancelled = createVisit(1L, LocalTime.of(10, 0), 60, "Cancelled");
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(List.of(cancelled));

            List<ScheduledVisit> conflicts = conflictService.detectPatientConflicts(
                    PATIENT_ID, TEST_DATE, LocalTime.of(10, 0), 60);

            assertTrue(conflicts.isEmpty());
        }

        @Test
        @DisplayName("should only match visits on the same date")
        void shouldOnlyMatchVisitsOnSameDate() {
            ScheduledVisit differentDate = createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled");
            differentDate.setScheduledDate(TEST_DATE.plusDays(1));
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(List.of(differentDate));

            List<ScheduledVisit> conflicts = conflictService.detectPatientConflicts(
                    PATIENT_ID, TEST_DATE, LocalTime.of(10, 0), 60);

            assertTrue(conflicts.isEmpty());
        }

        @Test
        @DisplayName("should not conflict when adjacent patient visits")
        void shouldNotConflictWhenAdjacent() {
            ScheduledVisit existing = createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(List.of(existing));

            // New visit starts exactly when existing ends
            List<ScheduledVisit> conflicts = conflictService.detectPatientConflicts(
                    PATIENT_ID, TEST_DATE, LocalTime.of(11, 0), 60);

            assertTrue(conflicts.isEmpty());
        }

        @Test
        @DisplayName("should not conflict when new visit ends exactly at existing visit start")
        void shouldNotConflictWhenNewVisitEndsAtExistingStart() {
            // Existing visit 10:00-11:00; new visit 9:00-10:00 ends exactly when
            // the existing visit starts. startMinutes < visitEndMinutes is true,
            // but endMinutes > visitStartMinutes is false — the combination the
            // adjacent-after-only test above never exercises.
            ScheduledVisit existing = createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(List.of(existing));

            List<ScheduledVisit> conflicts = conflictService.detectPatientConflicts(
                    PATIENT_ID, TEST_DATE, LocalTime.of(9, 0), 60);

            assertTrue(conflicts.isEmpty());
        }

        @Test
        @DisplayName("should exclude visits with null status")
        void shouldExcludeNullStatusVisits() {
            ScheduledVisit nullStatus = createVisit(1L, LocalTime.of(10, 0), 60, null);
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(List.of(nullStatus));

            List<ScheduledVisit> conflicts = conflictService.detectPatientConflicts(
                    PATIENT_ID, TEST_DATE, LocalTime.of(10, 0), 60);

            assertTrue(conflicts.isEmpty());
        }
    }

    // ========================================================================
    // exceedsDailyLimit (default limit)
    // ========================================================================

    @Nested
    @DisplayName("exceedsDailyLimit (default)")
    class ExceedsDailyLimitDefault {

        @Test
        @DisplayName("should return true when at daily limit of 8")
        void shouldReturnTrueWhenAtLimit() {
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(8L);

            assertTrue(conflictService.exceedsDailyLimit(CAREGIVER_ID, TEST_DATE));
        }

        @Test
        @DisplayName("should return true when over daily limit")
        void shouldReturnTrueWhenOverLimit() {
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(10L);

            assertTrue(conflictService.exceedsDailyLimit(CAREGIVER_ID, TEST_DATE));
        }

        @Test
        @DisplayName("should return false when below daily limit")
        void shouldReturnFalseWhenBelowLimit() {
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(5L);

            assertFalse(conflictService.exceedsDailyLimit(CAREGIVER_ID, TEST_DATE));
        }

        @Test
        @DisplayName("should return false when no visits scheduled")
        void shouldReturnFalseWhenNoVisits() {
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(0L);

            assertFalse(conflictService.exceedsDailyLimit(CAREGIVER_ID, TEST_DATE));
        }

        @Test
        @DisplayName("should return false when one below daily limit")
        void shouldReturnFalseWhenOneBelowLimit() {
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(7L);

            assertFalse(conflictService.exceedsDailyLimit(CAREGIVER_ID, TEST_DATE));
        }
    }

    // ========================================================================
    // exceedsDailyLimit (custom limit)
    // ========================================================================

    @Nested
    @DisplayName("exceedsDailyLimit (custom limit)")
    class ExceedsDailyLimitCustom {

        @Test
        @DisplayName("should return true when at custom limit")
        void shouldReturnTrueWhenAtCustomLimit() {
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(5L);

            assertTrue(conflictService.exceedsDailyLimit(CAREGIVER_ID, TEST_DATE, 5));
        }

        @Test
        @DisplayName("should return true when over custom limit")
        void shouldReturnTrueWhenOverCustomLimit() {
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(6L);

            assertTrue(conflictService.exceedsDailyLimit(CAREGIVER_ID, TEST_DATE, 5));
        }

        @Test
        @DisplayName("should return false when below custom limit")
        void shouldReturnFalseWhenBelowCustomLimit() {
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(3L);

            assertFalse(conflictService.exceedsDailyLimit(CAREGIVER_ID, TEST_DATE, 5));
        }
    }

    // ========================================================================
    // getTotalDurationForDay
    // ========================================================================

    @Nested
    @DisplayName("getTotalDurationForDay")
    class GetTotalDurationForDay {

        @Test
        @DisplayName("should sum durations of non-cancelled visits")
        void shouldSumDurationsOfActivVisits() {
            ScheduledVisit visit1 = createVisit(1L, LocalTime.of(9, 0), 60, "Scheduled");
            ScheduledVisit visit2 = createVisit(2L, LocalTime.of(11, 0), 45, "In Progress");
            ScheduledVisit cancelled = createVisit(3L, LocalTime.of(14, 0), 30, "Cancelled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(visit1, visit2, cancelled));

            int total = conflictService.getTotalDurationForDay(CAREGIVER_ID, TEST_DATE);

            assertEquals(105, total);
        }

        @Test
        @DisplayName("should return zero when no visits exist")
        void shouldReturnZeroWhenNoVisits() {
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(Collections.emptyList());

            int total = conflictService.getTotalDurationForDay(CAREGIVER_ID, TEST_DATE);

            assertEquals(0, total);
        }

        @Test
        @DisplayName("should return zero when all visits are cancelled")
        void shouldReturnZeroWhenAllCancelled() {
            ScheduledVisit cancelled1 = createVisit(1L, LocalTime.of(9, 0), 60, "Cancelled");
            ScheduledVisit cancelled2 = createVisit(2L, LocalTime.of(11, 0), 45, "Cancelled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(cancelled1, cancelled2));

            int total = conflictService.getTotalDurationForDay(CAREGIVER_ID, TEST_DATE);

            assertEquals(0, total);
        }

        @Test
        @DisplayName("should exclude visits with null status")
        void shouldExcludeNullStatusVisits() {
            ScheduledVisit scheduled = createVisit(1L, LocalTime.of(9, 0), 60, "Scheduled");
            ScheduledVisit nullStatus = createVisit(2L, LocalTime.of(11, 0), 45, null);
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(scheduled, nullStatus));

            int total = conflictService.getTotalDurationForDay(CAREGIVER_ID, TEST_DATE);

            assertEquals(60, total);
        }
    }

    // ========================================================================
    // exceedsDailyHours
    // ========================================================================

    @Nested
    @DisplayName("exceedsDailyHours")
    class ExceedsDailyHours {

        @Test
        @DisplayName("should return true when adding visit exceeds max hours")
        void shouldReturnTrueWhenExceedsMaxHours() {
            // Existing: 9 hours (540 minutes)
            ScheduledVisit visit1 = createVisit(1L, LocalTime.of(8, 0), 540, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(visit1));

            // Adding 90 minutes with max 10 hours => 540 + 90 = 630 > 600
            assertTrue(conflictService.exceedsDailyHours(CAREGIVER_ID, TEST_DATE, 90, 10));
        }

        @Test
        @DisplayName("should return false when within max hours")
        void shouldReturnFalseWhenWithinMaxHours() {
            ScheduledVisit visit1 = createVisit(1L, LocalTime.of(8, 0), 300, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(visit1));

            // 300 + 60 = 360 < 600 (10 hours)
            assertFalse(conflictService.exceedsDailyHours(CAREGIVER_ID, TEST_DATE, 60, 10));
        }

        @Test
        @DisplayName("should return false when exactly at max hours")
        void shouldReturnFalseWhenExactlyAtMaxHours() {
            ScheduledVisit visit1 = createVisit(1L, LocalTime.of(8, 0), 540, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(visit1));

            // 540 + 60 = 600 == 600 (exactly at limit, not exceeding)
            assertFalse(conflictService.exceedsDailyHours(CAREGIVER_ID, TEST_DATE, 60, 10));
        }

        @Test
        @DisplayName("should return false when no existing visits and new visit within limit")
        void shouldReturnFalseWhenNoExistingVisits() {
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(Collections.emptyList());

            assertFalse(conflictService.exceedsDailyHours(CAREGIVER_ID, TEST_DATE, 60, 10));
        }
    }

    // ========================================================================
    // findNextAvailableSlot
    // ========================================================================

    @Nested
    @DisplayName("findNextAvailableSlot")
    class FindNextAvailableSlot {

        @Test
        @DisplayName("should return 8:00 AM when no visits exist")
        void shouldReturnEarliestSlotWhenNoVisits() {
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(Collections.emptyList());

            LocalTime slot = conflictService.findNextAvailableSlot(CAREGIVER_ID, TEST_DATE, 60);

            assertEquals(LocalTime.of(8, 0), slot);
        }

        @Test
        @DisplayName("should return slot after existing visit")
        void shouldReturnSlotAfterExistingVisit() {
            ScheduledVisit visit = createVisit(1L, LocalTime.of(8, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(new ArrayList<>(List.of(visit)));

            LocalTime slot = conflictService.findNextAvailableSlot(CAREGIVER_ID, TEST_DATE, 60);

            assertEquals(LocalTime.of(9, 0), slot);
        }

        @Test
        @DisplayName("should find gap between existing visits")
        void shouldFindGapBetweenVisits() {
            ScheduledVisit visit1 = createVisit(1L, LocalTime.of(8, 0), 60, "Scheduled");
            ScheduledVisit visit2 = createVisit(2L, LocalTime.of(11, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(new ArrayList<>(List.of(visit1, visit2)));

            // 30 minute visit can fit in the gap between 9:00 and 11:00
            LocalTime slot = conflictService.findNextAvailableSlot(CAREGIVER_ID, TEST_DATE, 30);

            assertEquals(LocalTime.of(9, 0), slot);
        }

        @Test
        @DisplayName("should return null when no slot available before 6 PM")
        void shouldReturnNullWhenNoSlotAvailable() {
            // Visits from 8:00 to 17:30
            ScheduledVisit visit1 = createVisit(1L, LocalTime.of(8, 0), 570, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(new ArrayList<>(List.of(visit1)));

            // Need 60 minutes but only 30 minutes left before 18:00
            LocalTime slot = conflictService.findNextAvailableSlot(CAREGIVER_ID, TEST_DATE, 60);

            assertNull(slot);
        }

        @Test
        @DisplayName("should return slot at end of day when it fits before 6 PM")
        void shouldReturnSlotAtEndOfDayWhenFits() {
            ScheduledVisit visit = createVisit(1L, LocalTime.of(8, 0), 540, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(new ArrayList<>(List.of(visit)));

            // Visit ends at 17:00, 30 min fits before 18:00
            LocalTime slot = conflictService.findNextAvailableSlot(CAREGIVER_ID, TEST_DATE, 30);

            assertEquals(LocalTime.of(17, 0), slot);
        }

        @Test
        @DisplayName("should handle multiple back-to-back visits")
        void shouldHandleBackToBackVisits() {
            ScheduledVisit visit1 = createVisit(1L, LocalTime.of(8, 0), 60, "Scheduled");
            ScheduledVisit visit2 = createVisit(2L, LocalTime.of(9, 0), 60, "Scheduled");
            ScheduledVisit visit3 = createVisit(3L, LocalTime.of(10, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(new ArrayList<>(List.of(visit1, visit2, visit3)));

            LocalTime slot = conflictService.findNextAvailableSlot(CAREGIVER_ID, TEST_DATE, 60);

            assertEquals(LocalTime.of(11, 0), slot);
        }
    }

    // ========================================================================
    // analyzeConflicts
    // ========================================================================

    @Nested
    @DisplayName("analyzeConflicts")
    class AnalyzeConflicts {

        @Test
        @DisplayName("should return summary with no conflicts when schedule is clear")
        void shouldReturnNoConflicts() {
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(Collections.emptyList());
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(Collections.emptyList());
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(0L);

            ConflictSummary summary = conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, LocalTime.of(10, 0), 60);

            assertFalse(summary.hasConflicts());
            assertFalse(summary.hasWarnings());
            assertFalse(summary.isExceedsDailyLimit());
            assertFalse(summary.isExceedsDailyHours());
            assertTrue(summary.getWarnings().isEmpty());
        }

        @Test
        @DisplayName("should detect caregiver conflicts and add warning")
        void shouldDetectCaregiverConflicts() {
            ScheduledVisit existing = createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(existing));
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(Collections.emptyList());
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(1L);

            ConflictSummary summary = conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, LocalTime.of(10, 30), 60);

            assertTrue(summary.hasConflicts());
            assertTrue(summary.hasWarnings());
            assertEquals(1, summary.getCaregiverConflicts().size());
            assertTrue(summary.getPatientConflicts().isEmpty());
        }

        @Test
        @DisplayName("should detect patient conflicts and add warning")
        void shouldDetectPatientConflicts() {
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(Collections.emptyList());
            ScheduledVisit patientVisit = createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(List.of(patientVisit));
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(0L);

            ConflictSummary summary = conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, LocalTime.of(10, 30), 60);

            assertTrue(summary.hasConflicts());
            assertTrue(summary.hasWarnings());
            assertEquals(1, summary.getPatientConflicts().size());
            assertTrue(summary.getCaregiverConflicts().isEmpty());
        }

        @Test
        @DisplayName("should flag daily limit exceeded and add warning")
        void shouldFlagDailyLimitExceeded() {
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(Collections.emptyList());
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(Collections.emptyList());
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(8L);

            ConflictSummary summary = conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, LocalTime.of(10, 0), 60);

            assertTrue(summary.isExceedsDailyLimit());
            assertTrue(summary.hasWarnings());
            assertTrue(summary.getWarnings().stream()
                    .anyMatch(w -> w.contains("max visits")));
        }

        @Test
        @DisplayName("should flag daily hours exceeded and add warning")
        void shouldFlagDailyHoursExceeded() {
            // 9.5 hours existing + 1 hour new = 10.5 > 10
            ScheduledVisit longVisit = createVisit(1L, LocalTime.of(8, 0), 570, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(longVisit));
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(Collections.emptyList());
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(1L);

            ConflictSummary summary = conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, LocalTime.of(17, 30), 60);

            assertTrue(summary.isExceedsDailyHours());
            assertTrue(summary.hasWarnings());
            assertTrue(summary.getWarnings().stream()
                    .anyMatch(w -> w.contains("10 working hours")));
        }

        @Test
        @DisplayName("should accumulate multiple warnings")
        void shouldAccumulateMultipleWarnings() {
            // Overlapping caregiver visit + at daily limit + exceeds hours
            ScheduledVisit existing = createVisit(1L, LocalTime.of(10, 0), 570, "Scheduled");
            when(scheduledVisitRepository.findByCaregiverIdAndScheduledDate(CAREGIVER_ID, TEST_DATE))
                    .thenReturn(List.of(existing));
            ScheduledVisit patientVisit = createVisit(2L, LocalTime.of(10, 0), 60, "Scheduled");
            when(scheduledVisitRepository.findByPatientId(PATIENT_ID))
                    .thenReturn(List.of(patientVisit));
            when(scheduledVisitRepository.countByCaregiverIdAndScheduledDateAndStatusNot(
                    CAREGIVER_ID, TEST_DATE, "Cancelled")).thenReturn(8L);

            ConflictSummary summary = conflictService.analyzeConflicts(
                    CAREGIVER_ID, PATIENT_ID, TEST_DATE, LocalTime.of(10, 30), 60);

            assertTrue(summary.hasConflicts());
            assertTrue(summary.hasWarnings());
            assertTrue(summary.getWarnings().size() >= 3);
        }
    }

    // ========================================================================
    // ConflictSummary inner class
    // ========================================================================

    @Nested
    @DisplayName("ConflictSummary")
    class ConflictSummaryTests {

        @Test
        @DisplayName("should report no conflicts when both lists are empty")
        void shouldReportNoConflictsWhenEmpty() {
            ConflictSummary summary = new ConflictSummary();

            assertFalse(summary.hasConflicts());
        }

        @Test
        @DisplayName("should report conflicts when caregiver conflicts exist")
        void shouldReportConflictsWhenCaregiverConflictsExist() {
            ConflictSummary summary = new ConflictSummary();
            summary.setCaregiverConflicts(List.of(createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled")));

            assertTrue(summary.hasConflicts());
        }

        @Test
        @DisplayName("should report conflicts when patient conflicts exist")
        void shouldReportConflictsWhenPatientConflictsExist() {
            ConflictSummary summary = new ConflictSummary();
            summary.setPatientConflicts(List.of(createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled")));

            assertTrue(summary.hasConflicts());
        }

        @Test
        @DisplayName("should report conflicts when caregiverConflicts is null but patientConflicts has entries")
        void shouldReportConflictsWhenCaregiverConflictsNull() {
            // Exercises the caregiverConflicts == null branch of hasConflicts(),
            // which the default (non-null, empty-list) constructor never reaches.
            ConflictSummary summary = new ConflictSummary();
            summary.setCaregiverConflicts(null);
            summary.setPatientConflicts(List.of(createVisit(1L, LocalTime.of(10, 0), 60, "Scheduled")));

            assertTrue(summary.hasConflicts());
        }

        @Test
        @DisplayName("should report no conflicts when both conflict lists are null")
        void shouldReportNoConflictsWhenBothListsNull() {
            // Exercises the patientConflicts == null branch as well — reached
            // only once short-circuit evaluation gets past a null caregiverConflicts.
            ConflictSummary summary = new ConflictSummary();
            summary.setCaregiverConflicts(null);
            summary.setPatientConflicts(null);

            assertFalse(summary.hasConflicts());
        }

        @Test
        @DisplayName("should report no warnings when warnings list is empty")
        void shouldReportNoWarningsWhenEmpty() {
            ConflictSummary summary = new ConflictSummary();

            assertFalse(summary.hasWarnings());
        }

        @Test
        @DisplayName("should report warnings after addWarning is called")
        void shouldReportWarningsAfterAdd() {
            ConflictSummary summary = new ConflictSummary();
            summary.addWarning("Test warning");

            assertTrue(summary.hasWarnings());
            assertEquals(1, summary.getWarnings().size());
            assertEquals("Test warning", summary.getWarnings().get(0));
        }

        @Test
        @DisplayName("should accumulate multiple warnings")
        void shouldAccumulateWarnings() {
            ConflictSummary summary = new ConflictSummary();
            summary.addWarning("Warning 1");
            summary.addWarning("Warning 2");
            summary.addWarning("Warning 3");

            assertEquals(3, summary.getWarnings().size());
        }

        @Test
        @DisplayName("should initialize with defaults")
        void shouldInitializeWithDefaults() {
            ConflictSummary summary = new ConflictSummary();

            assertNotNull(summary.getCaregiverConflicts());
            assertTrue(summary.getCaregiverConflicts().isEmpty());
            assertNotNull(summary.getPatientConflicts());
            assertTrue(summary.getPatientConflicts().isEmpty());
            assertNotNull(summary.getWarnings());
            assertTrue(summary.getWarnings().isEmpty());
            assertFalse(summary.isExceedsDailyLimit());
            assertFalse(summary.isExceedsDailyHours());
        }

        @Test
        @DisplayName("should set and get exceedsDailyLimit")
        void shouldSetAndGetExceedsDailyLimit() {
            ConflictSummary summary = new ConflictSummary();
            summary.setExceedsDailyLimit(true);

            assertTrue(summary.isExceedsDailyLimit());
        }

        @Test
        @DisplayName("should set and get exceedsDailyHours")
        void shouldSetAndGetExceedsDailyHours() {
            ConflictSummary summary = new ConflictSummary();
            summary.setExceedsDailyHours(true);

            assertTrue(summary.isExceedsDailyHours());
        }
    }
}
