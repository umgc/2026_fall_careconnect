package com.careconnect.ehr;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

/** Test IDs TC-EHR-RAW-014..015 are permanent. Never renumber, never reuse. */
class StoredDateOfBirthTest {

    @Test
    @DisplayName("TC-EHR-RAW-014: both shapes the application writes parse to the same date")
    void parsesIsoAndUsShapes() {
        assertThat(StoredDateOfBirth.parse("1950-03-09")).contains(LocalDate.of(1950, 3, 9));
        assertThat(StoredDateOfBirth.parse("03/09/1950")).contains(LocalDate.of(1950, 3, 9));
        assertThat(StoredDateOfBirth.parse("  1950-03-09 ")).contains(LocalDate.of(1950, 3, 9));
    }

    @Test
    @DisplayName("TC-EHR-RAW-015: null, blank and anything else are unknown, not a guessed date")
    void unknownIsEmpty() {
        assertThat(StoredDateOfBirth.parse(null)).isEmpty();
        assertThat(StoredDateOfBirth.parse("   ")).isEmpty();
        assertThat(StoredDateOfBirth.parse("March 9, 1950")).isEmpty();
        assertThat(StoredDateOfBirth.parse("1950")).isEmpty();
        // STRICT: an impossible date is rejected, not rolled into March.
        assertThat(StoredDateOfBirth.parse("02/30/1950")).isEmpty();
    }
}
