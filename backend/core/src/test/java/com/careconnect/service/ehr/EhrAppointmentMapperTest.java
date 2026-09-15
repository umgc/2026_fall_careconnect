package com.careconnect.service.ehr;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

/** Unit tests for the FHIR {@code Appointment} → {@link EhrAppointmentRecord} field mapping. */
class EhrAppointmentMapperTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    private final Patient patient = Patient.builder().id(1L).firstName("Jane").build();
    private final EhrSource source = EhrSource.builder().id(2L).code("ATHENAHEALTH").build();
    private final EhrRawPayload rawPayload = EhrRawPayload.builder().id(3L).build();

    @Test
    void mapsCoreFieldsFromAFullFhirAppointmentResource() throws Exception {
        final JsonNode resource = JSON.readTree("""
                {
                  "resourceType": "Appointment",
                  "id": "appt-1",
                  "status": "booked",
                  "start": "2026-09-20T10:00:00-04:00",
                  "end": "2026-09-20T10:30:00-04:00",
                  "created": "2026-09-01T00:00:00-04:00",
                  "meta": { "lastUpdated": "2026-09-10T08:30:00-04:00" },
                  "serviceType": [ { "coding": [ { "display": "Checkup" } ] } ],
                  "reasonCode": [ { "text": "Annual physical" } ],
                  "participant": [
                    { "actor": { "reference": "Practitioner/p1", "display": "Dr. Smith" } },
                    { "actor": { "reference": "Location/l1", "display": "Main Clinic" } },
                    { "actor": { "reference": "Patient/pt1", "display": "Jane Smith" } }
                  ]
                }
                """);

        final EhrAppointmentRecord mapped =
                EhrAppointmentMapper.map(resource, patient, source, rawPayload);

        assertThat(mapped.getPatient()).isSameAs(patient);
        assertThat(mapped.getSource()).isSameAs(source);
        assertThat(mapped.getRawPayload()).isSameAs(rawPayload);
        assertThat(mapped.getExternalAppointmentId()).isEqualTo("appt-1");
        assertThat(mapped.getStatus()).isEqualTo("booked");
        assertThat(mapped.getStartTime()).isEqualTo(LocalDateTime.of(2026, 9, 20, 10, 0));
        assertThat(mapped.getEndTime()).isEqualTo(LocalDateTime.of(2026, 9, 20, 10, 30));
        assertThat(mapped.getProviderName()).isEqualTo("Dr. Smith");
        assertThat(mapped.getLocation()).isEqualTo("Main Clinic");
        assertThat(mapped.getServiceType()).isEqualTo("Checkup");
        assertThat(mapped.getReason()).isEqualTo("Annual physical");
        assertThat(mapped.getSourceCreatedAt()).isEqualTo(LocalDateTime.of(2026, 9, 1, 0, 0));
        assertThat(mapped.getSourceUpdatedAt()).isEqualTo(LocalDateTime.of(2026, 9, 10, 8, 30));
    }

    @Test
    void tolerantOfMissingOptionalFields() throws Exception {
        final JsonNode resource = JSON.readTree("""
                {
                  "resourceType": "Appointment",
                  "id": "appt-2",
                  "status": "cancelled"
                }
                """);

        final EhrAppointmentRecord mapped =
                EhrAppointmentMapper.map(resource, patient, source, rawPayload);

        assertThat(mapped.getExternalAppointmentId()).isEqualTo("appt-2");
        assertThat(mapped.getStatus()).isEqualTo("cancelled");
        assertThat(mapped.getStartTime()).isNull();
        assertThat(mapped.getProviderName()).isNull();
        assertThat(mapped.getLocation()).isNull();
        assertThat(mapped.getServiceType()).isNull();
        assertThat(mapped.getReason()).isNull();
    }

    @Test
    void acceptsAWhateverStatusValueTheSourceReturns() throws Exception {
        // The draft flags athenahealth's status vocabulary as unverified — an unrecognized value must
        // not be rejected here, since status is a plain string column, not a Java enum.
        final JsonNode resource = JSON.readTree("""
                {"resourceType": "Appointment", "id": "appt-3", "status": "waitlist"}
                """);

        assertThat(EhrAppointmentMapper.map(resource, patient, source, rawPayload).getStatus())
                .isEqualTo("waitlist");
    }

    @Test
    void requiresAnIdBecauseItIsTheUpsertKey() throws Exception {
        final JsonNode resource = JSON.readTree("""
                {"resourceType": "Appointment", "status": "booked"}
                """);

        assertThatThrownBy(() -> EhrAppointmentMapper.map(resource, patient, source, rawPayload))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("id");
    }
}
