package com.careconnect.integration.cerner;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.InputStream;
import java.util.Objects;
import java.util.stream.Stream;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Checks the shared synthetic fixtures offline; no source, Spring, or database is used. */
class CernerAllergyFixtureCompatibilityTest {
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final String PATIENT = "synthetic-patient-1";
    private static final String OTHER_PATIENT = "another-synthetic-patient";

    /** Fixed cases retain the original fixture names and authorship. */
    static Stream<String> fixtureNames() {
        return Stream.of("bundle-empty.json", "bundle-entered-in-error.json",
                "bundle-missing-reaction.json", "bundle-one-active-confirmed-allergy.json",
                "bundle-text-only-substance.json", "bundle-three-allergies.json");
    }

    /** Even an excluded record must not bypass the mapper's patient check. */
    static Stream<String> nonemptyFixtureNames() {
        return fixtureNames().filter(name -> !"bundle-empty.json".equals(name));
    }

    private static JsonNode resource(String path) throws Exception {
        try (InputStream input = Objects.requireNonNull(
                CernerAllergyFixtureCompatibilityTest.class.getResourceAsStream(path), path)) {
            return JSON.readTree(input);
        }
    }

    @ParameterizedTest
    @MethodSource("fixtureNames")
    @Tag("M3-REQ-04")
    void fullOutputMatchesFixedExpectation(String name) throws Exception {
        // Arrange: fixed output was recorded separately from this test's execution.
        final JsonNode source = resource("/cerner/fhir/allergyintolerance/" + name);
        final JsonNode expected = resource("/cerner/expected/allergy-mapper.json");
        assertThat(expected.path("authorizedPatient").asText()).isEqualTo(PATIENT);

        // Act and assert: compare all fields, nulls, and array order.
        final JsonNode actual = JSON.valueToTree(CernerAllergyMapper.map(source, PATIENT));
        assertThat(actual).isEqualTo(expected.path("cases").path(name));
    }

    @ParameterizedTest
    @MethodSource("fixtureNames")
    @Tag("M3-REQ-12")
    void mappingLeavesInputUnchanged(String name) throws Exception {
        // Arrange a deep copy so nested source changes are visible.
        final JsonNode source = resource("/cerner/fhir/allergyintolerance/" + name);
        final JsonNode before = source.deepCopy();
        // Act and assert: source provenance must remain intact.
        CernerAllergyMapper.map(source, PATIENT);
        assertThat(source).isEqualTo(before);
    }

    @ParameterizedTest
    @MethodSource("nonemptyFixtureNames")
    @Tag("M3-REQ-03")
    void wrongPatientRejectedWithoutIdentifierLeak(String name) throws Exception {
        // Arrange: reuse each nonempty fixture with a different authorized patient.
        final JsonNode source = resource("/cerner/fhir/allergyintolerance/" + name);
        // Act and assert: reject before returning data and keep IDs out of the error.
        assertThatThrownBy(() -> CernerAllergyMapper.map(source, OTHER_PATIENT))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageNotContaining(PATIENT)
                .hasMessageNotContaining(OTHER_PATIENT);
    }
}
