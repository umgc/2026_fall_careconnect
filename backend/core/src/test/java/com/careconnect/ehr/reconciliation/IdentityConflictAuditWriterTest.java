package com.careconnect.ehr.reconciliation;

import com.careconnect.ehr.reconciliation.IdentityConflictAuditWriter.Outcome;
import com.careconnect.ehr.reconciliation.IdentityConflictAuditWriter.PendingConflict;
import com.careconnect.ehr.reconciliation.IdentityConflictAuditWriter.ResolvedBy;
import com.careconnect.model.ehr.EhrConflictResolver;
import com.careconnect.model.ehr.EhrConflictStatus;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.Arrays;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The audit-writer port's own types. The library's enums have to line up with what the JPA layer can
 * store, since {@code JpaIdentityConflictAuditWriter} maps one to the other; a value added on one side
 * only would have nowhere to go.
 */
class IdentityConflictAuditWriterTest {

    @Test
    @DisplayName("every Outcome has a stored status of the same name (and PENDING is the only status that isn't an outcome)")
    void outcomesMatchStoredStatuses() {
        for (final Outcome outcome : Outcome.values()) {
            assertThat(EhrConflictStatus.valueOf(outcome.name())).isNotNull();
        }
        assertThat(Arrays.stream(EhrConflictStatus.values()).map(Enum::name))
                .containsExactlyInAnyOrder("PENDING", "ACCEPTED", "REJECTED");
    }

    @Test
    @DisplayName("every ResolvedBy has a stored resolver of the same name, and nothing else")
    void resolversMatchStoredResolvers() {
        assertThat(Arrays.stream(ResolvedBy.values()).map(Enum::name))
                .containsExactlyInAnyOrderElementsOf(
                        Arrays.stream(EhrConflictResolver.values()).map(Enum::name).toList());
    }

    @Test
    @DisplayName("a PendingConflict compares by value")
    void pendingConflictValueEquality() {
        final Instant at = Instant.parse("2026-09-01T10:00:00Z");

        assertThat(new PendingConflict(9L, "1950-03-09", "1950-03-10", at, at))
                .isEqualTo(new PendingConflict(9L, "1950-03-09", "1950-03-10", at, at))
                .isNotEqualTo(new PendingConflict(8L, "1950-03-09", "1950-03-10", at, at));
    }
}
