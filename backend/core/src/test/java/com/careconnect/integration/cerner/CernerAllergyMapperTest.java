package com.careconnect.integration.cerner;

import com.careconnect.integration.cerner.CernerAllergyMapper.Allergy;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class CernerAllergyMapperTest {

    private static final ObjectMapper JSON = new ObjectMapper();
    private static final String PATIENT = "12345";

    private static JsonNode bundle(String... resources) throws Exception {
        return JSON.readTree("{\"resourceType\":\"Bundle\",\"type\":\"searchset\",\"entry\":["
                + String.join(",", java.util.Arrays.stream(resources).map(r -> "{\"resource\":" + r + "}").toList())
                + "]}");
    }

    private static String allergy(String id, String patient, String extra) {
        return "{\"resourceType\":\"AllergyIntolerance\",\"id\":\"" + id + "\""
                + (patient == null ? "" : ",\"patient\":{\"reference\":\"Patient/" + patient + "\"}")
                + (extra.isEmpty() ? "" : "," + extra) + "}";
    }

    @Test
    @Tag("M3-REQ-04")
    @DisplayName("M3-SC-MAP-001: complete AllergyIntolerance maps every field")
    void completeResourceMapsAllFields() throws Exception {
        final String extra = "\"code\":{\"text\":\"Penicillin\",\"coding\":[{\"code\":\"7980\"}]},"
                + "\"clinicalStatus\":{\"coding\":[{\"code\":\"active\"}]},"
                + "\"verificationStatus\":{\"coding\":[{\"code\":\"confirmed\"}]},"
                + "\"recordedDate\":\"2024-03-01T10:00:00-05:00\","
                + "\"reaction\":[{\"severity\":\"severe\",\"manifestation\":[{\"text\":\"Hives\"},{\"text\":\"Wheezing\"}]}]";

        final List<Allergy> out = CernerAllergyMapper.map(bundle(allergy("a1", PATIENT, extra)), PATIENT);

        assertThat(out).containsExactly(new Allergy("CERNER", "a1", "Penicillin", "7980", "active",
                "confirmed", "severe", "2024-03-01T15:00:00Z", List.of("Hives", "Wheezing")));
    }

    @Test
    @Tag("M3-REQ-02")
    @DisplayName("M3-SC-MAP-003: partial dates keep precision and are not fabricated")
    void partialDatePreserved() {
        assertThat(CernerAllergyMapper.normalizeDate("2024-03")).isEqualTo("2024-03");
        assertThat(CernerAllergyMapper.normalizeDate("2024")).isEqualTo("2024");
        assertThat(CernerAllergyMapper.normalizeDate("not-a-date")).isNull();
        assertThat(CernerAllergyMapper.normalizeDate(null)).isNull();
    }

    @Test
    @Tag("M3-REQ-06")
    @DisplayName("M3-SC-MAP-004: no reaction maps to empty list with null optional fields")
    void noReactionYieldsEmptyList() throws Exception {
        final List<Allergy> out = CernerAllergyMapper.map(bundle(allergy("a2", PATIENT, "")), PATIENT);

        assertThat(out).hasSize(1);
        assertThat(out.get(0).reactions()).isEmpty();
        assertThat(out.get(0).severity()).isNull();
        assertThat(out.get(0).substanceCode()).isNull();
        assertThat(out.get(0).recordedDate()).isNull();
    }

    @Test
    @Tag("M3-REQ-06")
    @DisplayName("M3-SC-MAP-005: malformed entries are isolated; invalid bundle rejected")
    void malformedEntriesIsolated() throws Exception {
        final JsonNode b = bundle(
                allergy("", PATIENT, ""),
                allergy("a3", null, ""),
                allergy("a4", PATIENT, "\"recordedDate\":\"garbage\""),
                "{\"resourceType\":\"Observation\",\"id\":\"o1\"}",
                allergy("ok", PATIENT, ""));

        assertThat(CernerAllergyMapper.map(b, PATIENT)).extracting(Allergy::sourceRecordId).containsExactly("ok");
        assertThatThrownBy(() -> CernerAllergyMapper.map(JSON.readTree("{\"resourceType\":\"Patient\"}"), PATIENT))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> CernerAllergyMapper.map(null, PATIENT))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @Tag("M3-REQ-03")
    @DisplayName("M3-SC-MAP-006: different patient is rejected without leaking values")
    void otherPatientRejected() throws Exception {
        assertThatThrownBy(() -> CernerAllergyMapper.map(bundle(allergy("a5", "999", "")), PATIENT))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageNotContaining("999")
                .hasMessageNotContaining(PATIENT);
    }

    @Test
    @Tag("M3-REQ-04")
    @DisplayName("M3-SC-MAP-011: text without coding preserves text and leaves code null")
    void textWithoutCoding() throws Exception {
        final List<Allergy> out = CernerAllergyMapper.map(
                bundle(allergy("a6", PATIENT, "\"code\":{\"text\":\"Peanuts\"}")), PATIENT);

        assertThat(out.get(0).substanceText()).isEqualTo("Peanuts");
        assertThat(out.get(0).substanceCode()).isNull();
    }

    @Test
    @Tag("M3-REQ-04")
    @DisplayName("M3-SC-MAP-012: entered-in-error is excluded")
    void enteredInErrorExcluded() throws Exception {
        final String err = "\"verificationStatus\":{\"coding\":[{\"code\":\"entered-in-error\"}]}";

        assertThat(CernerAllergyMapper.map(bundle(allergy("e1", PATIENT, err), allergy("k1", PATIENT, "")), PATIENT))
                .extracting(Allergy::sourceRecordId).containsExactly("k1");
    }

    @Test
    @Tag("M3-REQ-04")
    @DisplayName("M3-SC-MAP-014: unknown severity maps to null without throwing")
    void unknownSeverityNull() throws Exception {
        final String extra = "\"reaction\":[{\"severity\":\"catastrophic\",\"manifestation\":[{\"text\":\"Rash\"}]}]";

        final List<Allergy> out = CernerAllergyMapper.map(bundle(allergy("s1", PATIENT, extra)), PATIENT);

        assertThat(out.get(0).severity()).isNull();
        assertThat(out.get(0).reactions()).containsExactly("Rash");
    }

    @Test
    @Tag("M3-REQ-04")
    @DisplayName("M3-SC-MAP-015: empty searchset Bundle yields empty list")
    void emptyBundle() throws Exception {
        assertThat(CernerAllergyMapper.map(bundle(), PATIENT)).isEmpty();
        assertThat(CernerAllergyMapper.map(
                JSON.readTree("{\"resourceType\":\"Bundle\",\"type\":\"searchset\"}"), PATIENT)).isEmpty();
    }

    @Test
    @Tag("M3-REQ-01")
    @DisplayName("M3-SC-MAP-008: repeat mapping is deterministic")
    void deterministic() throws Exception {
        final JsonNode b = bundle(allergy("d1", PATIENT, "\"code\":{\"text\":\"Latex\"}"));

        assertThat(CernerAllergyMapper.map(b, PATIENT)).isEqualTo(CernerAllergyMapper.map(b, PATIENT));
    }
}
