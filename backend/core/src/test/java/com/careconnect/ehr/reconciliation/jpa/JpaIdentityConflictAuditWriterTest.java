package com.careconnect.ehr.reconciliation.jpa;

import com.careconnect.ehr.reconciliation.IdentityConflictAuditWriter.Outcome;
import com.careconnect.ehr.reconciliation.IdentityConflictAuditWriter.PendingConflict;
import com.careconnect.ehr.reconciliation.IdentityConflictAuditWriter.ResolvedBy;
import com.careconnect.ehr.reconciliation.IdentityFieldNames;
import com.careconnect.model.ehr.EhrConflictResolver;
import com.careconnect.model.ehr.EhrConflictStatus;
import com.careconnect.model.ehr.EhrIdentityConflict;
import com.careconnect.repository.ehr.EhrIdentityConflictRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Instant;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The JPA audit writer on its own, with the repository mocked. Its queries and constraints against real
 * PostgreSQL are covered by {@code JpaContractPostgresTest}; this covers its own logic: the transaction
 * guard, how outcomes map to stored status and resolver, and resolving a pending row in place.
 * <p>
 * Test IDs TC-EHR-CONF-007..015 are permanent. Never renumber, never reuse.
 */
class JpaIdentityConflictAuditWriterTest {

    private static final String DOB = IdentityFieldNames.DATE_OF_BIRTH;
    private static final Instant SOURCE_UPDATED = Instant.parse("2026-09-01T10:00:00Z");
    private static final Instant NOW = Instant.parse("2026-10-08T12:00:00Z");

    private EhrIdentityConflictRepository repository;
    private JpaIdentityConflictAuditWriter writer;

    @BeforeEach
    void setUp() {
        repository = mock(EhrIdentityConflictRepository.class);
        writer = new JpaIdentityConflictAuditWriter(repository);
        TransactionSynchronizationManager.setActualTransactionActive(true);
    }

    @AfterEach
    void tearDown() {
        TransactionSynchronizationManager.setActualTransactionActive(false);
    }

    private EhrIdentityConflict saved() {
        final ArgumentCaptor<EhrIdentityConflict> row = ArgumentCaptor.forClass(EhrIdentityConflict.class);
        verify(repository).saveAndFlush(row.capture());
        return row.getValue();
    }

    @Test
    @DisplayName("TC-EHR-CONF-007: a decision is one resolved row: ACCEPTED/SYSTEM maps to ACCEPTED/SYSTEM, detected and resolved at the same instant")
    void recordDecisionAccepted() {
        writer.recordDecision(2L, 9L, IdentityFieldNames.PHONE, "555-0100", "555-0199", SOURCE_UPDATED,
                Outcome.ACCEPTED, ResolvedBy.SYSTEM, NOW);

        final EhrIdentityConflict row = saved();
        assertThat(row.getStatus()).isEqualTo(EhrConflictStatus.ACCEPTED);
        assertThat(row.getResolvedBy()).isEqualTo(EhrConflictResolver.SYSTEM);
        assertThat(row.getDetectedAt()).isEqualTo(NOW);
        assertThat(row.getResolvedAt()).isEqualTo(NOW);
        assertThat(row.getCanonicalValueBefore()).isEqualTo("555-0100");
        assertThat(row.getIncomingValue()).isEqualTo("555-0199");
        assertThat(row.getSourceUpdatedAt()).isEqualTo(SOURCE_UPDATED);
    }

    @Test
    @DisplayName("TC-EHR-CONF-008: REJECTED/PATIENT maps to REJECTED/PATIENT")
    void recordDecisionRejectedByPatient() {
        writer.recordDecision(2L, 9L, DOB, "1950-03-09", "1950-03-10", SOURCE_UPDATED,
                Outcome.REJECTED, ResolvedBy.PATIENT, NOW);

        final EhrIdentityConflict row = saved();
        assertThat(row.getStatus()).isEqualTo(EhrConflictStatus.REJECTED);
        assertThat(row.getResolvedBy()).isEqualTo(EhrConflictResolver.PATIENT);
    }

    @Test
    @DisplayName("TC-EHR-CONF-009: every write refuses to run outside a transaction, so an audit row can't outlive a rolled-back decision")
    void writesRequireTransaction() {
        TransactionSynchronizationManager.setActualTransactionActive(false);

        assertThatThrownBy(() -> writer.recordDecision(2L, 9L, DOB, "a", "b", SOURCE_UPDATED,
                Outcome.ACCEPTED, ResolvedBy.SYSTEM, NOW)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> writer.openPendingConflict(2L, 9L, DOB, "a", "b", SOURCE_UPDATED, NOW))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> writer.resolvePendingConflict(2L, DOB, Outcome.ACCEPTED, ResolvedBy.PATIENT, NOW))
                .isInstanceOf(IllegalStateException.class);
        verify(repository, never()).saveAndFlush(any());
    }

    @Test
    @DisplayName("TC-EHR-CONF-010: a pending conflict is stored PENDING with no resolution yet")
    void openPendingConflict() {
        writer.openPendingConflict(2L, 9L, DOB, "1950-03-09", "1950-03-10", SOURCE_UPDATED, NOW);

        final EhrIdentityConflict row = saved();
        assertThat(row.getStatus()).isEqualTo(EhrConflictStatus.PENDING);
        assertThat(row.getDetectedAt()).isEqualTo(NOW);
        assertThat(row.getResolvedAt()).isNull();
        assertThat(row.getResolvedBy()).isNull();
    }

    @Test
    @DisplayName("TC-EHR-CONF-011: the current pending conflict is read back as a PendingConflict, or empty when there is none")
    void currentPendingConflict() {
        final EhrIdentityConflict row = EhrIdentityConflict.builder()
                .patientId(2L).sourceId(9L).fieldName(DOB)
                .canonicalValueBefore("1950-03-09").incomingValue("1950-03-10")
                .sourceUpdatedAt(SOURCE_UPDATED).detectedAt(NOW).status(EhrConflictStatus.PENDING)
                .build();
        when(repository.findByPatientIdAndFieldNameAndStatus(2L, DOB, EhrConflictStatus.PENDING))
                .thenReturn(Optional.of(row));

        assertThat(writer.currentPendingConflict(2L, DOB))
                .contains(new PendingConflict(9L, "1950-03-09", "1950-03-10", SOURCE_UPDATED, NOW));
        assertThat(writer.currentPendingConflict(3L, DOB)).isEmpty();
    }

    @Test
    @DisplayName("TC-EHR-CONF-012: a decline counts only when the patient rejected that value from that source")
    void patientHasDeclinedAsksForPatientRejection() {
        when(repository.existsByPatientIdAndSourceIdAndFieldNameAndIncomingValueAndStatusAndResolvedBy(
                2L, 9L, DOB, "1950-03-10", EhrConflictStatus.REJECTED, EhrConflictResolver.PATIENT))
                .thenReturn(true);

        assertThat(writer.patientHasDeclined(2L, 9L, DOB, "1950-03-10")).isTrue();
        assertThat(writer.patientHasDeclined(2L, 8L, DOB, "1950-03-10")).isFalse();
    }

    @Test
    @DisplayName("TC-EHR-CONF-013: resolving updates the pending row itself, status and both resolution columns together")
    void resolveUpdatesInPlace() {
        final EhrIdentityConflict pending = EhrIdentityConflict.builder()
                .patientId(2L).sourceId(9L).fieldName(DOB).status(EhrConflictStatus.PENDING)
                .sourceUpdatedAt(SOURCE_UPDATED).detectedAt(SOURCE_UPDATED).build();
        when(repository.findByPatientIdAndFieldNameAndStatus(2L, DOB, EhrConflictStatus.PENDING))
                .thenReturn(Optional.of(pending));

        writer.resolvePendingConflict(2L, DOB, Outcome.ACCEPTED, ResolvedBy.PATIENT, NOW);

        assertThat(saved()).isSameAs(pending);
        assertThat(pending.getStatus()).isEqualTo(EhrConflictStatus.ACCEPTED);
        assertThat(pending.getResolvedBy()).isEqualTo(EhrConflictResolver.PATIENT);
        assertThat(pending.getResolvedAt()).isEqualTo(NOW);
    }

    @Test
    @DisplayName("TC-EHR-CONF-014: resolving when nothing is pending is an error, not a silent no-op")
    void resolveWithoutPendingFails() {
        when(repository.findByPatientIdAndFieldNameAndStatus(2L, DOB, EhrConflictStatus.PENDING))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> writer.resolvePendingConflict(2L, DOB, Outcome.REJECTED, ResolvedBy.PATIENT, NOW))
                .isInstanceOf(IllegalStateException.class);
        verify(repository, never()).saveAndFlush(any());
    }

    @Test
    @DisplayName("TC-EHR-CONF-015: a blank field name is refused; a missing repository is refused at construction")
    void inputValidation() {
        assertThatThrownBy(() -> writer.currentPendingConflict(2L, " ")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new JpaIdentityConflictAuditWriter(null)).isInstanceOf(NullPointerException.class);
    }
}
