package com.careconnect.ehr.reconciliation;

import com.careconnect.ehr.reconciliation.ReconciliationOutcome.Decision;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The per-field result the reconciler returns. Callers map each {@link Decision} to UI (a notice, or
 * the DOB confirmation prompt), so the set of decisions is a contract: adding or removing one has to be
 * a deliberate change that updates this test.
 * <p>
 * Test IDs TC-EHR-REC-058..060 are permanent. Never renumber, never reuse.
 */
class ReconciliationOutcomeTest {

    @Test
    @DisplayName("TC-EHR-REC-058: an outcome carries the field, the decision and the value")
    void carriesFieldDecisionAndValue() {
        final ReconciliationOutcome o = new ReconciliationOutcome(
                IdentityFieldNames.DATE_OF_BIRTH, Decision.PENDING_PATIENT_CONFIRMATION, "1950-03-10");

        assertThat(o.fieldName()).isEqualTo(IdentityFieldNames.DATE_OF_BIRTH);
        assertThat(o.decision()).isEqualTo(Decision.PENDING_PATIENT_CONFIRMATION);
        assertThat(o.appliedValue()).isEqualTo("1950-03-10");
    }

    @Test
    @DisplayName("TC-EHR-REC-059: outcomes compare by value, so callers and tests can match them directly")
    void valueEquality() {
        assertThat(new ReconciliationOutcome("phone", Decision.ACCEPTED_NEWER, "555-0102"))
                .isEqualTo(new ReconciliationOutcome("phone", Decision.ACCEPTED_NEWER, "555-0102"))
                .isNotEqualTo(new ReconciliationOutcome("phone", Decision.REJECTED_STALE, "555-0102"));
    }

    @Test
    @DisplayName("TC-EHR-REC-060: the decisions are exactly the documented eight, in order")
    void decisionSetIsTheContract() {
        assertThat(Decision.values()).containsExactly(
                Decision.FILLED_EMPTY,
                Decision.ALREADY_AGREED,
                Decision.ACCEPTED_NEWER,
                Decision.REJECTED_STALE,
                Decision.REJECTED_PREVIOUSLY_DECLINED,
                Decision.PENDING_PATIENT_CONFIRMATION,
                Decision.ACCEPTED_BY_PATIENT,
                Decision.REJECTED_BY_PATIENT);
    }
}
