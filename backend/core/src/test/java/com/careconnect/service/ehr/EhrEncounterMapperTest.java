package com.careconnect.service.ehr;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.util.Objects;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

@Tag("M3-REQ-01")
@Tag("M3-REQ-02")
@Tag("M3-REQ-18")
class EhrEncounterMapperTest {

    private static final long PATIENT_ID = 17L;
    private static final long SOURCE_ID = 4L;
    private static final long RAW_PAYLOAD_ID = 92L;
    private static final String EXTERNAL_PATIENT_ID = "synthetic-patient-1";

    private final ObjectMapper json = new ObjectMapper();

    @Test
    void mapsCompleteEncounterAndKeepsParticipantsStructured() throws Exception {
        final var actual = map("bundle-one-encounter.json");

        assertThat(actual.getPatientId()).isEqualTo(PATIENT_ID);
        assertThat(actual.getSourceId()).isEqualTo(SOURCE_ID);
        assertThat(actual.getRawPayloadId()).isEqualTo(RAW_PAYLOAD_ID);
        assertThat(actual.getExternalEncounterId()).isEqualTo("synthetic-encounter-1");
        assertThat(actual.getSourceVersionId()).isEqualTo("synthetic-encounter-version-1");
        assertThat(actual.getSourceUpdatedAt()).hasToString("2026-09-18T15:00:00Z");
        assertThat(actual.getStatus()).isEqualTo("finished");
        assertThat(actual.getClassSystem())
                .isEqualTo("http://terminology.hl7.org/CodeSystem/v3-ActCode");
        assertThat(actual.getClassCode()).isEqualTo("AMB");
        assertThat(actual.getClassDisplay()).isEqualTo("ambulatory");
        assertThat(actual.getEncounterTypes()).singleElement().satisfies(type -> {
            assertThat(type.code()).isEqualTo("O");
            assertThat(type.display()).isEqualTo("Outpatient");
            assertThat(type.text()).isEqualTo("Outpatient");
        });
        assertThat(actual.getPeriodStart()).isEqualTo("2026-09-18T14:00:00Z");
        assertThat(actual.getPeriodEnd()).isEqualTo("2026-09-18T15:00:00Z");
        assertThat(actual.getParticipants()).singleElement().satisfies(participant -> {
            assertThat(participant.reference())
                    .isEqualTo("Practitioner/synthetic-practitioner-1");
            assertThat(participant.display()).isEqualTo("Synthetic Clinician");
            assertThat(participant.types()).singleElement().satisfies(type ->
                    assertThat(type.code()).isEqualTo("PPRF"));
        });
        assertThat(actual.getServiceProviderReference())
                .isEqualTo("Organization/synthetic-organization-1");
        assertThat(actual.getServiceProviderDisplay()).isEqualTo("Synthetic Clinic");
        assertThat(actual.getLocations()).isEmpty();
        assertThat(actual.getReasonCodes()).isEmpty();
        assertThat(actual.getDiagnosisReferences()).isEmpty();
        assertThat(actual.getAppointmentReferences()).isEmpty();
    }

    @Test
    void missingOptionalFieldsBecomeNullScalarsAndEmptyCollections() throws Exception {
        final var actual = map("bundle-missing-optional-fields.json");

        assertThat(actual.getStatus()).isEqualTo("in-progress");
        assertThat(actual.getClassCode()).isEqualTo("AMB");
        assertThat(actual.getEncounterTypes()).isEmpty();
        assertThat(actual.getPeriodStart()).isNull();
        assertThat(actual.getPeriodEnd()).isNull();
        assertThat(actual.getParticipants()).isEmpty();
        assertThat(actual.getServiceProviderReference()).isNull();
        assertThat(actual.getLocations()).isEmpty();
        assertThat(actual.getReasonCodes()).isEmpty();
        assertThat(actual.getDiagnosisReferences()).isEmpty();
        assertThat(actual.getAppointmentReferences()).isEmpty();
        assertThat(actual.getSourceVersionId()).isNull();
        assertThat(actual.getSourceUpdatedAt()).isNull();
    }

    @Test
    void retainsMultipleParticipantRolesAndNormalizesOffsetTimes() throws Exception {
        final ObjectNode encounter = (ObjectNode) resource("bundle-one-encounter.json");
        final ObjectNode participant = (ObjectNode) encounter.path("participant").path(0);
        participant.withArray("type").add(json.readTree(
                "{\"coding\":[{\"system\":\"role-system\",\"code\":\"ATND\"}]}"));
        participant.putObject("period")
                .put("start", "2026-09-18T10:00:00-04:00")
                .put("end", "2026-09-18T11:00:00-04:00");

        final var actual = EhrEncounterMapper.map(
                encounter, PATIENT_ID, SOURCE_ID, RAW_PAYLOAD_ID, EXTERNAL_PATIENT_ID);

        assertThat(actual.getParticipants()).singleElement().satisfies(mapped -> {
            assertThat(mapped.types()).extracting(type -> type.code())
                    .containsExactly("PPRF", "ATND");
            assertThat(mapped.periodStart()).isEqualTo("2026-09-18T14:00:00Z");
            assertThat(mapped.periodEnd()).isEqualTo("2026-09-18T15:00:00Z");
        });
    }

    @Test
    void rejectsWrongPatientAndMissingRequiredClass() throws Exception {
        final ObjectNode encounter = (ObjectNode) resource("bundle-one-encounter.json");

        assertThatThrownBy(() -> EhrEncounterMapper.map(
                        encounter, PATIENT_ID, SOURCE_ID, RAW_PAYLOAD_ID, "another-patient"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Invalid canonical FHIR field: subject.reference");

        encounter.remove("class");
        assertThatThrownBy(() -> EhrEncounterMapper.map(
                        encounter, PATIENT_ID, SOURCE_ID, RAW_PAYLOAD_ID, EXTERNAL_PATIENT_ID))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Invalid canonical FHIR field: class");
    }

    private com.careconnect.model.ehr.EhrEncounterRecord map(final String file) throws Exception {
        return EhrEncounterMapper.map(
                resource(file), PATIENT_ID, SOURCE_ID, RAW_PAYLOAD_ID, EXTERNAL_PATIENT_ID);
    }

    private JsonNode resource(final String file) throws IOException {
        try (var input = getClass().getResourceAsStream("/cerner/fhir/encounter/" + file)) {
            return json.readTree(Objects.requireNonNull(input)).path("entry").path(0).path("resource");
        }
    }
}
