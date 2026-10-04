package com.careconnect.config;

import com.careconnect.testsupport.fixtures.AthenaPropertiesFixtures;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Validates the practice list on {@link AthenaProperties}: athena must never fall back to a practice
 * the developer did not choose, every entry must be in the form athena accepts, and a disabled
 * integration must not block startup.
 */
class AthenaPropertiesTest {

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"   ", " , ,"})
    @DisplayName("enabled with no practices fails at construction, naming the variable to set")
    void enabledWithoutPracticesFailsFast(final String practiceIds) {
        // Arrange
        final AthenaPropertiesFixtures.Builder builder =
                AthenaPropertiesFixtures.builder().enabled(true).practiceIds(practiceIds);

        // Act
        final IllegalStateException ex = assertThrows(IllegalStateException.class, builder::build);

        // Assert
        assertTrue(ex.getMessage().contains("ATHENA_PRACTICE_ID"), ex.getMessage());
    }

    @ParameterizedTest
    @ValueSource(strings = {"195900", "Practice-195900", "a-1.Practice-", "a-1.Practice-195900,80000"})
    @DisplayName("an entry not in ah-practice form fails at construction, naming the entry")
    void malformedEntryFailsFast(final String practiceIds) {
        // Act
        final IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> AthenaPropertiesFixtures.builder().practiceIds(practiceIds).build());

        // Assert
        assertTrue(ex.getMessage().contains("ah-practice form"), ex.getMessage());
    }

    @Test
    @DisplayName("disabled with no practices still constructs, so athena being off never blocks boot")
    void disabledWithoutPracticesIsAllowed() {
        // Act
        final AthenaProperties cfg = AthenaPropertiesFixtures.builder().enabled(false).practiceIds("").build();

        // Assert
        assertFalse(cfg.isEnabled());
        assertTrue(cfg.getPracticeIds().isEmpty());
    }

    @Test
    @DisplayName("the list is trimmed, empty entries dropped and duplicates removed, in order")
    void listIsParsed() {
        // Act
        final AthenaProperties cfg = AthenaPropertiesFixtures.builder()
                .practiceIds(" a-1.Practice-195900 , ,a-1.Practice-80000,a-1.Practice-195900").build();

        // Assert
        assertEquals(List.of("a-1.Practice-195900", "a-1.Practice-80000"), cfg.getPracticeIds());
    }

    @Test
    @DisplayName("a practice number finds its configured practice, and nothing else")
    void practiceWithNumber() {
        // Arrange
        final AthenaProperties cfg = AthenaPropertiesFixtures.builder()
                .practiceIds("a-1.Practice-195900,a-1.Practice-80000").build();

        // Act / Assert
        assertEquals(Optional.of("a-1.Practice-80000"), cfg.practiceWithNumber("80000"));
        assertEquals(Optional.of("a-1.Practice-195900"), cfg.practiceWithNumber("195900"));
        // 1959 is a prefix of 195900, not the same practice.
        assertEquals(Optional.empty(), cfg.practiceWithNumber("1959"));
    }
}
