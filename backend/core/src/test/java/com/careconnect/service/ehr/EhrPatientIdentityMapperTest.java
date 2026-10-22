package com.careconnect.service.ehr;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.time.Instant;
import java.time.LocalDate;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

class EhrPatientIdentityMapperTest {

    private final ObjectMapper json = new ObjectMapper();

    @Test
    @Tag("M3-REQ-02")
    void completePatientMapsIntoSharedSourceIdentityWithoutInventingValues()
            throws Exception {
        final var actual = EhrPatientIdentityMapper.map(
                fixture("patient-complete.json"), 42L, 5L);

        assertThat(actual.getPatientId()).isEqualTo(42L);
        assertThat(actual.getSourceId()).isEqualTo(5L);
        assertThat(actual.getSourceUpdatedAt())
                .isEqualTo(Instant.parse("2026-10-01T12:00:00Z"));
        assertThat(actual.getGivenName()).isEqualTo("Synthetic");
        assertThat(actual.getFamilyName()).isEqualTo("Patient");
        assertThat(actual.getDateOfBirth()).isEqualTo(LocalDate.of(1980, 2, 29));
        assertThat(actual.getEmail()).isEqualTo("synthetic.patient@example.test");
        assertThat(actual.getPhone()).isNull();
        assertThat(actual.getAddressLine1()).isEqualTo("100 Test Way");
        assertThat(actual.getCity()).isEqualTo("Example City");
        assertThat(actual.getState()).isEqualTo("MD");
        assertThat(actual.getPostalCode()).isEqualTo("00000");
        assertThat(actual.getGender()).isEqualTo("unknown");
        assertThat(actual.getMemberId()).isEqualTo("synthetic-mrn-1");
        assertThat(actual.getLanguage()).isEqualTo("en");
        assertThat(actual.getManagingOrg()).isNull();
    }

    @Test
    @Tag("M3-REQ-06")
    void missingSourceTimestampIsRejectedUntilCanonicalReconciliationRuleIsApproved()
            throws Exception {
        assertThatThrownBy(() -> EhrPatientIdentityMapper.map(
                fixture("patient-missing-optional-fields.json"), 42L, 5L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("meta.lastUpdated");
    }

    private JsonNode fixture(final String name) throws IOException {
        try (var input = getClass().getResourceAsStream("/cerner/fhir/patient/" + name)) {
            assertThat(input).isNotNull();
            return json.readTree(input);
        }
    }
}
