package com.careconnect.ehr.reconciliation;

import com.careconnect.ehr.reconciliation.ReconciliationOutcome.Decision;
import com.careconnect.ehr.reconciliation.support.InMemoryAuditWriter;
import com.careconnect.ehr.reconciliation.support.InMemoryPatientAccessor;
import com.careconnect.ehr.reconciliation.support.InMemoryProvenanceStore;
import com.careconnect.ehr.reconciliation.support.InMemoryTransactionRunner;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Guarantees of {@link RecencyWinsIdentityReconciler} itself, with in-memory collaborators. The full
 * reconciliation behaviour, shared by every implementation of the ports, is the contract suite
 * ({@code InMemoryContractTest}, {@code JpaContractPostgresTest}); this covers what the class promises on
 * its own: required collaborators, blank values never being authoritative, a fixed field order, and the
 * main recency decisions.
 */
class RecencyWinsIdentityReconcilerTest {

    private static final long PATIENT = 1L;
    private static final long SOURCE = 7L;
    private static final Instant OLD = Instant.parse("2026-01-01T00:00:00Z");
    private static final Instant NEW = Instant.parse("2026-09-01T00:00:00Z");

    private InMemoryProvenanceStore provenance;
    private InMemoryPatientAccessor patient;
    private InMemoryAuditWriter audit;
    private RecencyWinsIdentityReconciler reconciler;

    @BeforeEach
    void setUp() {
        provenance = new InMemoryProvenanceStore();
        patient = new InMemoryPatientAccessor();
        audit = new InMemoryAuditWriter();
        reconciler = new RecencyWinsIdentityReconciler(provenance, patient, audit, new InMemoryTransactionRunner());
        patient.seedPatientUpdatedAt(PATIENT, OLD);
    }

    private List<ReconciliationOutcome> reconcile(final Instant sourceUpdatedAt, final Map<String, String> fields) {
        return reconciler.reconcile(new SourceIdentitySnapshot(PATIENT, SOURCE, sourceUpdatedAt, fields));
    }

    @Test
    @DisplayName("every collaborator is required")
    void collaboratorsRequired() {
        final InMemoryTransactionRunner tx = new InMemoryTransactionRunner();
        assertThatThrownBy(() -> new RecencyWinsIdentityReconciler(null, patient, audit, tx))
                .isInstanceOf(NullPointerException.class);
        assertThatThrownBy(() -> new RecencyWinsIdentityReconciler(provenance, null, audit, tx))
                .isInstanceOf(NullPointerException.class);
        assertThatThrownBy(() -> new RecencyWinsIdentityReconciler(provenance, patient, null, tx))
                .isInstanceOf(NullPointerException.class);
        assertThatThrownBy(() -> new RecencyWinsIdentityReconciler(provenance, patient, audit, null))
                .isInstanceOf(NullPointerException.class);
    }

    @Test
    @DisplayName("an empty field is filled from the source")
    void emptyFieldIsFilled() {
        final List<ReconciliationOutcome> outcomes = reconcile(NEW, Map.of(IdentityFieldNames.PHONE, "555-0102"));

        assertThat(outcomes).containsExactly(
                new ReconciliationOutcome(IdentityFieldNames.PHONE, Decision.FILLED_EMPTY, "555-0102"));
        assertThat(patient.getCurrentValue(PATIENT, IdentityFieldNames.PHONE)).contains("555-0102");
    }

    @Test
    @DisplayName("a blank or missing incoming value is skipped: no outcome, and the patient's value is untouched")
    void blankIncomingIsNeverAuthoritative() {
        patient.seedCurrentValue(PATIENT, IdentityFieldNames.EMAIL, "jane@example.test");
        final Map<String, String> fields = new HashMap<>();
        fields.put(IdentityFieldNames.EMAIL, "   ");
        fields.put(IdentityFieldNames.PHONE, null);

        assertThat(reconcile(NEW, fields)).isEmpty();
        assertThat(patient.getCurrentValue(PATIENT, IdentityFieldNames.EMAIL)).contains("jane@example.test");
    }

    @Test
    @DisplayName("fields are processed in sorted name order whatever order the map gives, so lock order is fixed")
    void fieldsProcessedInSortedOrder() {
        final List<ReconciliationOutcome> outcomes = reconcile(NEW, Map.of(
                IdentityFieldNames.PHONE, "555-0102",
                IdentityFieldNames.EMAIL, "jane@example.test",
                IdentityFieldNames.GIVEN_NAME, "Jane"));

        assertThat(outcomes).extracting(ReconciliationOutcome::fieldName).isSorted();
    }

    @Test
    @DisplayName("a newer differing value replaces the patient's; an older one is rejected and leaves it")
    void newerWinsOlderLoses() {
        patient.seedCurrentValue(PATIENT, IdentityFieldNames.PHONE, "555-0100");
        provenance.recordAsFreshest(PATIENT, IdentityFieldNames.PHONE, SOURCE, Instant.parse("2026-05-01T00:00:00Z"));

        assertThat(reconcile(OLD, Map.of(IdentityFieldNames.PHONE, "555-0111")))
                .extracting(ReconciliationOutcome::decision).containsExactly(Decision.REJECTED_STALE);
        assertThat(patient.getCurrentValue(PATIENT, IdentityFieldNames.PHONE)).contains("555-0100");

        assertThat(reconcile(NEW, Map.of(IdentityFieldNames.PHONE, "555-0199")))
                .extracting(ReconciliationOutcome::decision).containsExactly(Decision.ACCEPTED_NEWER);
        assertThat(patient.getCurrentValue(PATIENT, IdentityFieldNames.PHONE)).contains("555-0199");
    }

    @Test
    @DisplayName("a newer differing date of birth is held for the patient's confirmation, not applied")
    void dateOfBirthWaitsForPatient() {
        patient.seedCurrentValue(PATIENT, IdentityFieldNames.DATE_OF_BIRTH, "1950-03-09");

        assertThat(reconcile(NEW, Map.of(IdentityFieldNames.DATE_OF_BIRTH, "1950-03-10")))
                .extracting(ReconciliationOutcome::decision)
                .containsExactly(Decision.PENDING_PATIENT_CONFIRMATION);
        assertThat(patient.getCurrentValue(PATIENT, IdentityFieldNames.DATE_OF_BIRTH)).contains("1950-03-09");
        assertThat(audit.currentPendingConflict(PATIENT, IdentityFieldNames.DATE_OF_BIRTH)).isPresent();
    }

    @Test
    @DisplayName("finalizing a date of birth when nothing is pending is an error")
    void finalizeWithoutPendingFails() {
        assertThatThrownBy(() -> reconciler.finalizePendingDateOfBirth(PATIENT, true))
                .isInstanceOf(IllegalStateException.class);
    }
}
