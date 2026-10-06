package com.careconnect.config;

import com.careconnect.testsupport.fixtures.AthenaPropertiesFixtures;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Validates the boot-time guard on {@link AthenaProperties}: athena must never fall back to a
 * practice the developer did not choose, yet a disabled integration must not block startup.
 */
class AthenaPropertiesTest {

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"   "})
    @DisplayName("enabled with no practice id fails at construction, naming the variable to set")
    void enabledWithoutPracticeIdFailsFast(final String practiceId) {
        // Arrange
        final AthenaPropertiesFixtures.Builder builder =
                AthenaPropertiesFixtures.builder().enabled(true).practiceId(practiceId);

        // Act
        final IllegalStateException ex = assertThrows(IllegalStateException.class, builder::build);

        // Assert
        assertTrue(ex.getMessage().contains("ATHENA_PRACTICE_ID"), ex.getMessage());
    }

    @Test
    @DisplayName("disabled with no practice id still constructs, so athena being off never blocks boot")
    void disabledWithoutPracticeIdIsAllowed() {
        // Act
        final AthenaProperties cfg =
                AthenaPropertiesFixtures.builder().enabled(false).practiceId("").build();

        // Assert
        assertFalse(cfg.isEnabled());
        assertEquals("", cfg.getPracticeId());
    }
}
