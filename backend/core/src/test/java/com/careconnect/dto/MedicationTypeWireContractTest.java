package com.careconnect.dto;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.careconnect.model.Medication.MedicationType;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.exc.InvalidFormatException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.junit.jupiter.api.Test;
import org.springframework.http.converter.json.Jackson2ObjectMapperBuilder;

/**
 * Wire contract for MedicationDTO.medicationType, as seen by the Flutter client
 * (PR #153, KI-05). The frontend matches on enum constant names, so the backend
 * must emit and accept constant names, not display names.
 */
class MedicationTypeWireContractTest {

    // Same builder Spring Boot uses for its MVC ObjectMapper; no enum features are
    // customized in application.properties.
    private final ObjectMapper mapper = Jackson2ObjectMapperBuilder.json().build();

    @ParameterizedTest
    @EnumSource(MedicationType.class)
    @DisplayName("TC-MED-TYPE-011: every MedicationType serializes as its constant name, not its display name")
    void serializesConstantName(MedicationType type) throws Exception {
        String json = mapper.writeValueAsString(MedicationDTO.builder().medicationType(type).build());
        assertThat(json).contains("\"medicationType\":\"" + type.name() + "\"");
    }

    @ParameterizedTest
    @EnumSource(value = MedicationType.class, names = {"HERBAL", "EMERGENCY"})
    @DisplayName("TC-MED-TYPE-012: HERBAL and EMERGENCY as sent by the Flutter add form are accepted")
    void acceptsNewFrontendValues(MedicationType type) throws Exception {
        MedicationDTO dto = mapper.readValue(
                "{\"medicationName\":\"Synthetic\",\"medicationType\":\"" + type.name() + "\"}",
                MedicationDTO.class);
        assertThat(dto.medicationType()).isEqualTo(type);
    }

    @Test
    @DisplayName("TC-MED-TYPE-013: OTC as sent by the Flutter add form is rejected (known mismatch, out of PR #153 scope)")
    void rejectsFrontendOtc() {
        assertThatThrownBy(() -> mapper.readValue(
                "{\"medicationName\":\"Synthetic\",\"medicationType\":\"OTC\"}",
                MedicationDTO.class))
                .isInstanceOf(InvalidFormatException.class);
    }
}
