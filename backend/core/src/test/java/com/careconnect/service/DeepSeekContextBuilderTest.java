package com.careconnect.service;

import com.careconnect.model.Allergy;
import com.careconnect.model.Allergy.AllergyType;
import com.careconnect.model.Allergy.AllergySeverity;
import com.careconnect.model.SymptomEntry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.Collections;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Unit tests for {@link DeepSeekContextBuilder}.
 *
 * <p>Covers all branches in both {@code buildAllergyContext} and
 * {@code buildSymptomContext}, including null lists, empty lists,
 * single-entry lists, multi-entry lists, and null field values.
 */
class DeepSeekContextBuilderTest {

    private static final DateTimeFormatter TS =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
                    .withZone(ZoneId.systemDefault());
    private DeepSeekContextBuilder builder;

    @BeforeEach
    void setUp() throws Exception {
        builder = new DeepSeekContextBuilder();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // buildAllergyContext
    // ═══════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("buildAllergyContext")
    class BuildAllergyContext {

        @Test
        @DisplayName("buildAllergyContext_nullList_returnsNoKnownAllergies")
        void buildAllergyContext_nullList_returnsNoKnownAllergies() throws Exception {
            final String result = builder.buildAllergyContext(1L, null);
            assertThat(result).isEqualTo("The patient has no known recorded drug allergies.");
        }

        @Test
        @DisplayName("buildAllergyContext_emptyList_returnsNoKnownAllergies")
        void buildAllergyContext_emptyList_returnsNoKnownAllergies() throws Exception {
            final String result = builder.buildAllergyContext(1L, Collections.emptyList());
            assertThat(result).isEqualTo("The patient has no known recorded drug allergies.");
        }

        @Test
        @DisplayName("buildAllergyContext_singleAllergy_returnsFormattedContext")
        void buildAllergyContext_singleAllergy_returnsFormattedContext() throws Exception {
            final Allergy allergy = Allergy.builder()
                    .allergen("Penicillin")
                    .allergyType(AllergyType.MEDICATION)
                    .severity(AllergySeverity.SEVERE)
                    .reaction("Anaphylaxis")
                    .isActive(true)
                    .build();

            final String result = builder.buildAllergyContext(1L, List.of(allergy));

            assertThat(result).startsWith("Patient Allergy Record:\n");
            assertThat(result).contains("- Allergen: Penicillin");
            assertThat(result).contains("| Type: MEDICATION");
            assertThat(result).contains("| Severity: SEVERE");
            assertThat(result).contains("| Reaction: Anaphylaxis");
            assertThat(result).contains("| Active: true");
            assertThat(result).endsWith("\nUse this allergy history to safely assist the patient.\n");
        }

        @Test
        @DisplayName("buildAllergyContext_multipleAllergies_returnsAllEntriesFormatted")
        void buildAllergyContext_multipleAllergies_returnsAllEntriesFormatted() throws Exception {
            final Allergy allergy1 = Allergy.builder()
                    .allergen("Penicillin")
                    .allergyType(AllergyType.MEDICATION)
                    .severity(AllergySeverity.SEVERE)
                    .reaction("Anaphylaxis")
                    .isActive(true)
                    .build();

            final Allergy allergy2 = Allergy.builder()
                    .allergen("Peanuts")
                    .allergyType(AllergyType.FOOD)
                    .severity(AllergySeverity.MODERATE)
                    .reaction("Hives")
                    .isActive(false)
                    .build();

            final String result = builder.buildAllergyContext(42L, List.of(allergy1, allergy2));

            assertThat(result).startsWith("Patient Allergy Record:\n");
            assertThat(result).contains("- Allergen: Penicillin");
            assertThat(result).contains("- Allergen: Peanuts");
            assertThat(result).contains("| Type: FOOD");
            assertThat(result).contains("| Severity: MODERATE");
            assertThat(result).contains("| Reaction: Hives");
            assertThat(result).contains("| Active: false");
            assertThat(result).endsWith("\nUse this allergy history to safely assist the patient.\n");
        }

        @Test
        @DisplayName("buildAllergyContext_nullFields_returnsNullStringsInOutput")
        void buildAllergyContext_nullFields_returnsNullStringsInOutput() throws Exception {
            final Allergy allergy = Allergy.builder()
                    .allergen(null)
                    .allergyType(null)
                    .severity(null)
                    .reaction(null)
                    .isActive(null)
                    .build();

            final String result = builder.buildAllergyContext(1L, List.of(allergy));

            assertThat(result).startsWith("Patient Allergy Record:\n");
            assertThat(result).contains("- Allergen: null");
            assertThat(result).contains("| Type: null");
            assertThat(result).contains("| Severity: null");
            assertThat(result).contains("| Reaction: null");
            assertThat(result).contains("| Active: null");
        }

        @Test
        @DisplayName("buildAllergyContext_nullPatientId_stillBuildsContext")
        void buildAllergyContext_nullPatientId_stillBuildsContext() throws Exception {
            final Allergy allergy = Allergy.builder()
                    .allergen("Dust")
                    .allergyType(AllergyType.ENVIRONMENTAL)
                    .severity(AllergySeverity.MILD)
                    .reaction("Sneezing")
                    .isActive(true)
                    .build();

            final String result = builder.buildAllergyContext(null, List.of(allergy));

            assertThat(result).contains("- Allergen: Dust");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // buildSymptomContext
    // ═══════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("buildSymptomContext")
    class BuildSymptomContext {

        @Test
        @DisplayName("buildSymptomContext_nullList_returnsNoSymptomEntries")
        void buildSymptomContext_nullList_returnsNoSymptomEntries() throws Exception {
            final String result = builder.buildSymptomContext(1L, null);
            assertThat(result).isEqualTo("No prior symptom entries on record.");
        }

        @Test
        @DisplayName("buildSymptomContext_emptyList_returnsNoSymptomEntries")
        void buildSymptomContext_emptyList_returnsNoSymptomEntries() throws Exception {
            final String result = builder.buildSymptomContext(1L, Collections.emptyList());
            assertThat(result).isEqualTo("No prior symptom entries on record.");
        }

        @Test
        @DisplayName("buildSymptomContext_singleSymptom_returnsFormattedContext")
        void buildSymptomContext_singleSymptom_returnsFormattedContext() throws Exception {
            final Instant now = Instant.now();
            final SymptomEntry entry = SymptomEntry.builder()
                    .symptomKey("headache")
                    .symptomValue("moderate")
                    .severity(3)
                    .completed(true)
                    .takenAt(now)
                    .build();

            final String result = builder.buildSymptomContext(1L, List.of(entry));
            final String expectedTs = TS.format(now);

            assertThat(result).startsWith("Recent Symptom History:\n");
            assertThat(result).contains("- " + expectedTs);
            assertThat(result).contains("| key: headache");
            assertThat(result).contains("| value: moderate");
            assertThat(result).contains("| severity: 3");
            assertThat(result).contains("| completed: true");
            assertThat(result).endsWith("\nUse this history to interpret the new symptom input.\n");
        }

        @Test
        @DisplayName("buildSymptomContext_multipleSymptoms_returnsAllEntriesFormatted")
        void buildSymptomContext_multipleSymptoms_returnsAllEntriesFormatted() throws Exception {
            final Instant t1 = Instant.parse("2025-01-15T10:30:00Z");
            final Instant t2 = Instant.parse("2025-01-16T14:00:00Z");

            final SymptomEntry entry1 = SymptomEntry.builder()
                    .symptomKey("headache")
                    .symptomValue("severe")
                    .severity(5)
                    .completed(true)
                    .takenAt(t1)
                    .build();

            final SymptomEntry entry2 = SymptomEntry.builder()
                    .symptomKey("cough")
                    .symptomValue("mild")
                    .severity(1)
                    .completed(false)
                    .takenAt(t2)
                    .build();

            final String result = builder.buildSymptomContext(1L, List.of(entry1, entry2));

            assertThat(result).contains("| key: headache");
            assertThat(result).contains("| key: cough");
            assertThat(result).contains("| value: severe");
            assertThat(result).contains("| value: mild");
            assertThat(result).contains("| completed: true");
            assertThat(result).contains("| completed: false");
        }

        @Test
        @DisplayName("buildSymptomContext_nullSymptomKey_returnsEmptyString")
        void buildSymptomContext_nullSymptomKey_returnsEmptyString() throws Exception {
            final Instant now = Instant.now();
            final SymptomEntry entry = SymptomEntry.builder()
                    .symptomKey(null)
                    .symptomValue("moderate")
                    .severity(2)
                    .completed(true)
                    .takenAt(now)
                    .build();

            final String result = builder.buildSymptomContext(1L, List.of(entry));

            // nz(null) returns ""
            assertThat(result).contains("| key: ");
            assertThat(result).doesNotContain("| key: null");
        }

        @Test
        @DisplayName("buildSymptomContext_nullSymptomValue_returnsEmptyString")
        void buildSymptomContext_nullSymptomValue_returnsEmptyString() throws Exception {
            final Instant now = Instant.now();
            final SymptomEntry entry = SymptomEntry.builder()
                    .symptomKey("fever")
                    .symptomValue(null)
                    .severity(4)
                    .completed(true)
                    .takenAt(now)
                    .build();

            final String result = builder.buildSymptomContext(1L, List.of(entry));

            // nz(null) returns "", then next field is prefixed with " | ", so two spaces appear
            assertThat(result).contains("| value:  |");
        }

        @Test
        @DisplayName("buildSymptomContext_nullSeverity_returnsEmptyStringForSeverity")
        void buildSymptomContext_nullSeverity_returnsEmptyStringForSeverity() throws Exception {
            final Instant now = Instant.now();
            final SymptomEntry entry = SymptomEntry.builder()
                    .symptomKey("nausea")
                    .symptomValue("mild")
                    .severity(null)
                    .completed(true)
                    .takenAt(now)
                    .build();

            final String result = builder.buildSymptomContext(1L, List.of(entry));

            // severity == null -> "", then next field is prefixed with " | ", so two spaces appear
            assertThat(result).contains("| severity:  |");
        }

        @Test
        @DisplayName("buildSymptomContext_nullCompleted_returnsFalse")
        void buildSymptomContext_nullCompleted_returnsFalse() throws Exception {
            final Instant now = Instant.now();
            final SymptomEntry entry = SymptomEntry.builder()
                    .symptomKey("fatigue")
                    .symptomValue("moderate")
                    .severity(3)
                    .completed(null)
                    .takenAt(now)
                    .build();

            final String result = builder.buildSymptomContext(1L, List.of(entry));

            // Boolean.TRUE.equals(null) -> false
            assertThat(result).contains("| completed: false");
        }

        @Test
        @DisplayName("buildSymptomContext_completedFalse_returnsFalse")
        void buildSymptomContext_completedFalse_returnsFalse() throws Exception {
            final Instant now = Instant.now();
            final SymptomEntry entry = SymptomEntry.builder()
                    .symptomKey("dizziness")
                    .symptomValue("light")
                    .severity(2)
                    .completed(false)
                    .takenAt(now)
                    .build();

            final String result = builder.buildSymptomContext(1L, List.of(entry));

            assertThat(result).contains("| completed: false");
        }

        @Test
        @DisplayName("buildSymptomContext_nullPatientId_stillBuildsContext")
        void buildSymptomContext_nullPatientId_stillBuildsContext() throws Exception {
            final Instant now = Instant.now();
            final SymptomEntry entry = SymptomEntry.builder()
                    .symptomKey("cough")
                    .symptomValue("dry")
                    .severity(2)
                    .completed(true)
                    .takenAt(now)
                    .build();

            final String result = builder.buildSymptomContext(null, List.of(entry));

            assertThat(result).contains("| key: cough");
        }

        @Test
        @DisplayName("buildSymptomContext_allFieldsNull_handlesGracefully")
        void buildSymptomContext_allFieldsNull_handlesGracefully() throws Exception {
            final Instant now = Instant.now();
            final SymptomEntry entry = SymptomEntry.builder()
                    .symptomKey(null)
                    .symptomValue(null)
                    .severity(null)
                    .completed(null)
                    .takenAt(now)
                    .build();

            final String result = builder.buildSymptomContext(1L, List.of(entry));

            assertThat(result).startsWith("Recent Symptom History:\n");
            assertThat(result).contains("| completed: false");
            assertThat(result).endsWith("\nUse this history to interpret the new symptom input.\n");
        }
    }
}
