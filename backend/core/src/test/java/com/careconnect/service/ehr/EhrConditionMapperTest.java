package com.careconnect.service.ehr;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.util.Objects;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

@Tag("M3-REQ-01")
@Tag("M3-REQ-02")
@Tag("M3-REQ-17")
class EhrConditionMapperTest {

    private static final long PATIENT_ID = 17L;
    private static final long SOURCE_ID = 4L;
    private static final long RAW_PAYLOAD_ID = 91L;
    private static final String EXTERNAL_PATIENT_ID = "synthetic-patient-1";

    private final ObjectMapper json = new ObjectMapper();

    @Test
    void mapsCompleteConditionWithoutFlatteningCodesOrProvenance() throws Exception {
        final var actual = map("bundle-one-condition.json");

        assertThat(actual.getPatientId()).isEqualTo(PATIENT_ID);
        assertThat(actual.getSourceId()).isEqualTo(SOURCE_ID);
        assertThat(actual.getRawPayloadId()).isEqualTo(RAW_PAYLOAD_ID);
        assertThat(actual.getExternalConditionId()).isEqualTo("synthetic-condition-1");
        assertThat(actual.getSourceVersionId()).isEqualTo("synthetic-condition-version-1");
        assertThat(actual.getSourceUpdatedAt()).hasToString("2026-09-15T10:00:00Z");
        assertThat(actual.getClinicalStatus()).isEqualTo("active");
        assertThat(actual.getVerificationStatus()).isEqualTo("confirmed");
        assertThat(actual.getCategories()).singleElement().satisfies(category -> {
            assertThat(category.system())
                    .isEqualTo("http://terminology.hl7.org/CodeSystem/condition-category");
            assertThat(category.code()).isEqualTo("problem-list-item");
        });
        assertThat(actual.getConditionCodes()).singleElement().satisfies(code -> {
            assertThat(code.system()).isEqualTo("http://snomed.info/sct");
            assertThat(code.code()).isEqualTo("38341003");
            assertThat(code.display()).isEqualTo("Hypertensive disorder, systemic arterial");
            assertThat(code.text()).isEqualTo("Synthetic hypertension");
        });
        assertThat(actual.getConditionText()).isEqualTo("Synthetic hypertension");
        assertThat(actual.getOnsetType()).isEqualTo("onsetDateTime");
        assertThat(actual.getOnsetValue()).isEqualTo("2020-04-15");
        assertThat(actual.getOnsetPrecision()).isEqualTo("DAY");
        assertThat(actual.getRecordedDate()).isEqualTo("2026-09-15T10:00:00Z");
        assertThat(actual.getRecordedDatePrecision()).isEqualTo("INSTANT");
        assertThat(actual.getEncounterReference()).isEqualTo("Encounter/synthetic-encounter-1");
        assertThat(actual.getRecorderReference())
                .isEqualTo("Practitioner/synthetic-practitioner-1");
        assertThat(actual.getRecorderDisplay()).isEqualTo("Synthetic Clinician");
        assertThat(actual.getHiddenFromActiveList()).isFalse();
    }

    @Test
    void missingOptionalFieldsBecomeNullScalarsAndEmptyCollections() throws Exception {
        final var actual = map("bundle-missing-optional-fields.json");

        assertThat(actual.getClinicalStatus()).isNull();
        assertThat(actual.getConditionCodes()).singleElement().satisfies(code -> {
            assertThat(code.system()).isNull();
            assertThat(code.code()).isNull();
            assertThat(code.text()).isEqualTo("Synthetic condition without coding");
        });
        assertThat(actual.getBodySites()).isEmpty();
        assertThat(actual.getOnsetValue()).isNull();
        assertThat(actual.getAbatementValue()).isNull();
        assertThat(actual.getEncounterReference()).isNull();
        assertThat(actual.getRecorderReference()).isNull();
        assertThat(actual.getSourceVersionId()).isNull();
        assertThat(actual.getSourceUpdatedAt()).isNull();
    }

    @Test
    void enteredInErrorIsRetainedForAuditButHiddenFromActiveResults() throws Exception {
        final var actual = map("bundle-entered-in-error.json");

        assertThat(actual.getVerificationStatus()).isEqualTo("entered-in-error");
        assertThat(actual.getHiddenFromActiveList()).isTrue();
    }

    @Test
    void preservesYearAndMonthOnsetPrecision() throws Exception {
        final JsonNode condition = resource("bundle-one-condition.json");
        ((com.fasterxml.jackson.databind.node.ObjectNode) condition).put("onsetDateTime", "1985-03");

        final var actual = EhrConditionMapper.map(
                condition, PATIENT_ID, SOURCE_ID, RAW_PAYLOAD_ID, EXTERNAL_PATIENT_ID);

        assertThat(actual.getOnsetValue()).isEqualTo("1985-03");
        assertThat(actual.getOnsetPrecision()).isEqualTo("MONTH");
    }

    @Test
    void rejectsWrongPatientBeforeARecordCanBeStored() throws Exception {
        final JsonNode condition = resource("bundle-one-condition.json");

        assertThatThrownBy(() -> EhrConditionMapper.map(
                        condition, PATIENT_ID, SOURCE_ID, RAW_PAYLOAD_ID, "another-patient"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Invalid canonical FHIR field: subject.reference");
    }

    private com.careconnect.model.ehr.EhrConditionRecord map(final String file) throws Exception {
        return EhrConditionMapper.map(
                resource(file), PATIENT_ID, SOURCE_ID, RAW_PAYLOAD_ID, EXTERNAL_PATIENT_ID);
    }

    private JsonNode resource(final String file) throws IOException {
        try (var input = getClass().getResourceAsStream("/cerner/fhir/condition/" + file)) {
            return json.readTree(Objects.requireNonNull(input)).path("entry").path(0).path("resource");
        }
    }
}
