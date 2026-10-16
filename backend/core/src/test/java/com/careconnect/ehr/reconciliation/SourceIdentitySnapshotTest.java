package com.careconnect.ehr.reconciliation;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The reconciler's only input: every component is required (DEF-EHR-REC-01).
 * <p>
 * Test IDs TC-EHR-REC-061..064 are permanent. Never renumber, never reuse.
 */
class SourceIdentitySnapshotTest {

    private static final Instant UPDATED = Instant.parse("2026-09-01T10:00:00Z");

    @Test
    @DisplayName("TC-EHR-REC-061: a fully populated snapshot keeps what it was given")
    void keepsComponents() {
        final SourceIdentitySnapshot s = new SourceIdentitySnapshot(2L, 9L, UPDATED,
                Map.of(IdentityFieldNames.GIVEN_NAME, "Jane"));

        assertThat(s.patientId()).isEqualTo(2L);
        assertThat(s.sourceId()).isEqualTo(9L);
        assertThat(s.sourceUpdatedAt()).isEqualTo(UPDATED);
        assertThat(s.fields()).containsEntry(IdentityFieldNames.GIVEN_NAME, "Jane");
    }

    @Test
    @DisplayName("TC-EHR-REC-062: an undated snapshot is refused, not accepted with a null provenance time (DEF-EHR-REC-01)")
    void undatedRefused() {
        assertThatThrownBy(() -> new SourceIdentitySnapshot(2L, 9L, null, Map.of()))
                .isInstanceOf(NullPointerException.class)
                .hasMessage("sourceUpdatedAt");
    }

    @Test
    @DisplayName("TC-EHR-REC-063: a missing patient, source or field map is refused, naming the missing component")
    void otherComponentsRequired() {
        assertThatThrownBy(() -> new SourceIdentitySnapshot(null, 9L, UPDATED, Map.of())).hasMessage("patientId");
        assertThatThrownBy(() -> new SourceIdentitySnapshot(2L, null, UPDATED, Map.of())).hasMessage("sourceId");
        assertThatThrownBy(() -> new SourceIdentitySnapshot(2L, 9L, UPDATED, null)).hasMessage("fields");
    }

    @Test
    @DisplayName("TC-EHR-REC-064: an empty field map is allowed: a source may have nothing to report")
    void emptyFieldsAllowed() {
        assertThat(new SourceIdentitySnapshot(2L, 9L, UPDATED, Map.of()).fields()).isEmpty();
    }
}
