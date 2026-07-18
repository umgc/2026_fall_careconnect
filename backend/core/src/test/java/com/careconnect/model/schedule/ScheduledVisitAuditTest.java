package com.careconnect.model.schedule;

// Tests for ScheduledVisitAudit entity.
// Covers construction, field access, equals/hashCode, and all audit actions.

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("ScheduledVisitAudit entity")
class ScheduledVisitAuditTest {

    @Test
    @DisplayName("no-arg constructor creates instance with null fields")
    void noArgConstructor() {
        // Arrange + Act
        ScheduledVisitAudit audit = new ScheduledVisitAudit();

        // Assert
        assertNull(audit.getId());
        assertNull(audit.getVisitId());
        assertNull(audit.getAction());
        assertNull(audit.getChangedField());
        assertNull(audit.getOldValue());
        assertNull(audit.getNewValue());
        assertNull(audit.getChangedAt());
        assertNull(audit.getChangedBy());
    }

    @Test
    @DisplayName("all-args constructor populates every field")
    void allArgsConstructor() {
        // Arrange
        LocalDateTime now = LocalDateTime.of(2026, 3, 17, 12, 0, 0);

        // Act
        ScheduledVisitAudit audit = new ScheduledVisitAudit(
                1L, 100L, "UPDATED", "scheduledTime",
                "10:00", "11:00", now, "admin@test.com");

        // Assert
        assertEquals(1L, audit.getId());
        assertEquals(100L, audit.getVisitId());
        assertEquals("UPDATED", audit.getAction());
        assertEquals("scheduledTime", audit.getChangedField());
        assertEquals("10:00", audit.getOldValue());
        assertEquals("11:00", audit.getNewValue());
        assertEquals(now, audit.getChangedAt());
        assertEquals("admin@test.com", audit.getChangedBy());
    }

    @Test
    @DisplayName("setters update all fields")
    void settersWork() {
        // Arrange
        ScheduledVisitAudit audit = new ScheduledVisitAudit();
        LocalDateTime now = LocalDateTime.now();

        // Act
        audit.setId(5L);
        audit.setVisitId(200L);
        audit.setAction("CREATED");
        audit.setChangedField(null);
        audit.setOldValue(null);
        audit.setNewValue("{\"id\":200}");
        audit.setChangedAt(now);
        audit.setChangedBy("system");

        // Assert
        assertEquals(5L, audit.getId());
        assertEquals(200L, audit.getVisitId());
        assertEquals("CREATED", audit.getAction());
        assertNull(audit.getChangedField());
        assertNull(audit.getOldValue());
        assertEquals("{\"id\":200}", audit.getNewValue());
        assertEquals(now, audit.getChangedAt());
        assertEquals("system", audit.getChangedBy());
    }

    @Test
    @DisplayName("CREATED action has null changedField and oldValue")
    void createdAction() {
        // Arrange + Act
        ScheduledVisitAudit audit = new ScheduledVisitAudit(
                1L, 100L, "CREATED", null, null, "{json}", LocalDateTime.now(), "user1");

        // Assert
        assertEquals("CREATED", audit.getAction());
        assertNull(audit.getChangedField());
        assertNull(audit.getOldValue());
        assertNotNull(audit.getNewValue());
    }

    @Test
    @DisplayName("DELETED action stores full_record with old value")
    void deletedAction() {
        // Arrange + Act
        ScheduledVisitAudit audit = new ScheduledVisitAudit(
                2L, 100L, "DELETED", "full_record", "{old_json}", "",
                LocalDateTime.now(), "admin");

        // Assert
        assertEquals("DELETED", audit.getAction());
        assertEquals("full_record", audit.getChangedField());
        assertNotNull(audit.getOldValue());
        assertEquals("", audit.getNewValue());
    }

    @Test
    @DisplayName("UPDATED action stores field name with old and new values")
    void updatedAction() {
        // Arrange + Act
        ScheduledVisitAudit audit = new ScheduledVisitAudit(
                3L, 100L, "UPDATED", "priority", "Normal", "Urgent",
                LocalDateTime.now(), "caregiver1");

        // Assert
        assertEquals("UPDATED", audit.getAction());
        assertEquals("priority", audit.getChangedField());
        assertEquals("Normal", audit.getOldValue());
        assertEquals("Urgent", audit.getNewValue());
    }

    @Test
    @DisplayName("equals compares by all fields")
    void equalsAndHashCode() {
        // Arrange
        LocalDateTime now = LocalDateTime.of(2026, 3, 17, 12, 0);
        ScheduledVisitAudit a = new ScheduledVisitAudit(
                1L, 100L, "UPDATED", "notes", "old", "new", now, "admin");
        ScheduledVisitAudit b = new ScheduledVisitAudit(
                1L, 100L, "UPDATED", "notes", "old", "new", now, "admin");

        // Assert
        assertEquals(a, b);
        assertEquals(a.hashCode(), b.hashCode());
    }

    @Test
    @DisplayName("not equal when fields differ")
    void notEqual() {
        // Arrange
        LocalDateTime now = LocalDateTime.now();
        ScheduledVisitAudit a = new ScheduledVisitAudit(
                1L, 100L, "UPDATED", "notes", "old", "new", now, "admin");
        ScheduledVisitAudit b = new ScheduledVisitAudit(
                2L, 100L, "UPDATED", "notes", "old", "new", now, "admin");

        // Assert
        assertNotEquals(a, b);
    }
}
