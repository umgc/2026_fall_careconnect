package com.careconnect.dto.schedule;

// Tests for all shift scheduling DTOs.
// Covers constructors, field access, equals/hashCode (Lombok @Data),
// and the ScheduledVisitResponse conversion constructor.

import com.careconnect.model.schedule.ScheduledVisit;
import com.careconnect.testsupport.fixtures.ScheduledVisitFixtures;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Shift Scheduling DTOs")
class ScheduleDtoTest {

    // ========================================================================
    // ScheduledVisitRequest
    // ========================================================================

    @Nested
    @DisplayName("ScheduledVisitRequest")
    class ScheduledVisitRequestTests {

        @Test
        @DisplayName("no-arg constructor creates instance with null fields")
        void noArgConstructor() {
            // Arrange + Act
            ScheduledVisitRequest req = new ScheduledVisitRequest();

            // Assert
            assertNull(req.getPatientId());
            assertNull(req.getServiceType());
            assertNull(req.getScheduledDate());
            assertNull(req.getScheduledTime());
            assertNull(req.getDurationMinutes());
            assertNull(req.getPriority());
            assertNull(req.getNotes());
        }

        @Test
        @DisplayName("all-args constructor populates every field")
        void allArgsConstructor() {
            // Arrange
            LocalDate date = LocalDate.of(2026, 3, 17);
            LocalTime time = LocalTime.of(10, 0);

            // Act
            ScheduledVisitRequest req = new ScheduledVisitRequest(
                    10L, "Personal Care", date, time, 60, "Normal", "Test notes");

            // Assert
            assertEquals(10L, req.getPatientId());
            assertEquals("Personal Care", req.getServiceType());
            assertEquals(date, req.getScheduledDate());
            assertEquals(time, req.getScheduledTime());
            assertEquals(60, req.getDurationMinutes());
            assertEquals("Normal", req.getPriority());
            assertEquals("Test notes", req.getNotes());
        }

        @Test
        @DisplayName("setters update fields")
        void settersWork() {
            // Arrange
            ScheduledVisitRequest req = new ScheduledVisitRequest();

            // Act
            req.setPatientId(5L);
            req.setServiceType("Skilled Nursing");
            req.setDurationMinutes(90);

            // Assert
            assertEquals(5L, req.getPatientId());
            assertEquals("Skilled Nursing", req.getServiceType());
            assertEquals(90, req.getDurationMinutes());
        }

        @Test
        @DisplayName("equals and hashCode based on field values")
        void equalsAndHashCode() {
            // Arrange
            LocalDate date = LocalDate.of(2026, 3, 17);
            LocalTime time = LocalTime.of(10, 0);
            ScheduledVisitRequest a = new ScheduledVisitRequest(
                    10L, "Personal Care", date, time, 60, "Normal", null);
            ScheduledVisitRequest b = new ScheduledVisitRequest(
                    10L, "Personal Care", date, time, 60, "Normal", null);

            // Assert
            assertEquals(a, b);
            assertEquals(a.hashCode(), b.hashCode());
        }
    }

    // ========================================================================
    // ScheduledVisitResponse
    // ========================================================================

    @Nested
    @DisplayName("ScheduledVisitResponse")
    class ScheduledVisitResponseTests {

        @Test
        @DisplayName("no-arg constructor creates empty response")
        void noArgConstructor() {
            ScheduledVisitResponse resp = new ScheduledVisitResponse();
            assertNull(resp.getId());
            assertNull(resp.getPatientName());
        }

        @Test
        @DisplayName("conversion constructor maps all fields from ScheduledVisit")
        void conversionConstructor() {
            // Arrange — use the shared fixture for a consistent baseline.
            ScheduledVisit visit = ScheduledVisitFixtures.basicScheduledVisit();
            visit.setCreatedAt(LocalDateTime.of(2026, 3, 17, 8, 0));
            visit.setUpdatedAt(LocalDateTime.of(2026, 3, 17, 9, 0));

            // Act
            ScheduledVisitResponse resp = new ScheduledVisitResponse(visit, "John Doe");

            // Assert
            assertEquals(visit.getId(), resp.getId());
            assertEquals(visit.getCaregiverId(), resp.getCaregiverId());
            assertEquals(visit.getPatientId(), resp.getPatientId());
            assertEquals("John Doe", resp.getPatientName());
            assertEquals(visit.getServiceType(), resp.getServiceType());
            assertEquals(visit.getScheduledDate(), resp.getScheduledDate());
            assertEquals(visit.getScheduledTime(), resp.getScheduledTime());
            assertEquals(visit.getDurationMinutes(), resp.getDurationMinutes());
            assertEquals(visit.getPriority(), resp.getPriority());
            assertEquals(visit.getNotes(), resp.getNotes());
            assertEquals(visit.getStatus(), resp.getStatus());
            assertEquals(visit.getCreatedAt(), resp.getCreatedAt());
            assertEquals(visit.getUpdatedAt(), resp.getUpdatedAt());
        }

        @Test
        @DisplayName("conversion constructor handles null patient name")
        void conversionWithNullName() {
            ScheduledVisit visit = ScheduledVisitFixtures.basicScheduledVisit();
            ScheduledVisitResponse resp = new ScheduledVisitResponse(visit, null);
            assertNull(resp.getPatientName());
        }
    }

    // ========================================================================
    // ScheduledVisitSummary
    // ========================================================================

    @Nested
    @DisplayName("ScheduledVisitSummary")
    class ScheduledVisitSummaryTests {

        @Test
        @DisplayName("all-args constructor populates counts")
        void allArgsConstructor() {
            ScheduledVisitSummary summary = new ScheduledVisitSummary(2, 3, 5, 10);
            assertEquals(2, summary.getOverdue());
            assertEquals(3, summary.getReady());
            assertEquals(5, summary.getUpcoming());
            assertEquals(10, summary.getTotalToday());
        }

        @Test
        @DisplayName("no-arg constructor defaults to zero")
        void noArgConstructor() {
            ScheduledVisitSummary summary = new ScheduledVisitSummary();
            assertEquals(0, summary.getOverdue());
            assertEquals(0, summary.getReady());
            assertEquals(0, summary.getUpcoming());
            assertEquals(0, summary.getTotalToday());
        }
    }

    // ========================================================================
    // ConflictCheckResponse
    // ========================================================================

    @Nested
    @DisplayName("ConflictCheckResponse")
    class ConflictCheckResponseTests {

        @Test
        @DisplayName("no-arg constructor creates empty response")
        void noArgConstructor() {
            ConflictCheckResponse resp = new ConflictCheckResponse();
            assertFalse(resp.isHasConflicts());
            assertFalse(resp.isExceedsDailyLimit());
            assertFalse(resp.isExceedsDailyHours());
        }

        @Test
        @DisplayName("all-args constructor populates all fields")
        void allArgsConstructor() {
            // Arrange
            List<String> messages = List.of("Overlap with visit 1");
            List<String> warnings = List.of("Daily limit exceeded");
            List<ScheduledVisitResponse> conflicts = List.of();

            // Act
            ConflictCheckResponse resp = new ConflictCheckResponse(
                    true, messages, warnings, conflicts, true, false);

            // Assert
            assertTrue(resp.isHasConflicts());
            assertEquals(1, resp.getConflictMessages().size());
            assertEquals("Overlap with visit 1", resp.getConflictMessages().get(0));
            assertEquals(1, resp.getWarnings().size());
            assertTrue(resp.isExceedsDailyLimit());
            assertFalse(resp.isExceedsDailyHours());
        }
    }

    // ========================================================================
    // ScheduledVisitAuditResponse
    // ========================================================================

    @Nested
    @DisplayName("ScheduledVisitAuditResponse")
    class ScheduledVisitAuditResponseTests {

        @Test
        @DisplayName("all-args constructor populates audit fields")
        void allArgsConstructor() {
            LocalDateTime now = LocalDateTime.of(2026, 3, 17, 12, 0);
            ScheduledVisitAuditResponse resp = new ScheduledVisitAuditResponse(
                    1L, 100L, "UPDATED", "scheduledTime",
                    "10:00", "11:00", now, "admin@test.com");

            assertEquals(1L, resp.getId());
            assertEquals(100L, resp.getVisitId());
            assertEquals("UPDATED", resp.getAction());
            assertEquals("scheduledTime", resp.getChangedField());
            assertEquals("10:00", resp.getOldValue());
            assertEquals("11:00", resp.getNewValue());
            assertEquals(now, resp.getChangedAt());
            assertEquals("admin@test.com", resp.getChangedBy());
        }

        @Test
        @DisplayName("no-arg constructor creates empty response")
        void noArgConstructor() {
            ScheduledVisitAuditResponse resp = new ScheduledVisitAuditResponse();
            assertNull(resp.getId());
            assertNull(resp.getAction());
        }
    }

    // ========================================================================
    // AuditDiffResponse
    // ========================================================================

    @Nested
    @DisplayName("AuditDiffResponse")
    class AuditDiffResponseTests {

        @Test
        @DisplayName("all-args constructor populates before/after snapshots")
        void allArgsConstructor() {
            ScheduledVisitResponse before = new ScheduledVisitResponse();
            before.setId(1L);
            ScheduledVisitResponse after = new ScheduledVisitResponse();
            after.setId(1L);

            LocalDateTime now = LocalDateTime.of(2026, 3, 17, 12, 0);
            AuditDiffResponse diff = new AuditDiffResponse(
                    before, after, "scheduledDate", "UPDATED", "admin", now);

            assertNotNull(diff.getBefore());
            assertNotNull(diff.getAfter());
            assertEquals("scheduledDate", diff.getChangedField());
            assertEquals("UPDATED", diff.getAction());
            assertEquals("admin", diff.getChangedBy());
            assertEquals(now, diff.getChangedAt());
        }

        @Test
        @DisplayName("before can be null for CREATED actions")
        void beforeNullForCreated() {
            AuditDiffResponse diff = new AuditDiffResponse(
                    null, new ScheduledVisitResponse(), null, "CREATED", "system",
                    LocalDateTime.now());
            assertNull(diff.getBefore());
            assertNotNull(diff.getAfter());
        }
    }

    // ========================================================================
    // CalendarViewDto
    // ========================================================================

    @Nested
    @DisplayName("CalendarViewDto")
    class CalendarViewDtoTests {

        @Test
        @DisplayName("setters and getters work")
        void settersAndGetters() {
            CalendarViewDto dto = new CalendarViewDto();
            LocalDate date = LocalDate.of(2026, 3, 17);
            dto.setDate(date);
            dto.setVisitCount(3);
            dto.setTotalDuration(180);
            dto.setVisits(List.of());
            dto.setConflict_warnings(List.of("Daily limit"));

            assertEquals(date, dto.getDate());
            assertEquals(3, dto.getVisitCount());
            assertEquals(180, dto.getTotalDuration());
            assertTrue(dto.getVisits().isEmpty());
            assertEquals(1, dto.getConflict_warnings().size());
        }
    }

    // ========================================================================
    // MonthViewDto
    // ========================================================================

    @Nested
    @DisplayName("MonthViewDto")
    class MonthViewDtoTests {

        @Test
        @DisplayName("setters and getters work")
        void settersAndGetters() {
            MonthViewDto dto = new MonthViewDto();
            dto.setMonth(3);
            dto.setYear(2026);
            dto.setDays(Map.of());

            assertEquals(3, dto.getMonth());
            assertEquals(2026, dto.getYear());
            assertNotNull(dto.getDays());
            assertTrue(dto.getDays().isEmpty());
        }
    }
}
