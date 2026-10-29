package com.careconnect.service.ehr;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import org.junit.jupiter.api.Test;

class CanonicalFhirMappingSupportTest {

    private final ObjectMapper json = new ObjectMapper();

    @Test
    void validatesResourceIdentityAndPatientReference() throws Exception {
        final JsonNode resource = json.readTree("""
                {"resourceType":"Condition","id":"condition-1",
                 "subject":{"reference":"Patient/patient-1"}}
                """);

        CanonicalFhirMappingSupport.requireResource(
                resource, "Condition", "patient-1");
        assertThatThrownBy(() -> CanonicalFhirMappingSupport.requireResource(
                resource, "Condition", "another-patient"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("subject.reference");
    }

    @Test
    void mapsConceptsReferencesAndSourceTimestamp() throws Exception {
        final JsonNode resource = json.readTree("""
                {"meta":{"lastUpdated":"2026-10-20T12:30:00-04:00"},
                 "code":{"coding":[{"system":"urn:test","code":"123",
                 "display":"Display"}],"text":"Text"},
                 "subject":{"reference":"Patient/patient-1","display":"Synthetic Patient"}}
                """);

        assertThat(CanonicalFhirMappingSupport.conceptCode(resource.path("code")))
                .isEqualTo("123");
        assertThat(CanonicalFhirMappingSupport.conceptLabel(resource.path("code")))
                .isEqualTo("Text");
        assertThat(CanonicalFhirMappingSupport.concepts(resource.path("code")))
                .singleElement().satisfies(value -> {
                    assertThat(value.system()).isEqualTo("urn:test");
                    assertThat(value.code()).isEqualTo("123");
                });
        assertThat(CanonicalFhirMappingSupport.reference(resource.path("subject")).reference())
                .isEqualTo("Patient/patient-1");
        assertThat(CanonicalFhirMappingSupport.sourceUpdatedAt(resource))
                .isEqualTo(Instant.parse("2026-10-20T16:30:00Z"));
    }

    @Test
    void preservesPartialDatePrecisionAndNormalizesDateTime() throws Exception {
        assertThat(CanonicalFhirMappingSupport.dateTime("onset", json.readTree("\"1985\"")))
                .extracting("value", "precision").containsExactly("1985", "YEAR");
        assertThat(CanonicalFhirMappingSupport.dateTime("onset", json.readTree("\"1985-03\"")))
                .extracting("value", "precision").containsExactly("1985-03", "MONTH");
        assertThat(CanonicalFhirMappingSupport.dateTime(
                "onset", json.readTree("\"2026-10-20T12:30:00-04:00\"")))
                .extracting("value", "precision")
                .containsExactly("2026-10-20T16:30:00Z", "INSTANT");
    }

    @Test
    void rejectsMalformedArrayAndTimestampShapes() throws Exception {
        assertThatThrownBy(() -> CanonicalFhirMappingSupport.array(
                json.readTree("{\"coding\":{}}"), "coding"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> CanonicalFhirMappingSupport.sourceUpdatedAt(
                json.readTree("{\"meta\":{\"lastUpdated\":\"not-a-date\"}}")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("meta.lastUpdated");
    }
}
