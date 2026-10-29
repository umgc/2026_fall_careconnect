package com.careconnect.integration.cerner;

import static org.assertj.core.api.Assertions.assertThat;

import com.careconnect.service.ehr.EhrConditionMapper;
import com.careconnect.service.ehr.EhrEncounterMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Objects;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

/** Locks candidate normalized outputs to paired source fixtures pending contract approval. */
@Tag("M3-REQ-01")
@Tag("M3-REQ-02")
class CernerClinicalExpectedOutputTest {

    private static final String EXTERNAL_PATIENT_ID = "synthetic-patient-1";
    private final ObjectMapper json = new ObjectMapper();

    @Test
    @Tag("M3-REQ-17")
    void conditionMatchesPairedCandidateExpectedOutput() throws Exception {
        final JsonNode resource = bundleResource(
                "/cerner/fhir/condition/bundle-one-condition.json");
        final var mapped = EhrConditionMapper.map(
                resource, 17L, 4L, 91L, EXTERNAL_PATIENT_ID);

        final JsonNode actual = json.valueToTree(
                CernerClinicalController.ConditionView.from(mapped));
        assertThat(actual)
                .isEqualTo(expected(
                        "/expected/condition/bundle-one-condition.expected.json"));
    }

    @Test
    @Tag("M3-REQ-18")
    void encounterMatchesPairedCandidateExpectedOutput() throws Exception {
        final JsonNode resource = bundleResource(
                "/cerner/fhir/encounter/bundle-one-encounter.json");
        final var mapped = EhrEncounterMapper.map(
                resource, 17L, 4L, 92L, EXTERNAL_PATIENT_ID);

        final JsonNode actual = json.valueToTree(
                CernerClinicalController.EncounterView.from(mapped));
        assertThat(actual)
                .isEqualTo(expected(
                        "/expected/encounter/bundle-one-encounter.expected.json"));
    }

    private JsonNode bundleResource(final String path) throws Exception {
        try (var input = getClass().getResourceAsStream(path)) {
            return json.readTree(Objects.requireNonNull(input))
                    .path("entry").path(0).path("resource");
        }
    }

    private JsonNode expected(final String path) throws Exception {
        try (var input = getClass().getResourceAsStream(path)) {
            return json.readTree(Objects.requireNonNull(input));
        }
    }
}
