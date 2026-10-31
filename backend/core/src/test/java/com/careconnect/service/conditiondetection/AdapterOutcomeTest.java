package com.careconnect.service.conditiondetection;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.careconnect.model.conditiondetection.ConditionFinding;
import com.careconnect.model.conditiondetection.ConditionName;
import com.careconnect.model.conditiondetection.ConditionSkipReason;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * Unit tests for {@link AdapterOutcome}: the defensive copy in {@code Completed} and the
 * single-argument {@code Skipped} constructor. Plain values only; nothing is mocked.
 */
class AdapterOutcomeTest {

    private static ConditionFinding finding(final ConditionName condition) {
        return new ConditionFinding(condition, 1, "MILD", -0.4, null);
    }

    /**
     * Scenario: an adapter keeps mutating its working list after returning. The outcome the
     * worker stores must not change with it, and must not be mutable by the worker either.
     */
    @Test
    void completed_copiesFindingsAndIsUnmodifiable() {
        // Arrange
        final List<ConditionFinding> working = new ArrayList<>();
        working.add(finding(ConditionName.DEPRESSION));

        // Act
        final AdapterOutcome.Completed outcome = new AdapterOutcome.Completed(working, 42.0);
        working.add(finding(ConditionName.ANXIETY));

        // Assert
        assertThat(outcome.findings()).containsExactly(finding(ConditionName.DEPRESSION));
        assertThat(outcome.speechSeconds()).isEqualTo(42.0);
        assertThatThrownBy(() -> outcome.findings().add(finding(ConditionName.ANXIETY)))
                .isInstanceOf(UnsupportedOperationException.class);
    }

    /** Scenario: most skips happen before any audio is measured, so speech time is unknown. */
    @Test
    void skipped_reasonOnly_leavesSpeechSecondsNull() {
        final AdapterOutcome.Skipped outcome =
                new AdapterOutcome.Skipped(ConditionSkipReason.NO_RECORDING);

        assertThat(outcome.reason()).isEqualTo(ConditionSkipReason.NO_RECORDING);
        assertThat(outcome.speechSeconds()).isNull();
        assertThat(outcome).isEqualTo(new AdapterOutcome.Skipped(ConditionSkipReason.NO_RECORDING, null));
    }

    /** Scenario: a deferral carries only its delay. */
    @Test
    void deferred_keepsDelay() {
        assertThat(new AdapterOutcome.Deferred(120L).delaySeconds()).isEqualTo(120L);
    }
}
