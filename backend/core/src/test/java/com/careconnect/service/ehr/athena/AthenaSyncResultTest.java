package com.careconnect.service.ehr.athena;

import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class AthenaSyncResultTest {

    @Test
    void completedCopiesTypeResultsAndRecordsCompletionStatus() {
        List<AthenaSyncResult.TypeResult> input = new ArrayList<>();
        input.add(new AthenaSyncResult.TypeResult("Patient", AthenaSyncResult.Outcome.STORED, 2));

        AthenaSyncResult result = AthenaSyncResult.completed(input);
        input.clear();

        assertThat(result.status()).isEqualTo(AthenaSyncResult.Status.COMPLETED);
        assertThat(result.syncedAt()).isNotNull();
        assertThat(result.types()).containsExactly(
                new AthenaSyncResult.TypeResult("Patient", AthenaSyncResult.Outcome.STORED, 2));
        assertThatThrownBy(() -> result.types().add(null))
                .isInstanceOf(UnsupportedOperationException.class);
    }

    @Test
    void unavailableHasNoTypeResults() {
        AthenaSyncResult result = AthenaSyncResult.unavailable();

        assertThat(result.status()).isEqualTo(AthenaSyncResult.Status.SOURCE_UNAVAILABLE);
        assertThat(result.syncedAt()).isNotNull();
        assertThat(result.types()).isEmpty();
    }
}
