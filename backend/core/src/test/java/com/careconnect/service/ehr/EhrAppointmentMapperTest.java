package com.careconnect.service.ehr;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class EhrAppointmentMapperTest {

    private final ObjectMapper json = new ObjectMapper();

    @Test
    void mapsCanonicalFieldsAndNormalizesOffsetsToUtc() throws Exception {
        final Patient patient = new Patient();
        final EhrSource source = new EhrSource();
        final EhrRawPayload rawPayload = new EhrRawPayload();
        final var resource = json.readTree("""
                {"resourceType":"Appointment","id":"appointment-1","status":"booked",
                 "start":"2026-11-01T01:30:00-04:00",
                 "end":"2026-11-01T02:30:00-04:00",
                 "created":"2026-10-20T12:00:00Z",
                 "meta":{"lastUpdated":"2026-10-21T13:00:00Z"},
                 "serviceType":[{"coding":[{"display":"Primary Care"}]}],
                 "reasonCode":[{"text":"Follow-up"}],
                 "participant":[
                   {"actor":{"reference":"Practitioner/1","display":"Dr. Synthetic"}},
                   {"actor":{"reference":"Location/1","display":"Test Clinic"}}]}
                """);

        final var result = EhrAppointmentMapper.map(resource, patient, source, rawPayload);

        assertThat(result.getPatient()).isSameAs(patient);
        assertThat(result.getSource()).isSameAs(source);
        assertThat(result.getRawPayload()).isSameAs(rawPayload);
        assertThat(result.getExternalAppointmentId()).isEqualTo("appointment-1");
        assertThat(result.getStatus()).isEqualTo("booked");
        assertThat(result.getStartTime()).isEqualTo(LocalDateTime.parse("2026-11-01T05:30:00"));
        assertThat(result.getEndTime()).isEqualTo(LocalDateTime.parse("2026-11-01T06:30:00"));
        assertThat(result.getProviderName()).isEqualTo("Dr. Synthetic");
        assertThat(result.getLocation()).isEqualTo("Test Clinic");
        assertThat(result.getServiceType()).isEqualTo("Primary Care");
        assertThat(result.getReason()).isEqualTo("Follow-up");
    }

    @Test
    void retainsProposedAppointmentWithMissingOptionalTimes() throws Exception {
        final var resource = json.readTree(
                "{\"resourceType\":\"Appointment\",\"id\":\"proposed-1\","
                        + "\"status\":\"proposed\"}");

        final var result = EhrAppointmentMapper.map(
                resource, new Patient(), new EhrSource(), null);

        assertThat(result.getStatus()).isEqualTo("proposed");
        assertThat(result.getStartTime()).isNull();
        assertThat(result.getEndTime()).isNull();
    }

    @Test
    void rejectsAppointmentWithoutSourceIdentifier() throws Exception {
        final var resource = json.readTree("{\"resourceType\":\"Appointment\"}");

        assertThatThrownBy(() -> EhrAppointmentMapper.map(
                resource, new Patient(), new EhrSource(), null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("missing required field: id");
    }
}
